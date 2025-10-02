#!/bin/bash

# Скрипт массового обновления Node API на всех нодах
# Mass Node API Update Script

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

# Список нод для обновления
NODES=(
    "217.144.187.104"  # GERMANY
    "77.110.105.82"    # RU1
    "93.188.206.70"    # Kazahstan
    "82.117.84.236"    # FIN
    "77.110.127.56"    # USA
    "83.147.253.12"    # NL
)

# Токен для Node API (должен быть одинаковый на всех нодах)
NODE_API_TOKEN="jfwfQ4RrVMdCspg8alk"

# Функция для красивого заголовка
show_header() {
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                                                              ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██╗  ██╗ ██████╗ ██████╗ ███████╗    █████╗ ██████╗ ██╗${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██║  ██║██╔═══██╗██╔══██╗██╔════╝   ██╔══██╗██╔══██╗██║${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}███████║██║   ██║██║  ██║█████╗     ███████║██████╔╝██║${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██╔══██║██║   ██║██║  ██║██╔══╝     ██╔══██║██╔═══╝ ██║${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}██║  ██║╚██████╔╝██████╔╝███████╗   ██║  ██║██║     ██║${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝   ╚═╝  ╚═╝╚═╝     ╚═╝${NC}               ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                                                              ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}       ${GRAY}Mass Node API Update Script${NC}                        ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                                                              ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Функция для вывода сообщений
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Функция для проверки подключения к ноде
check_node_connection() {
    local node=$1
    if ping -c 1 -W 5 "$node" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Функция для обновления Node API на одной ноде
update_node_api() {
    local node=$1
    local node_name=$2
    
    echo -e "${BOLD}${WHITE}┌─ 🔄 Обновление Node API на $node_name ($node) ─────────────┐${NC}"
    echo ""
    
    # Проверяем подключение
    if ! check_node_connection "$node"; then
        error "❌ Нода $node недоступна!"
        return 1
    fi
    
    log "📡 Подключение к ноде $node..."
    
    # Останавливаем Node API
    log "⏹️  Остановка Node API..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$node" "systemctl stop node-api" 2>/dev/null
    
    # Скачиваем и устанавливаем обновленный скрипт
    log "📥 Скачивание обновленного Node API..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$node" "
        # Создаем директорию если не существует
        mkdir -p /home/node-manager/node-api
        
        # Скачиваем обновленный скрипт
        curl -s https://raw.githubusercontent.com/your-repo/script/scripts-main/enhanced_node_api.py -o /home/node-manager/node-api/node_api.py
        
        # Устанавливаем права
        chmod +x /home/node-manager/node-api/node_api.py
        chown node-manager:node-manager /home/node-manager/node-api/node_api.py
        
        # Обновляем systemd сервис с новым токеном
        cat > /etc/systemd/system/node-api.service << 'EOF'
[Unit]
Description=Enhanced Node API Server v2.0.0
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/home/node-manager/node-api
Environment=\"NODE_API_TOKEN=$NODE_API_TOKEN\"
Environment=\"NODE_SERVICES=node_exporter,tblocker\"
ExecStart=/usr/bin/python3 /home/node-manager/node-api/node_api.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        # Перезагружаем systemd и запускаем сервис
        systemctl daemon-reload
        systemctl enable node-api
        systemctl start node-api
        
        # Ждем запуска
        sleep 3
        
        # Проверяем статус
        if systemctl is-active --quiet node-api; then
            echo '✅ Node API v2.0.0 запущен успешно!'
        else
            echo '❌ Ошибка запуска Node API'
            systemctl status node-api --no-pager
        fi
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "✅ Node API на $node_name обновлен успешно!"
        
        # Проверяем API
        log "🔍 Проверка API..."
        if curl -s -H "Authorization: Bearer $NODE_API_TOKEN" "http://$node:8080/health" >/dev/null 2>&1; then
            echo -e "   ${GREEN}✅ API отвечает${NC}"
        else
            echo -e "   ${RED}❌ API не отвечает${NC}"
        fi
    else
        error "❌ Ошибка обновления Node API на $node_name"
    fi
    
    echo ""
    echo -e "${BOLD}${WHITE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Функция для проверки статуса всех нод
check_all_nodes() {
    echo -e "${BOLD}${WHITE}┌─ 📊 Проверка статуса всех нод ─────────────────────────────┐${NC}"
    echo ""
    
    for i in "${!NODES[@]}"; do
        node="${NODES[$i]}"
        case $i in
            0) node_name="GERMANY" ;;
            1) node_name="RU1" ;;
            2) node_name="KAZAKHSTAN" ;;
            3) node_name="FIN" ;;
            4) node_name="USA" ;;
            5) node_name="NL" ;;
            *) node_name="NODE-$i" ;;
        esac
        
        echo -e "${WHITE}🔍 Проверка $node_name ($node):${NC}"
        
        # Проверяем подключение
        if check_node_connection "$node"; then
            echo -e "   ${GREEN}✅ Пинг: OK${NC}"
            
            # Проверяем Node API
            if curl -s -H "Authorization: Bearer $NODE_API_TOKEN" "http://$node:8080/health" >/dev/null 2>&1; then
                echo -e "   ${GREEN}✅ Node API: OK${NC}"
                
                # Получаем версию API
                version=$(curl -s -H "Authorization: Bearer $NODE_API_TOKEN" "http://$node:8080/health" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 2>/dev/null)
                if [ -n "$version" ]; then
                    echo -e "   ${CYAN}📋 Версия: $version${NC}"
                fi
            else
                echo -e "   ${RED}❌ Node API: НЕ ОТВЕЧАЕТ${NC}"
            fi
        else
            echo -e "   ${RED}❌ Пинг: НЕДОСТУПНА${NC}"
        fi
        
        echo ""
    done
    
    echo -e "${BOLD}${WHITE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Главное меню
