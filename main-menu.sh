#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функция для красивого заголовка
show_header() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}    Remnawave Management Suite${NC}"
    echo -e "${CYAN}================================${NC}"
    echo ""
}

# Главное меню
show_main_menu() {
    show_header
    echo -e "${GREEN}1.${NC} Управление Remnawave"
    echo -e "${GREEN}2.${NC} Управление RemnaNode"
    echo -e "${GREEN}3.${NC} Инструменты Reality"
    echo -e "${GREEN}4.${NC} Сетевые инструменты"
    echo -e "${GREEN}5.${NC} Установка Node Exporter"
    echo -e "${GREEN}6.${NC} Статус системы"
    echo -e "${RED}7.${NC} Выход"
    echo ""
    echo -n "Выберите опцию (1-7): "
}

# Функция для вызова скриптов
call_script() {
    local script_name=$1
    local script_path="./$script_name"
    
    # Проверяем разные возможные пути
    if [ -f "$script_path" ]; then
        echo -e "${YELLOW}Запуск $script_name...${NC}"
        echo ""
        bash "$script_path"
        echo ""
        echo -e "${GREEN}Скрипт $script_name завершен.${NC}"
        read -p "Нажмите Enter для возврата в главное меню..."
    elif [ -f "script/scripts-main/$script_name" ]; then
        echo -e "${YELLOW}Запуск $script_name...${NC}"
        echo ""
        bash "script/scripts-main/$script_name"
        echo ""
        echo -e "${GREEN}Скрипт $script_name завершен.${NC}"
        read -p "Нажмите Enter для возврата в главное меню..."
    else
        # Если файл не найден локально, скачиваем с GitHub
        echo -e "${YELLOW}Скачиваем $script_name с GitHub...${NC}"
        local github_url="https://raw.githubusercontent.com/Spakieone/Remna/main/$script_name"
        
        echo -e "${YELLOW}Запуск $script_name...${NC}"
        echo ""
        bash <(curl -s "$github_url")
        echo ""
        echo -e "${GREEN}Скрипт $script_name завершен.${NC}"
        read -p "Нажмите Enter для возврата в главное меню..."
    fi
}

# Функция системного статуса
show_system_status() {
    show_header
    echo -e "${BLUE}=== Статус системы ===${NC}"
    echo ""
    
    # Проверка Docker
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓${NC} Docker: Запущен"
    else
        echo -e "${RED}✗${NC} Docker: Остановлен"
    fi
    
    # Проверка Docker Compose
    if command -v docker-compose &> /dev/null || command -v docker compose &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker Compose: Доступен"
    else
        echo -e "${RED}✗${NC} Docker Compose: Не найден"
    fi
    
    # Проверка портов
    echo -e "${BLUE}Активные порты:${NC}"
    netstat -tlnp 2>/dev/null | grep -E ':(3000|3010|8080|9443|9050|9051)' | head -5 || echo "Нет активных портов"
    
    # Использование диска
    echo -e "${BLUE}Использование диска:${NC}"
    df -h / | tail -1
    
    # Память
    echo -e "${BLUE}Использование памяти:${NC}"
    free -h | grep Mem
    
    # Загрузка системы
    echo -e "${BLUE}Загрузка системы:${NC}"
    uptime
    
    echo ""
    read -p "Нажмите Enter для возврата в главное меню..."
}

# Основной цикл
while true; do
    show_main_menu
    read -r choice
    
    case $choice in
        1) call_script "remnawave.sh" ;;
        2) call_script "remnanode.sh" ;;
        3) call_script "selfsteal.sh" ;;
        4) call_script "wtm.sh" ;;
        5) call_script "install_node_exporter.sh" ;;
        6) show_system_status ;;
        7) 
            echo -e "${GREEN}До свидания!${NC}"
            exit 0
            ;;
        *) 
            echo -e "${RED}Неверный выбор! Попробуйте снова.${NC}"
            sleep 2
            ;;
    esac
done
