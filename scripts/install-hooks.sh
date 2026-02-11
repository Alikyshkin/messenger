#!/bin/bash

# Скрипт для установки git hooks
# Запустите: ./scripts/install-hooks.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "📦 Установка git hooks..."

# Копируем pre-commit hook
if [ -f "$REPO_ROOT/.git/hooks/pre-commit" ]; then
    echo "⚠️  Pre-commit hook уже существует. Перезаписываем..."
fi

cp "$SCRIPT_DIR/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

echo "✅ Pre-commit hook установлен!"
echo ""
echo "Теперь при каждом коммите будет автоматически проверяться:"
echo "  - Форматирование кода (flutter format)"
echo "  - Анализ кода (flutter analyze)"
echo "  - Компиляция для Web (flutter build web)"
echo ""
echo "Чтобы пропустить проверку (не рекомендуется):"
echo "  git commit --no-verify -m 'сообщение'"
