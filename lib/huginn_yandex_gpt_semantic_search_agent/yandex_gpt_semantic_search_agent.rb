# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

module Agents
  class YandexGptSemanticSearchAgent < Agent
    include WebRequestConcern

    can_dry_run!
    no_bulk_receive!
    cannot_be_scheduled!

    description <<~MD
      YandexGPT Semantic Search Agent использует эмбеддинги Yandex Foundation Models для семантического поиска по документам-кандидатам.

      ### Основные параметры
      `api_key`: API-ключ для Yandex Cloud API (обязательно)<br>
      `folder_id`: Идентификатор каталога Yandex Cloud (обязательно)<br>
      `candidate_documents`: Массив документов-кандидатов для поиска (обязательно)<br>
      `query_text`: Текст запроса для поиска с поддержкой Liquid (обязательно)<br>
      `result_extraction_pattern`: Liquid шаблон для извлечения результата из найденного документа<br>
      `min_similarity`: Минимальное значение косинусного сходства (0-1, по умолчанию 0.7)<br>
      `max_results`: Максимальное количество возвращаемых результатов (по умолчанию 5)<br>
      `model_uri`: URI модели для эмбеддингов<br>

      ### Принцип работы
      Агент вычисляет эмбеддинги для каждого документа-кандидата и текста запроса, затем находит наиболее подходящие документы на основе косинусного сходства.
      Для каждого найденного документа применяется шаблон `result_extraction_pattern` для извлечения конечного результата.

      ### Пример использования для классификации
      `candidate_documents`: `["ai artificial intelligence", "radio wireless communication", "iot internet of things and connected devices"]`<br>
      `query_text`: `"{{ title }} {{ description }}"`<br>
      `result_extraction_pattern`: `"{{ document | split: ' ' | first }}"`<br>
      <br>
      Запрос: "Новое исследование в области искусственного интеллекта"<br>
      Результат: `semantic_search.results` = ["ai"] (если сходство > min_similarity)

      ### Важно
      В dry run отсутствует кэширование, поэтому для всех документов эмбеддинги вычисляются каждый раз.
    MD

    event_description <<~MD
      События содержат оригинальный payload с добавленным объектом semantic_search:
      ```json
      {
        "semantic_search": {
          "results": ["result1", "result2"],
          "matches": [
            {
              "document": "original document text",
              "similarity": 0.85,
              "result": "extracted result"
            }
          ]
        }
      }
      ```
    MD

    def default_options
      {
        'api_key' => '',
        'folder_id' => '',
        'candidate_documents' => [
          "ai artificial intelligence and machine learning",
          "radio wireless communication technology",
          "iot internet of things and connected devices"
        ],
        'query_text' => '{{ title }} {{ description }}',
        'result_extraction_pattern' => '{{ document | split: " " | first }}',
        'min_similarity' => '0.7',
        'max_results' => '5',
        'model_uri' => 'text-search-doc',
        'expected_receive_period_in_days' => '2'
      }
    end

    def validate_options
      errors.add(:base, "api_key обязателен") unless options['api_key'].present?
      errors.add(:base, "folder_id обязателен") unless options['folder_id'].present?
      errors.add(:base, "candidate_documents обязателен") unless options['candidate_documents'].present?
      errors.add(:base, "query_text обязателен") unless options['query_text'].present?

      if options['min_similarity'].present?
        min_sim = options['min_similarity'].to_f
        errors.add(:base, "min_similarity должен быть между 0 и 1") unless min_sim.between?(0, 1)
      end

      if options['max_results'].present?
        max_res = options['max_results'].to_i
        errors.add(:base, "max_results должен быть положительным числом") unless max_res > 0
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
        document_embeddings = get_document_embeddings

        query_text = interpolated['query_text']
        if query_text.blank?
          log "Текст запроса пустой, пропускаем событие"
          return
        end

        query_embedding = get_embedding(query_text)
        unless query_embedding
          error "Не удалось получить эмбеддинг для запроса"
          return
        end

        similarities = calculate_similarities(query_embedding, document_embeddings)

        log "Вычисленные similarities: #{similarities.inspect}"

        selected_documents = select_documents(similarities)

        results = extract_results(selected_documents, event)

        create_event payload: event.payload.merge(
          'semantic_search' => {
            'results' => results.map { |r| r[:result] }.uniq,
            'matches' => results
          }
        )
      end
    rescue => e
      error "Ошибка обработки события: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
    end

    def get_document_embeddings
      # Используем memory как кэш для эмбеддингов документов
      memory['document_embeddings'] ||= {}
      documents = interpolated['candidate_documents']

      # Вычисляем эмбеддинги для отсутствующих документов
      documents_to_process = documents.reject { |doc| memory['document_embeddings'][doc].present? }

      if documents_to_process.any?
        log "Вычисляем эмбеддинги для #{documents_to_process.size} документов-кандидатов"

        # Обрабатываем документы группами с задержкой
        documents_to_process.each_slice(10).with_index do |batch, batch_index|
          # Добавляем задержку между группами запросов (1 секунда)
          sleep(1) if batch_index > 0

          batch.each do |document|
            embedding = get_embedding(document)
            if embedding
              memory['document_embeddings'][document] = embedding
            else
              error "Не удалось получить эмбеддинг для документа: #{document}"
            end
          end
        end
      end

      memory['document_embeddings']
    end

    def get_embedding(text)
      response = send_embedding_request(text)

      unless response&.success?
        error "Ошибка API: #{response&.body || 'Нет ответа'}"
        return nil
      end

      response_data = JSON.parse(response.body)

      if response_data['embedding']
        response_data['embedding']
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
          'x-data-logging-enabled': 'false'
        }
      )
    end

    def calculate_similarities(query_embedding, document_embeddings)
      similarities = {}

      document_embeddings.each do |document, doc_embedding|
        next unless doc_embedding.is_a?(Array) && query_embedding.is_a?(Array)

        similarity = cosine_similarity(query_embedding, doc_embedding)
        similarities[document] = similarity
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

    def select_documents(similarities)
      min_similarity = interpolated['min_similarity'].to_f
      max_results = interpolated['max_results'].to_i

      # Сортируем по убыванию сходства, выбираем превосходящие порог и ограничиваем количество
      sorted_similarities = similarities.sort_by { |_, similarity| -similarity }
      selected = sorted_similarities.select { |_, similarity| similarity >= min_similarity }
      limited = selected.first(max_results)

      log "Выбрано #{limited.size} документ(ов) из #{similarities.size} с сходством >= #{min_similarity}"

      limited.to_h
    end

    def extract_results(selected_documents, event)
      pattern = interpolated['result_extraction_pattern']
      results = []

      selected_documents.each do |document, similarity|
        interpolation_payload = event.payload.merge(
          'document' => document,
          'similarity' => similarity
        )

        result = interpolate_string(pattern, interpolation_payload)

        results << {
          'document' => document,
          'similarity' => similarity,
          'result' => result.strip
        }
      end

      results
    end
  end
end
