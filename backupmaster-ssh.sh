
#!/bin/bash

# Цвета для оформления
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Основной путь
SCRIPT_DIR=$(pwd)  # Директория, где запускается скрипт
BACKUP_DIR="$SCRIPT_DIR/backups"  # Папка для локальных бэкапов

# Функция для проверки и установки пакета
check_and_install_package() {
    local package="$1"
    if ! command -v "$package" >/dev/null 2>&1; then
        echo -e "${RED}Утилита $package не установлена. Устанавливаем...${NC}"
        sudo apt update
        sudo apt install -y "$package"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Утилита $package успешно установлена${NC}"
        else
            echo -e "${RED}Не удалось установить $package. Установите вручную: 'sudo apt install $package'${NC}"
            exit 1
        fi
    fi
}

# Проверка зависимостей
check_and_install_package "tar"
check_and_install_package "du"
check_and_install_package "df"
check_and_install_package "lsof"
check_and_install_package "ssh"
check_and_install_package "scp"
check_and_install_package "sshpass"

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

# Функция для проверки занятых файлов и убийства процессов
check_and_kill_open_files() {
    local dir="$1"
    OPEN_FILES=$(sudo lsof +D "$dir" 2>/dev/null | grep -v '^COMMAND' | awk '{print $NF}' | sort -u)
    if [ -n "$OPEN_FILES" ]; then
        echo -e "${RED}Обнаружены открытые файлы в $dir:${NC}"
        declare -A FILE_PIDS
        declare -A FILE_PROCS
        while read -r line; do
            pid=$(echo "$line" | awk '{print $2}')
            proc=$(echo "$line" | awk '{print $1}')
            file=$(echo "$line" | awk '{print $NF}')
            FILE_PIDS["$file"]="${FILE_PIDS["$file"]} $pid"
            FILE_PROCS["$file"]="${FILE_PROCS["$file"]} $proc (PID: $pid)"
        done < <(sudo lsof +D "$dir" 2>/dev/null | grep -v '^COMMAND')

        for file in "${!FILE_PIDS[@]}"; do
            echo " - $file"
            echo "   Занят процессами:${FILE_PROCS["$file"]}"
        done

        read -p "Убить процессы, использующие эти файлы? (y/n/q для возврата в меню): " KILL_PROCESSES
        if [ "$KILL_PROCESSES" = "q" ]; then
            echo "Возврат в главное меню."
            return 1
        fi
        if [ "$KILL_PROCESSES" = "y" ]; then
            echo "Убиваем процессы..."
            for file in "${!FILE_PIDS[@]}"; do
                IFS=' ' read -r -a PIDS <<< "${FILE_PIDS["$file"]}"
                for pid in "${PIDS[@]}"; do
                    sudo kill -9 "$pid" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo "Процесс PID $pid убит"
                    else
                        echo -e "${RED}Не удалось убить PID $pid${NC}"
                    fi
                done
            done
            sleep 1  # Даём время на завершение процессов
        fi
    fi
    return 0
}

