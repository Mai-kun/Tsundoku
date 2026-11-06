#!/bin/bash
# === Деинсталлятор Tsundoku для Linux ===
# Убирает ярлык и иконку из системы, затем (с подтверждениями) файлы программы
# и пользовательские данные. Сам скрипт поставляется внутри архива рядом с
# install-linux.sh; папку программы он находит через пользовательский ввод.
set -e

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Ошибка: Этот скрипт предназначен только для Linux."
    exit 1
fi

echo "=== Деинсталлятор Tsundoku для Linux ==="

# 0. Остановить запущенный экземпляр, если он есть.
if pgrep -f "Tsundoku" > /dev/null 2>&1; then
    echo "Найден запущенный Tsundoku."
    read -p "Остановить его? [Y/n]: " STOP
    if [[ ! "$STOP" =~ ^([nN])$ ]]; then
        pkill -f "Tsundoku" 2>/dev/null || true
        sleep 2
    fi
fi

# 1. Определить папку установки: ярлык хранит путь к бинарнику.
INSTALL_DIR=""
if [[ -f "$HOME/.local/share/applications/tsundoku.desktop" ]]; then
    EXEC_PATH=$(grep -m1 "^Exec=" "$HOME/.local/share/applications/tsundoku.desktop" | cut -d= -f2)
    INSTALL_DIR="$(dirname "$EXEC_PATH")"
fi

if [[ -z "$INSTALL_DIR" || ! -d "$INSTALL_DIR" ]]; then
    echo -e "\nПапка установки не найдена по ярлыку."
    echo "  1) $HOME/Documents/Tsundoku [по умолчанию]"
    echo "  2) $HOME/.local/bin/Tsundoku"
    echo "  3) Указать свой путь"
    read -p "Где установлена программа? [1-3, Enter = 1]: " OPTION
    case "$OPTION" in
        2) INSTALL_DIR="$HOME/.local/bin/Tsundoku" ;;
        3) read -p "Введите путь: " INSTALL_DIR ;;
        *) INSTALL_DIR="$HOME/Documents/Tsundoku" ;;
    esac
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
fi
echo "Папка программы: $INSTALL_DIR"

# 2. Удалить ярлыки и иконку из системы — всегда, без вопросов.
rm -f "$HOME/.local/share/applications/tsundoku.desktop"
rm -f "$HOME/.local/share/applications/tsundoku-wayland.desktop"
for SIZE in 256x256 512x512; do
    rm -f "$HOME/.local/share/icons/hicolor/$SIZE/apps/tsundoku.png"
done
gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
echo "Ярлык и иконка удалены."

# 3. Файлы программы.
read -p "Удалить файлы программы ($INSTALL_DIR)? [y/N]: " DEL_PROGRAM
if [[ "$DEL_PROGRAM" =~ ^([yY])$ ]]; then
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        echo "Папка программы удалена."
    else
        echo "Папка не найдена — пропуск."
    fi
fi

# 4. Пользовательские данные (база, обложки, chromium-профиль).
CANDIDATES=(
    "$HOME/.local/share/Tsundoku"
)
# Портативный режим хранит данные рядом с программой (уже удалена выше вместе с ней).
read -p "Удалить пользовательскую базу данных и обложки (~/.local/share/Tsundoku)? [y/N]: " DEL_DATA
if [[ "$DEL_DATA" =~ ^([yY])$ ]]; then
    for candidate in "${CANDIDATES[@]}"; do
        if [[ -d "$candidate" ]]; then
            rm -rf "$candidate"
            echo "Удалено: $candidate"
        fi
    done
fi

echo -e "\n=== Деинсталляция завершена ==="
