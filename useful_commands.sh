#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Функция для красивого заголовка
show_header() {
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                                                          ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}            ${WHITE}💡 ПОЛЕЗНЫЕ КОМАНДЫ СИСТЕМЫ${NC}            ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                                                          ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Функция для отображения меню
show_menu() {
    show_header
    
    echo -e "${BOLD}${WHITE}┌─ 🛠️  СИСТЕМНЫЕ КОМАНДЫ ─────────────────────────────────┐${NC}"
    echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}1.${NC} ${YELLOW}⚡ Обновить систему${NC}         ${GRAY}┃${NC} ${WHITE}apt update && upgrade${NC}      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}2.${NC} ${YELLOW}🌍 Тест на локацию${NC}          ${GRAY}┃${NC} ${WHITE}IP region check${NC}           ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}3.${NC} ${YELLOW}🚫 Проверка блокировок${NC}      ${GRAY}┃${NC} ${WHITE}IP.Check.Place${NC}            ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}4.${NC} ${YELLOW}🇷🇺 Скорость к РФ${NC}            ${GRAY}┃${NC} ${WHITE}Russian providers${NC}         ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}5.${NC} ${YELLOW}🌐 Скорость к зарубежным${NC}     ${GRAY}┃${NC} ${WHITE}International providers${NC}   ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}6.${NC} ${YELLOW}📱 Проверка Instagram${NC}       ${GRAY}┃${NC} ${WHITE}Audio block check${NC}        ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}${WHITE}┌─ 🚪 ВЫХОД ────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}0.${NC} ${WHITE}Назад в главное меню${NC}                        ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${WHITE}Выберите команду:${NC} "
    echo -n "   ➤ "
}

# Функция теста на локацию
test_location() {
    echo -e "${YELLOW}🌍 Тест на локацию...${NC}"
    echo ""
    
    echo -e "${BLUE}Выполняем: wget -qO - \"https://raw.githubusercontent.com/vernette/ipregion/refs/heads/master/ipregion.sh\" | bash${NC}"
    echo ""
    
    wget -qO - "https://raw.githubusercontent.com/vernette/ipregion/refs/heads/master/ipregion.sh" | bash
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Функция проверки блокировок
check_blocks() {
    echo -e "${YELLOW}🚫 Проверка IP сервера на блокировки...${NC}"
    echo ""
    
    echo -e "${BLUE}Выполняем: bash <(curl -Ls IP.Check.Place) -l en${NC}"
    echo ""
    
    bash <(curl -Ls IP.Check.Place) -l en
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Функция проверки скорости к российским провайдерам
test_speed_ru() {
    echo -e "${YELLOW}🇷🇺 Проверка скорости к российским провайдерам...${NC}"
    echo ""
    
    echo -e "${BLUE}Выполняем: wget -qO- speedtest.artydev.ru | bash${NC}"
    echo ""
    
    wget -qO- speedtest.artydev.ru | bash
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Функция проверки скорости к зарубежным провайдерам
test_speed_intl() {
    echo -e "${YELLOW}🌐 Проверка скорости к зарубежным провайдерам...${NC}"
    echo ""
    
    echo -e "${BLUE}Выполняем: wget -qO- bench.sh | bash${NC}"
    echo ""
    
    wget -qO- bench.sh | bash
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Функция проверки Instagram
check_instagram() {
    echo -e "${YELLOW}📱 Проверка блокировки аудио в Instagram...${NC}"
    echo ""
    
    echo -e "${BLUE}Выполняем: bash <(curl -L -s https://bench.openode.xyz/checker_inst.sh)${NC}"
    echo ""
    
    bash <(curl -L -s https://bench.openode.xyz/checker_inst.sh)
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Функция обновления системы
update_system() {
    echo -e "${YELLOW}⚡ Обновление системы...${NC}"
    echo ""
    
    echo -e "${BLUE}Выполняем: sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean${NC}"
    echo ""
    
    sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean
    
    echo ""
    echo -e "${GREEN}✅ Обновление завершено!${NC}"
    read -p "Нажмите Enter для продолжения..."
}

# Функция показа процессов
show_processes() {
    echo -e "${YELLOW}🔍 Показать запущенные процессы...${NC}"
    echo ""
    
    echo -e "${BLUE}Топ процессов по использованию CPU:${NC}"
    ps aux --sort=-%cpu | head -10
    
    echo ""
    echo -e "${BLUE}Топ процессов по использованию памяти:${NC}"
    ps aux --sort=-%mem | head -10
    
    echo ""
    echo -e "${BLUE}Docker контейнеры:${NC}"
    docker ps 2>/dev/null || echo -e "${RED}Docker не запущен${NC}"
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Основной цикл
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) 
            update_system
            ;;
        2) 
            test_location
            ;;
        3) 
            check_blocks
            ;;
        4) 
            test_speed_ru
            ;;
        5) 
            test_speed_intl
            ;;
        6) 
            check_instagram
            ;;
        0) 
            echo ""
            echo -e "${BOLD}${GREEN}👋 Возврат в главное меню...${NC}"
            echo ""
            exit 0
            ;;
        *) 
            echo -e "${RED}❌ Неверный выбор! Пожалуйста, выберите опцию от 0 до 6.${NC}"
            sleep 2
            ;;
    esac
done
