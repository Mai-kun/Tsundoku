#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "==> Очистка dist/..."
rm -rf dist && mkdir -p dist

# 1. Фронтенд: vite пишет результат прямо в MediaTracker.Server/wwwroot.
echo "==> Шаг 1/3: Сборка фронтенда..."
npm --prefix mediatracker-ui run build

if [ ! -f MediaTracker.Server/wwwroot/index.html ]; then
  echo "ОШИБКА: MediaTracker.Server/wwwroot/index.html не найден — фронтенд не собрался?" >&2
  exit 1
fi

# 2. Монолитный NativeAOT-бинарник: Kestrel + трей + лаунчер в одном Tsundoku.
#    Требует clang/llvm и zlib-dev (см. README). PublishAot включён в csproj.
echo "==> Шаг 2/3: Публикация NativeAOT (dotnet)..."
dotnet publish MediaTracker.Server -c Release -r linux-x64 -o dist/Tsundoku-Portable
chmod +x dist/Tsundoku-Portable/Tsundoku

# 3. Ярлык портативной папки.
echo "==> Шаг 3/3: Упаковка..."
cat > dist/Tsundoku-Portable/Tsundoku.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Tsundoku
Comment=Персональный трекер медиатеки
Exec=/opt/tsundoku/Tsundoku
Icon=tsundoku
Categories=Office;Viewer;
Terminal=false
DESKTOP

# Монолитный автономный AppImage: bin/ + wwwroot/ рядом с AppRun.
APPDIR="dist/.appdir"
mkdir -p "$APPDIR/bin"
cp dist/Tsundoku-Portable/Tsundoku "$APPDIR/bin/Tsundoku"
chmod +x "$APPDIR/bin/Tsundoku"
# Every native library ships next to the binary: the DllNotFoundException for a
# missing libSkiaSharp.so surfaced only at first cover download, as a fatal
# TypeInitializationException on the finalizer thread that killed the process.
cp dist/Tsundoku-Portable/*.so "$APPDIR/bin/"
chmod +x "$APPDIR/bin/"*.so
cp -r dist/Tsundoku-Portable/wwwroot "$APPDIR/wwwroot"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/bin:${LD_LIBRARY_PATH}"
# wwwroot sits at the AppDir root while the binary lives in bin/, so the
# content root must be $HERE — the server resolves wwwroot from it.
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
DESKTOP

ICON_SRC="mediatracker-ui/public/icons/default.png"
[ -f "$ICON_SRC" ] || ICON_SRC="mediatracker-ui/public/icon-512.png"
[ -f "$ICON_SRC" ] || ICON_SRC="mediatracker-ui/public/icon-192.png"
cp "$ICON_SRC" "$APPDIR/tsundoku.png"
ln -sf tsundoku.png "$APPDIR/.DirIcon"

# AppStream metainfo: named after the component id (appstreamcli requires the
# cid match; appimagetool's own filename check is skipped in favor of an
# explicit validation below).
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
  <content_rating type="oars-1.1"/>
  <releases>
    <release version="1.0.0" date="2026-11-05"/>
  </releases>
</component>
APPDATA
# A desktop-file copy under usr/share/applications lets appstreamcli resolve
# the <launchable> reference; the AppDir-root .desktop stays the AppImage entry point.
cp "$APPDIR/tsundoku.desktop" "$APPDIR/usr/share/applications/tsundoku.desktop"

if command -v appstreamcli >/dev/null 2>&1; then
  appstreamcli validate "$APPDIR/usr/share/metainfo/io.github.Maikun.Tsundoku.appdata.xml"
fi

# appimagetool: системный или автоматически скачанный в кэш.
ARCH="x86_64"
if command -v appimagetool >/dev/null 2>&1; then
  # --no-appstream: appimagetool's legacy check expects a tsundoku.appdata.xml
  # filename that conflicts with the cid-based naming appstreamcli validates above.
  ARCH=x86_64 appimagetool --no-appstream "$APPDIR" dist/Tsundoku.AppImage
else
  # Build-only cache: the produced binary/AppImage never reads or creates this path.
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
  # --appimage-extract-and-run: работает даже без FUSE в системе.
  ARCH=x86_64 "$TOOL" --appimage-extract-and-run --no-appstream "$APPDIR" dist/Tsundoku.AppImage
fi
chmod +x dist/Tsundoku.AppImage
rm -rf "$APPDIR"

# Контроль чистоты: в корне dist/ только финальные артефакты.
stray="$(find dist -mindepth 1 -maxdepth 1 ! -name 'Tsundoku.AppImage' ! -name 'Tsundoku-Portable')"
if [ -n "$stray" ]; then
  echo "ПРЕДУПРЕЖДЕНИЕ: посторонние файлы в корне dist/:" >&2
  echo "$stray" >&2
fi

echo "==> Сборка завершена успешно!"
echo "    AppImage монолит: dist/Tsundoku.AppImage"
echo "    Портативная папка: dist/Tsundoku-Portable/Tsundoku  (сервер + трей + лаунчер)"
