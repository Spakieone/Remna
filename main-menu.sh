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
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██████╗ ███████╗███╗   ███╗███╗   ██╗ █████╗ ${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██╔══██╗██╔════╝████╗ ████║████╗  ██║██╔══██╗${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██████╔╝█████╗  ██╔████╔██║██╔██╗ ██║███████║${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██╔══██╗██╔══╝  ██║╚██╔╝██║██║╚██╗██║██╔══██║${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██║  ██║███████╗██║ ╚═╝ ██║██║ ╚████║██║  ██║${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                                                              ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}       ${GRAY}Management Suite by Spakieone${NC}                          ${BOLD}${CYAN}║${NC}"
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
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}5.${NC} ${YELLOW}📈 Node Exporter + Node API${NC} ${GRAY}┃${NC} ${WHITE}Мониторинг и управление${NC}  ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}6.${NC} ${YELLOW}📊 System Status${NC}       ${GRAY}┃${NC} ${WHITE}Детальная информация${NC}    ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}7.${NC} ${YELLOW}⚙️ Настройка ноды${NC}       ${GRAY}┃${NC} ${WHITE}UFW и IPv6${NC}              ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}${WHITE}┌─ 💡 ПОЛЕЗНЫЕ КОМАНДЫ ────────────────────────────────┐${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}8.${NC} ${YELLOW}💡 Полезные команды${NC}    ${GRAY}┃${NC} ${WHITE}Системные команды${NC}       ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}${WHITE}┌─🚪ВЫХОД ─────────────────────────────────────────────┐${NC}"
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

# Меню Node Exporter + Node API
show_node_exporter_menu() {
    while true; do
        show_header
        echo -e "${BOLD}${WHITE}┌─ 📈 NODE EXPORTER + NODE API ────────────────────────┐${NC}"
        echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}1.${NC} ${YELLOW}📊 Установить Node Exporter${NC}    ${GRAY}┃${NC} ${WHITE}Мониторинг системы${NC}      ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}2.${NC} ${YELLOW}🔧 Установить Node API${NC}        ${GRAY}┃${NC} ${WHITE}Управление нодами${NC}        ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}3.${NC} ${YELLOW}🔄 Перезапустить Node Exporter${NC} ${GRAY}┃${NC} ${WHITE}Перезапуск сервиса${NC}      ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}4.${NC} ${YELLOW}🔄 Перезапустить Node API${NC}      ${GRAY}┃${NC} ${WHITE}Перезапуск сервиса${NC}      ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}5.${NC} ${YELLOW}📈 Статус Node Exporter${NC}       ${GRAY}┃${NC} ${WHITE}Проверка работы${NC}         ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}6.${NC} ${YELLOW}🔧 Статус Node API${NC}            ${GRAY}┃${NC} ${WHITE}Проверка работы${NC}         ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${BOLD}${WHITE}┌─🚪ВЫХОД ─────────────────────────────────────────────┐${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}0.${NC} ${WHITE}Назад в главное меню${NC}                        ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${WHITE}Выберите действие:${NC} "
        echo -n "   ➤ "
        
        read -r choice
        
        case $choice in
            1) 
                echo -e "${CYAN}📊 Установка Node Exporter...${NC}"
                call_script "install_node_exporter.sh" "menu"
                ;;
            2) 
                echo -e "${YELLOW}🔧 Установка Node API...${NC}"
                call_script "install_node_api.sh" "menu"
                ;;
            3) 
                echo -e "${BLUE}🔄 Перезапуск Node Exporter...${NC}"
                sudo systemctl restart node_exporter
                echo -e "${GREEN}✅ Node Exporter перезапущен${NC}"
                read -p "Нажмите Enter для продолжения..."
                ;;
            4) 
                echo -e "${PURPLE}🔄 Перезапуск Node API...${NC}"
                sudo systemctl restart node-api
                echo -e "${GREEN}✅ Node API перезапущен${NC}"
                read -p "Нажмите Enter для продолжения..."
                ;;
            5) 
                echo -e "${CYAN}📈 Статус Node Exporter...${NC}"
                sudo systemctl status node_exporter --no-pager
                read -p "Нажмите Enter для продолжения..."
                ;;
            6) 
                echo -e "${YELLOW}🔧 Статус Node API...${NC}"
                sudo systemctl status node-api --no-pager
                read -p "Нажмите Enter для продолжения..."
                ;;
            0) 
                return
                ;;
            *) 
                echo -e "${RED}❌ Неверный выбор! Пожалуйста, выберите опцию от 0 до 6.${NC}"
                sleep 2
                ;;
        esac
    done
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
            echo -e "${GREEN}📈 Запуск Node Exporter + Node API...${NC}"
            show_node_exporter_menu
            ;;
        6) 
            echo -e "${CYAN}📊 Загрузка статуса системы...${NC}"
            show_system_status 
            ;;
        7) 
            echo -e "${PURPLE}⚙️  Запуск настройки ноды...${NC}"
            call_script "node-config.sh" 
            ;;
        8) 
            echo -e "${YELLOW}💡 Запуск полезных команд...${NC}"
            call_script "useful_commands.sh" 
            ;;
        0) 
            echo ""
            echo -e "${BOLD}${GREEN}👋 До свидания! Спасибо за использование Remna Management Suite!${NC}"
            echo -e "${GRAY}   Удачного дня! 🚀${NC}"
            echo ""
            exit 0
            ;;
        *) 
            echo -e "${RED}❌ Неверный выбор! Пожалуйста, выберите опцию от 0 до 8.${NC}"
            sleep 2
            ;;
    esac
done
