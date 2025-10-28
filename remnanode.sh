install_tblocker_command() {
    echo -e "\033[1;37m🛡️  Установка tBlocker\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    local script_name="install-tblocker.sh"
    if [ -f "script/scripts-main/$script_name" ]; then
        bash "script/scripts-main/$script_name" install
    else
        echo -e "\033[38;5;244mСкачивание $script_name с GitHub...\033[0m"
        bash <(curl -fsSL "https://raw.githubusercontent.com/Spakieone/Remna/main/$script_name") install
    fi
}

uninstall_tblocker_command() {
    echo -e "\033[1;37m🗑️  Удаление tBlocker\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    local script_name="install-tblocker.sh"
    if [ -f "script/scripts-main/$script_name" ]; then
        bash "script/scripts-main/$script_name" uninstall
    else
        echo -e "\033[38;5;244mСкачивание $script_name с GitHub...\033[0m"
        bash <(curl -fsSL "https://raw.githubusercontent.com/Spakieone/Remna/main/$script_name") uninstall
    fi
}

# ===== Функции управления UFW =====

ufw_enable_command() {
    echo -e "\033[1;37m🔥 Включение UFW\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "\033[1;31m❌ UFW не установлен!\033[0m"
        echo -e "\033[38;5;244mУстановите UFW: sudo apt install ufw\033[0m"
        return 1
    fi
    
    if ufw status | grep -q "Status: active"; then
        echo -e "\033[1;33m⚠️  UFW уже активен\033[0m"
    else
        echo -e "\033[1;32m✅ Включаем UFW...\033[0m"
        
        # Открываем стандартные порты перед включением
        echo -e "\033[1;37m🔓 Открываем стандартные порты:\033[0m"
        echo -e "\033[1;32m  • SSH (22)...\033[0m"
        sudo ufw allow 22/tcp
        
        echo -e "\033[1;32m  • HTTPS (443)...\033[0m"
        sudo ufw allow 443/tcp
        
        # Включаем UFW
        if sudo ufw --force enable; then
            echo -e "\033[1;32m✅ UFW успешно включен с открытыми портами SSH и HTTPS\033[0m"
        else
            echo -e "\033[1;31m❌ Ошибка при включении UFW\033[0m"
        fi
    fi
}

ufw_disable_command() {
    echo -e "\033[1;37m❌ Выключение UFW\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "\033[1;31m❌ UFW не установлен!\033[0m"
        return 1
    fi
    
    if ! ufw status | grep -q "Status: active"; then
        echo -e "\033[1;33m⚠️  UFW уже неактивен\033[0m"
    else
        echo -e "\033[1;33m⚠️  Выключаем UFW...\033[0m"
        if sudo ufw --force disable; then
            echo -e "\033[1;32m✅ UFW успешно выключен\033[0m"
        else
            echo -e "\033[1;31m❌ Ошибка при выключении UFW\033[0m"
        fi
    fi
}

ufw_open_ports_command() {
    echo -e "\033[1;37m🌐 Открытие портов для IP\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "\033[1;31m❌ UFW не установлен!\033[0m"
        echo -e "\033[38;5;244mУстановите UFW: sudo apt install ufw\033[0m"
        return 1
    fi
    
    # Получаем порт из конфигурации для отображения в шапке
    local node_port="6001"
    if [ -f "$ENV_FILE" ]; then
        node_port=$(grep "APP_PORT=" "$ENV_FILE" | cut -d'=' -f2 2>/dev/null || echo "6001")
    fi
    
    echo -e "\033[1;37mВыберите порт для открытия:\033[0m"
    echo -e "\033[38;5;244mТекущий порт RemnaNode: $node_port\033[0m"
    echo
    echo -e "\033[1;37mДоступные порты:\033[0m"
    echo -e "   \033[38;5;15m1)\033[0m \033[1;32m9100\033[0m - Node Exporter (мониторинг)"
    echo -e "   \033[38;5;15m2)\033[0m \033[1;32m$node_port\033[0m - RemnaNode (текущий порт)"
    echo -e "   \033[38;5;15m3)\033[0m \033[1;32m22\033[0m - SSH"
    echo -e "   \033[38;5;15m4)\033[0m \033[1;32m443\033[0m - HTTPS"
    echo -e "   \033[38;5;15m5)\033[0m \033[1;32mДругой порт\033[0m - ввести вручную"
    echo
    
    read -p "Выберите опцию [1-5]: " port_choice
    
    local selected_port=""
    case "$port_choice" in
        1) selected_port="9100" ;;
        2) selected_port="$node_port" ;;
        3) selected_port="22" ;;
        4) selected_port="443" ;;
        5) 
            read -p "Введите номер порта: " selected_port
            if ! [[ "$selected_port" =~ ^[0-9]+$ ]] || [ "$selected_port" -lt 1 ] || [ "$selected_port" -gt 65535 ]; then
                echo -e "\033[1;31m❌ Неверный номер порта! Должен быть от 1 до 65535\033[0m"
                return 1
            fi
            ;;
        *)
            echo -e "\033[1;31m❌ Неверный выбор!\033[0m"
            return 1
            ;;
    esac
    
    echo
    echo -e "\033[1;37mВведите IP адрес для открытия порта $selected_port:\033[0m"
    echo -e "\033[38;5;244mПример: 192.168.1.100 или 10.0.0.0/8\033[0m"
    read -p "IP адрес: " target_ip
    
    if [ -z "$target_ip" ]; then
        echo -e "\033[1;31m❌ IP адрес не может быть пустым\033[0m"
        return 1
    fi
    
    echo
    echo -e "\033[1;37mОткрываем порт $selected_port для $target_ip:\033[0m"
    
    if sudo ufw allow from "$target_ip" to any port "$selected_port"; then
        echo -e "\033[1;32m✅ Порт $selected_port успешно открыт для $target_ip\033[0m"
    else
        echo -e "\033[1;31m❌ Ошибка при открытии порта $selected_port\033[0m"
    fi
}

ufw_reset_command() {
    echo -e "\033[1;37m🗑️  Сброс правил UFW\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "\033[1;31m❌ UFW не установлен!\033[0m"
        return 1
    fi
    
    echo -e "\033[1;33m⚠️  ВНИМАНИЕ: Это удалит ВСЕ правила UFW!\033[0m"
    read -p "Вы уверены? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "\033[1;32m✅ Сбрасываем правила UFW...\033[0m"
        if sudo ufw --force reset; then
            echo -e "\033[1;32m✅ Правила UFW успешно сброшены\033[0m"
        else
            echo -e "\033[1;31m❌ Ошибка при сбросе правил UFW\033[0m"
        fi
    else
        echo -e "\033[1;33m⚠️  Операция отменена\033[0m"
    fi
}

ufw_show_rules_command() {
    echo -e "\033[1;37m📋 Правила UFW\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "\033[1;31m❌ UFW не установлен!\033[0m"
        return 1
    fi
    
    echo -e "\033[1;37mСтатус UFW:\033[0m"
    sudo ufw status verbose
}

ufw_remove_remnanode_rules_command() {
    echo -e "\033[1;37m🗑️  Удаление правил UFW\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "\033[1;31m❌ UFW не установлен!\033[0m"
        return 1
    fi
    
    # Получаем порт из конфигурации
    local node_port="6001"
    if [ -f "$ENV_FILE" ]; then
        node_port=$(grep "APP_PORT=" "$ENV_FILE" | cut -d'=' -f2 2>/dev/null || echo "6001")
    fi
    
    echo -e "\033[1;37mУдаляем правила для порта $node_port...\033[0m"
    
    # Удаляем правила для RemnaNode порта
    sudo ufw delete allow "$node_port" 2>/dev/null || true
    sudo ufw delete deny "$node_port" 2>/dev/null || true
    
    echo -e "\033[1;32m✅ Правила UFW удалены\033[0m"
    echo -e "\033[38;5;244mТекущие правила:\033[0m"
    sudo ufw status numbered
}

node_exporter_menu_command() { :; }


#!/usr/bin/env bash
# Version: 3.2.2
set -e
SCRIPT_VERSION="3.2.2"

# Handle @ prefix for consistency with other scripts
if [ $# -gt 0 ] && [ "$1" = "@" ]; then
    shift  
fi

# Parse command line arguments
COMMAND=""
if [ $# -gt 0 ]; then
    COMMAND="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    key="$1"
    
    case $key in
        --name)
            # Имя приложения принудительно фиксировано как 'remnanode'
            echo "⚠️  Параметр --name игнорируется. Используется имя 'remnanode'."
            shift # past argument
            shift # past value
        ;;
        --dev)
            if [[ "$COMMAND" == "install" ]]; then
                USE_DEV_BRANCH="true"
            else
                echo "Ошибка: параметр --dev разрешен только с командой 'install'."
                exit 1
            fi
            shift # past argument
        ;;
        --help|-h)
            show_command_help "$COMMAND"
            exit 0
        ;;
        *)
            echo "Неизвестный аргумент: $key"
            exit 1
        ;;
    esac
done

# Fetch IP address from ipinfo.io API
NODE_IP=$(curl -s -4 ifconfig.io)

# If the IPv4 retrieval is empty, attempt to retrieve the IPv6 address
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(curl -s -6 ifconfig.io)
fi

APP_NAME="remnanode"

INSTALL_DIR="/opt"
APP_DIR="$INSTALL_DIR/$APP_NAME"
DATA_DIR="/var/lib/$APP_NAME"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
ENV_FILE="$APP_DIR/.env"
XRAY_FILE="$DATA_DIR/xray"
GEOIP_FILE="$DATA_DIR/geoip.dat"
GEOSITE_FILE="$DATA_DIR/geosite.dat"
SCRIPT_URL="https://raw.githubusercontent.com/Spakieone/Remna/main/remnanode.sh"

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

colorized_echo() {
    local color=$1
    local text=$2
    local style=${3:-0}  # Default style is normal

    case $color in
        "red") printf "\e[${style};91m${text}\e[0m\n" ;;
        "green") printf "\e[${style};92m${text}\e[0m\n" ;;
        "yellow") printf "\e[${style};93m${text}\e[0m\n" ;;
        "blue") printf "\e[${style};94m${text}\e[0m\n" ;;
        "magenta") printf "\e[${style};95m${text}\e[0m\n" ;;
        "cyan") printf "\e[${style};96m${text}\e[0m\n" ;;
        *) echo "${text}" ;;
    esac
}

check_running_as_root() {
    if [ "$(id -u)" != "0" ]; then
        colorized_echo red "Эта команда должна выполняться от root."
        exit 1
    fi
}


check_system_requirements() {
    local errors=0
    
    # Проверяем свободное место (минимум 1GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 1048576 ]; then  # 1GB в KB
        colorized_echo red "Ошибка: Недостаточно места на диске. Требуется минимум 1GB."
        errors=$((errors + 1))
    fi
    
    # Проверяем RAM (минимум 512MB)
    local available_ram=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_ram" -lt 256 ]; then
        colorized_echo yellow "Предупреждение: Мало доступной RAM (${available_ram}MB). Производительность может пострадать."
    fi
    
    # Проверяем архитектуру
    if ! identify_the_operating_system_and_architecture 2>/dev/null; then
        colorized_echo red "Ошибка: Неподдерживаемая архитектура системы."
        errors=$((errors + 1))
    fi
    
    return $errors
}

detect_os() {
    if [ -f /etc/lsb-release ]; then
        OS=$(lsb_release -si)
    elif [ -f /etc/os-release ]; then
        OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
        if [[ "$OS" == "Amazon Linux" ]]; then
            OS="Amazon"
        fi
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | awk '{print $1}')
    elif [ -f /etc/arch-release ]; then
        OS="Arch"
    else
        colorized_echo red "Неподдерживаемая операционная система"
        exit 1
    fi
}

detect_and_update_package_manager() {
    colorized_echo blue "Обновление менеджера пакетов"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        PKG_MANAGER="apt-get"
        $PKG_MANAGER update -qq >/dev/null 2>&1
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "AlmaLinux"* ]] || [[ "$OS" == "Amazon"* ]]; then
        PKG_MANAGER="yum"
        $PKG_MANAGER update -y -q >/dev/null 2>&1
        if [[ "$OS" != "Amazon" ]]; then
            $PKG_MANAGER install -y -q epel-release >/dev/null 2>&1
        fi
    elif [[ "$OS" == "Fedora"* ]]; then
        PKG_MANAGER="dnf"
        $PKG_MANAGER update -q -y >/dev/null 2>&1
    elif [[ "$OS" == "Arch"* ]]; then
        PKG_MANAGER="pacman"
        $PKG_MANAGER -Sy --noconfirm --quiet >/dev/null 2>&1
    elif [[ "$OS" == "openSUSE"* ]]; then
        PKG_MANAGER="zypper"
        $PKG_MANAGER refresh --quiet >/dev/null 2>&1
    else
        colorized_echo red "Неподдерживаемая операционная система"
        exit 1
    fi
}

detect_compose() {
    if docker compose >/dev/null 2>&1; then
        COMPOSE='docker compose'
    elif docker-compose >/dev/null 2>&1; then
        COMPOSE='docker-compose'
    else
        if [[ "$OS" == "Amazon"* ]]; then
            colorized_echo blue "Плагин Docker Compose не найден. Попытка ручной установки..."
            mkdir -p /usr/libexec/docker/cli-plugins
            curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/libexec/docker/cli-plugins/docker-compose >/dev/null 2>&1
            chmod +x /usr/libexec/docker/cli-plugins/docker-compose
            if docker compose >/dev/null 2>&1; then
                COMPOSE='docker compose'
                colorized_echo green "Плагин Docker Compose успешно установлен"
            else
                colorized_echo red "Не удалось установить плагин Docker Compose. Проверьте настройки."
                exit 1
            fi
        else
            colorized_echo red "docker compose не найден"
            exit 1
        fi
    fi
}

