#!/bin/bash

# Цвета для оформления
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Основные пути и файлы
LOCAL_BACKUP_DIR=$(pwd)  # Локальная директория по умолчанию
PACKAGE_LIST="$LOCAL_BACKUP_DIR/installed_packages.txt"
BACKUP_FILES=("$LOCAL_BACKUP_DIR"/home_backup_*.tar.gz)  # Массив локальных бэкапов
LATEST_BACKUP=$(ls -t "$LOCAL_BACKUP_DIR"/home_backup_*.tar.gz 2>/dev/null | head -n 1)

# Проверка доступности локальной директории
if [ ! -w "$LOCAL_BACKUP_DIR" ]; then
    echo -e "${RED}Нет прав на запись в $LOCAL_BACKUP_DIR. Запустите скрипт с достаточными правами.${NC}"
    exit 1
fi

# Проверка наличия lsof
if ! command -v lsof >/dev/null 2>&1; then
    echo -e "${RED}Утилита lsof не установлена. Установите её с помощью 'sudo apt install lsof' для проверки открытых файлов.${NC}"
fi

# Функция для создания бэкапа
create_backup() {
    echo -e "${GREEN}Куда сохранить бэкап?${NC}"
    echo "1. Локально ($LOCAL_BACKUP_DIR)"
    echo "2. Удалённый сервер (через SSH, локально+scp)"
    echo "3. Удалённый сервер (прямой бэкап через SSH)"
    read -p "Выберите вариант (1-3): " BACKUP_DEST

    # Установка пути для бэкапа
    HOME_BACKUP="$LOCAL_BACKUP_DIR/home_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    REMOTE_DEST=""
    REMOTE_PATH=""

    if [ "$BACKUP_DEST" = "2" ] || [ "$BACKUP_DEST" = "3" ]; then
        read -p "Введите SSH-адрес (например, user@host:/path/to/backup): " REMOTE_DEST
        ssh -q -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_DEST%%:*}" "exit" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}Не удалось подключиться к удалённому серверу. Проверьте адрес и доступность SSH.${NC}"
            return
        fi
        REMOTE_PATH="${REMOTE_DEST#*:}/home_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    elif [ "$BACKUP_DEST" != "1" ]; then
        echo -e "${RED}Неверный выбор. Бэкап будет создан локально.${NC}"
        BACKUP_DEST="1"
    fi

    echo -e "${GREEN}Создание списка установленных пакетов...${NC}"
    dpkg --get-selections > "$PACKAGE_LIST"
    if [ $? -eq 0 ]; then
        echo "Список пакетов сохранен в $PACKAGE_LIST"
    else
        echo -e "${RED}Ошибка при создании списка пакетов${NC}"
        exit 1
    fi

    # Проверка открытых файлов
    echo -e "${GREEN}Проверка открытых файлов в /home...${NC}"
    if command -v lsof >/dev/null 2>&1; then
        OPEN_FILES=$(sudo lsof +D /home 2>/dev/null | grep -v '^COMMAND' | awk '{print $NF}' | sort -u)
        if [ -n "$OPEN_FILES" ]; then
            echo -e "${RED}Обнаружены открытые файлы в /home:${NC}"
            echo "$OPEN_FILES" | while read -r file; do
                echo " - $file"
                sudo lsof "$file" 2>/dev/null | awk 'NR>1 {print "   Используется процессом: " $1 " (PID: " $2 ")"}'
            done
            read -p "Продолжить создание бэкапа несмотря на открытые файлы? (y/n): " CONTINUE
            if [ "$CONTINUE" != "y" ]; then
                echo "Создание бэкапа отменено."
                return
            fi
        else
            echo "Открытых файлов не найдено."
        fi
    else
        echo "Проверка пропущена, так как lsof не установлен."
    fi

    echo -e "${GREEN}Создание бэкапа директории /home...${NC}"
    echo "Внимание: если файлы в /home изменяются, это может вызвать ошибки."

    if [ "$BACKUP_DEST" = "3" ]; then
        # Прямой бэкап через SSH
        sudo tar -cz /home 2>tar_errors.log | ssh "${REMOTE_DEST%%:*}" "cat > $REMOTE_PATH"
        if [ $? -eq 0 ]; then
            echo "Бэкап успешно создан на удалённом сервере: $REMOTE_PATH"
            rm -f tar_errors.log
        else
            echo -e "${RED}Ошибка при создании бэкапа на удалённом сервере:${NC}"
            cat tar_errors.log
            echo -e "${RED}Совет: проверьте соединение или повторите с игнорированием ошибок.${NC}"
            exit 1
        fi
    else
        # Локальный бэкап или локальный+scp
        sudo tar -czf "$HOME_BACKUP" /home 2>tar_errors.log
        if [ $? -eq 0 ]; then
            echo "Бэкап успешно создан локально: $HOME_BACKUP"
            rm -f tar_errors.log
        else
            echo -e "${RED}Ошибка при создании бэкапа:${NC}"
            cat tar_errors.log
            echo -e "${RED}Совет: попробуйте остановить активные процессы или исключить изменяющиеся файлы.${NC}"
            read -p "Повторить попытку с игнорированием проблемных файлов? (y/n): " RETRY
            if [ "$RETRY" = "y" ]; then
                sudo tar -czf "$HOME_BACKUP" --warning=no-file-changed /home
                if [ $? -eq 0 ]; then
                    echo "Бэкап создан с игнорированием измененных файлов: $HOME_BACKUP"
                else
                    echo -e "${RED}Не удалось создать бэкап даже с игнорированием ошибок${NC}"
                    exit 1
                fi
            else
                exit 1
            fi
        fi

        if [ "$BACKUP_DEST" = "2" ]; then
            echo -e "${GREEN}Отправка бэкапа на удалённый сервер: $REMOTE_DEST${NC}"
            scp "$HOME_BACKUP" "$REMOTE_DEST"
            if [ $? -eq 0 ]; then
                echo "Бэкап успешно отправлен на $REMOTE_DEST"
                read -p "Удалить локальную копию бэкапа? (y/n): " DELETE_LOCAL
                if [ "$DELETE_LOCAL" = "y" ]; then
                    rm -f "$HOME_BACKUP"
                    echo "Локальная копия удалена"
                fi
            else
                echo -e "${RED}Ошибка при отправке бэкапа на удалённый сервер${NC}"
            fi
        fi
    fi
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

