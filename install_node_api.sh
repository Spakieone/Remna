#!/bin/bash

# Скрипт установки Node API
# Node API Installation Script

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

# Переменные
NODE_API_DIR="/home/node-manager/node-api"
NODE_API_SCRIPT="$NODE_API_DIR/node_api.py"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/node-api.service"
NODE_MANAGER_USER="node-manager"
NODE_API_TOKEN="" # Будет запрошен во время установки

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
    echo -e "${BOLD}${CYAN}║${NC}       ${GRAY}Node API Installation Script${NC}                        ${BOLD}${CYAN}║${NC}"
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

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен быть запущен с правами root (sudo)"
        exit 1
    fi
}

# Функция для запроса токена
get_node_api_token() {
    echo ""
    echo -e "${BOLD}${WHITE}┌─ 🔑 НАСТРОЙКА ТОКЕНА БЕЗОПАСНОСТИ ──────────────────────────┐${NC}"
    echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${YELLOW}Введите токен для Node API:${NC}                              ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${GRAY}Этот токен будет использоваться для авторизации${NC}        ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${GRAY}запросов к Node API на этой ноде.${NC}                        ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${CYAN}Рекомендации:${NC}                                          ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${CYAN}• Используйте сложный токен (минимум 20 символов)${NC}      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${CYAN}• Используйте одинаковый токен на всех нодах${NC}           ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}│${NC}  ${CYAN}• Пример: monitoring-bot-2024-secure-token-xyz789${NC}      ${BOLD}${WHITE}│${NC}"
    echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    while true; do
        echo -n -e "${WHITE}Введите токен: ${NC}"
        read token
        
        if [ -z "$token" ]; then
            echo -e "${RED}❌ Токен не может быть пустым!${NC}"
            continue
        fi
        
        if [ ${#token} -lt 10 ]; then
            echo -e "${RED}❌ Токен слишком короткий! Минимум 10 символов.${NC}"
            continue
        fi
        
        echo ""
        echo -n -e "${WHITE}Подтвердите токен: ${NC}"
        read confirm_token
        
        if [ "$token" != "$confirm_token" ]; then
            echo -e "${RED}❌ Токены не совпадают! Попробуйте снова.${NC}"
            continue
        fi
        
        NODE_API_TOKEN="$token"
        echo -e "${GREEN}✅ Токен установлен успешно!${NC}"
        break
    done
}

# Установка Node API
install_node_api() {
    log "🚀 Запуск установки Node API..."
    
    # 0. Запрашиваем токен безопасности
    get_node_api_token

    # 1. Создаем пользователя node-manager, если его нет
    if ! id -u "$NODE_MANAGER_USER" >/dev/null 2>&1; then
        log "Создание пользователя $NODE_MANAGER_USER..."
        useradd -m -s /bin/bash "$NODE_MANAGER_USER"
        echo "$NODE_MANAGER_USER ALL=(ALL) NOPASSWD: /bin/systemctl start *, /bin/systemctl stop *, /bin/systemctl restart *, /bin/systemctl status *, /sbin/reboot" | tee "/etc/sudoers.d/$NODE_MANAGER_USER" > /dev/null
        chmod 0440 "/etc/sudoers.d/$NODE_MANAGER_USER"
    else
        log "Пользователь $NODE_MANAGER_USER уже существует."
    fi

    # 2. Устанавливаем Python3 и pip
    log "Установка Python3 и pip..."
    apt update
    apt install -y python3 python3-pip python3-venv curl wget
    
    # Проверяем что pip3 установился
    if ! command -v pip3 &> /dev/null; then
        error "pip3 не установлен! Попробуйте: apt install python3-pip"
        return 1
    fi

    # 3. Создаем директорию для Node API
    log "Создание директории $NODE_API_DIR..."
    mkdir -p "$NODE_API_DIR"
    chown "$NODE_MANAGER_USER":"$NODE_MANAGER_USER" "$NODE_API_DIR"

    # 4. Создаем скрипт Node API
    log "Создание скрипта node_api.py..."
    cat > "$NODE_API_SCRIPT" << 'EOF'
#!/usr/bin/env python3
from flask import Flask, request, jsonify
import subprocess
import os
import psutil

app = Flask(__name__)

# Токен для авторизации
AUTH_TOKEN = os.getenv("NODE_API_TOKEN", "your-secret-token")

def check_auth():
    token = request.headers.get('Authorization')
    if not token or token != f"Bearer {AUTH_TOKEN}":
        return False
    return True

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "ok"}), 200