install_package() {
    if [ -z "$PKG_MANAGER" ]; then
        detect_and_update_package_manager
    fi

    PACKAGE=$1
    colorized_echo blue "Установка $PACKAGE"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        $PKG_MANAGER -y -qq install "$PACKAGE" >/dev/null 2>&1
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "AlmaLinux"* ]] || [[ "$OS" == "Amazon"* ]]; then
        $PKG_MANAGER install -y -q "$PACKAGE" >/dev/null 2>&1
    elif [[ "$OS" == "Fedora"* ]]; then
        $PKG_MANAGER install -y -q "$PACKAGE" >/dev/null 2>&1
    elif [[ "$OS" == "Arch"* ]]; then
        $PKG_MANAGER -S --noconfirm --quiet "$PACKAGE" >/dev/null 2>&1
    elif [[ "$OS" == "openSUSE"* ]]; then
        $PKG_MANAGER --quiet install -y "$PACKAGE" >/dev/null 2>&1
    else
        colorized_echo red "Неподдерживаемая операционная система"
        exit 1
    fi
}

install_docker() {
    colorized_echo blue "Установка Docker"
    if [[ "$OS" == "Amazon"* ]]; then
        amazon-linux-extras enable docker >/dev/null 2>&1
        yum install -y docker >/dev/null 2>&1
        systemctl start docker
        systemctl enable docker
        colorized_echo green "Docker успешно установлен на Amazon Linux"
    else
        curl -fsSL https://get.docker.com | sh
        colorized_echo green "Docker успешно установлен"
    fi
}

install_remnanode_script() {
    colorized_echo blue "Установка скрипта remnanode"
    TARGET_PATH="/usr/local/bin/$APP_NAME"
    curl -sSL $SCRIPT_URL -o $TARGET_PATH
    chmod 755 $TARGET_PATH
    colorized_echo green "Скрипт Remnanode успешно установлен в $TARGET_PATH"
}

# Улучшенная функция проверки доступности портов
validate_port() {
    local port="$1"
    
    # Проверяем диапазон портов
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    
    # Проверяем, что порт не зарезервирован системой
    if [ "$port" -lt 1024 ] && [ "$(id -u)" != "0" ]; then
        colorized_echo yellow "Предупреждение: Порт $port требует привилегий root"
    fi
    
    return 0
}

# Улучшенная функция получения занятых портов с fallback
get_occupied_ports() {
    local ports=""
    
    if command -v ss &>/dev/null; then
        ports=$(ss -tuln 2>/dev/null | awk 'NR>1 {print $5}' | grep -Eo '[0-9]+$' | sort -n | uniq)
    elif command -v netstat &>/dev/null; then
        ports=$(netstat -tuln 2>/dev/null | awk 'NR>2 {print $4}' | grep -Eo '[0-9]+$' | sort -n | uniq)
    else
        colorized_echo yellow "Не найдены ss или netstat. Устанавливаем net-tools..."
        detect_os
        if install_package net-tools; then
            if command -v netstat &>/dev/null; then
                ports=$(netstat -tuln 2>/dev/null | awk 'NR>2 {print $4}' | grep -Eo '[0-9]+$' | sort -n | uniq)
            fi
        else
            colorized_echo yellow "Не удалось установить net-tools. Пропускаем проверку конфликтов портов."
            return 1
        fi
    fi
    
    OCCUPIED_PORTS="$ports"
    return 0
}
is_port_occupied() {
    if echo "$OCCUPIED_PORTS" | grep -q -w "$1"; then
        return 0
    else
        return 1
    fi
}

install_latest_xray_core() {
    colorized_echo blue "🚀 Начинаем установку Xray-core..."
    identify_the_operating_system_and_architecture
    mkdir -p "$DATA_DIR"
    cd "$DATA_DIR"
    
    latest_release=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep -oP '"tag_name": "\K(.*?)(?=")')
    if [ -z "$latest_release" ]; then
        colorized_echo red "Не удалось получить последнюю версию Xray-core."
        exit 1
    fi
    
    if ! dpkg -s unzip >/dev/null 2>&1; then
        colorized_echo blue "Установка unzip..."
        detect_os
        install_package unzip
    fi
    
    xray_filename="Xray-linux-$ARCH.zip"
    xray_download_url="https://github.com/XTLS/Xray-core/releases/download/${latest_release}/${xray_filename}"
    
    colorized_echo blue "Загрузка Xray-core версии ${latest_release}..."
    colorized_echo yellow "URL: ${xray_download_url}"
    wget "${xray_download_url}" -q --show-progress
    if [ $? -ne 0 ]; then
        colorized_echo red "Ошибка: Не удалось загрузить Xray-core."
        exit 1
    fi
    colorized_echo green "✅ Загрузка завершена"
    
    colorized_echo blue "Извлечение Xray-core..."
    unzip -o "${xray_filename}" -d "$DATA_DIR" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        colorized_echo red "Ошибка: Не удалось извлечь Xray-core."
        exit 1
    fi
    colorized_echo green "✅ Извлечение завершено"

    rm "${xray_filename}"
    chmod +x "$XRAY_FILE"
    
    # Check what files were extracted
    colorized_echo blue "Извлеченные файлы:"
    if [ -f "$XRAY_FILE" ]; then
        colorized_echo green "  ✅ исполняемый файл xray"
    fi
    if [ -f "$GEOIP_FILE" ]; then
        colorized_echo green "  ✅ geoip.dat"
    fi
    if [ -f "$GEOSITE_FILE" ]; then
        colorized_echo green "  ✅ geosite.dat"
    fi
    
    colorized_echo green "Последний Xray-core (${latest_release}) установлен в $XRAY_FILE"
}

setup_log_rotation() {
    check_running_as_root
    
    # Check if the directory exists
    if [ ! -d "$DATA_DIR" ]; then
        colorized_echo blue "Создание директории $DATA_DIR"
        mkdir -p "$DATA_DIR"
    else
        colorized_echo green "Директория $DATA_DIR уже существует"
    fi
    
    # Check if logrotate is installed
    if ! command -v logrotate &> /dev/null; then
        colorized_echo blue "Установка logrotate"
        detect_os
        install_package logrotate
    else
        colorized_echo green "Logrotate уже установлен"
    fi
    
    # Check if logrotate config already exists
    LOGROTATE_CONFIG="/etc/logrotate.d/remnanode"
    if [ -f "$LOGROTATE_CONFIG" ]; then
        colorized_echo yellow "Конфигурация logrotate уже существует в $LOGROTATE_CONFIG"
        read -p "Хотите перезаписать её? (y/n): " -r overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            colorized_echo yellow "Сохраняем существующую конфигурацию logrotate"
            return
        fi
    fi
    
    # Create logrotate configuration
    colorized_echo blue "Создание конфигурации logrotate в $LOGROTATE_CONFIG"
    cat > "$LOGROTATE_CONFIG" <<EOL
$DATA_DIR/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
EOL

    chmod 644 "$LOGROTATE_CONFIG"
    
    # Test logrotate configuration
    colorized_echo blue "Тестирование конфигурации logrotate"
    if logrotate -d "$LOGROTATE_CONFIG" &> /dev/null; then
        colorized_echo green "Тест конфигурации logrotate прошел успешно"
        
        # Ask if user wants to run logrotate now
        read -p "Хотите запустить logrotate сейчас? (y/n): " -r run_now
        if [[ $run_now =~ ^[Yy]$ ]]; then
            colorized_echo blue "Запуск logrotate"
            if logrotate -vf "$LOGROTATE_CONFIG"; then
                colorized_echo green "Logrotate выполнен успешно"
            else
                colorized_echo red "Ошибка при запуске logrotate"
            fi
        fi
    else
        colorized_echo red "Тест конфигурации logrotate не прошел"
        logrotate -d "$LOGROTATE_CONFIG"
    fi
    
    # Update docker-compose.yml to mount logs directory
    if [ -f "$COMPOSE_FILE" ]; then
        colorized_echo blue "Обновление docker-compose.yml для монтирования директории логов"
        

        colorized_echo blue "Создание резервной копии docker-compose.yml..."
        backup_file=$(create_backup "$COMPOSE_FILE")
        if [ $? -eq 0 ]; then
            colorized_echo green "Резервная копия создана: $backup_file"
        else
            colorized_echo red "Не удалось создать резервную копию"
            return
        fi
        

        local service_indent=$(get_service_property_indentation "$COMPOSE_FILE")
        local indent_type=""
        if [[ "$service_indent" =~ $'\t' ]]; then
            indent_type=$'\t'
        else
            indent_type="  "
        fi
        local volume_item_indent="${service_indent}${indent_type}"
        

        local escaped_service_indent=$(escape_for_sed "$service_indent")
        local escaped_volume_item_indent=$(escape_for_sed "$volume_item_indent")
        

        if grep -q "^${escaped_service_indent}volumes:" "$COMPOSE_FILE"; then
            # Попробовать определить фактический отступ элементов '-' внутри текущей секции volumes
            local detected_item_indent=""
            detected_item_indent=$(awk 'found_volumes && match($0,/^[[:space:]]*-[[:space:]]/){ m=substr($0,1,RLENGTH-2); print m; exit } /^[[:space:]]*volumes:[[:space:]]*$/ { found_volumes=1 }' "$COMPOSE_FILE")
            if [ -n "$detected_item_indent" ]; then
                volume_item_indent="$detected_item_indent"
            fi
            
            # Проверяем, есть ли уже том логов
            if ! grep -q "/var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"; then
                # Находим последний элемент в секции volumes и добавляем после него
                local last_volume_line=$(awk '/^[[:space:]]*volumes:[[:space:]]*$/ { found=1; next } found && /^[[:space:]]*-[[:space:]]/ { last_line=NR } found && /^[[:space:]]*[a-zA-Z]/ && !/^[[:space:]]*-/ { exit } END { print last_line }' "$COMPOSE_FILE")
                if [ -n "$last_volume_line" ]; then
                    sed -i "${last_volume_line}a\\${volume_item_indent}- /var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"
                else
                    sed -i "/^${escaped_service_indent}volumes:/a\\${volume_item_indent}- /var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"
                fi
                colorized_echo green "Добавлен том логов в существующую секцию volumes"
            else
                colorized_echo yellow "Том логов уже существует в секции volumes"
            fi

            # Нормализуем отступы в секции volumes (на случай ранее добавленных строк)
            normalize_volumes_indentation "$COMPOSE_FILE"
        elif grep -q "^${escaped_service_indent}# volumes:" "$COMPOSE_FILE"; then
            sed -i "s|^${escaped_service_indent}# volumes:|${service_indent}volumes:|g" "$COMPOSE_FILE"
            
            if grep -q "^${escaped_volume_item_indent}#.*/var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"; then
                sed -i "s|^${escaped_volume_item_indent}#.*/var/log/remnanode:/var/log/remnanode|${volume_item_indent}- /var/log/remnanode:/var/log/remnanode|g" "$COMPOSE_FILE"
                colorized_echo green "Раскомментирована секция volumes и строка тома логов"
            else
                sed -i "/^${escaped_service_indent}volumes:/a\\${volume_item_indent}- /var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"
                colorized_echo green "Раскомментирована секция volumes и добавлена строка тома логов"
            fi
        else
            # Проверяем, есть ли уже секция volumes где-то в файле
            if grep -q "^[[:space:]]*volumes:" "$COMPOSE_FILE"; then
                # Если volumes есть, но не в нужном месте, исправляем это
                colorized_echo yellow "Найдена секция volumes, но не в правильном месте. Исправляем..."
                # Удаляем все существующие volumes и создаем правильную
                sed -i '/^[[:space:]]*volumes:/,/^[[:space:]]*[a-zA-Z]/ { /^[[:space:]]*[a-zA-Z]/!d; }' "$COMPOSE_FILE"
            fi
            sed -i "/^${escaped_service_indent}restart: always/a\\${service_indent}volumes:\\n${volume_item_indent}- /var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"
            colorized_echo green "Добавлена новая секция volumes с томом логов"
        fi
        

        colorized_echo blue "Проверка docker-compose.yml..."
        if validate_compose_file "$COMPOSE_FILE"; then
            colorized_echo green "Проверка docker-compose.yml прошла успешно"
            cleanup_old_backups "$COMPOSE_FILE"

            if is_remnanode_up; then
                read -p "Хотите перезапустить RemnaNode для применения изменений? (y/n): " -r restart_now
                if [[ $restart_now =~ ^[Yy]$ ]]; then
                    colorized_echo blue "Перезапуск RemnaNode"
                    if $APP_NAME restart -n; then
                        colorized_echo green "RemnaNode успешно перезапущен"
                    else
                        colorized_echo red "Не удалось перезапустить RemnaNode"
                    fi
                else
                    colorized_echo yellow "Не забудьте перезапустить RemnaNode для применения изменений"
                fi
            fi
        else
            colorized_echo red "Проверка docker-compose.yml не прошла! Восстановление резервной копии..."
            if restore_backup "$backup_file" "$COMPOSE_FILE"; then
                colorized_echo green "Резервная копия успешно восстановлена"
            else
                colorized_echo red "Не удалось восстановить резервную копию!"
            fi
            return
        fi
    else
        colorized_echo yellow "Файл Docker Compose не найден. Директория логов будет смонтирована при следующей установке."
    fi
    
    colorized_echo green "Настройка ротации логов успешно завершена"
}

