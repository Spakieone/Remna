#!/bin/bash

# Оптимизированный установщик Node API + MTR
# Исправлены все обнаруженные проблемы

set -euo pipefail  # Строгий режим

# Цвета и константы
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

readonly NODE_API_DIR="/opt/node-api"
readonly NODE_API_SCRIPT="$NODE_API_DIR/node_api.py"
readonly SYSTEMD_SERVICE_FILE="/etc/systemd/system/node-api.service"
readonly NODE_API_USER="node-api"

# Функции логирования
log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${BLUE}[ℹ]${NC} $1"; }

# Проверка прав root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        err "Требуются права root. Запустите: sudo $0"
        exit 1
    fi
}

# Проверка ОС
detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        err "Не удается определить ОС. Поддерживаются только Linux дистрибутивы."
        exit 1
    fi
    
    source /etc/os-release
    export OS_ID="$ID"
    export OS_VERSION="$VERSION_ID"
    info "Обнаружена ОС: $PRETTY_NAME"
}

# Валидация токена
validate_token() {
    local token="$1"
    
    if [[ -z "$token" ]]; then
        err "Токен не может быть пустым"
        return 1
    fi
    
    if [[ ${#token} -lt 8 ]]; then
        err "Токен должен содержать минимум 8 символов"
        return 1
    fi
    
    if [[ "$token" =~ [[:space:]] ]]; then
        err "Токен не должен содержать пробелы"
        return 1
    fi
    
    log "Токен прошел валидацию"
    return 0
}

# Получение токена
get_api_token() {
    if [[ -n "${NODE_API_TOKEN:-}" ]]; then
        if validate_token "$NODE_API_TOKEN"; then
            return 0
        else
            unset NODE_API_TOKEN
        fi
    fi
    
    echo
    info "Введите токен для Node API (минимум 8 символов, без пробелов):"
    while true; do
        echo -n "TOKEN: "
        read -r NODE_API_TOKEN
        
        if validate_token "$NODE_API_TOKEN"; then
            break
        fi
        warn "Попробуйте еще раз"
    done
    
    export NODE_API_TOKEN
}

# Установка системных пакетов
install_system_packages() {
    # Если явно попросили пропустить apt — выходим
    if [[ "${SKIP_APT:-false}" == "true" ]]; then
        warn "Пропускаем установку системных пакетов (SKIP_APT=true)"
        return 0
    fi

    # Если всё уже есть — тоже пропускаем
    if command -v python3 >/dev/null 2>&1 \
        && python3 -c 'import venv' 2>/dev/null \
        && { command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; }
    then
        info "Базовые инструменты уже установлены — пропускаю apt"
        return 0
    fi

    info "Обновление списка пакетов..."

    case "$OS_ID" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            # Базовые зависимости без спорных пакетов (docker/systemctl)
            if ! apt-get install -y -qq --no-install-recommends \
                python3 \
                python3-venv \
                python3-pip \
                python3-dev \
                curl \
                wget \
                ufw \
                mtr-tiny \
                traceroute; then
                warn "apt install завершился с ошибкой. Пробую исправить зависимости..."
                dpkg --configure -a || true
                apt-get -y --fix-broken install || true
                apt-get update -qq || true
                if ! apt-get install -y -qq --no-install-recommends \
                    python3 python3-venv python3-pip python3-dev curl wget ufw mtr-tiny traceroute; then
                    # Если после попытки починки всё равно ошибка — продолжаем, если python уже доступен
                    if command -v python3 >/dev/null 2>&1 && python3 -c 'import venv' 2>/dev/null; then
                        warn "Не удалось установить пакеты через apt, но Python/venv доступны — продолжаю установку"
                    else
                        err "Ошибка установки системных пакетов и Python не доступен"
                        exit 1
                    fi
                fi
            fi
            
            # Если docker отсутствует — мягкая установка через официальный скрипт
            if ! command -v docker >/dev/null 2>&1; then
                warn "Docker не обнаружен. Пытаюсь установить через get.docker.com"
                if command -v curl >/dev/null 2>&1; then
                    sh -c "$(curl -fsSL https://get.docker.com)" || warn "Не удалось установить Docker автоматически. Продолжаю без Docker"
                elif command -v wget >/dev/null 2>&1; then
                    wget -qO- https://get.docker.com | sh || warn "Не удалось установить Docker автоматически. Продолжаю без Docker"
                else
                    warn "curl/wget недоступны — пропускаю установку Docker"
                fi
            fi
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y python3 python3-pip python3-devel curl wget docker systemd firewalld mtr
            else
                yum install -y python3 python3-pip python3-devel curl wget docker systemd firewalld mtr
            fi
            ;;
        *)
            err "Неподдерживаемая ОС: $OS_ID"
            exit 1
            ;;
    esac
    
    log "Системные пакеты установлены"
}

# Установка MTR
install_mtr() {
    if [[ "${INSTALL_MTR:-true}" != "true" ]]; then
        info "Пропускаем установку MTR (INSTALL_MTR=false)"
        return 0
    fi
    
    info "Установка MTR для диагностики сети..."
    
    case "$OS_ID" in
        ubuntu|debian)
            if apt-get install -y mtr-tiny 2>/dev/null || apt-get install -y mtr 2>/dev/null; then
                log "MTR установлен"
            else
                warn "Не удалось установить MTR через apt"
                return 1
            fi
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y mtr || { warn "Не удалось установить MTR через dnf"; return 1; }
            else
                yum install -y mtr || { warn "Не удалось установить MTR через yum"; return 1; }
            fi
            ;;
        arch)
            pacman -Sy --noconfirm mtr || { warn "Не удалось установить MTR через pacman"; return 1; }
            ;;
        *)
            warn "Неизвестная ОС ($OS_ID), пропускаем установку MTR"
            return 1
            ;;
    esac
    
    # Проверяем установку
    if command -v mtr >/dev/null 2>&1; then
        log "MTR успешно установлен и доступен"
        return 0
    else
        warn "MTR установлен, но не найден в PATH"
        return 1
    fi
}

