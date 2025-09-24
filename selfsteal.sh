#!/usr/bin/env bash
# Caddy for Reality Selfsteal Installation Script
# This script installs and manages Caddy for Reality traffic masking
# VERSION=2.1.4

# Handle @ prefix for consistency with other scripts
if [ $# -gt 0 ] && [ "$1" = "@" ]; then
    shift  
fi

set -e
SCRIPT_VERSION="2.1.4"
GITHUB_REPO="Spakieone/Remna"
UPDATE_URL="https://raw.githubusercontent.com/$GITHUB_REPO/main/selfsteal.sh"
SCRIPT_URL="$UPDATE_URL"  # Алиас для совместимости
CONTAINER_NAME="caddy-selfsteal"
VOLUME_PREFIX="caddy"
CADDY_VERSION="2.9.1"

# Configuration
APP_NAME="selfsteal"
APP_DIR="/opt/caddy"
CADDY_CONFIG_DIR="$APP_DIR"
HTML_DIR="/opt/caddy/html"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color


# Parse command line arguments
COMMAND=""
if [ $# -gt 0 ]; then
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            echo "Скрипт управления Caddy Selfsteal v$SCRIPT_VERSION"
            exit 0
            ;;
        *)
            COMMAND="$1"
            ;;
    esac
fi
# Fetch IP address
NODE_IP=$(curl -s -4 ifconfig.io 2>/dev/null || echo "127.0.0.1")
if [ -z "$NODE_IP" ] || [ "$NODE_IP" = "" ]; then
    NODE_IP="127.0.0.1"
fi

# Check if running as root
check_running_as_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ Этот скрипт должен запускаться от root (используйте sudo)${NC}"
        exit 1
    fi
}

# Check system requirements
check_system_requirements() {
    echo -e "${WHITE}🔍 Проверка системных требований${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    echo

    local requirements_met=true

    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker не установлен${NC}"
        echo -e "${GRAY}   Сначала установите Docker${NC}"
        requirements_met=false
    else
        local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        echo -e "${GREEN}✅ Docker установлен: $docker_version${NC}"
    fi

    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker Compose V2 недоступен${NC}"
        requirements_met=false
    else
        local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✅ Docker Compose V2: $compose_version${NC}"
    fi

    # Check curl
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}❌ curl не установлен${NC}"
        requirements_met=false
    else
        echo -e "${GREEN}✅ curl доступен${NC}"
    fi

    # Check for existing Caddy installation
    if systemctl is-active --quiet caddy 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Обнаружен запущенный системный Caddy${NC}"
        local caddy_domain=""
        if [ -f "/etc/caddy/Caddyfile" ]; then
            caddy_domain=$(grep -E '^[a-zA-Z0-9.-]+\s*{' /etc/caddy/Caddyfile | head -1 | awk '{print $1}' | sed 's/{$//')
        fi
        if [ -n "$caddy_domain" ]; then
            echo -e "${GRAY}   Домен: $caddy_domain${NC}"
        fi
        echo -e "${GRAY}   PID: $(systemctl show -p MainPID --value caddy 2>/dev/null || echo 'unknown')${NC}"
        echo
        echo -e "${YELLOW}⚠️  Конфликт портов!${NC}"
        echo -e "${GRAY}   Системный Caddy может конфликтовать с Caddy Selfsteal${NC}"
        echo
        echo -e "${WHITE}🔧 Варианты действий:${NC}"
        echo -e "   ${WHITE}1)${NC} ${GRAY}Остановить и отключить системный Caddy${NC}"
        echo -e "   ${WHITE}2)${NC} ${GRAY}Продолжить установку (может вызвать конфликты)${NC}"
        echo -e "   ${WHITE}3)${NC} ${GRAY}Отменить установку${NC}"
        echo
        
        while true; do
            read -p "Выберите действие [1-3]: " caddy_choice
            case "$caddy_choice" in
                1)
                    echo -e "${YELLOW}🛑 Остановка системного Caddy...${NC}"
                    systemctl stop caddy 2>/dev/null || true
                    systemctl disable caddy 2>/dev/null || true
                    echo -e "${GREEN}✅ Системный Caddy остановлен и отключён${NC}"
                    echo
                    break
                    ;;
                2)
                    echo -e "${YELLOW}⚠️  Продолжаем установку с предупреждением о возможных конфликтах${NC}"
                    echo
                    break
                    ;;
                3)
                    echo -e "${GRAY}Установка отменена${NC}"
                    return 1
                    ;;
                *)
                    echo -e "${RED}❌ Неверный выбор. Введите 1, 2 или 3${NC}"
                    ;;
            esac
        done
    fi

    # Check available disk space
    local available_space=$(df / | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [ $available_gb -lt 1 ]; then
        echo -e "${RED}❌ Недостаточно места на диске: доступно ${available_gb}GB${NC}"
        requirements_met=false
    else
        echo -e "${GREEN}✅ Достаточно места на диске: доступно ${available_gb}GB${NC}"
    fi

    echo

    if [ "$requirements_met" = false ]; then
        echo -e "${RED}❌ Системные требования не выполнены!${NC}"
        return 1
    else
        echo -e "${GREEN}🎉 Все системные требования выполнены!${NC}"
        return 0
    fi
}