@app.route('/api/status', methods=['GET'])
def get_status():
    """Получение статуса ноды"""
    try:
        # Получаем системную информацию
        cpu_percent = psutil.cpu_percent(interval=0.1)
        ram_info = psutil.virtual_memory()
        disk_info = psutil.disk_usage('/')

        # Получаем статус сервисов
        services_status = {}
        configured_services = os.getenv("NODE_SERVICES", "nginx,node_exporter,vpn_service").split(',')
        for service in configured_services:
            result = subprocess.run(
                ['systemctl', 'is-active', service.strip()],
                capture_output=True, text=True
            )
            services_status[service.strip()] = result.stdout.strip()

        return jsonify({
            "status": "online",
            "cpu": f"{cpu_percent:.1f}%",
            "memory": f"{ram_info.percent:.1f}%",
            "uptime": subprocess.check_output(['uptime', '-p']).decode().strip(),
            "disk": f"{disk_info.percent:.1f}%",
            "services": services_status
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/service/<service>/<action>', methods=['POST'])
def control_service(service, action):
    """Управление сервисами"""
    if action not in ['start', 'stop', 'restart', 'status']:
        return jsonify({"error": "Invalid action"}), 400

    try:
        result = subprocess.run(
            ['sudo', 'systemctl', action, service],
            capture_output=True, text=True, timeout=30
        )

        return jsonify({
            "service": service,
            "action": action,
            "success": result.returncode == 0,
            "output": result.stdout,
            "error": result.stderr
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/reboot', methods=['POST'])
def reboot_node():
    """Перезагрузка ноды"""
    try:
        subprocess.run(['sudo', 'reboot'], check=False)
        return jsonify({"message": "Reboot initiated"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF
    chmod +x "$NODE_API_SCRIPT"
    chown "$NODE_MANAGER_USER":"$NODE_MANAGER_USER" "$NODE_API_SCRIPT"

    # 5. Устанавливаем зависимости глобально (проще и надежнее)
    log "Установка зависимостей..."
    
    # Устанавливаем Flask и psutil глобально
    pip3 install flask psutil
    
    # Проверяем что установка прошла успешно
    if [ $? -ne 0 ]; then
        error "Ошибка установки зависимостей! Попробуйте: pip3 install flask psutil"
        return 1
    fi
    
    # Проверяем установку
    log "Проверка установленных пакетов..."
    pip3 list | grep -E "(flask|psutil)"
    
    # Проверяем что Python может импортировать модули
    log "Тестирование импорта модулей..."
    python3 -c "import flask; import psutil; print('✅ Все модули импортированы успешно')"
    
    if [ $? -ne 0 ]; then
        error "Ошибка импорта модулей! Проверьте установку: pip3 list"
        return 1
    fi

    # 6. Создаем systemd сервис
    log "Создание systemd сервиса..."
    cat > "$SYSTEMD_SERVICE_FILE" << EOF
[Unit]
Description=Node API Server
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$NODE_API_DIR
Environment="NODE_API_TOKEN=$NODE_API_TOKEN"
Environment="NODE_SERVICES=nginx,node_exporter,vpn_service"
ExecStart=/usr/bin/python3 $NODE_API_SCRIPT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 7. Запускаем сервис
    log "Запуск сервиса Node API..."
    systemctl daemon-reload
    systemctl enable node-api
    systemctl start node-api

    # 8. Открываем порт в файрволе (если используется UFW)
    log "Настройка файрвола (UFW)..."
    if command -v ufw &> /dev/null; then
        ufw allow 8080/tcp
        ufw reload
        log "Порт 8080 открыт в UFW."
    else
        warn "UFW не найден, пропуск настройки файрвола."
    fi

    # 9. Сохраняем токен в файл для копирования в бот мониторинга
    log "Сохранение токена для бота мониторинга..."
    echo "NODE_API_TOKEN=$NODE_API_TOKEN" > /tmp/node_api_token.txt
    chmod 600 /tmp/node_api_token.txt

    log "✅ Установка Node API завершена!"
    echo ""
    info "📋 Проверка установки:"
    echo "   • Статус сервиса: sudo systemctl status node-api"
    echo "   • Проверка API: curl http://localhost:8080/health"
    echo "   • Логи сервиса: sudo journalctl -u node-api -f"
    echo ""
    echo -e "${BOLD}${YELLOW}🔑 ВАЖНО: Токен для бота мониторинга:${NC}"
    echo -e "${BOLD}${CYAN}NODE_API_TOKEN=$NODE_API_TOKEN${NC}"
    echo ""
    echo -e "${BOLD}${WHITE}📝 Скопируйте эту строку в .env файл бота мониторинга!${NC}"
    echo ""
}


# Исправление Node API (переустановка зависимостей)
fix_node_api() {
    log "🔧 Исправление Node API..."
    
    # Проверяем права root
    check_root
    
    # Проверяем что pip3 установлен
    if ! command -v pip3 &> /dev/null; then
        log "Установка pip3..."
        apt update
        apt install -y python3-pip
    fi
    
    # Переустанавливаем зависимости
    log "Переустановка зависимостей..."
    pip3 install --force-reinstall flask psutil
    
    # Проверяем установку
    log "Проверка установленных пакетов..."
    pip3 list | grep -E "(flask|psutil)"
    
    # Тестируем импорт
    log "Тестирование импорта модулей..."
    python3 -c "import flask; import psutil; print('✅ Все модули импортированы успешно')"
    
    if [ $? -ne 0 ]; then
        error "❌ Ошибка импорта модулей!"
        return 1
    fi
    
    # Перезапускаем сервис
    log "Перезапуск сервиса Node API..."
    systemctl restart node-api
    
    # Проверяем статус
    sleep 2
    if systemctl is-active --quiet node-api; then
        log "✅ Node API исправлен и запущен успешно!"
    else
        error "❌ Ошибка запуска Node API. Проверьте логи: sudo journalctl -u node-api -f"
    fi
}

# Проверка статуса
check_status() {
    show_header
    echo -e "${BOLD}${WHITE}📊 Статус Node API${NC}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo ""
    
    # Проверка сервиса
    echo -e "${WHITE}🔧 Сервис Node API:${NC}"
    if systemctl is-active --quiet node-api; then
        echo -e "   ${GREEN}✅ Статус: Запущен${NC}"
    else
        echo -e "   ${RED}❌ Статус: Остановлен${NC}"
    fi
    
    # Проверка порта
    echo -e "${WHITE}🌐 Порт 8080:${NC}"
    if netstat -tlnp 2>/dev/null | grep -q ":8080 "; then
        echo -e "   ${GREEN}✅ Порт открыт${NC}"
    else
        echo -e "   ${RED}❌ Порт закрыт${NC}"
    fi
    
    # Проверка API
    echo -e "${WHITE}🔍 API Health Check:${NC}"
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo -e "   ${GREEN}✅ API отвечает${NC}"
    else
        echo -e "   ${RED}❌ API не отвечает${NC}"
    fi
    
    echo ""
    echo -e "${GRAY}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    read -p "Нажмите Enter для возврата в меню..."
}

# Главное меню
show_menu() {
    while true; do
        show_header
        echo -e "${BOLD}${WHITE}┌─ 🔧 NODE API УПРАВЛЕНИЕ ──────────────────────────────┐${NC}"
        echo -e "${BOLD}${WHITE}│${NC}                                                      ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}1.${NC} ${YELLOW}🚀 Установить Node API${NC}           ${GRAY}┃${NC} ${WHITE}Полная установка${NC}        ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}2.${NC} ${YELLOW}🔧 Исправить Node API${NC}           ${GRAY}┃${NC} ${WHITE}Переустановка зависимостей${NC} ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}3.${NC} ${YELLOW}📊 Проверить статус${NC}              ${GRAY}┃${NC} ${WHITE}Статус сервиса${NC}          ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}4.${NC} ${YELLOW}🔄 Перезапустить сервис${NC}           ${GRAY}┃${NC} ${WHITE}Перезапуск${NC}             ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}5.${NC} ${YELLOW}📋 Показать логи${NC}                 ${GRAY}┃${NC} ${WHITE}Логи сервиса${NC}           ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}6.${NC} ${YELLOW}🔧 Тест API${NC}                      ${GRAY}┃${NC} ${WHITE}Тестирование${NC}           ${BOLD}${WHITE}│${NC}"
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
                check_root
                install_node_api
                read -p "Нажмите Enter для продолжения..."
                ;;
            2) 
                fix_node_api
                read -p "Нажмите Enter для продолжения..."
                ;;
            3) 
                check_status
                ;;
            4) 
                echo -e "${BLUE}🔄 Перезапуск Node API...${NC}"
                systemctl restart node-api
                echo -e "${GREEN}✅ Node API перезапущен${NC}"
                read -p "Нажмите Enter для продолжения..."
                ;;
            5) 
                echo -e "${CYAN}📋 Логи Node API:${NC}"
                journalctl -u node-api -f --no-pager
                ;;
            6) 
                echo -e "${YELLOW}🔧 Тестирование API...${NC}"
                echo ""
                echo -e "${WHITE}Health Check:${NC}"
                curl -s http://localhost:8080/health | jq . 2>/dev/null || curl -s http://localhost:8080/health
                echo ""
                echo -e "${WHITE}Status API:${NC}"
                curl -s http://localhost:8080/api/status | jq . 2>/dev/null || curl -s http://localhost:8080/api/status
                echo ""
                read -p "Нажмите Enter для продолжения..."
                ;;
            0) 
                return
                ;;
            *) 
                echo -e "${RED}❌ Неверный выбор! Пожалуйста, выберите опцию от 0 до 5.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Основная логика
if [ "$1" = "menu" ]; then
    show_menu
else
    check_root
    install_node_api
fi
