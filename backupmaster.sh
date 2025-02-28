#!/bin/bash

# Цвета для оформления
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Основной путь
SCRIPT_DIR=$(pwd)  # Директория, где запускается скрипт
BACKUP_DIR="$SCRIPT_DIR/backups"  # Папка для бэкапов

# Проверка зависимостей
if ! command -v tar >/dev/null 2>&1; then
    echo -e "${RED}Утилита tar не установлена. Установите её: 'sudo apt install tar'.${NC}"
    exit 1
fi
if ! command -v du >/dev/null 2>&1; then
    echo -e "${RED}Утилита du не установлена. Установите её: 'sudo apt install coreutils'.${NC}"
    exit 1
fi
if ! command -v df >/dev/null 2>&1; then
    echo -e "${RED}Утилита df не установлена. Установите её: 'sudo apt install coreutils'.${NC}"
    exit 1
fi

# Функция для оценки размера папки (в МБ)
estimate_size() {
    local path="$1"
    if [ -d "$path" ]; then
        local size=$(sudo du -sb "$path" 2>/dev/null | awk '{print $1}')  # Размер в байтах
        local compressed_bytes=$((size / 3))  # Примерный коэффициент сжатия
        local size_mb=$((compressed_bytes / 1024 / 1024))  # Перевод в МБ
        echo "$size_mb"
    else
        echo "0"
    fi
}

# Функция для получения свободного места в корневом разделе (в МБ)
get_free_space() {
    local free_space=$(df -B1M / | tail -n 1 | awk '{print $4}')  # Свободное место в МБ
    echo "$free_space"
}

# Функция для получения списка пользователей с домашними директориями в /home
get_users() {
    awk -F: '$3 >= 1000 && $6 ~ /^\/home\// && $1 !~ /^(nobody|nogroup)$/ {print $1}' /etc/passwd | sort -u
}