validate_domain_dns() {
    local domain="$1"
    local server_ip="$2"
    
    echo -e "${WHITE}🔍 Проверка DNS конфигурации${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    echo
    
    # Check if domain format is valid
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo -e "${RED}❌ Неверный формат домена!${NC}"
        echo -e "${GRAY}   Домен должен быть в формате: subdomain.domain.com${NC}"
        return 1
    fi
    
    echo -e "${WHITE}📝 Домен:${NC} $domain"
    echo -e "${WHITE}🖥️  IP сервера:${NC} $server_ip"
    echo
    
    # Check if dig is available
    if ! command -v dig >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Установка утилиты dig...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update >/dev/null 2>&1
            apt-get install -y dnsutils >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y bind-utils >/dev/null 2>&1
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y bind-utils >/dev/null 2>&1
        else
            echo -e "${RED}❌ Не удается установить утилиту dig автоматически${NC}"
            echo -e "${GRAY}   Установите вручную: apt install dnsutils${NC}"
            return 1
        fi
        
        if ! command -v dig >/dev/null 2>&1; then
            echo -e "${RED}❌ Не удалось установить утилиту dig${NC}"
            return 1
        fi
        echo -e "${GREEN}✅ Утилита dig установлена${NC}"
        echo
    fi
    
    # Perform DNS lookups
    echo -e "${WHITE}🔍 Проверка DNS записей:${NC}"
    echo
    
    # A record check
    echo -e "${GRAY}   Проверка A записи...${NC}"
    local a_records=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    
    if [ -z "$a_records" ]; then
        echo -e "${RED}   ❌ A-запись не найдена${NC}"
        local dns_status="failed"
    else
        echo -e "${GREEN}   ✅ Найдена A-запись:${NC}"
        while IFS= read -r ip; do
            echo -e "${GRAY}      → $ip${NC}"
            if [ "$ip" = "$server_ip" ]; then
                local dns_match="true"
            fi
        done <<< "$a_records"
    fi
    
    # AAAA record check (IPv6)
    echo -e "${GRAY}   Проверка AAAA-записи...${NC}"
    local aaaa_records=$(dig +short AAAA "$domain" 2>/dev/null)
    
    if [ -z "$aaaa_records" ]; then
        echo -e "${GRAY}   ℹ️  AAAA-запись (IPv6) не найдена${NC}"
    else
        echo -e "${GREEN}   ✅ Найдена AAAA-запись:${NC}"
        while IFS= read -r ip; do
            echo -e "${GRAY}      → $ip${NC}"
        done <<< "$aaaa_records"
    fi
    
    # CNAME record check
    echo -e "${GRAY}   Проверка CNAME-записи...${NC}"
    local cname_record=$(dig +short CNAME "$domain" 2>/dev/null)
    
    if [ -n "$cname_record" ]; then
        echo -e "${GREEN}   ✅ Найдена CNAME-запись:${NC}"
        echo -e "${GRAY}      → $cname_record${NC}"
        
        # Check CNAME target
        echo -e "${GRAY}   Разрешение целевого CNAME...${NC}"
        local cname_a_records=$(dig +short A "$cname_record" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        
        if [ -n "$cname_a_records" ]; then
            echo -e "${GREEN}   ✅ Целевой CNAME разрешён:${NC}"
            while IFS= read -r ip; do
                echo -e "${GRAY}      → $ip${NC}"
                if [ "$ip" = "$server_ip" ]; then
                    local dns_match="true"
                fi
            done <<< "$cname_a_records"
        fi
    else
        echo -e "${GRAY}   ℹ️  CNAME-запись не найдена${NC}"
    fi
    
    echo
    
    # DNS propagation check with multiple servers
    echo -e "${WHITE}🌐 Проверка распространения DNS:${NC}"
    echo
    
    local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222" "9.9.9.9")
    local propagation_count=0
    
    for dns_server in "${dns_servers[@]}"; do
        echo -e "${GRAY}   Проверка через $dns_server...${NC}"
        local remote_a=$(dig @"$dns_server" +short A "$domain" 2>/dev/null | head -1)
        
        if [ -n "$remote_a" ] && [[ "$remote_a" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            if [ "$remote_a" = "$server_ip" ]; then
                echo -e "${GREEN}   ✅ $remote_a (совпадает с сервером)${NC}"
                ((propagation_count++))
            else
                echo -e "${YELLOW}   ⚠️  $remote_a (другой IP)${NC}"
            fi
        else
            echo -e "${RED}   ❌ Нет ответа${NC}"
        fi
    done
    
    echo
    
    # Port availability check (только важные для Reality)
    echo -e "${WHITE}🔧 Проверка доступности портов:${NC}"
    echo
    
    # Check if port 443 is free (should be free for Xray)
    echo -e "${GRAY}   Проверка доступности порта 443...${NC}"
    if ss -tlnp | grep -q ":443 "; then
        echo -e "${YELLOW}   ⚠️  Порт 443 занят${NC}"
        echo -e "${GRAY}      Этот порт нужен для Xray Reality${NC}"
        local port_info=$(ss -tlnp | grep ":443 " | head -1 | awk '{print $1, $4}')
        echo -e "${GRAY}      Текущий: $port_info${NC}"
    else
        echo -e "${GREEN}   ✅ Порт 443 свободен для Xray${NC}"
    fi
    
    # Check if port 80 is free (will be used by Caddy)
    echo -e "${GRAY}   Проверка доступности порта 80...${NC}"
    if ss -tlnp | grep -q ":80 "; then
        echo -e "${YELLOW}   ⚠️  Порт 80 занят${NC}"
        echo -e "${GRAY}      Этот порт будет использоваться Caddy для HTTP-редиректов${NC}"
        local port80_occupied=$(ss -tlnp | grep ":80 " | head -1)
        echo -e "${GRAY}      Текущий: $port80_occupied${NC}"
    else
        echo -e "${GREEN}   ✅ Порт 80 свободен для Caddy${NC}"
    fi
    
    echo
    
    # Summary and recommendations
    echo -e "${WHITE}📋 Итог проверки DNS:${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 35))${NC}"
    
    if [ "$dns_match" = "true" ]; then
        echo -e "${GREEN}✅ Домен указывает на этот сервер корректно${NC}"
        echo -e "${GREEN}✅ Распространение DNS: $propagation_count/4 серверов${NC}"
        
        if [ "$propagation_count" -ge 2 ]; then
            echo -e "${GREEN}✅ Распространение DNS выглядит хорошо${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  Распространение DNS ограничено${NC}"
            echo -e "${GRAY}   Это может вызвать проблемы при необходимости${NC}"
        fi
    else
        echo -e "${RED}❌ Домен не указывает на этот сервер${NC}"
        echo -e "${GRAY}   Ожидаемый IP: $server_ip${NC}"
        
        if [ -n "$a_records" ]; then
            echo -e "${GRAY}   Текущие IP: $(echo "$a_records" | tr '\n' ' ')${NC}"
        fi
    fi
    
    echo
    echo -e "${WHITE}🔧 Требования для Reality:${NC}"
    echo -e "${GRAY}   • Домен должен указывать на этот сервер ✓${NC}"
    echo -e "${GRAY}   • Порт 443 должен быть свободен для Xray ✓${NC}"
    echo -e "${GRAY}   • Порт 80 будет использоваться Caddy для редиректов${NC}"
    echo -e "${GRAY}   • Caddy будет отдавать контент на внутреннем порту (9443)${NC}"
    echo -e "${GRAY}   • Настройте Xray Reality ПОСЛЕ установки Caddy${NC}"
    
    echo
    
    # Ask user decision
    if [ "$dns_match" = "true" ] && [ "$propagation_count" -ge 2 ]; then
        echo -e "${GREEN}🎉 Проверка DNS пройдена! Готово к установке.${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  DNS validation has warnings.${NC}"
        echo
        read -p "Продолжить в любом случае? [y/N]: " -r continue_anyway
        
        if [[ $continue_anyway =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}⚠️  Продолжаем установку несмотря на проблемы с DNS...${NC}"
            return 0
        else
            echo -e "${GRAY}Установка отменена. Пожалуйста, сначала исправьте конфигурацию DNS.${NC}"
            return 1
        fi
    fi
}

# Install function
install_command() {
    check_running_as_root
    
    clear
    echo -e "${WHITE}🚀 Установка Caddy для Reality Selfsteal${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo

    # Check if already installed
    if [ -d "$APP_DIR" ]; then
        echo -e "${YELLOW}⚠️  Установка Caddy уже существует в $APP_DIR${NC}"
        echo
        read -p "Хотите переустановить? [y/N]: " -r confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo -e "${GRAY}Установка отменена${NC}"
            return 0
        fi
        echo
        echo -e "${YELLOW}🗑️  Удаление существующей установки...${NC}"
        stop_services
        rm -rf "$APP_DIR"
        echo -e "${GREEN}✅ Существующая установка удалена${NC}"
        echo
    fi

    # Check system requirements
    if ! check_system_requirements; then
        return 1
    fi

    # Collect configuration
    echo -e "${WHITE}📝 Настройка конфигурации${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    echo

    # Domain configuration
    echo -e "${WHITE}🌐 Настройка домена${NC}"
    echo -e "${GRAY}Домен должен совпадать с настройками Xray Reality (realitySettings.serverNames)${NC}"
    echo
    
    local domain=""
    local skip_dns_check=false
    
    while [ -z "$domain" ]; do
        read -p "Введите ваш домен (например, reality.example.com): " domain
        if [ -z "$domain" ]; then
            echo -e "${RED}❌ Domain cannot be empty!${NC}"
            continue
        fi
        
        echo
        echo -e "${WHITE}🔍 Варианты проверки DNS:${NC}"
        echo -e "   ${WHITE}1)${NC} ${GRAY}Проверить конфигурацию DNS (рекомендуется)${NC}"
        echo -e "   ${WHITE}2)${NC} ${GRAY}Пропустить проверку DNS (для теста/разработки)${NC}"
        echo
        
        read -p "Выберите опцию [1-2]: " dns_choice
        
        case "$dns_choice" in
            1)
                echo
                if ! validate_domain_dns "$domain" "$NODE_IP"; then
                    echo
                    read -p "Попробовать другой домен? [Y/n]: " -r try_again
                    if [[ ! $try_again =~ ^[Nn]$ ]]; then
                        domain=""
                        continue
                    else
                        return 1
                    fi
                fi
                ;;
            2)
                echo -e "${YELLOW}⚠️  Пропуск проверки DNS...${NC}"
                skip_dns_check=true
                ;;
            *)
                echo -e "${RED}❌ Invalid option!${NC}"
                domain=""
                continue
                ;;
        esac
    done

    # Port configuration
    echo
    echo -e "${WHITE}🔌 Настройка порта${NC}"
    echo -e "${GRAY}Порт должен совпадать с настройками Xray Reality (realitySettings.dest)${NC}"
    echo
    
    local port="9443"
    read -p "Введите HTTPS-порт Caddy (по умолчанию: 9443): " input_port
    if [ -n "$input_port" ]; then
        port="$input_port"
    fi

    # Validate port
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}❌ Неверный номер порта!${NC}"
        return 1
    fi

    # Summary
    echo
    echo -e "${WHITE}📋 Итоги установки${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Домен:" "$domain"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "HTTPS-порт:" "$port"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Путь установки:" "$APP_DIR"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Путь HTML:" "$HTML_DIR"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "IP сервера:" "$NODE_IP"
    
    if [ "$skip_dns_check" = true ]; then
        printf "   ${WHITE}%-20s${NC} ${YELLOW}%s${NC}\n" "Проверка DNS:" "ПРОПУЩЕНО"
    else
        printf "   ${WHITE}%-20s${NC} ${GREEN}%s${NC}\n" "Проверка DNS:" "ПРОЙДЕНА"
    fi
    
    echo

    read -p "Продолжить установку? [Y/n]: " -r confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        echo -e "${GRAY}Установка отменена${NC}"
        return 0
    fi

    # Create directories
    echo
    echo -e "${WHITE}📁 Создание структуры каталогов${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    mkdir -p "$APP_DIR"
    mkdir -p "$HTML_DIR"
    mkdir -p "$APP_DIR/logs"
    
        echo -e "${GREEN}✅ Каталоги созданы${NC}"

    # Create .env file
    echo
    echo -e "${WHITE}⚙️  Создание файлов конфигурации${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"

    cat > "$APP_DIR/.env" << EOF
# Caddy for Reality Selfsteal Configuration
# Domain Configuration
SELF_STEAL_DOMAIN=$domain
SELF_STEAL_PORT=$port

# Generated on $(date)
# Server IP: $NODE_IP
EOF

    echo -e "${GREEN}✅ Файл .env создан${NC}"

    # Create docker-compose.yml
    cat > "$APP_DIR/docker-compose.yml" << EOF
services:
  caddy:
    image: caddy:2.9.1
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - $HTML_DIR:/var/www/html
      - ./logs:/var/log/caddy
      - ${VOLUME_PREFIX}_data:/data
      - ${VOLUME_PREFIX}_config:/config
    env_file:
      - .env
    network_mode: "host"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  ${VOLUME_PREFIX}_data:
  ${VOLUME_PREFIX}_config:
EOF

    echo -e "${GREEN}✅ Файл docker-compose.yml создан${NC}"

    # Create Caddyfile
    cat > "$APP_DIR/Caddyfile" << 'EOF'
{
    https_port {$SELF_STEAL_PORT}
    default_bind 127.0.0.1
    servers {
        listener_wrappers {
            proxy_protocol {
                allow 127.0.0.1/32
            }
            tls
        }
    }
    auto_https disable_redirects
    log {
        output file /var/log/caddy/access.log {
            roll_size 10MB
            roll_keep 5
            roll_keep_for 720h
            roll_compression gzip
        }
        level ERROR
        format json 
    }
}

http://{$SELF_STEAL_DOMAIN} {
    bind 0.0.0.0
    redir https://{$SELF_STEAL_DOMAIN}{uri} permanent
    log {
        output file /var/log/caddy/redirect.log {
            roll_size 5MB
            roll_keep 3
            roll_keep_for 168h
        }
    }
}

https://{$SELF_STEAL_DOMAIN} {
    root * /var/www/html
    try_files {path} /index.html
    file_server
    log {
        output file /var/log/caddy/access.log {
            roll_size 10MB
            roll_keep 5
            roll_keep_for 720h
            roll_compression gzip
        }
        level ERROR
    }
}

:{$SELF_STEAL_PORT} {
    tls internal
    respond 204
    log off
}