# Создание пользователя
create_user() {
    if id "$NODE_API_USER" >/dev/null 2>&1; then
        info "Пользователь $NODE_API_USER уже существует"
    else
        info "Создание пользователя $NODE_API_USER..."
        useradd --system --no-create-home --shell /bin/false "$NODE_API_USER" || {
            err "Не удалось создать пользователя $NODE_API_USER"
            exit 1
        }
        log "Пользователь $NODE_API_USER создан"
    fi
    
    # Добавляем пользователя в группу docker для доступа к Docker API
    if getent group docker > /dev/null 2>&1; then
        usermod -aG docker "$NODE_API_USER"
        log "Пользователь $NODE_API_USER добавлен в группу docker"
    else
        warn "Группа docker не найдена"
    fi
    
    # Добавляем sudo права для MTR (без пароля)
    echo "$NODE_API_USER ALL=(ALL) NOPASSWD: /usr/bin/mtr, /usr/bin/mtr-packet" > "/etc/sudoers.d/$NODE_API_USER-mtr"
    chmod 440 "/etc/sudoers.d/$NODE_API_USER-mtr"
    log "Добавлены sudo права для MTR пользователю $NODE_API_USER"
}

# Подготовка директории
setup_directory() {
    info "Настройка директории $NODE_API_DIR..."
    
    # Останавливаем сервис если работает
    systemctl stop node-api 2>/dev/null || true
    
    # Создаем директорию
    mkdir -p "$NODE_API_DIR"
    
    # Устанавливаем python3-venv перед созданием виртуального окружения
    info "Установка python3-venv..."
    case "$OS_ID" in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq || warn "Не удалось обновить apt"
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                python3-venv \
                python3.12-venv \
                || warn "Не удалось установить python3-venv"
            ;;
        centos|rhel|fedora)
            yum install -y -q python3-venv || warn "Не удалось установить python3-venv"
            ;;
        *)
            warn "Неизвестная ОС ($OS_ID), пропускаем установку python3-venv"
            ;;
    esac
    
    # Создаем Python venv
    info "Создание виртуального окружения Python..."
    if [[ -d "$NODE_API_DIR/venv" ]]; then
        rm -rf "$NODE_API_DIR/venv"
    fi
    
    python3 -m venv "$NODE_API_DIR/venv" || {
        err "Не удалось создать виртуальное окружение"
        exit 1
    }
    
    # Обновляем pip и устанавливаем зависимости
    info "Установка Python зависимостей..."
    "$NODE_API_DIR/venv/bin/pip" install --upgrade pip --quiet || {
        err "Не удалось обновить pip"
        exit 1
    }
    
    "$NODE_API_DIR/venv/bin/pip" install flask flask-cors psutil --quiet || {
        err "Не удалось установить Python зависимости"
        exit 1
    }
    
    # Устанавливаем дополнительные инструменты для тестов
    info "Установка дополнительных инструментов для тестов..."
    case "$OS_ID" in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq || warn "Не удалось обновить apt"
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                python3-venv \
                python3.12-venv \
                speedtest-cli \
                netcat-openbsd \
                nmap \
                dnsutils \
                traceroute \
                mtr-tiny \
                || warn "Не удалось установить некоторые инструменты"
            ;;
        centos|rhel|fedora)
            yum update -y -q || warn "Не удалось обновить yum"
            yum install -y -q \
                speedtest-cli \
                nc \
                nmap \
                bind-utils \
                traceroute \
                mtr \
                || warn "Не удалось установить некоторые инструменты"
            ;;
        *)
            warn "Неизвестная ОС ($OS_ID), пропускаем установку инструментов"
            ;;
    esac
    
    # Устанавливаем права
    chown -R "$NODE_API_USER:$NODE_API_USER" "$NODE_API_DIR"
    chmod 755 "$NODE_API_DIR"
    
    log "Директория настроена"
}

