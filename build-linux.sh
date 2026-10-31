#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "==> Очистка dist/..."
rm -rf dist && mkdir -p dist

echo "==> Шаг 1/5: Сборка фронтенда..."
npm --prefix mediatracker-ui run build

echo "==> Шаг 2/5: Публикация Tsundoku (linux-x64, NativeAOT, headless)..."
# PublishAot включён в csproj; сборка требует clang/llvm и zlib-dev (см. README).
dotnet publish MediaTracker.Server -c Release -r linux-x64 -o dist/server_build

echo "==> Шаг 3/5: Копирование сервера в каталог sidecar Tauri..."
# Имя файла обязано содержать Rust target triple хоста — так его ищет tauri.
# Рядом нужен libe_sqlite3.so: AOT-бинарник грузит его как соседний файл,
# tauri.linux.conf.json кладёт его в бандл как ресурс resource_dir/libe_sqlite3.so.
TRIPLE="$(rustc -vV | sed -n 's|host: ||p')"
TRIPLE="${TRIPLE:-x86_64-unknown-linux-gnu}"
mkdir -p src-tauri/binaries
cp dist/server_build/Tsundoku "src-tauri/binaries/tsundoku-server-${TRIPLE}" 2>/dev/null \
  || cp dist/server_build/Tsundoku.Server "src-tauri/binaries/tsundoku-server-${TRIPLE}"
chmod +x "src-tauri/binaries/tsundoku-server-${TRIPLE}"
cp dist/server_build/libe_sqlite3.so src-tauri/binaries/libe_sqlite3.so
chmod +x src-tauri/binaries/libe_sqlite3.so
echo "    sidecar: src-tauri/binaries/tsundoku-server-${TRIPLE}"

# Проверка стейджинга: бандлер не предупредит, если артефакты не готовы.
if [ ! -x "src-tauri/binaries/tsundoku-server-${TRIPLE}" ]; then
  echo "ОШИБКА: sidecar src-tauri/binaries/tsundoku-server-${TRIPLE} отсутствует или не исполняем" >&2
  exit 1
fi
if [ ! -x src-tauri/binaries/libe_sqlite3.so ]; then
  echo "ОШИБКА: src-tauri/binaries/libe_sqlite3.so отсутствует или не исполняем" >&2
  exit 1
fi
if [ ! -f MediaTracker.Server/wwwroot/index.html ]; then
  echo "ОШИБКА: MediaTracker.Server/wwwroot/index.html не найден — фронтенд не собран?" >&2
  exit 1
fi

echo "==> Шаг 4/5: Сборка нативного десктоп-приложения (Tauri v2: deb / AppImage)..."
npm run tauri build

echo "==> Шаг 5/5: Сборка чистых артефактов в dist/..."

# 1. AppImage монолит (бандлер AppImage может отсутствовать — тогда пропускаем).
cp src-tauri/target/release/bundle/appimage/*.AppImage dist/Tsundoku.AppImage 2>/dev/null || true
chmod +x dist/Tsundoku.AppImage 2>/dev/null || true

# Проверка упаковки wwwroot в ресурсы AppImage (resource_dir/usr/lib/Tsundoku).
if [ -x dist/Tsundoku.AppImage ]; then
  rm -rf .appimage-verify && mkdir .appimage-verify && (cd .appimage-verify && \
    ../dist/Tsundoku.AppImage --appimage-extract "usr/lib/Tsundoku/wwwroot/index.html" > /dev/null 2>&1)
  if [ -f .appimage-verify/squashfs-root/usr/lib/Tsundoku/wwwroot/index.html ]; then
    echo "    проверка AppImage: wwwroot упакован в ресурсы"
  else
    echo "ПРЕДУПРЕЖДЕНИЕ: wwwroot не найден внутри AppImage!" >&2
  fi
  rm -rf .appimage-verify
fi

# 2. Автономная портативная папка: GUI-шелл + bin/ с сервером и SQLite +
#    wwwroot рядом с бинарником (его находит сервер через AppContext.BaseDirectory
#    относительно --contentRoot, который шелл передаёт при запуске).
mkdir -p dist/Tsundoku-Portable/bin
cp src-tauri/target/release/tsundoku dist/Tsundoku-Portable/Tsundoku
chmod +x dist/Tsundoku-Portable/Tsundoku
cp dist/server_build/Tsundoku dist/Tsundoku-Portable/bin/tsundoku-server 2>/dev/null \
  || cp dist/server_build/Tsundoku.Server dist/Tsundoku-Portable/bin/tsundoku-server
chmod +x dist/Tsundoku-Portable/bin/tsundoku-server
cp dist/server_build/libe_sqlite3.so dist/Tsundoku-Portable/bin/libe_sqlite3.so
chmod +x dist/Tsundoku-Portable/bin/libe_sqlite3.so
cp -r MediaTracker.Server/wwwroot dist/Tsundoku-Portable/wwwroot

# 3. Системные пакеты, если бандлер их собрал.
mkdir -p dist/packages
cp src-tauri/target/release/bundle/deb/*.deb dist/packages/ 2>/dev/null || true
cp src-tauri/target/release/bundle/rpm/*.rpm dist/packages/ 2>/dev/null || true

# 4. Временная папка публикации больше не нужна.
rm -rf dist/server_build

echo "==> Сборка завершена успешно!"
echo "    1. AppImage монолит: dist/Tsundoku.AppImage"
echo "    2. Портативная папка: dist/Tsundoku-Portable/Tsundoku"
echo "    3. Сервер для systemd: dist/Tsundoku-Portable/bin/tsundoku-server"
