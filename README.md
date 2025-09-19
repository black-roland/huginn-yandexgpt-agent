# Huginn Yandex Foundation Models Agents

Набор агентов для интеграции сервисов искусственного интеллекта Yandex Cloud Foundation Models с Huginn.

## Агенты

### YandexGPT Agent

Агент для работы с языковыми моделями YandexGPT. Позволяет использовать мощь языковых моделей YandexGPT для обработки текста в ваших автоматизированных сценариях.

**Ключевые возможности:**
- Асинхронная работа с YandexGPT API
- Поддержка всех моделей YandexGPT (**YandexGPT-Lite**, **YandexGPT-Pro**)
- Гибкая настройка промптов через Liquid-шаблоны
- Контроль креативности (параметр температуры 0-1)
- Ограничение длины ответа (максимальное число токенов)
- Поддержка JSON вывода (структурированные данные)
- Автоматическая проверка статуса операций

### YandexGPT Semantic Search Agent

Универсальный агент для семантического поиска и классификации с использованием эмбеддингов Yandex Foundation Models. Поддерживает различные сценарии: от автотеггинга до семантического поиска по базе знаний.

**Ключевые возможности:**
- Семантический поиск по произвольным документам-кандидатам
- Гибкое извлечение результатов через Liquid-шаблоны
- Поддержка моделей эмбеддингов (`text-search-doc`, `text-search-query`)
- Кэширование эмбеддингов для документов-кандидатов
- Настраиваемый порог сходства (0-1) и лимит результатов

## Установка

Добавьте в файл `.env` вашего Huginn:

```bash
ADDITIONAL_GEMS="huginn_yandex_gpt_agent(github: black-roland/huginn-yandexgpt-agent)"
```

Затем выполните:

```bash
bundle
```

## Настройка агентов

### YandexGPT Agent

**Обязательные параметры:**
- `folder_id` - ID каталога Yandex Cloud
- `api_key` - API-ключ для аутентификации
- `model_name` - Название модели (`yandexgpt-lite`, `yandexgpt`)
- `system_prompt` - Системный промпт (определяет поведение модели)
- `user_prompt` - Пользовательский запрос (поддерживает Liquid-шаблоны)

**Основные настройки:**
- `temperature` (0-1) - Управление креативностью ответов
- `max_tokens` - Максимальное количество токенов в ответе
- `model_version` - Версия модели (`latest`, `rc`, `deprecated`)

**Structured Output:**
- `json_output` - Включить вывод в формате JSON
- `json_schema` - Схема для структурированного ответа (опционально)

### YandexGPT Semantic Search Agent

**Обязательные параметры:**
- `folder_id` - ID каталога Yandex Cloud
- `api_key` - API-ключ для аутентификации
- `candidate_documents` - Массив документов-кандидатов для поиска
- `query_text` - Текст запроса (поддерживает Liquid-шаблоны)

**Основные настройки:**
- `result_extraction_pattern` - Liquid шаблон для извлечения результатов
- `min_similarity` (0-1) - Минимальное значение косинусного сходства
- `max_results` - Максимальное количество возвращаемых результатов
- `model_uri` - URI модели эмбеддингов (`text-search-doc`, `text-search-query`)

## Примеры использования

### YandexGPT Agent - базовый сценарий:
```yaml
system_prompt: "Ты - помощник, который анализирует тексты"
user_prompt: "Выдели ключевые темы из текста: {{text}}"
temperature: 0.3
max_tokens: 500
```

### Yandex Foundation Semantic Search Agent - автотеггинг:

```yaml
candidate_documents: [
  "ai artificial intelligence and machine learning",
  "radio ham radio and wireless technologies",
  "iot internet of things, connected devices and home automation",
  "comms communication systems, telephony, APRS, Meshtastic"
]
query_text: "{{ title }} {{ description }}"
result_extraction_pattern: "{{ document | split: ' ' | first }}"
min_similarity: 0.5
max_results: 3
model_uri: "text-search-query"
```

### Yandex Foundation Semantic Search Agent - семантический поиск:

```yaml
candidate_documents: [
  "Александр Сергеевич Пушкин (26 мая [6 июня] 1799, Москва — 29 января [10 февраля] 1837, Санкт-Петербург) — русский поэт, драматург и прозаик, заложивший основы русского реалистического направления, литературный критик и теоретик литературы, историк, публицист, журналист.",
  "Ромашка — род однолетних цветковых растений семейства астровые, или сложноцветные, по современной классификации объединяет около 70 видов невысоких пахучих трав, цветущих с первого года жизни."
]
query_text: "когда день рождения Пушкина?"
result_extraction_pattern: "{{ document | split: ',' | first }}"
min_similarity: 0.6
max_results: 1
model_uri: "text-search-query"
```

## Формат выходных данных

### YandexGPT Agent:

```json
{
  "completion": {
    "text": "Ответ модели",
    "json": {
      "field1": "value1",
      "field2": ["array", "values"]
    },
    "usage": {
      "input_text_tokens": 150,
      "completion_tokens": 200,
      "total_tokens": 350
    },
    "model_version": "23.10.2024"
  }
}
```

### Yandex Foundation Semantic Search Agent:

```json
{
  "semantic_search": {
    "results": ["ai", "science"],
    "matches": [
      {
        "document": "ai artificial intelligence and machine learning",
        "similarity": 0.85,
        "result": "ai"
      },
      {
        "document": "science scientific research and discoveries",
        "similarity": 0.78,
        "result": "science"
      }
    ]
  }
}
```

## Преимущества использования

1. **Универсальность**: Один агент для множества задач семантического поиска
2. **Экономичность**: Эмбеддинги значительно дешевле полных LLM-запросов
3. **Гибкость**: Произвольные документы-кандидаты и шаблоны извлечения
4. **Стабильность**: Детерминированные результаты на основе векторной математики
5. **Прозрачность**: Подробная информация о сходстве и совпадениях

## Типичные сценарии использования

- **Автотеггинг закладок и контента**
- **Семантическая категоризация новостей**
- **Поиск похожего контента и дубликатов**
- **Извлечение структурированной информации из текста**

## Уведомление

Данный агент является неофициальным и не связан с Yandex Cloud. Yandex Foundation Models — это сервис, предоставляемый Yandex Cloud.

Данный агент не является официальным продуктом Яндекса и не поддерживается Яндексом. Разработчик агента не несёт ответственности за:
- Изменения в API Yandex Cloud;
- Прекращение работы сервиса Yandex Foundation Models;
- Любые возможные неполадки или убытки, вызванные использованием данного агента.
