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
    echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}5.${NC} ${YELLOW}📈 Node Exporter + API${NC} ${GRAY}┃${NC} ${WHITE}Мониторинг и управление${NC} ${BOLD}${WHITE}│${NC}"
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

# ===============================================================================
# NODE MONITORING SETUP - Интегрированное меню
# ===============================================================================

# Дополнительные цвета для Node Monitoring
readonly CYAN_BOLD='\033[1;36m'
readonly PURPLE_BOLD='\033[1;35m'

# Функции логирования для Node Monitoring
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }

# Проверка статуса сервиса
check_service_status() {
    local service_name="$1"
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Универсальная функция ожидания
wait_for_user() {
    echo
    read -p "Нажмите Enter для продолжения..."
}

# Универсальная функция поиска скрипта
find_script() {
    local script_name="$1"
    
    log_info "🔍 Ищем скрипт: $script_name"
    log_info "📁 Текущая директория: $(pwd)"
    
    # Проверяем разные возможные пути
    if [[ -f "script/scripts-main/$script_name" ]]; then
        log_info "✅ Найден в: script/scripts-main/$script_name"
        echo "script/scripts-main/$script_name"
    elif [[ -f "./$script_name" ]]; then
        log_info "✅ Найден в: ./$script_name"
        echo "./$script_name"
    elif [[ -f "$script_name" ]]; then
        log_info "✅ Найден в: $script_name"
        echo "$script_name"
    else
        log_error "❌ Скрипт $script_name не найден в:"
        log_error "   - script/scripts-main/$script_name"
        log_error "   - ./$script_name"
        log_error "   - $script_name"
        log_info "📋 Содержимое текущей директории:"
        ls -la 2>/dev/null || dir 2>/dev/null || echo "Не удалось получить список файлов"
        return 1
    fi
}

# Проверка существования скрипта
check_script_exists() {
    local script_path="$1"
    local script_name="$2"
    
    if [[ ! -f "$script_path" ]]; then
        log_error "$script_name не найден: $script_path"
        return 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        log_warn "$script_name не исполняемый, делаем исполняемым..."
        chmod +x "$script_path"
    fi
    
    return 0
}

# Функции установки
install_full_monitoring() {
    show_header
    log_info "🚀 Запуск полной установки..."
    echo -e "${YELLOW}Устанавливаем: Node API + MTR + Node Exporter${NC}"
    echo
    
    # Ищем скрипты установки
    local node_api_script
    local node_exporter_script
    
    log_info "🔍 Поиск скрипта install_node_api.sh..."
    if find_script "install_node_api.sh" >/dev/null 2>&1; then
        node_api_script=$(find_script "install_node_api.sh")
        log_info "✅ Найден Node API скрипт: $node_api_script"
    else
        log_error "❌ Скрипт install_node_api.sh не найден"
        find_script "install_node_api.sh" || true  # Показываем отладочную информацию
        wait_for_user
        return 1
    fi
    
    log_info "🔍 Поиск скрипта install_node_exporter.sh..."
    if find_script "install_node_exporter.sh" >/dev/null 2>&1; then
        node_exporter_script=$(find_script "install_node_exporter.sh")
        log_info "✅ Найден Node Exporter скрипт: $node_exporter_script"
    else
        log_error "❌ Скрипт install_node_exporter.sh не найден"
        find_script "install_node_exporter.sh" || true  # Показываем отладочную информацию
        wait_for_user
        return 1
    fi
    
    if ! check_script_exists "$node_api_script" "Node API скрипт"; then
        log_error "Не удалось найти скрипт установки Node API"
        wait_for_user
        return 1
    fi
    
    if ! check_script_exists "$node_exporter_script" "Node Exporter скрипт"; then
        log_error "Не удалось найти скрипт установки Node Exporter"
        wait_for_user
        return 1
    fi
    
    # Устанавливаем Node API + MTR
    log_info "Этап 1/2: Установка Node API + MTR"
    if INSTALL_MTR=true bash "$node_api_script"; then
        log_success "Node API + MTR установлены успешно"
    else
        log_error "Ошибка установки Node API + MTR"
        wait_for_user
        return 1
    fi
    
    echo
    log_info "Этап 2/2: Установка Node Exporter"
    if bash "$node_exporter_script"; then
        log_success "Node Exporter установлен успешно"
    else
        log_error "Ошибка установки Node Exporter"
        wait_for_user
        return 1
    fi
    
    echo
    log_success "✅ Полная установка завершена успешно!"
    wait_for_user
}

install_node_api_only() {
    show_header
    log_info "🔧 Установка Node API + MTR..."
    echo
    
    # Ищем скрипт установки
    local node_api_script
    log_info "🔍 Поиск скрипта install_node_api.sh..."
    if find_script "install_node_api.sh" >/dev/null 2>&1; then
        node_api_script=$(find_script "install_node_api.sh")
        log_info "✅ Найден Node API скрипт: $node_api_script"
    else
        log_error "❌ Скрипт install_node_api.sh не найден"
        find_script "install_node_api.sh" || true  # Показываем отладочную информацию
        wait_for_user
        return 1
    fi
    
    if ! check_script_exists "$node_api_script" "Node API скрипт"; then
        log_error "Не удалось найти скрипт установки Node API"
        wait_for_user
        return 1
    fi
    
    if INSTALL_MTR=true bash "$node_api_script"; then
        log_success "✅ Node API + MTR установлены успешно!"
    else
        log_error "Ошибка установки Node API + MTR"
        wait_for_user
        return 1
    fi
    
    wait_for_user
}

install_node_exporter_only() {
    show_header
    log_info "📊 Установка Node Exporter..."
    echo
    
    # Ищем скрипт установки
    local node_exporter_script
    log_info "🔍 Поиск скрипта install_node_exporter.sh..."
    if find_script "install_node_exporter.sh" >/dev/null 2>&1; then
        node_exporter_script=$(find_script "install_node_exporter.sh")
        log_info "✅ Найден Node Exporter скрипт: $node_exporter_script"
    else
        log_error "❌ Скрипт install_node_exporter.sh не найден"
        find_script "install_node_exporter.sh" || true  # Показываем отладочную информацию
        wait_for_user
        return 1
    fi
    
    if ! check_script_exists "$node_exporter_script" "Node Exporter скрипт"; then
        log_error "Не удалось найти скрипт установки Node Exporter"
        wait_for_user
        return 1
    fi
    
    if bash "$node_exporter_script"; then
        log_success "✅ Node Exporter установлен успешно!"
    else
        log_error "Ошибка установки Node Exporter"
        wait_for_user
        return 1
    fi
    
    wait_for_user
}

# Функции тестирования
test_node_api() {
    show_header
    log_info "🧪 Тестирование Node API..."
    echo
    
    if ! check_service_status "node-api"; then
        log_error "Node API не запущен"
        log_info "Попробуйте: sudo systemctl start node-api"
        wait_for_user
        return 1
    fi
    
    log_success "Node API сервис активен"
    
    # Проверяем health endpoint
    log_info "Проверка health endpoint..."
    if timeout 5 curl -s http://localhost:8080/health >/dev/null 2>&1; then
        log_success "Health endpoint отвечает"
        
        # Показываем ответ
        echo -e "${CYAN}Ответ health endpoint:${NC}"
        curl -s http://localhost:8080/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/health
    else
        log_warn "Health endpoint не отвечает"
    fi
    
    echo
    log_info "Статус сервиса:"
    systemctl status node-api --no-pager -l | head -20
    
    wait_for_user
}

test_mtr() {
    show_header
    log_info "🌐 Тестирование MTR диагностики..."
    echo
    
    if ! command -v mtr >/dev/null 2>&1; then
        log_error "MTR не установлен"
        log_info "Установите MTR: sudo apt install mtr-tiny"
        wait_for_user
        return 1
    fi
    
    log_success "MTR найден"
    
    # Показываем версию
    log_info "Версия MTR:"
    mtr --version 2>/dev/null || echo "Версия недоступна"
    
    echo
    log_info "Запуск MTR диагностики до 8.8.8.8 (5 циклов)..."
    echo
    
    if mtr --report --report-cycles 5 8.8.8.8; then
        log_success "MTR диагностика завершена успешно"
    else
        log_error "Ошибка выполнения MTR"
    fi
    
    wait_for_user
}

test_node_exporter() {
    show_header
    log_info "📊 Проверка метрик Node Exporter..."
    echo
    
    if ! check_service_status "node_exporter"; then
        log_error "Node Exporter не запущен"
        log_info "Попробуйте: sudo systemctl start node_exporter"
        wait_for_user
        return 1
    fi
    
    log_success "Node Exporter сервис активен"
    
    # Проверяем метрики endpoint
    log_info "Проверка endpoint метрик..."
    if timeout 5 curl -s http://localhost:9100/metrics >/dev/null 2>&1; then
        log_success "Endpoint метрик отвечает"
        
        # Показываем статистику метрик
        local metrics_count
        metrics_count=$(curl -s http://localhost:9100/metrics | wc -l)
        log_info "Доступно метрик: $metrics_count"
        
        echo
        log_info "Примеры метрик:"
        curl -s http://localhost:9100/metrics | grep -E "^(node_cpu|node_memory|node_filesystem)" | head -5
    else
        log_warn "Endpoint метрик не отвечает"
    fi
    
    echo
    log_info "Статус сервиса:"
    systemctl status node_exporter --no-pager -l | head -20
    
    wait_for_user
}

show_monitoring_logs() {
    show_header
    log_info "🔍 Просмотр логов..."
    echo
    
    echo "Выберите логи для просмотра:"
    echo "1. Node API"
    echo "2. Node Exporter"
    echo "3. Системные логи (последние ошибки)"
    echo "4. Все сервисы мониторинга"
    echo "0. Назад"
    echo
    read -p "Выберите [0-4]: " log_choice
    
    case $log_choice in
        1)
            if check_service_status "node-api"; then
                echo -e "${CYAN}📋 Логи Node API (последние 50 строк):${NC}"
                journalctl -u node-api -n 50 --no-pager
            else
                log_warn "Node API не запущен"
            fi
            ;;
        2)
            if check_service_status "node_exporter"; then
                echo -e "${CYAN}📋 Логи Node Exporter (последние 50 строк):${NC}"
                journalctl -u node_exporter -n 50 --no-pager
            else
                log_warn "Node Exporter не запущен"
            fi
            ;;
        3)
            echo -e "${CYAN}📋 Системные ошибки (последние 30 минут):${NC}"
            journalctl --since "30 minutes ago" --priority=err --no-pager
            ;;
        4)
            echo -e "${CYAN}📋 Все сервисы мониторинга:${NC}"
            for service in node-api node_exporter; do
                if systemctl is-enabled "$service" >/dev/null 2>&1; then
                    echo -e "\n${YELLOW}=== $service ===${NC}"
                    journalctl -u "$service" -n 10 --no-pager
                fi
            done
            ;;
        0)
            return
            ;;
        *)
            log_error "Неверный выбор"
            ;;
    esac
    
    wait_for_user
}

