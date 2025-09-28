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

    # 2. Исправляем dpkg если нужно
    log "Проверка состояния dpkg..."
    dpkg --configure -a
    if [ $? -ne 0 ]; then
        log "dpkg был прерван, исправляем..."
        dpkg --configure -a
        sleep 2
    fi
    
    # 3. Устанавливаем Python3 и pip
    log "Установка Python3 и pip..."
    apt update
    apt install -y python3 python3-pip python3-venv curl wget
    
    # Проверяем что pip3 установился
    if ! command -v pip3 &> /dev/null; then
        error "pip3 не установлен! Попробуйте: apt install python3-pip"
        return 1
    fi

    # 4. Создаем директорию для Node API
    log "Создание директории $NODE_API_DIR..."
    mkdir -p "$NODE_API_DIR"
    chown "$NODE_MANAGER_USER":"$NODE_MANAGER_USER" "$NODE_API_DIR"

    # 5. Создаем улучшенный скрипт Node API
    log "Создание улучшенного скрипта node_api.py..."
    cat > "$NODE_API_SCRIPT" << 'EOF'
#!/usr/bin/env python3
"""
Enhanced Node API для мониторинга всех компонентов ноды
Enhanced Node API for comprehensive node monitoring
"""

from flask import Flask, request, jsonify
import subprocess
import os
import psutil
import json
import time
import re
from datetime import datetime, timedelta
import platform
import socket

app = Flask(__name__)

# Токен для авторизации
AUTH_TOKEN = os.getenv("NODE_API_TOKEN", "your-secret-token")

def check_auth():
    """Проверка авторизации"""
    token = request.headers.get('Authorization')
    if not token or token != f"Bearer {AUTH_TOKEN}":
        return False
    return True

def run_command(cmd, timeout=30, shell=False):
    """Безопасное выполнение команд"""
    try:
        if shell:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        else:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return {
            'success': result.returncode == 0,
            'output': result.stdout.strip(),
            'error': result.stderr.strip(),
            'returncode': result.returncode
        }
    except subprocess.TimeoutExpired:
        return {
            'success': False,
            'output': '',
            'error': f'Command timeout after {timeout}s',
            'returncode': -1
        }
    except Exception as e:
        return {
            'success': False,
            'output': '',
            'error': str(e),
            'returncode': -1
        }

