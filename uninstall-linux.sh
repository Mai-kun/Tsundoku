#!/usr/bin/env bash
# === Деинсталлятор Tsundoku для Linux ===
# Убирает ярлыки, иконки, обёртки в bin/, кэш Chromium и — только с явными
# подтверждениями — файлы программы и пользовательские данные.
# Папка установки определяется автоматически: по Exec= ярлыка, по стандартным
# путям и по папке самого скрипта (in-place установка). Ничего не удаляется
# молча: пользовательская папка data/ всегда спрашивается отдельно, [y/N].
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Ошибка: Этот скрипт предназначен только для Linux."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- helpers ----------

# ask: безопасный ввод. При закрытом/пустом stdin (EOF) возвращает пустую
# строку, т.е. срабатывает ответ по умолчанию — скрипт не падает под set -e.
ask() {
    local reply=""
    read -r -p "$1" reply || reply=""
    printf '%s' "$reply"
}

# Подтверждение [y/N]: true только при явном y/Y.
confirm_no() { [[ "$(ask "$1")" =~ ^[yY]$ ]]; }

# Подтверждение [Y/n]: true при y/Y и при пустом вводе (Enter).
confirm_yes() { [[ "$(ask "$1")" =~ ^([yY])?$ ]]; }

# -m: путь может не существовать (введён вручную) — считаем логически.
realpath_of() { realpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

# Системные и пользовательские корни, которые деинсталлятор не трогает никогда.
is_protected_root() {
    local p="$1"
    case "$p" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|\
/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|/lost+found)
            return 0 ;;
    esac
    [[ "$p" == "$HOME" || "$p" == "$HOME/Documents" || "$p" == "$HOME/Downloads" ]] && return 0
    return 1
}

# ---------- 0. Остановить запущенный экземпляр ----------

# Точное совпадение по имени процесса (pgrep -x): шаблон по cmdline (pgrep -f
# "Tsundoku") убивал и родительский терминал с путём/аргументом "Tsundoku", и
# сам деинсталлятор — скрипт умирал посреди работы.
collect_tsundoku_pids() {
    local pid
    while IFS= read -r pid; do
        [[ -n "$pid" && "$pid" != "$$" && "$pid" != "$PPID" ]] && printf '%s\n' "$pid"
    done < <(pgrep -x Tsundoku 2>/dev/null || true)
}

pids="$(collect_tsundoku_pids)"
if [[ -n "$pids" ]]; then
    echo "Найден запущенный Tsundoku (PID: $(echo "$pids" | tr '\n' ' '))."
    if [[ -t 0 ]] && ! confirm_yes "Остановить его? [Y/n]: "; then
        echo "Пропускаю остановку процесса."
    else
        # shellcheck disable=SC2086
        kill -TERM $pids 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            collect_tsundoku_pids | grep -q . || break
            sleep 0.5
        done
        rest="$(collect_tsundoku_pids)"
        if [[ -n "$rest" ]]; then
            # shellcheck disable=SC2086
            kill -KILL $rest 2>/dev/null || true
        fi
        echo "Процесс остановлен."
    fi
fi

# ---------- 1. Определить папку установки ----------