# Создание Node API скрипта
create_node_api_script() {
    info "Создание Node API скрипта..."
    
    cat > "$NODE_API_SCRIPT" << 'EOF'
#!/usr/bin/env python3
"""
Optimized Node API v1.3.0
- Исправлены дублирования команд
- Оптимизирована проверка MTR
- Улучшен error handling
- Добавлены новые тесты: speedtest, tcp_ping, dns_lookup, port_scan
"""
import os
import json
import subprocess
from datetime import datetime
from flask import Flask, request, jsonify

app = Flask(__name__)

# Конфигурация
AUTH_TOKEN = os.getenv("NODE_API_TOKEN", "your-secret-token")
BOT_SERVICE_NAME = os.getenv("BOT_SERVICE_NAME", "").strip()
BOT_MATCH = os.getenv("BOT_MATCH", "").strip()

def check_auth():
    """Проверка авторизации"""
    token = request.headers.get('Authorization')
    return bool(token and token == f"Bearer {AUTH_TOKEN}")

def run_command(cmd, timeout=30, shell=False):
    """Безопасное выполнение команд с обработкой ошибок"""
    try:
        if shell:
            result = subprocess.run(
                cmd, shell=True, capture_output=True, 
                text=True, timeout=timeout
            )
        else:
            result = subprocess.run(
                cmd, capture_output=True, 
                text=True, timeout=timeout
            )
        
        return {
            "success": result.returncode == 0,
            "output": result.stdout.strip(),
            "error": result.stderr.strip(),
            "code": result.returncode
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "output": "",
            "error": f"Timeout {timeout}s",
            "code": -1
        }
    except Exception as e:
        return {
            "success": False,
            "output": "",
            "error": str(e),
            "code": -1
        }

def get_docker_info():
    """Получение информации о Docker контейнерах"""
    result = run_command(['docker', 'ps', '-a', '--format', 'json'])
    if not result["success"]:
        return {
            "success": False, 
            "error": result["error"], 
            "containers": {}, 
            "raw_containers": []
        }
    
    containers = []
    mapping = {}
    
    for line in result["output"].split('\n'):
        if line.strip():
            try:
                container = json.loads(line)
                containers.append(container)
                name = container.get('Names', '').strip('/')
                if name:
                    mapping[name] = container
            except json.JSONDecodeError:
                continue
    
    return {
        "success": True,
        "containers": mapping,
        "raw_containers": containers
    }

def check_service_status(service_name):
    """Проверка статуса systemd сервиса"""
    result = run_command(['systemctl', 'is-active', service_name], timeout=5)
    if result["success"]:
        status = result["output"].strip().lower()
        return status in ['active', 'running', 'started', 'activating', 'reloading']
    
    # Fallback: проверка через ps
    ps_result = run_command(['ps', 'aux'], timeout=5)
    if ps_result["success"]:
        return service_name in ps_result["output"]
    
    return False

def get_system_metrics():
    """Получение системных метрик"""
    metrics = {}
    
    # CPU
    cpu_result = run_command([
        'sh', '-c', 
        "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | sed 's/%us,//'"
    ], timeout=5)
    metrics['cpu'] = cpu_result["output"] if cpu_result["success"] else "N/A"
    
    # Memory
    mem_result = run_command([
        'sh', '-c',
        "free | grep Mem | awk '{printf \"%.1f\", $3/$2 * 100.0}'"
    ], timeout=5)
    metrics['memory'] = mem_result["output"] if mem_result["success"] else "N/A"
    
    # Disk
    disk_result = run_command([
        'sh', '-c',
        "df -h / | tail -1 | awk '{print $5}' | sed 's/%//'"
    ], timeout=5)
    metrics['disk_usage_percent'] = disk_result["output"] if disk_result["success"] else "N/A"
    
    # Uptime
    uptime_result = run_command(['uptime', '-p'], timeout=5)
    metrics['uptime'] = uptime_result["output"] if uptime_result["success"] else "N/A"
    
    return metrics

def get_compose_command():
    """Определяет правильную команду для docker compose"""
    # Проверяем новую версию (docker compose)
    new_version = run_command(['docker', 'compose', 'version'], timeout=5)
    if new_version["success"]:
        return "docker compose"
    
    # Проверяем старую версию (docker-compose)
    old_version = run_command(['docker-compose', 'version'], timeout=5)
    if old_version["success"]:
        return "docker-compose"
    
    # Fallback на docker-compose
    return "docker-compose"

def detect_server_type():
    """Определение типа сервера"""
    docker_result = run_command(['docker', 'ps', '--format', '{{.Names}}'], timeout=5)
    if docker_result["success"]:
        container_names = docker_result["output"].lower()
        if 'remnawave' in container_names:
            return "panel"
        elif 'remnanode' in container_names:
            return "node"
    
    # Дополнительная проверка через docker-compose файлы
    panel_compose = run_command(['ls', '/opt/remnawave/docker-compose.yml'], timeout=3)
    node_compose = run_command(['ls', '/opt/remnanode/docker-compose.yml'], timeout=3)
    
    if panel_compose["success"]:
        return "panel"
    elif node_compose["success"]:
        return "node"
    
    return "node"  # default

def get_xray_info():
    """Получение информации о Xray (только для нод)"""
    version = "N/A"
    status = "inactive"
    
    # Сначала проверяем, что контейнер remnanode запущен
    container_check = run_command(['docker', 'ps', '--filter', 'name=remnanode', '--format', '{{.Names}}'], timeout=5)
    print(f"[DEBUG] Container check: success={container_check['success']}, output='{container_check['output']}'")
    if not container_check["success"] or 'remnanode' not in container_check["output"]:
        print(f"[DEBUG] remnanode container not found or not running")
        return version, status
    
    # Версия Xray - пробуем разные пути
    version_commands = [
        ['docker', 'exec', 'remnanode', '/usr/local/bin/xray', '-version'],
        ['docker', 'exec', 'remnanode', '/app/xray', '-version'],
        ['docker', 'exec', 'remnanode', 'xray', '-version']
    ]
    
    for cmd in version_commands:
        version_result = run_command(cmd, timeout=5)
        print(f"[DEBUG] Xray version cmd {cmd}: success={version_result['success']}, output='{version_result['output'][:100]}'")
        if version_result["success"] and 'Xray' in version_result["output"]:
            version_line = version_result["output"].split('\n')[0]
            parts = version_line.split()
            if len(parts) > 1:
                version = parts[1]
                print(f"[DEBUG] Found Xray version: {version}")
                break
    
    # Статус Xray - пробуем разные методы
    status_commands = [
        ['docker', 'exec', 'remnanode', 'supervisorctl', 'status', 'xray'],
        ['docker', 'exec', 'remnanode', 'ps', 'aux']
    ]
    
    for i, cmd in enumerate(status_commands):
        status_result = run_command(cmd, timeout=5)
        if status_result["success"]:
            output = status_result["output"].lower()
            if i == 0:  # supervisorctl
                if 'running' in output or 'active' in output:
                    status = "running"
                    break
            else:  # ps aux
                if 'xray' in output:
                    status = "running"
                    break
    
    return version, status

def get_caddy_status():
    """Проверка статуса Caddy"""
    # Системный процесс
    if check_service_status('caddy'):
        return "running"
    
    # Docker контейнер
    docker_result = run_command([
        'docker', 'ps', '--filter', 'name=caddy', 
        '--format', '{{.State}}'
    ], timeout=5)
    
    if docker_result["success"] and 'running' in docker_result["output"].lower():
        return "running"
    
    return "inactive"

def get_bot_status():
    """Проверка статуса основного бота"""
    status = "inactive"
    hint = ""
    
    # Проверка через systemd
    if BOT_SERVICE_NAME and check_service_status(BOT_SERVICE_NAME):
        return "running", f"systemd:{BOT_SERVICE_NAME}"
    
    # Проверка через ps
    ps_result = run_command(['ps', 'aux'], timeout=5)
    if not ps_result["success"]:
        return status, hint
    
    ps_output = ps_result["output"].lower()
    
    # Формируем паттерны для поиска
    patterns = []
    if BOT_MATCH:
        for part in BOT_MATCH.replace(';', ',').split(','):
            if part.strip():
                patterns.append(part.strip().lower())
    
    # Добавляем стандартные паттерны
    patterns.extend([
        'solo_bot main.py',
        'solo_bot/main.py',
        '/solo_bot/main.py',
        '/solo bot/main.py',
        'venv/bin/python /root/solo_bot/main.py',
        'venv/bin/python /root/solo bot/main.py'
    ])
    
    # Проверяем паттерны
    for pattern in patterns:
        tokens = [t for t in pattern.replace('|', ' ').split() if t]
        if all(token in ps_output for token in tokens):
            return "running", "ps:match"
    
    return status, hint

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "ok",
        "ts": datetime.now().isoformat(),
        "version": "1.3.0-optimized"
    }), 200

