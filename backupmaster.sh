#!/bin/bash

# Цвета для оформления
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Основные пути и файлы
LOCAL_BACKUP_DIR=$(pwd)  # Локальная директория по умолчанию
PACKAGE_LIST="$LOCAL_BACKUP_DIR/installed_packages.txt"

# Проверка зависимостей
if ! command -v lsof >/dev/null 2>&1; then
    echo -e "${RED}Утилита lsof не установлена. Установите её: 'sudo apt install lsof'.${NC}"
fi
if ! command -v du >/dev/null 2>&1; then
    echo -e "${RED}Утилита du не установлена. Установите её: 'sudo apt install coreutils'.${NC}"
    exit 1
fi
if ! command -v df >/dev/null 2>&1; then
    echo -e "${RED}Утилита df не установлена. Установите её: 'sudo apt install coreutils'.${NC}"
    exit 1
fi

# Функция для оценки размера папки пользователя
estimate_user_backup_size() {
    local user_dir="/home/$1"
    if [ -d "$user_dir" ]; then
        local size=$(sudo du -sb "$user_dir" 2>/dev/null | awk '{print $1}')
        local compressed_bytes=$((size / 3))
        local size_mb=$((compressed_bytes / 1024 / 1024))
        echo "$size_mb"
    else
        echo "0"
    fi
}

# Функция для оценки размера источников пакетов
estimate_apt_backup_size() {
    local size=$(sudo du -sb /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | awk '{sum += $1} END {print sum}')
    local compressed_bytes=$((size / 3))
    local size_mb=$((compressed_bytes / 1024 / 1024))
    echo "$size_mb"
}

# Функция для поиска примонтированных устройств
list_mounted_devices() {
    df -h | grep -E '/dev/' | awk '$NF ~ /^\/media|^\/mnt/ {print $NF}' | sort -u
}

# Функция для получения списка пользователей с домашними директориями в /home
get_users() {
    awk -F: '$3 >= 1000 && $6 ~ /^\/home\// && $1 !~ /^(nobody|nogroup)$/ {print $1}' /etc/passwd | sort -u
}

