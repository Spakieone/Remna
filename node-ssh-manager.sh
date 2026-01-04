#!/bin/bash

# Node SSH Manager для Remnawave Panel
# Управление нодами через SSH

set -uo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция помощи
show_help() {
    cat << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📡 УПРАВЛЕНИЕ НОДАМИ ЧЕРЕЗ SSH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Использование:
  $0 <команда> <host> [опции]

Команды:
  status <host>              - Получить статус ноды
  update <host>              - Обновить RemnaNode
  core-update <host>         - Обновить Xray-core
  restart <host>             - Перезапустить RemnaNode
  logs <host>                - Показать логи

Опции:
  --user <user>              - SSH пользователь (по умолчанию: root)
  --port <port>              - SSH порт (по умолчанию: 22)
  --key <path>               - Путь к SSH ключу
  --password                 - Использовать пароль (интерактивно)
  --json                     - Вывод в формате JSON

Примеры:
  $0 status 192.168.1.100
  $0 status 192.168.1.100 --user admin --port 2222
  $0 update node.example.com --key /root/.ssh/node_key
  $0 status 192.168.1.100 --json

EOF
}

# Функция для выполнения SSH команды
execute_ssh_command() {
    local host="$1"
    local command="$2"
    local ssh_user="${SSH_USER:-root}"
    local ssh_port="${SSH_PORT:-22}"
    local ssh_key="${SSH_KEY:-}"
    local use_password="${USE_PASSWORD:-false}"
    
    # Формируем SSH команду
    local ssh_cmd="ssh"
    
    # Добавляем опции
    ssh_cmd="$ssh_cmd -o StrictHostKeyChecking=no"
    ssh_cmd="$ssh_cmd -o ConnectTimeout=10"
    ssh_cmd="$ssh_cmd -o BatchMode=yes"
    
    if [ -n "$ssh_key" ]; then
        ssh_cmd="$ssh_cmd -i $ssh_key"
    fi
    
    if [ "$use_password" = "true" ]; then
        ssh_cmd="$ssh_cmd -o BatchMode=no"
    fi
    
    ssh_cmd="$ssh_cmd -p $ssh_port"
    ssh_cmd="$ssh_cmd $ssh_user@$host"
    ssh_cmd="$ssh_cmd '$command'"
    
    # Выполняем команду
    if [ "$OUTPUT_JSON" = "true" ]; then
        local result=$(eval "$ssh_cmd" 2>&1)
        local exit_code=$?
        
        echo "{"
        echo "  \"success\": $([ $exit_code -eq 0 ] && echo "true" || echo "false"),"
        echo "  \"exit_code\": $exit_code,"
        echo "  \"output\": $(echo "$result" | jq -Rs .),"
        echo "  \"host\": \"$host\","
        echo "  \"command\": \"$command\""
        echo "}"
    else
        eval "$ssh_cmd"
    fi
}

# Функция получения статуса ноды
get_node_status() {
    local host="$1"
    local command="cd /opt/remnanode && /root/scripts/remnanode.sh status 2>&1 || echo 'RemnaNode не установлен'"
    
    if [ "$OUTPUT_JSON" = "true" ]; then
        execute_ssh_command "$host" "$command"
    else
        echo -e "${BLUE}📊 Получение статуса ноды: $host${NC}"
        echo ""
        execute_ssh_command "$host" "$command"
    fi
}

# Функция обновления RemnaNode
update_node() {
    local host="$1"
    local command="cd /opt/remnanode && /root/scripts/remnanode.sh update 2>&1"
    
    if [ "$OUTPUT_JSON" = "true" ]; then
        execute_ssh_command "$host" "$command"
    else
        echo -e "${BLUE}🔄 Обновление RemnaNode на ноде: $host${NC}"
        echo ""
        execute_ssh_command "$host" "$command"
    fi
}

# Функция обновления Xray-core
update_core() {
    local host="$1"
    local command="cd /opt/remnanode && /root/scripts/remnanode.sh core-update 2>&1"
    
    if [ "$OUTPUT_JSON" = "true" ]; then
        execute_ssh_command "$host" "$command"
    else
        echo -e "${BLUE}⬆️  Обновление Xray-core на ноде: $host${NC}"
        echo ""
        execute_ssh_command "$host" "$command"
    fi
}

# Функция перезапуска RemnaNode
restart_node() {
    local host="$1"
    local command="cd /opt/remnanode && /root/scripts/remnanode.sh restart 2>&1"
    
    if [ "$OUTPUT_JSON" = "true" ]; then
        execute_ssh_command "$host" "$command"
    else
        echo -e "${BLUE}🔄 Перезапуск RemnaNode на ноде: $host${NC}"
        echo ""
        execute_ssh_command "$host" "$command"
    fi
}

# Функция получения логов
get_node_logs() {
    local host="$1"
    local command="cd /opt/remnanode && /root/scripts/remnanode.sh logs 2>&1 | tail -50"
    
    if [ "$OUTPUT_JSON" = "true" ]; then
        execute_ssh_command "$host" "$command"
    else
        echo -e "${BLUE}📋 Логи ноды: $host${NC}"
        echo ""
        execute_ssh_command "$host" "$command"
    fi
}

# Парсинг аргументов
OUTPUT_JSON="false"
SSH_USER="root"
SSH_PORT="22"
SSH_KEY=""
USE_PASSWORD="false"
COMMAND=""
HOST=""

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --user)
            SSH_USER="$2"
            shift 2
            ;;
        --port)
            SSH_PORT="$2"
            shift 2
            ;;
        --key)
            SSH_KEY="$2"
            shift 2
            ;;
        --password)
            USE_PASSWORD="true"
            shift
            ;;
        --json)
            OUTPUT_JSON="true"
            shift
            ;;
        status|update|core-update|restart|logs)
            COMMAND="$1"
            if [ -n "$2" ] && [[ ! "$2" =~ ^-- ]]; then
                HOST="$2"
                shift 2
            else
                echo -e "${RED}❌ Ошибка: Укажите host для команды $1${NC}"
                exit 1
            fi
            ;;
        *)
            if [ -z "$COMMAND" ]; then
                echo -e "${RED}❌ Неизвестная команда: $1${NC}"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Проверка наличия команды и хоста
if [ -z "$COMMAND" ] || [ -z "$HOST" ]; then
    echo -e "${RED}❌ Ошибка: Укажите команду и host${NC}"
    show_help
    exit 1
fi

# Выполнение команды
case "$COMMAND" in
    status)
        get_node_status "$HOST"
        ;;
    update)
        update_node "$HOST"
        ;;
    core-update)
        update_core "$HOST"
        ;;
    restart)
        restart_node "$HOST"
        ;;
    logs)
        get_node_logs "$HOST"
        ;;
    *)
        echo -e "${RED}❌ Неизвестная команда: $COMMAND${NC}"
        exit 1
        ;;
esac