@app.route('/api/status')
def status():
    """Основной endpoint статуса"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    # Получаем базовые метрики
    metrics = get_system_metrics()
    server_type = detect_server_type()
    
    # Получаем информацию о сервисах
    services = {}
    if server_type == "panel":
        services['node_exporter'] = "active" if check_service_status('node_exporter') else "inactive"
    else:
        services['tblocker'] = "active" if check_service_status('tblocker') else "inactive"
        services['node_exporter'] = "active" if check_service_status('node_exporter') else "inactive"
    
    # Информация о Xray (только для нод)
    xray_version, xray_status = ("N/A", "inactive")
    if server_type == "node":
        xray_version, xray_status = get_xray_info()
    
    # Статус Caddy
    caddy_status = get_caddy_status()
    
    # Статус бота
    bot_status, bot_hint = get_bot_status()
    
    return jsonify({
        "status": "online",
        "ts": datetime.now().isoformat(),
        "server_type": server_type,
        "services": services,
        "xray_version": xray_version,
        "xray_status": xray_status,
        "caddy_status": caddy_status,
        "bot_status": bot_status,
        "bot_hint": bot_hint,
        "docker": get_docker_info(),
        **metrics
    })

@app.route('/api/docker')
def docker():
    """Docker информация"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify(get_docker_info())

@app.route('/api/docker/restart', methods=['POST'])
def docker_restart():
    """Перезапуск Docker контейнеров"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    containers = ["remnanode", "caddy"]
    if request.is_json and 'containers' in request.json:
        containers = request.json['containers']
    
    results = {}
    for container in containers:
        results[container] = run_command(['docker', 'restart', container], timeout=30)
    
    return jsonify({
        "message": "restart requested",
        "results": results,
        "ts": datetime.now().isoformat()
    })

@app.route('/api/exec')
def exec_command():
    """Выполнение команд"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    cmd = request.args.get('command', 'echo ok')
    
    # Для Docker команд используем shell=True и больший timeout
    if 'docker' in cmd.lower():
        result = run_command(cmd, timeout=120, shell=True)
    else:
        result = run_command(cmd.split(), timeout=30)
    
    return jsonify({
        "command": cmd,
        **result
    })

@app.route('/api/reboot', methods=['POST'])
def reboot():
    """Перезагрузка сервера"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        subprocess.Popen(['reboot'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return jsonify({
            "message": "reboot initiated",
            "ts": datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/update_panel', methods=['POST'])
def update_panel():
    """Обновление панели Remnawave"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Ищем docker-compose файл панели
        compose_paths = [
            "/opt/remnawave/docker-compose.yml",
            "/opt/remnawave/docker-compose.yaml", 
            "/root/remnawave/docker-compose.yml",
            "/root/remnawave/docker-compose.yaml",
            "/home/remnawave/docker-compose.yml",
            "/home/remnawave/docker-compose.yaml"
        ]
        
        compose_file = None
        compose_dir = None
        
        # Проверяем существование файлов
        for path in compose_paths:
            check_result = run_command(f"test -f {path}", timeout=5, shell=True)
            if check_result["success"]:
                compose_file = path
                compose_dir = os.path.dirname(path)
                break
        
        if not compose_file:
            return jsonify({
                "success": False,
                "error": "Docker compose file not found",
                "searched_paths": compose_paths
            })
        
        print(f"[DEBUG] Found docker-compose file: {compose_file}")
        
        # Выполняем команды пошагово для лучшей диагностики
        commands = [
            f"cd {compose_dir}",
            f"cd {compose_dir} && docker compose pull",
            f"cd {compose_dir} && docker compose down",
            f"cd {compose_dir} && docker compose up -d"
        ]
        
        results = []
        for i, cmd in enumerate(commands):
            step_name = ["change_dir", "pull_images", "stop_containers", "start_containers"][i]
            print(f"[DEBUG] Executing step {i+1}/{len(commands)}: {step_name}")
            print(f"[DEBUG] Command: {cmd}")
            
            result = run_command(cmd, timeout=120, shell=True)
            results.append({
                "step": step_name,
                "command": cmd,
                "success": result["success"],
                "output": result["output"],
                "error": result["error"]
            })
            
            print(f"[DEBUG] Step {step_name}: success={result['success']}")
            if result["error"]:
                print(f"[DEBUG] Error: {result['error']}")
            
            # Если команда не удалась, останавливаем процесс
            if not result["success"]:
                return jsonify({
                    "success": False,
                    "error": f"Step {step_name} failed: {cmd}",
                    "details": result["error"],
                    "steps": results
                })
        
        return jsonify({
            "success": True,
            "message": "Panel updated successfully",
            "steps": results,
            "compose_file": compose_file,
            "compose_dir": compose_dir,
            "ts": datetime.now().isoformat()
        })
        
    except Exception as e:
        print(f"[ERROR] Error updating panel: {e}")
        return jsonify({
            "success": False,
            "error": f"Update failed: {str(e)}"
        })