install_remnanode() {

    if ! check_system_requirements; then
        colorized_echo red "Проверка системных требований не прошла. Установка прервана."
        exit 1
    fi

    colorized_echo blue "Создание директории $APP_DIR"
    mkdir -p "$APP_DIR"

    colorized_echo blue "Создание директории $DATA_DIR"
    mkdir -p "$DATA_DIR"

    # Create log directory for tBlocker compatibility
    colorized_echo blue "Создание директории логов /var/log/remnanode"
    mkdir -p /var/log/remnanode

    echo
    echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;36m📋 Вставка конфигурации Docker Compose\033[0m"
    echo -e "\033[38;5;8m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo
    colorized_echo yellow "Вставьте содержимое docker-compose.yml из Remnawave-Panel"
    colorized_echo blue "Нажмите ENTER на пустой строке, когда закончите вставку:"
    echo
    
    COMPOSE_CONTENT=""
    line_count=0
    while IFS= read -r line; do
        if [[ -z "$line" ]] && [[ $line_count -gt 0 ]]; then
            break
        fi
        if [[ -n "$line" ]]; then
            COMPOSE_CONTENT="$COMPOSE_CONTENT$line"$'\n'
            ((line_count++))
        fi
    done

    if [[ -z "$COMPOSE_CONTENT" ]]; then
        colorized_echo red "❌ Ошибка: docker-compose.yml не может быть пустым!"
        exit 1
    fi

    # Save original compose file
    echo "$COMPOSE_CONTENT" > "$COMPOSE_FILE.tmp"
    
    # Add log volume to docker-compose.yml
    colorized_echo blue "Добавление volume для логов в docker-compose.yml..."
    
    # Check if volumes section exists
    if grep -q "^[[:space:]]*volumes:" "$COMPOSE_FILE.tmp"; then
        # Volumes section exists - check if log volume already present
        if grep -q "/var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE.tmp"; then
            colorized_echo green "✅ Volume для логов уже присутствует"
            mv "$COMPOSE_FILE.tmp" "$COMPOSE_FILE"
        else
            # Add log volume to existing volumes section
            awk '
                /^[[:space:]]*volumes:/ {
                    print $0
                    # Detect indentation of the volumes line
                    match($0, /^[[:space:]]*/)
                    base_indent = substr($0, RSTART, RLENGTH)
                    # Detect if using tabs or spaces for items
                    getline next_line
                    if (match(next_line, /^[[:space:]]*-/)) {
                        match(next_line, /^[[:space:]]*/)
                        item_indent = substr(next_line, RSTART, RLENGTH)
                        print item_indent "- /var/log/remnanode:/var/log/remnanode"
                        print next_line
                    } else {
                        print base_indent "  - /var/log/remnanode:/var/log/remnanode"
                        print next_line
                    }
                    next
                }
                { print }
            ' "$COMPOSE_FILE.tmp" > "$COMPOSE_FILE"
            rm "$COMPOSE_FILE.tmp"
            colorized_echo green "✅ Volume для логов добавлен в существующую секцию volumes"
        fi
    else
        # No volumes section - add it
        # Detect service indentation
        service_indent=$(grep -m1 "^[[:space:]]*container_name:" "$COMPOSE_FILE.tmp" | sed 's/container_name:.*//' || echo "    ")
        
        # Add volumes section before the end
        awk -v indent="$service_indent" '
            # Track if we are inside remnanode service
            /services:/ { in_services=1 }
            /remnanode:/ && in_services { in_remnanode=1 }
            
            # If we find next service or end of file, add volumes before it
            /^[[:space:]]*[a-zA-Z_-]+:/ && in_remnanode && !/remnanode:/ {
                print indent "volumes:"
                print indent "  - /var/log/remnanode:/var/log/remnanode"
                in_remnanode=0
            }
            
            { print }
            
            # Add at end if still in remnanode service
            END {
                if (in_remnanode) {
                    print indent "volumes:"
                    print indent "  - /var/log/remnanode:/var/log/remnanode"
                }
            }
        ' "$COMPOSE_FILE.tmp" > "$COMPOSE_FILE"
        rm "$COMPOSE_FILE.tmp"
        colorized_echo green "✅ Секция volumes с логами успешно добавлена"
    fi

    colorized_echo green "Файл Docker Compose сохранён в $COMPOSE_FILE"
    
    # Show the final compose file
    echo
    echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;36m📄 Итоговый docker-compose.yml:\033[0m"
    echo -e "\033[38;5;8m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo
    cat "$COMPOSE_FILE"
    echo
    echo -e "\033[38;5;8m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

    # Ask about installing Xray-core
    echo
    read -p "Установить последнюю версию Xray-core? (y/n): " -r install_xray
    INSTALL_XRAY=false
    if [[ "$install_xray" =~ ^[Yy]$ ]]; then
        INSTALL_XRAY=true
        install_latest_xray_core
    fi

    # Ask about installing tBlocker
    echo
    echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;36m🛡️  Установка tBlocker\033[0m"
    echo -e "\033[38;5;8m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo
    echo -e "\033[38;5;250mtBlocker - система блокировки торрент-трафика через iptables\033[0m"
    echo -e "\033[38;5;250mОбнаруживает и блокирует торрент-подключения пользователей\033[0m"
    echo
    read -p "Установить tBlocker? (y/n): " -r install_tb
    INSTALL_TB=false
    if [[ "$install_tb" =~ ^[Yy]$ ]]; then
        INSTALL_TB=true
    fi

    # Optionally install tBlocker right away
    if [ "$INSTALL_TB" == "true" ]; then
        echo
        colorized_echo blue "🛡️  Установка tBlocker по вашему запросу"
        install_tblocker_command
    fi

    echo
    echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;32m✅ Установка RemnaNode завершена!\033[0m"
    echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo
    echo -e "\033[38;5;250mДиректория: \033[1;37m$APP_DIR\033[0m"
    echo -e "\033[38;5;250mЛоги: \033[1;37m/var/log/remnanode\033[0m"
    echo -e "\033[38;5;250mDocker Compose: \033[1;37m$COMPOSE_FILE\033[0m"
    echo
    echo -e "\033[1;37mДля запуска используйте команду:\033[0m"
    echo -e "\033[1;36m  remnanode up\033[0m"
    echo
}

uninstall_remnanode_script() {
    if [ -f "/usr/local/bin/$APP_NAME" ]; then
        colorized_echo yellow "Removing remnanode script"
        rm "/usr/local/bin/$APP_NAME"
    fi
}

uninstall_remnanode() {
    if [ -d "$APP_DIR" ]; then
        colorized_echo yellow "Removing directory: $APP_DIR"
        rm -r "$APP_DIR"
    fi
}

uninstall_remnanode_docker_images() {
    images=$(docker images | grep remnawave/node | awk '{print $3}')
    if [ -n "$images" ]; then
        colorized_echo yellow "Removing Docker images of remnanode"
        for image in $images; do
            if docker rmi "$image" >/dev/null 2>&1; then
                colorized_echo yellow "Image $image removed"
            fi
        done
    fi
}

uninstall_remnanode_data_files() {
    if [ -d "$DATA_DIR" ]; then
        colorized_echo yellow "Removing directory: $DATA_DIR"
        rm -r "$DATA_DIR"
    fi
}

up_remnanode() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" up -d --remove-orphans
}

down_remnanode() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" down
}

show_remnanode_logs() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" logs
}

follow_remnanode_logs() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" logs -f
}

update_remnanode_script() {
    colorized_echo blue "Обновление скрипта remnanode"
    curl -sSL $SCRIPT_URL | install -m 755 /dev/stdin /usr/local/bin/$APP_NAME
    colorized_echo green "Скрипт Remnanode успешно обновлен"
}

update_remnanode() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" pull
}

is_remnanode_installed() {
    if [ -d "$APP_DIR" ]; then
        return 0
    else
        return 1
    fi
}

is_remnanode_up() {
    if ! is_remnanode_installed; then
        return 1
    fi
    
    detect_compose
    if [ -z "$($COMPOSE -f $COMPOSE_FILE ps -q -a)" ]; then
        return 1
    else
        return 0
    fi
}

install_command() {
    check_running_as_root
    if is_remnanode_installed; then
        colorized_echo red "RemnaNode уже установлен в $APP_DIR"
        read -p "Перезаписать предыдущую установку? (y/n) "
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            colorized_echo red "Установка отменена"
            exit 1
        fi
    fi
    detect_os
    if ! command -v curl >/dev/null 2>&1; then
        install_package curl
    fi
    if ! command -v docker >/dev/null 2>&1; then
        install_docker
    fi

    detect_compose
    install_remnanode_script
    install_remnanode
    up_remnanode
    
    # Extract NODE_PORT from docker-compose.yml
    NODE_PORT=$(grep -i "NODE_PORT=" "$COMPOSE_FILE" | sed 's/.*NODE_PORT=//' | sed 's/"//g' | head -1)
    if [ -z "$NODE_PORT" ]; then
        NODE_PORT="не указан в конфигурации"
    fi
    
    follow_remnanode_logs

    # final message
    clear
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
    echo -e "\033[1;37m🎉 RemnaNode успешно установлен!\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
    echo
    
    echo -e "\033[1;37m🌐 Информация о подключении:\033[0m"
    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "IP адрес:" "$NODE_IP"
    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Порт:" "$NODE_PORT"
    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s:%s\033[0m\n" "Полный URL:" "$NODE_IP" "$NODE_PORT"
    echo
    
    echo -e "\033[1;37m📋 Следующие шаги:\033[0m"
    echo -e "   \033[38;5;250m1.\033[0m Используйте IP и порт выше для настройки Remnawave Panel"
    echo -e "   \033[38;5;250m2.\033[0m Настройте ротацию логов: \033[38;5;15msudo $APP_NAME setup-logs\033[0m"
    
    if [ "$INSTALL_XRAY" == "true" ]; then
        echo -e "   \033[38;5;250m3.\033[0m \033[1;37mXray-core уже установлен и готов! ✅\033[0m"
    else
        echo -e "   \033[38;5;250m3.\033[0m Установите Xray-core: \033[38;5;15msudo $APP_NAME core-update\033[0m"
    fi
    
    if [ "$INSTALL_TB" == "true" ]; then
        echo -e "   \033[38;5;250m4.\033[0m \033[1;37mtBlocker установлен и готов к работе! ✅\033[0m"
    fi
    
    echo -e "   \033[38;5;250m5.\033[0m Настройте UFW: \033[38;5;15msudo ufw allow from \033[38;5;244mPANEL_IP\033[38;5;15m to any port $NODE_PORT\033[0m"
    echo -e "      \033[38;5;8m(Включить UFW: \033[38;5;15msudo ufw enable\033[38;5;8m)\033[0m"
    echo
    
    echo -e "\033[1;37m🛠️  Быстрые команды:\033[0m"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "status" "📊 Проверить статус сервиса"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "logs" "📋 Просмотреть логи контейнера"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "restart" "🔄 Перезапустить сервис"
    if [ "$INSTALL_XRAY" == "true" ]; then
        printf "   \033[38;5;15m%-15s\033[0m %s\n" "xray_log_out" "📤 Просмотреть логи Xray"
    fi
    echo
    
    echo -e "\033[1;37m📁 Расположение файлов:\033[0m"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Конфигурация:" "$APP_DIR"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Данные:" "$DATA_DIR"
    if [ "$INSTALL_XRAY" == "true" ]; then
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Бинарник Xray:" "$XRAY_FILE"
    fi
    echo
    
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
    echo -e "\033[38;5;8m💡 Для всех команд: \033[38;5;15msudo $APP_NAME\033[0m"
    echo -e "\033[38;5;8m📚 Проект: \033[38;5;250mhttps://gig.ovh\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
}

uninstall_command() {
    check_running_as_root
    if ! is_remnanode_installed; then
        colorized_echo red "RemnaNode не установлен!"
        exit 1
    fi
    
    read -p "Do you really want to uninstall Remnanode? (y/n) "
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        colorized_echo red "Aborted"
        exit 1
    fi
    
    detect_compose
    if is_remnanode_up; then
        down_remnanode
    fi
    
    # Удаляем контейнеры RemnaNode
    colorized_echo yellow "Удаление контейнеров RemnaNode..."
    if docker ps -aq --filter "name=remnanode" | grep -q .; then
        docker rm -f remnanode 2>/dev/null || true
        colorized_echo green "✅ Контейнеры RemnaNode удалены"
    fi
    
    uninstall_remnanode_script
    uninstall_remnanode
    uninstall_remnanode_docker_images
    
    read -p "Do you want to remove Remnanode data files too ($DATA_DIR)? (y/n) "
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        colorized_echo green "Remnanode успешно удален"
    else
        uninstall_remnanode_data_files
        colorized_echo green "Remnanode успешно удален"
    fi
}

install_script_command() {
    check_running_as_root
    colorized_echo blue "Установка скрипта RemnaNode глобально"
    install_remnanode_script
    colorized_echo green "✅ Скрипт успешно установлен!"
    colorized_echo white "Теперь вы можете запускать '$APP_NAME' из любого места"
}

uninstall_script_command() {
    check_running_as_root
    if [ ! -f "/usr/local/bin/$APP_NAME" ]; then
        colorized_echo red "❌ Скрипт не найден в /usr/local/bin/$APP_NAME"
        exit 1
    fi
    
    read -p "Вы уверены, что хотите удалить скрипт? (y/n): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        colorized_echo yellow "Операция отменена"
        exit 0
    fi
    
    colorized_echo blue "Удаление скрипта RemnaNode"
    uninstall_remnanode_script
    colorized_echo green "✅ Скрипт успешно удален!"
}

up_command() {
    help() {
        colorized_echo red "Использование: remnanode up [опции]"
        echo "OPTIONS:"
        echo "  -h, --help        display this help message"
        echo "  -n, --no-logs     do not follow logs after starting"
    }
    
    local no_logs=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-logs) no_logs=true ;;
            -h|--help) help; exit 0 ;;
            *) echo "Error: Invalid option: $1" >&2; help; exit 0 ;;
        esac
        shift
    done
    
    if ! is_remnanode_installed; then
        colorized_echo red "RemnaNode не установлен!"
        exit 1
    fi
    
    detect_compose
    
    if is_remnanode_up; then
        colorized_echo red "RemnaNode уже запущен"
        exit 1
    fi
    
    up_remnanode
    if [ "$no_logs" = false ]; then
        follow_remnanode_logs
    fi
}

