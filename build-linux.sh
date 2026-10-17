#!/usr/bin/env bash
set -e
echo "==> Сборка фронтенда..."
cd mediatracker-ui && npm run build && cd ..

echo "==> Публикация Tsundoku (linux-x64)..."
dotnet publish MediaTracker.Server -c Release -r linux-x64 --self-contained -o dist/linux-x64
chmod +x dist/linux-x64/Tsundoku
echo "==> Готово! Бинарник: dist/linux-x64/Tsundoku"