@app.route('/api/debug_update')
def debug_update():
    """Отладочный endpoint для диагностики проблем обновления"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Проверяем Docker
        docker_check = run_command("docker --version", timeout=10, shell=True)
        
        # Проверяем docker-compose
        compose_check = run_command("docker compose version", timeout=10, shell=True)
        
        # Проверяем права доступа к директориям
        dirs_to_check = ["/opt/remnanode", "/opt/remnawave", "/root/remnanode", "/root/remnawave"]
        dir_permissions = {}
        
        for dir_path in dirs_to_check:
            ls_result = run_command(f"ls -la {dir_path} 2>/dev/null || echo 'Directory not found'", timeout=10, shell=True)
            dir_permissions[dir_path] = ls_result.get("output", "N/A")
        
        # Проверяем текущие контейнеры
        containers_check = run_command("docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'", timeout=10, shell=True)
        
        # Проверяем docker-compose файлы
        compose_files = {}
        compose_paths = [
            "/opt/remnanode/docker-compose.yml",
            "/opt/remnanode/docker-compose.yaml",
            "/root/remnanode/docker-compose.yml", 
            "/root/remnanode/docker-compose.yaml",
            "/opt/remnawave/docker-compose.yml",
            "/opt/remnawave/docker-compose.yaml", 
            "/root/remnawave/docker-compose.yml",
            "/root/remnawave/docker-compose.yaml"
        ]
        
        for path in compose_paths:
            check_result = run_command(f"test -f {path} && echo 'EXISTS' || echo 'NOT_FOUND'", timeout=5, shell=True)
            compose_files[path] = check_result.get("output", "N/A")
        
        return jsonify({
            "success": True,
            "docker_version": docker_check.get("output", "N/A"),
            "compose_version": compose_check.get("output", "N/A"),
            "directory_permissions": dir_permissions,
            "compose_files": compose_files,
            "current_containers": containers_check.get("output", "N/A"),
            "user_info": run_command("whoami && id", timeout=5, shell=True).get("output", "N/A"),
            "working_directory": run_command("pwd", timeout=5, shell=True).get("output", "N/A"),
            "ts": datetime.now().isoformat()
        })
        
    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Debug failed: {str(e)}"
        })

@app.route('/api/test_update_node')
def test_update_node():
    """Тестовый endpoint для диагностики проблем обновления ноды"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Ищем docker-compose файл ноды
        compose_paths = [
            "/opt/remnanode/docker-compose.yml",
            "/opt/remnanode/docker-compose.yaml",
            "/root/remnanode/docker-compose.yml", 
            "/root/remnanode/docker-compose.yaml",
            "/home/remnanode/docker-compose.yml",
            "/home/remnanode/docker-compose.yaml"
        ]
        
        compose_file = None
        compose_dir = None
        
        # Проверяем существование файлов
        for path in compose_paths:
            check_result = run_command(f"test -f {path}", timeout=5, shell=True)
            if check_result["success"]:
                compose_file = path
                compose_dir = os.path.dirname(path)
                break
        
        if not compose_file:
            return jsonify({
                "success": False,
                "error": "Docker compose file not found",
                "searched_paths": compose_paths
            })
        
        # Выполняем диагностические команды
        diagnostic_commands = [
            f"cd {compose_dir} && pwd",
            f"cd {compose_dir} && ls -la",
            f"cd {compose_dir} && docker --version",
            f"cd {compose_dir} && docker compose version",
            f"cd {compose_dir} && docker compose config",
            f"cd {compose_dir} && docker compose ps"
        ]
        
        results = []
        for i, cmd in enumerate(diagnostic_commands):
            step_name = ["check_dir", "list_files", "docker_version", "compose_version", "compose_config", "compose_status"][i]
            print(f"[DEBUG] Executing diagnostic step {i+1}/{len(diagnostic_commands)}: {step_name}")
            
            result = run_command(cmd, timeout=30, shell=True)
            results.append({
                "step": step_name,
                "command": cmd,
                "success": result["success"],
                "output": result["output"],
                "error": result["error"]
            })
            
            print(f"[DEBUG] Diagnostic step {step_name}: success={result['success']}")
            if result["error"]:
                print(f"[DEBUG] Error: {result['error']}")
        
        return jsonify({
            "success": True,
            "compose_file": compose_file,
            "compose_dir": compose_dir,
            "diagnostic_results": results,
            "ts": datetime.now().isoformat()
        })
        
    except Exception as e:
        print(f"[ERROR] Error in test_update_node: {e}")
        return jsonify({
            "success": False,
            "error": f"Test failed: {str(e)}"
        })

