#!/usr/bin/env bash

set -e

echo "Starting server (npm run dev) and Flutter client (flutter run)..."
echo "Make sure you have already run dependencies installation once:"
echo "  cd server && npm install"
echo "  cd client && flutter pub get"
echo

# Run server
(cd server && npm run dev) &
SERVER_PID=$!

# Run client (API_BASE_URL указывает на локальный сервер)
(cd client && flutter run -d chrome --dart-define API_BASE_URL=http://localhost:3000) &
CLIENT_PID=$!

trap "echo; echo 'Stopping server and client...'; kill $SERVER_PID $CLIENT_PID 2>/dev/null || true" INT TERM EXIT

wait