# Функция для создания бэкапа
create_backup() {
    echo -e "${GREEN}Куда сохранить бэкап?${NC}"
    echo "1. Локально в текущую директорию ($LOCAL_BACKUP_DIR)"
    echo "2. Удалённый сервер (через SSH, локально+scp)"
    echo "3. Удалённый сервер (прямой бэкап через SSH)"
    echo "4. Указать свой локальный путь"
    echo "5. Выбрать примонтированное устройство"
    echo "q. Вернуться в главное меню"
    read -p "Выберите вариант (1-5 или q): " BACKUP_DEST

    if [ "$BACKUP_DEST" = "q" ]; then
        echo "Возврат в главное меню."
        return
    fi

    BACKUP_BASE=""
    REMOTE_DEST=""
    REMOTE_PATH=""

    case $BACKUP_DEST in
        1)
            BACKUP_BASE="$LOCAL_BACKUP_DIR"
            if [ ! -w "$BACKUP_BASE" ]; then
                echo -e "${RED}Нет прав на запись в $BACKUP_BASE${NC}"
                return
            fi
            ;;
        2|3)
            read -p "Введите SSH-адрес (например, user@host:/path/to/backup): " REMOTE_DEST
            ssh -q -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_DEST%%:*}" "exit" 2>/dev/null
            if [ $? -ne 0 ]; then
                echo -e "${RED}Не удалось подключиться к удалённому серверу${NC}"
                return
            fi
            REMOTE_PATH="${REMOTE_DEST#*:}"
            if [ "$BACKUP_DEST" = "2" ]; then
                BACKUP_BASE="$LOCAL_BACKUP_DIR"
            fi
            ;;
        4)
            read -p "Введите полный путь для сохранения бэкапа: " CUSTOM_PATH
            if [ ! -d "$CUSTOM_PATH" ]; then
                echo -e "${RED}Директория $CUSTOM_PATH не существует${NC}"
                return
            fi
            if [ ! -w "$CUSTOM_PATH" ]; then
                echo -e "${RED}Нет прав на запись в $CUSTOM_PATH${NC}"
                return
            fi
            BACKUP_BASE="$CUSTOM_PATH"
            ;;
        5)
            echo -e "${GREEN}Доступные примонтированные устройства:${NC}"
            MOUNTED_DEVICES=($(list_mounted_devices))
            if [ ${#MOUNTED_DEVICES[@]} -eq 0 ]; then
                echo -e "${RED}Устройства не найдены${NC}"
                return
            fi
            for i in "${!MOUNTED_DEVICES[@]}"; do
                echo "$((i+1)). ${MOUNTED_DEVICES[$i]}"
            done
            read -p "Выберите устройство (номер): " DEVICE_CHOICE
            if ! [[ "$DEVICE_CHOICE" =~ ^[0-9]+$ ]] || [ "$DEVICE_CHOICE" -lt 1 ] || [ "$DEVICE_CHOICE" -gt ${#MOUNTED_DEVICES[@]} ]; then
                echo -e "${RED}Неверный выбор${NC}"
                return
            fi
            BACKUP_BASE="${MOUNTED_DEVICES[$((DEVICE_CHOICE-1))]}"
            if [ ! -w "$BACKUP_BASE" ]; then
                echo -e "${RED}Нет прав на запись в $BACKUP_BASE${NC}"
                return
            fi
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            return
            ;;
    esac

    # Создание подпапки backups
    BACKUP_DIR="$BACKUP_BASE/backups"
    if [ "$BACKUP_DEST" != "3" ]; then  # Для прямого SSH подпапка создаётся на сервере
        if [ ! -d "$BACKUP_DIR" ]; then
            mkdir -p "$BACKUP_DIR"
            if [ $? -ne 0 ]; then
                echo -e "${RED}Не удалось создать папку $BACKUP_DIR${NC}"
                return
            fi
        fi
        if [ ! -w "$BACKUP_DIR" ]; then
            echo -e "${RED}Нет прав на запись в $BACKUP_DIR${NC}"
            return
        fi
    else
        ssh "${REMOTE_DEST%%:*}" "mkdir -p '$REMOTE_PATH/backups'" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}Не удалось создать папку backups на сервере${NC}"
            return
        fi
    fi

    # Список пользователей с домашними директориями в /home и UID >= 1000
    echo -e "${GREEN}Поиск пользователей для бэкапа...${NC}"
    USERS=($(get_users))
    if [ ${#USERS[@]} -eq 0 ]; then
        echo -e "${RED}Пользователи с UID >= 1000 и директориями в /home не найдены${NC}"
        echo "Содержимое /etc/passwd (для отладки):"
        awk -F: '$3 >= 1000 {print $1 " UID:" $3 " Home:" $6}' /etc/passwd | head -n 10
        return
    fi

    echo "Список пользователей для бэкапа:"
    for i in "${!USERS[@]}"; do
        USER_SIZE=$(estimate_user_backup_size "${USERS[$i]}")
        echo "$((i+1)). Пользователь: ${USERS[$i]} (примерный размер бэкапа: ${USER_SIZE} МБ)"
    done
    echo "all. Забэкапить всех пользователей"
    read -p "Выберите номер пользователя или 'all' для всех: " USER_CHOICE

    if [ "$USER_CHOICE" = "all" ]; then
        SELECTED_USERS=("${USERS[@]}")
        echo "Выбрано бэкапирование всех пользователей"
    else
        if ! [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] || [ "$USER_CHOICE" -lt 1 ] || [ "$USER_CHOICE" -gt ${#USERS[@]} ]; then
            echo -e "${RED}Неверный выбор${NC}"
            return
        fi
        SELECTED_USERS=("${USERS[$((USER_CHOICE-1))]}")
        echo "Выбран пользователь: ${SELECTED_USERS[0]}"
    fi

    echo -e "${GREEN}Создание списка установленных пакетов...${NC}"
    dpkg --get-selections > "$PACKAGE_LIST"
    if [ $? -eq 0 ]; then
        echo "Список пакетов сохранён: $PACKAGE_LIST"
    else
        echo -e "${RED}Ошибка при создании списка пакетов${NC}"
        return
    fi

    # Бэкап источников пакетов
    echo -e "${GREEN}Создание бэкапа источников пакетов...${NC}"
    APT_BACKUP="$BACKUP_DIR/apt_sources_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    APT_SIZE=$(estimate_apt_backup_size)
    echo "Примерный размер бэкапа источников: ${APT_SIZE} МБ"
    if [ "$BACKUP_DEST" = "3" ]; then
        APT_REMOTE_PATH="$REMOTE_PATH/backups/apt_sources_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        sudo tar -cz /etc/apt/sources.list /etc/apt/sources.list.d 2>tar_errors.log | ssh "${REMOTE_DEST%%:*}" "cat > $APT_REMOTE_PATH"
        if [ $? -eq 0 ]; then
            echo "Бэкап источников создан: $APT_REMOTE_PATH"
            rm -f tar_errors.log
        else
            echo -e "${RED}Ошибка при создании бэкапа источников:${NC}"
            cat tar_errors.log
            return
        fi
    else
        sudo tar -czf "$APT_BACKUP" /etc/apt/sources.list /etc/apt/sources.list.d 2>tar_errors.log
        if [ $? -eq 0 ]; then
            echo "Бэкап источников создан: $APT_BACKUP"
            rm -f tar_errors.log
        else
            echo -e "${RED}Ошибка при создании бэкапа источников:${NC}"
            cat tar_errors.log
            return
        fi

        if [ "$BACKUP_DEST" = "2" ]; then
            echo -e "${GREEN}Отправка бэкапа источников на сервер: $REMOTE_DEST${NC}"
            scp "$APT_BACKUP" "$REMOTE_DEST"
            if [ $? -eq 0 ]; then
                echo "Бэкап источников отправлен"
                read -p "Удалить локальную копию? (y/n): " DELETE_LOCAL
                if [ "$DELETE_LOCAL" = "y" ]; then
                    rm -f "$APT_BACKUP"
                    echo "Локальная копия удалена"
                fi
            else
                echo -e "${RED}Ошибка при отправке${NC}"
            fi
        fi
    fi

    # Бэкап каждого пользователя в отдельный архив
    for user in "${SELECTED_USERS[@]}"; do
        USER_HOME="/home/$user"
        if [ ! -d "$USER_HOME" ]; then
            echo -e "${RED}Домашняя директория $USER_HOME не найдена${NC}"
            continue
        fi

        echo -e "${GREEN}Проверка открытых файлов для $user...${NC}"
        if command -v lsof >/dev/null 2>&1; then
            OPEN_FILES=$(sudo lsof +D "$USER_HOME" 2>/dev/null | grep -v '^COMMAND' | awk '{print $NF}' | sort -u)
            if [ -n "$OPEN_FILES" ]; then
                echo -e "${RED}Обнаружены открытые файлы:${NC}"
                PIDS=$(sudo lsof +D "$USER_HOME" 2>/dev/null | grep -v '^COMMAND' | awk '{print $2}' | sort -u)
                echo "$OPEN_FILES" | while read -r file; do
                    echo " - $file"
                    sudo lsof "$file" 2>/dev/null | awk 'NR>1 {print "   Используется процессом: " $1 " (PID: " $2 ")"}'
                done
                read -p "Убить процессы для полного бэкапа $user? (y/n): " KILL_PROCESSES
                if [ "$KILL_PROCESSES" = "y" ]; then
                    echo "Убиваем процессы..."
                    echo "$PIDS" | while read -r pid; do
                        sudo kill -9 "$pid" 2>/dev/null
                        if [ $? -eq 0 ]; then
                            echo "Процесс PID $pid убит"
                        else
                            echo -e "${RED}Не удалось убить PID $pid${NC}"
                        fi
                    done
                    sleep 1
                fi
            fi
        fi

        echo -e "${GREEN}Создание бэкапа для $user...${NC}"
        USER_BACKUP="$BACKUP_DIR/home_backup_${user}_$(date +%Y%m%d_%H%M%S).tar.gz"
        if [ "$BACKUP_DEST" = "3" ]; then
            USER_REMOTE_PATH="$REMOTE_PATH/backups/home_backup_${user}_$(date +%Y%m%d_%H%M%S).tar.gz"
            sudo tar -cz "$USER_HOME" 2>tar_errors.log | ssh "${REMOTE_DEST%%:*}" "cat > $USER_REMOTE_PATH"
            if [ $? -eq 0 ]; then
                echo "Бэкап пользователя $user создан: $USER_REMOTE_PATH"
                rm -f tar_errors.log
            else
                echo -e "${RED}Ошибка при создании бэкапа $user:${NC}"
                cat tar_errors.log
                continue
            fi
        else
            sudo tar -czf "$USER_BACKUP" "$USER_HOME" 2>tar_errors.log
            if [ $? -eq 0 ]; then
                echo "Бэкап пользователя $user создан: $USER_BACKUP"
                rm -f tar_errors.log
            else
                echo -e "${RED}Ошибка при создании бэкапа $user:${NC}"
                cat tar_errors.log
                read -p "Повторить с игнорированием ошибок? (y/n): " RETRY
                if [ "$RETRY" = "y" ]; then
                    sudo tar -czf "$USER_BACKUP" --warning=no-file-changed "$USER_HOME"
                    if [ $? -eq 0 ]; then
                        echo "Бэкап создан: $USER_BACKUP"
                    else
                        echo -e "${RED}Не удалось создать бэкап $user${NC}"
                        continue
                    fi
                else
                    continue
                fi
            fi

            if [ "$BACKUP_DEST" = "2" ]; then
                echo -e "${GREEN}Отправка бэкапа $user на сервер: $REMOTE_DEST${NC}"
                scp "$USER_BACKUP" "$REMOTE_DEST"
                if [ $? -eq 0 ]; then
                    echo "Бэкап $user отправлен"
                    read -p "Удалить локальную копию? (y/n): " DELETE_LOCAL
                    if [ "$DELETE_LOCAL" = "y" ]; then
                        rm -f "$USER_BACKUP"
                        echo "Локальная копия удалена"
                    fi
                else
                    echo -e "${RED}Ошибка при отправке${NC}"
                fi
            fi
        fi
    done
}

# Функция для восстановления бэкапа
restore_backup() {
    echo -e "${GREEN}Доступные локальные бэкапы:${NC}"
    BACKUP_DIR="$LOCAL_BACKUP_DIR/backups"
    BACKUP_FILES=("$BACKUP_DIR"/home_backup_*.tar.gz "$BACKUP_DIR"/apt_sources_backup_*.tar.gz)
    if [ ${#BACKUP_FILES[@]} -eq 0 ] || [ ! -e "${BACKUP_FILES[0]}" ]; then
        echo -e "${RED}Локальные бэкапы не найдены в $BACKUP_DIR${NC}"
        return
    fi

    # Извлечение пользователей и источников из имён файлов бэкапа
    declare -A USER_BACKUPS
    APT_BACKUP=""
    for file in "${BACKUP_FILES[@]}"; do
        if [[ "$file" =~ home_backup_([^_]+)_[0-9]{8}_[0-9]{6}\.tar\.gz ]]; then
            USER="${BASH_REMATCH[1]}"
            USER_BACKUPS["$USER"]="$file"
        elif [[ "$file" =~ apt_sources_backup_[0-9]{8}_[0-9]{6}\.tar\.gz ]]; then
            APT_BACKUP="$file"
        fi
    done

    if [ ${#USER_BACKUPS[@]} -eq 0 ] && [ -z "$APT_BACKUP" ]; then
        echo -e "${RED}Не найдено бэкапов для восстановления${NC}"
        return
    fi

    if [ ${#USER_BACKUPS[@]} -gt 0 ]; then
        echo "Список доступных пользователей для восстановления:"
        i=1
        declare -A USER_MAP
        for user in "${!USER_BACKUPS[@]}"; do
            echo "$i. Пользователь: $user (${USER_BACKUPS[$user]})"
            USER_MAP[$i]="$user"
            ((i++))
        done
    else
        echo "Бэкапы пользователей не найдены"
    fi

    if [ -n "$APT_BACKUP" ]; then
        echo "Бэкап источников пакетов: $APT_BACKUP"
    fi

    echo "q. Вернуться в главное меню"
    read -p "Выберите номер пользователя (или 'q' для отмены): " USER_CHOICE

    if [ "$USER_CHOICE" = "q" ]; then
        echo "Возврат в главное меню."
        return
    fi

    if ! [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] || [ "$USER_CHOICE" -lt 1 ] || [ "$USER_CHOICE" -gt ${#USER_BACKUPS[@]} ]; then
        echo -e "${RED}Неверный выбор пользователя${NC}"
    else
        SELECTED_USER="${USER_MAP[$USER_CHOICE]}"
        SELECTED_BACKUP="${USER_BACKUPS[$SELECTED_USER]}"
        echo -e "${GREEN}Выбран бэкап для пользователя $SELECTED_USER: $SELECTED_BACKUP${NC}"
    fi

    if [ -n "$APT_BACKUP" ]; then
        read -p "Восстановить список пакетов и источники? (y/n): " RESTORE_PKGS
        if [ "$RESTORE_PKGS" = "y" ] && [ -f "$PACKAGE_LIST" ]; then
            echo -e "${GREEN}Восстановление источников пакетов...${NC}"
            sudo tar -xzf "$APT_BACKUP" -C / etc/apt/sources.list etc/apt/sources.list.d
            if [ $? -eq 0 ]; then
                echo "Источники пакетов восстановлены"
            else
                echo -e "${RED}Ошибка при восстановлении источников${NC}"
            fi

            echo -e "${GREEN}Восстановление списка пакетов...${NC}"
            sudo dpkg --set-selections < "$PACKAGE_LIST"
            sudo apt-get -y dselect-upgrade
            if [ $? -eq 0 ]; then
                echo "Список пакетов восстановлен"
            else
                echo -e "${RED}Ошибка при восстановлении пакетов${NC}"
            fi
        fi
    fi

    if [ -n "$SELECTED_USER" ]; then
        read -p "Восстановить домашнюю директорию $SELECTED_USER? (y/n): " RESTORE_HOME
        if [ "$RESTORE_HOME" = "y" ]; then
            echo -e "${GREEN}Восстановление домашней директории $SELECTED_USER...${NC}"
            sudo tar -xzf "$SELECTED_BACKUP" -C / "home/$SELECTED_USER"
            if [ $? -eq 0 ]; then
                echo "Директория пользователя $SELECTED_USER восстановлена"
            else
                echo -e "${RED}Ошибка при восстановлении $SELECTED_USER${NC}"
                return
            fi

            # Проверка и создание пользователя
            if ! id "$SELECTED_USER" >/dev/null 2>&1; then
                echo -e "${RED}Пользователь $SELECTED_USER не существует${NC}"
                read -p "Создать пользователя $SELECTED_USER? (y/n): " CREATE_USER
                if [ "$CREATE_USER" = "y" ]; then
                    sudo useradd -m -d "/home/$SELECTED_USER" -s /bin/bash "$SELECTED_USER"
                    if [ $? -eq 0 ]; then
                        echo "Пользователь $SELECTED_USER создан"
                        sudo chown -R "$SELECTED_USER:$SELECTED_USER" "/home/$SELECTED_USER"
                        read -p "Установить пароль для $SELECTED_USER? (y/n): " SET_PASSWD
                        if [ "$SET_PASSWD" = "y" ]; then
                            sudo passwd "$SELECTED_USER"
                        fi
                    else
                        echo -e "${RED}Ошибка при создании $SELECTED_USER${NC}"
                    fi
                fi
            else
                echo "Пользователь $SELECTED_USER уже существует"
                sudo chown -R "$SELECTED_USER:$SELECTED_USER" "/home/$SELECTED_USER"
            fi
        fi
    fi
}

# Функция для удаления локальных бэкапов
delete_backups() {
    echo -e "${GREEN}Доступные локальные бэкапы:${NC}"
    BACKUP_DIR="$LOCAL_BACKUP_DIR/backups"
    BACKUP_FILES=("$BACKUP_DIR"/home_backup_*.tar.gz "$BACKUP_DIR"/apt_sources_backup_*.tar.gz)
    if [ ${#BACKUP_FILES[@]} -eq 0 ] || [ ! -e "${BACKUP_FILES[0]}" ]; then
        echo -e "${RED}Локальные бэкапы не найдены в $BACKUP_DIR${NC}"
        return
    fi

    for i in "${!BACKUP_FILES[@]}"; do
        DATETIME=$(get_backup_datetime "${BACKUP_FILES[$i]}")
        echo "$((i+1)). ${BACKUP_FILES[$i]} (Создан: $DATETIME)"
    done
    echo "q. Вернуться в главное меню"
    read -p "Введите номера бэкапов для удаления (или 'q'): " CHOICES
    if [ "$CHOICES" = "q" ]; then
        echo "Возврат в главное меню."
        return
    fi

    IFS=' ' read -r -a CHOICE_ARRAY <<< "$CHOICES"
    for CHOICE in "${CHOICE_ARRAY[@]}"; do
        if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#BACKUP_FILES[@]} ]; then
            echo -e "${RED}Неверный номер: $CHOICE${NC}"
            continue
        fi
        SELECTED_BACKUP="${BACKUP_FILES[$((CHOICE-1))]}"
        echo -e "${GREEN}Удаление: $SELECTED_BACKUP${NC}"
        rm -f "$SELECTED_BACKUP"
        if [ $? -eq 0 ]; then
            echo "Бэкап удалён"
        else
            echo -e "${RED}Ошибка при удалении${NC}"
        fi
    done
}

# Функция для извлечения даты и времени из имени файла
get_backup_datetime() {
    local filename=$(basename "$1")
    local datetime_part=$(echo "$filename" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
    if [ -n "$datetime_part" ]; then
        local date_part=${datetime_part:0:8}
        local time_part=${datetime_part:9:6}
        echo "${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
    else
        echo "Не удалось определить время"
    fi
}

# Основное меню
while true; do
    clear
    echo -e "${GREEN}=== Меню управления бэкапами ===${NC}"
    echo "1. Создать бэкап"
    echo "2. Развернуть бэкап (локальный)"
    echo "3. Удалить локальные бэкапы"
    echo "4. Перезагрузить ПК"
    echo "5. Выйти"
    read -p "Выберите опцию (1-5): " choice

    case $choice in
        1)
            create_backup
            read -p "Нажмите Enter для продолжения..."
            ;;
        2)
            restore_backup
            read -p "Нажмите Enter для продолжения..."
            ;;
        3)
            delete_backups
            read -p "Нажмите Enter для продолжения..."
            ;;
        4)
            echo "Перезагрузка ПК..."
            sudo reboot
            ;;
        5)
            echo "Выход из скрипта."
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            sleep 2
            ;;
    esac
done