@app.route('/api/test_compose')
def test_compose():
    """Тест команд docker compose"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Тестируем разные варианты команд
        commands_to_test = [
            "docker compose version",
            "docker-compose version", 
            "docker compose --version",
            "docker-compose --version"
        ]
        
        results = {}
        for cmd in commands_to_test:
            result = run_command(cmd, timeout=10, shell=True)
            results[cmd] = {
                "success": result["success"],
                "output": result["output"],
                "error": result["error"]
            }
        
        return jsonify({
            "success": True,
            "compose_tests": results,
            "ts": datetime.now().isoformat()
        })
        
    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Test failed: {str(e)}"
        })

@app.route('/api/update_node', methods=['POST'])
def update_node():
    """Обновление ноды RemnaNode"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Ищем docker-compose файл ноды
        compose_paths = [
            "/opt/remnanode/docker-compose.yml",
            "/opt/remnanode/docker-compose.yaml",
            "/root/remnanode/docker-compose.yml", 
            "/root/remnanode/docker-compose.yaml",
            "/home/remnanode/docker-compose.yml",
            "/home/remnanode/docker-compose.yaml"
        ]
        
        compose_file = None
        compose_dir = None
        
        # Проверяем существование файлов
        for path in compose_paths:
            check_result = run_command(f"test -f {path}", timeout=5, shell=True)
            if check_result["success"]:
                compose_file = path
                compose_dir = os.path.dirname(path)
                break
        
        if not compose_file:
            return jsonify({
                "success": False,
                "error": "Docker compose file not found",
                "searched_paths": compose_paths
            })
        
        print(f"[DEBUG] Found docker-compose file: {compose_file}")
        
        # Выполняем команды пошагово для лучшей диагностики
        commands = [
            f"cd {compose_dir}",
            f"cd {compose_dir} && docker compose pull",
            f"cd {compose_dir} && docker compose down",
            f"cd {compose_dir} && docker compose up -d"
        ]
        
        results = []
        for i, cmd in enumerate(commands):
            step_name = ["change_dir", "pull_images", "stop_containers", "start_containers"][i]
            print(f"[DEBUG] Executing step {i+1}/{len(commands)}: {step_name}")
            print(f"[DEBUG] Command: {cmd}")
            
            result = run_command(cmd, timeout=120, shell=True)
            results.append({
                "step": step_name,
                "command": cmd,
                "success": result["success"],
                "output": result["output"],
                "error": result["error"]
            })
            
            print(f"[DEBUG] Step {step_name}: success={result['success']}")
            if result["error"]:
                print(f"[DEBUG] Error: {result['error']}")
            
            # Если команда не удалась, останавливаем процесс
            if not result["success"]:
                return jsonify({
                    "success": False,
                    "error": f"Step {step_name} failed: {cmd}",
                    "details": result["error"],
                    "steps": results
                })
        
        return jsonify({
            "success": True,
            "message": "Node updated successfully",
            "steps": results,
            "compose_file": compose_file,
            "compose_dir": compose_dir,
            "ts": datetime.now().isoformat()
        })
        
    except Exception as e:
        print(f"[ERROR] Error updating node: {e}")
        return jsonify({
            "success": False,
            "error": f"Update failed: {str(e)}"
        })

@app.route('/api/test_node_update')
def test_node_update():
    """Тестовый эндпоинт для проверки обновления ноды"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Проверяем Docker
        docker_check = run_command("docker --version", timeout=10, shell=True)
        
        # Проверяем docker-compose
        compose_check = run_command("docker compose version", timeout=10, shell=True)
        
        # Ищем файлы ноды
        compose_paths = [
            "/opt/remnanode/docker-compose.yml",
            "/opt/remnanode/docker-compose.yaml",
            "/root/remnanode/docker-compose.yml", 
            "/root/remnanode/docker-compose.yaml",
            "/home/remnanode/docker-compose.yml",
            "/home/remnanode/docker-compose.yaml"
        ]
        
        found_files = []
        for path in compose_paths:
            check_result = run_command(f"test -f {path}", timeout=5, shell=True)
            if check_result["success"]:
                found_files.append(path)
        
        # Проверяем текущие контейнеры
        containers_check = run_command("docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'", timeout=10, shell=True)
        
        return jsonify({
            "success": True,
            "docker_version": docker_check.get("output", "N/A"),
            "compose_version": compose_check.get("output", "N/A"),
            "found_compose_files": found_files,
            "searched_paths": compose_paths,
            "current_containers": containers_check.get("output", "N/A"),
            "ts": datetime.now().isoformat()
        })
        
    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Test failed: {str(e)}"
        })

@app.route('/api/test_panel_update')
def test_panel_update():
    """Тестовый эндпоинт для проверки обновления панели"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Проверяем Docker
        docker_check = run_command("docker --version", timeout=10, shell=True)
        
        # Проверяем docker-compose
        compose_check = run_command("docker compose version", timeout=10, shell=True)
        
        # Ищем файлы панели
        compose_paths = [
            "/opt/remnawave/docker-compose.yml",
            "/opt/remnawave/docker-compose.yaml", 
            "/root/remnawave/docker-compose.yml",
            "/root/remnawave/docker-compose.yaml",
            "/home/remnawave/docker-compose.yml",
            "/home/remnawave/docker-compose.yaml"
        ]
        
        found_files = []
        for path in compose_paths:
            check_result = run_command(f"test -f {path}", timeout=5, shell=True)
            if check_result["success"]:
                found_files.append(path)
        
        # Проверяем текущие контейнеры
        containers_check = run_command("docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'", timeout=10, shell=True)
        
        return jsonify({
            "success": True,
            "docker_version": docker_check.get("output", "N/A"),
            "compose_version": compose_check.get("output", "N/A"),
            "found_compose_files": found_files,
            "searched_paths": compose_paths,
            "current_containers": containers_check.get("output", "N/A"),
            "ts": datetime.now().isoformat()
        })
        
    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Test failed: {str(e)}"
        })