:80 {
    bind 0.0.0.0
    respond 204
    log off
}
EOF

    echo -e "${GREEN}✅ Файл Caddyfile создан${NC}"    # Install random template instead of default HTML
    echo
    echo -e "${WHITE}🎨 Выбор шаблона сайта${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 35))${NC}"
    
    # List of available templates (only 2 options)
    local templates=("1" "2")
    local template_names=("503 Error v1" "503 Error v2")
    
    echo -e "${WHITE}Доступные шаблоны:${NC}"
    echo -e "${GRAY}  1. 503 Error v1${NC}"
    echo -e "${GRAY}  2. 503 Error v2${NC}"
    echo
    
    # Ask user to choose
    while true; do
        read -p "Выберите шаблон (1-2): " template_choice
        if [[ "$template_choice" =~ ^[12]$ ]]; then
            break
        else
            echo -e "${RED}❌ Неверный выбор! Введите 1 или 2${NC}"
        fi
    done
    
    local selected_template="$template_choice"
    local selected_name=${template_names[$((template_choice-1))]}
    local installed_template=""
    
    echo -e "${CYAN}✅ Выбран шаблон: ${selected_name}${NC}"
    echo
    
    if download_template "$selected_template"; then
        echo -e "${GREEN}✅ Шаблон успешно установлен${NC}"
        installed_template="$selected_name template"
    else
        echo -e "${YELLOW}⚠️  Не удалось скачать шаблон, создаю запасной${NC}"
        create_default_html
        installed_template="Default template (fallback)"
    fi

    # Install management script
    install_management_script

    # Start services
    echo
    echo -e "${WHITE}🚀 Запуск сервисов Caddy${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    
    cd "$APP_DIR"
    echo -e "${WHITE}🔍 Проверка Caddyfile...${NC}"

    if [ ! -f "$APP_DIR/Caddyfile" ]; then
        echo -e "${RED}❌ Caddyfile не найден по пути $APP_DIR/Caddyfile${NC}"
        return 1
    fi

    if validate_caddyfile; then
        echo -e "${GREEN}✅ Caddyfile валиден${NC}"
    else
        echo -e "${RED}❌ Неверная конфигурация Caddyfile${NC}"
        echo -e "${YELLOW}💡 Проверьте синтаксис: sudo $APP_NAME edit${NC}"
        return 1
    fi

    if docker compose up -d; then
        echo -e "${GREEN}✅ Сервисы Caddy успешно запущены${NC}"
    else
        echo -e "${RED}❌ Не удалось запустить сервисы Caddy${NC}"
        return 1
    fi

    # Installation complete
    echo
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo -e "${WHITE}🎉 Установка успешно завершена!${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Домен:" "$domain"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "HTTPS-порт:" "$port"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Путь установки:" "$APP_DIR"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "HTML-контент:" "$HTML_DIR"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Установленный шаблон:" "$installed_template"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Команда управления:" "$APP_NAME"
      echo
    echo -e "${WHITE}📋 Следующие шаги:${NC}"
    echo -e "${GRAY}   • Настройте Xray Reality:${NC}"
    echo -e "${GRAY}     - serverNames: [\"$domain\"]${NC}"
    echo -e "${GRAY}     - dest: \"127.0.0.1:$port\"${NC}"
    echo -e "${GRAY}   • Сменить шаблон: sudo $APP_NAME template${NC}"
    echo -e "${GRAY}   • Изменить контент HTML в: $HTML_DIR${NC}"
    echo -e "${GRAY}   • Проверить статус: sudo $APP_NAME status${NC}"
    echo -e "${GRAY}   • Смотреть логи: sudo $APP_NAME logs${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
}

validate_caddyfile() {
    echo -e "${BLUE}🔍 Проверка Caddyfile...${NC}"
    
    # Загружаем переменные из .env файла для валидации
    if [ -f "$APP_DIR/.env" ]; then
        export $(grep -v '^#' "$APP_DIR/.env" | xargs)
    fi
    
    # Проверяем, что обязательные переменные установлены
    if [ -z "$SELF_STEAL_DOMAIN" ] || [ -z "$SELF_STEAL_PORT" ]; then
        echo -e "${YELLOW}⚠️ Переменные окружения не заданы, используем значения по умолчанию для проверки${NC}"
        export SELF_STEAL_DOMAIN="example.com"
        export SELF_STEAL_PORT="9443"
    fi
    
    # Валидация с теми же volume что и в рабочем контейнере
    if docker run --rm \
        -v "$APP_DIR/Caddyfile:/etc/caddy/Caddyfile:ro" \
        -v "/etc/letsencrypt:/etc/letsencrypt:ro" \
        -v "$APP_DIR/html:/var/www/html:ro" \
        -e "SELF_STEAL_DOMAIN=$SELF_STEAL_DOMAIN" \
        -e "SELF_STEAL_PORT=$SELF_STEAL_PORT" \
        caddy:${CADDY_VERSION}-alpine \
        caddy validate --config /etc/caddy/Caddyfile 2>&1; then
        echo -e "${GREEN}✅ Caddyfile валиден${NC}"
        return 0
    else
        echo -e "${RED}❌ Неверная конфигурация Caddyfile${NC}"
        echo -e "${YELLOW}💡 Проверьте синтаксис: sudo $APP_NAME edit${NC}"
        return 1
    fi
}

show_current_template_info() {
    echo -e "${WHITE}📄 Информация о текущем шаблоне${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 35))${NC}"
    echo
    
    if [ ! -d "$HTML_DIR" ] || [ ! "$(ls -A "$HTML_DIR" 2>/dev/null)" ]; then
        echo -e "${GRAY}   Шаблон не установлен${NC}"
        return
    fi
    
    # Проверить наличие основных файлов
    if [ -f "$HTML_DIR/index.html" ]; then
        local title=$(grep -o '<title>[^<]*</title>' "$HTML_DIR/index.html" 2>/dev/null | sed 's/<title>\|<\/title>//g' | head -1)
        local meta_comment=$(grep -o '<!-- [a-f0-9]\{16\} -->' "$HTML_DIR/index.html" 2>/dev/null | head -1)
        local file_count=$(find "$HTML_DIR" -type f | wc -l)
        local total_size=$(du -sh "$HTML_DIR" 2>/dev/null | cut -f1)
        
        echo -e "${WHITE}   Заголовок:${NC} ${GRAY}${title:-"Неизвестно"}${NC}"
        echo -e "${WHITE}   Файлов:${NC} ${GRAY}$file_count${NC}"
        echo -e "${WHITE}   Размер:${NC} ${GRAY}$total_size${NC}"
        echo -e "${WHITE}   Путь:${NC} ${GRAY}$HTML_DIR${NC}"
        
        if [ -n "$meta_comment" ]; then
            echo -e "${WHITE}   ID:${NC} ${GRAY}$meta_comment${NC}"
        fi
        
        # Показать последнее изменение
        local last_modified=$(stat -c %y "$HTML_DIR/index.html" 2>/dev/null | cut -d' ' -f1)
        if [ -n "$last_modified" ]; then
            echo -e "${WHITE}   Изменён:${NC} ${GRAY}$last_modified${NC}"
        fi
    else
        echo -e "${GRAY}   Пользовательский или неизвестный шаблон${NC}"
        echo -e "${WHITE}   Путь:${NC} ${GRAY}$HTML_DIR${NC}"
    fi
    echo
}

