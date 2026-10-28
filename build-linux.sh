#!/usr/bin/env bash
set -e
echo "==> Сборка фронтенда..."
cd mediatracker-ui && npm run build && cd ..

echo "==> Публикация Tsundoku (linux-x64, NativeAOT)..."
# PublishAot включён в csproj; сборка требует clang/llvm и zlib-dev (см. README).
dotnet publish MediaTracker.Server -c Release -r linux-x64 -o dist/linux-x64
chmod +x dist/linux-x64/Tsundoku
echo "==> Готово! Нативный бинарник: dist/linux-x64/Tsundoku"
