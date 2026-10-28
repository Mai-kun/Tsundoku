#!/bin/bash
# === Установщик Tsundoku для Linux (x64) ===
set -e

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Ошибка: Этот скрипт предназначен только для Linux."
    exit 1
fi

echo "=== Установщик Tsundoku для Linux (x64) ==="

# 1. Выбор папки установки
echo -e "\nКуда установить программу Tsundoku?"
echo "  1) В Документы ($HOME/Documents/Tsundoku) [по умолчанию]"
echo "  2) В домашнюю папку ($HOME/.local/bin/Tsundoku)"
echo "  3) Указать свой путь"
read -p "Выберите вариант [1-3, Enter = 1]: " OPTION1
case "$OPTION1" in
    2) INSTALL_DIR="$HOME/.local/bin/Tsundoku" ;;
    3) read -p "Введите путь: " INSTALL_DIR ;;
    *) INSTALL_DIR="$HOME/Documents/Tsundoku" ;;
esac
mkdir -p "$INSTALL_DIR"

# 1.5. Скачивание и установка
echo "Загрузка последней версии..."
REPO=${REPO:-"mai-kun/tsundoku"}
# Используем tr -d '\r' чтобы убрать скрытые символы переноса, которые могут ломать URL
DOWNLOAD_URL=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep -o 'https://[^"]*tsundoku-linux-x64\.zip' | head -n 1 | tr -d '\r')
echo "URL: $DOWNLOAD_URL"
curl -L "$DOWNLOAD_URL" -o /tmp/tsundoku-linux-x64.zip

# 1.6. Полная замена wwwroot: старые чанки ассетов не должны накапливаться между
# обновлениями. Удаляем только wwwroot — ничего вне этой папки не трогаем.
# Пользовательские данные (storage.json, .portable, data/, *.db, .secret.key) в релизный
# zip не входят и unzip -o их не перезаписывает.
if [[ -d "$INSTALL_DIR/wwwroot" ]]; then
    echo "Очистка старого wwwroot..."
    rm -rf "$INSTALL_DIR/wwwroot"
fi

unzip -o /tmp/tsundoku-linux-x64.zip -d "$INSTALL_DIR" -x "storage.json" ".portable" ".secret.key" "data/*" "*.db" "*.db-wal" "*.db-shm"
chmod +x "$INSTALL_DIR/Tsundoku"
rm /tmp/tsundoku-linux-x64.zip

# 2. Выбор режима хранения (только при первой установке — повторный запуск
# установки не должен перезаписывать уже выбранный режим)
if [[ -f "$INSTALL_DIR/storage.json" ]]; then
    echo -e "\nНайден существующий storage.json — режим хранения сохранён."
    MODE=""
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
    mkdir -p "$(eval echo $DATA_PATH)"
    if [[ "$MODE" == "custom" ]]; then
        JSON="{\"mode\":\"$MODE\",\"customPath\":\"$(eval echo $DATA_PATH)\"}"
    else
        JSON="{\"mode\":\"$MODE\"}"
    fi
    echo "$JSON" > "$INSTALL_DIR/storage.json"
fi

# Ярлык
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/tsundoku.desktop" <<DESKTOP
[Desktop Entry]
Name=Tsundoku
Exec=$INSTALL_DIR/Tsundoku
Type=Application
Categories=Utility;
DESKTOP

echo -e "\n=== Установка завершена ==="
echo "Программа: $INSTALL_DIR"
if [[ -n "$MODE" ]]; then
    echo "Данные: $(eval echo $DATA_PATH)"
fi
echo "Ярлык: ~/.local/share/applications/tsundoku.desktop"

read -p "Запустить Tsundoku прямо сейчас? [Y/n]: " RUN
if [[ "$RUN" =~ ^([yY]|"")$ ]]; then
    nohup "$INSTALL_DIR/Tsundoku" >/dev/null 2>&1 &
    echo "Запущено! Откройте http://127.0.0.1:5000"
fi
