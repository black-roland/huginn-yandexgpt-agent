# Huginn YandexGPT Agents

Набор агентов для интеграции сервисов искусственного интеллекта Yandex Cloud с Huginn.

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

### Yandex Embedding Classifier Agent

Агент для семантической классификации текста с использованием эмбеддингов YandexGPT. Идеален для автотеггинга и категоризации контента.

**Ключевые возможности:**
- Семантическая классификация на основе векторных представлений
- Поддержка моделей эмбеддингов (`text-search-doc`, `text-search-query`)
- Кэширование эмбеддингов для меток-кандидатов
- Настраиваемый порог сходства (0-1)

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

### Yandex Embedding Classifier Agent

**Обязательные параметры:**
- `folder_id` - ID каталога Yandex Cloud
- `api_key` - API-ключ для аутентификации
- `label_candidates` - Массив меток-кандидатов для классификации
- `text` - Текст для классификации (поддерживает Liquid-шаблоны)

**Основные настройки:**
- `min_similarity` (0-1) - Минимальное значение косинусного сходства
- `model_uri` - URI модели эмбеддингов (`text-search-doc`, `text-search-query`)

## Примеры использования

### YandexGPT Agent - базовый сценарий:
```yaml
system_prompt: "Ты - помощник, который анализирует тексты"
user_prompt: "Выдели ключевые темы из текста: {{text}}"
temperature: 0.3
max_tokens: 500
```

### Yandex Embedding Classifier Agent - автотеггинг:
```yaml
label_candidates: ["ai", "programming", "news", "science", "technology", "business"]
text: "{{title}} {{description}}"
min_similarity: 0.7
model_uri: "text-search-doc"
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

### Yandex Embedding Classifier Agent:
```json
{
  "classification": {
    "labels": ["ai", "science"],
    "similarities": {
      "ai": 0.85,
      "science": 0.78,
      "programming": 0.45,
      "news": 0.32
    },
    "debug": {
      "text_embedding_size": 256,
      "labels_processed": 6,
      "min_similarity": 0.7
    }
  }
}
```

## Преимущества использования

1. **Экономичность**: Эмбеддинги значительно дешевле полных LLM-запросов
2. **Скорость**: Быстрая семантическая классификация без генерации текста
3. **Стабильность**: Детерминированные результаты на основе векторной математики
4. **Гибкость**: Легкая настройка меток-кандидатов и порогов сходства

## Типичные сценарии использования

- **Автотеггинг закладок и контента**
- **Семантическая категоризация новостей**
- **Поиск дубликатов и похожего контента**
- **Интеллектуальная маршрутизация событий**