@app.route('/api/mtr')
def mtr_report():
    """MTR диагностика сети"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    target = request.args.get('target', '8.8.8.8')
    cycles = request.args.get('cycles', '10')
    
    # Используем traceroute по умолчанию (не требует root прав)
    traceroute_check = run_command(['which', 'traceroute'], timeout=5)
    if traceroute_check["success"]:
        result = run_command(['traceroute', '-n', target], timeout=60)
    else:
        # Fallback на MTR без sudo
        mtr_check = run_command(['which', 'mtr'], timeout=5)
        if mtr_check["success"]:
            result = run_command([
                'mtr', '--report', '--report-cycles', str(cycles), '--no-dns', target
            ], timeout=60)
        else:
            return jsonify({
                "error": "Ни traceroute, ни MTR не установлены",
                "success": False
            })
    
    if result["success"]:
        return jsonify({
            "success": True,
            "target": target,
            "cycles": cycles,
            "output": result["output"],
            "ts": datetime.now().isoformat()
        })
    else:
        return jsonify({
            "success": False,
            "error": result["error"] or "MTR завершился с ошибкой",
            "output": result["output"]
        })

@app.route('/api/speedtest', methods=['POST'])
def speedtest():
    """Speedtest через speedtest-cli"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Проверяем наличие speedtest-cli
        speedtest_check = run_command(['which', 'speedtest-cli'], timeout=5)
        if not speedtest_check["success"]:
            return jsonify({
                "success": False,
                "error": "speedtest-cli не установлен. Установите: apt install speedtest-cli"
            })
        
        # Запускаем speedtest с более детальными параметрами
        result = run_command([
            'speedtest-cli', 
            '--json', 
            '--secure',  # Используем HTTPS
            '--timeout', '30',  # Увеличиваем timeout для каждого этапа
            '--single'  # Одиночный поток для более точного измерения
        ], timeout=90)
        
        if result["success"]:
            try:
                speedtest_data = json.loads(result["output"])
                return jsonify({
                    "success": True,
                    "data": {
                        "download": round(speedtest_data.get("download", 0) / 1000000, 2),  # MB/s
                        "upload": round(speedtest_data.get("upload", 0) / 1000000, 2),    # MB/s
                        "ping": round(speedtest_data.get("ping", 0), 2),                 # ms
                        "server": speedtest_data.get("server", {}).get("name", "Unknown"),
                        "server_id": speedtest_data.get("server", {}).get("id", "Unknown"),
                        "server_country": speedtest_data.get("server", {}).get("country", "Unknown"),
                        "server_sponsor": speedtest_data.get("server", {}).get("sponsor", "Unknown"),
                        "client_ip": speedtest_data.get("client", {}).get("ip", "Unknown"),
                        "client_isp": speedtest_data.get("client", {}).get("isp", "Unknown"),
                        "test_duration": "~30-60 сек"  # Примерное время
                    },
                    "ts": datetime.now().isoformat()
                })
            except json.JSONDecodeError:
                return jsonify({
                    "success": False,
                    "error": "Ошибка парсинга результата speedtest"
                })
        else:
            return jsonify({
                "success": False,
                "error": result["error"] or "Speedtest завершился с ошибкой"
            })
    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Ошибка выполнения speedtest: {str(e)}"
        })

@app.route('/api/tcp_ping', methods=['POST'])
def tcp_ping():
    """TCP ping к указанному порту"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        data = request.get_json() or {}
        port = data.get('port', 80)
        
        if not isinstance(port, int) or port < 1 or port > 65535:
            return jsonify({
                "success": False,
                "error": "Неверный порт. Должен быть числом от 1 до 65535"
            })
        
        # Используем nc (netcat) для TCP ping
        nc_check = run_command(['which', 'nc'], timeout=5)
        if not nc_check["success"]:
            return jsonify({
                "success": False,
                "error": "netcat не установлен. Установите: apt install netcat"
            })
        
        # TCP ping к localhost
        result = run_command(['nc', '-z', '-v', '-w', '3', 'localhost', str(port)], timeout=10)
        
        if result["success"]:
            return jsonify({
                "success": True,
                "data": {
                    "port": port,
                    "status": "Порт открыт",
                    "time": "~5ms"  # Примерное время
                },
                "ts": datetime.now().isoformat()
            })
        else:
            return jsonify({
                "success": False,
                "data": {
                    "port": port,
                    "status": "Порт закрыт",
                    "time": "N/A"
                },
                "error": "Порт недоступен"
            })
    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Ошибка TCP ping: {str(e)}"
        })

@app.route('/api/dns_lookup', methods=['POST'])
def dns_lookup():
    """DNS lookup домена"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        data = request.get_json() or {}
        domain = data.get('domain', 'google.com')
        
        if not domain or not isinstance(domain, str):
            return jsonify({
                "success": False,
                "error": "Неверный домен"
            })
        
        # Используем nslookup для DNS запроса
        result = run_command(['nslookup', domain], timeout=10)
        
        if result["success"]:
            # Парсим результат nslookup
            output = result["output"]
            ip_address = "N/A"
            ttl = "N/A"
            
            # Ищем IP адрес в выводе
            import re
            ip_match = re.search(r'Address:\s*(\d+\.\d+\.\d+\.\d+)', output)
            if ip_match:
                ip_address = ip_match.group(1)
            
            return jsonify({
                "success": True,
                "data": {
                    "domain": domain,
                    "ip": ip_address,
                    "time": "~15ms",  # Примерное время
                    "ttl": ttl
                },
                "ts": datetime.now().isoformat()
            })
        else:
            return jsonify({
                "success": False,
                "error": result["error"] or "DNS lookup завершился с ошибкой"
            })
    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Ошибка DNS lookup: {str(e)}"
        })

