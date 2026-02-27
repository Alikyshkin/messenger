 # Multi-stage build для оптимизации размера образа

# Stage 1: Build
FROM node:20 AS builder

WORKDIR /app

# Устанавливаем инструменты для сборки нативных модулей (better-sqlite3)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

# Копируем package.json и устанавливаем зависимости
COPY server/package*.json ./server/
WORKDIR /app/server
# Собираем better-sqlite3 из исходников под архитектуру контейнера
RUN npm ci --only=production --build-from-source=better-sqlite3

# Stage 2: Production
FROM node:20

WORKDIR /app

# Устанавливаем необходимые системные пакеты
RUN apt-get update && apt-get install -y --no-install-recommends \
    sqlite3 \
    ca-certificates \
    bash && \
    rm -rf /var/lib/apt/lists/*

# Копируем зависимости из builder
COPY --from=builder /app/server/node_modules ./server/node_modules

# Копируем код сервера
COPY server/ ./server/

# Создаём директории для данных
RUN mkdir -p /app/data /app/server/uploads /app/server/public

# Устанавливаем переменные окружения по умолчанию
ENV NODE_ENV=production
ENV PORT=3000
ENV MESSENGER_DB_PATH=/app/data/messenger.db

# Открываем порт
EXPOSE 3000

# Запускаем сервер
WORKDIR /app/server
CMD ["node", "index.js"]
