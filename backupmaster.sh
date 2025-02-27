#!/bin/bash

# Цвета для оформления
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Основные пути и файлы
BACKUP_DIR="/backup"
PACKAGE_LIST="$BACKUP_DIR/installed_packages.txt"
HOME_BACKUP="$BACKUP_DIR/home_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

# Проверка и создание директории для бэкапов
if [ ! -d "$BACKUP_DIR" ]; then
    echo "Создаю директорию для бэкапов: $BACKUP_DIR"
    sudo mkdir -p "$BACKUP_DIR"
    sudo chmod 700 "$BACKUP_DIR"
fi

# Функция для создания бэкапа
create_backup() {
    echo -e "${GREEN}Создание списка установленных пакетов...${NC}"
    dpkg --get-selections > "$PACKAGE_LIST"
    if [ $? -eq 0 ]; then
        echo "Список пакетов сохранен в $PACKAGE_LIST"
    else
        echo -e "${RED}Ошибка при создании списка пакетов${NC}"
        exit 1
    fi

    echo -e "${GREEN}Создание бэкапа директории /home...${NC}"
    sudo tar -czf "$HOME_BACKUP" /home
    if [ $? -eq 0 ]; then
        echo "Бэкап успешно создан: $HOME_BACKUP"
    else
        echo -e "${RED}Ошибка при создании бэкапа${NC}"
        exit 1
    fi
}

# Функция для восстановления бэкапа
restore_backup() {
    echo "Доступные бэкапы:"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}Бэкапы не найдены${NC}"
        return
    fi

    read -p "Введите полный путь к архиву для восстановления: " RESTORE_FILE
    if [ -f "$RESTORE_FILE" ]; then
        echo -e "${GREEN}Восстановление /home из $RESTORE_FILE...${NC}"
        sudo tar -xzf "$RESTORE_FILE" -C /
        if [ $? -eq 0 ]; then
            echo "Восстановление завершено"
        else
            echo -e "${RED}Ошибка при восстановлении${NC}"
        fi
    else
        echo -e "${RED}Файл не найден${NC}"
    fi

    read -p "Восстановить список пакетов? (y/n): " RESTORE_PKGS
    if [ "$RESTORE_PKGS" = "y" ] && [ -f "$PACKAGE_LIST" ]; then
        echo -e "${GREEN}Восстановление списка пакетов...${NC}"
        sudo dpkg --set-selections < "$PACKAGE_LIST"
        sudo apt-get -y dselect-upgrade
    fi
}

# Основное меню
while true; do
    clear
    echo -e "${GREEN}=== Меню управления бэкапами ===${NC}"
    echo "1. Создать бэкап"
    echo "2. Развернуть бэкап"
    echo "3. Перезагрузить ПК"
    echo "4. Выйти"
    read -p "Выберите опцию (1-4): " choice

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
            echo "Перезагрузка ПК..."
            sudo reboot
            ;;
        4)
            echo "Выход из скрипта."
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
            sleep 2
            ;;
    esac
done