# Функции удаления
remove_node_api() {
    show_header
    log_info "❌ Удаление Node API..."
    echo
    
    log_warn "Это удалит Node API, все его файлы и конфигурации"
    read -p "Вы уверены? [y/N]: " confirm
    if [[ "$confirm" != [yY] ]]; then
        log_info "Отменено"
        wait_for_user
        return
    fi
    
    log_info "Остановка и отключение сервиса..."
    systemctl stop node-api 2>/dev/null || true
    systemctl disable node-api 2>/dev/null || true
    
    log_info "Удаление файлов..."
    rm -f /etc/systemd/system/node-api.service
    rm -rf /opt/node-api
    
    log_info "Удаление пользователя..."
    userdel node-api 2>/dev/null || true
    
    systemctl daemon-reload
    
    log_success "✅ Node API удален"
    wait_for_user
}

remove_node_exporter() {
    show_header
    log_info "❌ Удаление Node Exporter..."
    echo
    
    log_warn "Это удалит Node Exporter, все его файлы и конфигурации"
    read -p "Вы уверены? [y/N]: " confirm
    if [[ "$confirm" != [yY] ]]; then
        log_info "Отменено"
        wait_for_user
        return
    fi
    
    log_info "Остановка и отключение сервиса..."
    systemctl stop node_exporter 2>/dev/null || true
    systemctl disable node_exporter 2>/dev/null || true
    
    log_info "Удаление файлов..."
    rm -f /etc/systemd/system/node_exporter.service
    rm -f /usr/local/bin/node_exporter
    
    log_info "Удаление пользователя..."
    userdel node_exporter 2>/dev/null || true
    
    systemctl daemon-reload
    
    log_success "✅ Node Exporter удален"
    wait_for_user
}

