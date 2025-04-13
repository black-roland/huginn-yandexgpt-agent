# Huginn YandexGPT Agent

Агент для интеграции YandexGPT с Huginn. Позволяет использовать мощь языковых моделей YandexGPT для обработки текста в ваших автоматизированных сценариях.

## Ключевые возможности

- Асинхронная работа с YandexGPT API
- Поддержка всех моделей YandexGPT (**YandexGPT-Lite**, **YandexGPT-Pro**)
- Гибкая настройка промптов через Liquid-шаблоны
- Контроль креативности (параметр температуры 0-1)
- Ограничение длины ответа (максимальное число токенов)
- Поддержка JSON вывода (структурированные данные)
- Автоматическая проверка статуса операций

## Установка

Добавьте в файл `.env` вашего Huginn:

```bash
ADDITIONAL_GEMS="huginn_yandex_gpt_agent(github: black-roland/huginn-yandexgpt-agent)"
```

Затем выполните:

```bash
bundle
```

## Настройка агента

### Обязательные параметры:
- `folder_id` - ID каталога Yandex Cloud
- `api_key` - API-ключ для аутентификации
- `model_name` - Название модели (`yandexgpt-lite`, `yandexgpt`)
- `system_prompt` - Системный промпт (определяет поведение модели)
- `user_prompt` - Пользовательский запрос (поддерживает Liquid-шаблоны)

### Основные настройки:
- `temperature` (0-1) - Управление креативностью ответов
- `max_tokens` - Максимальное количество токенов в ответе
- `model_version` - Версия модели (`latest`, `rc`, `deprecated`)

### Structured Output:
- `json_output` - Включить вывод в формате JSON
- `json_schema` - Схема для структурированного ответа (опционально)

## Примеры использования

### Базовый сценарий:
```yaml
system_prompt: "Ты - помощник, который анализирует тексты"
user_prompt: "Выдели ключевые темы из текста: {{text}}"
temperature: 0.3
max_tokens: 500
```

## Формат выходных данных

События содержат оригинальный payload с добавленным ответом модели:

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
