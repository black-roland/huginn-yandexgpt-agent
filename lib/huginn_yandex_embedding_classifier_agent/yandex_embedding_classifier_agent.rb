# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

module Agents
  class YandexEmbeddingClassifierAgent < Agent
    include WebRequestConcern

    can_dry_run!
    no_bulk_receive!
    cannot_be_scheduled!

    description <<~MD
      Yandex Embedding Classifier Agent использует эмбеддинги YandexGPT для классификации текста.

      ### Основные параметры
      `api_key`: API-ключ для Yandex Cloud API (обязательно)<br>
      `folder_id`: Идентификатор каталога Yandex Cloud (обязательно)<br>
      `label_candidates`: Список меток-кандидатов, из которых будет производиться выбор (обязательно)<br>
      `text`: Текст для классификации с поддержкой Liquid (обязательно)<br>
      `min_similarity`: Минимальное значение косинусного сходства (0-1, по умолчанию 0.7)<br>
      `model_uri`: URI модели для эмбеддингов<br>

      ### Принцип работы
      Агент вычисляет эмбеддинги для каждой метки-кандидата и входящего текста, затем находит наиболее подходящие метки на основе косинусного сходства.
      Метки, чье сходство превышает `min_similarity`, добавляются в выходное событие.

      ### Пример использования
      `label_candidates`: ["ai", "programming", "news", "science"]
      Текст: "Новое исследование в области искусственного интеллекта"
      Результат: `classification.labels` = ["ai", "science"] (если сходство > min_similarity)
    MD

    event_description <<~MD
      События содержат оригинальный payload с добавленным объектом classification:
      ```json
      {
        "classification": {
          "labels": ["label1", "label2"],
          "similarities": {
            "label1": 0.85,
            "label2": 0.78
          }
        }
      }
      ```
    MD

    def default_options
      {
        'api_key' => '',
        'folder_id' => '',
        'label_candidates' => [],
        'text' => '{{title}} {{description}}',
        'min_similarity' => '0.7',
        'model_uri' => 'text-search-query',
        'expected_receive_period_in_days' => '2'
      }
    end

    def validate_options
      errors.add(:base, "api_key обязателен") unless options['api_key'].present?
      errors.add(:base, "folder_id обязателен") unless options['folder_id'].present?
      errors.add(:base, "label_candidates обязателен") unless options['label_candidates'].present?
      errors.add(:base, "text обязателен") unless options['text'].present?

      if options['min_similarity'].present?
        min_sim = options['min_similarity'].to_f
        errors.add(:base, "min_similarity должен быть между 0 и 1") unless min_sim.between?(0, 1)
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

    private

    def handle_event(event)
      interpolate_with(event) do
        label_embeddings = get_label_embeddings

        text_to_classify = interpolated['text']
        if text_to_classify.blank?
          log "Текст для классификации пустой, пропускаем событие"
          return
        end

        text_embedding = get_text_embedding(text_to_classify)
        unless text_embedding
          error "Не удалось получить эмбеддинг для текста"
          return
        end

        similarities = calculate_similarities(text_embedding, label_embeddings)

        log "Вычисленные similarities: #{similarities.inspect}"

        selected_labels = select_labels(similarities)

        create_event payload: event.payload.merge(
          'classification' => {
            'labels' => selected_labels.keys,
            'similarities' => similarities
          }
        )
      end
    rescue => e
      error "Ошибка обработки события: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
    end

    def get_label_embeddings
      # Используем memory как кэш для эмбеддингов меток-кандидатов
      memory['label_embeddings'] ||= {}
      labels = interpolated['label_candidates']

      # Вычисляем эмбеддинги для отсутствующих меток-кандидатов
      labels_to_process = labels.reject { |label| memory['label_embeddings'][label].present? }

      if labels_to_process.any?
        log "Вычисляем эмбеддинги для #{labels_to_process.size} меток-кандидатов"

        labels_to_process.each do |label|
          embedding = get_embedding(label)
          if embedding
            memory['label_embeddings'][label] = embedding
          else
            error "Не удалось получить эмбеддинг для метки-кандидата: #{label}"
          end
        end
      end

      memory['label_embeddings']
    end

    def get_text_embedding(text)
      get_embedding(text)
    end

    def get_embedding(text)
      response = send_embedding_request(text)

      unless response&.success?
        error "Ошибка API: #{response&.body || 'Нет ответа'}"
        return nil
      end

      response_data = JSON.parse(response.body)

      if response_data['embeddings'] && response_data['embeddings'][0]
        response_data['embeddings'][0]['embedding']
      else
        error "Неверный формат ответа от API: #{response_data.inspect}"
        nil
      end
    rescue JSON::ParserError => e
      error "Ошибка парсинга JSON: #{e.message}\nResponse body: #{response&.body}"
      nil
    end

    def send_embedding_request(text)
      model_uri = if interpolated['model_uri'].include?('://')
        interpolated['model_uri']
      else
        "emb://#{interpolated['folder_id']}/#{interpolated['model_uri']}/latest"
      end

      request_body = {
        modelUri: model_uri,
        text: text
      }

      faraday.post(
        "https://llm.api.cloud.yandex.net/foundationModels/v1/textEmbedding",
        request_body.to_json,
        {
          'Content-Type' => 'application/json',
          'Authorization' => "Api-Key #{interpolated['api_key']}",
          'x-folder-id' => interpolated['folder_id'],
          'x-data-logging-enabled': 'false' # Отключаем логирование запросов
        }
      )
    end

    def calculate_similarities(text_embedding, label_embeddings)
      similarities = {}

      label_embeddings.each do |label, label_embedding|
        next unless label_embedding.is_a?(Array) && text_embedding.is_a?(Array)

        similarity = cosine_similarity(text_embedding, label_embedding)
        similarities[label] = similarity
      end

      similarities
    end

    def cosine_similarity(vec_a, vec_b)
      return 0 unless vec_a.is_a?(Array) && vec_b.is_a?(Array)
      return 0 if vec_a.empty? || vec_b.empty?
      return 0 if vec_a.size != vec_b.size

      dot_product = 0
      norm_a = 0
      norm_b = 0

      vec_a.each_with_index do |a, i|
        b = vec_b[i]
        dot_product += a * b
        norm_a += a * a
        norm_b += b * b
      end

      norm_a = Math.sqrt(norm_a)
      norm_b = Math.sqrt(norm_b)

      return 0 if norm_a.zero? || norm_b.zero?

      dot_product / (norm_a * norm_b)
    end

    def select_labels(similarities)
      min_similarity = interpolated['min_similarity'].to_f

      # Сортируем по убыванию сходства и выбираем превосходящие порог
      sorted_similarities = similarities.sort_by { |_, similarity| -similarity }
      selected = sorted_similarities.select { |_, similarity| similarity >= min_similarity }

      log "Выбрано #{selected.size} метк(и/а) из #{similarities.size} с сходством >= #{min_similarity}"

      selected.to_h
    end

    def faraday
      @faraday ||= Faraday.new do |builder|
        builder.request :json
        builder.response :json, content_type: /\bjson$/
        builder.response :raise_error
        builder.adapter Faraday.default_adapter
      end
    end
  end
end
