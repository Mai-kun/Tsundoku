#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  if [ -d "$HOME/development/flutter/bin" ]; then
    export PATH="$HOME/development/flutter/bin:$PATH"
  fi
fi

echo "==> Очистка dist/..."
rm -rf dist && mkdir -p dist

# 1. Фронтенд: компиляция Flutter Web Canvas (WASM) и копирование в MediaTracker.Server/wwwroot
echo "==> Шаг 1/5: Сборка Flutter Web Canvas (WASM)..."
rm -rf MediaTracker.Server/wwwroot
mkdir -p MediaTracker.Server/wwwroot
(cd tsundoku-flutter && flutter build web --wasm)
cp -r tsundoku-flutter/build/web/* MediaTracker.Server/wwwroot/

if [ ! -f MediaTracker.Server/wwwroot/index.html ]; then
  echo "ОШИБКА: MediaTracker.Server/wwwroot/index.html не найден — Web-билд не собрался?" >&2
  exit 1
fi

# 2. Нативный Flutter Linux Desktop UI: сборка Release бандла в dist/Tsundoku-Portable/ui
echo "==> Шаг 2/5: Сборка нативного Flutter Desktop (Linux Release)..."
(cd tsundoku-flutter && flutter build linux --release)
mkdir -p dist/Tsundoku-Portable/ui
cp -r tsundoku-flutter/build/linux/x64/release/bundle/* dist/Tsundoku-Portable/ui/
chmod +x dist/Tsundoku-Portable/ui/tsundoku_flutter

if [ ! -f dist/Tsundoku-Portable/ui/tsundoku_flutter ]; then
  echo "ОШИБКА: dist/Tsundoku-Portable/ui/tsundoku_flutter не найден — Desktop UI не собрался?" >&2
  exit 1
fi

# 3. Актуальная OpenAPI-схема: генерация идёт на обычной (не-AOT) Release-сборке —
#    процесс строит хост в памяти с временной папкой данных и закрывается сразу после
#    выгрузки файла: сервер, браузер, трей, воркеры и миграции реальной БД не запускаются.
echo "==> Шаг 3/5: Экспорт openapi.json..."
dotnet build MediaTracker.Server/MediaTracker.Server.csproj -c Release --nologo -v q
dotnet MediaTracker.Server/bin/Release/net10.0/Tsundoku.dll --export-openapi dist/Tsundoku-Portable/openapi.json

# 4. Монолитный NativeAOT-бинарник: Kestrel + трей + лаунчер в одном Tsundoku.
#    Требует clang/llvm и zlib-dev (см. README). PublishAot включен в csproj.
echo "==> Шаг 4/5: Публикация NativeAOT (dotnet)..."
dotnet publish MediaTracker.Server -c Release -r linux-x64 -o dist/Tsundoku-Portable
chmod +x dist/Tsundoku-Portable/Tsundoku

# Нативные библиотеки (.so кодеков и sqlite) не должны мусорить в корне портативной папки:
# складываем их в lib/. Бинарник ищет их там через зашитый на линковке RUNPATH $ORIGIN/lib
# (см. LinkerArg в csproj), поэтому patchelf после сборки не нужен.
mkdir -p dist/Tsundoku-Portable/lib
mv dist/Tsundoku-Portable/*.so* dist/Tsundoku-Portable/lib/ 2>/dev/null || true

# Убедимся, что wwwroot присутствует в портативной папке
if [ ! -f dist/Tsundoku-Portable/wwwroot/index.html ]; then
  cp -r MediaTracker.Server/wwwroot dist/Tsundoku-Portable/
fi

# Автономный установщик едет рядом с бинарником: распаковал архив — запустил установку.
cp install-linux.sh uninstall-linux.sh dist/Tsundoku-Portable/
chmod +x dist/Tsundoku-Portable/install-linux.sh dist/Tsundoku-Portable/uninstall-linux.sh

# 5. Ярлык портативной папки и монолитный AppImage
echo "==> Шаг 5/5: Упаковка AppImage..."
cat > dist/Tsundoku-Portable/Tsundoku.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Tsundoku
Comment=Персональный трекер медиатеки
Exec=/opt/tsundoku/Tsundoku
Icon=/opt/tsundoku/wwwroot/icons/default.png
Categories=Office;Viewer;
Terminal=false
StartupWMClass=tsundoku_flutter
DESKTOP

# Монолитный автономный AppImage: bin/ + wwwroot/ + ui/ рядом с AppRun.
APPDIR="$ROOT/dist/Tsundoku.AppDir"
APPIMAGE_OUT="$ROOT/dist/Tsundoku.AppImage"
mkdir -p "$APPDIR/bin"
cp dist/Tsundoku-Portable/Tsundoku "$APPDIR/bin/Tsundoku"
chmod +x "$APPDIR/bin/Tsundoku"

cp dist/Tsundoku-Portable/lib/*.so* "$APPDIR/bin/" 2>/dev/null || true
chmod +x "$APPDIR/bin/"*.so* 2>/dev/null || true
cp -r dist/Tsundoku-Portable/wwwroot "$APPDIR/wwwroot"

# Включаем изолированную папку UI внутрь AppDir
mkdir -p "$APPDIR/ui"
cp -r dist/Tsundoku-Portable/ui/* "$APPDIR/ui/"
chmod +x "$APPDIR/ui/tsundoku_flutter"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/bin:${LD_LIBRARY_PATH}"
export MALLOC_ARENA_MAX=2
export MALLOC_TRIM_THRESHOLD_=131072
export DOTNET_CONTENTROOT="${HERE}"
export ASPNETCORE_CONTENTROOT="${HERE}"
exec "${HERE}/bin/Tsundoku" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/tsundoku.desktop" <<DESKTOP
[Desktop Entry]
Name=Tsundoku
Exec=AppRun
Icon=tsundoku
Type=Application
Categories=Utility;
StartupWMClass=tsundoku_flutter
DESKTOP

ICON_SRC="tsundoku-flutter/web/icons/default.png"
[ -f "$ICON_SRC" ] || ICON_SRC="tsundoku-flutter/web/icons/Icon-512.png"
[ -f "$ICON_SRC" ] || ICON_SRC="mediatracker-ui/public/icons/default.png"
[ -f "$ICON_SRC" ] || ICON_SRC="mediatracker-ui/public/icon-512.png"
cp "$ICON_SRC" "$APPDIR/tsundoku.png"
ln -sf tsundoku.png "$APPDIR/.DirIcon"

mkdir -p "$APPDIR/usr/share/metainfo" "$APPDIR/usr/share/applications"
cat > "$APPDIR/usr/share/metainfo/io.github.Maikun.Tsundoku.appdata.xml" <<'APPDATA'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.github.Maikun.Tsundoku</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MIT</project_license>
  <name>Tsundoku</name>
  <summary>Personal media library tracker</summary>
  <description>
    <p>
      Tsundoku (MediaTracker) is a personal tracker for anime, manga, books,
      movies, TV shows and games with external metadata aggregation.
    </p>
  </description>
  <launchable type="desktop-id">tsundoku.desktop</launchable>
  <url type="homepage">https://github.com/Mai-kun/Tsundoku</url>
  <developer id="io.github.maikun">
    <name>Mai-kun</name>
  </developer>
  <content_rating type="oars-1.1"/>
  <releases>
    <release version="1.0.0" date="2026-11-05"/>
  </releases>
</component>
APPDATA

cp "$APPDIR/tsundoku.desktop" "$APPDIR/usr/share/applications/tsundoku.desktop"

if command -v appstreamcli >/dev/null 2>&1; then
  appstreamcli validate "$APPDIR/usr/share/metainfo/io.github.Maikun.Tsundoku.appdata.xml"
fi

ARCH="x86_64"
if command -v appimagetool >/dev/null 2>&1; then
  ARCH=x86_64 appimagetool --no-appstream "$APPDIR" "$APPIMAGE_OUT"
else
  TOOL_DIR="$HOME/.cache/tsundoku-build"
  TOOL="$TOOL_DIR/appimagetool"
  if [ ! -x "$TOOL" ]; then
    echo "    appimagetool не найден — скачиваю в $TOOL_DIR..."
    mkdir -p "$TOOL_DIR"
    curl -fsSL -o "$TOOL.download" \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$TOOL.download"
    mv "$TOOL.download" "$TOOL"
  fi
  ARCH=x86_64 "$TOOL" --appimage-extract-and-run --no-appstream "$APPDIR" "$APPIMAGE_OUT"
fi
chmod +x "$APPIMAGE_OUT"
rm -rf "$APPDIR"

# Контроль чистоты: в корне dist/ только финальные артефакты.
stray="$(find dist -mindepth 1 -maxdepth 1 ! -name 'Tsundoku.AppImage' ! -name 'Tsundoku-Portable')"
if [ -n "$stray" ]; then
  echo "ПРЕДУПРЕЖДЕНИЕ: посторонние файлы в корне dist/:" >&2
  echo "$stray" >&2
fi

echo "==> Сборка завершена успешно!"
echo "    AppImage монолит: dist/Tsundoku.AppImage"
echo "    Портативная папка: dist/Tsundoku-Portable/Tsundoku  (сервер + трей + лаунчер + ui/)"
