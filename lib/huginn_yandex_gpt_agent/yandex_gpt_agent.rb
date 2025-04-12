# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

module Agents
  class YandexGptAgent < Agent
    include WebRequestConcern

    default_schedule "every_1m"
    no_bulk_receive!

    description <<~MD
      YandexGPT Agent отправляет асинхронные запросы к YandexGPT и проверяет статус операций.

      При получении новых events:
      1. Отправляет асинхронный запрос к YandexGPT
      2. Сохраняет operation ID и event ID в memory

      При выполнении по расписанию:
      1. Проверяет статус сохраненных операций
      2. Создает events с результатами завершенных операций

      Настройки:
      - `folder_id`: Идентификатор каталога Yandex Cloud
      - `api_key`: API-ключ для аутентификации
      - `model_name`: Название модели (например, "yandexgpt-lite")
      - `model_version`: Версия модели ("latest", "rc" или "deprecated")
      - `system_prompt`: Системный промпт (по умолчанию "Выдели основные мысли из статьи.")
      - `user_prompt`: Пользовательский промпт (может использовать Liquid)
      - `temperature`: Параметр температуры (по умолчанию 0.1)
      - `max_tokens`: Максимальное количество токенов (по умолчанию 2000)
    MD

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
        'expected_receive_period_in_days' => 1
      }
    end

    def validate_options
      errors.add(:base, "folder_id is required") unless options['folder_id'].present?
      errors.add(:base, "api_key is required") unless options['api_key'].present?
      errors.add(:base, "model_name is required") unless options['model_name'].present?
      errors.add(:base, "system_prompt is required") unless options['system_prompt'].present?
      errors.add(:base, "user_prompt is required") unless options['user_prompt'].present?

      if options['temperature'].present?
        temp = options['temperature'].to_f
        errors.add(:base, "temperature must be between 0 and 1") unless temp.between?(0, 1)
      end

      if options['max_tokens'].present?
        errors.add(:base, "max_tokens must be a positive number") unless options['max_tokens'].to_i > 0
      end
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          response = send_completion_request(
            system_prompt: interpolated['system_prompt'],
            user_prompt: interpolated['user_prompt'],
            temperature: interpolated['temperature'].to_f,
            max_tokens: interpolated['max_tokens'].to_i
          )

          if response && response['id']
            memory['pending_operations'] ||= {}
            memory['pending_operations'][response['id']] = {
              'event_id' => event.id,
              'created_at' => Time.now.utc.iso8601
            }
            log "Saved operation #{response['id']} for event #{event.id}"
          else
            error "Failed to get operation ID from YandexGPT response"
          end
        end
      end
    end

    def check
      memory['pending_operations'] ||= {}
      return if memory['pending_operations'].empty?

      # Получаем все event_ids из memory
      event_ids = memory['pending_operations'].values.map { |op| op['event_id'] }

      # Находим все события одним запросом
      events_by_id = received_events.where(id: event_ids).index_by(&:id)

      memory['pending_operations'].each do |operation_id, operation_data|
        next unless events_by_id.key?(operation_data['event_id'])

        response = check_operation_status(operation_id)

        if response && response['done']
          if response['response']
            event = events_by_id[operation_data['event_id']]
            create_event_with_result(event.payload, response['response'])
            memory['pending_operations'].delete(operation_id)
            log "Operation #{operation_id} completed for event #{event.id}"
          elsif response['error']
            error "Operation #{operation_id} failed: #{response['error']['message']}"
            memory['pending_operations'].delete(operation_id)
          end
        end
      end

      # Удаляем старые операции (старше 1 дня)
      memory['pending_operations'].delete_if do |_, data|
        Time.parse(data['created_at']) < 1.day.ago
      end
    end

    private

    def model_uri
      "gpt://#{interpolated['folder_id']}/#{interpolated['model_name']}/#{interpolated['model_version']}"
    end

    def send_completion_request(system_prompt:, user_prompt:, temperature:, max_tokens:)
      url = "https://llm.api.cloud.yandex.net/foundationModels/v1/completionAsync"

      headers = {
        'Content-Type' => 'application/json',
        'Authorization' => "Api-Key #{interpolated['api_key']}",
        'x-folder-id' => interpolated['folder_id']
      }

      body = {
        modelUri: model_uri,
        completionOptions: {
          stream: false,
          temperature: temperature,
          maxTokens: max_tokens.to_s
        },
        messages: [
          {
            role: 'system',
            text: system_prompt
          },
          {
            role: 'user',
            text: user_prompt
          }
        ]
      }.to_json

      response = faraday.post(url, body, headers)

      if response.success?
        JSON.parse(response.body)
      else
        error "YandexGPT request failed: #{response.status} - #{response.body}"
        nil
      end
    rescue => e
      error "Error sending request to YandexGPT: #{e.message}"
      nil
    end

    def check_operation_status(operation_id)
      url = "https://operation.api.cloud.yandex.net/operations/#{operation_id}"

      headers = {
        'Authorization' => "Api-Key #{interpolated['api_key']}"
      }

      response = faraday.get(url, nil, headers)

      if response.success?
        JSON.parse(response.body)
      else
        error "Failed to check operation status: #{response.status} - #{response.body}"
        nil
      end
    rescue => e
      error "Error checking operation status: #{e.message}"
      nil
    end

    def create_event_with_result(original_payload, gpt_response)
      text = gpt_response['alternatives']&.first&.dig('message', 'text')

      result = {
        'text' => text,
        'usage' => {
          'input_text_tokens' => gpt_response.dig('usage', 'inputTextTokens'),
          'completion_tokens' => gpt_response.dig('usage', 'completionTokens'),
          'total_tokens' => gpt_response.dig('usage', 'totalTokens')
        },
        'model_version' => gpt_response['modelVersion']
      }

      create_event payload: original_payload.merge('completion' => result)
    end
  end
end
