# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

module Agents
  class YandexGptAgent < Agent
    include WebRequestConcern
    include FormConfigurable

    default_schedule "every_1m"
    no_bulk_receive!

    description <<~MD
      YandexGPT Agent предоставляет интеграцию с языковыми моделями YandexGPT через Huginn.

      `folder_id`: Идентификатор каталога Yandex Cloud (обязательно)

      `api_key`: API-ключ для аутентификации (обязательно)

      `model_name`: Название модели (по умолчанию 'yandexgpt-lite')

      `model_version`: Версия модели ('latest', 'rc' или 'deprecated')

      `system_prompt`: Системный промпт (по умолчанию 'Выдели основные мысли из статьи.')

      `user_prompt`: Пользовательский промпт с поддержкой Liquid (обязательно)

      `temperature`: Креативность ответов (0-1, по умолчанию 0.1)

      `max_tokens`: Максимальное количество токенов (по умолчанию 2000)

      `json_output`: Возвращать ответ в формате JSON (true/false)

      `json_schema`: Схема JSON для структурированного ответа (опционально)

    MD

    event_description <<~MD
      События содержат оригинальный payload с добавленным ответом модели:
      ```json
      {
        "completion": {
          "text": "Ответ модели",
          "json": { ... },  # если включен json_output
          "usage": {
            "input_text_tokens": 10,
            "completion_tokens": 20,
            "total_tokens": 30
          },
          "model_version": "23.10.2024"
        }
      }
      ```
    MD

    form_configurable :folder_id, type: :string
    form_configurable :api_key, type: :string
    form_configurable :model_name, type: :string
    form_configurable :model_version, type: :string
    form_configurable :system_prompt, type: :text
    form_configurable :user_prompt, type: :text
    form_configurable :temperature, type: :number
    form_configurable :max_tokens, type: :number
    form_configurable :json_output, type: :boolean
    form_configurable :json_schema, type: :text, ace: { mode: 'json' }
    form_configurable :expected_receive_period_in_days, type: :number, html_options: { min: 1 }

    def default_options
      {
        'folder_id' => '',
        'api_key' => '',
        'model_name' => 'yandexgpt-lite',
        'model_version' => 'latest',
        'system_prompt' => 'Выдели основные мысли из статьи.',
        'user_prompt' => '{{message}}',
        'temperature' => 0.1,
        'max_tokens' => 2000,
        'json_output' => 'false',
        'expected_receive_period_in_days' => '2'
      }
    end

    def validate_options
      errors.add(:base, "folder_id обязателен") unless options['folder_id'].present?
      errors.add(:base, "api_key обязателен") unless options['api_key'].present?
      errors.add(:base, "user_prompt обязателен") unless options['user_prompt'].present?

      if options['temperature'].present?
        temp = options['temperature'].to_f
        errors.add(:base, "temperature должен быть между 0 и 1") unless temp.between?(0, 1)
      end

      if options['max_tokens'].present?
        errors.add(:base, "max_tokens должен быть положительным числом") unless options['max_tokens'].to_i > 0
      end

      if options['json_schema'].present?
        begin
          JSON.parse(options['json_schema'])
        rescue JSON::ParserError => e
          errors.add(:base, "json_schema должен быть валидным JSON: #{e.message}")
        end
      end
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        handle_event(event)
      end
    end

    def check
      check_pending_operations
    end

    private

    def handle_event(event)
      interpolate_with(event) do
        response = send_completion_request(
          system_prompt: interpolated['system_prompt'],
          user_prompt: interpolated['user_prompt'],
          temperature: interpolated['temperature'].to_f,
          max_tokens: interpolated['max_tokens'].to_i
        )

        if response && response['id']
          save_operation(response['id'], event.id)
          log "Запрос к YandexGPT: #{response.inspect}"
        else
          error "Не удалось получить operation ID от YandexGPT"
        end
      end
    rescue => e
      error "Ошибка обработки события: #{e.message}"
    end

    def check_pending_operations
      memory['pending_operations'] ||= {}
      return if memory['pending_operations'].empty?

      events = fetch_events(memory['pending_operations'].values.map { |op| op['event_id'] })

      memory['pending_operations'].each do |operation_id, operation_data|
        next unless events.key?(operation_data['event_id'])

        response = check_operation_status(operation_id)
        handle_operation_response(response, operation_id, events[operation_data['event_id']]) if response
      end

      cleanup_old_operations
    end

    def send_completion_request(system_prompt:, user_prompt:, temperature:, max_tokens:)
      request_body = {
        modelUri: model_uri,
        completionOptions: {
          stream: false,
          temperature: temperature,
          maxTokens: max_tokens.to_s
        },
        messages: [
          { role: 'system', text: system_prompt },
          { role: 'user', text: user_prompt }
        ]
      }

      # Добавляем параметры для структурированного вывода
      if boolify(interpolated['json_output'])
        if interpolated['json_schema'].present?
          begin
            request_body[:json_schema] = { schema: JSON.parse(interpolated['json_schema']) }
          rescue JSON::ParserError => e
            error "Ошибка парсинга json_schema: #{e.message}"
          end
        else
          request_body[:json_object] = true
        end
      end

      response = faraday.post(
        "https://llm.api.cloud.yandex.net/foundationModels/v1/completionAsync",
        request_body.to_json,
        {
          'Content-Type' => 'application/json',
          'Authorization' => "Api-Key #{interpolated['api_key']}",
          'x-folder-id' => interpolated['folder_id']
        }
      )

      response.success? ? JSON.parse(response.body) : nil
    end

    def check_operation_status(operation_id)
      response = faraday.get(
        "https://operation.api.cloud.yandex.net/operations/#{operation_id}",
        nil,
        { 'Authorization' => "Api-Key #{interpolated['api_key']}" }
      )

      response.success? ? JSON.parse(response.body) : nil
    end

    def model_uri
      "gpt://#{interpolated['folder_id']}/#{interpolated['model_name']}/#{interpolated['model_version']}"
    end

    def save_operation(operation_id, event_id)
      memory['pending_operations'] ||= {}
      memory['pending_operations'][operation_id] = {
        'event_id' => event_id,
        'created_at' => Time.now.utc.iso8601
      }
    end

    def fetch_events(event_ids)
      received_events.where(id: event_ids).index_by(&:id)
    end

    def handle_operation_response(response, operation_id, event)
      if response['done']
        if response['response']
          create_completion_event(event.payload, response['response'])
          log "Операция #{operation_id} завершена успешно"
        elsif response['error']
          error "Ошибка операции #{operation_id}: #{response['error']['message']}"
        end
        memory['pending_operations'].delete(operation_id)
      end
    end

    def create_completion_event(original_payload, gpt_response)
      text = gpt_response.dig('alternatives', 0, 'message', 'text')
      usage = gpt_response['usage']

      completion_data = {
        'text' => text,
        'usage' => {
          'input_text_tokens' => usage['inputTextTokens'],
          'completion_tokens' => usage['completionTokens'],
          'total_tokens' => usage['totalTokens']
        },
        'model_version' => gpt_response['modelVersion']
      }

      # Добавляем JSON ответ если он есть
      if boolify(interpolated['json_output']) && text
        begin
          json_response = JSON.parse(text.gsub('\\n', ''))
          completion_data['json'] = json_response
        rescue JSON::ParserError
          log "Не удалось распарсить JSON ответ от модели"
        end
      end

      create_event payload: original_payload.merge('completion' => completion_data)
    end

    def cleanup_old_operations
      memory['pending_operations'].delete_if do |_, data|
        Time.parse(data['created_at']) < 1.day.ago
      end
    end
  end
end