down_command() {
    if ! is_remnanode_installed; then
        colorized_echo red "RemnaNode не установлен!"
        exit 1
    fi
    
    detect_compose
    
    if ! is_remnanode_up; then
        colorized_echo red "RemnaNode уже остановлен"
        exit 1
    fi
    
    down_remnanode
}

restart_command() {
    help() {
        colorized_echo red "Использование: remnanode restart [опции]"
        echo "OPTIONS:"
        echo "  -h, --help        display this help message"
        echo "  -n, --no-logs     do not follow logs after starting"
    }
    
    local no_logs=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-logs) no_logs=true ;;
            -h|--help) help; exit 0 ;;
            *) echo "Error: Invalid option: $1" >&2; help; exit 0 ;;
        esac
        shift
    done
    
    if ! is_remnanode_installed; then
        colorized_echo red "RemnaNode не установлен!"
        exit 1
    fi
    
    detect_compose
    
    down_remnanode
    up_remnanode
    
    # Добавляем поддержку флага --no-logs
    if [ "$no_logs" = false ]; then
        follow_remnanode_logs
    fi
}

status_command() {
    echo -e "\033[1;37m📊 Проверка статуса RemnaNode:\033[0m"
    echo
    
    if ! is_remnanode_installed; then
        printf "   \033[38;5;15m%-12s\033[0m \033[1;31m❌ Не установлен\033[0m\n" "Статус:"
        echo -e "\033[38;5;8m   Выполните '\033[38;5;15msudo $APP_NAME install\033[38;5;8m' для установки\033[0m"
        exit 1
    fi
    
    detect_compose
    
    if ! is_remnanode_up; then
        printf "   \033[38;5;15m%-12s\033[0m \033[1;33m⏹️  Остановлен\033[0m\n" "Статус:"
        echo -e "\033[38;5;8m   Запустите '\033[38;5;15msudo $APP_NAME up\033[38;5;8m' для старта\033[0m"
        exit 1
    fi
    
    printf "   \033[38;5;15m%-12s\033[0m \033[1;32m✅ Запущен\033[0m\n" "Статус:"
    
    # Дополнительная информация
    if [ -f "$ENV_FILE" ]; then
        local app_port=$(grep "APP_PORT=" "$ENV_FILE" | cut -d'=' -f2 2>/dev/null)
        if [ -n "$app_port" ]; then
            printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Порт:" "$app_port"
        fi
    fi
    
    # Проверяем Xray
    local xray_version=$(get_current_xray_core_version)
    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Xray Core:" "$xray_version"
    
    echo
}

logs_command() {
    help() {
        colorized_echo red "Использование: remnanode logs [опции]"
        echo "OPTIONS:"
        echo "  -h, --help        display this help message"
        echo "  -n, --no-follow   do not show follow logs"
    }
    
    local no_follow=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-follow) no_follow=true ;;
            -h|--help) help; exit 0 ;;
            *) echo "Error: Invalid option: $1" >&2; help; exit 0 ;;
        esac
        shift
    done
    
    if ! is_remnanode_installed; then
        colorized_echo red "RemnaNode не установлен!"
        exit 1
    fi
    
    detect_compose
    
    if ! is_remnanode_up; then
        colorized_echo red "RemnaNode не запущен."
        exit 1
    fi
    
    if [ "$no_follow" = true ]; then
        show_remnanode_logs
    else
        follow_remnanode_logs
    fi
}

# update_command() {
#     check_running_as_root
#     if ! is_remnanode_installed; then
#         echo -e "\033[1;31m❌ RemnaNode not installed!\033[0m"
#         echo -e "\033[38;5;8m   Run '\033[38;5;15msudo $APP_NAME install\033[38;5;8m' first\033[0m"
#         exit 1
#     fi
    
#     detect_compose
    
#     echo -e "\033[1;37m🔄 Starting RemnaNode Update...\033[0m"
#     echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
#     echo -e "\033[38;5;250m📝 Step 1:\033[0m Updating script..."
#     update_remnanode_script
#     echo -e "\033[1;32m✅ Script updated\033[0m"
    
#     echo -e "\033[38;5;250m📝 Step 2:\033[0m Pulling latest version..."
#     update_remnanode
#     echo -e "\033[1;32m✅ Image updated\033[0m"
    
#     echo -e "\033[38;5;250m📝 Step 3:\033[0m Restarting services..."
#     down_remnanode
#     up_remnanode
#     echo -e "\033[1;32m✅ Services restarted\033[0m"
    
#     echo
#     echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
#     echo -e "\033[1;37m🎉 RemnaNode updated successfully!\033[0m"
#     echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
# }



update_command() {
    check_running_as_root
    if ! is_remnanode_installed; then
    echo -e "\033[1;31m❌ RemnaNode не установлен!\033[0m"
    echo -e "\033[38;5;8m   Сначала выполните '\033[38;5;15msudo $APP_NAME install\033[38;5;8m'\033[0m"
        exit 1
    fi
    
    detect_compose
    
    echo -e "\033[1;37m🔄 Проверка обновлений RemnaNode...\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    # Определяем используемый тег из docker-compose.yml
    local current_tag="latest"
    if [ -f "$COMPOSE_FILE" ]; then
        current_tag=$(grep -E "image:.*remnawave/node:" "$COMPOSE_FILE" | sed 's/.*remnawave\/node://' | tr -d '"' | tr -d "'" | xargs)
        if [ -z "$current_tag" ]; then
            current_tag="latest"
        fi
    fi
    
    echo -e "\033[38;5;250m🏷️  Текущий тег:\033[0m \033[38;5;15m$current_tag\033[0m"
    
    # Получаем локальную версию образа
    echo -e "\033[38;5;250m📝 Шаг 1:\033[0m Проверка локальной версии образа..."
    local local_image_id=""
    local local_created=""
    
    if docker images remnawave/node:$current_tag --format "table {{.ID}}\t{{.CreatedAt}}" | grep -v "IMAGE ID" > /dev/null 2>&1; then
        local_image_id=$(docker images remnawave/node:$current_tag --format "{{.ID}}" | head -1)
        local_created=$(docker images remnawave/node:$current_tag --format "{{.CreatedAt}}" | head -1 | cut -d' ' -f1,2)
        
        echo -e "\033[1;32m✅ Локальный образ найден\033[0m"
        echo -e "\033[38;5;8m   ID образа: $local_image_id\033[0m"
        echo -e "\033[38;5;8m   Создан: $local_created\033[0m"
    else
        echo -e "\033[1;33m⚠️  Локальный образ не найден\033[0m"
        local_image_id="none"
    fi
    
    # Проверяем обновления через docker pull
    echo -e "\033[38;5;250m📝 Шаг 2:\033[0m Проверка обновлений с помощью docker pull..."
    
    # Сохраняем текущий образ ID для сравнения
    local old_image_id="$local_image_id"
    
    # Запускаем docker pull
    if $COMPOSE -f $COMPOSE_FILE pull --quiet 2>/dev/null; then
        # Проверяем, изменился ли ID образа после pull
        local new_image_id=$(docker images remnawave/node:$current_tag --format "{{.ID}}" | head -1)
        
        local needs_update=false
        local update_reason=""
        
        if [ "$old_image_id" = "none" ]; then
            needs_update=true
            update_reason="Local image not found, downloaded new version"
            echo -e "\033[1;33m🔄 New image downloaded\033[0m"
        elif [ "$old_image_id" != "$new_image_id" ]; then
            needs_update=true
            update_reason="New version downloaded via docker pull"
            echo -e "\033[1;33m🔄 New version detected and downloaded\033[0m"
        else
            needs_update=false
            update_reason="Already up to date (verified via docker pull)"
            echo -e "\033[1;32m✅ Already up to date\033[0m"
        fi
    else
        echo -e "\033[1;33m⚠️  Docker pull не удался, предполагаем что обновление необходимо\033[0m"
        local needs_update=true
        local update_reason="Unable to verify current version"
        local new_image_id="$old_image_id"
    fi
    
    echo
    echo -e "\033[1;37m📊 Анализ обновления:\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    
    if [ "$needs_update" = true ]; then
        echo -e "\033[1;33m🔄 Доступно обновление\033[0m"
        echo -e "\033[38;5;250m   Причина: \033[38;5;15m$update_reason\033[0m"
        echo
        
        # Если новая версия уже загружена, автоматически продолжаем
        if [[ "$update_reason" == *"downloaded"* ]]; then
            echo -e "\033[1;37m🚀 Новая версия уже загружена, продолжаю обновление...\033[0m"
        else
            read -p "Продолжить обновление? (y/n): " -r confirm_update
            if [[ ! $confirm_update =~ ^[Yy]$ ]]; then
                echo -e "\033[1;31m❌ Обновление отменено пользователем\033[0m"
                exit 0
            fi
        fi
        
        echo
        echo -e "\033[1;37m🚀 Выполнение обновления...\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
        
        # Обновляем скрипт
        echo -e "\033[38;5;250m📝 Шаг 3:\033[0m Обновление скрипта..."
        if update_remnanode_script; then
            echo -e "\033[1;32m✅ Скрипт обновлен\033[0m"
        else
            echo -e "\033[1;33m⚠️  Не удалось обновить скрипт, продолжаем...\033[0m"
        fi
        
        # Проверяем, запущен ли контейнер
        local was_running=false
        if is_remnanode_up; then
            was_running=true
            echo -e "\033[38;5;250m📝 Шаг 4:\033[0m Остановка запущенного контейнера..."
            if down_remnanode; then
                echo -e "\033[1;32m✅ Контейнер остановлен\033[0m"
            else
                echo -e "\033[1;31m❌ Не удалось остановить контейнер\033[0m"
                exit 1
            fi
        else
            echo -e "\033[38;5;250m📝 Шаг 4:\033[0m Контейнер не запущен, пропускаем остановку..."
        fi
        
        # Загружаем образ только если еще не загружен
        if [[ "$update_reason" != *"downloaded"* ]]; then
            echo -e "\033[38;5;250m📝 Шаг 5:\033[0m Загрузка последнего образа..."
            if update_remnanode; then
                echo -e "\033[1;32m✅ Образ обновлен\033[0m"
                # Обновляем ID образа
                new_image_id=$(docker images remnawave/node:$current_tag --format "{{.ID}}" | head -1)
            else
                echo -e "\033[1;31m❌ Не удалось загрузить образ\033[0m"
                
                # Если контейнер был запущен, пытаемся его восстановить
                if [ "$was_running" = true ]; then
                    echo -e "\033[38;5;250m🔄 Попытка восстановить сервис...\033[0m"
                    up_remnanode
                fi
                exit 1
            fi
        else
            echo -e "\033[38;5;250m📝 Шаг 5:\033[0m Образ уже обновлён во время проверки\033[0m"
        fi
        
        # Запускаем контейнер только если он был запущен ранее
        if [ "$was_running" = true ]; then
            echo -e "\033[38;5;250m📝 Шаг 6:\033[0m Запуск обновленного контейнера..."
            if up_remnanode; then
                echo -e "\033[1;32m✅ Контейнер запущен\033[0m"
            else
                echo -e "\033[1;31m❌ Не удалось запустить контейнер\033[0m"
                exit 1
            fi
        else
            echo -e "\033[38;5;250m📝 Шаг 6:\033[0m Контейнер не был запущен, оставляем остановленным..."
        fi
        
        # Показываем финальную информацию
        echo
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        echo -e "\033[1;37m🎉 RemnaNode успешно обновлен!\033[0m"
        
        # Получаем новую информацию об образе
        local final_created=$(docker images remnawave/node:$current_tag --format "{{.CreatedAt}}" | head -1 | cut -d' ' -f1,2)
        
        echo -e "\033[1;37m📋 Сводка обновления:\033[0m"
        echo -e "\033[38;5;250m   Предыдущий: \033[38;5;8m$old_image_id\033[0m"
        echo -e "\033[38;5;250m   Текущий:  \033[38;5;15m$new_image_id\033[0m"
        echo -e "\033[38;5;250m   Создан:  \033[38;5;15m$final_created\033[0m"
        
        if [ "$was_running" = true ]; then
            echo -e "\033[38;5;250m   Статус:   \033[1;32mЗапущен\033[0m"
        else
            echo -e "\033[38;5;250m   Статус:   \033[1;33mОстановлен\033[0m"
            echo -e "\033[38;5;8m   Use '\033[38;5;15msudo $APP_NAME up\033[38;5;8m' to start\033[0m"
        fi
        
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        
    else
        echo -e "\033[1;32m✅ Уже актуально\033[0m"
        echo -e "\033[38;5;250m   Причина: \033[38;5;15m$update_reason\033[0m"
        echo
        
        # Проверяем все равно скрипт
        echo -e "\033[38;5;250m📝 Проверка обновлений скрипта...\033[0m"
        
        # Получаем текущую версию скрипта
        local current_script_version="$SCRIPT_VERSION"
        
        # Получаем последнюю версию скрипта с GitHub
        local remote_script_version=$(curl -s "$SCRIPT_URL" 2>/dev/null | grep "^SCRIPT_VERSION=" | cut -d'"' -f2)
        
        if [ -n "$remote_script_version" ] && [ "$remote_script_version" != "$current_script_version" ]; then
            echo -e "\033[1;33m🔄 Доступно обновление скрипта: \033[38;5;15mv$current_script_version\033[0m → \033[1;37mv$remote_script_version\033[0m"
            read -p "Хотите обновить скрипт? (y/n): " -r update_script
            if [[ $update_script =~ ^[Yy]$ ]]; then
                if update_remnanode_script; then
                    echo -e "\033[1;32m✅ Скрипт обновлен до v$remote_script_version\033[0m"
                    echo -e "\033[38;5;8m   Пожалуйста, запустите команду снова для использования новой версии\033[0m"
                else
                    echo -e "\033[1;33m⚠️  Обновление скрипта не удалось\033[0m"
                fi
            else
                echo -e "\033[38;5;8m   Обновление скрипта пропущено\033[0m"
            fi
        else
            echo -e "\033[1;32m✅ Скрипт актуален\033[0m"
        fi
        
        echo
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
        echo -e "\033[1;37m📊 Текущий статус:\033[0m"
        
        if is_remnanode_up; then
            echo -e "\033[38;5;250m   Контейнер: \033[1;32mЗапущен ✅\033[0m"
        else
            echo -e "\033[38;5;250m   Контейнер: \033[1;33mОстановлен ⏹️\033[0m"
            echo -e "\033[38;5;8m   Используйте '\033[38;5;15msudo $APP_NAME up\033[38;5;8m' для запуска\033[0m"
        fi
        
        echo -e "\033[38;5;250m   Тег образа: \033[38;5;15m$current_tag\033[0m"
        echo -e "\033[38;5;250m   ID образа:  \033[38;5;15m$local_image_id\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    fi
}

