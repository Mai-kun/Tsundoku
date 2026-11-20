#!/usr/bin/env bash
# === Автономный установщик Tsundoku для Linux (x64) ===
# Скрипт лежит ВНУТРИ архива tsundoku-linux-x64.zip рядом с бинарником Tsundoku:
# никаких загрузок из сети не требуется — установка идёт из папки распаковки.
# Режим «Оставить путь как есть» ничего не копирует: только права, ярлыки и
# иконки с указанием на текущую папку. В этом режиме вопрос об удалении
# исходных файлов не задаётся никогда.
set -euo pipefail

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

# ask: безопасный ввод. При закрытом stdin (EOF) возвращает пустую строку —
# срабатывает ответ по умолчанию, скрипт не падает под set -e.
ask() {
    local reply=""
    read -r -p "$1" reply || reply=""
    printf '%s' "$reply"
}

# -m: целевая папка может ещё не существовать — путь считается логически.
realpath_of() { realpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

echo "=== Установщик Tsundoku для Linux (x64) ==="

# 1. Выбор папки установки
echo -e "\nКуда установить программу Tsundoku?"
echo "  1) В Документы ($HOME/Documents/Tsundoku) [по умолчанию]"
echo "  2) В домашнюю папку ($HOME/.local/bin/Tsundoku)"
echo "  3) Оставить путь как есть (in-place: $SCRIPT_DIR — без копирования)"
echo "  4) Указать свой путь"
OPTION1="$(ask "Выберите вариант [1-4, Enter = 1]: ")"
IN_PLACE=0
case "$OPTION1" in
    2) INSTALL_DIR="$HOME/.local/bin/Tsundoku" ;;
    3) INSTALL_DIR="$SCRIPT_DIR"; IN_PLACE=1 ;;
    4) INSTALL_DIR="$(ask "Введите путь: ")" ;;
    *) INSTALL_DIR="$HOME/Documents/Tsundoku" ;;
esac
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

SOURCE_REAL="$(realpath_of "$SCRIPT_DIR")"
TARGET_REAL="$(realpath_of "$INSTALL_DIR")"

# Копирование было только если цель — другая папка. Именно по этому признаку в
# конце решается, задавать ли вопрос об удалении исходных файлов.
COPIED=0
if ((IN_PLACE)) || [[ "$TARGET_REAL" == "$SOURCE_REAL" ]]; then
    INSTALL_DIR="$SOURCE_REAL"
else
    COPIED=1
fi