def get_docker_info():
    """Получение информации о Docker контейнерах"""
    docker_info = {
        'containers': [],
        'images': [],
        'system_info': {},
        'remnanode': {'status': 'N/A', 'version': 'N/A', 'uptime': 'N/A'},
        'caddy': {'status': 'N/A', 'version': 'N/A', 'uptime': 'N/A'},
        'xray': {'status': 'N/A', 'version': 'N/A', 'uptime': 'N/A'}
    }
    
    # Словарь для быстрого доступа к контейнерам по имени
    containers_dict = {}
    
    try:
        # Получаем список контейнеров
        result = run_command(['docker', 'ps', '-a', '--format', 'json'])
        if result['success']:
            containers = []
            for line in result['output'].split('\n'):
                if line.strip():
                    try:
                        container = json.loads(line)
                        containers.append(container)
                        
                        # Добавляем в словарь для быстрого доступа
                        container_name = container.get('Names', '').strip('/')
                        if container_name:
                            containers_dict[container_name] = container
                            
                    except json.JSONDecodeError:
                        continue
            
            docker_info['containers'] = containers
            
            # Анализируем контейнеры
            for container in containers:
                name = container.get('Names', '').lower()
                status = container.get('State', '')
                
                if 'remnanode' in name:
                    docker_info['remnanode']['status'] = status
                    # Получаем версию RemnaNode
                    version_result = run_command(['docker', 'exec', container.get('Names', ''), 'node', '--version'], timeout=10)
                    if version_result['success']:
                        docker_info['remnanode']['version'] = version_result['output']
                    
                    # Получаем uptime
                    uptime_result = run_command(['docker', 'exec', container.get('Names', ''), 'uptime'], timeout=10)
                    if uptime_result['success']:
                        docker_info['remnanode']['uptime'] = uptime_result['output']
                
                elif 'caddy' in name:
                    docker_info['caddy']['status'] = status
                    # Получаем версию Caddy
                    version_result = run_command(['docker', 'exec', container.get('Names', ''), 'caddy', 'version'], timeout=10)
                    if version_result['success']:
                        docker_info['caddy']['version'] = version_result['output']
                    
                    # Получаем uptime
                    uptime_result = run_command(['docker', 'exec', container.get('Names', ''), 'uptime'], timeout=10)
                    if uptime_result['success']:
                        docker_info['caddy']['uptime'] = uptime_result['output']
        
        # Получаем информацию о Docker системе
        system_result = run_command(['docker', 'system', 'df', '--format', 'json'])
        if system_result['success']:
            try:
                docker_info['system_info'] = json.loads(system_result['output'])
            except json.JSONDecodeError:
                pass
        
        # Получаем список образов
        images_result = run_command(['docker', 'images', '--format', 'json'])
        if images_result['success']:
            images = []
            for line in images_result['output'].split('\n'):
                if line.strip():
                    try:
                        image = json.loads(line)
                        images.append(image)
                    except json.JSONDecodeError:
                        continue
            docker_info['images'] = images
            
    except Exception as e:
        docker_info['error'] = str(e)
    
    # Возвращаем данные в формате, который ожидает бот мониторинга
    return {
        'success': True,
        'containers': containers_dict,
        'system_info': docker_info.get('system_info', {}),
        'remnanode': docker_info.get('remnanode', {}),
        'caddy': docker_info.get('caddy', {}),
        'xray': docker_info.get('xray', {}),
        'raw_containers': docker_info.get('containers', []),
        'images': docker_info.get('images', [])
    }

def get_xray_info():
    """Получение информации о Xray Core"""
    xray_info = {
        'status': 'N/A',
        'version': 'N/A',
        'config_status': 'N/A',
        'uptime': 'N/A',
        'connections': 'N/A',
        'config_file': '/usr/local/etc/xray/config.json'
    }
    
    try:
        # Проверяем статус сервиса
        status_result = run_command(['systemctl', 'is-active', 'xray'])
        if status_result['success']:
            xray_info['status'] = status_result['output']
        
        # Получаем версию
        version_result = run_command(['xray', 'version'])
        if version_result['success']:
            version_line = version_result['output'].split('\n')[0]
            if 'Xray' in version_line:
                xray_info['version'] = version_line.split()[1] if len(version_line.split()) > 1 else 'N/A'
        
        # Проверяем конфигурационный файл
        if os.path.exists(xray_info['config_file']):
            xray_info['config_status'] = 'exists'
            # Проверяем валидность конфигурации
            config_result = run_command(['xray', 'test', '-c', xray_info['config_file']])
            if config_result['success']:
                xray_info['config_status'] = 'valid'
            else:
                xray_info['config_status'] = f'invalid: {config_result["error"]}'
        else:
            xray_info['config_status'] = 'not_found'
        
        # Получаем uptime сервиса
        uptime_result = run_command(['systemctl', 'show', 'xray', '--property=ActiveEnterTimestamp'])
        if uptime_result['success']:
            timestamp = uptime_result['output'].split('=')[1] if '=' in uptime_result['output'] else None
            if timestamp:
                try:
                    # Парсим timestamp и вычисляем uptime
                    start_time = datetime.fromisoformat(timestamp.replace(' ', 'T'))
                    uptime = datetime.now() - start_time
                    xray_info['uptime'] = str(uptime).split('.')[0]  # Убираем микросекунды
                except:
                    pass
        
        # Получаем количество соединений (если доступно)
        connections_result = run_command(['ss', '-tuln'], timeout=10)
        if connections_result['success']:
            # Считаем открытые порты (приблизительная оценка активности)
            lines = connections_result['output'].split('\n')
            xray_info['connections'] = len([line for line in lines if 'LISTEN' in line])
            
    except Exception as e:
        xray_info['error'] = str(e)
    
    return xray_info