identify_the_operating_system_and_architecture() {
    if [[ "$(uname)" == 'Linux' ]]; then
        case "$(uname -m)" in
            'i386' | 'i686') ARCH='32' ;;
            'amd64' | 'x86_64') ARCH='64' ;;
            'armv5tel') ARCH='arm32-v5' ;;
            'armv6l') ARCH='arm32-v6'; grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5' ;;
            'armv7' | 'armv7l') ARCH='arm32-v7a'; grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5' ;;
            'armv8' | 'aarch64') ARCH='arm64-v8a' ;;
            'mips') ARCH='mips32' ;;
            'mipsle') ARCH='mips32le' ;;
            'mips64') ARCH='mips64'; lscpu | grep -q "Little Endian" && ARCH='mips64le' ;;
            'mips64le') ARCH='mips64le' ;;
            'ppc64') ARCH='ppc64' ;;
            'ppc64le') ARCH='ppc64le' ;;
            'riscv64') ARCH='riscv64' ;;
            's390x') ARCH='s390x' ;;
            *) echo "error: The architecture is not supported."; exit 1 ;;
        esac
    else
        echo "error: This operating system is not supported."
        exit 1
    fi
}

get_xray_host_path_from_compose() {
    # Извлекаем путь хоста, который смонтирован в /usr/local/bin/xray
    if [ -f "$COMPOSE_FILE" ]; then
        awk '
            /^[[:space:]]*-[[:space:]]*/ && /:\/usr\/local\/bin\/xray/ {
                line=$0
                sub(/^[[:space:]]*-[[:space:]]*/,"",line)
                idx=index(line,":/usr/local/bin/xray")
                if (idx>0) {
                    host=substr(line,1,idx-1)
                    # Снимаем возможные кавычки вокруг пути
                    gsub(/^"|"$/,"",host)
                    gsub(/^'"'"'|'"'"'$/ ,"",host)
                    print host
                    exit
                }
            }
        ' "$COMPOSE_FILE"
    fi
}

get_current_xray_core_version() {
    # 1) Пробуем путь из docker-compose (если есть)
    local host_path
    host_path=$(get_xray_host_path_from_compose 2>/dev/null)
    if [ -n "$host_path" ] && [ -f "$host_path" ]; then
        local version_output version
        version_output=$("$host_path" -version 2>/dev/null)
        if [ $? -eq 0 ]; then
            version=$(echo "$version_output" | head -n1 | awk '{print $2}')
            [ -n "$version" ] && { echo "$version"; return; }
        fi
    fi

    # 2) Пробуем стандартный путь XRAY_FILE
    if [ -f "$XRAY_FILE" ]; then
        local version_output version
        version_output=$("$XRAY_FILE" -version 2>/dev/null)
        if [ $? -eq 0 ]; then
            version=$(echo "$version_output" | head -n1 | awk '{print $2}')
            [ -n "$version" ] && { echo "$version"; return; }
        fi
    fi

    # 3) Если контейнер запущен — смотрим бинарь внутри контейнера
    if is_remnanode_up; then
        local version_output version
        version_output=$(docker exec "$APP_NAME" /usr/local/bin/xray -version 2>/dev/null | head -n1)
        version=$(echo "$version_output" | awk '{print $2}')
        [ -n "$version" ] && { echo "$version"; return; }
    fi

    echo "Not installed"
}