# Функция для выбора и восстановления бэкапа (локальные)
restore_backup() {
    echo -e "${GREEN}Доступные локальные бэкапы:${NC}"
    BACKUP_FILES=("$LOCAL_BACKUP_DIR"/home_backup_*.tar.gz)
    if [ ${#BACKUP_FILES[@]} -eq 0 ] || [ ! -e "${BACKUP_FILES[0]}" ]; then
        echo -e "${RED}Локальные бэкапы не найдены${NC}"
        return
    fi

    for i in "${!BACKUP_FILES[@]}"; do
        DATETIME=$(get_backup_datetime "${BACKUP_FILES[$i]}")
        echo "$((i+1)). ${BACKUP_FILES[$i]} (Создан: $DATETIME)"
    done

    read -p "Выберите номер бэкапа для восстановления (или 'q' для отмены): " CHOICE
    if [ "$CHOICE" = "q" ]; then
        echo "Отмена восстановления."
        return
    fi

    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#BACKUP_FILES[@]} ]; then
        echo -e "${RED}Неверный выбор${NC}"
        return
    fi

    SELECTED_BACKUP="${BACKUP_FILES[$((CHOICE-1))]}"
    echo -e "${GREEN}Выбран бэкап: $SELECTED_BACKUP${NC}"

    read -p "Восстановить список пакетов? (y/n): " RESTORE_PKGS
    if [ "$RESTORE_PKGS" = "y" ] && [ -f "$PACKAGE_LIST" ]; then
        echo -e "${GREEN}Восстановление списка пакетов...${NC}"
        sudo dpkg --set-selections < "$PACKAGE_LIST"
        sudo apt-get -y dselect-upgrade
        if [ $? -ne 0 ]; then
            echo -e "${RED}Ошибка при восстановлении пакетов${NC}"
        fi
    fi

    read -p "Восстановить /home из выбранного бэкапа? (y/n): " RESTORE_HOME
    if [ "$RESTORE_HOME" = "y" ]; then
        echo -e "${GREEN}Восстановление /home из $SELECTED_BACKUP...${NC}"
        sudo tar -xzf "$SELECTED_BACKUP" -C /
        if [ $? -eq 0 ]; then
            echo "Восстановление завершено"
        else
            echo -e "${RED}Ошибка при восстановлении${NC}"
        fi
    fi
}

# Функция для удаления локальных бэкапов
delete_backups() {
    echo -e "${GREEN}Доступные локальные бэкапы для удаления:${NC}"
    BACKUP_FILES=("$LOCAL_BACKUP_DIR"/home_backup_*.tar.gz)
    if [ ${#BACKUP_FILES[@]} -eq 0 ] || [ ! -e "${BACKUP_FILES[0]}" ]; then
        echo -e "${RED}Локальные бэкапы не найдены${NC}"
        return
    fi

    for i in "${!BACKUP_FILES[@]}"; do
        DATETIME=$(get_backup_datetime "${BACKUP_FILES[$i]}")
        echo "$((i+1)). ${BACKUP_FILES[$i]} (Создан: $DATETIME)"
    done

    read -p "Введите номера бэкапов для удаления через пробел (или 'q' для отмены): " CHOICES
    if [ "$CHOICES" = "q" ]; then
        echo "Отмена удаления."
        return
    fi

    IFS=' ' read -r -a CHOICE_ARRAY <<< "$CHOICES"
    for CHOICE in "${CHOICE_ARRAY[@]}"; do
        if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#BACKUP_FILES[@]} ]; then
            echo -e "${RED}Неверный номер: $CHOICE. Пропускаем.${NC}"
            continue
        fi
        SELECTED_BACKUP="${BACKUP_FILES[$((CHOICE-1))]}"
        echo -e "${GREEN}Удаление: $SELECTED_BACKUP${NC}"
        rm -f "$SELECTED_BACKUP"
        if [ $? -eq 0 ]; then
            echo "Бэкап успешно удалён"
        else
            echo -e "${RED}Ошибка при удалении $SELECTED_BACKUP${NC}"
        fi
    done
}

# Проверка последнего локального бэкапа при запуске
if [ -n "$LATEST_BACKUP" ] && [ -f "$LATEST_BACKUP" ]; then
    clear
    DATETIME=$(get_backup_datetime "$LATEST_BACKUP")
    echo -e "${GREEN}Найден последний локальный бэкап: $LATEST_BACKUP (Создан: $DATETIME)${NC}"
    read -p "Хотите восстановить его прямо сейчас? (y/n): " RESTORE_NOW
    if [ "$RESTORE_NOW" = "y" ]; then
        BACKUP_FILES=("$LATEST_BACKUP")
        restore_backup
    fi
fi

# Основное меню
while true; do
    clear
    echo -e "${GREEN}=== Меню управления бэкапами ===${NC}"
    if [ -n "$LATEST_BACKUP" ]; then
        DATETIME=$(get_backup_datetime "$LATEST_BACKUP")
        echo "Последний локальный бэкап: $LATEST_BACKUP (Создан: $DATETIME)"
    else
        echo "Последний локальный бэкап: не найден"
    fi
    echo "1. Создать бэкап"
    echo "2. Развернуть бэкап (локальный)"
    echo "3. Удалить локальные бэкапы"
    echo "4. Перезагрузить ПК"
    echo "5. Выйти"
    read -p "Выберите опцию (1-5): " choice

    case $choice in
        1)
            create_backup
            LATEST_BACKUP=$(ls -t "$LOCAL_BACKUP_DIR"/home_backup_*.tar.gz 2>/dev/null | head -n 1)
            read -p "Нажмите Enter для продолжения..."
            ;;
        2)
            restore_backup
            read -p "Нажмите Enter для продолжения..."
            ;;
        3)
            delete_backups
            LATEST_BACKUP=$(ls -t "$LOCAL_BACKUP_DIR"/home_backup_*.tar.gz 2>/dev/null | head -n 1)
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
            echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
            sleep 2
            ;;
    esac
done