download_template() {
    local template_type="$1"
    local template_folder=""
    local template_name=""
    
    # Определяем папку для скачивания в зависимости от выбранного шаблона
    case "$template_type" in
        "1"|"10gag")
            template_folder="10gag"
            template_name="10gag - Сайт мемов"
            ;;
        "2"|"converter")
            template_folder="converter"
            template_name="Converter - Видеостудия-конвертер"
            ;;
        "3"|"convertit")
            template_folder="convertit"
            template_name="Convertit - Конвертер файлов"
            ;;
        "4"|"downloader")
            template_folder="downloader"
            template_name="Downloader - Даунлоадер"
            ;;
        "5"|"filecloud")
            template_folder="filecloud"
            template_name="FileCloud - Облачное хранилище"
            ;;
        "6"|"games-site")
            template_folder="games-site"
            template_name="Games-site - Ретро игровой портал"
            ;;
        "7"|"modmanager")
            template_folder="modmanager"
            template_name="ModManager - Мод-менеджер для игр"
            ;;
        "8"|"speedtest")
            template_folder="speedtest"
            template_name="SpeedTest - Спидтест"
            ;;
        "9"|"youtube")
            template_folder="YouTube"
            template_name="YouTube - Видеохостинг с капчей"
            ;;
        "10"|"503")
            template_folder="503-1"
            template_name="503 Error - Страница ошибки 503 - вариант 1"
            ;;
        "11"|"503")
            template_folder="503-2"
            template_name="503 Error - Страница ошибки 503 - вариант 2"
        ;;
        *)
            echo -e "${RED}❌ Unknown template type: $template_type${NC}"
            return 1
            ;;
    esac
    
    echo -e "${WHITE}🎨 Загрузка шаблона: $template_name${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo
    
    # Создаем директорию
    mkdir -p "$HTML_DIR"
    rm -rf "$HTML_DIR"/*
    cd "$HTML_DIR"
    
    # Попробуем сначала через git (если доступен)
    if command -v git >/dev/null 2>&1; then
        echo -e "${WHITE}📦 Использую Git для загрузки...${NC}"
        
        # Создаем временную директорию
        local temp_dir="/tmp/selfsteal-template-$$"
        mkdir -p "$temp_dir"
        
        # Клонируем только нужную папку через sparse-checkout
        if git clone --filter=blob:none --sparse "https://github.com/Spakieone/Remna.git" "$temp_dir" 2>/dev/null; then
            cd "$temp_dir"
            git sparse-checkout set "sni-templates/$template_folder" 2>/dev/null
            
            # Копируем файлы
            local source_path="$temp_dir/sni-templates/$template_folder"
            if [ -d "$source_path" ]; then
                if cp -r "$source_path"/* "$HTML_DIR/" 2>/dev/null; then
                    local files_copied=$(find "$HTML_DIR" -type f | wc -l)
                    echo -e "${GREEN}✅ Файлы шаблона скопированы: $files_copied файлов${NC}"
                    
                    # Очистка
                    rm -rf "$temp_dir"
                    
                    # Устанавливаем правильные права доступа
                    setup_file_permissions
                    
                    show_download_summary "$files_copied" "$template_name"
                    return 0
                else
                    echo -e "${YELLOW}⚠️  Метод Git не сработал, пробую wget...${NC}"
                fi
            else
                echo -e "${YELLOW}⚠️  Шаблон не найден в репозитории, пробую wget...${NC}"
            fi
            
            # Очистка в случае неудачи
            rm -rf "$temp_dir"
        else
            echo -e "${YELLOW}⚠️  Не удалось клонировать через Git, пробую wget...${NC}"
        fi
    fi
    
    # Fallback: используем wget для рекурсивного скачивания
    if command -v wget >/dev/null 2>&1; then
        echo -e "${WHITE}📦 Использую wget для рекурсивной загрузки...${NC}"
        
        local base_url="https://raw.githubusercontent.com/Spakieone/Remna/main/sni-templates/$template_folder"
        
        # Получаем структуру папки через GitHub API
        local api_url="https://api.github.com/repos/Spakieone/Remna/git/trees/main?recursive=1"
        local tree_data
        tree_data=$(curl -s "$api_url" 2>/dev/null)
        
        if [ -n "$tree_data" ] && echo "$tree_data" | grep -q '"path"'; then
            echo -e "${GREEN}✅ Структура репозитория получена${NC}"
            echo -e "${WHITE}📥 Загрузка файлов...${NC}"
            
            # Извлекаем пути файлов для нашего шаблона
            local template_files
            template_files=$(echo "$tree_data" | grep -o "\"path\":[^,]*" | sed 's/"path":"//' | sed 's/"//' | grep "^sni-templates/$template_folder/")
            
            local files_downloaded=0
            local failed_downloads=0
            
            if [ -n "$template_files" ]; then
                while IFS= read -r file_path; do
                    if [ -n "$file_path" ]; then
                        # Получаем относительный путь (убираем sni-templates/$template_folder/)
                        local relative_path="${file_path#sni-templates/$template_folder/}"
                        local file_url="https://raw.githubusercontent.com/Spakieone/Remna/main/$file_path"
                        
                        # Создаем директорию если нужно
                        local file_dir=$(dirname "$relative_path")
                        if [ "$file_dir" != "." ]; then
                            mkdir -p "$file_dir"
                        fi
                        
                        echo -e "${GRAY}   Скачиваю $relative_path...${NC}"
                        
                        if wget -q "$file_url" -O "$relative_path" 2>/dev/null; then
                            echo -e "${GREEN}   ✅ $relative_path${NC}"
                            ((files_downloaded++))
                        else
                            echo -e "${YELLOW}   ⚠️  $relative_path (ошибка)${NC}"
                            ((failed_downloads++))
                        fi
                    fi
                done <<< "$template_files"
                
                if [ $files_downloaded -gt 0 ]; then
                    setup_file_permissions
                    show_download_summary "$files_downloaded" "$template_name"
                    return 0
                fi
            else
                echo -e "${YELLOW}⚠️  Файлы шаблона не найдены, пробую запасной способ с curl...${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Не удалось получить структуру репозитория, пробую curl...${NC}"
        fi
    fi
    
    # Последний fallback: curl с предопределенным списком файлов
    echo -e "${WHITE}📦 Использую запасной метод curl...${NC}"
    
    # Базовые файлы, которые должны быть в большинстве шаблонов
    local common_files=("index.html" "favicon.ico" "favicon.svg" "site.webmanifest" "apple-touch-icon.png" "favicon-96x96.png" "web-app-manifest-192x192.png" "web-app-manifest-512x512.png")
    local asset_files=("assets/style.css" "assets/script.js" "assets/main.js")
    
    local base_url="https://raw.githubusercontent.com/Spakieone/Remna/main/sni-templates/$template_folder"
    local files_downloaded=0
    local failed_downloads=0
    
    echo -e "${WHITE}📥 Загрузка основных файлов...${NC}"
    
    # Скачиваем основные файлы
    for file in "${common_files[@]}"; do
        local url="$base_url/$file"
        echo -e "${GRAY}   Скачиваю $file...${NC}"
        
        if curl -fsSL "$url" -o "$file" 2>/dev/null; then
            echo -e "${GREEN}   ✅ $file${NC}"
            ((files_downloaded++))
        else
            echo -e "${YELLOW}   ⚠️  $file (необязательный файл не найден)${NC}"
            ((failed_downloads++))
        fi
    done
    
    # Скачиваем файлы assets
    mkdir -p assets
    echo -e "${WHITE}📁 Загрузка assets...${NC}"
    
    for file in "${asset_files[@]}"; do
        local url="$base_url/$file"
        local filename=$(basename "$file")
        echo -e "${GRAY}   Скачиваю assets/$filename...${NC}"
        
        if curl -fsSL "$url" -o "assets/$filename" 2>/dev/null; then
            echo -e "${GREEN}   ✅ assets/$filename${NC}"
            ((files_downloaded++))
        else
            echo -e "${YELLOW}   ⚠️  assets/$filename (необязательный файл не найден)${NC}"
            ((failed_downloads++))
        fi
    done
    
    if [ $files_downloaded -gt 0 ]; then
        setup_file_permissions
        show_download_summary "$files_downloaded" "$template_name"
        return 0
    else
        echo -e "${RED}❌ Failed to download any files${NC}"
        echo -e "${YELLOW}⚠️  Creating fallback template...${NC}"
        create_fallback_html "$template_name"
        return 1
    fi
}

# Функция для установки правильных прав доступа
setup_file_permissions() {
    echo -e "${WHITE}🔒 Setting up file permissions...${NC}"
    
    # Устанавливаем права на файлы
    chmod -R 644 "$HTML_DIR"/* 2>/dev/null || true
    
    # Устанавливаем права на директории
    find "$HTML_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    # Устанавливаем владельца (если возможно)
    chown -R www-data:www-data "$HTML_DIR" 2>/dev/null || true
    
    echo -e "${GREEN}✅ File permissions configured${NC}"
}

# Функция для показа итогов скачивания
show_download_summary() {
    local files_count="$1"
    local template_name="$2"
    
    echo
    echo -e "${WHITE}📊 Итоги загрузки:${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 25))${NC}"
    printf "   ${WHITE}%-20s${NC} ${GREEN}%d${NC}\n" "Скачано файлов:" "$files_count"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Шаблон:" "$template_name"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Путь:" "$HTML_DIR"
    
    # Показать размер
    local total_size=$(du -sh "$HTML_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Итоговый размер:" "$total_size"
    
    echo
    echo -e "${GREEN}✅ Шаблон успешно загружен${NC}"
}

# Fallback функция для создания базового HTML если скачивание не удалось
create_fallback_html() {
    local template_name="$1"
    
    cat > "index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$template_name</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }
        .container {
            text-align: center;
            max-width: 600px;
            padding: 2rem;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        p {
            font-size: 1.2rem;
            opacity: 0.9;
            margin-bottom: 2rem;
        }
        .status {
            background: rgba(255,255,255,0.1);
            padding: 1rem 2rem;
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Service Ready</h1>
        <p>$template_name template is now active</p>
        <div class="status">
            <p>✅ System Online</p>
        </div>
    </div>
</body>
</html>
EOF
}

# Create default HTML content for initial installation
create_default_html() {
    echo -e "${WHITE}🌐 Создание стандартного сайта${NC}"
    
    cat > "$HTML_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Добро пожаловать</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 500px;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        p {
            color: #666;
            line-height: 1.6;
            margin-bottom: 15px;
        }
        .status {
            display: inline-block;
            background: #4CAF50;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 14px;
            margin-top: 20px;
        }
        .info {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            margin-top: 20px;
            border-left: 4px solid #667eea;
        }
        .info h3 {
            color: #333;
            margin-bottom: 10px;
        }
        .command {
            background: #2d3748;
            color: #e2e8f0;
            padding: 10px;
            border-radius: 4px;
            font-family: monospace;
            margin: 10px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 Caddy for Reality Selfsteal</h1>
        <p>Сервер Caddy работает корректно и готов отдавать ваш контент.</p>
        <div class="status">✅ Сервис активен</div>
        <div class="info">
            <h3>🎨 Готов к установке шаблонов</h3>
            <p>Используйте менеджер шаблонов для установки сайтов:</p>
            <div class="command">sudo selfsteal template</div>
            <p>Доступны 10 готовых шаблонов: мемы, загрузчики, конвертеры и др.</p>
        </div>
    </div>
</body>
</html>
EOF

    # Create 404 page
    cat > "$HTML_DIR/404.html" << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 — Страница не найдена</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 40px;
            background: #f5f5f5;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 500px;
        }
        h1 {
            color: #e74c3c;
            font-size: 4rem;
            margin-bottom: 20px;
        }
        h2 {
            color: #333;
            margin-bottom: 15px;
        }
        p {
            color: #666;
            line-height: 1.6;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>404</h1>        <h2>Страница не найдена</h2>
        <p>Запрашиваемая страница не существует.</p>
    </div>
</body>
</html>
EOF
    echo -e "${GREEN}✅ Стандартный HTML-контент создан${NC}"
}

# Function to show template options
show_template_options() {
    echo -e "${WHITE}🎨 Варианты шаблонов сайта${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 35))${NC}"
    echo
    echo -e "${WHITE}Выберите тип шаблона:${NC}"
    echo -e "   ${WHITE}1)${NC} ${CYAN}⚠️ 503 Error - Страница ошибки 503 v1${NC}"
    echo -e "   ${WHITE}2)${NC} ${CYAN}⚠️ 503 Error - Страница ошибки 503 v2${NC}"
    echo
    echo -e "   ${WHITE}v)${NC} ${GRAY}📄 Просмотреть текущий шаблон${NC}"
    echo -e "   ${WHITE}k)${NC} ${GRAY}📝 Оставить текущий шаблон${NC}"
    echo
    echo -e "   ${GRAY}0)${NC} ${GRAY}⬅️  Отмена${NC}"
    echo
}


# Template management command
template_command() {
    check_running_as_root
    if ! docker --version >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker недоступен${NC}"
        return 1
    fi

    if [ ! -d "$APP_DIR" ]; then
        echo -e "${RED}❌ Caddy не установлен. Сначала выполните 'sudo $APP_NAME install'.${NC}"
        return 1
    fi
    

    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
    if [ "$running_services" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Caddy сейчас запущен${NC}"
        echo -e "${GRAY}   Изменения шаблона будут применены сразу${NC}"
        echo
        read -p "Продолжить загрузку шаблона? [Y/n]: " -r continue_template
        if [[ $continue_template =~ ^[Nn]$ ]]; then
            return 0
        fi
    fi
    
    
    while true; do
        clear
        show_template_options
        
        read -p "Выберите вариант шаблона [1-2, v, k]: " choice
        
        case "$choice" in
            1)
                echo
                if download_template "10"; then
                    echo -e "${GREEN}🎉 Шаблон 503 Error v1 успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Перезапустить Caddy для применения изменений? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Перезапуск Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy перезапущен${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон 503 Error v1${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            2)
                echo
                if download_template "11"; then
                    echo -e "${GREEN}🎉 Шаблон 503 Error v2 успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Перезапустить Caddy для применения изменений? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон 503 Error v2${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            3)
                echo
                if download_template "3"; then
                    echo -e "${GREEN}🎉 Шаблон Convertit успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Перезапустить Caddy для применения изменений? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон Convertit${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            4)
                echo
                if download_template "4"; then
                    echo -e "${GREEN}🎉 Шаблон Downloader успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Перезапустить Caddy для применения изменений? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон Downloader${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            5)
                echo
                if download_template "5"; then
                    echo -e "${GREEN}🎉 Шаблон FileCloud успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Перезапустить Caddy для применения изменений? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон FileCloud${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            6)
                echo
                if download_template "6"; then
                    echo -e "${GREEN}🎉 Шаблон Games-site успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Перезапустить Caddy для применения изменений? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон Games-site${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            7)
                echo
                if download_template "7"; then
                    echo -e "${GREEN}🎉 Шаблон ModManager успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Перезапустить Caddy для применения изменений? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон ModManager${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            8)
                echo
                if download_template "8"; then
                    echo -e "${GREEN}🎉 Шаблон SpeedTest успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Перезапустить Caddy для применения изменений? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон SpeedTest${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            9)
                echo
                if download_template "9"; then
                    echo -e "${GREEN}🎉 Шаблон YouTube успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Restart Caddy to apply changes? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон YouTube${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            10)
                echo
                if download_template "10"; then
                    echo -e "${GREEN}🎉 Шаблон 503 Error успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Restart Caddy to apply changes? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон 503 Error${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            11)
                echo
                if download_template "11"; then
                    echo -e "${GREEN}🎉 Шаблон 503 Error v2 успешно загружен!${NC}"
                    echo
                    local running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
                    if [ "$running_services" -gt 0 ]; then
                        read -p "Restart Caddy to apply changes? [Y/n]: " -r restart_caddy
                        if [[ ! $restart_caddy =~ ^[Nn]$ ]]; then
                            echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
                            cd "$APP_DIR" && docker compose restart
                            echo -e "${GREEN}✅ Caddy restarted${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Не удалось скачать шаблон 503 Error v2${NC}"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            v|V)
                echo
                show_current_template_info
                read -p "Нажмите Enter для продолжения..."
                ;;
            k|K)
                echo -e "${GRAY}Current template preserved${NC}"
                read -p "Нажмите Enter для продолжения..."
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}❌ Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}




install_management_script() {
    echo -e "${WHITE}🔧 Установка управляющего скрипта${NC}"
    
    # Определить путь к скрипту
    local script_path
    if [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "@" ]; then
        script_path="$0"
    else
        # Попытаться найти скрипт в /tmp или скачать заново
        local temp_script="/tmp/selfsteal-install.sh"
        if curl -fsSL "$UPDATE_URL" -o "$temp_script" 2>/dev/null; then
            script_path="$temp_script"
            echo -e "${GRAY}📥 Скрипт загружен из удалённого источника${NC}"
        else
            echo -e "${YELLOW}⚠️  Не удалось автоматически установить управляющий скрипт${NC}"
            echo -e "${GRAY}   Вы можете скачать его вручную: $UPDATE_URL${NC}"
            return 1
        fi
    fi
    
    # Установить скрипт
    if [ -f "$script_path" ]; then
        cp "$script_path" "/usr/local/bin/$APP_NAME"
        chmod +x "/usr/local/bin/$APP_NAME"
        echo -e "${GREEN}✅ Управляющий скрипт установлен: /usr/local/bin/$APP_NAME${NC}"
        
        # Очистить временный файл если использовался
        if [ "$script_path" = "/tmp/selfsteal-install.sh" ]; then
            rm -f "$script_path"
        fi
    else
        echo -e "${RED}❌ Не удалось установить управляющий скрипт${NC}"
        return 1
    fi
}
# Service management functions
up_command() {
    check_running_as_root
    
    if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
        echo -e "${RED}❌ Caddy is not installed. Run 'sudo $APP_NAME install' first.${NC}"
        return 1
    fi
    
    echo -e "${WHITE}🚀 Запуск сервисов Caddy${NC}"
    cd "$APP_DIR"
    
    if docker compose up -d; then
        echo -e "${GREEN}✅ Сервисы Caddy успешно запущены${NC}"
    else
        echo -e "${RED}❌ Не удалось запустить сервисы Caddy${NC}"
        return 1
    fi
}

down_command() {
    check_running_as_root
    
    if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
        echo -e "${YELLOW}⚠️  Caddy не установлен${NC}"
        return 0
    fi
    
    echo -e "${WHITE}🛑 Остановка сервисов Caddy${NC}"
    cd "$APP_DIR"
    
    if docker compose down; then
        echo -e "${GREEN}✅ Сервисы Caddy успешно остановлены${NC}"
    else
        echo -e "${RED}❌ Не удалось остановить сервисы Caddy${NC}"
        return 1
    fi
}

restart_command() {
    check_running_as_root
    echo -e "${YELLOW}⚠️  Validate Caddyfile after editing? [Y/n]:${NC}"
    read -p "" validate_choice
    if [[ ! $validate_choice =~ ^[Nn]$ ]]; then
        validate_caddyfile
    fi
    echo -e "${WHITE}🔄 Перезапуск сервисов Caddy${NC}"
    down_command
    sleep 2
    up_command
}

status_command() {
    if [ ! -d "$APP_DIR" ]; then
        echo -e "${RED}❌ Caddy не установлен${NC}"
        return 1
    fi

    echo -e "${WHITE}📊 Статус сервиса Caddy${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    echo

    cd "$APP_DIR"
    
    # Получаем статус контейнера
    local container_status=$(docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null)
    local running_count=$(docker compose ps -q --status running 2>/dev/null | wc -l)
    local total_count=$(docker compose ps -q 2>/dev/null | wc -l)
    
    # Проверяем реальный статус
    local actual_status=$(docker compose ps --format "{{.State}}" 2>/dev/null | head -1)
    
    if [ "$actual_status" = "running" ]; then
        echo -е "${GREEN}✅ Статус: Запущен${NC}"
        echo -e "${GREEN}✅ Все сервисы запущены ($running_count/$total_count)${NC}"
    elif [ "$actual_status" = "restarting" ]; then
        echo -e "${YELLOW}⚠️  Статус: Перезапуск (ошибка)${NC}"
        echo -e "${RED}❌ Сервис падает и перезапускается ($running_count/$total_count)${NC}"
        echo -e "${YELLOW}🔧 Требуется действие: проверьте логи на ошибки${NC}"
    elif [ -n "$actual_status" ]; then
        echo -e "${RED}❌ Статус: $actual_status${NC}"
        echo -e "${RED}❌ Сервисы не запущены ($running_count/$total_count)${NC}"
    else
        echo -e "${RED}❌ Статус: Не запущено${NC}"
        echo -e "${RED}❌ Сервисы не найдены${NC}"
    fi

    echo
    echo -e "${WHITE}📋 Сведения о контейнере:${NC}"
    if [ -n "$container_status" ]; then
        echo "$container_status"
    else
        echo -e "${GRAY}Контейнеры не найдены${NC}"
    fi

    # Показать рекомендации при проблемах
    if [ "$actual_status" = "restarting" ]; then
        echo
        echo -e "${YELLOW}🔧 Диагностика:${NC}"
        echo -e "${GRAY}   1. Посмотреть логи: selfsteal logs${NC}"
        echo -e "${GRAY}   2. Проверить конфиг: selfsteal edit${NC}"
        echo -e "${GRAY}   3. Перезапустить сервисы: selfsteal restart${NC}"
    fi
    
    # Show configuration summary
    if [ -f "$APP_DIR/.env" ]; then
        echo
        echo -e "${WHITE}⚙️  Конфигурация:${NC}"
        local domain=$(grep "SELF_STEAL_DOMAIN=" "$APP_DIR/.env" | cut -d'=' -f2)
        local port=$(grep "SELF_STEAL_PORT=" "$APP_DIR/.env" | cut -d'=' -f2)
        
        printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Домен:" "$domain"
        printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "HTTPS-порт:" "$port"
        printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Путь к HTML:" "$HTML_DIR"
    fi
    printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Версия скрипта:" "v$SCRIPT_VERSION"
}

logs_command() {
    if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
        echo -e "${RED}❌ Caddy не установлен${NC}"
        return 1
    fi
    
    echo -e "${WHITE}📝 Логи Caddy${NC}"
    echo -e "${GRAY}Нажмите Ctrl+C для выхода${NC}"
    echo
    
    cd "$APP_DIR"
    docker compose logs -f
}


# Clean logs function
clean_logs_command() {
    check_running_as_root
    
    if [ ! -d "$APP_DIR" ]; then
        echo -e "${RED}❌ Caddy is not installed${NC}"
        return 1
    fi
    
    echo -e "${WHITE}🧹 Очистка логов${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 25))${NC}"
    echo
    
    # Show current log sizes
    echo -e "${WHITE}📊 Текущие размеры логов:${NC}"
    
    # Docker logs
    local docker_logs_size
    docker_logs_size=$(docker logs $CONTAINER_NAME 2>&1 | wc -c 2>/dev/null || echo "0")
    docker_logs_size=$((docker_logs_size / 1024))
    echo -e "${GRAY}   Логи Docker: ${WHITE}${docker_logs_size}KB${NC}"
    
    # Caddy access logs
    local caddy_logs_path="$APP_DIR/caddy_data/_logs"
    if [ -d "$caddy_logs_path" ]; then
        local caddy_logs_size
        caddy_logs_size=$(du -sk "$caddy_logs_path" 2>/dev/null | cut -f1 || echo "0")
        echo -e "${GRAY}   Логи Caddy: ${WHITE}${caddy_logs_size}KB${NC}"
    fi
    
    echo
    read -p "Очистить все логи? [y/N]: " -r clean_choice
    
    if [[ $clean_choice =~ ^[Yy]$ ]]; then
        echo -e "${WHITE}🧹 Очищаю логи...${NC}"
        
        # Clean Docker logs by recreating container
        if docker ps -q -f name=$CONTAINER_NAME >/dev/null 2>&1; then
            echo -e "${GRAY}   Остановка Caddy...${NC}"
            cd "$APP_DIR" && docker compose stop
            
            echo -e "${GRAY}   Удаление контейнера для очистки логов...${NC}"
            docker rm $CONTAINER_NAME 2>/dev/null || true
            
            echo -e "${GRAY}   Запуск Caddy...${NC}"
            cd "$APP_DIR" && docker compose up -d
        fi
        
        # Clean Caddy internal logs
        if [ -d "$caddy_logs_path" ]; then
            echo -e "${GRAY}   Очистка access-логов Caddy...${NC}"
            rm -rf "$caddy_logs_path"/* 2>/dev/null || true
        fi
        
        echo -e "${GREEN}✅ Логи успешно очищены${NC}"
    else
        echo -e "${GRAY}Очистка логов отменена${NC}"
    fi
}

# Show log sizes function
logs_size_command() {
    check_running_as_root
    
    if [ ! -d "$APP_DIR" ]; then
        echo -e "${RED}❌ Caddy is not installed${NC}"
        return 1
    fi
    
    echo -e "${WHITE}📊 Размеры логов${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 25))${NC}"
    echo
    
    # Docker logs
    local docker_logs_size
    if docker ps -q -f name=$CONTAINER_NAME >/dev/null 2>&1; then
        docker_logs_size=$(docker logs $CONTAINER_NAME 2>&1 | wc -c 2>/dev/null || echo "0")
        docker_logs_size=$((docker_logs_size / 1024))
        echo -e "${WHITE}📋 Логи Docker:${NC} ${GRAY}${docker_logs_size}KB${NC}"
    else
        echo -e "${WHITE}📋 Логи Docker:${NC} ${GRAY}Контейнер не запущен${NC}"
    fi
    
    # Caddy access logs
    local caddy_data_dir
    caddy_data_dir=$(cd "$APP_DIR" && docker volume inspect "${APP_DIR##*/}_${VOLUME_PREFIX}_data" --format '{{.Mountpoint}}' 2>/dev/null || echo "")
    
    if [ -n "$caddy_data_dir" ] && [ -d "$caddy_data_dir" ]; then
        local access_log="$caddy_data_dir/access.log"
        if [ -f "$access_log" ]; then
            local access_log_size
            access_log_size=$(du -k "$access_log" 2>/dev/null | cut -f1 || echo "0")
        echo -e "${WHITE}📄 Access-лог:${NC} ${GRAY}${access_log_size}KB${NC}"
        else
            echo -e "${WHITE}📄 Access-лог:${NC} ${GRAY}Не найден${NC}"
        fi
        
        # Check for rotated logs
        local rotated_logs
        rotated_logs=$(find "$caddy_data_dir" -name "access.log.*" 2>/dev/null | wc -l || echo "0")
        if [ "$rotated_logs" -gt 0 ]; then
            local rotated_size
            rotated_size=$(find "$caddy_data_dir" -name "access.log.*" -exec du -k {} \; 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            echo -e "${WHITE}🔄 Ротация логов:${NC} ${GRAY}${rotated_size}KB (${rotated_logs} файлов)${NC}"
        fi
    else
        echo -e "${WHITE}📄 Логи Caddy:${NC} ${GRAY}Том недоступен${NC}"
    fi
    
    # Logs directory
    if [ -d "$APP_DIR/logs" ]; then
        local logs_dir_size
        logs_dir_size=$(du -sk "$APP_DIR/logs" 2>/dev/null | cut -f1 || echo "0")
        echo -e "${WHITE}📁 Каталог логов:${NC} ${GRAY}${logs_dir_size}KB${NC}"
    fi
    
    echo
    echo -e "${GRAY}💡 Подсказка: используйте 'sudo $APP_NAME clean-logs' для очистки всех логов${NC}"
    echo
}

