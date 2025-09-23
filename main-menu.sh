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

# Функция для красивого заголовка с волнами
show_header() {
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                                                              ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██████╗ ███████╗███╗   ███╗███╗   ██╗ █████╗ ${NC}                ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██╔══██╗██╔════╝████╗ ████║████╗  ██║██╔══██╗${NC}                ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██████╔╝█████╗  ██╔████╔██║██╔██╗ ██║███████║${NC}                ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██╔══██╗██╔══╝  ██║╚██╔╝██║██║╚██╗██║██╔══██║${NC}                ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██║  ██║███████╗██║ ╚═╝ ██║██║ ╚████║██║  ██║${NC}                ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝${NC}                ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                                                              ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}            ${GRAY}Management Suite by Spakieone${NC}                   ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                                                              ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Главное меню
show_main_menu() {
    show_header
    
    # Меню с выравниванием
    echo -e "${BOLD}${WHITE}┌─ 🛠️  ИНСТРУМЕНТЫ УПРАВЛЕНИЯ ─────────────────────────┐${NC}"
    echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}1.${NC} ${YELLOW}🧩 Remnawave Panel${NC}     ${GRAY}┃${NC} ${WHITE}Панель управления${NC}       ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}2.${NC} ${YELLOW}🖥️ RemnaNode Core${NC}      ${GRAY}┃${NC} ${WHITE}Узлы и сервисы${NC}          ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}3.${NC} ${YELLOW}🛡️ Reality Caddy${NC}       ${GRAY}┃${NC} ${WHITE}Маскировка трафика${NC}      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}4.${NC} ${YELLOW}🚀 Network Tools${NC}       ${GRAY}┃${NC} ${WHITE}Диагностика сети${NC}        ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}5.${NC} ${YELLOW}📈 Node Exporter${NC}       ${GRAY}┃${NC} ${WHITE}Мониторинг системы${NC}      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}6.${NC} ${YELLOW}📊 System Status${NC}       ${GRAY}┃${NC} ${WHITE}Детальная информация${NC}    ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}${WHITE}┌─  ВЫХОД ─────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}0.${NC} ${WHITE}Завершение работы${NC}                                ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${WHITE}Выберите инструмент:${NC} "
    echo -n "   ➤ "
}

# Функция для вызова скриптов
call_script() {
    local script_name=$1
    shift  # Убираем первый аргумент (имя скрипта), остальные - параметры
    local script_path="./$script_name"
    
    # Проверяем разные возможные пути
    if [ -f "$script_path" ]; then
        echo -e "${YELLOW}Запуск $script_name...${NC}"
        echo ""
        bash "$script_path" "$@"
        echo ""
        echo -e "${GREEN}Скрипт $script_name завершен.${NC}"
        read -p "Нажмите Enter для возврата в главное меню..."
    elif [ -f "script/scripts-main/$script_name" ]; then
        echo -e "${YELLOW}Запуск $script_name...${NC}"
        echo ""
        bash "script/scripts-main/$script_name" "$@"
        echo ""
        echo -e "${GREEN}Скрипт $script_name завершен.${NC}"
        read -p "Нажмите Enter для возврата в главное меню..."
    else
        # Если файл не найден локально, скачиваем с GitHub
        echo -e "${YELLOW}Скачиваем $script_name с GitHub...${NC}"
        local github_url="https://raw.githubusercontent.com/Spakieone/Remna/main/$script_name"
        
        echo -e "${YELLOW}Запуск $script_name...${NC}"
        echo ""
        # Скачиваем скрипт во временный файл и запускаем с параметрами
        local temp_script="/tmp/$script_name"
        curl -s "$github_url" -o "$temp_script"
        chmod +x "$temp_script"
        bash "$temp_script" "$@"
        rm -f "$temp_script"
        echo ""
        echo -e "${GREEN}Скрипт $script_name завершен.${NC}"
        read -p "Нажмите Enter для возврата в главное меню..."
    fi
}