# Целевая папка не может быть вложена в исходную (или наоборот совпадать):
# cp -r зациклится, а удаление исходника затронет установленную копию.
if ((COPIED)); then
    case "$TARGET_REAL" in
        "$SOURCE_REAL"|"$SOURCE_REAL"/*)
            echo "ОШИБКА: целевая папка находится внутри исходной ($TARGET_REAL)."
            echo "Выберите другую папку установки или режим «Оставить путь как есть»."
            exit 1 ;;
    esac
fi

# 2. Копирование файлов программы
if ((COPIED)); then
    mkdir -p "$INSTALL_DIR"

    # Полная замена wwwroot: старые чанки ассетов не должны накапливаться между
    # обновлениями. Пользовательские данные (storage.json, .portable, data/, *.db,
    # .secret.key) в архив не входят и не перезаписываются.
    if [[ -d "$INSTALL_DIR/wwwroot" ]]; then
        echo "Очистка старого wwwroot..."
        rm -rf "$INSTALL_DIR/wwwroot"
    fi

    echo "Копирование файлов в $INSTALL_DIR..."
    # Копируем всё, включая install/uninstall-скрипты: папка установки становится
    # самодостаточной — деинсталлятор можно запустить без сохранённого архива.
    (shopt -s dotglob nullglob; for item in "$SOURCE_REAL"/*; do
        cp -r "$item" "$INSTALL_DIR/"
    done)
    chmod +x "$INSTALL_DIR/Tsundoku"
else
    # In-place: файлы никуда не копируются, гарантируем только права на запуск.
    chmod +x "$INSTALL_DIR/Tsundoku"
fi
# В обоих режимах: права на запуск скриптов, если они лежат в целевой папке.
for s in install-linux.sh uninstall-linux.sh; do
    [[ -f "$INSTALL_DIR/$s" ]] && chmod +x "$INSTALL_DIR/$s" || true
done

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
    OPTION2="$(ask "Выберите вариант [1-3, Enter = 1]: ")"

    case "$OPTION2" in
        2) MODE="default"; DATA_PATH="~/.local/share/Tsundoku" ;;
        3) MODE="custom"; DATA_PATH="$(ask "Введите путь к данным: ")" ;;
        *) MODE="portable"; DATA_PATH="$INSTALL_DIR/data" ;;
    esac
fi

# Запись конфигурации (только когда режим был выбран сейчас)
if [[ -n "$MODE" ]]; then
    DATA_PATH="${DATA_PATH/#\~/$HOME}"
    mkdir -p "$DATA_PATH"
    if [[ "$MODE" == "custom" ]]; then
        JSON="{\"mode\":\"$MODE\",\"customPath\":\"$DATA_PATH\"}"
    else
        JSON="{\"mode\":\"$MODE\"}"
    fi
    echo "$JSON" > "$INSTALL_DIR/storage.json"
fi

# 4. Цветная иконка в систему: без неё ярлык (и док/панель задач) остаётся
# серым обобщённым значком. Кладём в оба размера: панель задач запрашивает
# 256x256, устанавливщики и сетка — 512x512.
ICON_SRC="$INSTALL_DIR/wwwroot/icons/default.png"
[[ -f "$ICON_SRC" ]] || ICON_SRC="$INSTALL_DIR/wwwroot/icon-512.png"
for SIZE in 256x256 512x512; do
    mkdir -p "$HOME/.local/share/icons/hicolor/$SIZE/apps"
    cp "$ICON_SRC" "$HOME/.local/share/icons/hicolor/$SIZE/apps/tsundoku.png" 2>/dev/null || true
done
# Обновить кэш темы иконок, чтобы KDE/GNOME увидели файл без перелогина.
command -v gtk-update-icon-cache >/dev/null 2>&1 && \
    gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# 5. Ярлык. Путь в кавычках: папки с пробелами в Exec=/Icon= иначе ломаются.
# Icon= ведёт на абсолютный путь: пока иконка не попала в кэш темы (или тема
# нестандартная), "Icon=tsundoku" рисует серый квадрат-заглушку.
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/tsundoku.desktop" <<DESKTOP
[Desktop Entry]
Name=Tsundoku
Exec="$INSTALL_DIR/Tsundoku"
Icon="$ICON_SRC"
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
Exec="$INSTALL_DIR/Tsundoku"
Icon="$ICON_SRC"
StartupWMClass=chrome-127.0.0.1__-Default
DESKTOP

echo -e "\n=== Установка завершена ==="
echo "Программа: $INSTALL_DIR"
if [[ -n "$MODE" ]]; then
    echo "Данные: $DATA_PATH"
fi
echo "Ярлык: ~/.local/share/applications/tsundoku.desktop"
if ((COPIED)); then
    echo "Удаление: запустите $INSTALL_DIR/uninstall-linux.sh"
else
    echo "Удаление: запустите $INSTALL_DIR/uninstall-linux.sh (лежит рядом с программой)"
fi

read -r -p "Запустить Tsundoku прямо сейчас? [Y/n]: " RUN || RUN=""
if [[ "$RUN" =~ ^([yY])?$ ]]; then
    nohup "$INSTALL_DIR/Tsundoku" >/dev/null 2>&1 &
    echo "Запущено! Откройте http://127.0.0.1:5000"
fi

# 6. Удаление исходных файлов дистрибутива — только когда файлы копировались
# в другую папку. В режиме «Оставить путь как есть» сюда не попадаем никогда.
if ((COPIED)); then
    echo
    SRC_ANSWER="$(ask "Удалить исходные файлы/архив, из которых производилась установка ($SOURCE_REAL)? [y/N]: ")"
    if [[ "$SRC_ANSWER" =~ ^[yY]$ ]]; then
        refuse_source=0
        # Защита от случайного удаления: системные и пользовательские корни,
        # вложенность исходника и целевой папки, а также папки без признаков
        # дистрибутива Tsundoku.
        case "$SOURCE_REAL" in
            /|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|\
/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|/lost+found|\
"$HOME"|"$HOME/Documents"|"$HOME/Downloads")
                echo "ОТКАЗ: $SOURCE_REAL — защищённый путь, удаление запрещено."
                refuse_source=1 ;;
        esac
        if [[ "$SOURCE_REAL" == "$TARGET_REAL" || "$TARGET_REAL" == "$SOURCE_REAL"/* || "$SOURCE_REAL" == "$TARGET_REAL"/* ]]; then
            echo "ОТКАЗ: исходник и целевая папка совпадают или вложены друг в друга — удаление запрещено."
            refuse_source=1
        fi
        if [[ ! -f "$SOURCE_REAL/Tsundoku" ]]; then
            echo "ОТКАЗ: в $SOURCE_REAL нет бинарника Tsundoku — это не похоже на папку дистрибутива."
            refuse_source=1
        fi
        if ((refuse_source)); then
            echo "Исходные файлы не удалены."
        else
            # bash держит файл скрипта открытым: удаление собственной папки
            # безопасно, скрипт доработает до конца.
            cd "$HOME"
            rm -rf -- "$SOURCE_REAL"
            echo "Исходная папка удалена: $SOURCE_REAL"
            # Сам архив установщик не трогает: где он лежит — скрипту не известно.
            parent="$(dirname "$SOURCE_REAL")"
            for z in "$parent/"*[tT]sundoku*.zip; do
                if [[ -f "$z" ]]; then
                    echo "Архив остался на месте: $z (можно удалить вручную)"
                fi
            done
        fi
    fi
fi