# Первая "команда" строки Exec= (сняв кавычки) — путь к бинарнику.
desktop_exec_dir() {
    local f="$1" exec_line first dir
    [[ -f "$f" ]] || return 1
    exec_line="$(sed -n 's/^[[:space:]]*Exec=//p' "$f" | head -n 1)"
    [[ -n "$exec_line" ]] || return 1
    first="${exec_line%% *}"
    first="${first%\"}"
    first="${first#\"}"
    [[ "$first" == */* ]] || return 1   # относительное имя (AppRun и т.п.) — не путь установки
    dir="$(dirname "$first")"
    [[ -d "$dir" ]] || return 1
    printf '%s' "$dir"
}

CANDIDATES=()
add_candidate() {
    local rp c
    rp="$(realpath_of "$1")"
    [[ -d "$rp" && -f "$rp/Tsundoku" ]] || return 0
    for c in "${CANDIDATES[@]:-}"; do
        [[ "$c" == "$rp" ]] && return 0
    done
    CANDIDATES+=("$rp")
}

# Ярлыки ставит установщик; Exec= хранит точный путь бинарника.
add_candidate "$(desktop_exec_dir "$HOME/.local/share/applications/tsundoku.desktop" || true)"
add_candidate "$(desktop_exec_dir "$HOME/.local/share/applications/tsundoku-wayland.desktop" || true)"
# Стандартные пути установщика и in-place установки (скрипт лежит рядом с
# бинарником), плюс текущая папка запуска.
for std in "$HOME/Documents/Tsundoku" "$HOME/.local/bin/Tsundoku" \
           "/opt/tsundoku" "$HOME/.local/share/tsundoku" "$SCRIPT_DIR" "$PWD"; do
    add_candidate "$std"
done

INSTALL_DIR=""
if ((${#CANDIDATES[@]} == 1)); then
    INSTALL_DIR="${CANDIDATES[0]}"
elif ((${#CANDIDATES[@]} > 1)); then
    echo -e "\nНайдено несколько папок с Tsundoku:"
    i=1
    for c in "${CANDIDATES[@]}"; do
        echo "  $i) $c"
        i=$((i + 1))
    done
    echo "  $i) Указать путь вручную"
    choice="$(ask "Какую удалить? [1-${#CANDIDATES[@]}, Enter = 1]: ")"
    [[ "$choice" =~ ^[0-9]+$ ]] || choice=1
    if ((choice >= 1 && choice <= ${#CANDIDATES[@]})); then
        INSTALL_DIR="${CANDIDATES[choice - 1]}"
    fi
fi

if [[ -z "$INSTALL_DIR" ]]; then
    echo -e "\nПапка установки не найдена автоматически."
    echo "  1) $HOME/Documents/Tsundoku [по умолчанию]"
    echo "  2) $HOME/.local/bin/Tsundoku"
    echo "  3) Указать свой путь"
    option="$(ask "Где установлена программа? [1-3, Enter = 1]: ")"
    case "$option" in
        2) INSTALL_DIR="$HOME/.local/bin/Tsundoku" ;;
        3) INSTALL_DIR="$(ask "Введите путь: ")" ;;
        *) INSTALL_DIR="$HOME/Documents/Tsundoku" ;;
    esac
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
    INSTALL_DIR="$(realpath_of "$INSTALL_DIR")"
fi
echo "Папка программы: $INSTALL_DIR"

# ---------- 2. Ярлыки, иконки, обёртки, кэш Chromium — всегда, без вопросов ----------

rm -f "$HOME/.local/share/applications/tsundoku.desktop" \
      "$HOME/.local/share/applications/tsundoku-wayland.desktop"
# Иконки всех размеров (установщик кладёт 256x256 и 512x512, но снимем все).
rm -f "$HOME/.local/share/icons/hicolor/"*/apps/tsundoku.png
command -v gtk-update-icon-cache >/dev/null 2>&1 && \
    gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# Симлинки/обёртки в ~/.local/bin и /usr/local/bin. Каталог (например
# ~/.local/bin/Tsundoku — вариант установки №2) не трогаем: это папка программы.
remove_bin_wrapper() {
    local path="$1"
    [[ -e "$path" || -L "$path" ]] || return 0
    [[ -d "$path" && ! -L "$path" ]] && return 0
    if rm -f -- "$path" 2>/dev/null; then
        echo "Удалена обёртка: $path"
    else
        echo "Не удалось удалить $path (нет прав? попробуйте: sudo rm -f \"$path\")"
    fi
}
for wrapper in "$HOME/.local/bin/"*[tT]sundoku*; do
    [[ -e "$wrapper" || -L "$wrapper" ]] && remove_bin_wrapper "$wrapper"
done
for wrapper in /usr/local/bin/*[tT]sundoku*; do
    [[ -e "$wrapper" || -L "$wrapper" ]] && remove_bin_wrapper "$wrapper"
done

# Временный кэш Chromium в tmpfs (см. BrowserLauncher: /dev/shm/tsundoku-*).
rm -rf -- /dev/shm/tsundoku-* 2>/dev/null || true
echo "Ярлыки, иконки, обёртки и кэш Chromium удалены."

# ---------- 3. Пользовательские данные — спрашиваем отдельно ----------

# Кандидаты собираем из storage.json (режим portable/default/custom знает
# точный путь), системного fallback-конфига и явных мест.
DATA_DIRS=()          # пути, подтверждённые к удалению
KEEP_DATA_DIRS=()     # пути, которые пользователь оставил

storage_data_paths() {
    # $1 = storage.json → печатает пути данных согласно записанному режиму.
    local f="$1" mode custom
    [[ -f "$f" ]] || return 0
    mode="$(sed -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)"
    custom="$(sed -n 's/.*"customPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)"
    case "${mode,,}" in
        portable|p) printf '%s\n' "$INSTALL_DIR/data" ;;
        custom|c)
            if [[ -n "$custom" ]]; then
                printf '%s\n' "${custom/#\~/$HOME}"
            fi ;;
        *) printf '%s\n' "$HOME/.local/share/Tsundoku" ;;
    esac
}

data_candidates=()
while IFS= read -r p; do [[ -n "$p" ]] && data_candidates+=("$(printf '%s' "$p")"); done < <(storage_data_paths "$INSTALL_DIR/storage.json")
while IFS= read -r p; do [[ -n "$p" ]] && data_candidates+=("$(printf '%s' "$p")"); done < <(storage_data_paths "$HOME/.local/share/Tsundoku/storage.json")
[[ -d "$INSTALL_DIR/data" ]] && data_candidates+=("$(printf '%s' "$INSTALL_DIR/data")")
[[ -d "$HOME/.local/share/Tsundoku" ]] && data_candidates+=("$(printf '%s' "$HOME/.local/share/Tsundoku")")

# Дедупликация сохранением порядка.
unique_data=()
for p in "${data_candidates[@]:-}"; do
    [[ -n "$p" ]] || continue
    rp="$(realpath_of "$p")"
    is_protected_root "$rp" && continue
    seen=""
    for u in "${unique_data[@]:-}"; do [[ "$u" == "$rp" ]] && seen=1 && break; done
    [[ -n "$seen" ]] || unique_data+=("$rp")
done

looks_like_data() {
    # Признаки пользовательских данных Tsundoku — защита от удаления чужой папки.
    local d="$1"
    [[ -e "$d/tracker.db" || -e "$d/tracker.db-shm" || -d "$d/covers" ||
       -d "$d/media" || -d "$d/offline" || -d "$d/logs" ||
       -d "$d/chromium-profile" || -e "$d/search_cache.db" ]]
}

for d in "${unique_data[@]:-}"; do
    [[ -n "$d" ]] || continue
    if [[ "$d" == "$HOME/.local/share/Tsundoku" ]]; then
        label="пользовательскую базу данных и обложки ($d)"
    else
        label="пользовательские данные ($d)"
    fi
    if ! looks_like_data "$d"; then
        echo -e "\nВНИМАНИЕ: $d не похож на папку данных Tsundoku."
    fi
    if confirm_no "Удалить ${label}? [y/N]: "; then
        DATA_DIRS+=("$d")
    else
        KEEP_DATA_DIRS+=("$d")
    fi
done

# ---------- 4. Файлы программы ----------

delete_program=0
if confirm_no "Удалить файлы программы ($INSTALL_DIR)? [y/N]: "; then
    delete_program=1
fi

if ((delete_program)); then
    if is_protected_root "$INSTALL_DIR"; then
        echo "ОТКАЗ: $INSTALL_DIR — системный/корневой путь, удаление запрещено."
    elif [[ ! -d "$INSTALL_DIR" ]]; then
        echo "Папка не найдена — пропуск."
    else
        keep_inside=""
        for d in "${KEEP_DATA_DIRS[@]:-}"; do
            [[ -n "$d" && "$d" == "$INSTALL_DIR"/* ]] && keep_inside=1
        done
        if [[ -n "$keep_inside" ]]; then
            # Портативные/in-place данные лежат внутри папки программы: удаляем
            # всё вокруг них, но data/ (и storage.json с выбранным режимом)
            # сохраняем — коллекция пользователя не пострадает.
            shopt -s dotglob nullglob
            for item in "$INSTALL_DIR"/*; do
                base="$(basename "$item")"
                rp="$(realpath_of "$item")"
                skip=""
                for d in "${KEEP_DATA_DIRS[@]:-}"; do
                    [[ -n "$d" && "$rp" == "$d" ]] && skip=1 && break
                done
                [[ -n "$skip" || "$base" == "storage.json" ]] && continue
                rm -rf -- "$item"
            done
            shopt -u dotglob nullglob
            echo "Файлы программы удалены (пользовательские данные сохранены)."
        else
            rm -rf -- "$INSTALL_DIR"
            echo "Папка программы удалена."
        fi
    fi
fi

# ---------- 5. Удаление самих данных ----------

for d in "${DATA_DIRS[@]:-}"; do
    [[ -n "$d" ]] || continue
    if is_protected_root "$d"; then
        echo "ОТКАЗ: $d — системный/корневой путь, удаление запрещено."
        continue
    fi
    if [[ ! -d "$d" ]]; then
        echo "Не найдено (уже удалено?): $d"
        continue
    fi
    rm -rf -- "$d"
    echo "Удалено: $d"
done

echo -e "\n=== Деинсталляция завершена ==="