# Функция системного статуса
show_system_status() {
    show_header
    echo -e "${BOLD}${WHITE}📊 Детальный статус системы${NC}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo ""
    
    # Проверка Docker
    echo -e "${WHITE}🐳 Docker:${NC}"
    if systemctl is-active --quiet docker; then
        echo -e "   ${GREEN}✅ Статус: Запущен${NC}"
        local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1 || echo "Неизвестно")
        echo -e "   ${GRAY}📦 Версия: $docker_version${NC}"
    else
        echo -e "   ${RED}❌ Статус: Остановлен${NC}"
    fi
    
    # Проверка Docker Compose
    echo -e "${WHITE}🔧 Docker Compose:${NC}"
    if command -v docker-compose &> /dev/null || command -v docker compose &> /dev/null; then
        echo -e "   ${GREEN}✅ Доступен${NC}"
    else
        echo -e "   ${RED}❌ Не найден${NC}"
    fi
    
    echo ""
    
    # Системные ресурсы
    echo -e "${WHITE}💾 Системные ресурсы:${NC}"
    
    # Использование диска
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    local disk_used=$(df -h / | tail -1 | awk '{print $3}')
    local disk_total=$(df -h / | tail -1 | awk '{print $2}')
    echo -e "   ${CYAN}💿 Диск:${NC} $disk_used / $disk_total (${disk_usage}%)"
    
    # Память
    local mem_info=$(free -h | grep Mem)
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_total=$(echo $mem_info | awk '{print $2}')
    local mem_percent=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    echo -e "   ${CYAN}🧠 Память:${NC} $mem_used / $mem_total (${mem_percent}%)"
    
    # CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    echo -e "   ${CYAN}⚡ CPU:${NC} ${cpu_usage}% загрузка"
    
    echo ""
    
    # Активные порты
    echo -e "${WHITE}🌐 Активные порты Remna:${NC}"
    local ports=$(netstat -tlnp 2>/dev/null | grep -E ':(3000|3010|8080|9443|9050|9051|5002|9100)' | head -5)
    if [ -n "$ports" ]; then
        echo "$ports" | while read line; do
            local port=$(echo $line | awk '{print $4}' | cut -d':' -f2)
            local service=$(echo $line | awk '{print $7}' | cut -d'/' -f2)
            echo -e "   ${GREEN}🔌 Порт $port:${NC} $service"
        done
    else
        echo -e "   ${GRAY}📭 Нет активных портов Remna${NC}"
    fi
    
    echo ""
    
    # Время работы системы
    echo -e "${WHITE}⏰ Время работы:${NC}"
    local uptime_info=$(uptime | sed 's/.*up //' | sed 's/,.*//')
    echo -e "   ${GRAY}🕐 Система работает: $uptime_info${NC}"
    
    echo ""
    echo -e "${GRAY}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    read -p "Нажмите Enter для возврата в главное меню..."
}

# Основной цикл
while true; do
    show_main_menu
    read -r choice
    
    case $choice in
        1) 
            echo -e "${CYAN}🧩 Запуск управления Remnawave...${NC}"
            call_script "remnawave.sh" 
            ;;
        2) 
            echo -e "${YELLOW}🖥️  Запуск управления RemnaNode...${NC}"
            call_script "remnanode.sh" 
            ;;
        3) 
            echo -e "${PURPLE}🛡️  Запуск инструментов Reality Caddy...${NC}"
            call_script "selfsteal.sh" 
            ;;
        4) 
            echo -e "${BLUE}🌐 Запуск сетевых инструментов...${NC}"
            call_script "wtm.sh" 
            ;;
        5) 
            echo -e "${GREEN}📈 Запуск Node Exporter...${NC}"
            call_script "install_node_exporter.sh" "menu"
            ;;
        6) 
            echo -e "${CYAN}📊 Загрузка статуса системы...${NC}"
            show_system_status 
            ;;
        0) 
            echo ""
            echo -e "${BOLD}${GREEN}👋 До свидания! Спасибо за использование Remna Management Suite!${NC}"
            echo -e "${GRAY}   Удачного дня! 🚀${NC}"
            echo ""
            exit 0
            ;;
        *) 
            echo -e "${RED}❌ Неверный выбор! Пожалуйста, выберите опцию от 0 до 6.${NC}"
            sleep 2
            ;;
    esac
done