stop_services() {
    if [ -f "$APP_DIR/docker-compose.yml" ]; then
        cd "$APP_DIR"
        docker compose down 2>/dev/null || true
    fi
}

uninstall_command() {
    check_running_as_root
    
    echo -e "${WHITE}🗑️  Удаление Caddy${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    echo
    
    if [ ! -d "$APP_DIR" ]; then
        echo -e "${YELLOW}⚠️  Caddy не установлен${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  Это полностью удалит Caddy и все данные!${NC}"
    echo
    read -p "Вы уверены, что хотите продолжить? [y/N]: " -r confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${GRAY}Удаление отменено${NC}"
        return 0
    fi
    
    echo
    echo -e "${WHITE}🛑 Остановка сервисов...${NC}"
    stop_services
    
    echo -e "${WHITE}🗑️  Удаление файлов...${NC}"
    rm -rf "$APP_DIR"
    
    echo -e "${WHITE}🗑️  Удаление управляющего скрипта...${NC}"
    rm -f "/usr/local/bin/$APP_NAME"
    
    echo -e "${GREEN}✅ Caddy успешно удалён${NC}"
    echo
    echo -e "${GRAY}Примечание: HTML-контент в $HTML_DIR сохранён${NC}"
}

edit_command() {
    check_running_as_root
    
    if [ ! -d "$APP_DIR" ]; then
        echo -e "${RED}❌ Caddy is not installed${NC}"
        return 1
    fi
    
    echo -e "${WHITE}📝 Редактирование файлов конфигурации${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    echo
    
    echo -e "${WHITE}Выберите файл для редактирования:${NC}"
    echo -e "   ${WHITE}1)${NC} ${GRAY}.env (настройки домена и порта)${NC}"
    echo -e "   ${WHITE}2)${NC} ${GRAY}Caddyfile (конфигурация Caddy)${NC}"
    echo -e "   ${WHITE}3)${NC} ${GRAY}docker-compose.yml (конфигурация Docker)${NC}"
    echo -e "   ${WHITE}0)${NC} ${GRAY}Отмена${NC}"
    echo
    
    read -p "Выберите опцию [0-3]: " choice
    
    case "$choice" in
        1)
            ${EDITOR:-nano} "$APP_DIR/.env"
            echo -e "${YELLOW}⚠️  Перезапустите Caddy для применения изменений: sudo $APP_NAME restart${NC}"
            ;;
        2)
            ${EDITOR:-nano} "$APP_DIR/Caddyfile"
            echo -e "${YELLOW}⚠️  Проверить Caddyfile после редактирования? [Y/n]:${NC}"
            read -p "" validate_choice
            if [[ ! $validate_choice =~ ^[Nn]$ ]]; then
                validate_caddyfile
            fi
            echo -e "${YELLOW}⚠️  Перезапустите Caddy для применения изменений: sudo $APP_NAME restart${NC}"
            ;;
        3)
            ${EDITOR:-nano} "$APP_DIR/docker-compose.yml"
            echo -e "${YELLOW}⚠️  Перезапустите Caddy для применения изменений: sudo $APP_NAME restart${NC}"
            ;;
        0)
            echo -e "${GRAY}Отменено${NC}"
            ;;
        *)
            echo -e "${RED}❌ Неверная опция${NC}"
            ;;
    esac
}