def get_system_info():
    """Получение расширенной системной информации"""
    system_info = {
        'hostname': socket.gethostname(),
        'os': platform.system(),
        'os_version': platform.release(),
        'architecture': platform.machine(),
        'cpu': {},
        'memory': {},
        'disk': {},
        'network': {},
        'uptime': 'N/A',
        'load_average': 'N/A',
        'processes': 'N/A',
        'services': {}
    }
    
    try:
        # CPU информация
        cpu_percent = psutil.cpu_percent(interval=1)
        cpu_count = psutil.cpu_count()
        cpu_freq = psutil.cpu_freq()
        
        system_info['cpu'] = {
            'usage_percent': cpu_percent,
            'count': cpu_count,
            'frequency_mhz': cpu_freq.current if cpu_freq else 'N/A',
            'load_avg': os.getloadavg() if hasattr(os, 'getloadavg') else 'N/A'
        }
        
        # Память
        memory = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        system_info['memory'] = {
            'total_gb': round(memory.total / (1024**3), 2),
            'used_gb': round(memory.used / (1024**3), 2),
            'free_gb': round(memory.free / (1024**3), 2),
            'usage_percent': memory.percent,
            'swap_total_gb': round(swap.total / (1024**3), 2),
            'swap_used_gb': round(swap.used / (1024**3), 2),
            'swap_percent': swap.percent
        }
        
        # Диск
        disk = psutil.disk_usage('/')
        disk_io = psutil.disk_io_counters()
        
        system_info['disk'] = {
            'total_gb': round(disk.total / (1024**3), 2),
            'used_gb': round(disk.used / (1024**3), 2),
            'free_gb': round(disk.free / (1024**3), 2),
            'usage_percent': round((disk.used / disk.total) * 100, 2),
            'read_bytes': disk_io.read_bytes if disk_io else 'N/A',
            'write_bytes': disk_io.write_bytes if disk_io else 'N/A'
        }
        
        # Сеть
        network_io = psutil.net_io_counters()
        network_connections = psutil.net_connections()
        
        system_info['network'] = {
            'bytes_sent': network_io.bytes_sent if network_io else 'N/A',
            'bytes_recv': network_io.bytes_recv if network_io else 'N/A',
            'packets_sent': network_io.packets_sent if network_io else 'N/A',
            'packets_recv': network_io.packets_recv if network_io else 'N/A',
            'connections_count': len(network_connections)
        }
        
        # Uptime системы
        uptime_result = run_command(['uptime', '-p'])
        if uptime_result['success']:
            system_info['uptime'] = uptime_result['output']
        
        # Load average
        load_result = run_command(['uptime'])
        if load_result['success']:
            # Извлекаем load average из вывода uptime
            load_match = re.search(r'load average: ([\d.]+), ([\d.]+), ([\d.]+)', load_result['output'])
            if load_match:
                system_info['load_average'] = {
                    '1min': load_match.group(1),
                    '5min': load_match.group(2),
                    '15min': load_match.group(3)
                }
        
        # Количество процессов
        system_info['processes'] = len(psutil.pids())
        
        # Статус важных сервисов
        important_services = ['node_exporter', 'tblocker', 'xray', 'docker']
        for service in important_services:
            service_result = run_command(['systemctl', 'is-active', service])
            system_info['services'][service] = service_result['output'] if service_result['success'] else 'inactive'
            
    except Exception as e:
        system_info['error'] = str(e)
    
    return system_info

