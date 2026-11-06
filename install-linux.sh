#!/bin/bash
# === Автономный установщик Tsundoku для Linux (x64) ===
# Скрипт лежит ВНУТРИ архива tsundoku-linux-x64.zip рядом с бинарником Tsundoku:
# никаких загрузок из сети не требуется — установка идёт из папки распаковки.
set -e

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Ошибка: Этот скрипт предназначен только для Linux."
    exit 1
fi

# Папка, из которой запущен скрипт (внутри архива, рядом с бинарником).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/Tsundoku" ]]; then
    echo "Ошибка: рядом со скриптом нет бинарника Tsundoku."
    echo "Запускайте install-linux.sh из распакованного архива tsundoku-linux-x64.zip."
    exit 1
fi

echo "=== Установщик Tsundoku для Linux (x64) ==="

# 1. Выбор папки установки
echo -e "\nКуда установить программу Tsundoku?"
echo "  1) В Документы ($HOME/Documents/Tsundoku) [по умолчанию]"
echo "  2) В домашнюю папку ($HOME/.local/bin/Tsundoku)"
echo "  3) В текущую папку ($SCRIPT_DIR — настройка без копирования)"
echo "  4) Указать свой путь"
read -p "Выберите вариант [1-4, Enter = 1]: " OPTION1
case "$OPTION1" in
    2) INSTALL_DIR="$HOME/.local/bin/Tsundoku" ;;
    3) INSTALL_DIR="$SCRIPT_DIR" ;;
    4) read -p "Введите путь: " INSTALL_DIR ;;
    *) INSTALL_DIR="$HOME/Documents/Tsundoku" ;;
esac
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

# 2. Копирование файлов программы
if [[ "$INSTALL_DIR" != "$SCRIPT_DIR" ]]; then
    mkdir -p "$INSTALL_DIR"

    # Полная замена wwwroot: старые чанки ассетов не должны накапливаться между
    # обновлениями. Пользовательские данные (storage.json, .portable, data/, *.db,
    # .secret.key) в архив не входят и не перезаписываются.
    if [[ -d "$INSTALL_DIR/wwwroot" ]]; then
        echo "Очистка старого wwwroot..."
        rm -rf "$INSTALL_DIR/wwwroot"
    fi

    echo "Копирование файлов в $INSTALL_DIR..."
    # Скрипты установки/удаления в целевую папку не нужны: они лежат в архиве.
    (shopt -s dotglob nullglob; for item in "$SCRIPT_DIR"/*; do
        base="$(basename "$item")"
        [[ "$base" == "install-linux.sh" || "$base" == "uninstall-linux.sh" ]] && continue
        cp -r "$item" "$INSTALL_DIR/"
    done)
    chmod +x "$INSTALL_DIR/Tsundoku"
fi

# 3. Режим хранения данных (только при первой установке — повторный запуск
# установки не должен перезаписывать уже выбранный режим)
MODE=""
if [[ -f "$INSTALL_DIR/storage.json" ]]; then
    echo -e "\nНайден существующий storage.json — режим хранения сохранён."
else
    echo -e "\nГде хранить базу данных и обложки?"
    echo "  1) Рядом с программой — Портативный режим [по умолчанию]"
    echo "  2) В системной папке (~/.local/share/Tsundoku)"
    echo "  3) Указать свой путь"
    read -p "Выберите вариант [1-3, Enter = 1]: " OPTION2

    case "$OPTION2" in
        2) MODE="default"; DATA_PATH="~/.local/share/Tsundoku" ;;
        3) MODE="custom"; read -p "Введите путь к данным: " DATA_PATH ;;
        *) MODE="portable"; DATA_PATH="$INSTALL_DIR/data" ;;
    esac
fi

# Запись конфигурации (только когда режим был выбран сейчас)
if [[ -n "$MODE" ]]; then
    mkdir -p "$(eval echo "$DATA_PATH")"
    if [[ "$MODE" == "custom" ]]; then
        JSON="{\"mode\":\"$MODE\",\"customPath\":\"$(eval echo "$DATA_PATH")\"}"
    else
        JSON="{\"mode\":\"$MODE\"}"
    fi
    echo "$JSON" > "$INSTALL_DIR/storage.json"
fi

# 4. Цветная иконка в систему: без неё ярлык (и док/панель задач) остаётся
# серым обобщённым значком. Кладём в оба размера: панель задач запрашивает
# 256x256, устанавливщики и сетка — 512x512.
ICON_SRC="$INSTALL_DIR/wwwroot/icons/default.png"
[ -f "$ICON_SRC" ] || ICON_SRC="$INSTALL_DIR/wwwroot/icon-512.png"
for SIZE in 256x256 512x512; do
    mkdir -p "$HOME/.local/share/icons/hicolor/$SIZE/apps"
    cp "$ICON_SRC" "$HOME/.local/share/icons/hicolor/$SIZE/apps/tsundoku.png" 2>/dev/null || true
done
# Обновить кэш темы иконок, чтобы KDE/GNOME увидели файл без перелогина.
gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# 5. Ярлык. Icon= ведёт на абсолютный путь: пока иконка не попала в кэш темы
# (или тема нестандартная), "Icon=tsundoku" рисует серый квадрат-заглушку.
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/tsundoku.desktop" <<DESKTOP
[Desktop Entry]
Name=Tsundoku
Exec=$INSTALL_DIR/Tsundoku
Icon=$ICON_SRC
Type=Application
Categories=Utility;Office;
# Must match the Chromium --app window's WM_CLASS on X11/XWayland sessions
# (--class=Tsundoku), or the taskbar/dock pairs the app window with the running
# browser instead of this entry.
StartupWMClass=Tsundoku
DESKTOP

# На нативном Wayland Chromium игнорирует --class и сам вычисляет app id как
# "chrome-<host>__-<внутренний профиль>" (host 127.0.0.1 и профиль Default у
# десктоп-запуска постоянны). Без второй записи панель задач на Wayland не найдёт
# иконку. Скрытый шлюз (NoDisplay) матчит именно этот класс.
cat > "$HOME/.local/share/applications/tsundoku-wayland.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Tsundoku
NoDisplay=true
Exec=$INSTALL_DIR/Tsundoku
Icon=$ICON_SRC
StartupWMClass=chrome-127.0.0.1__-Default
DESKTOP

echo -e "\n=== Установка завершена ==="
echo "Программа: $INSTALL_DIR"
if [[ -n "$MODE" ]]; then
    echo "Данные: $(eval echo "$DATA_PATH")"
fi
echo "Ярлык: ~/.local/share/applications/tsundoku.desktop"
echo "Удаление: запустите uninstall-linux.sh из архива (или $SCRIPT_DIR)"

read -p "Запустить Tsundoku прямо сейчас? [Y/n]: " RUN
if [[ "$RUN" =~ ^([yY]|"")$ ]]; then
    nohup "$INSTALL_DIR/Tsundoku" >/dev/null 2>&1 &
    echo "Запущено! Откройте http://127.0.0.1:5000"
fi