show_help() {
    echo -e "${WHITE}Скрипт управления Caddy for Reality Selfsteal v$SCRIPT_VERSION${NC}"
    echo
    echo -e "${WHITE}Использование:${NC}"
    echo -e "  ${CYAN}$APP_NAME${NC} [${GRAY}команда${NC}]"
    echo
    echo -e "${WHITE}Команды:${NC}"
    printf "   ${CYAN}%-12s${NC} %s\n" "install" "🚀 Установить Caddy для маскировки Reality"
    printf "   ${CYAN}%-12s${NC} %s\n" "up" "▶️  Запустить сервисы Caddy"
    printf "   ${CYAN}%-12s${NC} %s\n" "down" "⏹️  Остановить сервисы Caddy"
    printf "   ${CYAN}%-12s${NC} %s\n" "restart" "🔄 Перезапустить сервисы Caddy"
    printf "   ${CYAN}%-12s${NC} %s\n" "status" "📊 Показать статус сервиса"
    printf "   ${CYAN}%-12s${NC} %s\n" "logs" "📝 Показать логи сервиса"
    printf "   ${CYAN}%-12s${NC} %s\n" "logs-size" "📊 Показать размеры логов"
    printf "   ${CYAN}%-12s${NC} %s\n" "clean-logs" "🧹 Очистить все логи"
    printf "   ${CYAN}%-12s${NC} %s\n" "edit" "✏️  Редактировать файлы конфигурации"
    printf "   ${CYAN}%-12s${NC} %s\n" "uninstall" "🗑️  Удалить установку Caddy"
    printf "   ${CYAN}%-12s${NC} %s\n" "template" "🎨 Управлять шаблонами сайта"
    printf "   ${CYAN}%-12s${NC} %s\n" "menu" "📋 Показать интерактивное меню"
    printf "   ${CYAN}%-12s${NC} %s\n" "update" "🔄 Проверить обновления скрипта"
    echo
    echo -e "${WHITE}Примеры:${NC}"
    echo -e "  ${GRAY}sudo $APP_NAME install${NC}"
    echo -e "  ${GRAY}sudo $APP_NAME status${NC}"
    echo -e "  ${GRAY}sudo $APP_NAME logs${NC}"
    echo
    echo -e "${WHITE}Подробнее смотрите:${NC}"
    echo -e "  ${BLUE}https://github.com/Spakieone/Remna${NC}"
}