def get_node_exporter_metrics():
    """Получение метрик от Node Exporter"""
    metrics = {
        'cpu_usage': 'N/A',
        'memory_usage': 'N/A',
        'disk_usage': 'N/A',
        'network_io': 'N/A',
        'load_average': 'N/A',
        'uptime': 'N/A'
    }
    
    try:
        # Получаем метрики с Node Exporter
        result = run_command(['curl', '-s', 'http://localhost:9100/metrics'], timeout=10)
        if result['success']:
            lines = result['output'].split('\n')
            
            for line in lines:
                if line.startswith('node_cpu_seconds_total'):
                    # Простая оценка CPU usage
                    metrics['cpu_usage'] = 'available'
                elif line.startswith('node_memory_MemTotal_bytes'):
                    metrics['memory_usage'] = 'available'
                elif line.startswith('node_filesystem_size_bytes'):
                    metrics['disk_usage'] = 'available'
                elif line.startswith('node_load1'):
                    metrics['load_average'] = 'available'
                elif line.startswith('node_boot_time_seconds'):
                    metrics['uptime'] = 'available'
                    
    except Exception as e:
        metrics['error'] = str(e)
    
    return metrics

@app.route('/health', methods=['GET'])
def health_check():
    """Проверка здоровья API"""
    return jsonify({
        "status": "ok",
        "timestamp": datetime.now().isoformat(),
        "version": "2.0.0"
    }), 200

@app.route('/api/status', methods=['GET'])
def get_status():
    """Получение полного статуса ноды"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Собираем всю информацию
        system_info = get_system_info()
        docker_info = get_docker_info()
        xray_info = get_xray_info()
        node_exporter_metrics = get_node_exporter_metrics()
        
        return jsonify({
            "status": "online",
            "timestamp": datetime.now().isoformat(),
            "system": system_info,
            "docker": docker_info,
            "xray": xray_info,
            "node_exporter": node_exporter_metrics,
            "summary": {
                "cpu_usage": system_info['cpu']['usage_percent'],
                "memory_usage": system_info['memory']['usage_percent'],
                "disk_usage": system_info['disk']['usage_percent'],
                "remnanode_status": docker_info['remnanode']['status'],
                "caddy_status": docker_info['caddy']['status'],
                "xray_status": xray_info['status'],
                "node_exporter_status": system_info['services'].get('node_exporter', 'N/A'),
                "tblocker_status": system_info['services'].get('tblocker', 'N/A')
            }
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/system', methods=['GET'])
def get_system_status():
    """Получение системной информации"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        return jsonify(get_system_info())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/docker', methods=['GET'])
def get_docker_status():
    """Получение информации о Docker"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        return jsonify(get_docker_info())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/xray', methods=['GET'])
def get_xray_status():
    """Получение информации о Xray"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        return jsonify(get_xray_info())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/service/<service>/<action>', methods=['POST'])