show_menu() {
    while true; do
        show_header
        echo -e "${BOLD}${WHITE}┌─ 🔧 МАССОВОЕ ОБНОВЛЕНИЕ NODE API ────────────────────────┐${NC}"
        echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}1.${NC} ${YELLOW}🔄 Обновить все ноды${NC}              ${GRAY}┃${NC} ${WHITE}Массовое обновление${NC}     ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}2.${NC} ${YELLOW}📊 Проверить статус всех нод${NC}       ${GRAY}┃${NC} ${WHITE}Проверка состояния${NC}     ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}3.${NC} ${YELLOW}🔧 Обновить конкретную ноду${NC}         ${GRAY}┃${NC} ${WHITE}Выборочное обновление${NC}  ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}4.${NC} ${YELLOW}📋 Показать список нод${NC}              ${GRAY}┃${NC} ${WHITE}Список всех нод${NC}        ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${BOLD}${WHITE}┌─🚪ВЫХОД ─────────────────────────────────────────────┐${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}0.${NC} ${WHITE}Выход${NC}                                    ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${WHITE}Выберите действие:${NC} "
        echo -n "   ➤ "
        
        read -r choice
        
        case $choice in
            1) 
                echo -e "${BOLD}${YELLOW}🔄 Начинаем массовое обновление всех нод...${NC}"
                echo ""
                
                success_count=0
                total_count=${#NODES[@]}
                
                for i in "${!NODES[@]}"; do
                    node="${NODES[$i]}"
                    case $i in
                        0) node_name="GERMANY" ;;
                        1) node_name="RU1" ;;
                        2) node_name="KAZAKHSTAN" ;;
                        3) node_name="FIN" ;;
                        4) node_name="USA" ;;
                        5) node_name="NL" ;;
                        *) node_name="NODE-$i" ;;
                    esac
                    
                    if update_node_api "$node" "$node_name"; then
                        ((success_count++))
                    fi
                    
                    echo ""
                done
                
                echo -e "${BOLD}${GREEN}📊 Результаты обновления:${NC}"
                echo -e "${GREEN}   ✅ Успешно обновлено: $success_count из $total_count${NC}"
                echo -e "${RED}   ❌ Ошибок: $((total_count - success_count))${NC}"
                echo ""
                read -p "Нажмите Enter для продолжения..."
                ;;
            2) 
                check_all_nodes
                read -p "Нажмите Enter для продолжения..."
                ;;
            3) 
                echo -e "${BOLD}${WHITE}┌─ 🔧 Выберите ноду для обновления ─────────────────────┐${NC}"
                echo ""
                for i in "${!NODES[@]}"; do
                    node="${NODES[$i]}"
                    case $i in
                        0) node_name="GERMANY" ;;
                        1) node_name="RU1" ;;
                        2) node_name="KAZAKHSTAN" ;;
                        3) node_name="FIN" ;;
                        4) node_name="USA" ;;
                        5) node_name="NL" ;;
                        *) node_name="NODE-$i" ;;
                    esac
                    echo -e "${GREEN}$((i+1)).${NC} ${WHITE}$node_name${NC} (${CYAN}$node${NC})"
                done
                echo ""
                echo -e "${GREEN}0.${NC} ${WHITE}Назад${NC}"
                echo ""
                echo -n -e "${WHITE}Выберите ноду: ${NC}"
                read -r node_choice
                
                if [[ "$node_choice" =~ ^[0-9]+$ ]] && [ "$node_choice" -ge 1 ] && [ "$node_choice" -le "${#NODES[@]}" ]; then
                    node_index=$((node_choice-1))
                    node="${NODES[$node_index]}"
                    case $node_index in
                        0) node_name="GERMANY" ;;
                        1) node_name="RU1" ;;
                        2) node_name="KAZAKHSTAN" ;;
                        3) node_name="FIN" ;;
                        4) node_name="USA" ;;
                        5) node_name="NL" ;;
                        *) node_name="NODE-$node_index" ;;
                    esac
                    
                    update_node_api "$node" "$node_name"
                    read -p "Нажмите Enter для продолжения..."
                elif [ "$node_choice" = "0" ]; then
                    continue
                else
                    echo -e "${RED}❌ Неверный выбор!${NC}"
                    sleep 2
                fi
                ;;
            4) 
                echo -e "${BOLD}${WHITE}┌─ 📋 Список всех нод ─────────────────────────────────┐${NC}"
                echo ""
                for i in "${!NODES[@]}"; do
                    node="${NODES[$i]}"
                    case $i in
                        0) node_name="GERMANY" ;;
                        1) node_name="RU1" ;;
                        2) node_name="KAZAKHSTAN" ;;
                        3) node_name="FIN" ;;
                        4) node_name="USA" ;;
                        5) node_name="NL" ;;
                        *) node_name="NODE-$i" ;;
                    esac
                    echo -e "${GREEN}$((i+1)).${NC} ${WHITE}$node_name${NC} - ${CYAN}$node${NC}"
                done
                echo ""
                echo -e "${BOLD}${WHITE}└─────────────────────────────────────────────────────────────┘${NC}"
                echo ""
                read -p "Нажмите Enter для продолжения..."
                ;;
            0) 
                echo -e "${GREEN}👋 До свидания!${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}❌ Неверный выбор! Пожалуйста, выберите опцию от 0 до 4.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Основная логика
if [ "$1" = "menu" ]; then
    show_menu
elif [ "$1" = "update-all" ]; then
    show_header
    echo -e "${BOLD}${YELLOW}🔄 Автоматическое обновление всех нод...${NC}"
    echo ""
    
    success_count=0
    total_count=${#NODES[@]}
    
    for i in "${!NODES[@]}"; do
        node="${NODES[$i]}"
        case $i in
            0) node_name="GERMANY" ;;
            1) node_name="RU1" ;;
            2) node_name="KAZAKHSTAN" ;;
            3) node_name="FIN" ;;
            4) node_name="USA" ;;
            5) node_name="NL" ;;
            *) node_name="NODE-$i" ;;
        esac
        
        if update_node_api "$node" "$node_name"; then
            ((success_count++))
        fi
        
        echo ""
    done
    
    echo -e "${BOLD}${GREEN}📊 Результаты обновления:${NC}"
    echo -e "${GREEN}   ✅ Успешно обновлено: $success_count из $total_count${NC}"
    echo -e "${RED}   ❌ Ошибок: $((total_count - success_count))${NC}"
else
    show_menu
fi
