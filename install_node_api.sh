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
NODE_API_TOKEN="your-secret-token" # Замените на ваш токен

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

# Установка Node API
install_node_api() {
    log "🚀 Запуск установки Node API..."

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

    # 5. Создаем виртуальное окружение и устанавливаем зависимости
    log "Создание виртуального окружения и установка зависимостей..."
    sudo -u "$NODE_MANAGER_USER" python3 -m venv "$NODE_API_DIR/venv"
    sudo -u "$NODE_MANAGER_USER" "$NODE_API_DIR/venv/bin/pip" install flask psutil

    # 6. Создаем systemd сервис
    log "Создание systemd сервиса..."
    cat > "$SYSTEMD_SERVICE_FILE" << EOF
[Unit]
Description=Node API Server
After=network.target

[Service]
Type=simple
User=$NODE_MANAGER_USER
Group=$NODE_MANAGER_USER
WorkingDirectory=$NODE_API_DIR
Environment="NODE_API_TOKEN=$NODE_API_TOKEN"
Environment="NODE_SERVICES=nginx,node_exporter,vpn_service"
ExecStart=$NODE_API_DIR/venv/bin/python $NODE_API_SCRIPT
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

    log "✅ Установка Node API завершена!"
    echo ""
    info "📋 Проверка установки:"
    echo "   • Статус сервиса: sudo systemctl status node-api"
    echo "   • Проверка API: curl http://localhost:8080/health"
    echo "   • Логи сервиса: sudo journalctl -u node-api -f"
    echo ""
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
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}2.${NC} ${YELLOW}📊 Проверить статус${NC}              ${GRAY}┃${NC} ${WHITE}Статус сервиса${NC}          ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}3.${NC} ${YELLOW}🔄 Перезапустить сервис${NC}           ${GRAY}┃${NC} ${WHITE}Перезапуск${NC}             ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}4.${NC} ${YELLOW}📋 Показать логи${NC}                 ${GRAY}┃${NC} ${WHITE}Логи сервиса${NC}           ${BOLD}${WHITE}│${NC}"
        echo -e "${BOLD}${WHITE}│${NC}  ${BOLD}${GREEN}5.${NC} ${YELLOW}🔧 Тест API${NC}                      ${GRAY}┃${NC} ${WHITE}Тестирование${NC}           ${BOLD}${WHITE}│${NC}"
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
                check_status
                ;;
            3) 
                echo -e "${BLUE}🔄 Перезапуск Node API...${NC}"
                systemctl restart node-api
                echo -e "${GREEN}✅ Node API перезапущен${NC}"
                read -p "Нажмите Enter для продолжения..."
                ;;
            4) 
                echo -e "${CYAN}📋 Логи Node API:${NC}"
                journalctl -u node-api -f --no-pager
                ;;
            5) 
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