check_for_updates() {
    echo -e "${WHITE}🔍 Проверка обновлений...${NC}"
    
    # Check if curl is available
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  curl недоступен, не могу проверить обновления${NC}"
        return 1
    fi
    
    # Get latest version from GitHub script
    echo -e "${WHITE}📝 Получение последней версии скрипта...${NC}"
    local remote_script_version
    remote_script_version=$(curl -s "$UPDATE_URL" 2>/dev/null | grep "^SCRIPT_VERSION=" | cut -d'"' -f2)
    
    if [ -z "$remote_script_version" ]; then
        echo -e "${YELLOW}⚠️  Не удалось получить последнюю версию${NC}"
        return 1
    fi
    
    echo -e "${WHITE}📝 Текущая версия: ${GRAY}v$SCRIPT_VERSION${NC}"
    echo -e "${WHITE}📦 Последняя версия:  ${GRAY}v$remote_script_version${NC}"
    echo
    
    # Compare versions
    if [ "$SCRIPT_VERSION" = "$remote_script_version" ]; then
        echo -e "${GREEN}✅ У вас установлена последняя версия${NC}"
        return 0
    else
        echo -e "${YELLOW}🔄 Доступна новая версия!${NC}"
        echo
        
        # Try to get changelog/release info if available
        echo -e "${WHITE}Что нового в v$remote_script_version:${NC}"
        echo -e "${GRAY}• Исправления и улучшения${NC}"
        echo -e "${GRAY}• Повышена стабильность${NC}"
        echo -e "${GRAY}• Обновлены функции${NC}"
        
        echo
        read -p "Хотите обновить сейчас? [Y/n]: " -r update_choice
        
        if [[ ! $update_choice =~ ^[Nn]$ ]]; then
            update_script
        else
            echo -e "${GRAY}Обновление пропущено${NC}"
        fi
    fi
}

# Update script function
update_script() {
    echo -e "${WHITE}🔄 Обновление скрипта...${NC}"
    
    # Create backup
    local backup_file="/tmp/caddy-selfsteal-backup-$(date +%Y%m%d_%H%M%S).sh"
    if cp "$0" "$backup_file" 2>/dev/null; then
        echo -e "${GRAY}💾 Создана резервная копия: $backup_file${NC}"
    fi
    
    # Download new version
    local temp_file="/tmp/caddy-selfsteal-update-$$.sh"
    
    if curl -fsSL "$UPDATE_URL" -o "$temp_file" 2>/dev/null; then
        # Verify downloaded file
        if [ -s "$temp_file" ] && head -1 "$temp_file" | grep -q "#!/"; then
            # Get new version from downloaded script
            local new_version=$(grep "^SCRIPT_VERSION=" "$temp_file" | cut -d'"' -f2)
            
            # Check if running as root for system-wide update
            if [ "$EUID" -eq 0 ]; then
                # Update system installation
                if [ -f "/usr/local/bin/$APP_NAME" ]; then
                    cp "$temp_file" "/usr/local/bin/$APP_NAME"
                    chmod +x "/usr/local/bin/$APP_NAME"
                    echo -e "${GREEN}✅ Системный скрипт успешно обновлён${NC}"
                fi
                
                # Update current script if different location
                if [ "$0" != "/usr/local/bin/$APP_NAME" ]; then
                    cp "$temp_file" "$0"
                    chmod +x "$0"
                    echo -e "${GREEN}✅ Текущий скрипт успешно обновлён${NC}"
                fi
            else
                # User-level update
                cp "$temp_file" "$0"
                chmod +x "$0"
                echo -e "${GREEN}✅ Скрипт успешно обновлён${NC}"
                echo -e "${YELLOW}💡 Запустите с sudo для обновления системной установки${NC}"
            fi
            
            rm -f "$temp_file"
            
            echo
            echo -e "${WHITE}🎉 Обновление завершено!${NC}"
            echo -e "${WHITE}📝 Обновлено до версии: ${GRAY}v$new_version${NC}"
            echo -e "${GRAY}Пожалуйста, перезапустите скрипт для применения новой версии${NC}"
            echo
            
            read -p "Перезапустить скрипт сейчас? [Y/n]: " -r restart_choice
            if [[ ! $restart_choice =~ ^[Nn]$ ]]; then
                echo -e "${GRAY}Перезапуск...${NC}"
                exec "$0" "$@"
            fi
        else
            echo -e "${RED}❌ Загруженный файл повреждён${NC}"
            rm -f "$temp_file"
            return 1
        fi
    else
        echo -e "${RED}❌ Не удалось скачать обновление${NC}"
        rm -f "$temp_file"
        return 1
    fi
}

# Auto-update check (silent)
check_for_updates_silent() {
    # Simple silent check for updates
    if command -v curl >/dev/null 2>&1; then
        local remote_script_version
        remote_script_version=$(timeout 5 curl -s "$UPDATE_URL" 2>/dev/null | grep "^SCRIPT_VERSION=" | cut -d'"' -f2 2>/dev/null)
        
        if [ -n "$remote_script_version" ] && [ "$SCRIPT_VERSION" != "$remote_script_version" ]; then
            echo -e "${YELLOW}💡 Доступно обновление: v$remote_script_version (текущая: v$SCRIPT_VERSION)${NC}"
            echo -e "${GRAY}   Выполните 'sudo $APP_NAME update' для обновления${NC}"
            echo
        fi
    fi 2>/dev/null || true  # Suppress any errors completely
}

# Manual update command
update_command() {
    check_running_as_root
    check_for_updates
}

# Guide and instructions command
guide_command() {
    clear
    echo -e "${WHITE}📖 Руководство по настройке Selfsteal${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo

    # Get current configuration
    local domain=""
    local port=""
    if [ -f "$APP_DIR/.env" ]; then
        domain=$(grep "SELF_STEAL_DOMAIN=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2)
        port=$(grep "SELF_STEAL_PORT=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2)
    fi

    echo -e "${BLUE}🎯 Что такое Selfsteal?${NC}"
    echo -e "${GRAY}Selfsteal — это фронтенд на базе Caddy для протокола Xray Reality, который обеспечивает:"
    echo "• Маскировку трафика под полноценные сайты"
    echo "• Завершение SSL/TLS и управление сертификатами"
    echo "• Набор шаблонов сайтов для лучшей маскировки"
    echo "• Простую интеграцию с серверами Xray Reality${NC}"
    echo

    echo -e "${BLUE}🔧 Как это работает:${NC}"
    echo -e "${GRAY}1. Caddy работает на пользовательском HTTPS-порту (по умолчанию: 9443)"
    echo "2. Xray Reality перенаправляет нерелевантный трафик в Caddy"
    echo "3. Обычные пользователи видят обычный сайт"
    echo "4. VPN‑клиенты подключаются через протокол Reality${NC}"
    echo

    if [ -n "$domain" ] && [ -n "$port" ]; then
        echo -e "${GREEN}✅ Текущая конфигурация:${NC}"
        echo -e "${WHITE}   Домен:${NC} ${CYAN}$domain${NC}"
        echo -e "${WHITE}   HTTPS-порт:${NC} ${CYAN}$port${NC}"
        echo -e "${WHITE}   URL сайта:${NC} ${CYAN}https://$domain:$port${NC}"
        echo
    else
        echo -e "${YELLOW}⚠️  Selfsteal ещё не настроен. Сначала выполните установку!${NC}"
        echo
    fi

    echo -e "${BLUE}📋 Пример конфигурации Xray Reality:${NC}"
    echo -e "${GRAY}Скопируйте шаблон и адаптируйте под ваш Xray‑сервер:${NC}"
    echo

    # Generate a random private key if openssl is available
    local private_key="#REPLACE_WITH_YOUR_PRIVATE_KEY"
    if command -v openssl >/dev/null 2>&1; then
        private_key=$(openssl rand -base64 32 | tr -d '=' | head -c 43)
    fi

    cat << EOF
${WHITE}{
    "inbounds": [
        {
            "tag": "VLESS_SELFSTEAL_WITH_CADDY",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [],
                "decryption": "none"
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            },
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "xver": 1,
                    "target": "127.0.0.1:${port:-9443}",
                    "spiderX": "",
                    "shortIds": [
                        ""
                    ],
                    "privateKey": "$private_key",
                    "serverNames": [
                        "${domain:-reality.example.com}"
                    ]
                }
            }
        }
    ]
}${NC}
EOF

    echo
    echo -e "${YELLOW}🔑 Замените следующие значения:${NC}"
    echo -e "${GRAY}• ${WHITE}clients[]${GRAY} — добавьте клиентов с их UUID${NC}"
    echo -e "${GRAY}• ${WHITE}shortIds${GRAY} — добавьте ваши Reality short IDs${NC}"
    if command -v openssl >/dev/null 2>&1; then
        echo -e "${GRAY}• ${WHITE}privateKey${GRAY} — сгенерирован выше (или используйте свой)${NC}"
    else
        echo -e "${GRAY}• ${WHITE}privateKey${GRAY} — сгенерируйте инструментами Reality key${NC}"
    fi
    if [ -z "$domain" ]; then
        echo -e "${GRAY}• ${WHITE}reality.example.com${GRAY} — ваш реальный домен${NC}"
    fi
    if [ -z "$port" ] || [ "$port" != "9443" ]; then
        echo -e "${GRAY}• ${WHITE}9443${GRAY} — ваш HTTPS‑порт Caddy${NC}"
    fi
    echo

    echo -e "${BLUE}🔐 Генерация Reality‑ключей${NC}"
    echo -e "${GRAY}• Используйте ${WHITE}Private key${GRAY} в конфигурации Xray‑сервера${NC}"
    echo

    echo -e "${BLUE}📱 Подсказки по настройке клиента:${NC}"
    echo -e "${GRAY}Для клиентов (v2rayN, v2rayNG и т. п.):${NC}"
    echo -e "${WHITE}• Протокол:${NC} VLESS"
    echo -e "${WHITE}• Шифрование:${NC} Reality"
    echo -e "${WHITE}• Сервер:${NC} ${domain:-your-domain.com}"
    echo -e "${WHITE}• Порт:${NC} 443"
    echo -e "${WHITE}• Flow:${NC} xtls-rprx-vision"
    echo -e "${WHITE}• SNI:${NC} ${domain:-your-domain.com}"
    echo -e "${WHITE}• Reality Public Key:${NC} (из генерации x25519)"
    echo

    echo -e "${BLUE}🔍 Проверка вашей настройки:${NC}"
    echo -e "${GRAY}1. Проверьте, запущен ли Caddy:${NC}"
    echo -e "${CYAN}   curl -k https://${domain:-your-domain.com}${NC}"
    echo
    echo -e "${GRAY}2. Убедитесь, что сайт открывается в браузере:${NC}"
    echo -e "${CYAN}   https://${domain:-your-domain.com}${NC}"
    echo
    echo -e "${GRAY}3. Проверьте подключение Xray Reality:${NC}"
    echo -e "${CYAN}   Используйте ваш VPN‑клиент с конфигурацией выше${NC}"
    echo

    echo -e "${BLUE}🛠️  Диагностика:${NC}"
    echo -e "${GRAY}• ${WHITE}Connection refused:${GRAY} проверьте, что Caddy запущен (опция 5)${NC}"
    echo -e "${GRAY}• ${WHITE}Ошибки SSL-сертификата:${GRAY} убедитесь, что DNS указывает на ваш сервер${NC}"
    echo -e "${GRAY}• ${WHITE}Reality не работает:${GRAY} проверьте доступность порта ${port:-9443}${NC}"
    echo -e "${GRAY}• ${WHITE}Сайт не загружается:${GRAY} попробуйте переустановить шаблон (опция 6)${NC}"
    echo

    echo -e "${GREEN}💡 Полезные советы:${NC}"
    echo -e "${GRAY}• Используйте разные шаблоны сайта для маскировки${NC}"
    echo -e "${GRAY}• Следите за корректностью DNS-настроек домена${NC}"
    echo -e "${GRAY}• Регулярно проверяйте логи на проблемы${NC}"
    echo -e "${GRAY}• Регулярно обновляйте Caddy и Xray${NC}"
    echo


    echo -e "${YELLOW}📚 Дополнительные материалы:${NC}"
    echo -e "${GRAY}• Документация Xray: ${CYAN}https://xtls.github.io/${NC}"
    echo -e "${GRAY}• Руководство по Reality: ${CYAN}https://github.com/XTLS/REALITY${NC}"
    echo
}