def control_service(service, action):
    """Управление сервисами"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    if action not in ['start', 'stop', 'restart', 'status']:
        return jsonify({"error": "Invalid action"}), 400

    try:
        result = run_command(['systemctl', action, service], timeout=30)
        
        return jsonify({
            "service": service,
            "action": action,
            "success": result['success'],
            "output": result['output'],
            "error": result['error']
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/remnanode/<action>', methods=['POST'])
def control_remnanode(action):
    """Управление RemnaNode"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    if action not in ['restart', 'status', 'update', 'logs', 'stop', 'start']:
        return jsonify({"error": "Invalid action"}), 400

    try:
        if action == 'restart':
            result = run_command(['docker', 'restart', 'remnanode'], timeout=30)
        elif action == 'start':
            result = run_command(['docker', 'start', 'remnanode'], timeout=30)
        elif action == 'stop':
            result = run_command(['docker', 'stop', 'remnanode'], timeout=30)
        elif action == 'status':
            result = run_command(['docker', 'inspect', 'remnanode'], timeout=10)
        elif action == 'update':
            # Обновляем RemnaNode
            pull_result = run_command(['docker', 'pull', 'remnawave/node:latest'], timeout=120)
            if pull_result['success']:
                restart_result = run_command(['docker', 'restart', 'remnanode'], timeout=30)
                result = restart_result
            else:
                result = pull_result
        elif action == 'logs':
            result = run_command(['docker', 'logs', '--tail', '100', 'remnanode'], timeout=10)

        return jsonify({
            "action": action,
            "success": result['success'],
            "output": result['output'],
            "error": result['error']
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/xray/<action>', methods=['POST'])
def control_xray(action):
    """Управление Xray Core"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    if action not in ['restart', 'status', 'reload', 'test_config']:
        return jsonify({"error": "Invalid action"}), 400

    try:
        if action == 'restart':
            result = run_command(['systemctl', 'restart', 'xray'], timeout=30)
        elif action == 'status':
            result = run_command(['systemctl', 'status', 'xray'], timeout=10)
        elif action == 'reload':
            result = run_command(['systemctl', 'reload', 'xray'], timeout=30)
        elif action == 'test_config':
            result = run_command(['xray', 'test', '-c', '/usr/local/etc/xray/config.json'], timeout=10)

        return jsonify({
            "action": action,
            "success": result['success'],
            "output": result['output'],
            "error": result['error']
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/reboot', methods=['POST'])
def reboot_node():
    """Перезагрузка ноды"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        # Запускаем перезагрузку в фоне
        subprocess.Popen(['reboot'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return jsonify({
            "message": "Reboot initiated",
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/metrics', methods=['GET'])
def get_metrics():
    """Получение метрик для мониторинга"""
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    
    try:
        system_info = get_system_info()
        
        return jsonify({
            "timestamp": datetime.now().isoformat(),
            "cpu_usage_percent": system_info['cpu']['usage_percent'],
            "memory_usage_percent": system_info['memory']['usage_percent'],
            "disk_usage_percent": system_info['disk']['usage_percent'],
            "load_average": system_info['load_average'],
            "uptime": system_info['uptime'],
            "processes_count": system_info['processes'],
            "network_connections": system_info['network']['connections_count']
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    print(f"🚀 Starting Enhanced Node API v2.0.0")
    print(f"📊 Monitoring: System, Docker, Xray, RemnaNode, Node Exporter")
    print(f"🔐 Auth Token: {'*' * len(AUTH_TOKEN) if AUTH_TOKEN != 'your-secret-token' else 'DEFAULT (CHANGE!)'}")
    print(f"🌐 Listening on: 0.0.0.0:8080")
    
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF
    chmod +x "$NODE_API_SCRIPT"
    chown "$NODE_MANAGER_USER":"$NODE_MANAGER_USER" "$NODE_API_SCRIPT"

    # 6. Устанавливаем зависимости глобально (проще и надежнее)
    log "Установка зависимостей..."
    
    # Пробуем разные способы установки
    log "Попытка 1: apt install python3-flask python3-psutil..."
    apt install -y python3-flask python3-psutil
    
    if [ $? -ne 0 ]; then
        log "Попытка 2: pip3 install с --break-system-packages..."
        pip3 install --break-system-packages flask psutil
    fi
    
    if [ $? -ne 0 ]; then
        log "Попытка 3: python3 -m pip install с --break-system-packages..."
        python3 -m pip install --break-system-packages flask psutil
    fi
    
    # Проверяем что установка прошла успешно
    if [ $? -ne 0 ]; then
        error "Ошибка установки зависимостей! Попробуйте: pip3 install flask psutil"
        return 1
    fi
    
    # Проверяем установку
    log "Проверка установленных пакетов..."
    
    # Проверяем через pip3
    if command -v pip3 &> /dev/null; then
        pip3 list | grep -E "(flask|psutil)"
    fi
    
    # Проверяем через python3
    python3 -c "
import sys
try:
    import flask
    print('✅ Flask установлен')
except ImportError:
    print('❌ Flask не найден')
try:
    import psutil
    print('✅ psutil установлен')
except ImportError:
    print('❌ psutil не найден')
"
    # Проверяем что Python может импортировать модули
    log "Тестирование импорта модулей..."
    python3 -c "import flask; import psutil; print('✅ Все модули импортированы успешно')"
    
    if [ $? -ne 0 ]; then
        error "Ошибка импорта модулей! Проверьте установку: pip3 list"
        return 1
    fi

    # 7. Создаем systemd сервис
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
Environment="NODE_SERVICES=node_exporter,tblocker"
ExecStart=/usr/bin/python3 $NODE_API_SCRIPT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 8. Запускаем сервис
    log "Запуск сервиса Node API..."
    systemctl daemon-reload
    systemctl enable node-api
    systemctl start node-api

    # 9. Открываем порт в файрволе (если используется UFW)
    log "Настройка файрвола (UFW)..."
    if command -v ufw &> /dev/null; then
        ufw allow 8080/tcp
        ufw reload
        log "Порт 8080 открыт в UFW."
    else
        warn "UFW не найден, пропуск настройки файрвола."
    fi

    # 10. Сохраняем токен в файл для копирования в бот мониторинга
    log "Сохранение токена для бота мониторинга..."
    echo "NODE_API_TOKEN=$NODE_API_TOKEN" > /tmp/node_api_token.txt
    chmod 600 /tmp/node_api_token.txt

    log "✅ Установка Enhanced Node API v2.0.0 завершена!"
    echo ""
    info "📋 Проверка установки:"
    echo "   • Статус сервиса: sudo systemctl status node-api"
    echo "   • Проверка API: curl http://localhost:8080/health"
    echo "   • Полный статус: curl -H 'Authorization: Bearer $NODE_API_TOKEN' http://localhost:8080/api/status"
    echo "   • Логи сервиса: sudo journalctl -u node-api -f"
    echo ""
    echo -e "${BOLD}${GREEN}🚀 Новые возможности Enhanced Node API v2.0.0:${NC}"
    echo -e "${GREEN}   • 📊 Расширенный мониторинг системы (CPU, RAM, Disk, Network)${NC}"
    echo -e "${GREEN}   • 🐳 Детальная информация о Docker контейнерах${NC}"
    echo -e "${GREEN}   • ⚡ Мониторинг Xray Core (версия, статус, конфигурация)${NC}"
    echo -e "${GREEN}   • 🔧 Управление RemnaNode (restart, update, logs)${NC}"
    echo -e "${GREEN}   • 📈 Интеграция с Node Exporter${NC}"
    echo -e "${GREEN}   • 🔄 Новые endpoints: /api/system, /api/docker, /api/xray, /api/metrics${NC}"
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
    
    # Исправляем dpkg если нужно
    log "Проверка состояния dpkg..."
    dpkg --configure -a
    if [ $? -ne 0 ]; then
        log "dpkg был прерван, исправляем..."
        dpkg --configure -a
        sleep 2
    fi
    
    # Проверяем что pip3 установлен
    if ! command -v pip3 &> /dev/null; then
        log "Установка pip3..."
        apt update
        apt install -y python3-pip
        
        # Проверяем что pip3 установился
        if ! command -v pip3 &> /dev/null; then
            error "pip3 не установлен! Попробуйте: apt install python3-pip"
            return 1
        fi
    fi
    
    # Переустанавливаем зависимости
    log "Переустановка зависимостей..."
    
    # Пробуем разные способы установки
    log "Попытка 1: apt install python3-flask python3-psutil..."
    apt install -y python3-flask python3-psutil
    
    if [ $? -ne 0 ]; then
        log "Попытка 2: pip3 install с --break-system-packages..."
        pip3 install --break-system-packages --force-reinstall flask psutil
    fi
    
    if [ $? -ne 0 ]; then
        log "Попытка 3: python3 -m pip install с --break-system-packages..."
        python3 -m pip install --break-system-packages --force-reinstall flask psutil
    fi
    
    # Проверяем установку
    log "Проверка установленных пакетов..."
    
    # Проверяем через pip3
    if command -v pip3 &> /dev/null; then
        pip3 list | grep -E "(flask|psutil)"
    fi
    
    # Проверяем через python3
    python3 -c "
import sys
try:
    import flask
    print('✅ Flask установлен')
except ImportError:
    print('❌ Flask не найден')
try:
    import psutil
    print('✅ psutil установлен')
except ImportError:
    print('❌ psutil не найден')
"
    
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
