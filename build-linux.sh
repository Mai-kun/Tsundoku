#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "==> Очистка dist/..."
rm -rf dist && mkdir -p dist dist/.server_build

# 1. Быстрый линковщик для Rust: mold > lld > системный ld.
#    RUSTFLAGS полностью перекрывает rustflags из src-tauri/.cargo/config.toml,
#    поэтому в ветке fallback "-C linker=..." нейтрализует отсутствующий mold.
if command -v mold >/dev/null 2>&1 && command -v clang >/dev/null 2>&1; then
  echo "==> [Rust] Обнаружен mold, активируем быстрый линковщик..."
  export RUSTFLAGS="${RUSTFLAGS:-} -C linker=clang -C link-arg=-fuse-ld=mold"
elif command -v lld >/dev/null 2>&1 && command -v clang >/dev/null 2>&1; then
  echo "==> [Rust] mold не найден, используем lld..."
  export RUSTFLAGS="${RUSTFLAGS:-} -C linker=clang -C link-arg=-fuse-ld=lld"
else
  echo "==> [Rust] Ни mold, ни lld не найдены — используем системный линковщик."
  export RUSTFLAGS="${RUSTFLAGS:-} -C linker=cc"
fi

echo "==> Шаг 1/4: Параллельная сборка фронтенда и NativeAOT бэкенда..."
# PublishAot включён в csproj; сборка требует clang/llvm и zlib-dev (см. README).
(
  npm --prefix mediatracker-ui run build
) &
PID_FRONT=$!

(
  # ExcludeWwwrootFromPublish: vite (running in parallel) rewrites wwwroot with
  # new content-hashed names while this publish would copy the stale snapshot
  # it took at startup -> MSB3030. Nothing consumes the publish-output wwwroot
  # (Tauri and the portable folder take it from the source folder), so drop it.
  dotnet publish MediaTracker.Server -c Release -r linux-x64 -o dist/.server_build -p:ExcludeWwwrootFromPublish=true
) &
PID_BACK=$!

wait $PID_FRONT || { echo "ОШИБКА: Сборка фронтенда завершилась сбоем" >&2; exit 1; }
wait $PID_BACK || { echo "ОШИБКА: Публикация .NET NativeAOT завершилась сбоем" >&2; exit 1; }

echo "==> Шаг 2/4: Подготовка sidecar бинарников..."
# Имя файла обязано содержать Rust target triple хоста — так его ищет tauri.
# Рядом нужен libe_sqlite3.so: AOT-бинарник грузит его как соседний файл,
# tauri.linux.conf.json кладёт его в бандл как ресурс resource_dir/libe_sqlite3.so.
TRIPLE="$(rustc -vV | sed -n 's|host: ||p')"
TRIPLE="${TRIPLE:-x86_64-unknown-linux-gnu}"
mkdir -p src-tauri/binaries
cp dist/.server_build/Tsundoku "src-tauri/binaries/tsundoku-server-${TRIPLE}" 2>/dev/null \
  || cp dist/.server_build/Tsundoku.Server "src-tauri/binaries/tsundoku-server-${TRIPLE}"
chmod +x "src-tauri/binaries/tsundoku-server-${TRIPLE}"
cp dist/.server_build/libe_sqlite3.so src-tauri/binaries/libe_sqlite3.so
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

echo "==> Шаг 3/4: Сборка нативного десктоп-приложения (Tauri v2: deb / AppImage)..."
# beforeBuildCommand отключаем оверрайдом: фронтенд уже собран на шаге 1,
# повторный запуск vite через tauri не нужен. --bundles ограничивает
# генерацию пакетов appimage+deb (без rpm и прочих таргетов "all").
npx tauri build --bundles appimage,deb --config '{"build":{"beforeBuildCommand":""}}'

echo "==> Шаг 4/4: Формирование чистых артефактов в dist/..."

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
cp dist/.server_build/Tsundoku dist/Tsundoku-Portable/bin/tsundoku-server 2>/dev/null \
  || cp dist/.server_build/Tsundoku.Server dist/Tsundoku-Portable/bin/tsundoku-server
chmod +x dist/Tsundoku-Portable/bin/tsundoku-server
cp dist/.server_build/libe_sqlite3.so dist/Tsundoku-Portable/bin/libe_sqlite3.so
chmod +x dist/Tsundoku-Portable/bin/libe_sqlite3.so
cp -r MediaTracker.Server/wwwroot dist/Tsundoku-Portable/wwwroot

# 3. Системные пакеты, если бандлер их собрал.
mkdir -p dist/packages
cp src-tauri/target/release/bundle/deb/*.deb dist/packages/ 2>/dev/null || true

# 4. Временные артефакты больше не нужны. Чистим и то, что могло просочиться
#    в корень dist/ мимо `-o` (старый безусловный PublishDir в csproj).
rm -rf dist/.server_build
rm -rf dist/Tsundoku.Server dist/Tsundoku.Server.dbg dist/libe_sqlite3.so dist/wwwroot

# 5. Контроль чистоты: в корне dist/ допустимы только финальные артефакты.
stray="$(find dist -mindepth 1 -maxdepth 1 ! -name 'Tsundoku.AppImage' ! -name 'packages' ! -name 'Tsundoku-Portable')"
if [ -n "$stray" ]; then
  echo "ПРЕДУПРЕЖДЕНИЕ: посторонние файлы в корне dist/:" >&2
  echo "$stray" >&2
fi

echo "==> Сборка завершена успешно!"
echo "    1. AppImage монолит: dist/Tsundoku.AppImage"
echo "    2. Портативная папка: dist/Tsundoku-Portable/Tsundoku"
echo "    3. Сервер для systemd: dist/Tsundoku-Portable/bin/tsundoku-server"