main_menu() {    # Auto-check for updates on first run
    # check_for_updates_silent
    
    while true; do
        clear
    echo -e "${WHITE}🔗 Caddy for Reality Selfsteal${NC}"
    echo -e "${GRAY}Система управления v$SCRIPT_VERSION${NC}"
        echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
        echo


        local menu_status="Not installed"
        local status_color="$GRAY"
        local domain=""
        local port=""
        
        if [ -d "$APP_DIR" ]; then
            if [ -f "$APP_DIR/.env" ]; then
                domain=$(grep "SELF_STEAL_DOMAIN=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2)
                port=$(grep "SELF_STEAL_PORT=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2)
            fi
            
            cd "$APP_DIR"
            local container_state=$(docker compose ps --format "{{.State}}" 2>/dev/null | head -1)
            
            case "$container_state" in
                "running")
                    menu_status="Running"
                    status_color="$GREEN"
                    ;;
                "restarting")
                    menu_status="Error (Restarting)"
                    status_color="$YELLOW"
                    ;;
                "exited"|"stopped")
                    menu_status="Stopped"
                    status_color="$RED"
                    ;;
                "paused")
                    menu_status="Paused"
                    status_color="$YELLOW"
                    ;;
                *)
                    if [ -f "$APP_DIR/docker-compose.yml" ]; then
                        menu_status="Not running"
                        status_color="$RED"
                    else
                        menu_status="Not installed"
                        status_color="$GRAY"
                    fi
                    ;;
            esac
        fi
        
        case "$menu_status" in
            "Running")
                echo -e "${status_color}✅ Статус: Запущен${NC}"
                ;;
            "Error (Restarting)")
                echo -e "${status_color}⚠️  Статус: Ошибка (перезапуск)${NC}"
                ;;
            "Stopped"|"Not running")
                echo -e "${status_color}❌ Статус: Остановлен${NC}"
                ;;
            "Paused")
                echo -e "${status_color}⏸️  Статус: Приостановлен${NC}"
                ;;
            *)
                echo -e "${status_color}📦 Статус: $menu_status${NC}"
                ;;
        esac
        
        # Check for system Caddy
        if systemctl is-active --quiet caddy 2>/dev/null; then
            local sys_caddy_domain=""
            if [ -f "/etc/caddy/Caddyfile" ]; then
                sys_caddy_domain=$(grep -E '^[a-zA-Z0-9.-]+\s*{' /etc/caddy/Caddyfile | head -1 | awk '{print $1}' | sed 's/{$//')
            fi
            echo -e "${YELLOW}⚠️  Системный Caddy активен${NC}"
            if [ -n "$sys_caddy_domain" ]; then
                echo -e "${GRAY}   Домен: $sys_caddy_domain${NC}"
            fi
        fi
        
        if [ -n "$domain" ]; then
            printf "   ${WHITE}%-10s${NC} ${GRAY}%s${NC}\n" "Домен:" "$domain"
        fi
        if [ -n "$port" ]; then
            printf "   ${WHITE}%-10s${NC} ${GRAY}%s${NC}\n" "Порт:" "$port"
        fi
        
        if [ "$menu_status" = "Error (Restarting)" ]; then
            echo
            echo -e "${YELLOW}⚠️  Сервис испытывает проблемы!${NC}"
            echo -e "${GRAY}   Рекомендуется: Проверить логи (опция 8) или перезапустить сервисы (опция 4)${NC}"
        fi
        
        echo
        echo -e "${WHITE}📋 Доступные операции:${NC}"
        echo

        echo -e "${WHITE}🔧 Управление сервисом:${NC}"
        echo -e "   ${WHITE}1)${NC} 🚀 Установить Caddy"
        echo -e "   ${WHITE}2)${NC} ▶️  Запустить сервисы"
        echo -e "   ${WHITE}3)${NC} ⏹️  Остановить сервисы"
        echo -e "   ${WHITE}4)${NC} 🔄 Перезапустить сервисы"
        echo -e "   ${WHITE}5)${NC} 📊 Статус сервиса"
        echo

        echo -e "${WHITE}🎨 Управление сайтом:${NC}"
        echo -e "   ${WHITE}6)${NC} 🎨 Шаблоны сайтов"
        echo -e "   ${WHITE}7)${NC} 📖 Руководство по настройке"
        echo

        echo -e "${WHITE}📝 Логи и мониторинг:${NC}"
        echo -e "   ${WHITE}8)${NC} 📝 Просмотреть логи"
        echo -e "   ${WHITE}9)${NC} 📊 Размеры логов"
        echo -e "   ${WHITE}10)${NC} 🧹 Очистить логи"
        echo -e "   ${WHITE}11)${NC} ✏️  Редактировать конфигурацию"
        echo

        echo -e "${WHITE}🗑️  Обслуживание:${NC}"
        echo -e "   ${WHITE}12)${NC} 🗑️  Удалить Caddy"
        echo -e "   ${WHITE}13)${NC} 🔄 Проверить обновления"
        echo
        echo -e "   ${GRAY}0)${NC} ⬅️  Выход"
        echo
        case "$menu_status" in
            "Not installed")
                echo -e "${BLUE}💡 Подсказка: начните с опции 1 для установки Caddy${NC}"
                ;;
            "Stopped"|"Not running")
                echo -e "${BLUE}💡 Подсказка: используйте опцию 2 для запуска сервисов${NC}"
                ;;
            "Error (Restarting)")
                echo -e "${BLUE}💡 Подсказка: проверьте логи (7) для диагностики проблем${NC}"
                ;;
            "Running")
                echo -e "${BLUE}💡 Подсказка: используйте опцию 6 для настройки шаблонов сайта${NC}"
                ;;
        esac

        read -p "$(echo -e "${WHITE}Выберите опцию [0-13]:${NC} ")" choice

        case "$choice" in
            1) install_command; read -p "Нажмите Enter для продолжения..." ;;
            2) up_command; read -p "Нажмите Enter для продолжения..." ;;
            3) down_command; read -p "Нажмите Enter для продолжения..." ;;
            4) restart_command; read -p "Нажмите Enter для продолжения..." ;;
            5) status_command; read -p "Нажмите Enter для продолжения..." ;;
            6) template_command ;;
            7) guide_command; read -p "Нажмите Enter для продолжения..." ;;
            8) logs_command; read -p "Нажмите Enter для продолжения..." ;;
            9) logs_size_command; read -p "Нажмите Enter для продолжения..." ;;
            10) clean_logs_command; read -p "Нажмите Enter для продолжения..." ;;
            11) edit_command; read -p "Нажмите Enter для продолжения..." ;;
            12) uninstall_command; read -p "Нажмите Enter для продолжения..." ;;
            13) update_command; read -p "Нажмите Enter для продолжения..." ;;
            0) clear; exit 0 ;;
            *) 
                echo -e "${RED}❌ Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Main execution
case "$COMMAND" in
    install) install_command ;;
    up) up_command ;;
    down) down_command ;;
    restart) restart_command ;;
    status) status_command ;;
    logs) logs_command ;;
    logs-size) logs_size_command ;;
    clean-logs) clean_logs_command ;;
    edit) edit_command ;;
    uninstall) uninstall_command ;;
    template) template_command ;;
    guide) guide_command ;;
    menu) main_menu ;;
    update) update_command ;;
    check-update) update_command ;;
    help) show_help ;;
    --version|-v) echo "Caddy Selfsteal Management Script v$SCRIPT_VERSION" ;;
    --help|-h) show_help ;;
    "") main_menu ;;
    *) 
        echo -e "${RED}❌ Unknown command: $COMMAND${NC}"
        echo "Use '$APP_NAME --help' for usage information."
        exit 1
        ;;
esac
