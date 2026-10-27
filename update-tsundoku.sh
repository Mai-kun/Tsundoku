#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.local/share/Tsundoku"
BACKUP_DIR="$DATA_DIR/backups"

echo "==> 1. Создание страховочного бэкапа базы данных..."
mkdir -p "$BACKUP_DIR"
if [ -f "$DATA_DIR/tracker.db" ]; then
    cp "$DATA_DIR/tracker.db" "$BACKUP_DIR/tracker_$(date +%Y%m%d_%H%M%S).db"
    # Оставляем только последние 10 автобэкапов
    ls -1t "$BACKUP_DIR"/tracker_*.db 2>/dev/null | tail -n +11 | xargs -r rm --
    echo "    Бэкап сохранён в $BACKUP_DIR"
fi

echo "==> 2. Сборка свежей версии Tsundoku..."
cd "$REPO_DIR"
# Если используешь git и хочешь стягивать с GitHub, раскомментируй:
# git pull --ff-only
./build-linux.sh

echo "==> 3. Перезапуск пользовательского сервиса..."
if systemctl --user is-active --quiet tsundoku.service; then
    systemctl --user restart tsundoku.service
    echo "==> Готово! Сервис Tsundoku обновлён и перезапущен."
else
    echo "==> Сборка завершена! Запусти: systemctl --user start tsundoku.service"
fi