@app.route('/api/port_scan', methods=['POST'])
def port_scan():
    """Сканирование портов"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        data = request.get_json() or {}
        scan_type = data.get('scan_type', 'common')
        
        # Определяем порты для сканирования
        port_ranges = {
            'quick': [22, 80, 443],
            'common': [21, 22, 23, 25, 53, 80, 110, 143, 443, 993, 995],
            'web': [80, 443, 8080, 8443],
            'ssh': [22, 2222],
            'full': list(range(1, 1025))  # Порты 1-1024
        }
        
        ports_to_scan = port_ranges.get(scan_type, port_ranges['common'])
        
        # Используем nmap если доступен, иначе nc
        nmap_check = run_command(['which', 'nmap'], timeout=5)
        open_ports = []
        
        if nmap_check["success"]:
            # Используем nmap для быстрого сканирования
            ports_str = ','.join(map(str, ports_to_scan))
            result = run_command(['nmap', '-p', ports_str, 'localhost', '--open'], timeout=30)
            
            if result["success"]:
                # Парсим результат nmap
                import re
                port_matches = re.findall(r'(\d+)/tcp\s+open\s+(\w+)', result["output"])
                for port, service in port_matches:
                    open_ports.append({
                        "port": int(port),
                        "service": service
                    })
        else:
            # Fallback на nc
            nc_check = run_command(['which', 'nc'], timeout=5)
            if nc_check["success"]:
                for port in ports_to_scan:
                    result = run_command(['nc', '-z', '-v', '-w', '1', 'localhost', str(port)], timeout=5)
                    if result["success"]:
                        open_ports.append({
                            "port": port,
                            "service": "unknown"
                        })
            else:
                return jsonify({
                    "success": False,
                    "error": "Ни nmap, ни netcat не установлены. Установите: apt install nmap netcat"
                })
        
        return jsonify({
            "success": True,
            "data": {
                "scan_type": scan_type,
                "open_ports": open_ports,
                "duration": "~5s"  # Примерное время
            },
            "ts": datetime.now().isoformat()
        })
        
    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Ошибка сканирования портов: {str(e)}"
        })

if __name__ == '__main__':
    print('🚀 Starting Optimized Node API v1.3.0 on :8080')
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF
    
    chmod +x "$NODE_API_SCRIPT"
    chown "$NODE_API_USER:$NODE_API_USER" "$NODE_API_SCRIPT"
    
    log "Node API скрипт создан"
}

# Создание systemd сервиса
create_systemd_service() {
    info "Создание systemd сервиса..."
    
    cat > "$SYSTEMD_SERVICE_FILE" << EOF
[Unit]
Description=Node API (Optimized)
Documentation=https://github.com/spakieone/node-api
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
User=$NODE_API_USER
Group=$NODE_API_USER
WorkingDirectory=$NODE_API_DIR

# Environment variables
Environment="NODE_API_TOKEN=$NODE_API_TOKEN"
Environment="PYTHONUNBUFFERED=1"
Environment="VIRTUAL_ENV=$NODE_API_DIR/venv"
Environment="PATH=$NODE_API_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Service configuration
ExecStart=$NODE_API_DIR/venv/bin/python $NODE_API_SCRIPT
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=3

# Security settings (NoNewPrivileges отключен для sudo MTR)
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$NODE_API_DIR
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=node-api

[Install]
WantedBy=multi-user.target
EOF
    
    log "Systemd сервис создан"
}

# Настройка firewall
setup_firewall() {
    info "Настройка firewall..."
    
    case "$OS_ID" in
        ubuntu|debian)
            if command -v ufw >/dev/null 2>&1; then
                ufw --force enable 2>/dev/null || true
                ufw allow 8080/tcp || warn "Не удалось открыть порт 8080 в UFW"
                log "UFW настроен (порт 8080 открыт)"
            else
                warn "UFW не найден, пропускаем настройку firewall"
            fi
            ;;
        centos|rhel|fedora)
            if command -v firewall-cmd >/dev/null 2>&1; then
                systemctl enable firewalld 2>/dev/null || true
                systemctl start firewalld 2>/dev/null || true
                firewall-cmd --permanent --add-port=8080/tcp || warn "Не удалось открыть порт 8080 в firewalld"
                firewall-cmd --reload || true
                log "Firewalld настроен (порт 8080 открыт)"
            else
                warn "Firewalld не найден, пропускаем настройку firewall"
            fi
            ;;
        *)
            warn "Неизвестная ОС, пропускаем настройку firewall"
            ;;
    esac
}

# Запуск сервиса
start_service() {
    info "Запуск Node API сервиса..."
    
    systemctl daemon-reload
    systemctl enable node-api
    
    if systemctl start node-api; then
        log "Node API сервис запущен"
    else
        err "Не удалось запустить Node API сервис"
        info "Проверьте логи: journalctl -u node-api -f"
        exit 1
    fi
    
    # Проверяем что сервис действительно работает
    sleep 3
    if systemctl is-active --quiet node-api; then
        log "Node API сервис активен"
    else
        err "Node API сервис не активен после запуска"
        info "Логи сервиса:"
        journalctl -u node-api --no-pager -n 20
        exit 1
    fi
}

# Финальная проверка
final_check() {
    info "Выполнение финальной проверки..."
    
    # Проверяем health endpoint
    sleep 2
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        log "Health endpoint отвечает"
    else
        warn "Health endpoint не отвечает (возможно, сервис еще запускается)"
    fi
    
    # Показываем информацию для проверки
    echo
    info "Установка завершена! Для проверки выполните:"
    echo -e "${BLUE}curl -H 'Authorization: Bearer $NODE_API_TOKEN' http://localhost:8080/api/status${NC}"
    echo
    info "Логи сервиса: journalctl -u node-api -f"
    info "Статус сервиса: systemctl status node-api"
}

# Cleanup функция
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        err "Установка прервана с ошибкой (код: $exit_code)"
        warn "Для очистки выполните: sudo systemctl stop node-api && sudo rm -rf $NODE_API_DIR"
    fi
}

# Основная функция
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                 ${GREEN}Node API Installer v1.2.0${NC}                    ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                     ${YELLOW}Optimized Edition${NC}                        ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    trap cleanup EXIT
    
    require_root
    detect_os
    get_api_token
    
    info "Начинаем установку Node API + MTR..."
    
    install_system_packages
    install_mtr
    create_user
    setup_directory
    create_node_api_script
    create_systemd_service
    setup_firewall
    start_service
    final_check
    
    echo
    log "🎉 Установка Node API успешно завершена!"
}

# Запуск
main "$@"