# Функция для создания бэкапа пользователей
backup_users() {
    # Создание папки backups, если её нет
    if [ ! -d "$BACKUP_DIR" ]; then
        sudo mkdir -p "$BACKUP_DIR"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Не удалось создать папку $BACKUP_DIR${NC}"
            return
        fi
    fi
    if [ ! -w "$BACKUP_DIR" ]; then
        sudo chmod u+w "$BACKUP_DIR"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Нет прав на запись в $BACKUP_DIR и не удалось их изменить${NC}"
            return
        fi
    fi

    echo -e "${GREEN}Поиск пользователей...${NC}"
    USERS=($(get_users))
    if [ ${#USERS[@]} -eq 0 ]; then
        echo -e "${RED}Пользователи с UID >= 1000 и директориями в /home не найдены${NC}"
        return
    fi

    echo "Список пользователей для бэкапа:"
    for i in "${!USERS[@]}"; do
        USER_SIZE=$(estimate_size "/home/${USERS[$i]}")
        echo "$((i+1)). Пользователь: ${USERS[$i]} (примерный размер бэкапа: ${USER_SIZE} МБ)"
    done
    echo "all. Забэкапить всех"
    read -p "Выберите номер пользователя или 'all': " USER_CHOICE

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

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)

    # Создание бэкапов с предварительной оценкой размера
    for user in "${SELECTED_USERS[@]}"; do
        USER_HOME="/home/$user"
        if [ ! -d "$USER_HOME" ]; then
            echo -e "${RED}Директория $USER_HOME не найдена${NC}"
            continue
        fi

        BACKUP_SIZE=$(estimate_size "$USER_HOME")
        echo -e "${GREEN}Бэкап пользователя $user...${NC}"
        echo "Примерный размер бэкапа: $BACKUP_SIZE МБ"
        USER_BACKUP="$BACKUP_DIR/home_backup_${user}_$TIMESTAMP.tar.gz"
        sudo tar -czf "$USER_BACKUP" "$USER_HOME" 2>tar_errors.log
        if [ $? -eq 0 ]; then
            echo "Домашняя директория $user забэкаплена: $USER_BACKUP"
            rm -f tar_errors.log
        else
            echo -e "${RED}Ошибка при бэкапе $user:${NC}"
            cat tar_errors.log
            rm -f tar_errors.log
            continue
        fi
    done
}

# Функция для восстановления бэкапов пользователей
restore_users() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}Папка бэкапов $BACKUP_DIR не найдена${NC}"
        return
    fi

    USER_BACKUPS=("$BACKUP_DIR"/home_backup_*.tar.gz)

    echo -e "${GREEN}Поиск бэкапов в $BACKUP_DIR...${NC}"
    echo "Количество найденных бэкапов: ${#USER_BACKUPS[@]}"
    echo "Список бэкапов:"
    for file in "${USER_BACKUPS[@]}"; do
        echo " - $file"
    done

    if [ ${#USER_BACKUPS[@]} -eq 0 ] || [ ! -e "${USER_BACKUPS[0]}" ]; then
        echo -e "${RED}Бэкапы пользователей не найдены в $BACKUP_DIR${NC}"
        return
    fi

    echo -e "${GREEN}Доступные бэкапы пользователей:${NC}"
    i=1
    declare -a BACKUP_LIST
    for file in "${USER_BACKUPS[@]}"; do
        if [[ "$file" =~ home_backup_(.+)_[0-9]{8}_[0-9]{6}\.tar\.gz ]]; then
            USER="${BASH_REMATCH[1]}"
            DATETIME=$(get_backup_datetime "$file")
            echo "$i. Пользователь: $USER ($file, Создан: $DATETIME)"
            BACKUP_LIST[$i]="$file"
            ((i++))
        else
            echo "$i. Нераспознанный файл: $file"
            BACKUP_LIST[$i]="$file"
            ((i++))
        fi
    done
    TOTAL_BACKUPS=$((i - 1))

    if [ $TOTAL_BACKUPS -eq 0 ]; then
        echo -e "${RED}Не найдено подходящих бэкапов для восстановления${NC}"
        return
    fi

    echo "all. Восстановить все"
    echo "q. Вернуться в главное меню"
    read -p "Выберите номер бэкапа, 'all' или 'q': " CHOICE

    if [ "$CHOICE" = "q" ]; then
        echo "Возврат в главное меню."
        return
    fi

    if [ "$CHOICE" = "all" ]; then
        SELECTED_BACKUPS=("${USER_BACKUPS[@]}")
        echo "Выбрано восстановление всех бэкапов"
    else
        if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt $TOTAL_BACKUPS ]; then
            echo -e "${RED}Неверный выбор${NC}"
            return
        fi
        SELECTED_BACKUPS=("${BACKUP_LIST[$CHOICE]}")
        echo "Выбран бэкап: ${SELECTED_BACKUPS[0]}"
    fi

    # Проверка свободного места перед восстановлением
    FREE_SPACE=$(get_free_space)
    echo "Свободное место на диске: $FREE_SPACE МБ"
    for backup in "${SELECTED_BACKUPS[@]}"; do
        BACKUP_SIZE=$(ls -l "$backup" | awk '{print int($5 / 1024 / 1024)}')  # Размер файла в МБ
        echo "Размер бэкапа $backup: $BACKUP_SIZE МБ"
        if [ "$BACKUP_SIZE" -gt "$FREE_SPACE" ]; then
            echo -e "${RED}Недостаточно свободного места для восстановления $backup (требуется $BACKUP_SIZE МБ, доступно $FREE_SPACE МБ)${NC}"
            return
        fi
    done

    # Восстановление выбранных бэкапов
    for backup in "${SELECTED_BACKUPS[@]}"; do
        if [[ "$backup" =~ home_backup_(.+)_[0-9]{8}_[0-9]{6}\.tar\.gz ]]; then
            USER="${BASH_REMATCH[1]}"
            echo -e "${GREEN}Восстановление пользователя $USER...${NC}"
            sudo tar -xzf "$backup" -C / "home/$USER"
            if [ $? -eq 0 ]; then
                echo "Домашняя директория $USER восстановлена"
                
                # Проверка существования пользователя
                if ! id "$USER" >/dev/null 2>&1; then
                    echo -e "${RED}Пользователь $USER не существует в системе${NC}"
                    read -p "Создать пользователя $USER? (y/n): " CREATE_USER
                    if [ "$CREATE_USER" = "y" ]; then
                        sudo useradd -m -d "/home/$USER" -s /bin/bash "$USER"
                        if [ $? -eq 0 ]; then
                            echo "Пользователь $USER создан"
                            sudo chown -R "$USER:$USER" "/home/$USER"  # Установка прав
                            read -p "Установить пароль для $USER? (y/n): " SET_PASSWD
                            if [ "$SET_PASSWD" = "y" ]; then
                                sudo passwd "$USER"
                            else
                                echo "Пароль для $USER не установлен"
                            fi
                        else
                            echo -e "${RED}Ошибка при создании пользователя $USER${NC}"
                        fi
                    else
                        echo "Пользователь $USER не создан"
                    fi
                else
                    echo "Пользователь $USER уже существует в системе"
                    sudo chown -R "$USER:$USER" "/home/$USER"  # Установка прав для существующего пользователя
                fi
            else
                echo -e "${RED}Ошибка при восстановлении $USER${NC}"
                continue
            fi
        else
            echo -e "${RED}Не удалось распознать пользователя в $backup${NC}"
            continue
        fi
    done
}

# Функция для удаления бэкапов
delete_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}Папка бэкапов $BACKUP_DIR не найдена${NC}"
        return
    fi

    BACKUP_FILES=("$BACKUP_DIR"/home_backup_*.tar.gz)
    if [ ${#BACKUP_FILES[@]} -eq 0 ] || [ ! -e "${BACKUP_FILES[0]}" ]; then
        echo -e "${RED}Бэкапы не найдены в $BACKUP_DIR${NC}"
        return
    fi

    echo -e "${GREEN}Доступные бэкапы:${NC}"
    for i in "${!BACKUP_FILES[@]}"; do
        DATETIME=$(get_backup_datetime "${BACKUP_FILES[$i]}")
        echo "$((i+1)). ${BACKUP_FILES[$i]} (Создан: $DATETIME)"
    done
    echo "q. Вернуться в главное меню"
    read -p "Введите номера бэкапов для удаления через пробел (или 'q'): " CHOICES

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
        sudo rm -f "$SELECTED_BACKUP"
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

# Главное меню
while true; do
    clear
    echo -e "${GREEN}=== Меню управления бэкапами ===${NC}"
    echo "1. Создать бэкап пользователей"
    echo "2. Восстановить бэкап пользователей"
    echo "3. Удалить бэкапы"
    echo "4. Выйти"
    read -p "Выберите опцию (1-4): " choice

    case $choice in
        1)
            backup_users
            read -p "Нажмите Enter для продолжения..."
            ;;
        2)
            restore_users
            read -p "Нажмите Enter для продолжения..."
            ;;
        3)
            delete_backups
            read -p "Нажмите Enter для продолжения..."
            ;;
        4)
            echo "Выход из скрипта."
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            sleep 2
            ;;
    esac
done