get_xray_core() {
    identify_the_operating_system_and_architecture
    clear
    
    validate_version() {
        local version="$1"
        local response=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/tags/$version")
        if echo "$response" | grep -q '"message": "Not Found"'; then
            echo "invalid"
        else
            echo "valid"
        fi
    }
    
    print_menu() {
        clear
        
        # Заголовок в монохромном стиле
        echo -e "\033[1;37m⚡ Xray-core Installer\033[0m \033[38;5;8mVersion Manager\033[0m \033[38;5;244mv$SCRIPT_VERSION\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
        echo
        
        # Текущая версия
        current_version=$(get_current_xray_core_version)
        echo -e "\033[1;37m🌐 Current Status:\033[0m"
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Xray Version:" "$current_version"
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Architecture:" "$ARCH"
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Install Path:" "$XRAY_FILE"
        echo
        
        # Показываем режим выбора релизов
        echo -e "\033[1;37m🎯 Release Mode:\033[0m"
        if [ "$show_prereleases" = true ]; then
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m \033[38;5;244m(Including Pre-releases)\033[0m\n" "Current:" "All Releases"
        else
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m \033[1;37m(Stable Only)\033[0m\n" "Current:" "Stable Releases"
        fi
        echo
        
        # Доступные версии с метками
        echo -e "\033[1;37m🚀 Available Versions:\033[0m"
        for ((i=0; i<${#versions[@]}; i++)); do
            local version_num=$((i + 1))
            local version_name="${versions[i]}"
            local is_prerelease="${prereleases[i]}"
            
            # Определяем тип релиза и используем echo вместо printf
            if [ "$is_prerelease" = "true" ]; then
                echo -e "   \033[38;5;15m${version_num}:\033[0m \033[38;5;250m${version_name}\033[0m \033[38;5;244m(Pre-release)\033[0m"
            elif [ $i -eq 0 ] && [ "$is_prerelease" = "false" ]; then
                echo -e "   \033[38;5;15m${version_num}:\033[0m \033[38;5;250m${version_name}\033[0m \033[1;37m(Latest Stable)\033[0m"
            else
                echo -e "   \033[38;5;15m${version_num}:\033[0m \033[38;5;250m${version_name}\033[0m \033[38;5;8m(Stable)\033[0m"
            fi
        done
        echo
        
        # Опции
        echo -e "\033[1;37m🔧 Опции:\033[0m"
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "M:" "📝 Ввести версию вручную"
        if [ "$show_prereleases" = true ]; then
            printf "   \033[38;5;15m%-3s\033[0m %s\n" "S:" "🔒 Показать только стабильные релизы"
        else
            printf "   \033[38;5;15m%-3s\033[0m %s\n" "A:" "🧪 Показать все релизы (включая пре-релизы)"
        fi
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "R:" "🔄 Обновить список версий"
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "D:" "🏠 Восстановить стандартный Xray контейнера"
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "Q:" "❌ Выйти из установщика"
        echo
        
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
        echo -e "\033[1;37m📖 Использование:\033[0m"
        echo -e "   Выберите номер \033[38;5;15m(1-${#versions[@]})\033[0m, \033[38;5;15mM\033[0m для ручного ввода, \033[38;5;15mA/S\033[0m для переключения релизов, \033[38;5;15mD\033[0m для восстановления по умолчанию, или \033[38;5;15mQ\033[0m для выхода"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
    }
    
    fetch_versions() {
        local include_prereleases="$1"
        echo -e "\033[1;37m🔍 Fetching Xray-core versions...\033[0m"
        
        if [ "$include_prereleases" = true ]; then
            echo -e "\033[38;5;8m   Including pre-releases...\033[0m"
            latest_releases=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=8")
        else
            echo -e "\033[38;5;8m   Stable releases only...\033[0m"
            latest_releases=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=15")
        fi
        
        if [ -z "$latest_releases" ] || echo "$latest_releases" | grep -q '"message":'; then
            echo -e "\033[1;31m❌ Failed to fetch versions. Please check your internet connection.\033[0m"
            return 1
        fi
        
        # Парсим JSON и извлекаем нужную информацию
        versions=()
        prereleases=()
        
        # Извлекаем данные с помощью более надежного парсинга
        local temp_file=$(mktemp)
        echo "$latest_releases" | grep -E '"(tag_name|prerelease)"' > "$temp_file"
        
        local current_version=""
        local count=0
        local max_count=6
        
        while IFS= read -r line; do
            if [[ "$line" =~ \"tag_name\":[[:space:]]*\"([^\"]+)\" ]]; then
                current_version="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ \"prerelease\":[[:space:]]*(true|false) ]]; then
                local is_prerelease="${BASH_REMATCH[1]}"
                
                # Если не показываем pre-releases, пропускаем их
                if [ "$include_prereleases" = false ] && [ "$is_prerelease" = "true" ]; then
                    current_version=""
                    continue
                fi
                
                # Добавляем версию в массивы
                if [ -n "$current_version" ] && [ $count -lt $max_count ]; then
                    versions+=("$current_version")
                    prereleases+=("$is_prerelease")
                    ((count++))
                fi
                current_version=""
            fi
        done < "$temp_file"
        
        rm "$temp_file"
        
        if [ ${#versions[@]} -eq 0 ]; then
            echo -e "\033[1;31m❌ No versions found.\033[0m"
            return 1
        fi
        
        echo -e "\033[1;32m✅ Found ${#versions[@]} versions\033[0m"
        return 0
    }
    
    # Инициализация
    local show_prereleases=false
    
    # Первоначальная загрузка версий
    if ! fetch_versions "$show_prereleases"; then
        exit 1
    fi
    
    while true; do
        print_menu
        echo -n -e "\033[1;37m> \033[0m"
        read choice
        
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#versions[@]}" ]; then
            choice=$((choice - 1))
            selected_version=${versions[choice]}
            local selected_prerelease=${prereleases[choice]}
            
            echo
            if [ "$selected_prerelease" = "true" ]; then
            echo -e "\033[1;33m⚠️  Выбрана пре-релизная версия: \033[1;37m$selected_version\033[0m"
            echo -е "\033[38;5;8m   Пре-релизы могут содержать ошибки и не рекомендуются для продакшена.\033[0m"
            read -p "Вы уверены, что хотите продолжить? (y/n): " -r confirm_prerelease
                if [[ ! $confirm_prerelease =~ ^[Yy]$ ]]; then
                echo -e "\033[1;31m❌ Установка отменена.\033[0m"
                    continue
                fi
            else
                echo -e "\033[1;32m✅ Выбрана стабильная версия: \033[1;37m$selected_version\033[0m"
            fi
            break
            
        elif [ "$choice" == "M" ] || [ "$choice" == "m" ]; then
            echo
            echo -e "\033[1;37m📝 Ручной ввод версии:\033[0m"
            while true; do
                echo -n -е "\033[38;5;8mВведите версию (например, v1.8.4): \033[0m"
                read custom_version
                
                if [ -z "$custom_version" ]; then
                    echo -e "\033[1;31m❌ Версия не может быть пустой. Попробуйте снова.\033[0m"
                    continue
                fi
                
                echo -e "\033[1;37m🔍 Проверка версии $custom_version...\033[0m"
                if [ "$(validate_version "$custom_version")" == "valid" ]; then
                    selected_version="$custom_version"
                    echo -e "\033[1;32m✅ Версия $custom_version корректна!\033[0m"
                    break 2
                else
                    echo -e "\033[1;31m❌ Версия $custom_version не найдена. Попробуйте снова.\033[0m"
                    echo -e "\033[38;5;8m   Подсказка: проверьте https://github.com/XTLS/Xray-core/releases\033[0m"
                    echo
                fi
            done
            
        elif [ "$choice" == "A" ] || [ "$choice" == "a" ]; then
            if [ "$show_prereleases" = false ]; then
                show_prereleases=true
                if ! fetch_versions "$show_prereleases"; then
                    show_prereleases=false
                    continue
                fi
            fi
            
        elif [ "$choice" == "S" ] || [ "$choice" == "s" ]; then
            if [ "$show_prereleases" = true ]; then
                show_prereleases=false
                if ! fetch_versions "$show_prereleases"; then
                    show_prereleases=true
                    continue
                fi
            fi
            
        elif [ "$choice" == "R" ] || [ "$choice" == "r" ]; then
            if ! fetch_versions "$show_prereleases"; then
                continue
            fi
            
        elif [ "$choice" == "D" ] || [ "$choice" == "d" ]; then
            echo
            echo -e "\033[1;33m🏠 Восстановить стандартный Xray контейнера\033[0m"
            echo -e "\033[38;5;8m   Это удалит внешние монтирования Xray и вернёт встроенную версию из контейнера.\033[0m"
            echo
            read -p "Вы уверены, что хотите восстановить стандартный Xray контейнера? (y/n): " -r confirm_restore
            if [[ $confirm_restore =~ ^[Yy]$ ]]; then
                restore_to_container_default
                echo
                echo -n -e "\033[38;5;8mНажмите Enter для продолжения...\033[0m"
                read
            else
                echo -e "\033[1;31m❌ Восстановление отменено.\033[0m"
                echo
                echo -n -e "\033[38;5;8mНажмите Enter для продолжения...\033[0m"
                read
            fi
            
        elif [ "$choice" == "Q" ] || [ "$choice" == "q" ]; then
            echo
            echo -e "\033[1;31m❌ Installation cancelled by user.\033[0m"
            exit 0
            
        else
            echo
            echo -e "\033[1;31m❌ Invalid choice: '$choice'\033[0m"
            echo -e "\033[38;5;8m   Please enter a number between 1-${#versions[@]}, M for manual, A/S to toggle releases, R to refresh, D to restore default, or Q to quit.\033[0m"
            echo
            echo -n -e "\033[38;5;8mPress Enter to continue...\033[0m"
            read
        fi
    done
    
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    echo -e "\033[1;37m🚀 Запуск установки\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    
    # Проверка и установка unzip
    if ! dpkg -s unzip >/dev/null 2>&1; then
        echo -e "\033[1;37m📦 Установка необходимых пакетов...\033[0m"
        detect_os
        install_package unzip
        echo -e "\033[1;32m✅ Пакеты успешно установлены\033[0m"
    fi
    
    mkdir -p "$DATA_DIR"
    cd "$DATA_DIR"
    
    xray_filename="Xray-linux-$ARCH.zip"
    xray_download_url="https://github.com/XTLS/Xray-core/releases/download/${selected_version}/${xray_filename}"
    
    # Скачивание с прогрессом
    echo -e "\033[1;37m📥 Скачивание Xray-core $selected_version...\033[0m"
    echo -e "\033[38;5;8m   URL: $xray_download_url\033[0m"
    
    if wget "${xray_download_url}" -q --show-progress; then
        echo -e "\033[1;32m✅ Загрузка успешно завершена\033[0m"
    else
        echo -e "\033[1;31m❌ Ошибка загрузки!\033[0m"
        echo -e "\033[38;5;8m   Проверьте интернет-соединение или попробуйте другую версию.\033[0m"
        exit 1
    fi
    
    # Извлечение
    echo -e "\033[1;37m📦 Извлечение Xray-core...\033[0m"
    if unzip -o "${xray_filename}" -d "$DATA_DIR" >/dev/null 2>&1; then
        echo -e "\033[1;32m✅ Извлечение успешно завершено\033[0m"
    else
        echo -e "\033[1;31m❌ Ошибка извлечения!\033[0m"
        echo -e "\033[38;5;8m   Загруженный файл может быть повреждён.\033[0m"
        exit 1
    fi
    
    # Очистка и настройка прав
    rm "${xray_filename}"
    chmod +x "$XRAY_FILE"
    
    # Финальное сообщение
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    echo -e "\033[1;37m🎉 Установка завершена!\033[0m"
    
    # Информация об установке
    echo -е "\033[1;37m📋 Подробности установки:\033[0m"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Версия:" "$selected_version"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Архитектура:" "$ARCH"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Путь установки:" "$XRAY_FILE"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Размер файла:" "$(du -h "$XRAY_FILE" | cut -f1)"
    echo
    
    # Проверка версии
    echo -e "\033[1;37m🔍 Проверка установки...\033[0m"
    if installed_version=$("$XRAY_FILE" -version 2>/dev/null | head -n1 | awk '{print $2}'); then
        echo -e "\033[1;32m✅ Xray-core работает корректно\033[0m"
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Используемая версия:" "$installed_version"
    else
        echo -e "\033[1;31m⚠️  Установка завершена, но проверка не прошла\033[0m"
        echo -e "\033[38;5;8m   Бинарный файл может быть несовместим с вашей системой\033[0m"
    fi
}



# Функция для создания резервной копии файла
create_backup() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$file" ]; then
        cp "$file" "$backup_file"
        echo "$backup_file"
        return 0
    else
        return 1
    fi
}

# Функция для восстановления из резервной копии
restore_backup() {
    local backup_file="$1"
    local original_file="$2"
    
    if [ -f "$backup_file" ]; then
        cp "$backup_file" "$original_file"
        return 0
    else
        return 1
    fi
}

# Функция для проверки валидности docker-compose файла
validate_compose_file() {
    local compose_file="$1"
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    

    local current_dir=$(pwd)
    

    cd "$(dirname "$compose_file")"
    

    if command -v docker >/dev/null 2>&1; then

        detect_compose
        
        # Проверяем синтаксис файла
        if $COMPOSE config >/dev/null 2>&1; then
            cd "$current_dir"
            return 0
        else

            colorized_echo red "Ошибки проверки Docker Compose:"
            $COMPOSE config 2>&1 | head -10
            cd "$current_dir"
            return 1
        fi
    else

        if grep -q "services:" "$compose_file" && grep -q "remnanode:" "$compose_file"; then
            cd "$current_dir"
            return 0
        else
            cd "$current_dir"
            return 1
        fi
    fi
}

# Функция для удаления старых резервных копий (оставляем только последние 5)
cleanup_old_backups() {
    local file_pattern="$1"
    local keep_count=5
    
    # Найти все файлы резервных копий и удалить старые
    ls -t ${file_pattern}.backup.* 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -f 2>/dev/null || true
}

# Обновленная функция для определения отступов из docker-compose.yml
get_indentation_from_compose() {
    local compose_file="$1"
    local indentation=""
    
    if [ -f "$compose_file" ]; then
        # Сначала ищем строку с "remnanode:" (точное совпадение)
        local service_line=$(grep -n "remnanode:" "$compose_file" | head -1)
        if [ -n "$service_line" ]; then
            local line_content=$(echo "$service_line" | cut -d':' -f2-)
            indentation=$(echo "$line_content" | sed 's/remnanode:.*//' | grep -o '^[[:space:]]*')
        fi
        
        # Если не нашли точное совпадение, ищем любой сервис с "remna"
        if [ -z "$indentation" ]; then
            local remna_service_line=$(grep -E "^[[:space:]]*[a-zA-Z0-9_-]*remna[a-zA-Z0-9_-]*:" "$compose_file" | head -1)
            if [ -n "$remna_service_line" ]; then
                indentation=$(echo "$remna_service_line" | sed 's/[a-zA-Z0-9_-]*remna[a-zA-Z0-9_-]*:.*//' | grep -o '^[[:space:]]*')
            fi
        fi
        
        # Если не нашли сервис с "remna", пробуем найти любой сервис
        if [ -z "$indentation" ]; then
            local any_service_line=$(grep -E "^[[:space:]]*[a-zA-Z0-9_-]+:" "$compose_file" | head -1)
            if [ -n "$any_service_line" ]; then
                indentation=$(echo "$any_service_line" | sed 's/[a-zA-Z0-9_-]*:.*//' | grep -o '^[[:space:]]*')
            fi
        fi
    fi
    
    # Если ничего не нашли, используем 2 пробела по умолчанию
    if [ -z "$indentation" ]; then
        indentation="  "
    fi
    
    echo "$indentation"
}

# Обновленная функция для получения отступа для свойств сервиса
get_service_property_indentation() {
    local compose_file="$1"
    local base_indent=$(get_indentation_from_compose "$compose_file")
    local indent_type=""
    if [[ "$base_indent" =~ $'\t' ]]; then
        indent_type=$'\t'
    else
        indent_type="  "
    fi
    local property_indent=""
    if [ -f "$compose_file" ]; then
        local in_remna_service=false
        local current_service=""
        
        while IFS= read -r line; do

            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]]*$ ]]; then
                current_service=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/:[[:space:]]*$//')
                

                if [[ "$current_service" =~ remna ]]; then
                    in_remna_service=true
                else
                    in_remna_service=false
                fi
                continue
            fi
            

            if [ "$in_remna_service" = true ]; then
                local line_indent=$(echo "$line" | grep -o '^[[:space:]]*')
                

                if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]]*$ ]] && [ ${#line_indent} -le ${#base_indent} ]; then
                    break
                fi
                

                if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                    property_indent=$(echo "$line" | sed 's/[a-zA-Z0-9_-]*:.*//' | grep -o '^[[:space:]]*')
                    break
                fi
            fi
        done < "$compose_file"
    fi
    
    # Если не нашли свойство, добавляем один уровень отступа к базовому
    if [ -z "$property_indent" ]; then
        property_indent="${base_indent}${indent_type}"
    fi
    
    echo "$property_indent"
}


escape_for_sed() {
    local text="$1"
    echo "$text" | sed 's/[]\.*^$()+?{|[]/\\&/g' | sed 's/\t/\\t/g'
}


normalize_volumes_indentation() {
    local compose_file="$1"
    [ -f "$compose_file" ] || return 0

    local service_indent=$(get_service_property_indentation "$compose_file")
    local indent_type=""
    if [[ "$service_indent" =~ $'\t' ]]; then
        indent_type=$'\t'
    else
        indent_type="  "
    fi
    local item_indent="${service_indent}${indent_type}"

    # Перенормируем отступы элементов '-' внутри секции volumes сервиса remna*
    local tmp_file
    tmp_file=$(mktemp)
    awk -v base="${service_indent}" -v item="${item_indent}" '
        function indent_len(s,  n,i,c) { n=0; for(i=1;i<=length(s);i++){c=substr(s,i,1); if(c=="\t"){n+=1}else if(c==" "){n+=1}else break} return n }
        function starts_with_volumes(line,base){return (line ~ "^" base "volumes:[[:space:]]*$")}
        BEGIN{in_remna=0; in_vol=0; base_len=length(base)}
        {
            line=$0
            # Детекция заголовков сервисов
            if (match(line, /^[[:space:]]*[A-Za-z0-9_-]+:[[:space:]]*$/)) {
                name=line; sub(/^[[:space:]]*/, "", name); sub(/:[[:space:]]*$/, "", name)
                # Выход из секции volumes при встрече нового свойства/сервиса c отступом не больше base
                if (in_vol) { in_vol=0 }
                if (name ~ /remna/) { in_remna=1 } else if (indent_len(line) <= base_len) { in_remna=0 }
            }
            # Вход в volumes
            if (in_remna && starts_with_volumes(line, base)) { in_vol=1; print line; next }
            # Нормализация элементов
            if (in_vol && match(line, /^[[:space:]]*-[[:space:]]/)) {
                sub(/^[[:space:]]*-[[:space:]]*/, item "- ", line)
                print line; next
            }
            print $0
        }
    ' "$compose_file" > "$tmp_file" && mv "$tmp_file" "$compose_file"
}

update_core_command() {
    check_running_as_root
    get_xray_core
    colorized_echo blue "Updating docker-compose.yml with Xray-core volume..."
    

    if [ ! -f "$COMPOSE_FILE" ]; then
        colorized_echo red "Файл Docker Compose не найден в $COMPOSE_FILE"
        exit 1
    fi
    

    colorized_echo blue "Создание резервной копии docker-compose.yml..."
    backup_file=$(create_backup "$COMPOSE_FILE")
    if [ $? -eq 0 ]; then
        colorized_echo green "Резервная копия создана: $backup_file"
    else
        colorized_echo red "Не удалось создать резервную копию"
        exit 1
    fi
    

    local service_indent=$(get_service_property_indentation "$COMPOSE_FILE")
    

    local indent_type=""
    if [[ "$service_indent" =~ $'\t' ]]; then
        indent_type=$'\t'
    else
        indent_type="  "
    fi
    local volume_item_indent="${service_indent}${indent_type}"
    

    local escaped_service_indent=$(escape_for_sed "$service_indent")
    local escaped_volume_item_indent=$(escape_for_sed "$volume_item_indent")

    if grep -q "^${escaped_service_indent}volumes:" "$COMPOSE_FILE"; then
        # Remove existing xray-related volumes using # as delimiter to avoid issues with / in paths
        sed -i "\#$XRAY_FILE#d" "$COMPOSE_FILE"
        sed -i "\#geoip\.dat#d" "$COMPOSE_FILE"
        sed -i "\#geosite\.dat#d" "$COMPOSE_FILE"
        
        # Create temporary file with volume mounts
        temp_volumes=$(mktemp)
        echo "${volume_item_indent}- $XRAY_FILE:/usr/local/bin/xray" > "$temp_volumes"
        if [ -f "$GEOIP_FILE" ]; then
            echo "${volume_item_indent}- $GEOIP_FILE:/usr/local/share/xray/geoip.dat" >> "$temp_volumes"
        fi
        if [ -f "$GEOSITE_FILE" ]; then
            echo "${volume_item_indent}- $GEOSITE_FILE:/usr/local/share/xray/geosite.dat" >> "$temp_volumes"
        fi
        
        # Insert volumes after the volumes: line
        sed -i "/^${escaped_service_indent}volumes:/r $temp_volumes" "$COMPOSE_FILE"
        rm "$temp_volumes"
        colorized_echo green "Updated Xray volumes in existing volumes section"
        
    elif grep -q "^${escaped_service_indent}# volumes:" "$COMPOSE_FILE"; then
        sed -i "s|^${escaped_service_indent}# volumes:|${service_indent}volumes:|g" "$COMPOSE_FILE"
        
        # Create temporary file with volume mounts
        temp_volumes=$(mktemp)
        echo "${volume_item_indent}- $XRAY_FILE:/usr/local/bin/xray" > "$temp_volumes"
        if [ -f "$GEOIP_FILE" ]; then
            echo "${volume_item_indent}- $GEOIP_FILE:/usr/local/share/xray/geoip.dat" >> "$temp_volumes"
        fi
        if [ -f "$GEOSITE_FILE" ]; then
            echo "${volume_item_indent}- $GEOSITE_FILE:/usr/local/share/xray/geosite.dat" >> "$temp_volumes"
        fi
        
        # Insert volumes after the volumes: line
        sed -i "/^${escaped_service_indent}volumes:/r $temp_volumes" "$COMPOSE_FILE"
        rm "$temp_volumes"
        colorized_echo green "Uncommented volumes section and added Xray volumes"
        
    else
        # Create temporary file with volumes section
        temp_volumes=$(mktemp)
        echo "${service_indent}volumes:" > "$temp_volumes"
        echo "${volume_item_indent}- $XRAY_FILE:/usr/local/bin/xray" >> "$temp_volumes"
        if [ -f "$GEOIP_FILE" ]; then
            echo "${volume_item_indent}- $GEOIP_FILE:/usr/local/share/xray/geoip.dat" >> "$temp_volumes"
        fi
        if [ -f "$GEOSITE_FILE" ]; then
            echo "${volume_item_indent}- $GEOSITE_FILE:/usr/local/share/xray/geosite.dat" >> "$temp_volumes"
        fi
        
        # Insert volumes section after restart: always
        sed -i "/^${escaped_service_indent}restart: always/r $temp_volumes" "$COMPOSE_FILE"
        rm "$temp_volumes"
        colorized_echo green "Added new volumes section with Xray volumes"
    fi
    
    # Show what was mounted
    colorized_echo blue "Mounted volumes:"
    colorized_echo green "  ✅ xray → /usr/local/bin/xray"
    if [ -f "$GEOIP_FILE" ]; then
        colorized_echo green "  ✅ geoip.dat → /usr/local/share/xray/geoip.dat"
    fi
    if [ -f "$GEOSITE_FILE" ]; then
        colorized_echo green "  ✅ geosite.dat → /usr/local/share/xray/geosite.dat"
    fi
    

    colorized_echo blue "Validating docker-compose.yml..."
    if validate_compose_file "$COMPOSE_FILE"; then
        colorized_echo green "Проверка docker-compose.yml прошла успешно"
        
        colorized_echo blue "Перезапуск RemnaNode..."

        restart_command -n
        
        colorized_echo green "Installation of XRAY-CORE version $selected_version completed."
        

        read -p "Операция успешно завершена. Хотите сохранить резервную копию? (y/n): " -r keep_backup
        if [[ ! $keep_backup =~ ^[Yy]$ ]]; then
            rm "$backup_file"
            colorized_echo blue "Backup file removed"
        else
            colorized_echo blue "Резервная копия сохранена в: $backup_file"
        fi

        cleanup_old_backups "$COMPOSE_FILE"
        
    else
        colorized_echo red "Проверка docker-compose.yml не прошла! Восстановление резервной копии..."
        if restore_backup "$backup_file" "$COMPOSE_FILE"; then
            colorized_echo green "Резервная копия успешно восстановлена"
            colorized_echo red "Please check the docker-compose.yml file manually"
        else
            colorized_echo red "Не удалось восстановить резервную копию! Исходный файл может быть поврежден"
            colorized_echo red "Расположение резервной копии: $backup_file"
        fi
        exit 1
    fi
}


restore_to_container_default() {
    check_running_as_root
    colorized_echo blue "Restoring to container default Xray-core..."
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        colorized_echo red "Файл Docker Compose не найден в $COMPOSE_FILE"
        exit 1
    fi
    
    # Create backup before making changes
    colorized_echo blue "Создание резервной копии docker-compose.yml..."
    backup_file=$(create_backup "$COMPOSE_FILE")
    if [ $? -eq 0 ]; then
        colorized_echo green "Резервная копия создана: $backup_file"
    else
        colorized_echo red "Не удалось создать резервную копию"
        exit 1
    fi
    
    local service_indent=$(get_service_property_indentation "$COMPOSE_FILE")
    local escaped_service_indent=$(escape_for_sed "$service_indent")
    
    # Remove xray-related volume mounts using # as delimiter
    colorized_echo blue "Removing external Xray volume mounts..."
    sed -i "\#$XRAY_FILE#d" "$COMPOSE_FILE"
    sed -i "\#geoip\.dat#d" "$COMPOSE_FILE"
    sed -i "\#geosite\.dat#d" "$COMPOSE_FILE"
    
    # Check if volumes section is now empty and comment it out
    if grep -q "^${escaped_service_indent}volumes:" "$COMPOSE_FILE"; then
        # Count non-empty lines after volumes: line within the service
        volume_count=$(sed -n "/^${escaped_service_indent}volumes:/,/^${service_indent}[a-zA-Z_]/p" "$COMPOSE_FILE" | \
                      grep -v "^${escaped_service_indent}volumes:" | \
                      grep -v "^$" | \
                      grep -v "^${service_indent}[a-zA-Z_]" | \
                      wc -l)
        
        if [ "$volume_count" -eq 0 ]; then
            colorized_echo blue "Commenting out empty volumes section..."
            sed -i "s|^${escaped_service_indent}volumes:|${service_indent}# volumes:|g" "$COMPOSE_FILE"
        fi
    fi
    
    # Validate the docker-compose file
    colorized_echo blue "Validating docker-compose.yml..."
    if validate_compose_file "$COMPOSE_FILE"; then
        colorized_echo green "Проверка docker-compose.yml прошла успешно"
        
        colorized_echo blue "Перезапуск RemnaNode для использования стандартного Xray контейнера..."
        restart_command -n
        
        colorized_echo green "✅ Успешно восстановлен стандартный Xray-core контейнера"
        colorized_echo blue "The container will now use its built-in Xray version"
        
        # Ask about backup
        read -p "Операция успешно завершена. Хотите сохранить резервную копию? (y/n): " -r keep_backup
        if [[ ! $keep_backup =~ ^[Yy]$ ]]; then
            rm "$backup_file"
            colorized_echo blue "Backup file removed"
        else
            colorized_echo blue "Резервная копия сохранена в: $backup_file"
        fi

        cleanup_old_backups "$COMPOSE_FILE"
        
    else
        colorized_echo red "Проверка docker-compose.yml не прошла! Восстановление резервной копии..."
        if restore_backup "$backup_file" "$COMPOSE_FILE"; then
            colorized_echo green "Резервная копия успешно восстановлена"
            colorized_echo red "Please check the docker-compose.yml file manually"
        else
            colorized_echo red "Не удалось восстановить резервную копию! Исходный файл может быть поврежден"
            colorized_echo red "Расположение резервной копии: $backup_file"
        fi
        exit 1
    fi
}


check_editor() {
    if [ -z "$EDITOR" ]; then
        if command -v nano >/dev/null 2>&1; then
            EDITOR="nano"
        elif command -v vi >/dev/null 2>&1; then
            EDITOR="vi"
        else
            detect_os
            install_package nano
            EDITOR="nano"
        fi
    fi
}

xray_log_out() {
        if ! is_remnanode_installed; then
            colorized_echo red "RemnaNode not installed!"
            exit 1
        fi
    detect_compose

        if ! is_remnanode_up; then
            colorized_echo red "RemnaNode is not running. Start it first with 'remnanode up'"
            exit 1
        fi

    docker exec -it $APP_NAME tail -n +1 -f /var/log/supervisor/xray.out.log
}

xray_log_err() {
        if ! is_remnanode_installed; then
            colorized_echo red "RemnaNode not installed!"
            exit 1
        fi
    
     detect_compose
 
        if ! is_remnanode_up; then
            colorized_echo red "RemnaNode is not running. Start it first with 'remnanode up'"
            exit 1
        fi

    docker exec -it $APP_NAME tail -n +1 -f /var/log/supervisor/xray.err.log
}

edit_command() {
    detect_os
    check_editor
    if [ -f "$COMPOSE_FILE" ]; then
        $EDITOR "$COMPOSE_FILE"
    else
        colorized_echo red "Compose file not found at $COMPOSE_FILE"
        exit 1
    fi
}


usage() {
    clear

    echo -e "\033[1;37m⚡ $APP_NAME\033[0m \033[38;5;8mИнтерфейс командной строки\033[0m \033[38;5;244mv$SCRIPT_VERSION\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    echo
    echo -e "\033[1;37m📖 Использование:\033[0m"
    echo -e "   \033[38;5;15m$APP_NAME\033[0m \033[38;5;8m<команда>\033[0m \033[38;5;244m[опции]\033[0m"
    echo

    echo -e "\033[1;37m🚀 Основные команды:\033[0m"
    printf "   \033[38;5;15m%-18s\033[0m %s\n" "install" "🛠️  Установить RemnaNode"
    printf "   \033[38;5;15m%-18s\033[0m %s\n" "update" "⬆️  Обновить до последней версии"
    printf "   \033[38;5;15m%-18s\033[0m %s\n" "uninstall" "🗑️  Полностью удалить RemnaNode"
    echo

    echo -e "\033[1;37m⚙️  Управление сервисом:\033[0m"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "up" "▶️  Запустить сервисы"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "down" "⏹️  Остановить сервисы"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "restart" "🔄 Перезапустить сервисы"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "status" "📊 Показать статус сервиса"
    echo

    echo -e "\033[1;37m📊 Мониторинг и логи:\033[0m"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "logs" "📋 Просмотр логов контейнера"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "xray-log-out" "📤 Просмотр выходных логов Xray"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "xray-log-err" "📥 Просмотр логов ошибок Xray"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "setup-logs" "🗂️  Настройка ротации логов"
    echo

    echo -e "\033[1;37m⚙️  Обновления и конфигурация:\033[0m"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "update" "🔄 Обновить RemnaNode"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "core-update" "⬆️  Обновить Xray-core"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "edit" "📝 Редактировать конфигурацию"
    echo

    echo -e "\033[1;37m📋 Информация:\033[0m"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "help" "📖 Показать эту справку"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "version" "📋 Показать информацию о версии"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "menu" "🎛️  Интерактивное меню"
    echo

    if is_remnanode_installed && [ -f "$ENV_FILE" ]; then
        local node_port=$(grep "APP_PORT=" "$ENV_FILE" | cut -d'=' -f2 2>/dev/null || echo "")
        if [ -n "$node_port" ]; then
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
            echo -e "\033[1;37m🌐 Доступ к RemnaNode:\033[0m \033[38;5;117m$NODE_IP:$node_port\033[0m"
        fi
    fi

    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
    echo -e "\033[1;37m📖 Примеры:\033[0m"
    echo -e "\033[38;5;244m   sudo $APP_NAME install\033[0m"
    echo -e "\033[38;5;244m   sudo $APP_NAME core-update\033[0m"
    echo -e "\033[38;5;244m   $APP_NAME logs\033[0m"
    echo -e "\033[38;5;244m   $APP_NAME menu           # Интерактивное меню\033[0m"
    echo -e "\033[38;5;244m   $APP_NAME                # То же, что и menu\033[0m"
    echo
    echo -e "\033[38;5;8mИспользуйте '\033[38;5;15m$APP_NAME <команда> --help\033[38;5;8m' для подробной справки по команде\033[0m"
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
    echo -e "\033[38;5;8m📚 Проект: \033[38;5;250mhttps://gig.ovh\033[0m"
    echo -e "\033[38;5;8m🐛 Проблемы: \033[38;5;250mhttps://github.com/Spakieone/Remna\033[0m"
    echo -e "\033[38;5;8m💬 Поддержка: \033[38;5;250mhttps://t.me/remnawave\033[0m"
    echo -e "\033[38;5;8m👨‍💻 Автор: \033[38;5;250mDigneZzZ\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
}

# Функция для версии
show_version() {
    echo -e "\033[1;37m🚀 CLI управления RemnaNode\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    echo -e "\033[38;5;250mВерсия: \033[38;5;15m$SCRIPT_VERSION\033[0m"
    echo -e "\033[38;5;250mАвтор:  \033[38;5;15mDigneZzZ\033[0m"
    echo -e "\033[38;5;250mGitHub:  \033[38;5;15mhttps://github.com/Spakieone/Remna\033[0m"
    echo -e "\033[38;5;250mПроект: \033[38;5;15mhttps://gig.ovh\033[0m"
    echo -e "\033[38;5;250mПоддержка: \033[38;5;15mhttps://t.me/remnawave\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
}

main_menu() {
    while true; do
        clear
        echo -e "\033[1;37m🚀 Управление RemnaNode $APP_NAME\033[0m \033[38;5;244mv$SCRIPT_VERSION\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo
        
        # Проверка статуса узла
        local menu_status="Не установлен"
        local status_color="\033[38;5;244m"
        local node_port=""
        local xray_version=""
        
        if is_remnanode_installed; then
            if [ -f "$ENV_FILE" ]; then
                node_port=$(grep "APP_PORT=" "$ENV_FILE" | cut -d'=' -f2 2>/dev/null || echo "")
            fi
            
            if is_remnanode_up; then
                menu_status="Запущен"
                status_color="\033[1;32m"
                echo -e "${status_color}✅ Статус RemnaNode: ЗАПУЩЕН\033[0m"
                
                # Статус Caddy
                echo
                local caddy_status=""
                local caddy_type=""
                
                # Проверяем Docker контейнеры Caddy
                if docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -q "caddy"; then
                    local caddy_container=$(docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep "caddy" | head -1 | awk '{print $1}')
                    if [ -n "$caddy_container" ]; then
                        if docker ps --format "{{.Status}}" --filter "name=$caddy_container" 2>/dev/null | grep -q "Up"; then
                            caddy_status="✅ Запущен"
                            caddy_type="Docker ($caddy_container)"
                        else
                            caddy_status="⏹️ Остановлен"
                            caddy_type="Docker ($caddy_container)"
                        fi
                    fi
                fi
                
                # Если Docker контейнер не найден, проверяем systemd
                if [ -z "$caddy_status" ]; then
                    if systemctl list-unit-files 2>/dev/null | grep -q '^caddy\.service'; then
                        if systemctl is-active --quiet caddy 2>/dev/null; then
                            caddy_status="✅ Запущен"
                            caddy_type="Systemd"
                        else
                            caddy_status="⏹️ Остановлен"
                            caddy_type="Systemd"
                        fi
                    elif [ -f "/etc/systemd/system/caddy.service" ] || [ -f "/lib/systemd/system/caddy.service" ]; then
                        if systemctl is-active --quiet caddy 2>/dev/null; then
                            caddy_status="✅ Запущен"
                            caddy_type="Systemd"
                        else
                            caddy_status="⏹️ Остановлен"
                            caddy_type="Systemd"
                        fi
                    fi
                fi
                
                # Если systemd не найден, проверяем процессы
                if [ -z "$caddy_status" ]; then
                    if pgrep -f "caddy" >/dev/null 2>&1; then
                        local caddy_pid=$(pgrep -f "caddy" | head -1)
                        local caddy_cmd=$(ps -p "$caddy_pid" -o cmd= 2>/dev/null | head -1)
                        caddy_status="✅ Запущен"
                        caddy_type="Process (PID: $caddy_pid)"
                    else
                        caddy_status="❌ Не установлен"
                        caddy_type=""
                    fi
                fi
                
                if [ -n "$caddy_type" ]; then
                    echo -e "\033[1;37m🚦 Статус Caddy:\033[0m \033[1;32m$caddy_status\033[0m \033[38;5;244m($caddy_type)\033[0m"
                else
                    echo -e "\033[1;37m🚦 Статус Caddy:\033[0m \033[1;31m$caddy_status\033[0m"
                fi
                
                # Показываем информацию о подключении
                if [ -n "$node_port" ]; then
                    echo
                    echo -e "\033[1;37m🌐 Информация о подключении:\033[0m"
                    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;117m%s\033[0m\n" "IP адрес:" "$NODE_IP"
                    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;117m%s\033[0m\n" "Порт:" "$node_port"
                    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;117m%s:%s\033[0m\n" "Полный URL:" "$NODE_IP" "$node_port"

                    # Статусы iptables и tBlocker отдельными строками
                    local tb_exists=false tb_active=false ipt_label="" tb_label=""
                    if systemctl list-unit-files 2>/dev/null | grep -q '^tblocker\.service' || \
                       [ -f "/etc/systemd/system/tblocker.service" ] || [ -f "/lib/systemd/system/tblocker.service" ]; then
                        tb_exists=true
                        if systemctl is-active --quiet tblocker 2>/dev/null; then
                            tb_active=true
                        fi
                    fi
                    if $tb_exists; then
                        if $tb_active; then tb_label="\033[1;32m✅ Запущен\033[0m"; else tb_label="\033[1;31m⏹️  Остановлен\033[0m"; fi
                    else
                        tb_label="\033[38;5;244m❌ Не установлен\033[0m"
                    fi
                    if command -v iptables >/dev/null 2>&1; then
                        if iptables -L -n >/dev/null 2>&1; then
                            ipt_label="\033[1;32m✅ Активен\033[0m"
                        else
                            ipt_label="\033[1;33m⚠️  Недоступен\033[0m"
                        fi
                    else
                        ipt_label="\033[38;5;244m❌ Не найден\033[0m"
                    fi
                    echo -e "\033[1;37m🛡️  Firewall (iptables):\033[0m ${ipt_label}"
                    printf "       \033[38;5;15m%-10s\033[0m %b\n" "tBlocker:" "${tb_label}"
                    
                    # Статус UFW
                    local ufw_status=""
                    if command -v ufw >/dev/null 2>&1; then
                        if ufw status | grep -q "Status: active"; then
                            ufw_status="\033[1;32m✅ Активен\033[0m"
                        else
                            ufw_status="\033[1;33m⚠️  Неактивен\033[0m"
                        fi
                    else
                        ufw_status="\033[38;5;244m❌ Не установлен\033[0m"
                    fi
                    printf "       \033[38;5;15m%-10s\033[0m %b\n" "UFW:" "${ufw_status}"
                fi
                
                # Проверяем Xray-core
                xray_version=$(get_current_xray_core_version 2>/dev/null || echo "Not installed")
                echo
                echo -e "\033[1;37m⚙️  Статус компонентов:\033[0m"
                printf "   \033[38;5;15m%-12s\033[0m " "Xray Core:"
                if [ "$xray_version" != "Not installed" ]; then
                    echo -e "\033[1;32m✅ $xray_version\033[0m"
                else
                    echo -e "\033[1;33m⚠️  Не установлен\033[0m"
                fi

                # (подробный блок tBlocker/iptables удалён во избежание дублирования)
                
                # Показываем использование ресурсов
                echo
                echo -e "\033[1;37m💾 Использование ресурсов:\033[0m"
                
                local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
                local mem_info=$(free -h | grep "Mem:" 2>/dev/null)
                local mem_used=$(echo "$mem_info" | awk '{print $3}' 2>/dev/null || echo "N/A")
                local mem_total=$(echo "$mem_info" | awk '{print $2}' 2>/dev/null || echo "N/A")
                
                printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s%%\033[0m\n" "Использование CPU:" "$cpu_usage"
                printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s / %s\033[0m\n" "Память:" "$mem_used" "$mem_total"
                
                local disk_usage=$(df -h "$APP_DIR" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' 2>/dev/null || echo "N/A")
                local disk_available=$(df -h "$APP_DIR" 2>/dev/null | tail -1 | awk '{print $4}' 2>/dev/null || echo "N/A")
                
                printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s%% использовано, %s доступно\033[0m\n" "Использование диска:" "$disk_usage" "$disk_available"
                
                # Проверяем логи
                if [ -d "$DATA_DIR" ]; then
                    local log_files=$(find "$DATA_DIR" -name "*.log" 2>/dev/null | wc -l)
                    if [ "$log_files" -gt 0 ]; then
                        local total_log_size=$(du -sh "$DATA_DIR"/*.log 2>/dev/null | awk '{total+=$1} END {print total"K"}' | sed 's/KK/K/')
                        printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s файлов (%s)\033[0m\n" "Файлы логов:" "$log_files" "$total_log_size"
                    fi
                fi
                
            else
                menu_status="Остановлен"
                status_color="\033[1;31m"
                echo -e "${status_color}❌ Статус RemnaNode: ОСТАНОВЛЕН\033[0m"
                echo -e "\033[38;5;244m   Сервисы установлены, но не запущены\033[0m"
                echo -e "\033[38;5;244m   Используйте опцию 2 для запуска RemnaNode\033[0m"
            fi
        else
            echo -e "${status_color}📦 Статус RemnaNode: НЕ УСТАНОВЛЕН\033[0m"
            echo -e "\033[38;5;244m   Используйте опцию 1 для установки RemnaNode\033[0m"
        fi
        
        echo
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo
        echo -e "\033[1;37m🚀 Установка и управление:\033[0m"
        echo -e "   \033[38;5;15m1)\033[0m 🛠️  Установить RemnaNode"
        echo -e "   \033[38;5;15m2)\033[0m ▶️  Запустить сервисы RemnaNode"
        echo -e "   \033[38;5;15m3)\033[0m ⏹️  Остановить сервисы RemnaNode"
        echo -e "   \033[38;5;15m4)\033[0m 🔄 Перезапустить сервисы RemnaNode"
        echo -e "   \033[38;5;15m5)\033[0m 🗑️  Удалить RemnaNode"
        echo
        echo -e "\033[1;37m📊 Мониторинг и логи:\033[0m"
        echo -e "   \033[38;5;15m6)\033[0m 📊 Показать статус RemnaNode"
        echo -e "   \033[38;5;15m7)\033[0m 📋 Просмотреть логи контейнера"
        echo -e "   \033[38;5;15m8)\033[0m 📤 Просмотреть выходные логи Xray"
        echo -e "   \033[38;5;15m9)\033[0m 📥 Просмотреть логи ошибок Xray"
        echo
        echo -e "\033[1;37m⚙️  Обновления и конфигурация:\033[0m"
        echo -e "   \033[38;5;15m10)\033[0m 🔄 Обновить RemnaNode"
        echo -e "   \033[38;5;15m11)\033[0m ⬆️  Обновить Xray-core"
        echo -e "   \033[38;5;15m12)\033[0m 📝 Редактировать конфигурацию"
        echo -e "   \033[38;5;15m13)\033[0m 🗂️  Настроить ротацию логов"

        # Разделитель и отдельный блок tBlocker с другим цветом заголовка
        echo -e "\033[38;5;8m$(printf '%.0s_' $(seq 1 54))\033[0m"
        echo -e "\033[1;36m🛡️  tBlocker:\033[0m"
        echo -e "   \033[38;5;15m14)\033[0m 🛡️  Установить tBlocker"
        echo -e "   \033[38;5;15m15)\033[0m 🗑️  Удалить tBlocker"
        echo
        
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo -e "\033[38;5;15m   0)\033[0m 🚪 Выход в терминал"
        echo
        
        # Показываем подсказки в зависимости от состояния
        case "$menu_status" in
            "Не установлен")
                echo -e "\033[1;34m💡 Совет: Начните с опции 1 для установки RemnaNode\033[0m"
                ;;
            "Остановлен")
                echo -e "\033[1;34m💡 Совет: Используйте опцию 2 для запуска узла\033[0m"
                ;;
            "Запущен")
                if [ "$xray_version" = "Not installed" ]; then
                    echo -e "\033[1;34m💡 Совет: Установите Xray-core с опцией 11 для лучшей производительности\033[0m"
                else
                    echo -e "\033[1;34m💡 Совет: Проверьте логи (7-9) или настройте ротацию логов (13)\033[0m"
                fi
                ;;
        esac
        
        echo -e "\033[38;5;8mRemnaNode CLI v$SCRIPT_VERSION by DigneZzZ • gig.ovh\033[0m"
        echo
        read -p "$(echo -e "\033[1;37mВыберите опцию [0-15]:\033[0m ")" choice

        case "$choice" in
            1) install_command; read -p "Нажмите Enter для продолжения..." ;;
            2) up_command; read -p "Нажмите Enter для продолжения..." ;;
            3) down_command; read -p "Нажмите Enter для продолжения..." ;;
            4) restart_command; read -p "Нажмите Enter для продолжения..." ;;
            5) uninstall_command; read -p "Нажмите Enter для продолжения..." ;;
            6) status_command; read -p "Нажмите Enter для продолжения..." ;;
            7) logs_command; read -p "Нажмите Enter для продолжения..." ;;
            8) xray_log_out; read -p "Нажмите Enter для продолжения..." ;;
            9) xray_log_err; read -p "Нажмите Enter для продолжения..." ;;
            10) update_command; read -p "Нажмите Enter для продолжения..." ;;
            11) update_core_command; read -p "Нажмите Enter для продолжения..." ;;
            12) edit_command; read -p "Нажмите Enter для продолжения..." ;;
            13) setup_log_rotation; read -p "Нажмите Enter для продолжения..." ;;
            14) install_tblocker_command; read -p "Нажмите Enter для продолжения..." ;;
            15) uninstall_tblocker_command; read -p "Нажмите Enter для продолжения..." ;;
            0) clear; exit 0 ;;
            *) 
                echo -e "\033[1;31m❌ Неверная опция!\033[0m"
                sleep 1
                ;;
        esac
    done
}

# Главная обработка команд
case "${COMMAND:-menu}" in
    install) install_command ;;
    install-script) install_script_command ;;
    uninstall) uninstall_command ;;
    uninstall-script) uninstall_script_command ;;
    up) up_command ;;
    down) down_command ;;
    restart) restart_command ;;
    status) status_command ;;
    logs) logs_command ;;
    xray-log-out) xray_log_out ;;
    xray-log-err) xray_log_err ;;
    update) update_command ;;
    core-update) update_core_command ;;
    edit) edit_command ;;
    setup-logs) setup_log_rotation ;;
    install-tblocker) install_tblocker_command ;;
    help|--help|-h) usage ;;
    version|--version|-v) show_version ;;
    menu) main_menu ;;
    "") main_menu ;;
    *) 
        echo -e "\033[1;31m❌ Неизвестная команда: $COMMAND\033[0m"
        echo -e "\033[38;5;244mИспользуйте '\033[38;5;15m$APP_NAME help\033[38;5;244m' для просмотра доступных команд\033[0m"
        exit 1
        ;;
esac

