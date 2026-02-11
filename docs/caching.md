# Кэширование с Redis

Проект использует Redis для кэширования данных и улучшения производительности.

## Настройка

### Переменные окружения

Добавьте в `.env`:

```env
REDIS_URL=redis://localhost:6379
REDIS_SESSION_TTL=86400      # TTL для сессий (24 часа)
REDIS_USER_TTL=3600           # TTL для данных пользователей (1 час)
REDIS_CONTACTS_TTL=1800       # TTL для списка контактов (30 минут)
REDIS_CHATS_TTL=1800          # TTL для списка чатов (30 минут)
```

### Запуск Redis

#### Docker

```bash
docker run -d --name redis -p 6379:6379 redis:alpine
```

#### Docker Compose

Добавьте в `docker-compose.yml`:

```yaml
services:
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data

volumes:
  redis-data:
```

## Что кэшируется

### Данные пользователей
- Профиль пользователя (`/users/me`, `/users/:id`)
- TTL: 1 час

### Контакты
- Список контактов пользователя (`/contacts`)
- TTL: 30 минут
- Инвалидируется при добавлении/удалении контакта

### Чаты
- Список чатов пользователя (`/chats`)
- TTL: 30 минут

## Использование в коде

### Базовые операции

```javascript
import { get, set, del, CacheKeys } from './utils/cache.js';
import config from './config/index.js';

// Получить значение
const user = await get(CacheKeys.user(userId));

// Сохранить значение
await set(CacheKeys.user(userId), userData, config.redis.ttl.user);

// Удалить значение
await del(CacheKeys.user(userId));
```

### Доступные функции

- `get(key)` - получить значение
- `set(key, value, ttlSeconds)` - сохранить значение
- `del(key)` - удалить значение
- `delPattern(pattern)` - удалить все ключи по паттерну
- `exists(key)` - проверить существование ключа
- `expire(key, seconds)` - установить TTL
- `mget(...keys)` - получить несколько значений
- `mset(keyValuePairs, ttlSeconds)` - сохранить несколько значений
- `incr(key)` - инкремент значения
- `decr(key)` - декремент значения

### Ключи кэша

Используйте `CacheKeys` для генерации ключей:

```javascript
CacheKeys.user(userId)              // user:123
CacheKeys.userContacts(userId)      // user:123:contacts
CacheKeys.userChats(userId)        // user:123:chats
CacheKeys.message(messageId)       // message:456
CacheKeys.group(groupId)            // group:789
CacheKeys.groupMembers(groupId)     // group:789:members
CacheKeys.session(token)            // session:token123
CacheKeys.onlineUsers()             // online:users
```

## Fallback поведение

Если Redis недоступен или не настроен:
- Кэширование автоматически отключается
- Все запросы идут напрямую в базу данных
- Приложение продолжает работать без кэширования
- В логах появляются предупреждения

## Инвалидация кэша

Кэш автоматически инвалидируется при:
- Обновлении профиля пользователя
- Добавлении/удалении контакта
- Изменении данных группы

Для ручной инвалидации:

```javascript
import { del, CacheKeys } from './utils/cache.js';

// Удалить кэш пользователя
await del(CacheKeys.user(userId));

// Удалить кэш контактов
await del(CacheKeys.userContacts(userId));
```

## Мониторинг

Проверьте статус Redis в логах приложения:

```bash
# Успешное подключение
[INFO] Redis подключен

# Ошибка подключения
[WARN] Redis URL не указан, кэширование отключено
[ERROR] Не удалось подключиться к Redis
```

## Production рекомендации

1. **Безопасность**:
   - Используйте пароль для Redis: `REDIS_URL=redis://:password@host:6379`
   - Ограничьте доступ к Redis только из приложения
   - Используйте SSL/TLS для удалённых подключений

2. **Производительность**:
   - Настройте maxmemory и политику eviction
   - Используйте персистентность (RDB или AOF) для важных данных
   - Мониторьте использование памяти

3. **Высокая доступность**:
   - Используйте Redis Sentinel для отказоустойчивости
   - Или Redis Cluster для горизонтального масштабирования

4. **Мониторинг**:
   - Используйте Redis INFO для метрик
   - Интегрируйте с Prometheus через redis_exporter

## Troubleshooting

### Кэш не работает

1. Проверьте подключение к Redis:
```bash
redis-cli ping
# Должно вернуть: PONG
```

2. Проверьте переменные окружения:
```bash
echo $REDIS_URL
```

3. Проверьте логи приложения на наличие ошибок Redis

### Старые данные в кэше

Инвалидируйте кэш вручную:
```bash
redis-cli FLUSHDB
```

Или удалите конкретные ключи:
```bash
redis-cli DEL "user:123"
```
