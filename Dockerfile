# syntax=docker/dockerfile:1.4
# Multi-stage build для оптимизации размера образа

# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Копируем package.json и устанавливаем зависимости с кэшированием
COPY server/package*.json ./server/
RUN --mount=type=cache,target=/root/.npm \
    cd server && npm ci --only=production

# Stage 2: Production
FROM node:20-alpine

WORKDIR /app

# Устанавливаем необходимые системные пакеты
RUN apk add --no-cache \
    sqlite \
    bash

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
