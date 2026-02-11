# Тестирование

Проект использует Jest для unit и integration тестов.

## Запуск тестов

```bash
# Все тесты
npm test

# В режиме watch
npm run test:watch

# С покрытием кода
npm run test:coverage
```

## Структура тестов

Тесты находятся в директории `__tests__/`:

- `auth.test.js` - тесты аутентификации
- `messages.test.js` - тесты сообщений
- `validation.test.js` - тесты валидации

## Написание тестов

### Пример unit теста

```javascript
import { validate, registerSchema } from '../middleware/validation.js';

describe('registerSchema', () => {
  it('должен валидировать корректные данные', () => {
    const validData = {
      username: 'testuser',
      password: 'password123',
    };
    
    const { error } = registerSchema.validate(validData);
    expect(error).toBeUndefined();
  });
});
```

### Пример integration теста

```javascript
import request from 'supertest';
import app from '../index.js';

describe('POST /auth/register', () => {
  it('должен зарегистрировать нового пользователя', async () => {
    const response = await request(app)
      .post('/auth/register')
      .send({
        username: 'testuser',
        password: 'password123',
      })
      .expect(201);

    expect(response.body).toHaveProperty('token');
  });
});
```

## Тестовая база данных

Тесты используют отдельную тестовую БД (`test.db`), которая создаётся и удаляется автоматически.

## Покрытие кода

Целевое покрытие: **80%+**

Проверить текущее покрытие:
```bash
npm run test:coverage
```

Отчёт будет доступен в `coverage/lcov-report/index.html`.

## Best Practices

1. **Изоляция тестов**: Каждый тест должен быть независимым
2. **Очистка данных**: Используйте `beforeAll` и `afterAll` для настройки и очистки
3. **Моки**: Используйте моки для внешних зависимостей (Redis, FCM)
4. **Асинхронность**: Всегда используйте `async/await` для асинхронных операций
5. **Описательные имена**: Используйте понятные названия для тестов

## CI/CD

Тесты автоматически запускаются в GitHub Actions при каждом push и pull request.