# Главное меню Node Monitoring
show_node_exporter_menu() {
    while true; do
        show_header
        echo -e "${CYAN_BOLD}┌─────────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN_BOLD}│${NC}                    ${PURPLE_BOLD}NODE MONITORING SETUP${NC}                        ${CYAN_BOLD}│${NC}"
        echo -e "${CYAN_BOLD}│${NC}                   ${BLUE}Management by Spakieone${NC}                       ${CYAN_BOLD}│${NC}"
        echo -e "${CYAN_BOLD}│${NC}                     ${YELLOW}Optimized v1.2.0${NC}                          ${CYAN_BOLD}│${NC}"
        echo -e "${CYAN_BOLD}└─────────────────────────────────────────────────────────────────┘${NC}"
        echo
        
        echo -e "${GREEN}┌─ 🚀 УСТАНОВКА ──────────────────────────────────────────────────┐${NC}"
        echo -e "${GREEN}│${NC} 1. 🚀 Полная установка (рекомендуется)  ${CYAN}│${NC} Node API + Exporter   ${GREEN}│${NC}"
        echo -e "${GREEN}│${NC} 2. 🔧 Установить только Node API        ${CYAN}│${NC} API + диагностика     ${GREEN}│${NC}"
        echo -e "${GREEN}│${NC} 3. 📊 Установить только Node Exporter   ${CYAN}│${NC} Метрики системы       ${GREEN}│${NC}"
        echo -e "${GREEN}└─────────────────────────────────────────────────────────────────┘${NC}"
        echo
        
        echo -e "${YELLOW}┌─ 🔧 ИНСТРУМЕНТЫ ────────────────────────────────────────────────┐${NC}"
        echo -e "${YELLOW}│${NC} 4. 🧪 Тест Node API                     ${CYAN}│${NC} Проверка API          ${YELLOW}│${NC}"
        echo -e "${YELLOW}│${NC} 5. 🌐 Тест MTR диагностики              ${CYAN}│${NC} Тест сети             ${YELLOW}│${NC}"
        echo -e "${YELLOW}│${NC} 6. 📊 Проверить метрики Node Exporter   ${CYAN}│${NC} Статус метрик         ${YELLOW}│${NC}"
        echo -e "${YELLOW}│${NC} 7. 🔍 Показать логи                     ${CYAN}│${NC} Системные логи        ${YELLOW}│${NC}"
        echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────┘${NC}"
        echo
        
        echo -e "${RED}┌─ 🗑️ УДАЛЕНИЕ ───────────────────────────────────────────────────┐${NC}"
        echo -e "${RED}│${NC} 8. ❌ Удалить Node API                  ${CYAN}│${NC} Только API            ${RED}│${NC}"
        echo -e "${RED}│${NC} 9. ❌ Удалить Node Exporter             ${CYAN}│${NC} Только метрики        ${RED}│${NC}"
        echo -e "${RED}└─────────────────────────────────────────────────────────────────┘${NC}"
        echo
        
        echo -e "${BLUE}┌─ 🚪 ВЫХОД ──────────────────────────────────────────────────────┐${NC}"
        echo -e "${BLUE}│${NC} 0. 🔙 Назад в главное меню              ${CYAN}│${NC} Возврат               ${BLUE}│${NC}"
        echo -e "${BLUE}└─────────────────────────────────────────────────────────────────┘${NC}"
        echo
        
        echo -e "${CYAN}Выберите инструмент [1-9, 0-выход]: ${NC}"
        echo -n "   ➤ "
        
        read -r choice
        
        case $choice in
            1)
                install_full_monitoring
                ;;
            2)
                install_node_api_only
                ;;
            3)
                install_node_exporter_only
                ;;
            4)
                test_node_api
                ;;
            5)
                test_mtr
                ;;
            6)
                test_node_exporter
                ;;
            7)
                show_monitoring_logs
                ;;
            8)
                remove_node_api
                ;;
            9)
                remove_node_exporter
                ;;
            0)
                return
                ;;
            *)
                log_error "Неверный выбор. Попробуйте снова."
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