# Функция для локального бэкапа пользователей
backup_users_local() {
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
    echo "q. Вернуться в главное меню"
    read -p "Выберите номер пользователя, 'all' или 'q': " USER_CHOICE

    if [ "$USER_CHOICE" = "q" ]; then
        echo "Возврат в главное меню."
        return
    fi

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

    # Создание бэкапов с проверкой занятых файлов
    for user in "${SELECTED_USERS[@]}"; do
        USER_HOME="/home/$user"
        if [ ! -d "$USER_HOME" ]; then
            echo -e "${RED}Директория $USER_HOME не найдена${NC}"
            continue
        fi

        # Проверка занятых файлов
        check_and_kill_open_files "$USER_HOME"
        if [ $? -eq 1 ]; then
            return  # Возврат в главное меню, если выбрано 'q'
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

# Функция для бэкапа пользователей на удалённый сервер через SSH
backup_users_ssh() {
    echo -e "${GREEN}Настройка подключения к удалённому серверу...${NC}"
    read -p "Введите имя сервера (например, example.com): " SERVER
    if [ -z "$SERVER" ]; then
        echo -e "${RED}Имя сервера не указано${NC}"
        return
    fi
    read -p "Введите логин: " LOGIN
    if [ -z "$LOGIN" ]; then
        echo -e "${RED}Логин не указан${NC}"
        return
    fi
    read -s -p "Введите пароль: " PASSWORD
    echo
    if [ -z "$PASSWORD" ]; then
        echo -e "${RED}Пароль не указан${NC}"
        return
    fi
    read -p "Введите путь на сервере (например, /backups): " REMOTE_PATH
    if [ -z "$REMOTE_PATH" ]; then
        echo -e "${RED}Путь на сервере не указан${NC}"
        return
    fi

    # Проверка подключения с автоматическим принятием ключа
    echo -e "${GREEN}Проверка подключения к $LOGIN@$SERVER...${NC}"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$LOGIN@$SERVER" "echo Connection OK" 2>ssh_errors.log
    if [ $? -ne 0 ]; then
        echo -e "${RED}Не удалось подключиться к $LOGIN@$SERVER:${NC}"
        cat ssh_errors.log
        rm -f ssh_errors.log
        return
    fi
    rm -f ssh_errors.log

    # Создание директории на удалённом сервере
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$LOGIN@$SERVER" "mkdir -p '$REMOTE_PATH'" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}Не удалось создать директорию $REMOTE_PATH на сервере${NC}"
        return
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
    echo "q. Вернуться в главное меню"
    read -p "Выберите номер пользователя, 'all' или 'q': " USER_CHOICE

    if [ "$USER_CHOICE" = "q" ]; then
        echo "Возврат в главное меню."
        return
    fi

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

    # Создание бэкапов и отправка на сервер
    for user in "${SELECTED_USERS[@]}"; do
        USER_HOME="/home/$user"
        if [ ! -d "$USER_HOME" ]; then
            echo -e "${RED}Директория $USER_HOME не найдена${NC}"
            continue
        fi

        # Проверка занятых файлов
        check_and_kill_open_files "$USER_HOME"
        if [ $? -eq 1 ]; then
            return  # Возврат в главное меню, если выбрано 'q'
        fi

        BACKUP_SIZE=$(estimate_size "$USER_HOME")
        echo -e "${GREEN}Бэкап пользователя $user...${NC}"
        echo "Примерный размер бэкапа: $BACKUP_SIZE МБ"
        TEMP_BACKUP="/tmp/home_backup_${user}_$TIMESTAMP.tar.gz"
        sudo tar -czf "$TEMP_BACKUP" "$USER_HOME" 2>tar_errors.log
        if [ $? -eq 0 ]; then
            echo "Бэкап создан локально: $TEMP_BACKUP"
            REMOTE_BACKUP="$REMOTE_PATH/home_backup_${user}_$TIMESTAMP.tar.gz"
            sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no "$TEMP_BACKUP" "$LOGIN@$SERVER:$REMOTE_BACKUP" 2>scp_errors.log
            if [ $? -eq 0 ]; then
                echo "Бэкап успешно отправлен на $LOGIN@$SERVER:$REMOTE_BACKUP"
                sudo rm -f "$TEMP_BACKUP"  # Удаляем временный файл
                rm -f tar_errors.log
            else
                echo -e "${RED}Ошибка при отправке бэкапа на сервер:${NC}"
                cat scp_errors.log
                sudo rm -f "$TEMP_BACKUP"
                rm -f tar_errors.log scp_errors.log
                continue
            fi
        else
            echo -e "${RED}Ошибка при бэкапе $user:${NC}"
            cat tar_errors.log
            sudo rm -f "$TEMP_BACKUP"
            rm -f tar_errors.log
            continue
        fi
    done
}

# Функция для локального восстановления бэкапов пользователей
restore_users_local() {
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
                    read -p "Создать пользователя $USER? (y/n/q для возврата в меню): " CREATE_USER
                    if [ "$CREATE_USER" = "q" ]; then
                        echo "Возврат в главное меню."
                        return
                    fi
                    if [ "$CREATE_USER" = "y" ]; then
                        sudo useradd -m -d "/home/$USER" -s /bin/bash "$USER"
                        if [ $? -eq 0 ]; then
                            echo "Пользователь $USER создан"
                            sudo chown -R "$USER:$USER" "/home/$USER"  # Установка прав
                            read -p "Установить пароль для $USER? (y/n/q для возврата в меню): " SET_PASSWD
                            if [ "$SET_PASSWD" = "q" ]; then
                                echo "Возврат в главное меню."
                                return
                            fi
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

# Функция для восстановления бэкапов с удалённого сервера через SSH
restore_users_ssh() {
    echo -e "${GREEN}Настройка подключения к удалённому серверу...${NC}"
    read -p "Введите имя сервера (например, example.com): " SERVER
    if [ -z "$SERVER" ]; then
        echo -e "${RED}Имя сервера не указано${NC}"
        return
    fi
    read -p "Введите логин: " LOGIN
    if [ -z "$LOGIN" ]; then
        echo -e "${RED}Логин не указан${NC}"
        return
    fi
    read -s -p "Введите пароль: " PASSWORD
    echo
    if [ -z "$PASSWORD" ]; then
        echo -e "${RED}Пароль не указан${NC}"
        return
    fi
    read -p "Введите путь на сервере (например, /backups): " REMOTE_PATH
    if [ -z "$REMOTE_PATH" ]; then
        echo -e "${RED}Путь на сервере не указан${NC}"
        return
    fi

    # Проверка подключения с автоматическим принятием ключа
    echo -e "${GREEN}Проверка подключения к $LOGIN@$SERVER...${NC}"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$LOGIN@$SERVER" "echo Connection OK" 2>ssh_errors.log
    if [ $? -ne 0 ]; then
        echo -e "${RED}Не удалось подключиться к $LOGIN@$SERVER:${NC}"
        cat ssh_errors.log
        rm -f ssh_errors.log
        return
    fi
    rm -f ssh_errors.log

    # Получение списка бэкапов с сервера
    echo -e "${GREEN}Получение списка бэкапов с $LOGIN@$SERVER:$REMOTE_PATH...${NC}"
    USER_BACKUPS=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$LOGIN@$SERVER" "ls -1 '$REMOTE_PATH'/home_backup_*.tar.gz 2>/dev/null")
    if [ -z "$USER_BACKUPS" ]; then
        echo -e "${RED}Бэкапы не найдены в $REMOTE_PATH на сервере${NC}"
        return
    fi

    # Преобразование списка в массив
    IFS=$'\n' read -r -d '' -a BACKUP_ARRAY <<< "$USER_BACKUPS"

    echo -e "${GREEN}Доступные бэкапы пользователей:${NC}"
    i=1
    declare -a BACKUP_LIST
    for file in "${BACKUP_ARRAY[@]}"; do
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
        SELECTED_BACKUPS=("${BACKUP_LIST[@]}")
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
        TEMP_BACKUP="/tmp/$(basename "$backup")"
        sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no "$LOGIN@$SERVER:$backup" "$TEMP_BACKUP" 2>scp_errors.log
        if [ $? -eq 0 ]; then
            BACKUP_SIZE=$(ls -l "$TEMP_BACKUP" | awk '{print int($5 / 1024 / 1024)}')  # Размер файла в МБ
            echo "Размер бэкапа $backup: $BACKUP_SIZE МБ"
            if [ "$BACKUP_SIZE" -gt "$FREE_SPACE" ]; then
                echo -e "${RED}Недостаточно свободного места для восстановления $backup (требуется $BACKUP_SIZE МБ, доступно $FREE_SPACE МБ)${NC}"
                sudo rm -f "$TEMP_BACKUP"
                return
            fi
        else
            echo -e "${RED}Ошибка при загрузке $backup с сервера:${NC}"
            cat scp_errors.log
            sudo rm -f "$TEMP_BACKUP"
            rm -f scp_errors.log
            return
        fi
    done

    # Восстановление выбранных бэкапов
    for backup in "${SELECTED_BACKUPS[@]}"; do
        TEMP_BACKUP="/tmp/$(basename "$backup")"
        if [[ "$backup" =~ home_backup_(.+)_[0-9]{8}_[0-9]{6}\.tar\.gz ]]; then
            USER="${BASH_REMATCH[1]}"
            echo -e "${GREEN}Восстановление пользователя $USER...${NC}"
            sudo tar -xzf "$TEMP_BACKUP" -C / "home/$USER"
            if [ $? -eq 0 ]; then
                echo "Домашняя директория $USER восстановлена"
                sudo rm -f "$TEMP_BACKUP"  # Удаляем временный файл
                
                # Проверка существования пользователя
                if ! id "$USER" >/dev/null 2>&1; then
                    echo -e "${RED}Пользователь $USER не существует в системе${NC}"
                    read -p "Создать пользователя $USER? (y/n/q для возврата в меню): " CREATE_USER
                    if [ "$CREATE_USER" = "q" ]; then
                        echo "Возврат в главное меню."
                        return
                    fi
                    if [ "$CREATE_USER" = "y" ]; then
                        sudo useradd -m -d "/home/$USER" -s /bin/bash "$USER"
                        if [ $? -eq 0 ]; then
                            echo "Пользователь $USER создан"
                            sudo chown -R "$USER:$USER" "/home/$USER"  # Установка прав
                            read -p "Установить пароль для $USER? (y/n/q для возврата в меню): " SET_PASSWD
                            if [ "$SET_PASSWD" = "q" ]; then
                                echo "Возврат в главное меню."
                                return
                            fi
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
                sudo rm -f "$TEMP_BACKUP"
                continue
            fi
        else
            echo -e "${RED}Не удалось распознать пользователя в $backup${NC}"
            sudo rm -f "$TEMP_BACKUP"
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
    echo "1. Создать локальный бэкап пользователей"
    echo "2. Создать бэкап пользователей на SSH-сервер"
    echo "3. Восстановить локальный бэкап пользователей"
    echo "4. Восстановить бэкап пользователей с SSH-сервера"
    echo "5. Удалить локальные бэкапы"
    echo "6. Выйти"
    read -p "Выберите опцию (1-6): " choice

    case $choice in
        1)
            backup_users_local
            read -p "Нажмите Enter для продолжения..."
            ;;
        2)
            backup_users_ssh
            read -p "Нажмите Enter для продолжения..."
            ;;
        3)
            restore_users_local
            read -p "Нажмите Enter для продолжения..."
            ;;
        4)
            restore_users_ssh
            read -p "Нажмите Enter для продолжения..."
            ;;
        5)
            delete_backups
            read -p "Нажмите Enter для продолжения..."
            ;;
        6)
            echo "Выход из скрипта."
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            sleep 2
            ;;
    esac
done
