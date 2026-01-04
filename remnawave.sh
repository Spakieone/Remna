#!/usr/bin/env bash
# Скрипт установки панели Remnawave
# Этот скрипт устанавливает и управляет панелью Remnawave
# VERSION=3.7.3

set -uo pipefail
SCRIPT_VERSION="3.7.3"
BACKUP_SCRIPT_VERSION="1.0.2"  # Версия backup скрипта создаваемого Schedule функцией

if [ $# -gt 0 ] && [ "$1" = "@" ]; then
    shift  
fi

if [ $# -gt 0 ]; then
    COMMAND="$1"
    shift
fi



while [[ $# -gt 0 ]]; do  
    key="$1"  
    case $key in  
        --name)  
            # Имя приложения принудительно фиксировано как 'remnawave'
            echo -e "\033[38;5;244m⚠️  Параметр --name игнорируется. Используется имя 'remnawave'.\033[0m"
            shift
            shift
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
        --compress|-c|--data-only|--include-configs|-h|--help)
            # Аргументы команды backup - не обрабатываем здесь, пропускаем
            break
        ;;
        *)  
            break
        ;;  
    esac  
done


# Получение IP адреса через API ipinfo.io
NODE_IP=$(curl -s -4 ifconfig.io)

# Если получение IPv4 пустое, пытаемся получить IPv6 адрес
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(curl -s -6 ifconfig.io)
fi

# Установка имени приложения по умолчанию, если не указано
if [[ "$COMMAND" == "install" || "$COMMAND" == "install-script" ]] && [ -z "$APP_NAME" ]; then
    APP_NAME="remnawave"
fi
# Установка имени скрипта, если APP_NAME не установлен
if [ -z "$APP_NAME" ]; then
    APP_NAME="remnawave"
fi

INSTALL_DIR="/opt"
APP_DIR="$INSTALL_DIR/$APP_NAME"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
ENV_FILE="$APP_DIR/.env"
APP_CONFIG_FILE="$APP_DIR/app-config.json"
SCRIPT_URL="https://raw.githubusercontent.com/Spakieone/Remna/main/remnawave.sh"
SUB_ENV_FILE="$APP_DIR/.env.subscription"
BACKUP_CONFIG_FILE="$APP_DIR/backup-config.json"
BACKUP_SCRIPT_FILE="$APP_DIR/backup-scheduler.sh"
BACKUP_LOG_FILE="$APP_DIR/logs/backup.log"

# ===== BACKUP SCRIPT VERSION CHECK FUNCTIONS =====

# ===== PANEL VERSION FUNCTIONS =====

get_panel_version() {
    local container_name="${APP_NAME}"
    
    # Проверяем что контейнер запущен
    if ! docker exec "$container_name" echo "test" >/dev/null 2>&1; then
        echo "unknown"
        return 1
    fi
    
    # Пробуем получить версию из package.json
    local version=$(docker exec "$container_name" awk -F'"' '/"version"/{print $4; exit}' package.json 2>/dev/null)
    
    if [ -z "$version" ]; then
        # Альтернативный способ
        version=$(docker exec "$container_name" sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json 2>/dev/null | head -1)
    fi
    
    if [ -z "$version" ]; then
        echo "unknown"
        return 1
    fi
    
    echo "$version"
    return 0
}

validate_panel_version_compatibility() {
    local backup_version="$1"
    local current_version="$2"
    
    # Если одна из версий неизвестна - предупреждение
    if [ "$backup_version" = "unknown" ] || [ "$current_version" = "unknown" ]; then
        return 2  # Warning - unknown version
    fi
    
    # Если версии совпадают - OK
    if [ "$backup_version" = "$current_version" ]; then
        return 0  # Compatible
    fi
    
    # Проверяем major.minor версии (игнорируем patch)
    local backup_major_minor=$(echo "$backup_version" | cut -d'.' -f1,2)
    local current_major_minor=$(echo "$current_version" | cut -d'.' -f1,2)
    
    if [ "$backup_major_minor" = "$current_major_minor" ]; then
        return 1  # Minor incompatibility (different patch versions)
    fi
    
    return 3  # Major incompatibility
}

# ===== END PANEL VERSION FUNCTIONS =====

check_backup_script_version() {
    if [ ! -f "$BACKUP_SCRIPT_FILE" ]; then
        return 1  # Script doesn't exist
    fi
    
    # Максимально простая и безопасная проверка версии
    local script_version=""
    
    # Пробуем прочитать только первую строку с версией
    script_version=$(sed -n '1,10p' "$BACKUP_SCRIPT_FILE" 2>/dev/null | grep "^BACKUP_SCRIPT_VERSION=" 2>/dev/null | head -1 | cut -d'"' -f2 2>/dev/null)
    
    # Если sed не сработал, пробуем awk
    if [ -z "$script_version" ]; then
        script_version=$(awk '/^BACKUP_SCRIPT_VERSION=/ {gsub(/.*"/,""); gsub(/".*/,""); print; exit}' "$BACKUP_SCRIPT_FILE" 2>/dev/null)
    fi
    
    if [ -z "$script_version" ]; then
        return 2  # Old script without version or error reading
    fi
    
    if [ "$script_version" != "$BACKUP_SCRIPT_VERSION" ]; then
        return 3  # Version mismatch
    fi
    
    return 0  # Version is current
}

prompt_backup_script_update() {
    local status=$1
    
    echo -e "\033[1;33m⚠️  Требуется обновление скрипта бэкапа\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    echo
    
    case $status in
        1)
            echo -e "\033[38;5;250m📄 Скрипт бэкапа не найден\033[0m"
            echo -e "\033[38;5;244m   Будет создан новый скрипт бэкапа\033[0m"
            ;;
        2) 
            echo -e "\033[38;5;250m📜 Обнаружен старый скрипт бэкапа (без информации о версии)\033[0m"
            echo -e "\033[38;5;244m   Скрипт нужно обновить для совместимости\033[0m"
            ;;
        3)
            # Безопасное чтение версии с timeout
            local script_version=""
            if command -v timeout >/dev/null 2>&1; then
                script_version=$(timeout 5 head -5 "$BACKUP_SCRIPT_FILE" 2>/dev/null | grep "^BACKUP_SCRIPT_VERSION=" | cut -d'"' -f2 2>/dev/null)
            else
                script_version=$(head -5 "$BACKUP_SCRIPT_FILE" 2>/dev/null | grep "^BACKUP_SCRIPT_VERSION=" | cut -d'"' -f2 2>/dev/null)
            fi
            echo -e "\033[38;5;250m🔄 Обнаружено несоответствие версий\033[0m"
            echo -e "\033[38;5;244m   Текущая: ${script_version:-'unknown'} → Последняя: $BACKUP_SCRIPT_VERSION\033[0m"
            ;;
    esac
    
    echo
    echo -e "\033[1;37m🔧 Улучшения в последней версии:\033[0m"
    echo -e "\033[38;5;250m   ✓ Единая структура бэкапа (ручной + запланированный)\033[0m"
    echo -e "\033[38;5;250m   ✓ Улучшенное сжатие и обработка файлов\033[0m"
    echo -e "\033[38;5;250m   ✓ Лучшая обработка ошибок и логирование\033[0m"
    echo -e "\033[38;5;250m   ✓ Улучшенная совместимость восстановления\033[0m"
    echo
    
    if [ "$status" -eq 1 ]; then
        echo -e "\033[1;32m✅ Автоматическое создание скрипта бэкапа...\033[0m"
        return 0
    fi
    
    echo -e "\033[1;37mОбновить скрипт бэкапа сейчас?\033[0m"
    echo -e "\033[38;5;244m(Рекомендуется - старые бэкапы продолжат работать)\033[0m"
    echo
    read -p "Обновить скрипт бэкапа? [Y/n]: " -r update_choice
    
    case "$update_choice" in
        [nN]|[nN][oO])
            echo -e "\033[1;33m⚠️  Используется старый скрипт бэкапа (может вызвать проблемы совместимости)\033[0m"
            return 1
            ;;
        *)
            echo -e "\033[1;32m✅ Обновление скрипта бэкапа...\033[0m"
            return 0
            ;;
    esac
}

# ===== END BACKUP SCRIPT VERSION CHECK FUNCTIONS =====


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

check_system_requirements() {
    local errors=0
    
    # Проверяем свободное место (минимум 2GB для панели)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 2097152 ]; then  # 2GB in KB
        colorized_echo red "Ошибка: Недостаточно места на диске. Для панели Remnawave требуется минимум 2GB."
        errors=$((errors + 1))
    fi
    
    # Проверяем RAM (минимум 1GB)
    local available_ram=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_ram" -lt 512 ]; then
        colorized_echo yellow "Предупреждение: Мало доступной RAM (${available_ram}MB). Производительность панели может пострадать."
    fi
    
    # Проверяем архитектуру
    local arch=$(uname -m)
    case "$arch" in
        'amd64'|'x86_64'|'aarch64'|'arm64') ;;
        *) 
            colorized_echo red "Ошибка: Неподдерживаемая архитектура: $arch"
            errors=$((errors + 1))
            ;;
    esac
    
    return $errors
}

check_running_as_root() {
    if [ "$(id -u)" != "0" ]; then
        colorized_echo red "Эта команда должна выполняться от root."
        exit 1
    fi
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

            # Create symlink for compatibility with older scripts
            ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

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

install_remnawave_script() {  
    colorized_echo blue "Установка скрипта remnawave"  
    TARGET_PATH="/usr/local/bin/$APP_NAME"  
      
    if [ ! -d "/usr/local/bin" ]; then  
        mkdir -p /usr/local/bin  
    fi  
      
    curl -sSL $SCRIPT_URL -o $TARGET_PATH  
  
    chmod 755 $TARGET_PATH  
      
    if [ -f "$TARGET_PATH" ]; then  
        colorized_echo green "Скрипт Remnawave успешно установлен в $TARGET_PATH"  
    else  
        colorized_echo red "Не удалось установить скрипт remnawave в $TARGET_PATH"  
        exit 1  
    fi  
}

# Функция для проверки и восстановления поврежденного backup-config.json
validate_and_fix_backup_config() {
    if [ ! -f "$BACKUP_CONFIG_FILE" ]; then
        return 0  # Файл не существует, будет создан позже
    fi
    
    # Проверяем валидность JSON
    if ! jq . "$BACKUP_CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "\033[1;33m⚠️  Файл конфигурации резервного копирования поврежден, пытаемся восстановить...\033[0m"
        
        # Пытаемся извлечь токен из поврежденного файла
        local existing_token=""
        local existing_chat_id=""
        local existing_thread_id=""
        
        if [ -f "$BACKUP_CONFIG_FILE" ]; then
            # Ищем токен в поврежденном файле (может быть без кавычек)
            existing_token=$(grep -o '"bot_token":[[:space:]]*[^,}]*' "$BACKUP_CONFIG_FILE" 2>/dev/null | sed 's/"bot_token":[[:space:]]*//' | sed 's/^"//;s/"$//' || echo "")
            existing_chat_id=$(grep -o '"chat_id":[[:space:]]*[^,}]*' "$BACKUP_CONFIG_FILE" 2>/dev/null | sed 's/"chat_id":[[:space:]]*//' | sed 's/^"//;s/"$//' || echo "")
            existing_thread_id=$(grep -o '"thread_id":[[:space:]]*[^,}]*' "$BACKUP_CONFIG_FILE" 2>/dev/null | sed 's/"thread_id":[[:space:]]*//' | sed 's/^"//;s/"$//' || echo "")
            
            # Создаем бэкап поврежденного файла
            cp "$BACKUP_CONFIG_FILE" "$BACKUP_CONFIG_FILE.corrupted.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi
        
        # Определяем значения для восстановления
        local bot_token_value="null"
        local chat_id_value="null"
        local thread_id_value="null"
        local telegram_enabled="false"
        
        if [ -n "$existing_token" ] && [ "$existing_token" != "null" ] && [ "$existing_token" != "*" ]; then
            bot_token_value="\"$existing_token\""
            telegram_enabled="true"
        fi
        
        if [ -n "$existing_chat_id" ] && [ "$existing_chat_id" != "null" ]; then
            chat_id_value="\"$existing_chat_id\""
        fi
        
        if [ -n "$existing_thread_id" ] && [ "$existing_thread_id" != "null" ]; then
            thread_id_value="\"$existing_thread_id\""
        fi
        
        # Пересоздаем конфигурационный файл с сохраненными данными
        cat > "$BACKUP_CONFIG_FILE" << EOF
{
  "app_name": "remnawave",
  "schedule": "0 2 * * *",
  "compression": {
    "enabled": true,
    "level": 6
  },
  "retention": {
    "days": 7,
    "min_backups": 3
  },
  "telegram": {
    "enabled": $telegram_enabled,
    "bot_token": $bot_token_value,
    "chat_id": $chat_id_value,
    "thread_id": $thread_id_value,
    "split_large_files": true,
    "max_file_size": 49,
    "api_server": "https://api.telegram.org",
    "use_custom_api": false
  }
}
EOF
        
        # Проверяем что новый файл валиден
        if jq . "$BACKUP_CONFIG_FILE" >/dev/null 2>&1; then
            echo -e "\033[1;32m✅ Конфигурация резервного копирования успешно восстановлена\033[0m"
            if [ "$telegram_enabled" = "true" ]; then
                echo -e "\033[1;36m📱 Настройки Telegram были сохранены из поврежденного файла\033[0m"
            fi
        else
            echo -e "\033[1;31m❌ Не удалось восстановить конфигурацию резервной копии\033[0m"
            return 1
        fi
    fi
    
    return 0
}

ensure_backup_dirs() {
    if [ ! -d "$APP_DIR" ]; then
        echo -e "\033[1;31m❌ Remnawave не установлен!\033[0m"
        echo -e "\033[38;5;8m   Сначала выполните '\033[38;5;15msudo $APP_NAME install\033[38;5;8m'\033[0m"
        return 1
    fi
    
    # Проверяем и исправляем поврежденный конфиг если нужно
    validate_and_fix_backup_config
    
    mkdir -p "$APP_DIR/logs" 2>/dev/null || true
    mkdir -p "$APP_DIR/backups" 2>/dev/null || true
    mkdir -p "$APP_DIR/temp" 2>/dev/null || true
    
    if [ ! -f "$BACKUP_CONFIG_FILE" ]; then
        echo -e "\033[38;5;244m   Создание конфигурации резервного копирования по умолчанию...\033[0m"
        cat > "$BACKUP_CONFIG_FILE" << EOF
{
  "app_name": "$APP_NAME",
  "schedule": "0 2 * * *",
  "compression": {
    "enabled": true,
    "level": 6
  },
  "retention": {
    "days": 7,
    "min_backups": 3
  },
  "telegram": {
    "enabled": false,
    "bot_token": null,
    "chat_id": null,
    "thread_id": null,
    "split_large_files": true,
    "max_file_size": 49,
    "api_server": "https://api.telegram.org",
    "use_custom_api": false
  }
}
EOF
    fi
    
    return 0
}

ensure_rsync_installed() {
    if command -v rsync >/dev/null 2>&1; then
        return 0
    fi
    
    echo -e "\033[38;5;250m📦 Установка rsync для лучшей производительности бэкапа...\033[0m"
    
    local install_success=false
    
    if command -v apt-get >/dev/null 2>&1; then
        if apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq rsync >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y -q rsync >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v dnf >/dev/null 2>&1; then
        if dnf install -y -q rsync >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v pacman >/dev/null 2>&1; then
        if pacman -S --noconfirm --quiet rsync >/dev/null 2>&1; then
            install_success=true
        fi
    fi
    
    if [ "$install_success" = true ]; then
        echo -e "\033[1;32m✅ rsync установлен успешно\033[0m"
        return 0
    else
        echo -e "\033[1;33m⚠️  Не удалось установить rsync, используем альтернативный метод\033[0m"
        return 1
    fi
}

schedule_command() {
    if [ "$#" -eq 0 ]; then
        schedule_menu
        return
    fi
        if [ "$#" -eq 0 ]; then
        schedule_menu  
        return 0       
    fi
    
    case "$1" in
        setup|config) schedule_setup_menu ;;
        enable) schedule_enable ;;
        disable) schedule_disable ;;
        status) schedule_status ;;
        test) schedule_test_backup ;;
        test-telegram) schedule_test_telegram ;;
        run) schedule_run_backup ;;
        logs) schedule_show_logs ;;
        cleanup) schedule_cleanup ;;
        help|-h|--help) schedule_help ;;
        menu) schedule_menu ;;
        *) 
            echo -e "\033[1;31mНеизвестная команда: $1\033[0m"
            echo -e "\033[38;5;8mИспользуйте '\033[38;5;15m$APP_NAME schedule help\033[38;5;8m' для списка команд\033[0m"
            echo
            echo -e "\033[1;37mДоступные команды:\033[0m"
            echo -e "   \033[38;5;15msetup\033[0m           Настроить параметры бэкапа"
            echo -e "   \033[38;5;15menable\033[0m          Включить планировщик"
            echo -e "   \033[38;5;15mdisable\033[0m         Отключить планировщик"
            echo -e "   \033[38;5;15mstatus\033[0m          Показать статус планировщика"
            echo -e "   \033[38;5;15mtest\033[0m            Тест создания бэкапа"
            echo -e "   \033[38;5;15mtest-telegram\033[0m   Тест отправки в Telegram"
            echo -e "   \033[38;5;15mrun\033[0m             Запустить бэкап сейчас"
            echo -e "   \033[38;5;15mlogs\033[0m            Просмотр логов бэкапа"
            echo -e "   \033[38;5;15mcleanup\033[0m         Очистить старые бэкапы"
            echo -e "   \033[38;5;15mhelp\033[0m            Показать эту справку"
            ;;
    esac
}


schedule_menu() {
    if ! ensure_backup_dirs; then
        return 1
    fi
    
    while true; do
        clear
        echo -e "\033[1;37m📅 Управление планировщиком бэкапов\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        echo
        
        local status=$(schedule_get_status)
        if [ "$status" = "enabled" ]; then
            echo -e "\033[1;32m✅ Статус планировщика: ВКЛЮЧЕН\033[0m"
        else
            echo -e "\033[1;31m❌ Статус планировщика: ВЫКЛЮЧЕН\033[0m"
        fi
        
        if [ -f "$BACKUP_CONFIG_FILE" ]; then
            local schedule=$(jq -r '.schedule // "Не настроено"' "$BACKUP_CONFIG_FILE" 2>/dev/null)
            local telegram_enabled=$(jq -r '.telegram.enabled // false' "$BACKUP_CONFIG_FILE" 2>/dev/null)
            local retention=$(jq -r '.retention.days // 7' "$BACKUP_CONFIG_FILE" 2>/dev/null)
            local compression=$(jq -r '.compression.enabled // true' "$BACKUP_CONFIG_FILE" 2>/dev/null)
            
            echo -e "\033[38;5;250mРасписание: $schedule\033[0m"
            echo -e "\033[38;5;250mТип бэкапа: Полный (база данных + все конфиги)\033[0m"
            echo -e "\033[38;5;250mСжатие: $([ "$compression" = "true" ] && echo "✅ Включено" || echo "❌ Отключено")\033[0m"
            echo -e "\033[38;5;250mTelegram: $([ "$telegram_enabled" = "true" ] && echo "✅ Включено" || echo "❌ Отключено")\033[0m"
            echo -e "\033[38;5;250mХранение: $retention дней\033[0m"
        else
            echo -e "\033[38;5;244mКонфигурация не найдена\033[0m"
        fi
        
        # Показываем информацию о логах
        if [ -f "$BACKUP_LOG_FILE" ]; then
            local log_size=$(du -sh "$BACKUP_LOG_FILE" 2>/dev/null | cut -f1)
            local last_entry=$(tail -1 "$BACKUP_LOG_FILE" 2>/dev/null | grep -o '\[.*\]' | head -1 || echo "No entries")
            echo -e "\033[38;5;250mРазмер лога: $log_size, Последняя запись: $last_entry\033[0m"
        fi
        
        echo
        echo -e "\033[1;37m📋 Доступные действия:\033[0m"
        echo -e "   \033[38;5;15m1)\033[0m 🔧 Настроить параметры бэкапа"
        echo -e "   \033[38;5;15m2)\033[0m ⚙️  Включить/Отключить планировщик"
        echo -e "   \033[38;5;15m3)\033[0m 🧪 Тест создания бэкапа"
        echo -e "   \033[38;5;15m4)\033[0m 📱 Тест доставки в Telegram"
        echo -e "   \033[38;5;15m5)\033[0m 📊 Показать статус планировщика"
        echo -e "   \033[38;5;15m6)\033[0m 📋 Просмотр логов бэкапа"
        echo -e "   \033[38;5;15m7)\033[0m 🧹 Очистить старые бэкапы"
        echo -e "   \033[38;5;15m8)\033[0m ▶️  Запустить полный бэкап сейчас"
        echo -e "   \033[38;5;15m9)\033[0m 🔄 Обновить скрипт бэкапа"
        echo -e "   \033[38;5;15ma)\033[0m 🧹  Очистить логи"
        echo -e "   \033[38;5;244m0)\033[0m ⬅️  Назад в главное меню"
        echo
        echo -e "\033[38;5;8m💡 Все запланированные бэкапы включают базу данных + конфигурации\033[0m"
        echo
        
        read -p "Выберите опцию [0-9,a]: " choice
        
        case "$choice" in
            1) schedule_setup_menu ;;
            2) schedule_toggle ;;
            3) 
                schedule_test_backup
                echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
                ;;
            4) 
                schedule_test_telegram
                echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
                ;;
            5) 
                schedule_status
                echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
                ;;
            6) schedule_show_logs ;;
            7) schedule_cleanup ;;
            8) schedule_run_backup ;;
            9) schedule_update_script ;;
            a|A) schedule_clear_logs ;;
            0) 
                clear
                return 0  
                ;;
            *) 
                echo -e "\033[1;31mНеверная опция!\033[0m"
                sleep 1
                ;;
        esac
    done
}

# Новая функция очистки логов
schedule_clear_logs() {
    echo
    read -p "Очистить все логи бэкапа? [y/N]: " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        if [ -f "$BACKUP_LOG_FILE" ]; then
            > "$BACKUP_LOG_FILE"  # Очищаем файл
            echo -e "\033[1;32m✅ Логи бэкапа очищены\033[0m"
        else
            echo -e "\033[38;5;244mНет файла логов для очистки\033[0m"
        fi
    else
        echo -e "\033[38;5;250mОперация отменена\033[0m"
    fi
    
    sleep 2
}

schedule_update_script() {
    clear
    echo -e "\033[1;37m🔄 Обновление скрипта бэкапа\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
    echo
    
    # Упрощённое обновление - просто пересоздаём скрипт
    echo -e "\033[1;33m🔄 Обновление скрипта бэкапа до последней версии...\033[0m"
    echo -e "\033[38;5;244m   Пересоздание скрипта с версией $BACKUP_SCRIPT_VERSION\033[0m"
    echo
    
    # Создаём новый скрипт
    schedule_create_backup_script
    
    if [ -f "$BACKUP_SCRIPT_FILE" ]; then
        echo -e "\033[1;32m✅ Скрипт бэкапа успешно обновлен (v$BACKUP_SCRIPT_VERSION)\033[0m"
        echo -e "\033[38;5;244m   Расположение скрипта: $BACKUP_SCRIPT_FILE\033[0m"
        
        echo
        echo -e "\033[1;37m🚀 Возможности в v$BACKUP_SCRIPT_VERSION:\033[0m"
        echo -e "\033[38;5;250m   ✓ Единая структура бэкапа (совместима с ручными бэкапами)\033[0m"
        echo -e "\033[38;5;250m   ✓ Улучшенное сжатие и обработка файлов\033[0m"
        echo -e "\033[38;5;250m   ✓ Лучшая обработка ошибок и логирование\033[0m"
        echo -e "\033[38;5;250m   ✓ Улучшенная совместимость восстановления\033[0m"
        echo -e "\033[38;5;250m   ✓ Автоматическая проверка версий\033[0m"
        
        # Если scheduler включен, показываем статус
        local status=$(schedule_get_status)
        if [ "$status" = "enabled" ]; then
            echo
            echo -e "\033[1;37m📋 Статус планировщика: ВКЛЮЧЕН\033[0m"
            echo -e "\033[38;5;250m   Обновленный скрипт будет использоваться для следующего запланированного бэкапа\033[0m"
            echo -e "\033[38;5;244m   Перезапуск не требуется - изменения вступают в силу немедленно\033[0m"
        fi
    else
        echo -e "\033[1;31m❌ Не удалось обновить скрипт бэкапа\033[0m"
    fi
    
    echo
    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
}
schedule_setup_menu() {
    # Убеждаемся что rsync установлен для лучшей производительности
    if ! command -v rsync >/dev/null 2>&1; then
        ensure_rsync_installed
    fi

    while true; do
        clear
    echo -e "\033[1;37m🔧 Конфигурация бэкапов\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
        echo
        
        if [ -f "$BACKUP_CONFIG_FILE" ]; then
            echo -e "\033[1;37m📋 Текущие настройки:\033[0m"
            local schedule=$(jq -r '.schedule // "Not set"' "$BACKUP_CONFIG_FILE" 2>/dev/null)
            local compression=$(jq -r '.compression.enabled // false' "$BACKUP_CONFIG_FILE" 2>/dev/null)
            local retention=$(jq -r '.retention.days // 7' "$BACKUP_CONFIG_FILE" 2>/dev/null)
            local telegram_enabled=$(jq -r '.telegram.enabled // false' "$BACKUP_CONFIG_FILE" 2>/dev/null)
            
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Расписание:" "$schedule"
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Сжатие:" "$([ "$compression" = "true" ] && echo "Включено" || echo "Отключено")"
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s дней\033[0m\n" "Хранение:" "$retention"
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Telegram:" "$([ "$telegram_enabled" = "true" ] && echo "Включено (лимит 49MB)" || echo "Отключено")"
            echo
        fi
        
    echo -e "\033[1;37m⚙️  Параметры конфигурации:\033[0m"
        echo -e "   \033[38;5;15m1)\033[0m ⏰ Установить расписание бэкапа"
        echo -e "   \033[38;5;15m2)\033[0m 🗜️  Настроить сжатие"
        echo -e "   \033[38;5;15m3)\033[0m 🗂️  Установить политику хранения"
        echo -e "   \033[38;5;15m4)\033[0m 📱 Настроить Telegram"
        echo -e "   \033[38;5;15m5)\033[0m 🔄 Сбросить к умолчанию"
        echo -e "   \033[38;5;15m6)\033[0m 🔧 Пересоздать скрипт бэкапа"
        echo -e "   \033[38;5;244m0)\033[0m ⬅️  Назад"
        echo
        
        read -p "Выберите опцию [0-6]: " choice
        
        case "$choice" in
            1) schedule_configure_schedule ;;
            2) schedule_configure_compression ;;
            3) schedule_configure_retention ;;
            4) schedule_configure_telegram ;;
            5) schedule_reset_config ;;
            6) schedule_recreate_script ;;
            0) 
                return 0  
                ;;
            *) 
                echo -e "\033[1;31mНеверная опция!\033[0m"
                sleep 1
                ;;
        esac
    done
}

schedule_recreate_script() {
    echo
    echo -e "\033[1;37m🔧 Пересоздание скрипта бэкапа\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 35))\033[0m"
    echo
    echo -e "\033[38;5;250mБудет пересоздан скрипт бэкапа последней версии\033[0m"
    read -p "Продолжить? [y/N]: " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Удаляем старый скрипт
        if [ -f "$BACKUP_SCRIPT_FILE" ]; then
            rm -f "$BACKUP_SCRIPT_FILE"
            echo -e "\033[38;5;244m   Старый скрипт удален\033[0m"
        fi
        
        # Создаем новый
        schedule_create_backup_script
        echo -e "\033[1;32m✅ Скрипт бэкапа успешно пересоздан!\033[0m"
    else
        echo -e "\033[38;5;250mОперация отменена\033[0m"
    fi
    
    sleep 2
}


schedule_configure_schedule() {
    clear
    echo -e "\033[1;37m⏰ Настройка расписания бэкапа\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 35))\033[0m"
    echo
    echo -e "\033[1;37m📋 Предустановленные расписания:\033[0m"
    echo -e "   \033[38;5;15m1)\033[0m Ежедневно в 02:00"
    echo -e "   \033[38;5;15m2)\033[0m Ежедневно в 04:00"
    echo -e "   \033[38;5;15m3)\033[0m Каждые 12 часов"
    echo -e "   \033[38;5;15m4)\033[0m Еженедельно (воскресенье 02:00)"
    echo -e "   \033[38;5;15m5)\033[0m Пользовательское выражение cron"
    echo
    
    read -p "Выберите расписание [1-5]: " choice
    
    local cron_expression=""
    case "$choice" in
        1) cron_expression="0 2 * * *" ;;
        2) cron_expression="0 4 * * *" ;;
        3) cron_expression="0 */12 * * *" ;;
        4) cron_expression="0 2 * * 0" ;;
        5) 
            echo
            echo -e "\033[1;37m⚙️  Пользовательское выражение Cron\033[0m"
            echo -e "\033[38;5;244mФормат: минута час день месяц день_недели\033[0m"
            echo -е "\033[38;5;244mПример: 0 3 * * * (ежедневно в 03:00)\033[0m"
            echo
            read -p "Введите выражение cron: " cron_expression
            
            if ! echo "$cron_expression" | grep -E '^[0-9\*\-\,\/]+ [0-9\*\-\,\/]+ [0-9\*\-\,\/]+ [0-9\*\-\,\/]+ [0-9\*\-\,\/]+$' >/dev/null; then
                echo -e "\033[1;31m❌ Неверное выражение cron!\033[0m"
                sleep 2
                return
            fi
            ;;
        *) echo -e "\033[1;31mНеверная опция!\033[0m"; sleep 1; return ;;
    esac
    
    schedule_update_config ".schedule" "\"$cron_expression\""
    echo -e "\033[1;32m✅ Расписание обновлено: $cron_expression\033[0m"
    sleep 2
}

schedule_configure_compression() {
    clear
    echo -e "\033[1;37m🗜️  Настройка сжатия\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
    echo
    echo -e "\033[38;5;250mСжатие уменьшает размер бэкапа, но увеличивает нагрузку на CPU\033[0m"
    echo
    
    read -p "Включить сжатие? [y/N]: " enable_compression
    
    if [[ $enable_compression =~ ^[Yy]$ ]]; then
        schedule_update_config ".compression.enabled" "true"
        
        echo
        echo -e "\033[1;37m📊 Уровень сжатия:\033[0m"
        echo -e "   \033[38;5;15m1)\033[0m Быстро (уровень 1)"
        echo -e "   \033[38;5;15m2)\033[0m Сбалансированно (уровень 6)"
        echo -e "   \033[38;5;15m3)\033[0m Лучшее (уровень 9)"
        echo
        
        read -p "Выберите уровень сжатия [1-3]: " level_choice
        
        local compression_level=6
        case "$level_choice" in
            1) compression_level=1 ;;
            2) compression_level=6 ;;
            3) compression_level=9 ;;
        esac
        
        schedule_update_config ".compression.level" "$compression_level"
        echo -e "\033[1;32m✅ Сжатие включено (уровень $compression_level)\033[0m"
    else
        schedule_update_config ".compression.enabled" "false"
        echo -e "\033[1;32m✅ Сжатие выключено\033[0m"
    fi
    
    sleep 2
}

schedule_configure_retention() {
    clear
    echo -e "\033[1;37m🗂️  Настройка политики хранения\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 35))\033[0m"
    echo
    echo -e "\033[38;5;250mКак долго хранить файлы бэкапа до автоматического удаления\033[0m"
    echo
    
    read -p "Период хранения в днях [7]: " retention_days
    retention_days=${retention_days:-7}
    
    if ! [[ "$retention_days" =~ ^[0-9]+$ ]] || [ "$retention_days" -lt 1 ]; then
        echo -e "\033[1;31m❌ Неверное число!\033[0m"
        sleep 2
        return
    fi
    
    schedule_update_config ".retention.days" "$retention_days"
    
    echo
    read -p "Хранить минимальное количество бэкапов независимо от возраста? [y/N]: " keep_minimum
    if [[ $keep_minimum =~ ^[Yy]$ ]]; then
        read -p "Минимальное количество бэкапов для хранения [3]: " min_backups
        min_backups=${min_backups:-3}
        
        if [[ "$min_backups" =~ ^[0-9]+$ ]] && [ "$min_backups" -ge 1 ]; then
            schedule_update_config ".retention.min_backups" "$min_backups"
        fi
    fi
    
    echo -e "\033[1;32m✅ Политика хранения обновлена: $retention_days дней\033[0m"
    sleep 2
}

schedule_configure_telegram() {
    clear
    echo -e "\033[1;37m📱 Настройка интеграции с Telegram\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    echo
    
    read -p "Включить уведомления Telegram? [y/N]: " enable_telegram
    
    if [[ $enable_telegram =~ ^[Yy]$ ]]; then
        schedule_update_config ".telegram.enabled" "true"

        schedule_update_config ".telegram.use_custom_api" "false"
        schedule_update_config ".telegram.api_server" "\"https://api.telegram.org\""
        schedule_update_config ".telegram.max_file_size" "49"
        schedule_update_config ".telegram.split_large_files" "true"
        
        echo -e "\033[1;32m✅ Используется официальный Telegram Bot API (лимит 49MB)\033[0m"
        
        # Bot Token
        echo
        echo -e "\033[1;37m🤖 Настройка Bot Token\033[0m"
        echo -e "\033[38;5;244mПолучите токен у @BotFather в Telegram\033[0m"
        
        local current_token=$(jq -r '.telegram.bot_token // ""' "$BACKUP_CONFIG_FILE" 2>/dev/null)
        if [ -n "$current_token" ] && [ "$current_token" != "null" ]; then
            echo -e "\033[38;5;250mТекущий токен: ${current_token:0:10}...\033[0m"
            read -p "Сохранить текущий токен? [Y/n]: " keep_token
            if [[ ! $keep_token =~ ^[Nn]$ ]]; then
                current_token=""
            fi
        fi
        
        if [ -z "$current_token" ] || [ "$current_token" = "null" ]; then
            read -p "Введите токен бота: " bot_token
            if [ -z "$bot_token" ]; then
                echo -e "\033[1;31m❌ Требуется токен!\033[0m"
                sleep 2
                return
            fi
            
            # Экранируем специальные символы в токене для безопасного JSON
            bot_token_escaped=$(printf '%s' "$bot_token" | sed 's/"/\\"/g')
            
            if schedule_update_config ".telegram.bot_token" "\"$bot_token_escaped\""; then
                echo -e "\033[1;32m✅ Токен бота успешно сохранен\033[0m"
            else
                echo -e "\033[1;31m❌ Не удалось сохранить токен бота\033[0m"
                sleep 2
                return
            fi
        fi
        
        # Chat ID
        echo
        echo -e "\033[1;37m💬 Настройка чата\033[0m"
        echo -e "\033[38;5;244mДля групп: используйте отрицательный ID (например, -1001234567890)\033[0m"
        echo -e "\033[38;5;244mДля личных чатов: положительный ID (например, 123456789)\033[0m"
        
        read -p "Введите ID чата: " chat_id
        if [ -z "$chat_id" ]; then
            echo -e "\033[1;31m❌ Требуется Chat ID!\033[0m"
            sleep 2
            return
        fi
        schedule_update_config ".telegram.chat_id" "\"$chat_id\""
        
        # Thread ID (optional)
        echo
        echo -e "\033[1;37m🧵 Настройка темы (опционально)\033[0m"
        echo -e "\033[38;5;244mДля групповых тем/топиков. Оставьте пустым, если не используете темы.\033[0m"
        
        read -p "Введите ID темы (необязательно): " thread_id
        if [ -n "$thread_id" ]; then
            schedule_update_config ".telegram.thread_id" "\"$thread_id\""
        else
            schedule_update_config ".telegram.thread_id" "null"
        fi
        
        echo -e "\033[1;32m✅ Интеграция с Telegram настроена!\033[0m"
        echo -e "\033[38;5;8m   Файлы больше 49MB будут автоматически разделены\033[0m"
        echo -e "\033[38;5;8m   Используйте 'Test Telegram' для проверки настроек\033[0m"
    else
        schedule_update_config ".telegram.enabled" "false"
        echo -e "\033[1;32m✅ Уведомления Telegram отключены\033[0m"
    fi
    
    sleep 2
}

schedule_update_config() {
    local key="$1"
    local value="$2"
    
    # Проверяем и исправляем поврежденный конфиг если нужно
    validate_and_fix_backup_config
    
    if [ ! -f "$BACKUP_CONFIG_FILE" ]; then
        echo '{}' > "$BACKUP_CONFIG_FILE"
    fi

    local temp_file=$(mktemp)
    if jq "$key = $value" "$BACKUP_CONFIG_FILE" > "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$BACKUP_CONFIG_FILE"
    else
        echo -e "\033[1;31m❌ Не удалось обновить конфигурацию резервного копирования\033[0m"
        rm -f "$temp_file"
        return 1
    fi
}

ensure_cron_installed() {
    # Проверяем наличие crontab
    if command -v crontab >/dev/null 2>&1; then
        return 0
    fi
    
    echo -e "\033[38;5;250m📦 Установка службы cron для планирования бэкапов...\033[0m"
    
    # Определяем пакетный менеджер и устанавливаем cron
    local install_success=false
    
    if command -v apt-get >/dev/null 2>&1; then
        if apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq cron >/dev/null 2>&1; then
            # Запускаем и включаем cron service
            systemctl start cron 2>/dev/null || service cron start 2>/dev/null || true
            systemctl enable cron 2>/dev/null || true
            install_success=true
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y -q cronie >/dev/null 2>&1; then
            systemctl start crond 2>/dev/null || service crond start 2>/dev/null || true
            systemctl enable crond 2>/dev/null || true
            install_success=true
        fi
    elif command -v dnf >/dev/null 2>&1; then
        if dnf install -y -q cronie >/dev/null 2>&1; then
            systemctl start crond 2>/dev/null || service crond start 2>/dev/null || true
            systemctl enable crond 2>/dev/null || true
            install_success=true
        fi
    elif command -v pacman >/dev/null 2>&1; then
        if pacman -S --noconfirm --quiet cronie >/dev/null 2>&1; then
            systemctl start cronie 2>/dev/null || true
            systemctl enable cronie 2>/dev/null || true
            install_success=true
        fi
    fi
    
    if [ "$install_success" = true ]; then
        echo -e "\033[1;32m✅ Служба cron установлена и запущена успешно\033[0m"
        return 0
    else
        echo -e "\033[1;31m❌ Не удалось автоматически установить службу cron\033[0m"
        echo -e "\033[38;5;244m   Установите вручную:\033[0m"
        if command -v apt-get >/dev/null 2>&1; then
            echo -e "\033[38;5;117m   sudo apt-get install cron\033[0m"
        elif command -v yum >/dev/null 2>&1; then
            echo -e "\033[38;5;117m   sudo yum install cronie\033[0m"
        elif command -v dnf >/dev/null 2>&1; then
            echo -e "\033[38;5;117m   sudo dnf install cronie\033[0m"
        fi
        return 1
    fi
}

schedule_get_status() {
    if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT_FILE"; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

schedule_toggle() {
    local status=$(schedule_get_status)
    
    if [ "$status" = "enabled" ]; then
        echo -e "\033[1;33mОтключение планировщика...\033[0m"
        schedule_disable
    else
        echo -e "\033[1;33mВключение планировщика...\033[0m"
        schedule_enable
    fi
    
    # Add pause to show result before returning to menu
    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
}

schedule_enable() {
    # Проверяем и устанавливаем cron если необходимо
    if ! ensure_cron_installed; then
        echo -e "\033[1;31m❌ Нельзя включить планировщик без службы cron!\033[0m"
        sleep 3
        return
    fi
    
    if [ ! -f "$BACKUP_CONFIG_FILE" ]; then
        echo -e "\033[1;31m❌ Конфигурация не найдена! Сначала настройте параметры бэкапа.\033[0m"
        sleep 2
        return
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "\033[1;31m❌ jq не установлен! Пожалуйста, установите jq.\033[0m"
        echo -e "\033[38;5;244m   Установите: sudo apt-get install jq\033[0m"
        sleep 3
        return
    fi
    
    local schedule=$(jq -r '.schedule // ""' "$BACKUP_CONFIG_FILE" 2>/dev/null)
    if [ -z "$schedule" ] || [ "$schedule" = "null" ]; then
        echo -e "\033[1;31m❌ Расписание не настроено! Сначала установите расписание бэкапа.\033[0m"
        sleep 2
        return
    fi

    # Проверяем и создаём backup скрипт если необходимо
    if [ ! -f "$BACKUP_SCRIPT_FILE" ]; then
        echo -e "\033[1;33m⚠️  Создание скрипта бэкапа...\033[0m"
        schedule_create_backup_script
    else
        # Простая проверка - если файл есть, но версия может быть старой, обновляем
        echo -e "\033[1;33m⚠️  Обеспечение актуальности скрипта бэкапа...\033[0m"
        schedule_create_backup_script
    fi

    local cron_entry="$schedule $BACKUP_SCRIPT_FILE >> $BACKUP_LOG_FILE 2>&1 # Remnawave Backup Scheduler"
    
    # Удаляем старую запись для backup-scheduler.sh если есть
    if (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_FILE"; echo "$cron_entry") | crontab - 2>/dev/null; then
        echo -e "\033[1;32m✅ Планировщик бэкапов включен!\033[0m"
        echo -e "\033[38;5;250mРасписание: $schedule\033[0m"
    else
        echo -e "\033[1;31m❌ Не удалось включить планировщик! Проверьте статус службы cron.\033[0m"
        echo -e "\033[38;5;244m   Попробуйте: sudo systemctl status cron\033[0m"
    fi
    
    sleep 2
}

schedule_disable() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo -e "\033[1;33m⚠️  Crontab недоступен, но планировщик должен быть отключен\033[0m"
        sleep 2
        return
    fi
    
    if crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_FILE" | crontab - 2>/dev/null; then
        echo -e "\033[1;32m✅ Планировщик бэкапов отключен!\033[0m"
    else
        # Попробуем создать пустой crontab если его не было
        if crontab -l 2>/dev/null | wc -l | grep -q "^0$"; then
            echo "" | crontab - 2>/dev/null
            echo -e "\033[1;32m✅ Планировщик бэкапов отключен (crontab был пуст)!\033[0m"
        else
            echo -e "\033[1;33m⚠️  Не удалось изменить crontab, но планировщик должен быть отключен\033[0m"
        fi
    fi
    
    sleep 2
}




# ===== RESTORE VALIDATION AND SAFETY FUNCTIONS =====

# Функция детального логирования для операций восстановления
log_restore_operation() {
    local operation="$1"
    local status="$2"
    local details="$3"
    local restore_log_file="$APP_DIR/logs/restore.log"
    
    # Создаем директорию для логов если не существует
    mkdir -p "$(dirname "$restore_log_file")"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] RESTORE: $operation - $status"
    
    if [ -n "$details" ]; then
        log_entry="$log_entry - $details"
    fi
    
    echo "$log_entry" >> "$restore_log_file"
    
    # Дополнительно выводим в основной лог если функция доступна
    if declare -f log_message >/dev/null 2>&1; then
        log_message "RESTORE: $operation - $status"
    fi
}

# Функция проверки совместимости версий
check_version_compatibility() {
    local backup_metadata="$1"
    local current_script_version="$SCRIPT_VERSION"
    
    if [ ! -f "$backup_metadata" ]; then
        log_restore_operation "Version Check" "WARNING" "Метаданные не найдены, пропускаем проверку версий"
        return 0
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_restore_operation "Version Check" "WARNING" "jq недоступен, пропускаем проверку версий"
        return 0
    fi
    
    local backup_script_version=$(jq -r '.script_version // "unknown"' "$backup_metadata" 2>/dev/null)
    local backup_panel_version=$(jq -r '.panel_version // "unknown"' "$backup_metadata" 2>/dev/null)
    local backup_date=$(jq -r '.date_created // "unknown"' "$backup_metadata" 2>/dev/null)
    
    # Получаем текущую версию панели
    local current_panel_version=$(get_panel_version)
    
    log_restore_operation "Version Check" "INFO" "Скрипт бэкапа: $backup_script_version, Текущий: $current_script_version, Панель в бэкапе: $backup_panel_version, Текущая панель: $current_panel_version, Дата: $backup_date"
    
    # Проверка совместимости версии панели (критически важно!)
    if [ "$backup_panel_version" != "unknown" ] && [ "$current_panel_version" != "unknown" ]; then
        validate_panel_version_compatibility "$backup_panel_version" "$current_panel_version"
        local panel_compat_result=$?
        
        case $panel_compat_result in
            0)
                echo -e "\033[1;32m✅ Совместимость версий панели: Идеальное совпадение ($current_panel_version)\033[0m"
                log_restore_operation "Panel Version Check" "SUCCESS" "Версии совпадают: $current_panel_version"
                ;;
            1)
                echo -e "\033[1;33m⚠️  Совместимость версий панели: Незначительное различие\033[0m"
                echo -e "\033[38;5;244m   Панель в бэкапе: $backup_panel_version\033[0m"
                echo -e "\033[38;5;244m   Текущая панель: $current_panel_version\033[0m"
                echo -e "\033[38;5;244m   Восстановление должно работать, но проверьте функциональность после\033[0m"
                log_restore_operation "Panel Version Check" "WARNING" "Незначительное различие версий: $backup_panel_version -> $current_panel_version"
                ;;
            3)
                echo -e "\033[1;31m❌ КРИТИЧНО: Обнаружена несовместимость версий панели!\033[0m"
                echo -e "\033[38;5;244m   Версия панели в бэкапе: $backup_panel_version\033[0m"
                echo -e "\033[38;5;244m   Текущая версия панели: $current_panel_version\033[0m"
                echo -e "\033[1;31m   ⚠️  Восстановление этого бэкапа может сломать вашу панель!\033[0m"
                echo
                echo -e "\033[1;37m🔧 Рекомендуемые действия:\033[0m"
                echo -e "\033[38;5;250m   1. Сначала установите панель Remnawave v$backup_panel_version\033[0m"
                echo -e "\033[38;5;250m   2. Или создайте новый бэкап из текущей панели v$current_panel_version\033[0m"
                echo
                read -p "Продолжить в любом случае? Это ОПАСНО! [y/N]: " -r force_continue
                if [[ ! $force_continue =~ ^[Yy]$ ]]; then
                    log_restore_operation "Panel Version Check" "ERROR" "Пользователь отменил из-за несовместимости версий"
                    echo -e "\033[1;33m⚠️  Восстановление отменено для безопасности\033[0m"
                    return 2
                fi
                log_restore_operation "Panel Version Check" "WARNING" "Пользователь принудительно продолжил несмотря на несовместимость"
                ;;
        esac
    elif [ "$backup_panel_version" = "unknown" ]; then
        echo -e "\033[1;33m⚠️  Версия панели неизвестна в бэкапе - невозможно проверить совместимость\033[0m"
        log_restore_operation "Panel Version Check" "WARNING" "Неизвестная версия панели в бэкапе"
    elif [ "$current_panel_version" = "unknown" ]; then
        echo -e "\033[1;33m⚠️  Текущая версия панели неизвестна - невозможно проверить совместимость\033[0m"
        log_restore_operation "Panel Version Check" "WARNING" "Неизвестная текущая версия панели"
    fi
    
    # Проверка версии скрипта (менее критично)
    if [ "$backup_script_version" != "unknown" ] && [ "$backup_script_version" != "$current_script_version" ]; then
        local backup_major=$(echo "$backup_script_version" | cut -d'.' -f1)
        local current_major=$(echo "$current_script_version" | cut -d'.' -f1)
        
        if [ "$backup_major" != "$current_major" ]; then
            log_restore_operation "Script Version Check" "WARNING" "Несовпадение мажорных версий — бэкап может быть несовместим"
            echo -e "\033[1;33m⚠️  Предупреждение о совместимости версий скрипта:\033[0m"
            echo -e "\033[38;5;244m   Скрипт в бэкапе: $backup_script_version\033[0m"
            echo -e "\033[38;5;244m   Текущий скрипт: $current_script_version\033[0m"
            return 1
        else
            log_restore_operation "Script Version Check" "INFO" "Незначительная разница версий скрипта, должно быть совместимо"
        fi
    fi
    
    return 0
}

# Функция проверки системных ресурсов
check_system_resources() {
    local backup_file="$1"
    local target_dir="$2"
    
    echo -e "\033[38;5;250m📝 Проверка системных ресурсов...\033[0m"
    
    # Размер бэкапа
    local backup_size=0
    if [ -f "$backup_file" ]; then
        backup_size=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
    fi
    
    # Доступное место на диске (в KB)
    local available_space=$(df "$(dirname "$target_dir")" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    local available_bytes=$((available_space * 1024))
    
    # Проверяем что места достаточно (с запасом 50% для extraction и временных файлов)
    local required_space=$((backup_size * 15 / 10))
    
    if [ "$available_bytes" -lt "$required_space" ] && [ "$backup_size" -gt 0 ]; then
        local backup_mb=$((backup_size / 1024 / 1024))
        local available_mb=$((available_bytes / 1024 / 1024))
        echo -e "\033[1;31m❌ Недостаточно места на диске!\033[0m"
        echo -e "\033[38;5;244m   Требуется: ~${backup_mb}MB + 50% буфер, Доступно: ${available_mb}MB\033[0m"
        return 1
    fi
    
    # Проверка памяти (базовая)
    local available_memory=$(free -m 2>/dev/null | awk 'NR==2{print $7}' || echo "1000")
    if [ "$available_memory" -lt 500 ]; then
        echo -e "\033[1;33m⚠️  Мало доступной памяти (${available_memory}MB), восстановление может быть медленным\033[0m"
    fi
    
    echo -e "\033[1;32m✅ Проверка системных ресурсов пройдена\033[0m"
    return 0
}

# Функция валидации SQL содержимого
validate_sql_integrity() {
    local sql_file="$1"
    
    if [ ! -f "$sql_file" ]; then
        return 1
    fi
    
    echo -e "\033[38;5;250m📝 Проверка целостности SQL файла...\033[0m"
    
    # Проверка размера файла
    local file_size=$(wc -c < "$sql_file" 2>/dev/null || echo "0")
    if [ "$file_size" -lt 100 ]; then
        echo -e "\033[1;31m❌ SQL файл слишком мал (${file_size} байт)\033[0m"
        return 1
    fi
    
    # Проверка заголовков PostgreSQL (более мягкая проверка)
    local pg_header_found=false
    if head -20 "$sql_file" | grep -qi "PostgreSQL\|postgres\|pg_dump"; then
        pg_header_found=true
    fi
    
    # Проверка на наличие критических команд
    local has_structure=false
    local has_data=false
    local command_count=0
    
    # Более детальная проверка команд
    if grep -qE "CREATE\s+(TABLE|DATABASE|SCHEMA|INDEX)" "$sql_file" 2>/dev/null; then
        has_structure=true
        command_count=$((command_count + 1))
    fi
    
    if grep -qE "ALTER\s+(TABLE|DATABASE)" "$sql_file" 2>/dev/null; then
        has_structure=true
        command_count=$((command_count + 1))
    fi
    
    if grep -qE "INSERT\s+INTO|COPY\s+.*FROM\s+stdin" "$sql_file" 2>/dev/null; then
        has_data=true
        command_count=$((command_count + 1))
    fi
    
    # Проверяем специфичные для RemnaWave таблицы (если есть)
    local remnawave_tables=false
    if grep -qiE "(users|nodes|traffic|settings)" "$sql_file" 2>/dev/null; then
        remnawave_tables=true
    fi
    
    # Результаты проверки
    if [ "$has_structure" = false ] && [ "$has_data" = false ]; then
        echo -e "\033[1;31m❌ SQL файл не содержит валидных команд базы данных\033[0m"
        return 1
    fi
    
    if [ "$pg_header_found" = false ] && [ "$command_count" -lt 3 ]; then
        echo -e "\033[1;33m⚠️  Предупреждение: SQL файл может не быть стандартным дампом PostgreSQL\033[0m"
    fi
    
    if [ "$remnawave_tables" = true ]; then
        echo -e "\033[1;32m✅ Обнаружены таблицы базы данных RemnaWave\033[0m"
    fi
    
    # Проверка на SQL инъекции и подозрительные команды
    if grep -qi "drop database\|rm -rf\|system\|exec\|eval" "$sql_file" 2>/dev/null; then
        echo -e "\033[1;33m⚠️  Предупреждение: SQL файл содержит потенциально опасные команды\033[0m"
    fi
    
    echo -e "\033[1;32m✅ Проверка SQL файла пройдена\033[0m"
    return 0
}
# Функция валидации извлеченного бэкапа
validate_extracted_backup() {
    local target_dir="$1"
    local backup_type="${2:-full}"
    local app_name="$3"
    
    echo -e "\033[38;5;250m📝 Проверка извлеченного бэкапа...\033[0m"
    
    local validation_errors=0
    
    # Проверка структуры файлов для full backup
    if [ "$backup_type" = "full" ]; then
        # Обязательные файлы: docker-compose.yml и .env
        if [ ! -f "$target_dir/docker-compose.yml" ]; then
            echo -e "\033[1;31m❌ Отсутствует критический файл: docker-compose.yml\033[0m"
            validation_errors=$((validation_errors + 1))
        else
            # Проверка синтаксиса docker-compose.yml
            if ! docker compose -f "$target_dir/docker-compose.yml" config >/dev/null 2>&1; then
                echo -e "\033[1;31m❌ Неверный синтаксис docker-compose.yml\033[0m"
                validation_errors=$((validation_errors + 1))
            fi
        fi
        
        # .env является обязательным для RemnaWave (содержит настройки БД)
        if [ ! -f "$target_dir/.env" ]; then
            echo -e "\033[1;31m❌ Отсутствует критический файл: .env\033[0m"
            echo -e "\033[38;5;244m   Файл .env необходим для конфигурации базы данных\033[0m"
            validation_errors=$((validation_errors + 1))
        else
            # Проверяем что .env содержит необходимые переменные для PostgreSQL
            local required_vars=("POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB")
            for var in "${required_vars[@]}"; do
                if ! grep -q "^${var}=" "$target_dir/.env" 2>/dev/null; then
                    echo -e "\033[1;33m⚠️  Предупреждение: в .env отсутствует переменная: $var\033[0m"
                fi
            done
        fi
    fi
    
    # Проверка файлов базы данных (может быть в разных форматах и с разными именами)
    local database_files_found=()
    
    # Поиск файлов базы данных более надежным способом
    # Ищем все SQL файлы и их сжатые версии
    mapfile -t database_files_found < <(
        find "$target_dir" -maxdepth 1 -type f \( \
            -name "*.sql" -o \
            -name "*.sql.gz" -o \
            -name "*.sql.bz2" -o \
            -name "*.sql.xz" \
        \) -printf '%f\n' 2>/dev/null | sort
    )
    
    # Если find не поддерживает -printf (например, на macOS), используем альтернативный метод
    if [ ${#database_files_found[@]} -eq 0 ]; then
        while IFS= read -r -d '' file; do
            database_files_found+=("$(basename "$file")")
        done < <(find "$target_dir" -maxdepth 1 -type f \( \
            -name "*.sql" -o \
            -name "*.sql.gz" -o \
            -name "*.sql.bz2" -o \
            -name "*.sql.xz" \
        \) -print0 2>/dev/null | sort -z)
    fi
    
    if [ ${#database_files_found[@]} -gt 0 ]; then
        echo -e "\033[1;32m✅ Найдены файлы базы данных: ${database_files_found[*]}\033[0m"
        
        # Валидируем найденные файлы БД
        for db_file in "${database_files_found[@]}"; do
            local full_db_path="$target_dir/$db_file"
            
            # Если файл сжат (.gz), временно разархивируем для проверки
            if [[ "$db_file" == *.gz ]]; then
                local temp_sql="/tmp/validate_db_$$.sql"
                if gunzip -c "$full_db_path" > "$temp_sql" 2>/dev/null; then
                    if ! validate_sql_integrity "$temp_sql"; then
                        echo -e "\033[1;31m❌ Не удалось проверить сжатый файл базы данных: $db_file\033[0m"
                        validation_errors=$((validation_errors + 1))
                    fi
                    rm -f "$temp_sql"
                else
                    echo -e "\033[1;31m❌ Не удалось распаковать файл базы данных: $db_file\033[0m"
                    validation_errors=$((validation_errors + 1))
                fi
            else
                # Обычный SQL файл
                if ! validate_sql_integrity "$full_db_path"; then
                    echo -e "\033[1;31m❌ Не удалось проверить файл базы данных: $db_file\033[0m"
                    validation_errors=$((validation_errors + 1))
                fi
            fi
        done
    elif [ "$backup_type" = "full" ]; then
        echo -e "\033[1;33m⚠️  Предупреждение: В бэкапе не найдены файлы базы данных\033[0m"
        echo -e "\033[38;5;244m   Ожидаемые файлы: database.sql, db_backup.sql или сжатые варианты\033[0m"
    fi
    
    # Проверка прав доступа
    if [ ! -r "$target_dir" ] || [ ! -w "$target_dir" ]; then
        echo -e "\033[1;31m❌ Недостаточно прав для целевой директории\033[0m"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        echo -e "\033[1;32m✅ Проверка бэкапа пройдена\033[0m"
        log_restore_operation "Backup Validation" "SUCCESS" "Все проверки валидации пройдены"
        return 0
    else
        echo -e "\033[1;31m❌ Проверка бэкапа не пройдена ($validation_errors ошибок)\033[0m"
        log_restore_operation "Backup Validation" "ERROR" "Найдено ошибок валидации: $validation_errors"
        return 1
    fi
}

# Функция создания safety backup перед восстановлением
create_safety_backup() {
    local target_dir="$1"
    local app_name="$2"
    local backup_dir="$3"
    
    if [ ! -d "$target_dir" ]; then
        echo -e "\033[38;5;244m   Существующая установка не найдена, пропускаем резервное копирование\033[0m"
        log_restore_operation "Safety Backup" "INFO" "Существующая установка не найдена"
        return 0
    fi
    
    echo -e "\033[38;5;250m📝 Создание резервной копии перед восстановлением...\033[0m"
    
    local safety_backup_dir="$backup_dir/safety_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$safety_backup_dir"
    
    # Создаем дамп базы данных если она работает
    if [ -f "$target_dir/docker-compose.yml" ]; then
        cd "$target_dir"
        local db_container="${app_name}-db"
        
        if docker compose ps -q "$db_container" 2>/dev/null | grep -q .; then
            echo -e "\033[38;5;244m   Создание дампа базы данных...\033[0m"
            
            local postgres_user="postgres"
            local postgres_password="postgres"
            local postgres_db="postgres"
            
            # Читаем настройки из .env если доступны
            if [ -f "$target_dir/.env" ]; then
                postgres_user=$(grep "^POSTGRES_USER=" "$target_dir/.env" | cut -d'=' -f2 2>/dev/null || echo "postgres")
                postgres_password=$(grep "^POSTGRES_PASSWORD=" "$target_dir/.env" | cut -d'=' -f2 2>/dev/null || echo "postgres")
                postgres_db=$(grep "^POSTGRES_DB=" "$target_dir/.env" | cut -d'=' -f2 2>/dev/null || echo "postgres")
            fi
            
            if docker exec -e PGPASSWORD="$postgres_password" "$db_container" \
                pg_dump -U "$postgres_user" -d "$postgres_db" --clean --create > "$safety_backup_dir/database_safety.sql" 2>/dev/null; then
                echo -e "\033[1;32m✅ Резервная копия базы данных создана\033[0m"
                log_restore_operation "Database Safety Backup" "SUCCESS" "Дамп базы данных создан"
            else
                echo -e "\033[1;33m⚠️  Не удалось создать безопасную резервную копию базы данных\033[0m"
                log_restore_operation "Database Safety Backup" "WARNING" "Не удалось создать дамп базы данных"
            fi
        fi
    fi
    
    # Копируем важные файлы конфигурации
    echo -e "\033[38;5;244m   Резервное копирование конфигурационных файлов...\033[0m"
    
    local files_copied=0
    for file in docker-compose.yml .env config.json settings.yml remnawave.conf; do
        if [ -f "$target_dir/$file" ]; then
            cp "$target_dir/$file" "$safety_backup_dir/" 2>/dev/null && files_copied=$((files_copied + 1))
        fi
    done
    
    # Копируем важные директории если они небольшие
    for dir in certs ssl certificates config configs custom scripts; do
        if [ -d "$target_dir/$dir" ]; then
            local dir_size=$(du -s "$target_dir/$dir" 2>/dev/null | cut -f1 || echo "999999")
            if [ "$dir_size" -lt 10240 ]; then  # меньше 10MB
                cp -r "$target_dir/$dir" "$safety_backup_dir/" 2>/dev/null && files_copied=$((files_copied + 1))
            fi
        fi
    done
    
    # Сохраняем информацию о safety backup
    echo "$safety_backup_dir" > "/tmp/safety_backup_location_$$"
    
    echo -e "\033[1;32m✅ Создана резервная копия ($files_copied объектов): $safety_backup_dir\033[0m"
    log_restore_operation "Safety Backup" "SUCCESS" "$files_copied файлов сохранено в $safety_backup_dir"
    return 0
}

# Функция отката в случае неудачного восстановления
rollback_from_safety_backup() {
    local target_dir="$1"
    local app_name="$2"
    
    if [ ! -f "/tmp/safety_backup_location_$$" ]; then
        echo -e "\033[1;31m❌ Путь к резервной копии для отката не найден\033[0m"
        log_restore_operation "Rollback" "ERROR" "Путь к резервной копии не найден"
        return 1
    fi
    
    local safety_backup_dir=$(cat "/tmp/safety_backup_location_$$")
    
    if [ ! -d "$safety_backup_dir" ]; then
        echo -e "\033[1;31m❌ Директория резервной копии не найдена: $safety_backup_dir\033[0m"
        log_restore_operation "Rollback" "ERROR" "Директория резервной копии не найдена"
        return 1
    fi
    
    echo -e "\033[38;5;250m📝 Откат из резервной копии...\033[0m"
    log_restore_operation "Rollback" "STARTED" "Rolling back from $safety_backup_dir"
    
    # Останавливаем сервисы
    if [ -f "$target_dir/docker-compose.yml" ]; then
        cd "$target_dir"
        docker compose down 2>/dev/null
    fi
    
    # Восстанавливаем файлы из safety backup
    local files_restored=0
    for file in docker-compose.yml .env config.json settings.yml remnawave.conf; do
        if [ -f "$safety_backup_dir/$file" ]; then
            cp "$safety_backup_dir/$file" "$target_dir/" 2>/dev/null && files_restored=$((files_restored + 1))
        fi
    done
    
    # Восстанавливаем директории
    for dir in certs ssl certificates config configs custom scripts; do
        if [ -d "$safety_backup_dir/$dir" ]; then
            rm -rf "$target_dir/$dir" 2>/dev/null
            cp -r "$safety_backup_dir/$dir" "$target_dir/" 2>/dev/null && files_restored=$((files_restored + 1))
        fi
    done
    
    # Восстанавливаем базу данных если есть
    if [ -f "$safety_backup_dir/database_safety.sql" ] && [ -f "$target_dir/docker-compose.yml" ]; then
        echo -e "\033[38;5;244m   Восстановление базы данных из резервной копии...\033[0m"
        
        cd "$target_dir"
        docker compose up -d "${app_name}-db" 2>/dev/null
        
        # Ждем готовности БД
        local attempts=0
        while [ $attempts -lt 15 ]; do
            if docker exec "${app_name}-db" pg_isready -U postgres >/dev/null 2>&1; then
                break
            fi
            sleep 2
            attempts=$((attempts + 1))
        done
        
        if [ $attempts -lt 15 ]; then
            if docker exec -i "${app_name}-db" psql -U postgres < "$safety_backup_dir/database_safety.sql" >/dev/null 2>&1; then
                echo -e "\033[1;32m✅ База данных успешно откачена\033[0m"
                log_restore_operation "Database Rollback" "SUCCESS" "База данных восстановлена из резервной копии"
            else
                echo -e "\033[1;33m⚠️  При откате базы данных возникли проблемы\033[0m"
                log_restore_operation "Database Rollback" "WARNING" "При откате базы данных возникли проблемы"
            fi
        fi
        
        docker compose down 2>/dev/null
    fi
    
    echo -e "\033[1;32m✅ Откат завершен ($files_restored элементов восстановлено)\033[0m"
    log_restore_operation "Rollback" "SUCCESS" "Восстановлено файлов: $files_restored"
    
    # Очищаем временные файлы
    rm -f "/tmp/safety_backup_location_$$"
    
    return 0
}

# Функция проверки целостности после восстановления
verify_restore_integrity() {
    local target_dir="$1"
    local app_name="$2"
    local backup_type="${3:-full}"
    
    echo -e "\033[38;5;250m📝 Проверка целостности восстановления...\033[0m"
    
    local integrity_score=0
    local max_score=10
    local issues=()
    
    # Проверка файлов (2 балла)
    if [ -f "$target_dir/docker-compose.yml" ]; then
        integrity_score=$((integrity_score + 1))
        if docker compose -f "$target_dir/docker-compose.yml" config >/dev/null 2>&1; then
            integrity_score=$((integrity_score + 1))
        else
            issues+=("docker-compose.yml syntax error")
        fi
    else
        issues+=("docker-compose.yml missing")
    fi
    
    # Проверка запуска сервисов (4 балла)
    if [ -f "$target_dir/docker-compose.yml" ]; then
        cd "$target_dir"
        if docker compose up -d >/dev/null 2>&1; then
            integrity_score=$((integrity_score + 2))
            
            # Ждем немного и проверяем статус
            sleep 8
            local running_services=$(docker compose ps -q 2>/dev/null | wc -l)
            local healthy_services=0
            
            for container_id in $(docker compose ps -q 2>/dev/null); do
                local status=$(docker inspect "$container_id" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
                if [ "$status" = "running" ]; then
                    healthy_services=$((healthy_services + 1))
                fi
            done
            
            if [ "$running_services" -gt 0 ] && [ "$healthy_services" -gt 0 ]; then
                if [ "$healthy_services" -eq "$running_services" ]; then
                    integrity_score=$((integrity_score + 2))
                else
                    integrity_score=$((integrity_score + 1))
                    issues+=("some services not running ($healthy_services/$running_services)")
                fi
            else
                issues+=("no services running")
            fi
        else
            issues+=("failed to start services")
        fi
    fi
    
    # Проверка базы данных (2 балла)
    if [ "$backup_type" = "full" ] || [ "$backup_type" = "database" ]; then
        local db_container="${app_name}-db"
        if docker exec "$db_container" pg_isready -U postgres >/dev/null 2>&1; then
            integrity_score=$((integrity_score + 1))
            
            # Проверяем что в БД есть данные
            local table_count=$(docker exec -e PGPASSWORD="postgres" "$db_container" \
                psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")
            
            if [ "$table_count" -gt 0 ]; then
                integrity_score=$((integrity_score + 1))
            else
                issues+=("database appears empty")
            fi
        else
            issues+=("database not responding")
        fi
    fi
    
    # Проверка сети и доступности (2 балла)
    local main_container="${app_name}-app"
    if docker exec "$main_container" echo "test" >/dev/null 2>&1; then
        integrity_score=$((integrity_score + 1))
        
        # Проверяем внутреннюю связность
        if docker exec "$main_container" nc -z "${app_name}-db" 5432 >/dev/null 2>&1; then
            integrity_score=$((integrity_score + 1))
        else
            issues+=("network connectivity issues")
        fi
    else
        issues+=("main application container not responding")
    fi
    
    # Выводим результат
    local percentage=$((integrity_score * 100 / max_score))
    
    # Детальный отчет об обнаруженных проблемах
    if [ ${#issues[@]} -gt 0 ]; then
        echo -e "\033[38;5;244m   Обнаружены проблемы:\033[0m"
        for issue in "${issues[@]}"; do
            echo -e "\033[38;5;244m   - $issue\033[0m"
        done
    fi
    
    if [ $percentage -ge 80 ]; then
        echo -e "\033[1;32m✅ Проверка целостности восстановления пройдена: $integrity_score/$max_score ($percentage%)\033[0m"
        log_restore_operation "Integrity Check" "SUCCESS" "$integrity_score/$max_score ($percentage%)"
        return 0
    elif [ $percentage -ge 60 ]; then
        echo -e "\033[1;33m⚠️  Предупреждение проверки целостности восстановления: $integrity_score/$max_score ($percentage%)\033[0m"
        log_restore_operation "Integrity Check" "WARNING" "$integrity_score/$max_score ($percentage%) - проблем: ${#issues[@]}"
        return 1
    else
        echo -e "\033[1;31m❌ Проверка целостности восстановления не пройдена: $integrity_score/$max_score ($percentage%)\033[0m"
        log_restore_operation "Integrity Check" "ERROR" "$integrity_score/$max_score ($percentage%) - проблем: ${#issues[@]}"
        return 2
    fi
}

# ===== END RESTORE VALIDATION AND SAFETY FUNCTIONS =====

schedule_create_backup_script() {
    local config_dir="$(dirname "$BACKUP_CONFIG_FILE")"
    mkdir -p "$config_dir"
    
    # Проверяем и исправляем поврежденный конфиг если нужно
    validate_and_fix_backup_config
    
    cat > "$BACKUP_SCRIPT_FILE" <<'BACKUP_SCRIPT_EOF'
#!/bin/bash

# Backup Script Version - used for compatibility checking
BACKUP_SCRIPT_VERSION="1.0.1"
BACKUP_SCRIPT_DATE="$(date '+%Y-%m-%d')"

# Читаем конфигурацию backup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/backup-config.json"
LOG_FILE="$SCRIPT_DIR/logs/backup.log"

# Функция логирования
log_message() {
    # Создаем директорию для логов если не существует
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Функция для проверки доступности команд
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_message "ERROR: Требуемая команда '$1' не найдена"
        exit 1
    fi
}

# Проверяем необходимые команды
check_command docker
check_command jq

# Определяем переменные из конфигурации
if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERROR: Конфигурация бэкапа не найдена: $CONFIG_FILE"
    exit 1
fi

# Проверяем валидность JSON конфигурации
if ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
    log_message "ERROR: Файл конфигурации бэкапа повреждён: $CONFIG_FILE"
    log_message "Please run the main script to recreate configuration"
    exit 1
fi

APP_NAME=$(jq -r '.app_name // "remnawave"' "$CONFIG_FILE")
APP_DIR="/opt/$APP_NAME"
BACKUP_DIR="$APP_DIR/backups"
TEMP_BACKUP_ROOT="/tmp/${APP_NAME}_backup"
COMPRESS_ENABLED=$(jq -r '.compression.enabled // true' "$CONFIG_FILE")
TELEGRAM_ENABLED=$(jq -r '.telegram.enabled // false' "$CONFIG_FILE")

# Создаем директории для бэкапов
mkdir -p "$BACKUP_DIR"
mkdir -p "$TEMP_BACKUP_ROOT"

# Генерируем имя бэкапа
timestamp=$(date +%Y%m%d_%H%M%S)
backup_name="remnawave_scheduled_${timestamp}"
temp_backup_dir="$TEMP_BACKUP_ROOT/temp_$timestamp"

log_message "Starting scheduled backup..."
log_message "Creating full system backup: $backup_name"

# Создаем временную директорию для сборки бэкапа
mkdir -p "$temp_backup_dir"

# Шаг 1: Экспорт базы данных
log_message "Step 1: Exporting database..."

# Читаем параметры БД из .env файла
postgres_user="postgres"
postgres_password="postgres"
postgres_db="postgres"

if [ -f "$APP_DIR/.env" ]; then
    postgres_user=$(grep "^POSTGRES_USER=" "$APP_DIR/.env" | cut -d'=' -f2 2>/dev/null | sed 's/^"//;s/"$//' || echo "postgres")
    postgres_password=$(grep "^POSTGRES_PASSWORD=" "$APP_DIR/.env" | cut -d'=' -f2 2>/dev/null | sed 's/^"//;s/"$//' || echo "postgres")
    postgres_db=$(grep "^POSTGRES_DB=" "$APP_DIR/.env" | cut -d'=' -f2 2>/dev/null | sed 's/^"//;s/"$//' || echo "postgres")
fi

db_container="${APP_NAME}-db"
if ! docker exec "$db_container" pg_isready -U "$postgres_user" >/dev/null 2>&1; then
    log_message "ERROR: Контейнер базы данных не готов"
    rm -rf "$temp_backup_dir"
    exit 1
fi

database_file="$temp_backup_dir/database.sql"
if docker exec -e PGPASSWORD="$postgres_password" "$db_container" \
    pg_dump -U "$postgres_user" -d "$postgres_db" --clean --if-exists > "$database_file" 2>/dev/null; then
    
    # ИСПРАВЛЕНО: убрал local
    db_size=$(du -sh "$database_file" | cut -f1)
    log_message "Database exported successfully ($db_size)"
else
    log_message "ERROR: Экспорт базы данных не удался"
    rm -rf "$temp_backup_dir"
    exit 1
fi

# Шаг 2: Копирование конфигурационных файлов прямо в корень
log_message "Step 2: Creating application configuration backup..."

# Копируем всю структуру кроме некоторых директорий
log_message "Copying application configuration files..."

if command -v rsync >/dev/null 2>&1; then
    # rsync доступен, используем его с правильными исключениями
    rsync -av \
        --exclude='backups/' \
        --exclude='logs/' \
        --exclude='temp/' \
        --exclude='*.log' \
        --exclude='*.tmp' \
        --exclude='.git/' \
        "$APP_DIR/" \
        "$temp_backup_dir/" 2>/dev/null
    copy_result=$?
else
    # Используем улучшенный cp метод без рекурсии
    log_message "rsync not available, using selective copy method"
    copy_result=0
    
    # Копируем файлы по одному, исключая проблемные директории
    find "$APP_DIR" -maxdepth 1 -type f \( \
        -name "*.json" -o \
        -name "*.yml" -o \
        -name "*.yaml" -o \
        -name "*.env*" -o \
        -name "*.conf" -o \
        -name "*.ini" -o \
        -name "*.sh" -o \
        -name "docker-compose*" \
    \) -exec cp {} "$temp_backup_dir/" \; 2>/dev/null || true
    
    # Копируем важные директории если они существуют (исключая backups, logs, temp)
    for dir in certs ssl certificates config configs custom scripts; do
        if [ -d "$APP_DIR/$dir" ]; then
            cp -r "$APP_DIR/$dir" "$temp_backup_dir/" 2>/dev/null || true
        fi
    done
    
    # Проверяем что хотя бы docker-compose.yml скопирован
    if [ ! -f "$temp_backup_dir/docker-compose.yml" ]; then
        copy_result=1
        log_message "ERROR: Критический файл docker-compose.yml не найден или не удалось скопировать"
    fi
fi

if [ $copy_result -eq 0 ]; then
    app_files_count=$(find "$temp_backup_dir" -type f | wc -l)
    log_message "Application files copied successfully ($app_files_count files)"
else
    log_message "ERROR: Не удалось скопировать файлы приложения"
    rm -rf "$temp_backup_dir"
    exit 1
fi

# Шаг 3: Добавляем скрипт управления
log_message "Step 3: Including management script..."

script_source="/usr/local/bin/$APP_NAME"
if [ -f "$script_source" ]; then
    cp "$script_source" "$temp_backup_dir/install-script.sh"
    log_message "Management script included"
else
    log_message "WARNING: Management script not found at $script_source"
fi

# Шаг 4: Создаем метаданные
log_message "Step 4: Creating backup metadata..."

metadata_file="$temp_backup_dir/backup-metadata.json"

# Получаем версию панели
panel_version=$(docker exec "${APP_NAME}" awk -F'"' '/"version"/{print $4; exit}' package.json 2>/dev/null || echo "unknown")

cat > "$metadata_file" <<METADATA_EOF
{
    "backup_type": "full_system",
    "app_name": "$APP_NAME",
    "timestamp": "$timestamp",
    "date_created": "$(date -Iseconds)",
    "script_version": "$(grep '^SCRIPT_VERSION=' "$script_source" | cut -d'=' -f2 | tr -d '"' || echo 'unknown')",
    "panel_version": "$panel_version",
    "database_included": true,
    "application_files_included": true,
    "management_script_included": $([ -f "$temp_backup_dir/install-script.sh" ] && echo "true" || echo "false"),
    "docker_images": {
$(docker images --format '        "{{.Repository}}:{{.Tag}}": "{{.ID}}"' | grep -E "(remnawave|postgres|valkey)" | head -10 || echo '')
    },
    "system_info": {
        "hostname": "$(hostname)",
        "os": "$(lsb_release -d 2>/dev/null | cut -f2 || uname -s)",
        "docker_version": "$(docker --version | cut -d' ' -f3 | tr -d ',')",
        "backup_size_uncompressed": "$(du -sh "$temp_backup_dir" | cut -f1)"
    }
}
METADATA_EOF

log_message "Backup metadata created"

# Шаг 5: Сжатие бэкапа (если включено)
if [ "$COMPRESS_ENABLED" = "true" ]; then
    log_message "Step 5: Compressing backup..."
    
    cd "$(dirname "$temp_backup_dir")"
    if tar -czf "$BACKUP_DIR/${backup_name}.tar.gz" -C "$TEMP_BACKUP_ROOT" "temp_$timestamp" 2>/dev/null; then
        compressed_size=$(du -sh "$BACKUP_DIR/${backup_name}.tar.gz" | cut -f1)
        log_message "Backup compressed successfully ($compressed_size)"
        
        # Удаляем временную директорию
        rm -rf "$temp_backup_dir"
        
        final_backup_file="$BACKUP_DIR/${backup_name}.tar.gz"
    else
        log_message "ERROR: Сжатие бэкапа не удалось"
        rm -rf "$temp_backup_dir"
        exit 1
    fi
else
    # Перемещаем несжатую директорию в финальное местоположение  
    mv "$temp_backup_dir" "$BACKUP_DIR/$backup_name"
    
    final_backup_file="$BACKUP_DIR/$backup_name"
    backup_size=$(du -sh "$final_backup_file" | cut -f1)
    log_message "Backup created successfully: $backup_name ($backup_size)"
fi

# Шаг 6: Отправка в Telegram (если включено)
if [ "$TELEGRAM_ENABLED" = "true" ]; 
    then    log_message "Step 6: Sending backup to Telegram..."
    
    telegram_bot_token=$(jq -r '.telegram.bot_token' "$CONFIG_FILE")
    telegram_chat_id=$(jq -r '.telegram.chat_id' "$CONFIG_FILE")
    telegram_thread_id=$(jq -r '.telegram.thread_id' "$CONFIG_FILE")
    
    if [ "$telegram_bot_token" != "null" ] && [ "$telegram_chat_id" != "null" ]; then
        # Отправляем информацию о бэкапе
        backup_info="🤖 *Scheduled Backup Created*

📦 *Name:* \`$backup_name\`
📅 *Date:* $(date '+%Y-%m-%d %H:%M:%S')
🔢 *Size:* $(du -sh "$final_backup_file" | cut -f1)
🏷️ *Type:* Full System Backup
� *Panel:* v$panel_version
�🖥️ *Server:* $(hostname)
✅ *Status:* Success"
          # Если файл меньше 50MB, отправляем его
        file_size_bytes=$(stat -c%s "$final_backup_file" 2>/dev/null || echo "0")
        max_size=$((50 * 1024 * 1024))  # 50MB в байтах
        
        if [ "$file_size_bytes" -lt "$max_size" ] && [[ "$final_backup_file" =~ \.tar\.gz$ ]]; then
            log_message "Sending file via Telegram API: $(basename "$final_backup_file")"
            
            # Отправляем с учетом thread_id
            if [ -n "$telegram_thread_id" ] && [ "$telegram_thread_id" != "null" ]; then
                log_message "Sending to thread: $telegram_thread_id"
                curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendDocument" \
                    -F "chat_id=$telegram_chat_id" \
                    -F "document=@$final_backup_file" \
                    -F "caption=$backup_info" \
                    -F "parse_mode=Markdown" \
                    -F "message_thread_id=$telegram_thread_id" >/dev/null
            else
                curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendDocument" \
                    -F "chat_id=$telegram_chat_id" \
                    -F "document=@$final_backup_file" \
                    -F "caption=$backup_info" \
                    -F "parse_mode=Markdown" >/dev/null
            fi
            
            if [ $? -eq 0 ]; then
                log_message "File sent successfully to Telegram"
            else
                log_message "ERROR: Не удалось отправить файл в Telegram"
            fi
        else
            log_message "Sending backup notification to Telegram (file too large for upload)"
            
            # Отправляем текстовое сообщение с учетом thread_id
            if [ -n "$telegram_thread_id" ] && [ "$telegram_thread_id" != "null" ]; then
                log_message "Sending to thread: $telegram_thread_id"
                curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" \
                    -F "chat_id=$telegram_chat_id" \
                    -F "text=$backup_info" \
                    -F "parse_mode=Markdown" \
                    -F "message_thread_id=$telegram_thread_id" >/dev/null
            else
                curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" \
                    -F "chat_id=$telegram_chat_id" \
                    -F "text=$backup_info" \
                    -F "parse_mode=Markdown" >/dev/null
            fi
            
            if [ $? -eq 0 ]; then
                log_message "Backup notification sent successfully to Telegram"
            else
                log_message "ERROR: Не удалось отправить уведомление в Telegram"
            fi
        fi
        
        log_message "Backup sent to Telegram successfully"
    else
        log_message "WARNING: Telegram credentials not configured"
    fi
fi

# Шаг 7: Очистка старых бэкапов
retention_days=$(jq -r '.retention.days // 7' "$CONFIG_FILE")
min_backups=$(jq -r '.retention.min_backups // 3' "$CONFIG_FILE")

log_message "Cleaning up backups older than $retention_days days..."

# Находим старые файлы
find "$BACKUP_DIR" -name "remnawave_scheduled_*" -type f -mtime +$retention_days -delete 2>/dev/null
find "$BACKUP_DIR" -name "remnawave_scheduled_*" -type d -mtime +$retention_days -exec rm -rf {} + 2>/dev/null

# Проверяем минимальное количество
current_backups=$(ls -1 "$BACKUP_DIR"/remnawave_scheduled_* 2>/dev/null | wc -l)
if [ "$current_backups" -lt "$min_backups" ]; then
    log_message "WARNING: Only $current_backups backups remain (minimum: $min_backups)"
fi

log_message "Old backups cleaned up"
log_message "Backup process completed successfully"

# Очистка временной директории бэкапа
log_message "Cleaning up temporary backup directory..."
rm -rf "$TEMP_BACKUP_ROOT" 2>/dev/null || true

BACKUP_SCRIPT_EOF

    chmod +x "$BACKUP_SCRIPT_FILE"
    echo -e "\033[1;32m✅ Скрипт бэкапа создан: $BACKUP_SCRIPT_FILE\033[0m"
}
# Добавляем после функции backup_command:

restore_command() {
    check_running_as_root
    
    local backup_file=""
    local target_app_name="$APP_NAME"
    local target_base_dir="/opt"  
    local force_restore=false
    local database_only=false
    local skip_install=false
    
    # Парсинг аргументов
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --file|-f) 
                backup_file="$2"
                shift 2
                ;;
            --name|-n)
                # Имя приложения принудительно фиксировано как 'remnawave'
                echo -e "\033[38;5;244m⚠️  Параметр --name игнорируется. Используется имя 'remnawave'.\033[0m"
                shift
                shift
                ;;
            --path|-p)  
                target_base_dir="$2"
                shift 2
                ;;
            --database-only)
                database_only=true
                shift
                ;;
            --skip-install)
                skip_install=true
                shift
                ;;
            --force)
                force_restore=true
                shift
                ;;
            -h|--help) 
                echo -e "\033[1;37m🔄 Система восстановления Remnawave\033[0m"
                echo
        echo -e "\033[1;37mИспользование:\033[0m"
                echo -e "  \033[38;5;15m$APP_NAME restore\033[0m [\033[38;5;244moptions\033[0m]"
                echo
                echo -e "\033[1;37mОпции:\033[0m"
                echo -e "  \033[38;5;244m--file, -f <path>\033[0m     Восстановить из конкретного файла бэкапа"
                echo -e "  \033[38;5;244m--name, -n <name>\033[0m     Установить пользовательское имя приложения (по умолчанию: remnawave)"
                echo -e "  \033[38;5;244m--path, -p <path>\033[0m     Базовый путь установки (по умолчанию: /opt)"
                echo -e "  \033[38;5;244m--database-only\033[0m       Восстановить только базу данных (требует существующую установку)"
                echo -e "  \033[38;5;244m--skip-install\033[0m        Не устанавливать скрипт управления"
                echo -e "  \033[38;5;244m--force\033[0m               Пропустить подтверждения"
                echo -e "  \033[38;5;244m--help, -h\033[0m            Показать эту справку"
                echo
                echo -e "\033[1;37mПримеры:\033[0m"
                echo -e "  \033[38;5;244m$APP_NAME restore --file backup.tar.gz\033[0m"
                echo -e "  \033[38;5;244m$APP_NAME restore --file backup.tar.gz --name newpanel\033[0m"
                echo -e "  \033[38;5;244m$APP_NAME restore --file backup.tar.gz --path /root\033[0m"
                echo -e "  \033[38;5;244m$APP_NAME restore --database-only --file backup.tar.gz\033[0m"
                echo
                exit 0
                ;;
            --) shift; break ;;  # Конец опций
            -*) 
                echo "Unknown option: $1" >&2
                echo "Используйте '$APP_NAME restore --help' для справки по использованию."
                exit 1
                ;;
            *) break ;;  # Позиционные аргументы
        esac
    done
    
    # Устанавливаем целевую директорию
    local target_dir="$target_base_dir/$target_app_name"
    
    # Если файл не указан, показываем интерактивное меню
    if [ -z "$backup_file" ]; then
        restore_interactive_menu "$target_app_name" "$database_only" "$skip_install" "$force_restore" "$target_base_dir"
    else
        restore_from_backup "$backup_file" "$target_app_name" "$database_only" "$skip_install" "$force_restore" "$target_base_dir"
    fi
}

restore_interactive_menu() {
    local target_app_name="$1"
    local database_only="$2"
    local skip_install="$3"
    local force_restore="$4"
    local target_base_dir="$5"
    
    while true; do
        clear
        echo -e "\033[1;37m🔄 Восстановление из бэкапа\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
        echo
        
        # Показываем текущую конфигурацию
        echo -e "\033[1;37m⚙️  Конфигурация восстановления:\033[0m"
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Целевое имя:" "$target_app_name"
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Целевой путь:" "$target_base_dir/$target_app_name"
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Тип восстановления:" "$([ "$database_only" = true ] && echo "Только база данных" || echo "Полная система")"
        echo
        
        # Проверяем существование целевой директории
        if [ -d "$target_base_dir/$target_app_name" ]; then
            echo -e "\033[1;33m⚠️  Целевая директория уже существует!\033[0m"
            echo -e "\033[38;5;244m   Существующая установка будет сохранена в резервную копию и заменена\033[0m"
        else
            echo -e "\033[1;32m✅ Целевая директория чистая\033[0m"
        fi
        echo
        
        # Сканируем доступные бэкапы в разных локациях
        local backup_files=()
        
        # Ищем в стандартной директории текущего приложения
        if [ -d "$APP_DIR/backups" ]; then
            # Используем find для более надежного поиска всех типов backup файлов
            while IFS= read -r -d '' backup; do
                backup_files+=("$backup")
            done < <(find "$APP_DIR/backups" -maxdepth 1 -type f \( \
                -name "remnawave_*.tar.gz" -o \
                -name "remnawave_*.sql" -o \
                -name "remnawave_*.sql.gz" -o \
                -name "remnawave_*.sql.bz2" -o \
                -name "remnawave_*.sql.xz" \
            \) -print0 2>/dev/null | sort -zr)
        fi
        
        # Ищем в стандартных директориях других установок
        for possible_dir in /opt/remnawave*/backups /opt/*/backups; do
            if [ -d "$possible_dir" ] && [ "$possible_dir" != "$APP_DIR/backups" ]; then
                while IFS= read -r -d '' backup; do
                    backup_files+=("$backup")
                done < <(find "$possible_dir" -maxdepth 1 -type f \( \
                    -name "remnawave_*.tar.gz" -o \
                    -name "remnawave_*.sql" -o \
                    -name "remnawave_*.sql.gz" -o \
                    -name "remnawave_*.sql.bz2" -o \
                    -name "remnawave_*.sql.xz" \
                \) -print0 2>/dev/null | sort -zr)
            fi
        done
        
        if [ ${#backup_files[@]} -eq 0 ]; then
            echo -e "\033[1;33m⚠️  No backup files found!\033[0m"
            echo
            echo -e "\033[38;5;244mSearched in:\033[0m"
            echo -e "\033[38;5;244m   • $APP_DIR/backups/\033[0m"
            echo -e "\033[38;5;244m   • /opt/*/backups/\033[0m"
            echo
            echo -e "\033[1;37m📋 Опции:\033[0m"
            echo -e "   \033[38;5;15m1)\033[0m 📁 Specify custom backup file path"
            echo -e "   \033[38;5;15m2)\033[0m ⚙️  Change restore settings"
            echo -e "   \033[38;5;244m0)\033[0m ⬅️  Back to main menu"
            echo
            
            read -p "Выберите опцию [0-2]: " choice
            
            case "$choice" in
                1) 
                    restore_custom_file "$target_app_name" "$database_only" "$skip_install" "$force_restore" "$target_base_dir"
                    ;;
                2) 
                    restore_configure_settings "$target_app_name" "$database_only" "$skip_install" "$force_restore" "$target_base_dir"
                    ;;
                0) return 0 ;;
                *) 
                    echo -e "\033[1;31mInvalid option!\033[0m"
                    sleep 1
                    ;;
            esac
            continue
        fi
        
        echo -e "\033[1;37m📦 Available Backups:\033[0m"
        echo
        
        local index=1
        for backup in "${backup_files[@]}"; do
            local backup_name=$(basename "$backup")
            local backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
            local backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1)
            local backup_source=$(dirname "$backup" | sed 's|/backups||')
            
            # Определяем тип бэкапа
            local backup_icon="📦"
            local backup_type="Unknown"
            
            if [[ "$backup_name" =~ scheduled ]]; then
                backup_icon="🤖"
                backup_type="Scheduled"
            elif [[ "$backup_name" =~ full ]]; then
                backup_icon="📁"
                backup_type="Full"
            elif [[ "$backup_name" =~ db ]]; then
                backup_icon="🗄️"
                backup_type="Database"
            fi
            
            # Определяем совместимость с текущим режимом восстановления
            local compatible=true
            local compat_note=""
            
            if [ "$database_only" = true ]; then
                if [[ "$backup_name" =~ \.tar\.gz$ ]]; then
                    compat_note=" (will extract DB)"
                fi
            else
                if [[ "$backup_name" =~ \.sql ]]; then
                    compat_note=" (DB only - need full backup)"
                    compatible=false
                fi
            fi
            
            if [ "$compatible" = true ]; then
                printf "   \033[38;5;15m%2d)\033[0m %s \033[38;5;250m%-30s\033[0m \033[38;5;244m%s\033[0m \033[38;5;244m%s\033[0m\033[38;5;117m%s\033[0m\n" \
                    "$index" "$backup_icon" "$backup_name" "$backup_size" "$backup_date" "$compat_note"
            else
                printf "   \033[38;5;244m%2d)\033[0m %s \033[38;5;244m%-30s\033[0m \033[38;5;244m%s\033[0m \033[38;5;244m%s\033[0m\033[1;31m%s\033[0m\n" \
                    "$index" "$backup_icon" "$backup_name" "$backup_size" "$backup_date" "$compat_note"
            fi
            printf "      \033[38;5;244m   Источник: %s | Тип: %s\033[0m\n" "$backup_source" "$backup_type"
            echo
            index=$((index + 1))
        done
        
        echo -e "\033[1;37m📋 Опции:\033[0m"
        echo -e "   \033[38;5;15m97)\033[0m 📁 Specify custom backup file path"
        echo -e "   \033[38;5;15m98)\033[0m ⚙️  Change restore settings"
        echo -e "   \033[38;5;15m99)\033[0m 🔄 Refresh backup list"
        echo -e "   \033[38;5;244m0)\033[0m ⬅️  Back to main menu"
        echo
        
        read -p "Выберите бэкап для восстановления [0-${#backup_files[@]}]: " choice
        
        case "$choice" in
            0) return 0 ;;
            97) 
                restore_custom_file "$target_app_name" "$database_only" "$skip_install" "$force_restore" "$target_base_dir"
                ;;
            98) 
                restore_configure_settings "$target_app_name" "$database_only" "$skip_install" "$force_restore" "$target_base_dir"
                ;;
            99) continue ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backup_files[@]} ]; then
                    local selected_backup="${backup_files[$((choice - 1))]}"
                    restore_from_backup "$selected_backup" "$target_app_name" "$database_only" "$skip_install" "$force_restore" "$target_base_dir"
                    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
                else
                    echo -e "\033[1;31mInvalid option!\033[0m"
                    sleep 1
                fi
                ;;
        esac
    done
}

restore_configure_settings() {
    local current_target_name="$1"
    local current_database_only="$2"
    local current_skip_install="$3"
    local current_force_restore="$4"
    local current_target_base_dir="$5"
    
    while true; do
        clear
        echo -e "\033[1;37m⚙️  Restore Settings\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
        echo
        
        echo -e "\033[1;37m📋 Current Settings:\033[0m"
        printf "   \033[38;5;15m1)\033[0m \033[38;5;250mИмя целевого приложения: \033[0m\033[1;37m%s\033[0m\n" "$current_target_name"
        printf "   \033[38;5;15m2)\033[0m \033[38;5;250mЦелевой путь: \033[0m\033[1;37m%s\033[0m\n" "$current_target_base_dir"
        printf "   \033[38;5;15m3)\033[0m \033[38;5;250mТип восстановления: \033[0m\033[1;37m%s\033[0m\n" "$([ "$current_database_only" = true ] && echo "Только база данных" || echo "Полная система")"
        printf "   \033[38;5;15m4)\033[0m \033[38;5;250mПропустить установку скрипта: \033[0m\033[1;37m%s\033[0m\n" "$([ "$current_skip_install" = true ] && echo "Да" || echo "Нет")"
        printf "   \033[38;5;15m5)\033[0m \033[38;5;250mПринудительный режим: \033[0m\033[1;37m%s\033[0m\n" "$([ "$current_force_restore" = true ] && echo "Включен" || echo "Отключен")"
        echo
        echo -e "   \033[38;5;244m0)\033[0m ⬅️  Back to backup selection"
        echo
        
        read -p "Выберите настройку для изменения [0-5]: " choice
        
        case "$choice" in
            1)
                echo
                echo -e "\033[1;37m📝 Change Target App Name\033[0m"
                echo -e "\033[38;5;250mCurrent: $current_target_name\033[0m"
                echo -e "\033[38;5;244mNote: Will be installed to $current_target_base_dir/<app_name>/\033[0m"
                echo
                read -p "Введите новое имя приложения: " new_name
                
                if [ -n "$new_name" ] && [[ "$new_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    current_target_name="$new_name"
                    echo -e "\033[1;32m✅ App name changed to: $current_target_name\033[0m"
                else
                    echo -e "\033[1;31m❌ Invalid app name! Use only letters, numbers, - and _\033[0m"
                fi
                sleep 2
                ;;
            2)
                echo
                echo -e "\033[1;37m📝 Change Target Base Path\033[0m"
                echo -e "\033[38;5;250mCurrent: $current_target_base_dir\033[0m"
                echo -e "\033[38;5;244mApp will be installed to: <path>/$current_target_name/\033[0m"
                echo
                read -p "Введите новый базовый путь: " new_path
                
                if [ -n "$new_path" ]; then
                    # Убираем конечный слеш
                    new_path="${new_path%/}"
                    current_target_base_dir="$new_path"
                    echo -e "\033[1;32m✅ Base path changed to: $current_target_base_dir\033[0m"
                else
                    echo -e "\033[1;31m❌ Path cannot be empty!\033[0m"
                fi
                sleep 2
                ;;
            3)
                if [ "$current_database_only" = true ]; then
                    current_database_only=false
                    echo -e "\033[1;32m✅ Changed to: Full system restore\033[0m"
                else
                    current_database_only=true
                    echo -e "\033[1;32m✅ Changed to: Database only restore\033[0m"
                fi
                sleep 2
                ;;
            4)
                if [ "$current_skip_install" = true ]; then
                    current_skip_install=false
                    echo -e "\033[1;32m✅ Скрипт управления будет установлен\033[0m"
                else
                    current_skip_install=true
                    echo -e "\033[1;32m✅ Установка скрипта управления будет пропущена\033[0m"
                fi
                sleep 2
                ;;
            5)
                if [ "$current_force_restore" = true ]; then
                    current_force_restore=false
                    echo -e "\033[1;32m✅ Подтверждения включены\033[0m"
                else
                    current_force_restore=true
                    echo -e "\033[1;32m✅ Принудительный режим включен (пропустить подтверждения)\033[0m"
                fi
                sleep 2
                ;;
            0)
                # Возвращаемся в меню с обновленными настройками
                restore_interactive_menu "$current_target_name" "$current_database_only" "$current_skip_install" "$current_force_restore" "$current_target_base_dir"
                return
                ;;
            *)
                echo -e "\033[1;31mInvalid option!\033[0m"
                sleep 1
                ;;
        esac
    done
}

restore_custom_file() {
    local target_app_name="$1"
    local database_only="$2"
    local skip_install="$3"
    local force_restore="$4"
    local target_base_dir="$5"
    
    echo
    echo -e "\033[1;37m📁 Пользовательский файл бэкапа\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
    echo
    echo -e "\033[38;5;250mВведите полный путь к файлу бэкапа.\033[0m"
    echo -e "\033[38;5;244mПоддерживаемые форматы: .tar.gz, .sql, .sql.gz\033[0m"
    echo
    
    read -p "Путь к файлу бэкапа: " -r custom_path
    
    if [ -z "$custom_path" ]; then
        echo -e "\033[1;31m❌ Путь не указан!\033[0m"
        sleep 2
        return
    fi
    
    # Расширяем относительные пути
    if [[ "$custom_path" == ~* ]]; then
        custom_path="${custom_path/#\~/$HOME}"
    fi
    
    if [ ! -f "$custom_path" ]; then
        echo -e "\033[1;31m❌ File not found: $custom_path\033[0m"
        sleep 2
        return
    fi
    
    restore_from_backup "$custom_path" "$target_app_name" "$database_only" "$skip_install" "$force_restore" "$target_base_dir"
}

check_system_requirements_for_restore() {
    echo -e "\033[1;37m🔍 Проверка системных требований\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    echo
    
    local requirements_met=true
    local install_needed=()
    
    # Проверка ОС
    echo -e "\033[38;5;250m📝 Шаг 1:\033[0m Проверка операционной системы..."
    if ! command -v lsb_release >/dev/null 2>&1 && ! [ -f /etc/os-release ]; then
        echo -e "\033[1;33m⚠️  Cannot determine OS version\033[0m"
    else
        local os_info=""
        if command -v lsb_release >/dev/null 2>&1; then
            os_info=$(lsb_release -d | cut -f2)
        elif [ -f /etc/os-release ]; then
            os_info=$(grep "PRETTY_NAME" /etc/os-release | cut -d'"' -f2)
        fi
        echo -e "\033[1;32m✅ OS: $os_info\033[0m"
    fi
    
    # Проверка прав root
    echo -e "\033[38;5;250m📝 Шаг 2:\033[0m Проверка прав root..."
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[1;31m❌ Требуются права root!\033[0m"
        echo -e "\033[38;5;244m   Пожалуйста, запустите с sudo\033[0m"
        return 1
    else
        echo -e "\033[1;32m✅ Права root подтверждены\033[0m"
    fi
    
    # Проверка базовых утилит
    echo -e "\033[38;5;250m📝 Шаг 3:\033[0m Проверка системных утилит..."
    local basic_tools=("curl" "wget" "tar" "gzip" "jq")
    local missing_basic=()
    
    for tool in "${basic_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_basic+=("$tool")
        fi
    done
    
    if [ ${#missing_basic[@]} -eq 0 ]; then
        echo -e "\033[1;32m✅ All basic utilities available\033[0m"
    else
        echo -e "\033[1;33m⚠️  Missing utilities: ${missing_basic[*]}\033[0m"
        install_needed+=("${missing_basic[@]}")
    fi
    
    # Проверка Docker
    echo -e "\033[38;5;250m📝 Шаг 4:\033[0m Проверка Docker..."
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "\033[1;33m⚠️  Docker не установлен\033[0m"
        install_needed+=("docker")
        requirements_met=false
    else
        local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        echo -e "\033[1;32m✅ Docker installed: $docker_version\033[0m"
        
        # Проверка запуска Docker
        if ! docker info >/dev/null 2>&1; then
            echo -e "\033[1;33m⚠️  Демон Docker не запущен\033[0m"
            echo -e "\033[38;5;244m   Попытка запустить службу Docker\033[0m"
        else
            echo -e "\033[38;5;244m   ✓ Демон Docker запущен\033[0m"
        fi
    fi
    
    # Проверка Docker Compose
    echo -e "\033[38;5;250m📝 Шаг 5:\033[0m Проверка Docker Compose..."
    if ! docker compose version >/dev/null 2>&1; then
        echo -e "\033[1;33m⚠️  Docker Compose V2 not available\033[0m"
        
        # Проверяем старую версию
        if command -v docker-compose >/dev/null 2>&1; then
            local compose_version=$(docker-compose --version | cut -d' ' -f3 | tr -d ',')
            echo -e "\033[1;33m⚠️  Found legacy docker-compose: $compose_version\033[0m"
            echo -e "\033[38;5;244m   Recommend updating to Docker with built-in Compose V2\033[0m"
        else
            install_needed+=("docker-compose")
            requirements_met=false
        fi
    else
        local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        echo -e "\033[1;32m✅ Docker Compose V2: $compose_version\033[0m"
    fi
    
    # Проверка свободного места
    echo -e "\033[38;5;250m📝 Шаг 6:\033[0m Проверка дискового пространства..."
    local available_space=$(df / | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [ $available_gb -lt 2 ]; then
        echo -e "\033[1;31m❌ Недостаточно места на диске: доступно ${available_gb}GB\033[0m"
        echo -e "\033[38;5;244m   Минимум 2GB требуется для операции восстановления\033[0m"
        requirements_met=false
    else
        echo -e "\033[1;32m✅ Достаточно места на диске: доступно ${available_gb}GB\033[0m"
    fi
    
    # Проверка сетевого подключения
    echo -e "\033[38;5;250m📝 Шаг 7:\033[0m Проверка сетевого подключения..."
    if curl -s --connect-timeout 5 https://registry-1.docker.io/v2/ >/dev/null; then
        echo -e "\033[1;32m✅ Подключение к Docker Hub подтверждено\033[0m"
    else
        echo -e "\033[1;33m⚠️  Проблемы с подключением к Docker Hub\033[0m"
        echo -e "\033[38;5;244m   Это может вызвать проблемы при загрузке Docker образов\033[0m"
    fi
    
    # Итоговый результат
    echo
    if [ ${#install_needed[@]} -gt 0 ]; then
        echo -e "\033[1;37m📦 Missing Dependencies:\033[0m"
        for package in "${install_needed[@]}"; do
            echo -e "\033[38;5;244m   • $package\033[0m"
        done
        echo
        
        echo -e "\033[1;37m🔧 Auto-install missing dependencies?\033[0m"
        read -p "Install missing packages automatically? [Y/n]: " -r auto_install
        
        if [[ ! $auto_install =~ ^[Nn]$ ]]; then
            install_missing_dependencies "${install_needed[@]}"
            
            # Повторная проверка после установки
            echo
            echo -e "\033[1;37m🔄 Re-checking after installation...\033[0m"
            check_system_requirements_for_restore
            return $?
        else
            echo -e "\033[1;31m❌ Cannot proceed without required dependencies\033[0m"
            echo
            echo -e "\033[1;37m📋 Manual installation commands:\033[0m"
            show_manual_install_commands "${install_needed[@]}"
            return 1
        fi
    elif [ "$requirements_met" = false ]; then
        echo -e "\033[1;31m❌ System requirements not met\033[0m"
        return 1
    else
        echo -e "\033[1;32m🎉 All system requirements satisfied!\033[0m"
        return 0
    fi
}

install_missing_dependencies() {
    local packages=("$@")
    
    echo
    echo -e "\033[1;37m📦 Installing Missing Dependencies\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    
    # Определяем пакетный менеджер
    if command -v apt-get >/dev/null 2>&1; then
        install_with_apt "${packages[@]}"
    elif command -v yum >/dev/null 2>&1; then
        install_with_yum "${packages[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        install_with_dnf "${packages[@]}"
    else
        echo -e "\033[1;31m❌ Unsupported package manager!\033[0m"
            echo -e "\033[38;5;244m   Пожалуйста, установите зависимости вручную\033[0m"
        return 1
    fi
}


install_with_apt() {
    local packages=("$@")
    
    echo -e "\033[38;5;250m📝 Using APT package manager...\033[0m"
    
    # Обновляем список пакетов
    echo -e "\033[38;5;244m   Updating package list...\033[0m"
    if apt-get update >/dev/null 2>&1; then
        echo -e "\033[1;32m✅ Package list updated\033[0m"
    else
        echo -e "\033[1;33m⚠️  Не удалось обновить список пакетов, продолжаем...\033[0m"
    fi
    
    for package in "${packages[@]}"; do
        echo -e "\033[38;5;250m📦 Installing $package...\033[0m"
        
        case "$package" in
            "docker")
                # Устанавливаем Docker официальным способом
                echo -e "\033[38;5;244m   Installing Docker from official repository...\033[0m"
                curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    systemctl start docker 2>/dev/null
                    systemctl enable docker 2>/dev/null
                    echo -e "\033[1;32m✅ Docker installed and started\033[0m"
                else
                    echo -e "\033[1;31m❌ Установка Docker не удалась\033[0m"
                fi
                ;;
            "docker-compose")
                # Docker Compose как отдельный пакет уже включен в современный Docker
                echo -e "\033[1;32m✅ Docker Compose included with Docker\033[0m"
                ;;
            "jq")
                apt-get install -y jq >/dev/null 2>&1 && echo -e "\033[1;32m✅ jq установлен\033[0m" || echo -e "\033[1;31m❌ Установка jq не удалась\033[0m"
                ;;
            "curl")
                apt-get install -y curl >/dev/null 2>&1 && echo -e "\033[1;32m✅ curl установлен\033[0m" || echo -e "\033[1;31m❌ Установка curl не удалась\033[0m"
                ;;
            "wget")
                apt-get install -y wget >/dev/null 2>&1 && echo -e "\033[1;32m✅ wget установлен\033[0m" || echo -e "\033[1;31m❌ Установка wget не удалась\033[0m"
                ;;
            *)
                apt-get install -y "$package" >/dev/null 2>&1 && echo -e "\033[1;32m✅ $package установлен\033[0m" || echo -e "\033[1;31m❌ Установка $package не удалась\033[0m"
                ;;
        esac
    done
}

install_with_yum() {
    local packages=("$@")
    
    echo -e "\033[38;5;250m📝 Using YUM package manager...\033[0m"
    
    for package in "${packages[@]}"; do
        echo -e "\033[38;5;250m📦 Installing $package...\033[0m"
        
        case "$package" in
            "docker")
                curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
                systemctl start docker 2>/dev/null
                systemctl enable docker 2>/dev/null
                echo -e "\033[1;32m✅ Docker installed\033[0m"
                ;;
            *)
                yum install -y "$package" >/dev/null 2>&1 && echo -e "\033[1;32m✅ $package установлен\033[0m" || echo -e "\033[1;31m❌ Установка $package не удалась\033[0m"
                ;;
        esac
    done
}

install_with_dnf() {
    local packages=("$@")
    
    echo -e "\033[38;5;250m📝 Using DNF package manager...\033[0m"
    
    for package in "${packages[@]}"; do
        echo -e "\033[38;5;250m📦 Installing $package...\033[0m"
        
        case "$package" in
            "docker")
                curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
                systemctl start docker 2>/dev/null
                systemctl enable docker 2>/dev/null
                echo -e "\033[1;32m✅ Docker installed\033[0m"
                ;;
            *)
                dnf install -y "$package" >/dev/null 2>&1 && echo -e "\033[1;32m✅ $package установлен\033[0m" || echo -e "\033[1;31m❌ Установка $package не удалась\033[0m"
                ;;
        esac
    done
}

show_manual_install_commands() {
    local packages=("$@")
    
    echo
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "\033[38;5;244m# Ubuntu/Debian:\033[0m"
        echo -e "\033[38;5;117msudo apt-get update\033[0m"
        for package in "${packages[@]}"; do
            if [ "$package" = "docker" ]; then
                echo -e "\033[38;5;117mcurl -fsSL https://get.docker.com | sh\033[0m"
            else
                echo -e "\033[38;5;117msudo apt-get install -y $package\033[0m"
            fi
        done
    elif command -v yum >/dev/null 2>&1; then
        echo -e "\033[38;5;244m# CentOS/RHEL:\033[0m"
        for package in "${packages[@]}"; do
            if [ "$package" = "docker" ]; then
                echo -e "\033[38;5;117mcurl -fsSL https://get.docker.com | sh\033[0m"
            else
                echo -e "\033[38;5;117msudo yum install -y $package\033[0m"
            fi
        done
    fi
}
restore_from_backup() {
    local backup_file="$1"
    local target_app_name="$2"
    local database_only="$3"
    local skip_install="$4"
    local force_restore="$5"
    local target_base_dir="${6:-/opt}"
    
    local target_dir="$target_base_dir/$target_app_name"
    
    
    if ! check_system_requirements_for_restore; then
        echo -e "\033[1;31m❌ Проверка системных требований не пройдена!\033[0m"
        echo -e "\033[38;5;244m   Пожалуйста, устраните проблемы выше перед продолжением\033[0m"
        return 1
    fi

    echo
    echo -e "\033[1;37m🔄 Preparing Restore Operation\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    echo
    
    # Валидация бэкапа
    echo -e "\033[38;5;250m📝 Step 1:\033[0m Validating backup file..."
    
    if [ ! -f "$backup_file" ]; then
        echo -e "\033[1;31m❌ Backup file not found: $backup_file\033[0m"
        return 1
    fi
    
    # Определяем тип файла
    local backup_type=""
    if [[ "$backup_file" =~ \.tar\.gz$ ]]; then
        backup_type="archive"
        # Проверяем архив
        if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
            echo -e "\033[1;31m❌ Invalid or corrupted backup archive!\033[0m"
            return 1
        fi
    elif [[ "$backup_file" =~ \.sql\.gz$ ]]; then
        backup_type="compressed_sql"
        # Проверяем сжатый SQL
        if ! gunzip -t "$backup_file" 2>/dev/null; then
            echo -e "\033[1;31m❌ Invalid or corrupted compressed SQL file!\033[0m"
            return 1
        fi
    elif [[ "$backup_file" =~ \.sql$ ]]; then
        backup_type="sql"
        # Проверяем что файл содержит SQL
        if ! head -10 "$backup_file" | grep -q -i "postgresql\|create\|insert\|copy\|select"; then
            echo -e "\033[1;33m⚠️  File may not be a valid SQL dump\033[0m"
        fi
    else
        echo -e "\033[1;31m❌ Unsupported file format! Supported: .tar.gz, .sql, .sql.gz\033[0m"
        return 1
    fi
    
    echo -e "\033[1;32m✅ Backup file validation passed (type: $backup_type)\033[0m"
    
    # Анализируем содержимое архива для .tar.gz
    local backup_info=""
    local original_app_name=""
    
    if [ "$backup_type" = "archive" ]; then
        echo -e "\033[38;5;244m   Analyzing backup content...\033[0m"
        
        local temp_analysis_dir="/tmp/backup_analysis_$$"
        mkdir -p "$temp_analysis_dir"
        
        # Извлекаем только метаданные для анализа
        tar -xzf "$backup_file" -C "$temp_analysis_dir" "*/backup-metadata.json" 2>/dev/null || true
        
        local metadata_file=$(find "$temp_analysis_dir" -name "backup-metadata.json" 2>/dev/null | head -1)
        
        if [ -f "$metadata_file" ]; then
            original_app_name=$(jq -r '.app_name // "unknown"' "$metadata_file" 2>/dev/null)
            local backup_timestamp=$(jq -r '.timestamp // "unknown"' "$metadata_file" 2>/dev/null)
            local script_version=$(jq -r '.script_version // "unknown"' "$metadata_file" 2>/dev/null)
            local backup_type_meta=$(jq -r '.backup_type // "unknown"' "$metadata_file" 2>/dev/null)
            
            backup_info="Original: $original_app_name, Created: $backup_timestamp, Version: $script_version, Type: $backup_type_meta"
            echo -e "\033[38;5;244m   ✓ Backup metadata found and valid\033[0m"
        else
            echo -e "\033[1;33m⚠️  No metadata found in backup (older format?)\033[0m"
            original_app_name="unknown"
        fi
        
        rm -rf "$temp_analysis_dir"
    fi
    
    # Показываем план восстановления
    echo
    echo -e "\033[1;37m📋 Restore Plan:\033[0m"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Файл бэкапа:" "$(basename "$backup_file")"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Размер бэкапа:" "$(du -sh "$backup_file" | cut -f1)"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Тип бэкапа:" "$backup_type"
    if [ -n "$backup_info" ]; then
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Информация о бэкапе:" "$backup_info"
    fi
    echo
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Целевое имя:" "$target_app_name"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Целевая директория:" "$target_dir"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Тип восстановления:" "$([ "$database_only" = true ] && echo "Только база данных" || echo "Полная система")"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Установить скрипт:" "$([ "$skip_install" = true ] && echo "Пропустить" || echo "Да")"
    
    # Проверка совместимости
    echo
    echo -e "\033[1;37m⚙️  Compatibility Check:\033[0m"
    local compatibility_issues=0
    
    if [ "$database_only" = false ] && [[ "$backup_file" =~ \.sql ]]; then
        echo -e "\033[1;31m❌ Full system restore requested but backup contains only database\033[0m"
        echo -e "\033[38;5;244m   Solution: Use --database-only flag or use full backup (.tar.gz)\033[0m"
        compatibility_issues=$((compatibility_issues + 1))
    fi
    
    if [ "$database_only" = true ] && [ "$backup_type" = "archive" ]; then
        echo -e "\033[1;32m✅ Database-only restore from archive (will extract database.sql)\033[0m"
    elif [ "$database_only" = true ] && [[ "$backup_file" =~ \.sql ]]; then
        echo -e "\033[1;32m✅ Database-only restore from SQL file\033[0m"
    elif [ "$database_only" = false ] && [ "$backup_type" = "archive" ]; then
        echo -e "\033[1;32m✅ Full system restore from archive\033[0m"
    fi
    
    if [ $compatibility_issues -gt 0 ]; then
        echo -e "\033[1;31m❌ Cannot proceed due to compatibility issues\033[0m"
        return 1
    fi
    
    # Проверяем текущее состояние
    echo
    echo -e "\033[1;37m⚙️  System Analysis:\033[0m"
    
    local target_exists=false
    local backup_needed=false
    
    if [ -d "$target_dir" ]; then
        target_exists=true
        echo -e "\033[1;33m⚠️  Target directory exists: $target_dir\033[0m"
        
        if [ "$database_only" = false ]; then
            echo -e "\033[38;5;244m   • Directory will be backed up and replaced\033[0m"
            backup_needed=true
        else
            echo -e "\033[38;5;244m   • Only database will be restored\033[0m"
        fi
    else
        echo -e "\033[1;32m✅ Target directory is clean: $target_dir\033[0m"
    fi
    
    # Проверяем наличие управляющего скрипта
    local script_exists=false
    if [ -f "/usr/local/bin/$target_app_name" ]; then
        script_exists=true
        echo -e "\033[1;33m⚠️  Management script exists: /usr/local/bin/$target_app_name\033[0m"
        if [ "$skip_install" = false ]; then
            echo -e "\033[38;5;244m   • Script will be updated\033[0m"
        fi
    else
        echo -e "\033[1;32m✅ No conflicting management script found\033[0m"
    fi
    
    # Запрашиваем подтверждение
    if [ "$force_restore" != true ]; then
        echo
        echo -e "\033[1;37m🤔 Proceed with restore operation?\033[0m"
        read -p "Continue? [y/N]: " -r confirm
        
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo -e "\033[38;5;250mВосстановление отменено\033[0m"
            return 0
        fi
    fi
    
    # Начинаем процесс восстановления
    echo
    echo -e "\033[1;37m🔄 Starting Restore Process\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    # Шаг 1: Резервное копирование существующей установки
    if [ "$backup_needed" = true ]; then
        echo -e "\033[38;5;250m📝 Step 1:\033[0m Creating safety backup..."
        
        local safety_backup_dir="/opt/restore_backups"
        local safety_backup_name="${target_app_name}_pre_restore_$(date +%Y%m%d_%H%M%S)"
        
        mkdir -p "$safety_backup_dir"
        
        if tar -czf "$safety_backup_dir/${safety_backup_name}.tar.gz" -C "$(dirname "$target_dir")" "$(basename "$target_dir")" 2>/dev/null; then
            echo -e "\033[1;32m✅ Safety backup created: $safety_backup_dir/${safety_backup_name}.tar.gz\033[0m"
        else
            echo -e "\033[1;33m⚠️  Резервная копия безопасности не создана, продолжаем...\033[0m"
        fi
    fi
    
    # Шаг 2: Обработка в зависимости от типа восстановления
    if [ "$database_only" = false ] && [ "$backup_type" = "archive" ]; then
        # Полное восстановление из архива
        restore_full_from_archive "$backup_file" "$target_dir" "$target_app_name" "$original_app_name" "$skip_install"
    elif [ "$database_only" = true ]; then
        # Восстановление только БД
        restore_database_only "$backup_file" "$backup_type" "$target_dir" "$target_app_name"
    fi
    
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    echo -e "\033[1;37m🎉 Restore Completed!\033[0m"
    echo
    
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Восстановлено из:" "$(basename "$backup_file")"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Целевое имя:" "$target_app_name"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Путь установки:" "$target_dir"
    
    # Показываем URL доступа если возможно
    if [ -f "$target_dir/.env" ] && [ "$database_only" = false ]; then
        local app_port=$(grep "^APP_PORT=" "$target_dir/.env" | cut -d'=' -f2 2>/dev/null)
        local server_ip="${NODE_IP:-127.0.0.1}"
        
        echo
        echo -e "\033[1;37m🌐 Panel Access:\033[0m"
        if [ -n "$app_port" ]; then
            printf "   \033[38;5;15m%-20s\033[0m \033[38;5;117mhttp://%s:%s\033[0m\n" "URL панели:" "$server_ip" "$app_port"
        fi
    fi
    
    echo
    echo -e "\033[38;5;8m💡 Next steps:\033[0m"
    echo -e "\033[38;5;244m   • Check status: sudo $target_app_name status\033[0m"
    echo -e "\033[38;5;244m   • Смотреть логи: sudo $target_app_name logs\033[0m"
    echo -e "\033[38;5;244m   • Health check: sudo $target_app_name health\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
}

restore_full_from_archive() {
    local backup_file="$1"
    local target_dir="$2"
    local target_app_name="$3"
    local original_app_name="$4"
    local skip_install="$5"
    
    log_restore_operation "Full Restore" "STARTED" "File: $backup_file, Target: $target_dir, App: $target_app_name"
    
    # Step 0: Проверка системных ресурсов
    echo -e "\033[38;5;250m📝 Шаг 0:\033[0m Проверка системных ресурсов..."
    if ! check_system_resources "$backup_file" "$target_dir"; then
        log_restore_operation "Resource Check" "ERROR" "Недостаточно системных ресурсов"
        return 1
    fi
    log_restore_operation "Resource Check" "SUCCESS" "Системные ресурсы проверены"
    
    # Step 1: Создание safety backup
    echo -e "\033[38;5;250m📝 Шаг 1:\033[0m Создание резервной копии безопасности..."
    local backup_parent_dir="$(dirname "$target_dir")/backups"
    mkdir -p "$backup_parent_dir"
    
    if ! create_safety_backup "$target_dir" "$target_app_name" "$backup_parent_dir"; then
        echo -e "\033[1;33m⚠️  Не удалось создать резервную копию безопасности, продолжаем с осторожностью...\033[0m"
        log_restore_operation "Safety Backup" "WARNING" "Не удалось создать резервную копию"
    else
        log_restore_operation "Safety Backup" "SUCCESS" "Резервная копия создана"
    fi
    
    # Step 2: Остановка существующих сервисов
    local services_were_running=false
    if [ -f "$target_dir/docker-compose.yml" ]; then
        echo -e "\033[38;5;250m📝 Шаг 2:\033[0m Остановка существующих сервисов..."
        
        cd "$target_dir"
        if docker compose ps -q | grep -q .; then
            services_were_running=true
            if docker compose down 2>/dev/null; then
                echo -e "\033[1;32m✅ Сервисы остановлены\033[0m"
                log_restore_operation "Service Shutdown" "SUCCESS" "Все сервисы остановлены"
            else
                echo -e "\033[1;33m⚠️  Не удалось остановить сервисы, продолжаем...\033[0m"
                log_restore_operation "Service Shutdown" "WARNING" "Не удалось остановить некоторые сервисы"
            fi
        else
            echo -e "\033[38;5;244m   Запущенных сервисов не найдено\033[0m"
            log_restore_operation "Service Shutdown" "INFO" "Не найдено запущенных сервисов"
        fi
    fi
    
    # Step 3: Извлечение архива
    echo -e "\033[38;5;250m📝 Шаг 3:\033[0m Извлечение бэкапа в целевую директорию..."
    
    # Удаляем старую директорию если нужно
    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
    fi
    
    # Создаем родительскую директорию
    mkdir -p "$(dirname "$target_dir")"
    
    # Извлекаем архив
    local temp_extract_dir="/tmp/restore_extract_$$"
    mkdir -p "$temp_extract_dir"
    
    if tar -xzf "$backup_file" -C "$temp_extract_dir" 2>/dev/null; then
        # Находим директорию с бэкапом
        local backup_content=$(ls "$temp_extract_dir")
        local backup_dir_name=$(echo "$backup_content" | head -1)
        
            if [ -d "$temp_extract_dir/$backup_dir_name" ]; then
                # Проверяем структуру - новый unified формат или старый с app/
                if [ -f "$temp_extract_dir/$backup_dir_name/docker-compose.yml" ]; then
                    # НОВЫЙ ФОРМАТ: файлы приложения в корне бэкапа
                    mv "$temp_extract_dir/$backup_dir_name" "$target_dir"
                    echo -e "\033[1;32m✅ Бэкап успешно извлечён (унифицированный формат)\033[0m"
                    log_restore_operation "Archive Extraction" "SUCCESS" "Бэкап единого формата извлечён"
                elif [ -d "$temp_extract_dir/$backup_dir_name/app" ]; then
                    # СТАРЫЙ ФОРМАТ: приложение в поддиректории app
                    mv "$temp_extract_dir/$backup_dir_name/app" "$target_dir"
                    
                    # Копируем database.sql в target_dir для последующего использования
                    if [ -f "$temp_extract_dir/$backup_dir_name/database.sql" ]; then
                        cp "$temp_extract_dir/$backup_dir_name/database.sql" "$target_dir/"
                    fi
                
                # Сохраняем скрипт установки
                if [ -f "$temp_extract_dir/$backup_dir_name/install-script.sh" ]; then
                    cp "$temp_extract_dir/$backup_dir_name/install-script.sh" "/tmp/restore_script_$$"
                fi
                echo -e "\033[1;32m✅ Бэкап успешно извлечён (устаревший формат)\033[0m"
                log_restore_operation "Archive Extraction" "SUCCESS" "Бэкап старого формата извлечён"
            else
                # Очень старый формат - вся директория является приложением
                mv "$temp_extract_dir/$backup_dir_name" "$target_dir"
                echo -e "\033[1;32m✅ Бэкап успешно извлечён (устаревший формат)\033[0m"
                log_restore_operation "Archive Extraction" "SUCCESS" "Очень старый формат бэкапа извлечён"
            fi
        else
            echo -e "\033[1;31m❌ Неожиданная структура бэкапа!\033[0m"
            log_restore_operation "Archive Extraction" "ERROR" "Неожиданная структура бэкапа"
            rm -rf "$temp_extract_dir"
            return 1
        fi
    else
        echo -e "\033[1;31m❌ Не удалось извлечь бэкап!\033[0m"
        log_restore_operation "Archive Extraction" "ERROR" "Не удалось извлечь tar-архив"
        rm -rf "$temp_extract_dir"
        return 1
    fi
    
    rm -rf "$temp_extract_dir"
    
    # Step 4: Проверка совместимости версий (если есть метаданные)
    if [ -f "$target_dir/backup-metadata.json" ]; then
        echo -e "\033[38;5;250m📝 Шаг 4a:\033[0m Проверка совместимости версий..."
        check_version_compatibility "$target_dir/backup-metadata.json"
    fi
    
    # Step 4: Валидация извлеченного бэкапа
    echo -e "\033[38;5;250m📝 Шаг 4:\033[0m Проверка извлечённого бэкапа..."
    if ! validate_extracted_backup "$target_dir" "full" "$target_app_name"; then
        echo -e "\033[1;31m❌ Backup validation failed! Rolling back...\033[0m"
        log_restore_operation "Backup Validation" "ERROR" "Валидация не пройдена, запускаем откат"
        rollback_from_safety_backup "$target_dir" "$target_app_name"
        return 1
    else
        log_restore_operation "Backup Validation" "SUCCESS" "Извлечённый бэкап валидирован"
    fi
    
    # Step 5: Установка управляющего скрипта
    if [ "$skip_install" = false ]; then
        echo -e "\033[38;5;250m📝 Шаг 5:\033[0m Установка управляющего скрипта..."
        
        local script_source=""
        
        # Ищем скрипт в порядке приоритета
        if [ -f "/tmp/restore_script_$$" ]; then
            script_source="/tmp/restore_script_$$"
            echo -e "\033[38;5;244m   Using script from backup\033[0m"
        elif [ -f "$target_dir/install-script.sh" ]; then
            script_source="$target_dir/install-script.sh"
            echo -e "\033[38;5;244m   Using script from extracted files\033[0m"
        elif [ -f "/usr/local/bin/$APP_NAME" ]; then
            script_source="/usr/local/bin/$APP_NAME"
            echo -e "\033[38;5;244m   Using current system script\033[0m"
        fi
        
        if [ -n "$script_source" ]; then
            # Обновляем APP_NAME в скрипте если нужно
            if [ "$target_app_name" != "$original_app_name" ] && [ "$original_app_name" != "unknown" ]; then
                echo -e "\033[38;5;244m   Adapting script for new app name...\033[0m"
                sed "s/APP_NAME=\"$original_app_name\"/APP_NAME=\"$target_app_name\"/" "$script_source" > "/usr/local/bin/$target_app_name"
            else
                cp "$script_source" "/usr/local/bin/$target_app_name"
            fi
            
            chmod +x "/usr/local/bin/$target_app_name"
            echo -e "\033[1;32m✅ Management script installed: /usr/local/bin/$target_app_name\033[0m"
            log_restore_operation "Script Installation" "SUCCESS" "Скрипт управления установлен: /usr/local/bin/$target_app_name"
        else
            echo -e "\033[1;33m⚠️  No management script found in backup, skipping installation\033[0m"
            log_restore_operation "Script Installation" "WARNING" "Скрипт управления не найден в бэкапе"
        fi
        
        # Очищаем временный файл
        rm -f "/tmp/restore_script_$$"
    fi
    
    # Step 6: Запуск и восстановление БД (с расширенной обработкой ошибок)
    echo -e "\033[38;5;250m📝 Шаг 6:\033[0m Запуск восстановления базы данных..."
    if ! restore_database_in_existing_installation "$target_dir" "$target_app_name"; then
        echo -e "\033[1;31m❌ Database restore failed! Rolling back...\033[0m"
        log_restore_operation "Database Restore" "ERROR" "Восстановление базы данных не удалось, выполняется откат"
        rollback_from_safety_backup "$target_dir" "$target_app_name"
        return 1
    else
        log_restore_operation "Database Restore" "SUCCESS" "База данных успешно восстановлена"
    fi
    
    # Step 7: Проверка целостности восстановления
    echo -e "\033[38;5;250m📝 Шаг 7:\033[0m Финальная проверка целостности..."
    local integrity_result=0
    verify_restore_integrity "$target_dir" "$target_app_name" "full"
    integrity_result=$?
    
    if [ $integrity_result -eq 0 ]; then
        echo -e "\033[1;32m🎉 Full restore completed successfully!\033[0m"
        log_restore_operation "Full Restore" "SUCCESS" "Восстановление успешно завершено с полной целостностью"
        # Очищаем safety backup при успешном восстановлении
        if [ -f "/tmp/safety_backup_location_$$" ]; then
            local safety_backup_dir=$(cat "/tmp/safety_backup_location_$$")
            echo -e "\033[38;5;244m   Cleaning up safety backup: $safety_backup_dir\033[0m"
            rm -rf "$safety_backup_dir" 2>/dev/null
            rm -f "/tmp/safety_backup_location_$$"
            log_restore_operation "Cleanup" "SUCCESS" "Резервная копия удалена"
        fi
        return 0
    elif [ $integrity_result -eq 1 ]; then
        echo -e "\033[1;33m⚠️  Restore completed with warnings - please check the application\033[0m"
        log_restore_operation "Full Restore" "WARNING" "Восстановление завершено с предупреждениями о целостности"
        return 0
    else
        echo -e "\033[1;31m❌ Restore failed integrity check! Rolling back...\033[0m"
        log_restore_operation "Full Restore" "ERROR" "Восстановление не прошло проверку целостности, выполняется откат"
        rollback_from_safety_backup "$target_dir" "$target_app_name"
        return 1
    fi
}

restore_database_only() {
    local backup_file="$1"
    local backup_type="$2"
    local target_dir="$3"
    local target_app_name="$4"
    
    log_restore_operation "Database Only Restore" "STARTED" "File: $backup_file, Type: $backup_type, Target: $target_dir"
    
    # Step 1: Создание safety backup базы данных
    echo -e "\033[38;5;250m📝 Шаг 1:\033[0m Создание резервной копии базы данных..."
    local backup_parent_dir="$(dirname "$target_dir")/backups"
    mkdir -p "$backup_parent_dir"
    
    if ! create_safety_backup "$target_dir" "$target_app_name" "$backup_parent_dir"; then
        echo -e "\033[1;33m⚠️  Failed to create safety backup, continuing with caution...\033[0m"
        log_restore_operation "Safety Backup" "WARNING" "Не удалось создать резервную копию"
    else
        log_restore_operation "Safety Backup" "SUCCESS" "Резервная копия создана"
    fi
    
    echo -e "\033[38;5;250m📝 Шаг 2:\033[0m Подготовка файла базы данных..."
    
    local database_file=""
    
    # Получаем файл БД в зависимости от типа
    if [ "$backup_type" = "sql" ]; then
        database_file="$backup_file"
    elif [ "$backup_type" = "compressed_sql" ]; then
        # Распаковываем во временный файл
        database_file="/tmp/restore_db_$$.sql"
        if gunzip -c "$backup_file" > "$database_file"; then
            echo -e "\033[1;32m✅ SQL file decompressed\033[0m"
        else
            echo -e "\033[1;31m❌ Failed to decompress SQL file!\033[0m"
            return 1
        fi
    elif [ "$backup_type" = "archive" ]; then
        # Извлекаем файл базы данных из архива (поддержка разных имен)
        local temp_db_dir="/tmp/restore_db_$$"
        mkdir -p "$temp_db_dir"
        
        # Сначала получаем список всех файлов в архиве
        local archive_contents
        mapfile -t archive_contents < <(tar -tzf "$backup_file" 2>/dev/null | grep -E '\.(sql|sql\.gz|sql\.bz2|sql\.xz)$' | head -20)
        
        if [ ${#archive_contents[@]} -eq 0 ]; then
            echo -e "\033[1;31m❌ No database files found in archive!\033[0m"
            rm -rf "$temp_db_dir"
            return 1
        fi
        
        # Приоритетный список для выбора лучшего файла БД
        local priority_patterns=("database.sql" "db_backup.sql" "backup.sql" "dump.sql" "*.sql")
        local found_db_file=""
        local selected_file=""
        
        # Ищем файл по приоритету
        for pattern in "${priority_patterns[@]}"; do
            for archive_file in "${archive_contents[@]}"; do
                local basename_file=$(basename "$archive_file")
                if [[ "$basename_file" == $pattern ]]; then
                    selected_file="$archive_file"
                    break 2
                fi
            done
        done
        
        # Если не нашли по приоритету, берем первый SQL файл
        if [ -z "$selected_file" ] && [ ${#archive_contents[@]} -gt 0 ]; then
            selected_file="${archive_contents[0]}"
        fi
        
        if [ -n "$selected_file" ]; then
            echo -e "\033[38;5;250m📝 Extracting database file: $selected_file\033[0m"
            if tar -xzf "$backup_file" -C "$temp_db_dir" "$selected_file" 2>/dev/null; then
                found_db_file="$temp_db_dir/$selected_file"
                if [ -f "$found_db_file" ]; then
                    echo -e "\033[1;32m✅ Database file extracted from archive: $(basename "$found_db_file")\033[0m"
                    database_file="$found_db_file"
                else
                    echo -e "\033[1;31m❌ Extracted file not found: $found_db_file\033[0m"
                    rm -rf "$temp_db_dir"
                    return 1
                fi
            else
                echo -e "\033[1;31m❌ Failed to extract $selected_file from archive!\033[0m"
                rm -rf "$temp_db_dir"
                return 1
            fi
        else
            echo -e "\033[1;31m❌ No suitable database files found in archive!\033[0m"
            rm -rf "$temp_db_dir"
            return 1
        fi
    fi
    
    # Step 3: Валидация файла базы данных
    if [ -n "$database_file" ] && [ -f "$database_file" ]; then
        echo -e "\033[38;5;250m📝 Шаг 3:\033[0m Проверка файла базы данных..."
        
        # Используем улучшенную валидацию SQL
        if ! validate_sql_integrity "$database_file"; then
            echo -e "\033[1;31m❌ Database file validation failed! Rolling back...\033[0m"
            log_restore_operation "SQL Validation" "ERROR" "Файл базы данных не прошёл валидацию"
            rollback_from_safety_backup "$target_dir" "$target_app_name"
            return 1
        fi
        
        log_restore_operation "SQL Validation" "SUCCESS" "Файл базы данных прошёл валидацию"
        echo -e "\033[1;32m✅ Database file validation passed\033[0m"
    else
        echo -e "\033[1;31m❌ Database file not found or inaccessible!\033[0m"
        log_restore_operation "File Check" "ERROR" "Файл базы данных не найден или недоступен"
        return 1
    fi
    
    # Step 4: Восстанавливаем БД в существующей установке (с обработкой ошибок)
    if ! restore_database_in_existing_installation "$target_dir" "$target_app_name" "$database_file"; then
        echo -e "\033[1;31m❌ Database restore failed! Rolling back...\033[0m"
        log_restore_operation "Database Restore" "ERROR" "Восстановление базы данных не удалось, выполняется откат"
        rollback_from_safety_backup "$target_dir" "$target_app_name"
        return 1
    fi
    
    # Step 5: Проверка целостности БД
    echo -e "\033[38;5;250m📝 Шаг 5:\033[0m Проверка целостности базы данных..."
    local integrity_result=0
    verify_restore_integrity "$target_dir" "$target_app_name" "database"
    integrity_result=$?
    
    if [ $integrity_result -le 1 ]; then
        echo -e "\033[1;32m🎉 Database restore completed successfully!\033[0m"
        log_restore_operation "Database Only Restore" "SUCCESS" "Восстановление базы данных завершено с проверкой целостности"
        # Очищаем safety backup при успешном восстановлении
        if [ -f "/tmp/safety_backup_location_$$" ]; then
            local safety_backup_dir=$(cat "/tmp/safety_backup_location_$$")
            echo -e "\033[38;5;244m   Cleaning up safety backup: $safety_backup_dir\033[0m"
            rm -rf "$safety_backup_dir" 2>/dev/null
            rm -f "/tmp/safety_backup_location_$$"
        fi
    else
        echo -e "\033[1;33m⚠️  Database restore completed but integrity check has warnings\033[0m"
    fi
    
    # Очищаем временные файлы
    if [ "$backup_type" = "compressed_sql" ]; then
        rm -f "/tmp/restore_db_$$.sql"
    elif [ "$backup_type" = "archive" ]; then
        rm -rf "/tmp/restore_db_$$"
    fi
}
restore_database_in_existing_installation() {
    local target_dir="$1"
    local target_app_name="$2"
    local database_file="$3"
    
    log_restore_operation "Database Installation" "STARTED" "Target: $target_dir, App: $target_app_name"

    if [ -z "$database_file" ]; then
        # Ищем файл БД в target_dir более надежным способом
        local found_db_files=()
        
        # Используем find для поиска всех файлов БД
        mapfile -t found_db_files < <(
            find "$target_dir" -maxdepth 1 -type f \( \
                -name "*.sql" -o \
                -name "*.sql.gz" -o \
                -name "*.sql.bz2" -o \
                -name "*.sql.xz" \
            \) -printf '%f\n' 2>/dev/null | sort
        )
        
        # Если find не поддерживает -printf, используем альтернативный метод
        if [ ${#found_db_files[@]} -eq 0 ]; then
            while IFS= read -r -d '' file; do
                found_db_files+=("$(basename "$file")")
            done < <(find "$target_dir" -maxdepth 1 -type f \( \
                -name "*.sql" -o \
                -name "*.sql.gz" -o \
                -name "*.sql.bz2" -o \
                -name "*.sql.xz" \
            \) -print0 2>/dev/null | sort -z)
        fi
        
        if [ ${#found_db_files[@]} -eq 0 ]; then
            echo -e "\033[1;31m❌ No database files found in $target_dir!\033[0m"
            return 1
        fi
        
        # Приоритетный выбор файла БД
        local priority_patterns=("database.sql" "db_backup.sql" "backup.sql" "dump.sql")
        local selected_db_file=""
        
        # Сначала ищем по приоритету среди несжатых файлов
        for pattern in "${priority_patterns[@]}"; do
            for db_file in "${found_db_files[@]}"; do
                if [[ "$db_file" == "$pattern" ]]; then
                    selected_db_file="$db_file"
                    break 2
                fi
            done
        done
        
        # Если не нашли несжатый, ищем сжатый по приоритету
        if [ -z "$selected_db_file" ]; then
            for pattern in "${priority_patterns[@]}"; do
                for db_file in "${found_db_files[@]}"; do
                    if [[ "$db_file" == "${pattern}.gz" ]] || [[ "$db_file" == "${pattern}.bz2" ]] || [[ "$db_file" == "${pattern}.xz" ]]; then
                        selected_db_file="$db_file"
                        break 2
                    fi
                done
            done
        fi
        
        # Если все еще не нашли, берем первый доступный файл
        if [ -z "$selected_db_file" ] && [ ${#found_db_files[@]} -gt 0 ]; then
            selected_db_file="${found_db_files[0]}"
        fi
        
        if [ -n "$selected_db_file" ]; then
            local full_db_path="$target_dir/$selected_db_file"
            
            # Проверяем, сжат ли файл
            if [[ "$selected_db_file" =~ \.(gz|bz2|xz)$ ]]; then
                local temp_sql="/tmp/restore_expanded_$$.sql"
                local decompress_cmd=""
                
                case "$selected_db_file" in
                    *.gz) decompress_cmd="gunzip -c" ;;
                    *.bz2) decompress_cmd="bunzip2 -c" ;;
                    *.xz) decompress_cmd="xz -dc" ;;
                esac
                
                if $decompress_cmd "$full_db_path" > "$temp_sql" 2>/dev/null; then
                    database_file="$temp_sql"
                    log_restore_operation "Database File" "INFO" "Используется сжатый $selected_db_file из целевой директории (распакован)"
                    echo -e "\033[38;5;244m   Found compressed database file: $selected_db_file (decompressed)\033[0m"
                else
                    echo -e "\033[1;33m⚠️  Failed to decompress $selected_db_file\033[0m"
                fi
            else
                database_file="$full_db_path"
                log_restore_operation "Database File" "INFO" "Используется $selected_db_file из целевой директории"
                echo -e "\033[38;5;244m   Found database file: $selected_db_file\033[0m"
            fi
        fi
    fi
    
    if [ -z "$database_file" ] || [ ! -f "$database_file" ]; then
        echo -e "\033[1;31m❌ Database file not found!\033[0m"
        echo -e "\033[38;5;244m   Expected: $target_dir/database.sql\033[0m"
        return 1
    fi
    
    # Дополнительная валидация файла БД
    local db_size=$(wc -c < "$database_file" 2>/dev/null || echo "0")
    if [ "$db_size" -lt 100 ]; then
        echo -e "\033[1;31m❌ Database file appears to be empty or corrupted (size: $db_size bytes)!\033[0m"
        return 1
    fi
    
    if [ ! -f "$target_dir/docker-compose.yml" ]; then
        echo -e "\033[1;31m❌ No docker-compose.yml found! Cannot restore database.\033[0m"
        return 1
    fi
    cd "$target_dir"
    
    echo -e "\033[38;5;250m📝 Starting database service...\033[0m"
    
    # Запускаем ТОЛЬКО базу данных для восстановления
    local db_startup_log="/tmp/db_startup_$$.log"
    if docker compose up -d "${target_app_name}-db" 2>"$db_startup_log"; then
        echo -e "\033[1;32m✅ Database service started\033[0m"
        
        # Ждем готовности базы данных с улучшенным логированием
        echo -e "\033[38;5;244m   Waiting for database to be ready...\033[0m"
        local attempts=0
        local max_attempts=30
        
        while [ $attempts -lt $max_attempts ]; do
            if docker exec "${target_app_name}-db" pg_isready -U postgres >/dev/null 2>&1; then
                echo -e "\033[1;32m✅ Database is ready (attempt $((attempts + 1)))\033[0m"
                break
            fi
            
            sleep 2
            attempts=$((attempts + 1))
            
            if [ $attempts -eq $max_attempts ]; then
                echo -e "\033[1;31m❌ База данных не запустилась после $max_attempts попыток!\033[0m"
                echo -e "\033[38;5;244m   Проверьте логи: docker compose logs ${target_app_name}-db\033[0m"
                if [ -f "$db_startup_log" ]; then
                    echo -e "\033[38;5;244m   Startup errors:\033[0m"
                    head -10 "$db_startup_log" | sed 's/^/     /'
                fi
                rm -f "$db_startup_log"
                return 1
            fi
        done
    else
        echo -e "\033[1;31m❌ Failed to start database service!\033[0m"
        if [ -f "$db_startup_log" ]; then
            echo -e "\033[38;5;244m   Startup errors:\033[0m"
            head -10 "$db_startup_log" | sed 's/^/     /'
        fi
        rm -f "$db_startup_log"
        return 1
    fi
    
    rm -f "$db_startup_log"
    
    echo -e "\033[38;5;250m📝 Restoring database...\033[0m"
    
    local db_container="${target_app_name}-db"
    local postgres_user="postgres"
    local postgres_password="postgres"
    local postgres_db="postgres"
    
    # Читаем настройки из env файла если доступны
    if [ -f "$target_dir/.env" ]; then
        postgres_user=$(grep "^POSTGRES_USER=" "$target_dir/.env" | cut -d'=' -f2 2>/dev/null || echo "postgres")
        postgres_password=$(grep "^POSTGRES_PASSWORD=" "$target_dir/.env" | cut -d'=' -f2 2>/dev/null || echo "postgres")
        postgres_db=$(grep "^POSTGRES_DB=" "$target_dir/.env" | cut -d'=' -f2 2>/dev/null || echo "postgres")
        echo -e "\033[38;5;244m   Using database credentials from .env file\033[0m"
    fi
    
    # Проверяем подключение к БД
    if ! docker exec -e PGPASSWORD="$postgres_password" "$db_container" \
        psql -U "$postgres_user" -d "$postgres_db" -c "SELECT 1;" >/dev/null 2>&1; then
        echo -e "\033[1;31m❌ Cannot connect to database with provided credentials!\033[0m"
        return 1
    fi
    
    # Создаем резервную копию текущей схемы (если есть данные)
    echo -e "\033[38;5;244m   Creating current schema backup...\033[0m"
    local current_schema_backup="/tmp/current_schema_backup_$$.sql"
    docker exec -e PGPASSWORD="$postgres_password" "$db_container" \
        pg_dump -U "$postgres_user" -d "$postgres_db" --schema-only > "$current_schema_backup" 2>/dev/null || true
    
    # Очищаем текущую базу данных
    echo -e "\033[38;5;244m   Clearing current database...\033[0m"
    local clear_db_log="/tmp/clear_db_$$.log"
    if docker exec -e PGPASSWORD="$postgres_password" "$db_container" \
        psql -U "$postgres_user" -d "$postgres_db" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >"$clear_db_log" 2>&1; then
        echo -e "\033[1;32m✅ Database cleared\033[0m"
    else
        echo -e "\033[1;31m❌ Failed to clear database!\033[0m"
        echo -e "\033[38;5;244m   Clear operation errors:\033[0m"
        head -5 "$clear_db_log" | sed 's/^/     /'
        rm -f "$clear_db_log" "$current_schema_backup"
        return 1
    fi
    rm -f "$clear_db_log"
    
    # Восстанавливаем данные с улучшенной безопасностью и логированием
    echo -e "\033[38;5;244m   Importing backup data ($(du -sh "$database_file" | cut -f1))...\033[0m"
    local restore_log="/tmp/restore_db_$$.log"
    local restore_errors="/tmp/restore_errors_$$.log"
    
    # Создаем временный файл с улучшенными настройками восстановления
    local enhanced_sql="/tmp/enhanced_restore_$$.sql"
    cat > "$enhanced_sql" <<EOF
-- Отключаем уведомления для ускорения
SET client_min_messages = WARNING;
-- Улучшаем производительность
SET synchronous_commit = off;
SET wal_buffers = '16MB';
SET checkpoint_completion_target = 0.9;

-- Включаем содержимое оригинального файла
\\i $database_file

-- Обновляем статистику
ANALYZE;
EOF
    
    log_restore_operation "Database Import" "STARTED" "Importing $(du -sh "$database_file" | cut -f1) of data"
    
    if docker exec -i -e PGPASSWORD="$postgres_password" "$db_container" \
        psql -U "$postgres_user" -d "$postgres_db" --set ON_ERROR_STOP=on \
        -f "/tmp/enhanced_restore_$$.sql" >"$restore_log" 2>"$restore_errors"; then
        
        # Проверяем что данные действительно восстановились
        local table_count=$(docker exec -e PGPASSWORD="$postgres_password" "$db_container" \
            psql -U "$postgres_user" -d "$postgres_db" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")
        
        if [ "$table_count" -gt 0 ]; then
            echo -e "\033[1;32m✅ Database restored successfully ($table_count tables)\033[0m"
            log_restore_operation "Database Import" "SUCCESS" "Восстановлено таблиц: $table_count"
        else
            echo -e "\033[1;33m⚠️  Database restore completed but no tables found\033[0m"
            log_restore_operation "Database Import" "WARNING" "Восстановление завершено, но таблицы не найдены"
        fi
    else
        echo -e "\033[1;31m❌ Database restore failed!\033[0m"
        log_restore_operation "Database Import" "ERROR" "Восстановление базы данных не удалось"
        
        # Показываем детали ошибки если доступны
        if [ -f "$restore_errors" ] && [ -s "$restore_errors" ]; then
            echo -e "\033[38;5;244m   Error details:\033[0m"
            head -5 "$restore_errors" | sed 's/^/     /'
        fi
        if [ -f "$restore_errors" ] && [ -s "$restore_errors" ]; then
            echo -e "\033[38;5;244m   Restore errors:\033[0m"
            head -10 "$restore_errors" | sed 's/^/     /'
        fi
        echo -e "\033[38;5;244m   Check database logs: docker compose logs ${target_app_name}-db\033[0m"
        
        # Пытаемся восстановить старую схему при неудаче
        if [ -f "$current_schema_backup" ] && [ -s "$current_schema_backup" ]; then
            echo -e "\033[38;5;244m   Attempting to restore previous schema...\033[0m"
            docker exec -i -e PGPASSWORD="$postgres_password" "$db_container" \
                psql -U "$postgres_user" -d "$postgres_db" < "$current_schema_backup" >/dev/null 2>&1 || true
        fi
        
        rm -f "$restore_log" "$restore_errors" "$enhanced_sql" "$current_schema_backup"
        return 1
    fi
    
    # Очищаем временные файлы
    rm -f "$restore_log" "$restore_errors" "$enhanced_sql" "$current_schema_backup"
    
    # Очищаем временные файлы базы данных
    rm -f "$target_dir/database.sql" "$target_dir/db_backup.sql"
    
    # Останавливаем БД перед запуском всех сервисов
    echo -e "\033[38;5;250m📝 Stopping database service...\033[0m"
    docker compose down 2>/dev/null
    
    # Запускаем ВСЕ сервисы с улучшенной обработкой
    echo -e "\033[38;5;250m📝 Starting all services...\033[0m"
    
    local startup_log="/tmp/startup_$$.log"
    if docker compose up -d 2>"$startup_log"; then
        echo -e "\033[1;32m✅ All services started\033[0m"
    else
        echo -e "\033[1;33m⚠️  Service startup had issues\033[0m"
        if [ -f "$startup_log" ]; then
            echo -e "\033[38;5;244m   Startup warnings:\033[0m"
            head -5 "$startup_log" | sed 's/^/     /'
        fi
    fi
    rm -f "$startup_log"
    
    # Проверяем финальный статус с расширенной диагностикой
    echo -e "\033[38;5;244m   Performing health check...\033[0m"
    sleep 8
    
    local services_status=""
    if command -v jq >/dev/null 2>&1; then
        services_status=$(docker compose ps --format json 2>/dev/null | jq -r 'select(.Health == "healthy" or .State == "running") | .Service' 2>/dev/null)
        local healthy_services=$(echo "$services_status" | wc -l)
        local total_services=$(docker compose ps --format json 2>/dev/null | jq -r '.Service' 2>/dev/null | wc -l)
    else
        # Резервный метод без jq
        local healthy_services=$(docker compose ps | grep -c "Up\|healthy" || echo "0")
        local total_services=$(docker compose ps | tail -n +2 | wc -l)
    fi
    
    if [ "$healthy_services" -gt 0 ] && [ "$total_services" -gt 0 ]; then
        if [ "$healthy_services" -eq "$total_services" ]; then
            echo -e "\033[1;32m✅ All services healthy: $healthy_services/$total_services\033[0m"
        else
            echo -e "\033[1;33m⚠️  Partial health: $healthy_services/$total_services services healthy\033[0m"
            echo -e "\033[38;5;244m   Check individual service status: docker compose ps\033[0m"
        fi
    else
        echo -e "\033[1;33m⚠️  Service health check inconclusive\033[0m"
    fi
    
    return 0
}

schedule_test_backup() {
    clear
    echo -e "\033[1;37m🧪 Testing Backup Creation\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
    echo
    
    if ! is_remnawave_up; then
        echo -e "\033[1;31m❌ Сервисы Remnawave не запущены!\033[0m"
        echo -e "\033[38;5;8m   Start services first with 'sudo $APP_NAME up'\033[0m"
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
        return
    fi
    
    if ! ensure_backup_dirs; then
        return 1
    fi
    
    echo -e "\033[38;5;250mСоздание тестового бэкапа...\033[0m"
    
    # Проверяем версию backup скрипта
    check_backup_script_version
    local version_status=$?
    
    if [ $version_status -ne 0 ]; then
        echo
        if prompt_backup_script_update $version_status; then
            schedule_create_backup_script
            echo -e "\033[1;32m✅ Скрипт бэкапа успешно обновлен\033[0m"
            echo
        fi
    fi
    
    if [ ! -f "$BACKUP_SCRIPT_FILE" ]; then
        schedule_create_backup_script
    fi
    
    if [ ! -f "$BACKUP_CONFIG_FILE" ]; then
        echo -e "\033[1;33m⚠️  Конфигурация бэкапа не найдена. Создаю стандартную...\033[0m"
        schedule_reset_config 
    fi
    
    if bash "$BACKUP_SCRIPT_FILE"; then
        echo -e "\033[1;32m✅ Test backup completed successfully!\033[0m"
        echo -e "\033[38;5;250mCheck $APP_DIR/backups for the backup file\033[0m"
    else
        echo -e "\033[1;31m❌ Test backup failed!\033[0m"
        echo -e "\033[38;5;8m   Проверьте логи: $BACKUP_LOG_FILE\033[0m"
    fi
    
    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
}

schedule_test_telegram() {
    clear
    echo -e "\033[1;37m📱 Testing Telegram Integration\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 35))\033[0m"
    echo
    
    if [ ! -f "$BACKUP_CONFIG_FILE" ]; then
        echo -e "\033[1;31m❌ No configuration found!\033[0m"
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
        return
    fi
    
    local telegram_enabled=$(jq -r '.telegram.enabled // false' "$BACKUP_CONFIG_FILE" 2>/dev/null)
    if [ "$telegram_enabled" != "true" ]; then
        echo -e "\033[1;31m❌ Telegram integration is disabled!\033[0m"
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
        return
    fi
    
    local bot_token=$(jq -r '.telegram.bot_token' "$BACKUP_CONFIG_FILE" 2>/dev/null)
    local chat_id=$(jq -r '.telegram.chat_id' "$BACKUP_CONFIG_FILE" 2>/dev/null)
    local thread_id=$(jq -r '.telegram.thread_id' "$BACKUP_CONFIG_FILE" 2>/dev/null)
    
    echo -e "\033[38;5;250mSending test message...\033[0m"
    
    local api_url="https://api.telegram.org/bot$bot_token"
    local message="🧪 Test message from Remnawave Backup System
📅 $(date '+%Y-%m-%d %H:%M:%S')
✅ Telegram integration is working correctly!"
    
    local params="chat_id=$chat_id&text=$(echo "$message" | sed 's/ /%20/g')"
    
    if [ -n "$thread_id" ] && [ "$thread_id" != "null" ]; then
        params="$params&message_thread_id=$thread_id"
    fi
    
    local response=$(curl -s -X POST "$api_url/sendMessage" -d "$params")
    
    if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
        echo -e "\033[1;32m✅ Тестовое сообщение успешно отправлено!\033[0m"
        echo -e "\033[38;5;250mCheck your Telegram for the test message\033[0m"
    else
        echo -e "\033[1;31m❌ Не удалось отправить тестовое сообщение!\033[0m"
        echo -e "\033[38;5;244mResponse: $(echo "$response" | jq -r '.description // "Unknown error"')\033[0m"
    fi
    
    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
}

schedule_status() {
    clear
    echo -e "\033[1;37m📊 Backup Scheduler Status\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 35))\033[0m"
    echo
      local status=$(schedule_get_status)
    
    # Проверяем статус cron service
    echo -e "\033[1;37m🔧 System Status:\033[0m"
    if command -v crontab >/dev/null 2>&1; then
        echo -e "\033[1;32m✅ Cron service: Available\033[0m"
        
        # Проверяем запущен ли cron daemon
        if systemctl is-active cron >/dev/null 2>&1 || systemctl is-active crond >/dev/null 2>&1 || pgrep -x "cron\|crond" >/dev/null 2>&1; then
            echo -e "\033[1;32m✅ Cron daemon: Running\033[0m"
        else
            echo -e "\033[1;33m⚠️  Cron daemon: Not running\033[0m"
        fi
    else
        echo -e "\033[1;31m❌ Cron service: Not installed\033[0m"
        echo -e "\033[38;5;244m   Install with: sudo apt-get install cron\033[0m"
    fi
    echo
    
    echo -e "\033[1;37m📋 Scheduler Status:\033[0m"
    if [ "$status" = "enabled" ]; then
        echo -e "\033[1;32m✅ Status: ENABLED\033[0m"
        

        local cron_line=$(crontab -l 2>/dev/null | grep "$BACKUP_SCRIPT_FILE")
        if [ -n "$cron_line" ]; then
            local schedule=$(echo "$cron_line" | awk '{print $1" "$2" "$3" "$4" "$5}')
            echo -e "\033[38;5;250mРасписание: $schedule\033[0m"
        fi
        
        if command -v crontab >/dev/null && [ -n "$cron_line" ]; then

            local schedule_desc=""
            case "$schedule" in
                "0 2 * * *") schedule_desc="Daily at 2:00 AM" ;;
                "0 4 * * *") schedule_desc="Daily at 4:00 AM" ;;
                "0 */12 * * *") schedule_desc="Every 12 hours" ;;
                "0 2 * * 0") schedule_desc="Weekly on Sunday at 2:00 AM" ;;
                *) schedule_desc="Custom: $schedule" ;;
            esac
            echo -e "\033[38;5;250mFrequency: $schedule_desc\033[0m"
        fi
    else
        echo -e "\033[1;31m❌ Status: DISABLED\033[0m"
    fi
    
    # Проверяем версию backup скрипта
    echo
    echo -e "\033[1;37m🔧 Backup Script Status:\033[0m"
    
    check_backup_script_version
    local version_status=$?
    
    case $version_status in
        0)
            echo -e "\033[1;32m✅ Script version: Current ($BACKUP_SCRIPT_VERSION)\033[0m"
            ;;
        1)
            echo -e "\033[1;33m⚠️  Script status: Not found\033[0m"
            echo -e "\033[38;5;244m   Will be created automatically when needed\033[0m"
            ;;
        2)
            echo -e "\033[1;31m❌ Script version: Legacy (no version info)\033[0m"
            echo -e "\033[38;5;244m   Update recommended for latest features\033[0m"
            ;;
        3)
            # Безопасное чтение версии с timeout
            local script_version=""
            if command -v timeout >/dev/null 2>&1; then
                script_version=$(timeout 5 head -5 "$BACKUP_SCRIPT_FILE" 2>/dev/null | grep "^BACKUP_SCRIPT_VERSION=" | cut -d'"' -f2 2>/dev/null)
            else
                script_version=$(head -5 "$BACKUP_SCRIPT_FILE" 2>/dev/null | grep "^BACKUP_SCRIPT_VERSION=" | cut -d'"' -f2 2>/dev/null)
            fi
            echo -e "\033[1;33m⚠️  Script version: Outdated (${script_version:-'unknown'})\033[0m"
            echo -e "\033[38;5;244m   Current version: $BACKUP_SCRIPT_VERSION - update recommended\033[0m"
            ;;
    esac

    echo
    echo -e "\033[1;37m📦 Recent Backups:\033[0m"
    

    local backup_directory="$APP_DIR/backups"
    

    if [ ! -d "$backup_directory" ]; then
        echo -e "\033[38;5;244m   Backup directory not found: $backup_directory\033[0m"
        echo -e "\033[38;5;244m   Запустите бэкап для создания директории\033[0m"
    else

        local backup_files=""
        

        backup_files=$(ls -t "$backup_directory"/remnawave_scheduled_*.tar.gz "$backup_directory"/remnawave_scheduled_*.sql.gz "$backup_directory"/remnawave_scheduled_*.sql 2>/dev/null | head -5)
        

        if [ -z "$backup_files" ]; then
            backup_files=$(ls -t "$backup_directory"/remnawave_*.tar.gz "$backup_directory"/remnawave_*.sql.gz "$backup_directory"/remnawave_*.sql 2>/dev/null | head -5)
        fi
        
        if [ -n "$backup_files" ]; then
            echo "$backup_files" | while IFS= read -r file; do
                if [ -f "$file" ]; then
                    local filename=$(basename "$file")
                    local file_size=$(du -sh "$file" 2>/dev/null | cut -f1)
                    local file_date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
                    

                    local backup_type="📦"
                    if [[ "$filename" =~ scheduled ]]; then
                        backup_type="🤖"  # автоматический
                    elif [[ "$filename" =~ full ]]; then
                        backup_type="📁"  # полный ручной
                    else
                        backup_type="📊"  # обычный
                    fi
                    
                    printf "   %s \033[38;5;250m%-35s\033[0m \033[38;5;244m%s\033[0m \033[38;5;244m%s\033[0m\n" "$backup_type" "$filename" "$file_size" "$file_date"
                fi
            done
        else
            echo -e "\033[38;5;244m   No backup files found in $backup_directory\033[0m"
            echo -e "\033[38;5;244m   Run a backup to see files here\033[0m"
        fi
    fi
    

    echo
    echo -e "\033[1;37m📈 Statistics:\033[0m"
    
    if [ -d "$backup_directory" ]; then

        local total_backups=$(find "$backup_directory" -maxdepth 1 -type f \( \
            -name "remnawave_*.tar.gz" -o \
            -name "remnawave_*.sql" -o \
            -name "remnawave_*.sql.gz" -o \
            -name "remnawave_*.sql.bz2" -o \
            -name "remnawave_*.sql.xz" \
        \) 2>/dev/null | wc -l)
        local scheduled_backups=$(find "$backup_directory" -maxdepth 1 -type f \( \
            -name "remnawave_scheduled_*.tar.gz" -o \
            -name "remnawave_scheduled_*.sql" -o \
            -name "remnawave_scheduled_*.sql.gz" -o \
            -name "remnawave_scheduled_*.sql.bz2" -o \
            -name "remnawave_scheduled_*.sql.xz" \
        \) 2>/dev/null | wc -l)
        local manual_backups=$(find "$backup_directory" -maxdepth 1 -type f \( \
            -name "remnawave_full_*.tar.gz" -o \
            -name "remnawave_full_*.sql" -o \
            -name "remnawave_full_*.sql.gz" -o \
            -name "remnawave_full_*.sql.bz2" -o \
            -name "remnawave_full_*.sql.xz" -o \
            -name "remnawave_db_*.sql" -o \
            -name "remnawave_db_*.sql.gz" -o \
            -name "remnawave_db_*.sql.bz2" -o \
            -name "remnawave_db_*.sql.xz" \
        \) 2>/dev/null | wc -l)
        
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Всего бэкапов:" "$total_backups"
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Запланированные бэкапы:" "$scheduled_backups"
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Ручные бэкапы:" "$manual_backups"
        

        local backup_dir_size=$(du -sh "$backup_directory" 2>/dev/null | cut -f1)
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Общий размер:" "$backup_dir_size"
    else
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Всего бэкапов:" "0"
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Запланированные бэкапы:" "0"
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Ручные бэкапы:" "0"
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Общий размер:" "0B"
    fi
    
    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
}


schedule_show_logs() {
    clear
    echo -e "\033[1;37m📋 Логи бэкапа\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 20))\033[0m"
    echo
    
    if [ -f "$BACKUP_LOG_FILE" ]; then

        local log_size=$(du -sh "$BACKUP_LOG_FILE" 2>/dev/null | cut -f1)
        echo -e "\033[38;5;250mФайл лога: $(basename "$BACKUP_LOG_FILE") ($log_size)\033[0m"
        echo -e "\033[38;5;250mПуть: $BACKUP_LOG_FILE\033[0m"
        echo
        echo -e "\033[38;5;250mПоследние 30 записей:\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        
        tail -30 "$BACKUP_LOG_FILE" | while IFS= read -r line; do
            if echo "$line" | grep -q "ERROR\|FAILED\|Failed"; then
                echo -e "\033[1;31m$line\033[0m"
            elif echo "$line" | grep -q "SUCCESS\|successfully\|SUCCESS\|✅\|completed"; then
                echo -e "\033[1;32m$line\033[0m"
            elif echo "$line" | grep -q "MANUAL BACKUP\|==="; then
                echo -e "\033[1;37m$line\033[0m"
            elif echo "$line" | grep -q "WARNING\|⚠️"; then
                echo -e "\033[1;33m$line\033[0m"
            elif echo "$line" | grep -q "Starting\|Step\|Creating"; then
                echo -e "\033[1;36m$line\033[0m"
            else
                echo -e "\033[38;5;250m$line\033[0m"
            fi
        done
        
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        echo
        echo -e "\033[38;5;244m💡 Команды:\033[0m"
        echo -e "\033[38;5;244m   Смотреть полный лог: tail -f $BACKUP_LOG_FILE\033[0m"
        echo -e "\033[38;5;244m   Очистить лог: > $BACKUP_LOG_FILE\033[0m"
    else
        echo -e "\033[38;5;244mФайл лога не найден по пути: $BACKUP_LOG_FILE\033[0m"
        echo -e "\033[38;5;244mЛоги появятся после первого запуска бэкапа\033[0m"
    fi
    
    echo
    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
}

schedule_run_backup() {
    clear
    echo -e "\033[1;37m▶️  Ручной запуск полного бэкапа\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 35))\033[0m"
    echo
    
    if ! is_remnawave_up; then
        echo -e "\033[1;31m❌ Сервисы Remnawave не запущены!\033[0m"
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
        return
    fi
    
    echo -e "\033[1;37m📦 Тип бэкапа: Полный системный бэкап\033[0m"
    echo -e "\033[38;5;250m   ✓ База PostgreSQL (полный дамп)\033[0m"
    echo -e "\033[38;5;250m   ✓ Файлы окружения (.env, .env.subscription)\033[0m"
    echo -e "\033[38;5;250m   ✓ Конфигурация Docker Compose\033[0m"
    echo -e "\033[38;5;250m   ✓ Все доп. конфиги (*.json, *.yml и т. п.)\033[0m"
    echo -e "\033[38;5;250m   ✓ Каталоги конфигурации (certs, custom и др.)\033[0m"
    echo
    echo -e "\033[38;5;250m🏃‍♂️ Запуск бэкапа...\033[0m"
    echo

    # Создаем/обновляем backup скрипт
    if [ ! -f "$BACKUP_SCRIPT_FILE" ]; then
        schedule_create_backup_script
        echo -e "\033[1;32m✅ Скрипт бэкапа создан\033[0m"
        echo
    fi
    
    if [ ! -f "$BACKUP_SCRIPT_FILE" ]; then
        schedule_create_backup_script
    fi
    mkdir -p "$(dirname "$BACKUP_LOG_FILE")"
    
    echo "" >> "$BACKUP_LOG_FILE"
    echo "=============================================" >> "$BACKUP_LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MANUAL FULL BACKUP STARTED by user" >> "$BACKUP_LOG_FILE"
    echo "=============================================" >> "$BACKUP_LOG_FILE"
    
    # Запускаем backup скрипт
    bash "$BACKUP_SCRIPT_FILE" 2>&1 | tee -a "$BACKUP_LOG_FILE"
    
    local exit_code=${PIPESTATUS[0]}
    
    echo "=============================================" >> "$BACKUP_LOG_FILE"
    if [ $exit_code -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] MANUAL FULL BACKUP COMPLETED SUCCESSFULLY" >> "$BACKUP_LOG_FILE"
        echo -e "\033[1;32m🎉 Ручной полный бэкап успешно завершён!\033[0m"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] MANUAL FULL BACKUP FAILED" >> "$BACKUP_LOG_FILE"
        echo -e "\033[1;31m❌ Ручной полный бэкап завершился с ошибкой!\033[0m"
    fi
    echo "=============================================" >> "$BACKUP_LOG_FILE"
    echo "" >> "$BACKUP_LOG_FILE"
    
    echo
    echo -e "\033[1;37m📋 Backup Information:\033[0m"
    echo -e "\033[38;5;250m   Type: Full system backup (database + all configs)\033[0m"
    echo -e "\033[38;5;250m   Location: $APP_DIR/backups/\033[0m"
    echo -e "\033[38;5;250m   Логи: $BACKUP_LOG_FILE\033[0m"
    
    local latest_backup=$(ls -t "$APP_DIR/backups"/remnawave_scheduled_*.{tar.gz,sql} 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
        local backup_size=$(du -sh "$latest_backup" | cut -f1)
        echo -e "\033[38;5;250m   Latest: $(basename "$latest_backup") ($backup_size)\033[0m"
    fi
    
    echo
    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
}
schedule_cleanup() {
    clear
    echo -e "\033[1;37m🧹 Cleanup Old Backups\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 25))\033[0m"
    echo
    
    local backup_directory="$APP_DIR/backups"
    
    if [ ! -d "$backup_directory" ]; then
        echo -e "\033[38;5;244mBackup directory not found: $backup_directory\033[0m"
        echo -e "\033[38;5;244mNo backups to clean\033[0m"
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
        return
    fi

    local retention_days=7
    local min_backups=3
    
    if [ -f "$BACKUP_CONFIG_FILE" ]; then
        retention_days=$(jq -r '.retention.days // 7' "$BACKUP_CONFIG_FILE" 2>/dev/null)
        min_backups=$(jq -r '.retention.min_backups // 3' "$BACKUP_CONFIG_FILE" 2>/dev/null)
    fi
    
    echo -e "\033[1;37m📋 Cleanup Configuration:\033[0m"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s дней\033[0m\n" "Период хранения:" "$retention_days"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s файлов\033[0m\n" "Минимум для хранения:" "$min_backups"
    echo

    local all_backups=$(ls -t "$backup_directory"/remnawave_*.tar.gz "$backup_directory"/remnawave_*.sql.gz "$backup_directory"/remnawave_*.sql 2>/dev/null)
    local total_files=$(echo "$all_backups" | grep -c . 2>/dev/null || echo "0")
    
    echo -e "\033[1;37m📊 Current Status:\033[0m"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Всего файлов бэкапа:" "$total_files"
    
    if [ "$total_files" -eq 0 ]; then
        echo -e "\033[38;5;244mNo backup files found in $backup_directory\033[0m"
        echo -e "\033[38;5;244mNothing to clean\033[0m"
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
        return
    fi
    local dir_size=$(du -sh "$backup_directory" 2>/dev/null | cut -f1)
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Размер директории:" "$dir_size"
    echo
    local old_files=""
    local old_count=0
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - retention_days * 86400))
    
    echo -e "\033[1;37m🔍 Analyzing backup files:\033[0m"
    echo "$all_backups" | while IFS= read -r file; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local file_size=$(du -sh "$file" 2>/dev/null | cut -f1)
            local file_time=$(stat -c %Y "$file" 2>/dev/null)
            local file_date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
            local age_days=$(( (current_time - file_time) / 86400 ))
            local file_type="📦"
            local status_color="38;5;250"
            local status_text="Keep"
            
            if [[ "$filename" =~ scheduled ]]; then
                file_type="🤖"
            elif [[ "$filename" =~ full ]]; then
                file_type="📁"
            else
                file_type="📊"
            fi
            
            if [ $age_days -gt $retention_days ]; then
                status_color="1;31"
                status_text="DELETE (${age_days}d old)"
            else
                status_text="Keep (${age_days}d old)"
            fi
            
            printf "   %s \033[38;5;250m%-30s\033[0m \033[38;5;244m%s\033[0m \033[38;5;244m%s\033[0m \033[${status_color}m%s\033[0m\n" \
                "$file_type" "$filename" "$file_size" "$file_date" "$status_text"
        fi
    done
    echo "$all_backups" | while IFS= read -r file; do
        if [ -f "$file" ]; then
            local file_time=$(stat -c %Y "$file" 2>/dev/null)
            if [ $file_time -lt $cutoff_time ]; then
                echo "$file"
            fi
        fi
    done > /tmp/files_to_delete_$$
    
    old_files=$(cat /tmp/files_to_delete_$$ 2>/dev/null)
    old_count=$(cat /tmp/files_to_delete_$$ 2>/dev/null | wc -l)
    rm -f /tmp/files_to_delete_$$
    
    echo

    local remaining_count=$((total_files - old_count))
    
    if [ $remaining_count -lt $min_backups ]; then
        local files_to_keep=$((min_backups - remaining_count))
        echo -e "\033[1;33m⚠️  Protection activated!\033[0m"
        echo -e "\033[38;5;250mWould keep minimum $min_backups backups, reducing deletion by $files_to_keep files\033[0m"

        old_files=$(echo "$all_backups" | tail -n +$((min_backups + 1)) | while IFS= read -r file; do
            if [ -f "$file" ]; then
                local file_time=$(stat -c %Y "$file" 2>/dev/null)
                if [ $file_time -lt $cutoff_time ]; then
                    echo "$file"
                fi
            fi
        done)
        old_count=$(echo "$old_files" | grep -c . 2>/dev/null || echo "0")
    fi
    
    if [ "$old_count" -eq 0 ] || [ -z "$old_files" ]; then
        echo -e "\033[1;32m✅ No files to delete\033[0m"
        echo -e "\033[38;5;250mAll backups are within retention period or protected by minimum count\033[0m"
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
        return
    fi
    

    echo -e "\033[1;37m📋 Cleanup Summary:\033[0m"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Файлов к удалению:" "$old_count"
    printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Файлов к сохранению:" "$remaining_count"
    
    # Простой подсчет размера без сложных операций
    local delete_size=0
    local temp_file="/tmp/delete_size_$$"
    echo "0" > "$temp_file"
    
    for file in $old_files; do
        if [ -f "$file" ]; then
            local size_bytes=$(stat -c %s "$file" 2>/dev/null || echo "0")
            delete_size=$((delete_size + size_bytes))
        fi
    done
    echo "$delete_size" > "$temp_file"
    
    local delete_size_human=""
    if command -v numfmt >/dev/null 2>&1; then
        delete_size_human=$(numfmt --to=iec --suffix=B $(cat "$temp_file" 2>/dev/null || echo "0"))
    else
        delete_size_human="Unknown"
    fi
    rm -f "$temp_file"
    
    if [ "$delete_size_human" != "Unknown" ]; then
        printf "   \033[38;5;15m%-20s\033[0m \033[38;5;250m%s\033[0m\n" "Место для освобождения:" "$delete_size_human"
    fi
    
    echo
    echo -n "Proceed with cleanup? [y/N]: "
    read confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo
        echo -e "\033[1;37m🗑️  Deleting old backup files...\033[0m"
        
        local deleted_count=0
        local failed_count=0
        
        echo "$old_files" | while IFS= read -r file; do
            if [ -f "$file" ]; then
                local filename=$(basename "$file")
                if rm -f "$file" 2>/dev/null; then
                    echo -e "\033[1;32m   ✅ Deleted: $filename\033[0m"
                    deleted_count=$((deleted_count + 1))
                else
                    echo -e "\033[1;31m   ❌ Failed to delete: $filename\033[0m"
                    failed_count=$((failed_count + 1))
                fi
            fi
        done
        
        echo
        if [ $failed_count -eq 0 ]; then
            echo -e "\033[1;32m🎉 Cleanup completed successfully!\033[0m"
            echo -e "\033[38;5;250mDeleted $old_count backup files\033[0m"
        else
            echo -e "\033[1;33m⚠️  Cleanup completed with warnings\033[0m"
            echo -e "\033[38;5;250mDeleted: $deleted_count, Failed: $failed_count\033[0m"
        fi
        local new_dir_size=$(du -sh "$backup_directory" 2>/dev/null | cut -f1)
        echo -e "\033[38;5;250mNew directory size: $new_dir_size\033[0m"
    else
        echo -e "\033[38;5;250mCleanup cancelled\033[0m"
    fi
    
    echo
    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
}

schedule_reset_config() {
    echo
    read -p "Reset all backup configuration to defaults? [y/N]: " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        cat > "$BACKUP_CONFIG_FILE" << 'EOF'
{
  "schedule": "0 2 * * *",
  "compression": {
    "enabled": true,
    "level": 6
  },
  "retention": {
    "days": 7,
    "min_backups": 3
  },
  "telegram": {
    "enabled": false,
    "bot_token": null,
    "chat_id": null,
    "thread_id": null,
    "split_large_files": true,
    "max_file_size": 49,
    "api_server": "https://api.telegram.org",
    "use_custom_api": false
  }
}
EOF
        echo -e "\033[1;32m✅ Configuration reset to defaults\033[0m"
    else
        echo -e "\033[38;5;250mReset cancelled\033[0m"
    fi
    
    sleep 2
}

# Справка
schedule_help() {
    clear
    echo -e "\033[1;37m📚 Справка планировщика бэкапов\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
    echo
    echo -e "\033[1;37mCommands:\033[0m"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "setup" "🔧 Настроить параметры бэкапа"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "enable" "✅ Включить планировщик"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "disable" "❌ Отключить планировщик"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "status" "📊 Показать статус"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "test" "🧪 Тест создания бэкапа"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "test-telegram" "📱 Тест доставки в Telegram"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "run" "▶️  Запустить бэкап сейчас"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "logs" "📋 Просмотр логов"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "cleanup" "🧹 Очистить старые бэкапы"
    echo
    echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
}

generate_random_string() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex $((${1}/2))
    else
        cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1} | head -n 1
    fi
}

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
    
    # Проверяем на конфликт с известными сервисами
    case "$port" in
        22|80|443|53|25|110|143|993|995)
            colorized_echo yellow "Предупреждение: Порт $port обычно используется системными сервисами"
            ;;
    esac
    
    return 0
}

get_occupied_ports() {
    local ports=""
    
    if command -v ss &>/dev/null; then
        ports=$(ss -tuln 2>/dev/null | awk 'NR>1 {print $5}' | grep -Eo '[0-9]+$' | sort -n | uniq)
    elif command -v netstat &>/dev/null; then
        ports=$(netstat -tuln 2>/dev/null | awk 'NR>2 {print $4}' | grep -Eo '[0-9]+$' | sort -n | uniq)
    else
        colorized_echo yellow "Установка сетевых утилит для проверки портов..."
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

sanitize_domain() {
    # Remove leading/trailing whitespace, trailing slashes, and protocol
    echo "$1" | sed -e 's|^https\?://||' -e 's|/$||' | xargs
}

validate_domain() {
    local domain="$1"
    # Check if domain contains slashes or spaces after sanitization
    if [[ "$domain" == */* ]] || [[ "$domain" == *\ * ]]; then
        return 1
    fi
    return 0
}

validate_prefix() {
    local prefix="$1"
    # Check if prefix contains only alphanumeric characters and hyphens
    if [[ ! "$prefix" =~ ^[a-zA-Z0-9-]+$ ]]; then
        return 1
    fi
    return 0
}

install_remnawave() {
    mkdir -p "$APP_DIR"

    # Generate random JWT secrets using openssl if available
    JWT_AUTH_SECRET=$(openssl rand -hex 128)
    JWT_API_TOKENS_SECRET=$(openssl rand -hex 128)

    # Generate random metrics credentials
    METRICS_USER=$(generate_random_string 12)
    METRICS_PASS=$(generate_random_string 32)

    # Check for occupied ports
    get_occupied_ports

    # Default ports
    DEFAULT_APP_PORT=3000
    DEFAULT_METRICS_PORT=3001
    DEFAULT_SUB_PAGE_PORT=3010
    DEFAULT_DB_PORT=6767

    # Check if default ports are occupied and ask for alternatives if needed
    APP_PORT=$DEFAULT_APP_PORT
    if is_port_occupied "$APP_PORT"; then
        colorized_echo yellow "Порт по умолчанию APP_PORT $APP_PORT уже занят."
        while true; do
            read -p "Enter an alternative APP_PORT: " -r APP_PORT
            if [[ "$APP_PORT" -ge 1 && "$APP_PORT" -le 65535 ]]; then
                if is_port_occupied "$APP_PORT"; then
                    colorized_echo red "Порт $APP_PORT уже занят. Введите другой порт."
                else
                    break
                fi
            else
                colorized_echo red "Недопустимый порт. Введите значение от 1 до 65535."
            fi
        done
    fi

    METRICS_PORT=$DEFAULT_METRICS_PORT
    if is_port_occupied "$METRICS_PORT"; then
        colorized_echo yellow "Порт по умолчанию METRICS_PORT $METRICS_PORT уже занят."
        while true; do
            read -p "Enter an alternative METRICS_PORT: " -r METRICS_PORT
            if [[ "$METRICS_PORT" -ge 1 && "$METRICS_PORT" -le 65535 ]]; then
                if is_port_occupied "$METRICS_PORT"; then
                    colorized_echo red "Порт $METRICS_PORT уже занят. Введите другой порт."
                else
                    break
                fi
            else
                colorized_echo red "Недопустимый порт. Введите значение от 1 до 65535."
            fi
        done
    fi

    SUB_PAGE_PORT=$DEFAULT_SUB_PAGE_PORT
    if is_port_occupied "$SUB_PAGE_PORT"; then
        colorized_echo yellow "Порт страницы подписки по умолчанию $SUB_PAGE_PORT уже занят."
        while true; do
            read -p "Enter an alternative subscription page port: " -r SUB_PAGE_PORT
            if [[ "$SUB_PAGE_PORT" -ge 1 && "$SUB_PAGE_PORT" -le 65535 ]]; then
                if is_port_occupied "$SUB_PAGE_PORT"; then
                    colorized_echo red "Порт $SUB_PAGE_PORT уже занят. Введите другой порт."
                else
                    break
                fi
            else
                colorized_echo red "Недопустимый порт. Введите значение от 1 до 65535."
            fi
        done
    fi

    DB_PORT=$DEFAULT_DB_PORT
    if is_port_occupied "$DB_PORT"; then
        colorized_echo yellow "Порт БД по умолчанию DB_PORT $DB_PORT уже занят."
        while true; do
            read -p "Enter an alternative DB_PORT: " -r DB_PORT
            if [[ "$DB_PORT" -ge 1 && "$DB_PORT" -le 65535 ]]; then
                if is_port_occupied "$DB_PORT"; then
                    colorized_echo red "Порт $DB_PORT уже занят. Введите другой порт."
                else
                    break
                fi
            else
                colorized_echo red "Недопустимый порт. Введите значение от 1 до 65535."
            fi
        done
    fi

    # Ask for domain names
    while true; do
        read -p "Введите домен панели (например, panel.example.com или * для любого домена): " -r FRONT_END_DOMAIN
        FRONT_END_DOMAIN=$(sanitize_domain "$FRONT_END_DOMAIN")
        if [[ "$FRONT_END_DOMAIN" == http* ]]; then
            colorized_echo red "Введите только домен без http:// или https://"
        elif [[ -z "$FRONT_END_DOMAIN" ]]; then
            colorized_echo red "Домен не может быть пустым"
        elif ! validate_domain "$FRONT_END_DOMAIN" && [[ "$FRONT_END_DOMAIN" != "*" ]]; then
            colorized_echo red "Неверный формат домена. Домен не должен содержать слешей или пробелов."
        else
            break
        fi
    done

    # Ask for subscription page domain and prefix
    while true; do
        read -p "Введите домен страницы подписки (например, sub-link.example.com): " -r SUB_DOMAIN
        SUB_DOMAIN=$(sanitize_domain "$SUB_DOMAIN")
        if [[ "$SUB_DOMAIN" == http* ]]; then
            colorized_echo red "Введите только домен без http:// или https://"
        elif [[ -z "$SUB_DOMAIN" ]]; then
            colorized_echo red "Домен не может быть пустым"
        elif [[ "$SUB_DOMAIN" == */* ]]; then
            colorized_echo red "Неверный формат домена. Домен не должен содержать слешей."
        elif ! validate_domain "$SUB_DOMAIN"; then
            colorized_echo red "Неверный формат домена. Домен не должен содержать слешей или пробелов."
        else
            break
        fi
    done

    while true; do
        read -p "Введите префикс страницы подписки (по умолчанию: sub): " -r CUSTOM_SUB_PREFIX
        if [[ -z "$CUSTOM_SUB_PREFIX" ]]; then
            CUSTOM_SUB_PREFIX="sub"
            break
        elif ! validate_prefix "$CUSTOM_SUB_PREFIX"; then
            colorized_echo red "Неверный формат префикса. Разрешены только буквы, цифры и дефисы."
        else
            break
        fi
    done

    # Construct SUB_PUBLIC_DOMAIN with the prefix
    SUB_PUBLIC_DOMAIN="${SUB_DOMAIN}/${CUSTOM_SUB_PREFIX}"

    # Ask for META_TITLE and META_DESCRIPTION
    read -p "Введите META_TITLE для страницы подписки (по умолчанию: 'Remnawave VPN - Ваша страница подписки'): " -r META_TITLE
    if [[ -z "$META_TITLE" ]]; then
        META_TITLE="Remnawave VPN - Ваша страница подписки"
    fi

    read -p "Введите META_DESCRIPTION для страницы подписки (по умолчанию: 'Remnawave VPN - Лучший VPN-сервис'): " -r META_DESCRIPTION
    if [[ -z "$META_DESCRIPTION" ]]; then
        META_DESCRIPTION="Remnawave VPN - Лучший VPN-сервис"
    fi

    # Ask about Telegram integration
    read -p "Включить уведомления Telegram? (y/n): " -r enable_telegram
    IS_TELEGRAM_NOTIFICATIONS_ENABLED=false
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_NOTIFY_USERS_CHAT_ID=""
    TELEGRAM_NOTIFY_NODES_CHAT_ID=""
    TELEGRAM_NOTIFY_NODES_THREAD_ID=""
    TELEGRAM_NOTIFY_USERS_THREAD_ID=""
    TELEGRAM_NOTIFY_CRM_CHAT_ID=""
    TELEGRAM_NOTIFY_CRM_THREAD_ID=""

    if [[ "$enable_telegram" =~ ^[Yy]$ ]]; then
        IS_TELEGRAM_NOTIFICATIONS_ENABLED=true
        read -p "Введите Telegram Bot Token: " -r TELEGRAM_BOT_TOKEN
        read -p "Введите Chat ID для уведомлений пользователей: " -r TELEGRAM_NOTIFY_USERS_CHAT_ID
        read -p "Введите Chat ID для уведомлений нод (по умолчанию: как у пользователей): " -r TELEGRAM_NOTIFY_NODES_CHAT_ID
        if [[ -z "$TELEGRAM_NOTIFY_NODES_CHAT_ID" ]]; then
            TELEGRAM_NOTIFY_NODES_CHAT_ID="$TELEGRAM_NOTIFY_USERS_CHAT_ID"
        fi
        read -p "Введите Thread ID для уведомлений пользователей (опционально): " -r TELEGRAM_NOTIFY_USERS_THREAD_ID
        read -p "Введите Thread ID для уведомлений нод (опционально): " -r TELEGRAM_NOTIFY_NODES_THREAD_ID
        if [[ -z "$TELEGRAM_NOTIFY_NODES_THREAD_ID" ]]; then
            TELEGRAM_NOTIFY_NODES_THREAD_ID="$TELEGRAM_NOTIFY_USERS_THREAD_ID"
        fi
        
        # CRM Notification settings
        read -p "Введите Chat ID для уведомлений CRM (по умолчанию: как у нод): " -r TELEGRAM_NOTIFY_CRM_CHAT_ID
        if [[ -z "$TELEGRAM_NOTIFY_CRM_CHAT_ID" ]]; then
            TELEGRAM_NOTIFY_CRM_CHAT_ID="$TELEGRAM_NOTIFY_NODES_CHAT_ID"
        fi
        read -p "Введите Thread ID для уведомлений CRM (по умолчанию: как у нод): " -r TELEGRAM_NOTIFY_CRM_THREAD_ID
        if [[ -z "$TELEGRAM_NOTIFY_CRM_THREAD_ID" ]]; then
            TELEGRAM_NOTIFY_CRM_THREAD_ID="$TELEGRAM_NOTIFY_NODES_THREAD_ID"
        fi
    fi

    # Ask about Telegram OAuth authorization
    read -p "Включить Telegram OAuth вход для админ-панели? (y/n): " -r enable_telegram_oauth
    TELEGRAM_OAUTH_ENABLED=false
    TELEGRAM_OAUTH_ADMIN_IDS=""

    if [[ "$enable_telegram_oauth" =~ ^[Yy]$ ]]; then
        TELEGRAM_OAUTH_ENABLED=true
        while true; do
            read -p "Введите Telegram Admin ID (через запятую, только цифры, напр. 123456789,987654321): " -r input_ids
            input_ids=$(echo "$input_ids" | tr -d ' ')
            if [[ "$input_ids" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
                TELEGRAM_OAUTH_ADMIN_IDS="[$input_ids]"
                break
            else
                colorized_echo red "Неверный формат! Введите только числовые ID через запятую (без пробелов)."
            fi
        done

        if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
            colorized_echo yellow "Вы еще не указали Telegram Bot Token. Введите токен, чтобы OAuth работал (оставьте пустым, чтобы пропустить): " -r TELEGRAM_BOT_TOKEN
        fi

        if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
            colorized_echo red "Для Telegram OAuth требуется токен бота. OAuth будет отключен."
            TELEGRAM_OAUTH_ENABLED=false
            TELEGRAM_OAUTH_ADMIN_IDS=""
        fi
    fi

    # Determine image tag based on --dev flag
    BACKEND_IMAGE_TAG="latest"
    if [ "$USE_DEV_BRANCH" == "true" ]; then
        BACKEND_IMAGE_TAG="dev"
    fi

    colorized_echo blue "Генерация файла .env"
    cat > "$ENV_FILE" <<EOL
### APP ###
APP_PORT=$APP_PORT
METRICS_PORT=$METRICS_PORT

### REDIS ###
REDIS_HOST=remnawave-redis
REDIS_PORT=6379

### API ###
# Possible values: max (start instances on all cores), number (start instances on number of cores), -1 (start instances on all cores - 1)
# !!! Do not set this value more that physical cores count in your machine !!!
API_INSTANCES=1

### DATABASE ###
# FORMAT: postgresql://{user}:{password}@{host}:{port}/{database}
DATABASE_URL="postgresql://postgres:postgres@remnawave-db:5432/postgres"

### JWT ###
### CHANGE DEFAULT VALUES ###
JWT_AUTH_SECRET=$JWT_AUTH_SECRET
JWT_API_TOKENS_SECRET=$JWT_API_TOKENS_SECRET


SHORT_UUID_LENGTH=25

### TELEGRAM ###
IS_TELEGRAM_NOTIFICATIONS_ENABLED=$IS_TELEGRAM_NOTIFICATIONS_ENABLED
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_NOTIFY_USERS_CHAT_ID=$TELEGRAM_NOTIFY_USERS_CHAT_ID
TELEGRAM_NOTIFY_NODES_CHAT_ID=$TELEGRAM_NOTIFY_NODES_CHAT_ID
TELEGRAM_NOTIFY_CRM_CHAT_ID=$TELEGRAM_NOTIFY_CRM_CHAT_ID
TELEGRAM_NOTIFY_NODES_THREAD_ID=$TELEGRAM_NOTIFY_NODES_THREAD_ID
TELEGRAM_NOTIFY_USERS_THREAD_ID=$TELEGRAM_NOTIFY_USERS_THREAD_ID
TELEGRAM_NOTIFY_CRM_THREAD_ID=$TELEGRAM_NOTIFY_CRM_THREAD_ID


BANDWIDTH_USAGE_NOTIFICATIONS_ENABLED=true
BANDWIDTH_USAGE_NOTIFICATIONS_THRESHOLD=[80,95]

### TELEGRAM OAUTH ###
TELEGRAM_OAUTH_ENABLED=$TELEGRAM_OAUTH_ENABLED
TELEGRAM_OAUTH_ADMIN_IDS=$TELEGRAM_OAUTH_ADMIN_IDS

### FRONT_END ###
# Domain for panel access. Can be set to * to accept any domain
FRONT_END_DOMAIN=$FRONT_END_DOMAIN

### SUBSCRIPTION PUBLIC DOMAIN ###
### RAW DOMAIN, WITHOUT HTTP/HTTPS, DO NOT PLACE / to end of domain ###
SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN

### SWAGGER ###
SWAGGER_PATH=/docs
SCALAR_PATH=/scalar
IS_DOCS_ENABLED=false

### PROMETHEUS ###
### Metrics are available at /api/metrics
METRICS_USER=$METRICS_USER
METRICS_PASS=$METRICS_PASS

### WEBHOOK ###
WEBHOOK_ENABLED=false
### Only https:// is allowed
#WEBHOOK_URL=https://webhook.site/1234567890
### This secret is used to sign the webhook payload, must be exact 64 characters. Only a-z, 0-9, A-Z are allowed.
#WEBHOOK_SECRET_HEADER=vsmu67Kmg6R8FjIOF1WUY8LWBHie4scdEqrfsKmyf4IAf8dY3nFS0wwYHkhh6ZvQ

### CLOUDFLARE ###
# USED ONLY FOR docker-compose-prod-with-cf.yml
# NOT USED BY THE APP ITSELF
#CLOUDFLARE_TOKEN=ey...

### Database ###
### For Postgres Docker container ###
# NOT USED BY THE APP ITSELF
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres
#JWT_SECRET_KEY=1d9ca50cefda20fe710bca86ca829c919334055e07623d090987680391524b8e
HWID_DEVICE_LIMIT_ENABLED=false
HWID_FALLBACK_DEVICE_LIMIT=10
HWID_MAX_DEVICES_ANNOUNCE="You have reached the maximum number of devices for your subscription."
EOL
    colorized_echo green "Файл окружения сохранен в $ENV_FILE"

SUB_ENV_FILE="$APP_DIR/.env.subscription"

colorized_echo blue "Генерация .env.subscription для страницы подписки"
cat > "$SUB_ENV_FILE" <<EOL
### Remnawave Panel URL, can be http://remnawave:3000 or https://panel.example.com
REMNAWAVE_PANEL_URL=http://${APP_NAME}:${APP_PORT}

APP_PORT=${SUB_PAGE_PORT}

# Serve at custom root path, for example, this value can be: CUSTOM_SUB_PREFIX=sub
# Do not place / at the start/end
CUSTOM_SUB_PREFIX=${CUSTOM_SUB_PREFIX}

# Support Marzban links
#MARZBAN_LEGACY_LINK_ENABLED=false
#MARZBAN_LEGACY_SECRET_KEY=
#REMNAWAVE_API_TOKEN=

### META FOR SUBSCRIPTION PAGE ###
META_TITLE="$META_TITLE"
META_DESCRIPTION="$META_DESCRIPTION"

# If you use "Caddy with security" addon, you can place here X-Api-Key, which will be applied to requests to Remnawave Panel.
#CADDY_AUTH_API_TOKEN=

EOL
colorized_echo green "Файл окружения подписки сохранен в $SUB_ENV_FILE"

    # Create app-config.json for subscription page with app and instruction links
colorized_echo blue "Генерация статического файла app-config.json"
cat > "$APP_CONFIG_FILE" <<'EOL'

{
  "config": {
    "additionalLocales": [
      "ru"
    ],
    "branding": {
      "name": "VsemVPN подписка",
      "logoUrl": "https://remna.st/img/logo.svg",
      "supportUrl": "https://t.me/"
    }
  },
  "platforms": {
    "android": [
      {
        "id": "happ",
        "name": "Happ",
        "isFeatured": true,
        "urlScheme": "happ://add/",
        "installationStep": {
          "buttons": [
            {
              "buttonLink": "https://play.google.com/store/apps/details?id=com.happproxy",
              "buttonText": {
                "en": "Open in Google Play",
                "ru": "Открыть в Google Play"
              }
            },
            {
              "buttonLink": "https://github.com/Happ-proxy/happ-android/releases/latest/download/Happ.apk",
              "buttonText": {
                "en": "Download APK",
                "ru": "Скачать APK"
              }
            }
          ],
          "description": {
            "en": "Open the page in Google Play and install the app. Or install the app directly from the APK file if Google Play is not working.",
            "ru": "Откройте страницу в Google Play и установите приложение. Или установите приложение из APK файла напрямую, если Google Play не работает."
          }
        },
        "addSubscriptionStep": {
          "description": {
            "en": "Click the button below to add subscription",
            "ru": "Нажмите кнопку ниже, чтобы добавить подписку"
          }
        },
        "connectAndUseStep": {
          "description": {
            "en": "Open the app and connect to the server",
            "ru": "Откройте приложение и подключитесь к серверу"
          }
        }
      },
      {
        "id": "clash-meta",
        "name": "Clash Meta",
        "isFeatured": false,
        "urlScheme": "clash://install-config?url=",
        "installationStep": {
          "buttons": [
            {
              "buttonLink": "https://github.com/MetaCubeX/ClashMetaForAndroid/releases/download/v2.11.7/cmfa-2.11.7-meta-universal-release.apk",
              "buttonText": {
                "en": "Download APK",
                "ru": "Скачать APK"
              }
            },
            {
              "buttonLink": "https://f-droid.org/packages/com.github.metacubex.clash.meta/",
              "buttonText": {
                "en": "Open in F-Droid",
                "ru": "Открыть в F-Droid"
              }
            }
          ],
          "description": {
            "en": "Download and install Clash Meta APK",
            "ru": "Скачайте и установите Clash Meta APK"
          }
        },
        "addSubscriptionStep": {
          "description": {
            "en": "Tap the button to import configuration",
            "ru": "Нажмите кнопку, чтобы импортировать конфигурацию"
          }
        },
        "connectAndUseStep": {
          "description": {
            "en": "Open Clash Meta and tap on Connect",
            "ru": "Откройте Clash Meta и нажмите Подключиться"
          }
        }
      },
      {
            "id": "v2raytun",
            "name": "V2RayTun",
            "isFeatured": false,
            "urlScheme": "v2raytun://import/",
            "installationStep": {
                "buttons": [
                    {
                        "buttonLink": "https://play.google.com/store/apps/details?id=com.v2raytun.android",
                        "buttonText": {
                            "en": "Open in Google Play",
                            "ru": "Открыть в Google Play"
                        }
                    },
                    {
                        "buttonLink": "https://github.com/DigneZzZ/v2raytun/releases/latest/download/v2RayTun_universal.apk",
                        "buttonText": {
                            "en": "Download APK",
                            "ru": "Скачать APK"
                        }
                    }
                ],
                "description": {
                    "en": "Open the page in Google Play and install the app.",
                    "ru": "Откройте страницу в Google Play и установите приложение."
                }
            },
            "addSubscriptionStep": {
                "description": {
                    "en": "Click the button below to add subscription",
                    "ru": "Нажмите кнопку ниже, чтобы добавить подписку"
                }
            },
            "connectAndUseStep": {
                "description": {
                    "en": "Select a server and press the connect button.",
                    "fa": "یک سرور را انتخاب کنید و دکمه اتصال را فشار دهید.",
                    "ru": "Выберите сервер и нажмите кнопку подключения."
                }
            }
        }
    ],
    "ios": [
      {
        "id": "happ",
        "name": "Happ",
        "isFeatured": true,
        "urlScheme": "happ://add/",
        "installationStep": {
          "buttons": [
            {
              "buttonLink": "https://apps.apple.com/us/app/happ-proxy-utility/id6504287215",
              "buttonText": {
                "en": "Open in App Store [EU]",
                "ru": "Открыть в App Store [EU]"
              }
            },
            {
              "buttonLink": "https://apps.apple.com/ru/app/happ-proxy-utility-plus/id6746188973",
              "buttonText": {
                "en": "Open in App Store [RU]",
                "ru": "Открыть в App Store [RU]"
              }
            }
          ],
          "description": {
            "en": "Open the page in App Store and install the app. Launch it, in the VPN configuration permission window click Allow and enter your passcode.",
            "ru": "Откройте страницу в App Store и установите приложение. Запустите его, в окне разрешения VPN-конфигурации нажмите Allow и введите свой пароль."
          }
        },
        "addSubscriptionStep": {
          "description": {
            "en": "Click the button below — the app will open and the subscription will be added automatically",
            "ru": "Нажмите кнопку ниже — приложение откроется, и подписка добавится автоматически."
          }
        },
        "connectAndUseStep": {
          "description": {
            "en": "In the main section, click the large power button in the center to connect to VPN. Don't forget to select a server from the server list. If needed, choose another server from the server list.",
            "ru": "В главном разделе нажмите большую кнопку включения в центре для подключения к VPN. Не забудьте выбрать сервер в списке серверов. При необходимости выберите другой сервер из списка серверов."
          }
        }
      },
            {
        "id": "shadowrocket",
        "name": "Shadowrocket",
        "isFeatured": false,
        "urlScheme": "sub://",
        "isNeedBase64Encoding": true,
        "installationStep": {
          "buttons": [
            {
              "buttonLink": "https://apps.apple.com/ru/app/shadowrocket/id932747118",
              "buttonText": {
                "en": "Open in App Store",
                "ru": "Открыть в App Store"
              }
            }
          ],
          "description": {
            "en": "Open the page in App Store and install the app. Launch it, in the VPN configuration permission window click Allow and enter your passcode.",
            "ru": "Откройте страницу в App Store и установите приложение. Запустите его, в окне разрешения VPN-конфигурации нажмите Allow и введите свой пароль."
          }
        },
        "additionalBeforeAddSubscriptionStep": {
                "buttons": [
                    {
                        "buttonLink": "shadowrocket://config/add/https://dignezzz.github.io/ru_direct.conf",
                        "buttonText": {
                            "en": "Add routing",
                            "ru": "Добавить роутинг"
                        }
                    }
                ],
                "title": {
                    "en": "Add routing",
                    "ru": "Добавить роутинг"
                },
                "description": {
                    "en": "Click the button below to add the ru_direct.conf configuration file.",
                    "ru": "Нажмите кнопку ниже, чтобы добавить файл конфигурации ru_direct.conf."
                }
            },
        "addSubscriptionStep": {
          "description": {
            "en": "Click the button below — the app will open and the subscription will be added automatically",
            "ru": "Нажмите кнопку ниже — приложение откроется, и подписка добавится автоматически."
          }
        },
        "connectAndUseStep": {
          "description": {
            "en": "In the main section, click the large power button in the center to connect to VPN. Don't forget to select a server from the server list. If needed, choose another server from the server list.",
            "ru": "В главном разделе нажмите большую кнопку включения в центре для подключения к VPN. Не забудьте выбрать сервер в списке серверов. При необходимости выберите другой сервер из списка серверов."
          }
        }
      }
    ],
    "linux": [
      {
            "id": "clash-verge",
            "name": "Clash Verge",
            "isFeatured": false,
            "urlScheme": "clash://install-config?url=",
            "installationStep": {
                "buttons": [
                    {
                        "buttonLink": "https://github.com/coolcoala/clash-verge-rev-lite/releases",
                        "buttonText": {
                            "en": "Linux",
                            "ru": "Linux"
                        }
                    }
                ],
                "description": {
                    "en": "Choose the version for your device, click the button below and install the app.",
                    "ru": "Выберете подходящую версию для вашего устройства, нажмите на кнопку ниже и установите приложение."
                }
            },
            "addSubscriptionStep": {
                "description": {
                    "en": "Click the button below to add subscription",
                    "ru": "Нажмите кнопку ниже, чтобы добавить подписку"
                }
            },
            "connectAndUseStep": {
                "description": {
                    "en": "You can select a server in the Proxy section, and enable VPN in the Settings section. Set the TUN Mode switch to ON.",
                    "ru": "Выбрать сервер можно в разделе Прокси, включить VPN можно в разделе Настройки. Установите переключатель TUN Mode в положение ВКЛ."
                }
            }
        }
    ],
    "macos": [
      {
            "id": "koala-clash",
            "name": "Koala Clash",
            "isFeatured": true,
            "urlScheme": "clash://install-config?url=",
            "installationStep": {
                "buttons": [
                    {
                        "buttonLink": "https://github.com/coolcoala/clash-verge-rev-lite/releases/latest/download/Koala.Clash_x64.dmg",
                        "buttonText": {
                            "en": "macOS (Intel)",
                            "ru": "macOS (Intel)"
                        }
                    },
                    {
                        "buttonLink": "https://github.com/coolcoala/clash-verge-rev-lite/releases/latest/download/Koala.Clash_aarch64.dmg",
                        "buttonText": {
                            "en": "macOS (Apple Silicon)",
                            "ru": "macOS (Apple Silicon)"
                        }
                    }
                ],
                "description": {
                    "en": "Choose the version for your device, click the button below and install the app.",
                    "ru": "Выберете подходящую версию для вашего устройства, нажмите на кнопку ниже и установите приложение."
                }
            },
            "addSubscriptionStep": {
                "description": {
                    "en": "Click the button below to add subscription",
                    "ru": "Нажмите кнопку ниже, чтобы добавить подписку"
                }
            },
            "connectAndUseStep": {
                "description": {
                    "en": "You can select a server in the Proxy section, and enable VPN in the Settings section. Set the TUN Mode switch to ON.",
                    "ru": "Выбрать сервер можно в разделе Прокси, включить VPN можно в разделе Настройки. Установите переключатель в положение ВКЛ."
                }
            }
        },
        {
            "id": "V2RayTun",
            "name": "V2RayTun",
            "isFeatured": false,
            "urlScheme": "v2raytun://import/",
            "installationStep": {
                "buttons": [
                    {
                        "buttonLink": "https://apps.apple.com/ru/app/v2raytun/id6476628951",
                        "buttonText": {
                            "en": "macOS",
                            "fa": "مک",
                            "ru": "macOS"
                        }
                    }
                ],
                "description": {
                    "en": "Open the page in App Store and install the app. Launch it, in the VPN configuration permission window click Allow and enter your passcode.",
                    "ru": "Откройте страницу в App Store и установите приложение. Запустите его, в окне разрешения VPN-конфигурации нажмите Allow и введите свой пароль."
                }
            },
            "addSubscriptionStep": {
                "description": {
                    "en": "Click the button below — the app will open and the subscription will be added automatically",
                    "ru": "Нажмите кнопку ниже — приложение откроется, и подписка добавится автоматически."
                }
            },
            "connectAndUseStep": {
                "description": {
                    "en": "Select a server and press the connect button.",
                    "ru": "Выберите сервер и нажмите кнопку подключения."
                }
            },
            "additionalAfterAddSubscriptionStep": {
                "buttons": [],
                "title": {
                    "en": "Managed services",
                    "ru": "Настройка сервисов роутинга"
                },
                "description": {
                    "en": "Afer install go to the Services tab and set which of the services DONT NEED VPN",
                    "ru": "После добавления подписки перейдите в раздел Сервисы и выделите там то, чему НЕ ТРЕБУЕТСЯ VPN"
                }
            }
        }
    ],
    "windows": [
      {
            "id": "clash-verge",
            "name": "Clash Verge",
            "isFeatured": false,
            "urlScheme": "clash://install-config?url=",
            "installationStep": {
                "buttons": [
                    {
                        "buttonLink": "https://github.com/coolcoala/clash-verge-rev-lite/releases/latest/download/Koala.Clash_x64-setup.exe",
                        "buttonText": {
                            "en": "Windows",
                            "ru": "Windows"
                        }
                    }
                ],
                "description": {
                    "en": "Choose the version for your device, click the button below and install the app.",
                    "ru": "Выберете подходящую версию для вашего устройства, нажмите на кнопку ниже и установите приложение."
                }
            },
            "addSubscriptionStep": {
                "description": {
                    "en": "Click the button below to add subscription",
                    "ru": "Нажмите кнопку ниже, чтобы добавить подписку"
                }
            },
            "connectAndUseStep": {
                "description": {
                    "en": "You can select a server in the Proxy section, and enable VPN in the Settings section. Set the switch to ON.",
                    "ru": "Выбрать сервер можно в разделе Прокси, включить VPN можно в разделе Настройки. Установите переключатель TUN Mode в положение ВКЛ."
                }
            }
        }
      
    ],
    "androidTV": [],
    "appleTV": []
  }
}


EOL
colorized_echo green "Статический файл инструкций сохранен в $APP_CONFIG_FILE"


    colorized_echo blue "Генерация файла docker-compose.yml"
    cat > "$COMPOSE_FILE" <<EOL
services:
    remnawave-db:
        image: postgres:17
        container_name: '${APP_NAME}-db'
        hostname: ${APP_NAME}-db
        restart: always
        env_file:
            - .env
        environment:
            - POSTGRES_USER=\${POSTGRES_USER}
            - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
            - POSTGRES_DB=\${POSTGRES_DB}
            - TZ=UTC
        ports:
            - '127.0.0.1:6767:5432'
        volumes:
            - ${APP_NAME}-db-data:/var/lib/postgresql/data
        networks:
            - ${APP_NAME}-network
        healthcheck:
            test: ['CMD-SHELL', 'pg_isready -U \$\${POSTGRES_USER} -d \$\${POSTGRES_DB}']
            interval: 3s
            timeout: 10s
            retries: 3
        logging:
          driver: json-file
          options:
            max-size: "30m"
            max-file: "5"


    remnawave:
        image: remnawave/backend:${BACKEND_IMAGE_TAG}
        container_name: '${APP_NAME}'
        hostname: ${APP_NAME}
        restart: always
        ports:
            - '127.0.0.1:${APP_PORT}:${APP_PORT}'
            - '127.0.0.1:${METRICS_PORT}:${METRICS_PORT}'
        env_file:
            - .env
        networks:
            - ${APP_NAME}-network
        depends_on:
          remnawave-db:
            condition: service_healthy
          remnawave-redis:
            condition: service_healthy
        logging:
          driver: json-file
          options:
            max-size: "30m"
            max-file: "5"
            

    remnawave-subscription-page:
        image: remnawave/subscription-page:latest
        container_name: ${APP_NAME}-subscription-page
        hostname: ${APP_NAME}-subscription-page
        restart: always
        env_file:
            - .env.subscription
# Picked up from file .env.subscription
#        environment:
#            - REMNAWAVE_PLAIN_DOMAIN=http://${APP_NAME}:${APP_PORT}
#            - SUBSCRIPTION_PAGE_PORT=${SUB_PAGE_PORT}
#            - CUSTOM_SUB_PREFIX=${CUSTOM_SUB_PREFIX}
#            - META_TITLE=${META_TITLE}
#            - META_DESCRIPTION=${META_DESCRIPTION}
        ports:
            - '127.0.0.1:${SUB_PAGE_PORT}:${SUB_PAGE_PORT}'
        networks:
            - ${APP_NAME}-network
        volumes:
            - ${APP_DIR}/app-config.json:/opt/app/frontend/assets/app-config.json
        logging:
          driver: json-file
          options:
            max-size: "30m"
            max-file: "5"
            

    remnawave-redis:
        image: valkey/valkey:8.0.2-alpine
        container_name: ${APP_NAME}-redis
        hostname: ${APP_NAME}-redis
        restart: always
        networks:
            - ${APP_NAME}-network
        volumes:
            - ${APP_NAME}-redis-data:/data
        healthcheck:
            test: [ "CMD", "valkey-cli", "ping" ]
            interval: 3s
            timeout: 10s
            retries: 3
        logging:
            driver: json-file
            options:
                max-size: "30m"
                max-file: "5"
        

networks:
    ${APP_NAME}-network:
        name: ${APP_NAME}-network
        driver: bridge
        external: false

volumes:
    ${APP_NAME}-db-data:
        driver: local
        external: false
        name: ${APP_NAME}-db-data
    ${APP_NAME}-redis-data:
      driver: local
      external: false
      name: ${APP_NAME}-redis-data
EOL
    colorized_echo green "Файл Docker Compose сохранен в $COMPOSE_FILE"
}

uninstall_remnawave_script() {
    if [ -f "/usr/local/bin/$APP_NAME" ]; then
        colorized_echo yellow "Удаление скрипта remnawave"
        rm "/usr/local/bin/$APP_NAME"
    fi
}

uninstall_remnawave() {
    if [ -d "$APP_DIR" ]; then
        colorized_echo yellow "Удаление директории: $APP_DIR"
        rm -r "$APP_DIR"
    fi
}

uninstall_remnawave_docker_images() {
    images=$(docker images | grep remnawave | awk '{print $3}')
    if [ -n "$images" ]; then
        colorized_echo yellow "Удаление Docker-образов remnawave"
        for image in $images; do
            if docker rmi "$image" >/dev/null 2>&1; then
                colorized_echo yellow "Image $image removed"
            fi
        done
    fi
}

uninstall_remnawave_volumes() {
    volumes=$(docker volume ls | grep "${APP_NAME}" | awk '{print $2}')
    if [ -n "$volumes" ]; then
        colorized_echo yellow "Удаление Docker-томов remnawave"
        for volume in $volumes; do
            if docker volume rm "$volume" >/dev/null 2>&1; then
                colorized_echo yellow "Volume $volume removed"
            fi
        done
    fi
}

up_remnawave() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" up -d --remove-orphans
}

down_remnawave() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" down
}

show_remnawave_logs() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" logs
}

follow_remnawave_logs() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" logs -f
}

update_remnawave_script() {
    colorized_echo blue "Updating remnawave script"
    curl -sSL $SCRIPT_URL | install -m 755 /dev/stdin /usr/local/bin/$APP_NAME
    colorized_echo green "Скрипт remnawave успешно обновлен"
}

update_remnawave() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" pull
}

backup_command() {
    check_running_as_root
    detect_compose  
    
    if ! is_remnawave_installed; then
        colorized_echo red "Remnawave не установлен!"
        exit 1
    fi

    local compress=true         # По умолчанию сжимаем бэкап
    local include_configs=true  # По умолчанию полный бэкап
    local data_only=false       # Новый флаг для только БД
    
    # Парсинг аргументов
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --no-compress) 
                compress=false 
                ;;
            --data-only) 
                include_configs=false 
                data_only=true 
                ;;
            --include-configs) 
                include_configs=true 
                data_only=false
                ;;
            -h|--help) 
                echo -e "\033[1;37m💾 Remnawave Backup System\033[0m"
                echo
                echo -e "\033[1;37mИспользование:\033[0m"
                echo -e "  \033[38;5;15m$APP_NAME backup\033[0m [\033[38;5;244moptions\033[0m]"
                echo
                echo -e "\033[1;37mОпции:\033[0m"
                echo -e "  \033[38;5;244m--no-compress\033[0m       Создать несжатый бэкап (по умолчанию: сжатый)"
                echo -e "  \033[38;5;244m--data-only\033[0m         Бэкап только базы данных (без конфигов)"
                echo -e "  \033[38;5;244m--include-configs\033[0m   Включить файлы конфигурации (по умолчанию)"
                echo -e "  \033[38;5;244m--help, -h\033[0m          Показать эту справку"
                echo
                echo -e "\033[1;37mПримеры:\033[0m"
                echo -e "  \033[38;5;15m$APP_NAME backup\033[0m                           \033[38;5;8m# Полный бэкап (по умолчанию)\033[0m"
                echo -e "  \033[38;5;15m$APP_NAME backup --compress\033[0m                \033[38;5;8m# Сжатый полный бэкап\033[0m"
                echo -e "  \033[38;5;15m$APP_NAME backup --data-only\033[0m               \033[38;5;8m# Только база данных\033[0m"
                echo -e "  \033[38;5;15m$APP_NAME backup --data-only --compress\033[0m    \033[38;5;8m# Сжатая только база данных\033[0m"
                echo
                echo -e "\033[38;5;8mПо умолчанию: полный бэкап включает базу и конфигурационные файлы\033[0m"
                exit 0
                ;;
            *) 
                echo "Неизвестная опция: $1" >&2
                echo "Используйте '$APP_NAME backup --help' для справки по использованию."
                exit 1
                ;;
        esac
        shift
    done
    
    if [ ! -f "$ENV_FILE" ]; then
        colorized_echo red "Файл .env не найден!"
        exit 1
    fi

    # Проверяем, что база данных запущена
    if ! is_remnawave_up; then
        colorized_echo red "Сервисы Remnawave не запущены!"
        echo -e "\033[38;5;8m   Сначала выполните '\033[38;5;15msudo $APP_NAME up\033[38;5;8m'\033[0m"
        exit 1
    fi

    # Проверяем, что контейнер базы данных доступен
    local db_container="${APP_NAME}-db"
    if ! docker ps --format "{{.Names}}" | grep -q "^${db_container}$"; then
        colorized_echo red "Контейнер базы данных '$db_container' не найден или не запущен!"
        exit 1
    fi

    # Получаем данные подключения к БД
    local POSTGRES_USER=$(grep "^POSTGRES_USER=" "$ENV_FILE" | cut -d '=' -f2)
    local POSTGRES_PASSWORD=$(grep "^POSTGRES_PASSWORD=" "$ENV_FILE" | cut -d '=' -f2)
    local POSTGRES_DB=$(grep "^POSTGRES_DB=" "$ENV_FILE" | cut -d '=' -f2)

    # Устанавливаем значения по умолчанию
    POSTGRES_USER=${POSTGRES_USER:-postgres}
    POSTGRES_DB=${POSTGRES_DB:-postgres}

    if [ -z "$POSTGRES_PASSWORD" ]; then
        colorized_echo red "POSTGRES_PASSWORD не найден в файле .env!"
        exit 1
    fi

    # Создаем директорию для бэкапов
    local BACKUP_DIR="$APP_DIR/backups"
    mkdir -p "$BACKUP_DIR"

    # Генерируем имя файла
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name=""
    local backup_path=""
    
    if [ "$include_configs" = true ]; then
        # Полный бэкап с конфигами
        backup_name="remnawave_full_${timestamp}"
        local backup_dir="$BACKUP_DIR/$backup_name"
        mkdir -p "$backup_dir"
        
        echo -e "\033[1;37m💾 Создание полного системного бэкапа...\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        
        # Создаем дамп базы данных
        echo -e "\033[38;5;250m📝 Шаг 1:\033[0m Экспорт базы данных..."
        if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$db_container" \
            pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F p --verbose > "$backup_dir/database.sql" 2>/dev/null; then
            local db_size=$(du -sh "$backup_dir/database.sql" | cut -f1)
            echo -e "\033[1;32m✅ База данных успешно экспортирована ($db_size)\033[0m"
        else
            echo -e "\033[1;31m❌ Ошибка экспорта базы данных!\033[0m"
            rm -rf "$backup_dir"
            exit 1
        fi
        
        # Универсальное копирование конфигурационных файлов
        echo -e "\033[38;5;250m📝 Шаг 2:\033[0m Включение конфигурационных файлов..."
        
        local config_count=0
        
        # Копируем основные конфигурационные файлы прямо в корень бэкапа
        echo -e "\033[38;5;244m   Копирование основных конфигурационных файлов...\033[0m"
        for config_file in "$ENV_FILE" "$SUB_ENV_FILE" "$COMPOSE_FILE"; do
            if [ -f "$config_file" ]; then
                local filename=$(basename "$config_file")
                cp "$config_file" "$backup_dir/"
                config_count=$((config_count + 1))
                echo -e "\033[38;5;244m   ✓ $filename\033[0m"
            fi
        done
        
        # Копируем дополнительные конфигурационные файлы по расширениям
        echo -e "\033[38;5;244m   Поиск дополнительных конфигурационных файлов...\033[0m"
        local extensions=("json" "yml" "yaml" "toml" "ini" "conf" "config" "cfg")
        
        for ext in "${extensions[@]}"; do
            for config_file in "$APP_DIR"/*."$ext"; do
                if [ -f "$config_file" ]; then
                    local filename=$(basename "$config_file")
                    # Исключаем файлы, которые могут быть временными или логами
                    if [[ ! "$filename" =~ ^(temp|tmp|cache|log|debug) ]]; then
                        cp "$config_file" "$backup_dir/"
                        config_count=$((config_count + 1))
                        echo -e "\033[38;5;244m   ✓ $filename\033[0m"
                    fi
                fi
            done
        done
        
        # Копируем важные директории с конфигурациями
        echo -e "\033[38;5;244m   Проверка каталогов конфигурации...\033[0m"
        local config_dirs=("certs" "certificates" "ssl" "configs" "config" "custom" "themes" "plugins")
        
        for dir_name in "${config_dirs[@]}"; do
            local config_dir="$APP_DIR/$dir_name"
            if [ -d "$config_dir" ] && [ "$(ls -A "$config_dir" 2>/dev/null)" ]; then
                cp -r "$config_dir" "$backup_dir/"
                local dir_files=$(find "$config_dir" -type f | wc -l)
                config_count=$((config_count + dir_files))
                echo -e "\033[38;5;244m   ✓ $dir_name/ ($dir_files files)\033[0m"
            fi
        done
        
        # Создаем метаданные
        echo -e "\033[38;5;250m📝 Шаг 3:\033[0m Создание метаданных бэкапа..."
        
        # Получаем версию панели
        local panel_version=$(get_panel_version)
        
        cat > "$backup_dir/metadata.json" << EOF
{
    "backup_type": "full",
    "timestamp": "$timestamp",
    "app_name": "$APP_NAME",
    "script_version": "$SCRIPT_VERSION",
    "panel_version": "$panel_version",
    "database_included": true,
    "configs_included": true,
    "config_files_count": $config_count,
    "hostname": "$(hostname)",
    "backup_size": "calculated_after_compression"
}
EOF
        
        # Создаем информационный файл
        cat > "$backup_dir/backup_info.txt" << EOF
Remnawave Panel Backup Information
==================================
Backup Date: $(date)
Backup Type: Full System Backup
Script Version: $SCRIPT_VERSION
Panel Version: $panel_version
Hostname: $(hostname)

Included Components:
✓ PostgreSQL Database (complete dump)
✓ Environment Files (.env, .env.subscription)
✓ Docker Compose Configuration
✓ Additional Config Files ($config_count files)
✓ Configuration Directories
✓ SSL Certificates (if present)

Restoration:
=============

🚀 RECOMMENDED METHOD (Automatic):
----------------------------------
1. Transfer backup file to target server
2. Install management script (if not installed):
   • curl -Ls https://raw.githubusercontent.com/Spakieone/Remna/main/remnawave.sh -o remnawave.sh
   • sudo bash remnawave.sh @ install-script --name $APP_NAME
3. Use built-in restore function:
   • sudo $APP_NAME restore --file $(basename "$backup_path")

✅ This method includes:
   • Automatic panel installation (if needed)
   • Version compatibility checking
   • Safety backup creation
   • Database restoration with error handling
   • Configuration file copying
   • Service management

🛠️ MANUAL METHOD (Advanced users only):
---------------------------------------
Only use if automatic restore fails or for custom scenarios.

New Installation:
1. Download: curl -Ls https://raw.githubusercontent.com/Spakieone/Remna/main/remnawave.sh
2. Install script: sudo bash remnawave.sh @ install-script --name $APP_NAME
3. Создать директорию: sudo mkdir -p $APP_DIR
4. Extract: tar -xzf $(basename "$backup_path")
5. Copy all configs: sudo cp -r $(basename "$backup_path" .tar.gz)/* $APP_DIR/
6. Set permissions: sudo chown -R root:root $APP_DIR
7. Запустить сервисы: sudo $APP_NAME up -d
8. Wait for DB: sleep 15
9. Clear DB: docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
10. Restore DB: cat $(basename "$backup_path" .tar.gz)/database.sql | docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB
11. Перезапуск: sudo $APP_NAME restart

Existing Installation:
1. Остановить: sudo $APP_NAME down
2. Safety backup: sudo $APP_NAME backup --data-only
3. Extract: tar -xzf $(basename "$backup_path")
4. Clear DB: docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
5. Restore DB: cat $(basename "$backup_path" .tar.gz)/database.sql | docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB
6. Запустить: sudo $APP_NAME up

⚠️  ВАЖНО: Целевая система должна иметь совместимую версию Remnawave Panel ($panel_version)

Сгенерировано Remnawave Management CLI
EOF
        
        echo -e "\033[1;32m✅ Configuration files included ($config_count items)\033[0m"
        
        # Компрессия если требуется
        if [ "$compress" = true ]; then
            echo -e "\033[38;5;250m📝 Step 4:\033[0m Compressing backup..."
            cd "$BACKUP_DIR" || exit 1
            if tar -czf "${backup_name}.tar.gz" "$backup_name" 2>/dev/null; then
                local compressed_size=$(du -sh "${backup_name}.tar.gz" | cut -f1)
                echo -e "\033[1;32m✅ Backup compressed successfully ($compressed_size)\033[0m"
                backup_path="$BACKUP_DIR/${backup_name}.tar.gz"
                
                # Удаляем некомпрессированную версию
                rm -rf "$backup_dir"
            else
                echo -e "\033[1;31m❌ Compression failed, keeping uncompressed backup\033[0m"
                backup_path="$backup_dir"
            fi
        else
            backup_path="$backup_dir"
        fi
        
    else
        # Простой бэкап только базы данных  
        echo -e "\033[1;37m💾 Creating database backup...\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        echo -e "\033[38;5;250mDatabase: $POSTGRES_DB\033[0m"
        echo -e "\033[38;5;250mContainer: $db_container\033[0m"
        
        # Создаем бэкап
        if [ "$compress" = true ]; then
            # Проверяем наличие gzip
            if ! command -v gzip >/dev/null 2>&1; then
                colorized_echo yellow "Warning: gzip not found, creating uncompressed backup instead"
                backup_name="remnawave_db_${timestamp}.sql"
                backup_path="$BACKUP_DIR/$backup_name"
                echo -e "\033[38;5;250mBackup file: $backup_name\033[0m"
                echo
                if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$db_container" \
                    pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F p --verbose > "$backup_path" 2>/dev/null; then
                    local backup_size=$(du -sh "$backup_path" | cut -f1)
                    echo -e "\033[1;32m✅ Database backup created successfully ($backup_size)!\033[0m"
                else
                    echo -e "\033[1;31m❌ Database backup failed!\033[0m"
                    rm -f "$backup_path"
                    exit 1
                fi
            else
                backup_name="remnawave_db_${timestamp}.sql.gz"
                backup_path="$BACKUP_DIR/$backup_name"
                echo -e "\033[38;5;250mBackup file: $backup_name\033[0m"
                echo
                if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$db_container" \
                    pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F p --verbose 2>/dev/null | \
                    gzip > "$backup_path"; then
                    local backup_size=$(du -sh "$backup_path" | cut -f1)
                    echo -e "\033[1;32m✅ Compressed database backup created successfully ($backup_size)!\033[0m"
                else
                    echo -e "\033[1;31m❌ Database backup failed!\033[0m"
                    rm -f "$backup_path"
                    exit 1
                fi
            fi
        else
            backup_name="remnawave_db_${timestamp}.sql"
            backup_path="$BACKUP_DIR/$backup_name"
            echo -e "\033[38;5;250mBackup file: $backup_name\033[0m"
            echo
            if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$db_container" \ 
                pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F p --verbose > "$backup_path" 2>/dev/null; then
                local backup_size=$(du -sh "$backup_path" | cut -f1)
                echo -e "\033[1;32m✅ Database backup created successfully ($backup_size)!\033[0m"
            else
                echo -e "\033[1;31m❌ Database backup failed!\033[0m"
                rm -f "$backup_path"
                exit 1
            fi
        fi
    fi

    # Показываем итоговую информацию
    echo
    echo -e "\033[1;37m📋 Backup Information:\033[0m"
    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Location:" "$backup_path"
    
    if [ -f "$backup_path" ]; then
        local file_size=$(du -sh "$backup_path" | cut -f1)
        printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Size:" "$file_size"
    elif [ -d "$backup_path" ]; then
        local dir_size=$(du -sh "$backup_path" | cut -f1)
        printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Size:" "$dir_size"
    fi
    
    # Показываем версию панели
    local current_panel_version=$(get_panel_version)
    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Panel:" "v$current_panel_version"
    
    if [ "$include_configs" = true ]; then
        if [ "$compress" = true ]; then
            printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Type:" "Full backup (database + configs, compressed)"
        else
            printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Type:" "Full backup (database + configs)"
        fi
    else
        if [ "$compress" = true ]; then
            printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Type:" "Database only (compressed)"
        else
            printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Type:" "Database only"
        fi
    fi
    
    if [ "$compress" = true ]; then
        printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Compression:" "gzip"
    fi
    echo
    
    # Показываем как восстановить
    echo -e "\033[1;37m🔄 To restore this backup:\033[0m"
    if [ "$include_configs" = true ]; then
        echo -e "\033[1;32m✓ Full system backup - includes database and all configuration files\033[0m"
        echo
        echo -e "\033[1;37m🚀 RECOMMENDED: Use built-in restore function\033[0m"
        echo -e "\033[38;5;244m1. Transfer backup to target server\033[0m"
        echo -e "\033[38;5;244m2. Install script: curl -Ls https://raw.githubusercontent.com/Spakieone/Remna/main/remnawave.sh -o remnawave.sh\033[0m"
        echo -e "\033[38;5;244m3. Install manager: sudo bash remnawave.sh @ install-script --name $APP_NAME\033[0m"
        echo -e "\033[38;5;244m4. Restore: sudo $APP_NAME restore --file \"$(basename "$backup_path")\"\033[0m"
        echo
        echo -e "\033[38;5;8m   ✅ Includes automatic version checking, safety backups, and error handling\033[0m"
        echo
        echo -e "\033[1;37m🛠️  MANUAL METHOD (if automatic fails):\033[0m"
        echo -e "\033[38;5;244mNew installation:\033[0m"
        echo -e "\033[38;5;244m1. Download: curl -Ls https://raw.githubusercontent.com/Spakieone/Remna/main/remnawave.sh\033[0m"
        echo -e "\033[38;5;244m2. Install script: sudo bash remnawave.sh @ install-script --name $APP_NAME\033[0m"
        echo -e "\033[38;5;244m3. Создать директорию: sudo mkdir -p $APP_DIR\033[0m"
        if [ "$compress" = true ]; then
            echo -e "\033[38;5;244m4. Extract: tar -xzf \"$(basename "$backup_path")\"\033[0m"
            echo -e "\033[38;5;244m5. Copy all configs: sudo cp -r $(basename "$backup_path" .tar.gz)/* $APP_DIR/\033[0m"
            echo -e "\033[38;5;244m6. Set permissions: sudo chown -R root:root $APP_DIR\033[0m"
            echo -e "\033[38;5;244m7. Запустить сервисы: sudo $APP_NAME up -d\033[0m"
            echo -e "\033[38;5;244m8. Wait for DB: sleep 15\033[0m"
            echo -e "\033[38;5;244m9. Clear DB: docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB -c \"DROP SCHEMA public CASCADE; CREATE SCHEMA public;\"\033[0m"
            echo -e "\033[38;5;244m10. Restore DB: cat $(basename "$backup_path" .tar.gz)/database.sql | docker exec -i -e PGPASSWORD=\"$POSTGRES_PASSWORD\" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB\033[0m"
            echo -e "\033[38;5;244m11. Перезапуск: sudo $APP_NAME restart\033[0m"
        else
            echo -e "\033[38;5;244m4. Copy all configs: sudo cp -r $(basename "$backup_path")/* $APP_DIR/\033[0m"
            echo -e "\033[38;5;244m5. Set permissions: sudo chown -R root:root $APP_DIR\033[0m"
            echo -e "\033[38;5;244m6. Запустить сервисы: sudo $APP_NAME up -d\033[0m"
            echo -e "\033[38;5;244m7. Wait for DB: sleep 15\033[0m"
            echo -e "\033[38;5;244m8. Clear DB: docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB -c \"DROP SCHEMA public CASCADE; CREATE SCHEMA public;\"\033[0m"
            echo -e "\033[38;5;244m9. Restore DB: cat $(basename "$backup_path")/database.sql | docker exec -i -e PGPASSWORD=\"$POSTGRES_PASSWORD\" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB\033[0m"
            echo -e "\033[38;5;244m10. Перезапуск: sudo $APP_NAME restart\033[0m"
        fi
    else
        echo -e "\033[1;33m⚠️  Database-only backup - configuration files not included\033[0m"
        echo -e "\033[38;5;244mRequires existing Remnawave installation with same version ($panel_version)\033[0m"
        echo
        echo -e "\033[1;37m🚀 RECOMMENDED: Use built-in restore function\033[0m"
        echo -e "\033[38;5;244m1. Transfer backup to target server\033[0m"
        echo -e "\033[38;5;244m2. Restore: sudo $APP_NAME restore --database-only --file \"$(basename "$backup_path")\"\033[0m"
        echo
        echo -e "\033[1;37m🛠️  MANUAL METHOD:\033[0m"
        if [ "$compress" = true ]; then
            echo -e "\033[38;5;244m1. Остановить: sudo $APP_NAME down\033[0m"
            echo -e "\033[38;5;244m2. Clear DB: docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB -c \"DROP SCHEMA public CASCADE; CREATE SCHEMA public;\"\033[0m"
            echo -e "\033[38;5;244m3. Restore: zcat \"$(basename "$backup_path")\" | docker exec -i -e PGPASSWORD=\"$POSTGRES_PASSWORD\" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB\033[0m"
            echo -e "\033[38;5;244m4. Запустить: sudo $APP_NAME up\033[0m"
        else
            echo -e "\033[38;5;244m1. Остановить: sudo $APP_NAME down\033[0m"
            echo -e "\033[38;5;244m2. Clear DB: docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB -c \"DROP SCHEMA public CASCADE; CREATE SCHEMA public;\"\033[0m"
            echo -e "\033[38;5;244m3. Restore: cat \"$(basename "$backup_path")\" | docker exec -i -e PGPASSWORD=\"$POSTGRES_PASSWORD\" ${APP_NAME}-db psql -U $POSTGRES_USER -d $POSTGRES_DB\033[0m"
            echo -e "\033[38;5;244m4. Запустить: sudo $APP_NAME up\033[0m"
        fi
    fi
    echo
    
    # Автоматическая очистка старых бэкапов (оставляем последние 10)
    local old_backups=$(ls -t "$BACKUP_DIR"/remnawave_*_*.{sql*,tar.gz} 2>/dev/null | tail -n +11)
    if [ -n "$old_backups" ]; then
        echo "$old_backups" | xargs rm -rf
        local removed_count=$(echo "$old_backups" | wc -l)
        echo -e "\033[38;5;8m🧹 Cleaned up $removed_count old backup(s) (keeping last 10)\033[0m"
    fi
}



monitor_command() {
    check_running_as_root
    
    if ! is_remnawave_installed; then
        echo -e "\033[1;31m❌ Remnawave не установлен!\033[0m"
        return 1
    fi
    
    if ! is_remnawave_up; then
        echo -e "\033[1;31m❌ Сервисы Remnawave не запущены!\033[0m"
        echo -e "\033[38;5;8m   Use 'sudo $APP_NAME up' to start services\033[0m"
        return 1
    fi
    
    # Однократный вывод статистики
    echo -e "\033[1;37m📊 Remnawave Performance Monitor - $(date '+%Y-%m-%d %H:%M:%S')\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
    echo
    
    # Показываем статистику контейнеров
    echo -e "\033[1;37m🐳 Container Statistics:\033[0m"
    local stats_available=false
    
    # Проверяем доступность docker stats
    if docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null | grep -q "${APP_NAME}"; then
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" | grep -E "(NAME|${APP_NAME})"
        stats_available=true
    else
        echo -e "\033[38;5;244m   Docker stats not available or no containers running\033[0m"
    fi
    
    echo
    
    # Показываем системные ресурсы
    echo -e "\033[1;37m💻 System Resources:\033[0m"
    
    # CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
    echo -e "   \033[38;5;15mCPU:\033[0m $cpu_usage% usage"
    
    # Memory
    local mem_info=$(free -h | grep "Mem:" 2>/dev/null)
    if [ -n "$mem_info" ]; then
        local mem_used=$(echo "$mem_info" | awk '{print $3}')
        local mem_total=$(echo "$mem_info" | awk '{print $2}')
        local mem_percent=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
        echo -e "   \033[38;5;15mMemory:\033[0m $mem_percent% usage ($mem_used used / $mem_total total)"
    else
        echo -e "   \033[38;5;15mMemory:\033[0m N/A"
    fi
    
    # Disk
    local disk_info=$(df -h "$APP_DIR" 2>/dev/null | tail -1)
    if [ -n "$disk_info" ]; then
        local disk_used=$(echo "$disk_info" | awk '{print $3}')
        local disk_total=$(echo "$disk_info" | awk '{print $2}')
        local disk_percent=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
        echo -e "   \033[38;5;15mDisk:\033[0m $disk_used used / $disk_total total ($disk_percent%)"
    else
        echo -e "   \033[38;5;15mDisk:\033[0m N/A"
    fi
    
    echo
    
    # Дополнительная информация о контейнерах
    if [ "$stats_available" = true ]; then
        echo -e "\033[1;37m📋 Container Details:\033[0m"
        detect_compose
        cd "$APP_DIR" 2>/dev/null || true
        
        local container_info=$($COMPOSE -f "$COMPOSE_FILE" ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)
        if [ -n "$container_info" ]; then
            echo "$container_info" | tail -n +2 | while IFS=$'\t' read -r service status ports; do
                local status_icon="❓"
                local status_color="38;5;244"
                
                if [[ "$status" =~ "Up" ]]; then
                    if [[ "$status" =~ "healthy" ]]; then
                        status_icon="✅"
                        status_color="1;32"
                    elif [[ "$status" =~ "unhealthy" ]]; then
                        status_icon="❌"
                        status_color="1;31"
                    else
                        status_icon="🟡"
                        status_color="1;33"
                    fi
                elif [[ "$status" =~ "Exit" ]]; then
                    status_icon="❌"
                    status_color="1;31"
                fi
                
                printf "   \033[38;5;15m%-20s\033[0m \033[${status_color}m${status_icon} %-25s\033[0m \033[38;5;244m%s\033[0m\n" "$service:" "$status" "$ports"
            done
        fi
    fi
    
    echo
    echo -e "\033[38;5;8m📊 Snapshot taken at $(date '+%H:%M:%S')\033[0m"
    echo -e "\033[38;5;8m💡 For continuous monitoring, use: docker stats\033[0m"

        if [[ "${BASH_SOURCE[1]}" =~ "main_menu" ]] || [[ "$0" =~ "$APP_NAME" ]] && [[ "$1" != "--no-pause" ]]; then
        echo
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
    fi
}

is_remnawave_installed() {
    if [ -d "$APP_DIR" ]; then
        return 0
    else
        return 1
    fi
}

is_remnawave_up() {
    detect_compose
    if [ -z "$($COMPOSE -f $COMPOSE_FILE ps -q -a 2>/dev/null)" ]; then
        return 1
    else
        return 0
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

warn_already_installed() {
    colorized_echo red "⚠️ Remnawave is already installed at: \e[1m$APP_DIR\e[0m"
    colorized_echo yellow "To install another instance, use the \e[1m--name <custom_name>\e[0m flag."
    colorized_echo cyan "Example: remnawave install --name mypanel"
}


install_command() {
    check_running_as_root
    if is_remnawave_installed; then
        warn_already_installed
        read -r -p "Do you want to override the previous installation? (y/n) "
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            colorized_echo red "Aborted installation"
            exit 1
        fi
    fi
    detect_os
    if ! command -v curl >/dev/null 2>&1; then
        install_package curl
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        install_package openssl
    fi
    if ! command -v docker >/dev/null 2>&1; then
        install_docker
    fi

    detect_compose
    install_remnawave_script
    install_remnawave
    up_remnawave

    follow_remnawave_logs

    colorized_echo green "==================================================="
    colorized_echo green "Панель Remnawave успешно установлена!"
    colorized_echo green "Panel URL (local access only): http://127.0.0.1:$APP_PORT"
    colorized_echo green "Subscription Page URL (local access only): http://127.0.0.1:$SUB_PAGE_PORT"
    colorized_echo green "==================================================="
    colorized_echo yellow "ВАЖНО: Эти URL доступны только с самого сервера."
    colorized_echo yellow "You must set up a reverse proxy to make them accessible from the internet."
    colorized_echo yellow "Configure your reverse proxy to point to:"
    colorized_echo yellow "Panel domain: $FRONT_END_DOMAIN -> 127.0.0.1:$APP_PORT"
    colorized_echo yellow "Subscription domain: $SUB_DOMAIN -> 127.0.0.1:$SUB_PAGE_PORT"
    colorized_echo green "==================================================="
}

uninstall_command() {
    check_running_as_root
    if ! is_remnawave_installed; then
        colorized_echo red "Remnawave не установлен!"
        exit 1
    fi

    read -p "Do you really want to uninstall Remnawave? (y/n) "
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        colorized_echo red "Aborted"
        exit 1
    fi

    detect_compose
    if is_remnawave_up; then
        down_remnawave
    fi
    uninstall_remnawave_script
    uninstall_remnawave
    uninstall_remnawave_docker_images

    read -p "Do you want to remove Remnawave data volumes too? This will DELETE ALL DATABASE DATA! (y/n) "
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        uninstall_remnawave_volumes
    fi

    colorized_echo green "Remnawave uninstalled successfully"
}

up_command() {
    help() {
        colorized_echo red "Использование: remnawave up [опции]"
        echo "ОПЦИИ:"
        echo "  -h, --help        показать эту справку"
        echo "  -n, --no-logs     не показывать логи после старта"
    }

    local no_logs=false
    
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-logs) no_logs=true ;;
            -h|--help) 
                echo -e "\033[1;37m▶️  up\033[0m - Start all Remnawave services"
                echo
                echo -e "\033[1;37mИспользование:\033[0m"
                echo -e "  \033[38;5;15m$APP_NAME\033[0m \033[38;5;250mup\033[0m [\033[38;5;244m--no-logs\033[0m]"
                echo
                echo -e "\033[1;37mOptions:\033[0m"
                echo -e "  \033[38;5;244m-n, --no-logs\033[0m   Start without following logs"
                echo
                exit 0
                ;;
            *) 
                echo "Ошибка: Неверная опция: $1" >&2
                echo "Используйте '$APP_NAME up --help' для справки по использованию."
                exit 1
                ;;
        esac
        shift
    done
    

    if ! is_remnawave_installed; then
        colorized_echo red "Remnawave не установлен!"
        exit 1
    fi

    detect_compose

    if is_remnawave_up; then
        colorized_echo red "Remnawave уже запущен"
        exit 1
    fi

    up_remnawave
    if [ "$no_logs" = false ]; then
        follow_remnawave_logs
    fi
}

down_command() {
    if ! is_remnawave_installed; then
        colorized_echo red "Remnawave не установлен!"
        exit 1
    fi

    detect_compose

    if ! is_remnawave_up; then
        colorized_echo red "Remnawave уже остановлен"
        exit 1
    fi

    down_remnawave
}

restart_command() {
    help() {
        colorized_echo red "Использование: remnawave restart [опции]"
        echo "ОПЦИИ:"
        echo "  -h, --help        показать эту справку"
        echo "  -n, --no-logs     не показывать логи после старта"
    }

    local no_logs=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-logs) no_logs=true ;;
            -h|--help) help; exit 0 ;;
            *) echo "Ошибка: Неверная опция: $1" >&2; help; exit 0 ;;
        esac
        shift
    done

    if ! is_remnawave_installed; then
        colorized_echo red "Remnawave не установлен!"
        exit 1
    fi

    detect_compose

    down_remnawave
    up_remnawave

    if [ "$no_logs" = false ]; then
        follow_remnawave_logs
    fi
}

health_check_command() {
    echo -e "\033[1;37m🏥 Remnawave System Health Check\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    echo
    
    local issues=0
    
    # Проверка установки
    if ! is_remnawave_installed; then
        echo -e "\033[1;31m❌ Панель не установлена\033[0m"
        return 1
    fi
    
    # Проверка Docker
    if ! command -v docker >/dev/null; then
        echo -e "\033[1;31m❌ Docker не установлен\033[0m"
        issues=$((issues + 1))
    else
        echo -e "\033[1;32m✅ Docker installed\033[0m"
        
        # Проверка статуса Docker daemon
        if ! docker info >/dev/null 2>&1; then
            echo -e "\033[1;31m❌ Демон Docker не запущен\033[0m"
            issues=$((issues + 1))
        else
            echo -e "\033[1;32m✅ Демон Docker запущен\033[0m"
        fi
    fi
    
    # Проверка Docker Compose
    detect_compose
    if [ -z "$COMPOSE" ]; then
        echo -e "\033[1;31m❌ Docker Compose not found\033[0m"
        issues=$((issues + 1))
    else
        echo -e "\033[1;32m✅ Docker Compose available ($COMPOSE)\033[0m"
    fi
    
    # Проверка конфигурационных файлов
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "\033[1;31m❌ Environment file missing: $ENV_FILE\033[0m"
        issues=$((issues + 1))
    else
        echo -e "\033[1;32m✅ Environment file exists\033[0m"
        
        # Проверка обязательных переменных
        local required_vars=("APP_PORT" "JWT_AUTH_SECRET" "JWT_API_TOKENS_SECRET" "POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB")
        for var in "${required_vars[@]}"; do
            if ! grep -q "^${var}=" "$ENV_FILE"; then
                echo -e "\033[1;31m❌ Missing required variable: $var\033[0m"
                issues=$((issues + 1))
            fi
        done
    fi
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "\033[1;31m❌ Docker Compose file missing: $COMPOSE_FILE\033[0m"
        issues=$((issues + 1))
    else
        echo -e "\033[1;32m✅ Docker Compose file exists\033[0m"
        
        # Проверка валидности compose файла
        if validate_compose_file "$COMPOSE_FILE"; then
            echo -e "\033[1;32m✅ Docker Compose file valid\033[0m"
        else
            echo -e "\033[1;31m❌ Docker Compose file invalid\033[0m"
            issues=$((issues + 1))
        fi
    fi
    
    # Проверка портов
    if [ -f "$ENV_FILE" ]; then
        echo -e "\033[1;37m🔌 Port Status Check:\033[0m"
        
        local app_port=$(grep "^APP_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        local metrics_port=$(grep "^METRICS_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        
        if [ -f "$SUB_ENV_FILE" ]; then
            local sub_port=$(grep "^APP_PORT=" "$SUB_ENV_FILE" | cut -d'=' -f2)
        fi
        
        # Проверяем каждый порт отдельно
        for port in $app_port $metrics_port $sub_port; do
            if [ -n "$port" ]; then
                local port_info=""
                local status_color="1;32"
                local status_icon="✅"
                
                # Получаем информацию о процессе, использующем порт
                if command -v ss >/dev/null 2>&1; then
                    port_info=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1)
                elif command -v netstat >/dev/null 2>&1; then
                    port_info=$(netstat -tlnp 2>/dev/null | grep ":$port " | head -1)
                fi
                
                if [ -n "$port_info" ]; then
                    # Извлекаем имя процесса
                    local process_name=""
                    if echo "$port_info" | grep -q "docker-proxy"; then
                        process_name="docker-proxy"
                    elif echo "$port_info" | grep -q "nginx"; then
                        process_name="nginx"
                    elif echo "$port_info" | grep -q "apache"; then
                        process_name="apache"
                    else
                        # Попытка извлечь имя процесса из вывода
                        process_name=$(echo "$port_info" | grep -o 'users:(([^)]*))' | sed 's/users:((\([^)]*\)).*/\1/' | cut -d',' -f1 | tr -d '"' | head -1)
                        if [ -z "$process_name" ]; then
                            process_name="unknown process"
                        fi
                    fi
                    
                    # Определяем, это наш порт или чужой
                    if echo "$process_name" | grep -q "docker"; then
                        status_color="1;32"
                        status_icon="✅"
                        printf "   \033[38;5;15mPort %s:\033[0m \033[${status_color}m${status_icon} Used by Remnawave (docker)\033[0m\n" "$port"
                    else
                        status_color="1;33"
                        status_icon="⚠️ "
                        printf "   \033[38;5;15mPort %s:\033[0m \033[${status_color}m${status_icon} Occupied by %s\033[0m\n" "$port" "$process_name"
                        issues=$((issues + 1))
                    fi
                else
                    printf "   \033[38;5;15mPort %s:\033[0m \033[1;32m✅ Available\033[0m\n" "$port"
                fi
            fi
        done
    fi
    
    # Проверка дискового пространства
    local available_space=$(df "$APP_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [ "$available_space" -lt 1048576 ]; then  # 1GB в KB
        echo -e "\033[1;33m⚠️  Low disk space: $(( available_space / 1024 ))MB available\033[0m"
        issues=$((issues + 1))
    else
        echo -e "\033[1;32m✅ Sufficient disk space: $(( available_space / 1024 ))MB available\033[0m"
    fi
    
    # Проверка RAM
    local available_ram=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_ram" -lt 256 ]; then
        echo -e "\033[1;33m⚠️  Low available RAM: ${available_ram}MB\033[0m"
    else
        echo -e "\033[1;32m✅ Sufficient RAM: ${available_ram}MB available\033[0m"
    fi
    
    # Проверка состояния сервисов (если установлены)
    if is_remnawave_up; then
        echo -e "\033[1;37m🐳 Services Status:\033[0m"
        detect_compose
        cd "$APP_DIR" 2>/dev/null || true
        
        # Получаем статус каждого сервиса
        local services_status=$($COMPOSE -f "$COMPOSE_FILE" ps --format "table {{.Service}}\t{{.Status}}" 2>/dev/null || echo "")
        
        if [ -n "$services_status" ]; then
            echo "$services_status" | tail -n +2 | while IFS=$'\t' read -r service status; do
                local status_icon="❓"
                local status_color="38;5;244"
                
                if [[ "$status" =~ "Up" ]]; then
                    if [[ "$status" =~ "healthy" ]]; then
                        status_icon="✅"
                        status_color="1;32"
                    elif [[ "$status" =~ "unhealthy" ]]; then
                        status_icon="❌"
                        status_color="1;31"
                    else
                        status_icon="🟡"
                        status_color="1;33"
                    fi
                elif [[ "$status" =~ "Exit" ]]; then
                    status_icon="❌"
                    status_color="1;31"
                elif [[ "$status" =~ "Restarting" ]]; then
                    status_icon="🔄"
                    status_color="1;33"
                fi
                
                printf "   \033[38;5;15m%-20s\033[0m \033[${status_color}m${status_icon} ${status}\033[0m\n" "$service:"
            done
        fi
    fi
    
    echo
    if [ $issues -eq 0 ]; then
        echo -e "\033[1;32m🎉 System health: EXCELLENT\033[0m"
        return 0
    else
        echo -e "\033[1;33m⚠️  Found $issues issue(s) that may affect performance\033[0m"
        
        # Предлагаем решения для типичных проблем
        echo
        echo -e "\033[1;37m💡 Recommendations:\033[0m"
        if [ $issues -gt 0 ]; then
            echo -e "\033[38;5;244m   • Check port conflicts and reconfigure if needed\033[0m"
            echo -e "\033[38;5;244m   • Review logs with '\033[38;5;15msudo $APP_NAME logs\033[38;5;244m'\033[0m"
            echo -e "\033[38;5;244m   • Restart services with '\033[38;5;15msudo $APP_NAME restart\033[38;5;244m'\033[0m"
        fi
        
        return 1
    fi
}



validate_compose_file() {
    local compose_file="$1"
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    
    local current_dir=$(pwd)
    cd "$(dirname "$compose_file")"
    
    if command -v docker >/dev/null 2>&1; then
        detect_compose
        
        if $COMPOSE config >/dev/null 2>&1; then
            cd "$current_dir"
            return 0
        else
            cd "$current_dir"
            return 1
        fi
    fi
    
    cd "$current_dir"
    return 0
}
status_command() {
    check_running_as_root
    detect_compose
    
    echo -e "\033[1;37m📊 Remnawave Panel Status Check:\033[0m"
    echo
    
    # Проверяем статус панели
    if is_remnawave_installed; then
        if is_remnawave_up; then
            printf "   \033[38;5;15m%-12s\033[0m \033[1;32m✅ Running\033[0m\n" "Status:"
        else
            printf "   \033[38;5;15m%-12s\033[0m \033[1;31m❌ Stopped\033[0m\n" "Status:"
        fi
    else
        printf "   \033[38;5;15m%-12s\033[0m \033[1;33m⚠️  Not Installed\033[0m\n" "Status:"
        return 1
    fi
    
    echo
    
    # Показываем статус сервисов
    echo -e "\033[1;37m🔧 Services Status:\033[0m"
    cd "$APP_DIR" 2>/dev/null || true
    
    local services_status=$($COMPOSE -f "$COMPOSE_FILE" ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "")
    
    if [ -n "$services_status" ]; then
        echo "$services_status" | tail -n +2 | while IFS=$'\t' read -r service status ports; do
            local status_icon="❓"
            local status_color="38;5;244"
            
            if [[ "$status" =~ "Up" ]]; then
                if [[ "$status" =~ "healthy" ]]; then
                    status_icon="✅"
                    status_color="1;32"
                elif [[ "$status" =~ "unhealthy" ]]; then
                    status_icon="❌"
                    status_color="1;31"
                else
                    status_icon="🟡"
                    status_color="1;33"
                fi
            elif [[ "$status" =~ "Exit" ]]; then
                status_icon="❌"
                status_color="1;31"
            elif [[ "$status" =~ "Restarting" ]]; then
                status_icon="🔄"
                status_color="1;33"
            fi
            
            printf "   \033[38;5;15m%-25s\033[0m \033[${status_color}m${status_icon} %-25s\033[0m \033[38;5;244m%s\033[0m\n" "$service" "$status" "$ports"
        done
    else
        echo -e "\033[38;5;244m   No services found\033[0m"
    fi
    
    echo
    
    # Показываем использование ресурсов основного контейнера
    echo -e "\033[1;37m💾 Использование ресурсов:\033[0m"
    local main_stats=$(docker stats --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}" "${APP_NAME}" 2>/dev/null || echo "N/A\tN/A")
    local cpu_perc=$(echo "$main_stats" | cut -f1)
    local mem_usage=$(echo "$main_stats" | cut -f2)
    
    if [ "$cpu_perc" != "N/A" ]; then
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250mCPU: %-10s %s\033[0m\n" "Main Panel:" "$cpu_perc" "$mem_usage"
    else
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;244mStats not available\033[0m\n" "Main Panel:"
    fi
    
    echo
    
    # Показываем информацию о подключении
    if [ -f "$ENV_FILE" ]; then
        echo -e "\033[1;37m🌐 Connection Information:\033[0m"
        
        local app_port=$(grep "^APP_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        local metrics_port=$(grep "^METRICS_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        local panel_domain=$(grep "^FRONT_END_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs 2>/dev/null)
        local sub_domain=$(grep "^SUB_PUBLIC_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs 2>/dev/null)
        
        # Subscription port
        local sub_port=""
        if [ -f "$SUB_ENV_FILE" ]; then
            sub_port=$(grep "^APP_PORT=" "$SUB_ENV_FILE" | cut -d'=' -f2)
        fi
        
        # IP адрес
        local server_ip="${NODE_IP:-127.0.0.1}"
        
        # URL подключения
        if [ -n "$app_port" ]; then
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s:%s\033[0m\n" "Panel URL:" "$server_ip" "$app_port"
        fi
        
        if [ -n "$sub_port" ]; then
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s:%s\033[0m\n" "Sub Page URL:" "$server_ip" "$sub_port"
        fi
        
        if [ -n "$metrics_port" ]; then
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s:%s/api/metrics\033[0m\n" "Metrics URL:" "$server_ip" "$metrics_port"
        fi
        
        # Домены
        if [ -n "$panel_domain" ] && [ "$panel_domain" != "null" ]; then
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Panel Domain:" "$panel_domain"
        fi
        
        if [ -n "$sub_domain" ] && [ "$sub_domain" != "null" ]; then
            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Sub Domain:" "$sub_domain"
        fi
    fi
    
    echo
    

    if is_remnawave_up; then
        local unhealthy_count=$(docker ps --format "{{.Names}}\t{{.Status}}" | grep "$APP_NAME" | grep -c "unhealthy" 2>/dev/null || echo "0")
        if ! [[ "$unhealthy_count" =~ ^[0-9]+$ ]]; then
            unhealthy_count=0
        fi
        
        if [ "$unhealthy_count" -eq 0 ]; then
            echo -e "\033[1;32m🎉 All services are healthy and running!\033[0m"
        else
            echo -e "\033[1;33m⚠️  Some services may have health issues ($unhealthy_count unhealthy)\033[0m"
        fi
    else
        echo -e "\033[1;31m❌ Services are not running\033[0m"
        echo -e "\033[38;5;8m   Use 'sudo $APP_NAME up' to start services\033[0m"
    fi
    if [[ "${BASH_SOURCE[1]}" =~ "main_menu" ]] || [[ "$0" =~ "$APP_NAME" ]] && [[ "$1" != "--no-pause" ]]; then
        echo
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
    fi
}

logs_command() {
    check_running_as_root
    detect_compose
    
    if ! is_remnawave_installed; then
        colorized_echo red "Remnawave не установлен!"
        return 1
    fi

    if ! is_remnawave_up; then
        colorized_echo red "Сервисы Remnawave не запущены!"
        colorized_echo yellow "   Run 'sudo $APP_NAME up' first"
        return 1
    fi

    logs_menu
}

logs_menu() {
    while true; do
        clear
        echo -e "\033[1;37m📋 Application Logs\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
        echo
        
        echo -e "\033[1;37m📊 Опции логов:\033[0m"
        echo -e "   \033[38;5;15m1)\033[0m 📱 Follow all logs (real-time)"
        echo -e "   \033[38;5;15m2)\033[0m 📄 Show last 100 lines"
        echo -e "   \033[38;5;15m3)\033[0m 🔍 Show specific service logs"
        echo -e "   \033[38;5;15m4)\033[0m ❌ Show error logs only"
        echo -e "   \033[38;5;244m0)\033[0m ⬅️  Back"
        echo
        
        read -p "Выберите опцию [0-4]: " choice
        
        case "$choice" in
            1) show_live_logs ;;
            2) show_recent_logs ;;
            3) show_service_logs ;;
            4) show_error_logs ;;
            0) return 0 ;;
            *) 
                echo -e "\033[1;31mInvalid option!\033[0m"
                sleep 1
                ;;
        esac
    done
}

show_live_logs() {
    clear
    echo -e "\033[1;37m📱 Live Logs (Press Ctrl+C to exit)\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    echo
    
    cd "$APP_DIR"
    $COMPOSE -f "$COMPOSE_FILE" logs -f --tail=50
    
    echo
    echo ""; echo -e "\033[1;32m✅ Возврат в меню через 2 секунды...\033[0m"; sleep 2
}

show_recent_logs() {
    clear
    echo -e "\033[1;37m📄 Last 100 Log Lines\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    echo
    
    cd "$APP_DIR"
    $COMPOSE -f "$COMPOSE_FILE" logs --tail=100
    
    echo
    echo ""; echo -e "\033[1;32m✅ Возврат в меню через 2 секунды...\033[0m"; sleep 2
}

show_service_logs() {
    while true; do
        clear
        echo -e "\033[1;37m🔍 Service Logs\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
        echo
        
        echo -e "\033[1;37m📦 Available Services:\033[0m"
        echo -e "   \033[38;5;15m1)\033[0m 🚀 Main Panel (remnawave)"
        echo -e "   \033[38;5;15m2)\033[0m 🗄️  Database (remnawave-db)"
        echo -e "   \033[38;5;15m3)\033[0m 📊 Redis (remnawave-redis)"
        echo -e "   \033[38;5;15m4)\033[0m 📄 Subscription Page"
        echo -e "   \033[38;5;244m0)\033[0m ⬅️  Back"
        echo
        
        read -p "Select service [0-4]: " service_choice
        
        local service_name=""
        case "$service_choice" in
            1) service_name="remnawave" ;;
            2) service_name="remnawave-db" ;;
            3) service_name="remnawave-redis" ;;
            4) service_name="remnawave-subscription-page" ;;
            0) return 0 ;;
            *) 
                echo -e "\033[1;31mInvalid option!\033[0m"
                sleep 1
                continue
                ;;
        esac
        
        clear
        echo -e "\033[1;37m📋 Logs for: $service_name\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        echo
        
        cd "$APP_DIR"
        $COMPOSE -f "$COMPOSE_FILE" logs --tail=100 "$service_name"
        
        echo
        echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3
    done
}

show_error_logs() {
    clear
    echo -e "\033[1;37m❌ Error Logs Only\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    echo
    
    cd "$APP_DIR"
    $COMPOSE -f "$COMPOSE_FILE" logs --tail=200 | grep -i "error\|exception\|failed\|fatal" || echo "No errors found in recent logs"
    
    echo
    echo ""; echo -e "\033[1;32m✅ Возврат в меню через 2 секунды...\033[0m"; sleep 2
}
update_command() {
    check_running_as_root
    if ! is_remnawave_installed; then
        echo -e "\033[1;31m❌ Remnawave не установлен!\033[0m"
        echo -e "\033[38;5;8m   Run '\033[38;5;15msudo $APP_NAME install\033[38;5;8m' first\033[0m"
        exit 1
    fi
    
    detect_compose
    
    echo -e "\033[1;37m🔄 Starting Remnawave Update Check...\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    # Получаем текущую версию скрипта
    local current_script_version="$SCRIPT_VERSION"
    
    # Получаем последнюю версию скрипта с GitHub
    echo -e "\033[38;5;250m📝 Step 1:\033[0m Checking for script updates..."
    local remote_script_version=$(curl -s "$SCRIPT_URL" 2>/dev/null | grep "^SCRIPT_VERSION=" | cut -d'"' -f2)
    
    if [ -n "$remote_script_version" ] && [ "$remote_script_version" != "$current_script_version" ]; then
        echo -e "\033[1;33m🔄 Script update available: \033[38;5;15mv$current_script_version\033[0m → \033[1;37mv$remote_script_version\033[0m"
        read -p "Do you want to update the script first? (y/n): " -r update_script
        if [[ $update_script =~ ^[Yy]$ ]]; then
            update_remnawave_script
            echo -e "\033[1;32m✅ Script updated to v$remote_script_version\033[0m"
            echo -e "\033[38;5;8m   Please run the update command again to continue\033[0m"
            exit 0
        fi
    else
        echo -e "\033[1;32m✅ Script is up to date (v$current_script_version)\033[0m"
    fi
    cd "$APP_DIR" 2>/dev/null || { echo -e "\033[1;31m❌ Cannot access app directory\033[0m"; exit 1; }

    echo -e "\033[38;5;250m📝 Step 2:\033[0m Checking current images..."
    local compose_images=$($COMPOSE -f "$COMPOSE_FILE" config 2>/dev/null | grep "image:" | awk '{print $2}' | sort | uniq)
    
    if [ -z "$compose_images" ]; then
        echo -e "\033[1;31m❌ Cannot read compose file images\033[0m"
        exit 1
    fi
    
    echo -e "\033[38;5;244mImages to check:\033[0m"
    echo "$compose_images" | while read image; do
        echo -e "\033[38;5;244m   $image\033[0m"
    done

    echo -e "\033[38;5;250m📝 Step 3:\033[0m Pulling latest images..."
    
    local pull_output=""
    local pull_exit_code=0

    pull_output=$($COMPOSE -f "$COMPOSE_FILE" pull 2>&1) || pull_exit_code=$?
    
    if [ $pull_exit_code -ne 0 ]; then
        echo -e "\033[1;31m❌ Failed to pull images:\033[0m"
        echo -e "\033[38;5;244m$pull_output\033[0m"
        exit 1
    fi

    local images_updated=false
    local update_indicators=""

    if echo "$pull_output" | grep -qi "downloading\|downloaded\|pulling fs layer\|extracting\|pull complete"; then
        images_updated=true
        update_indicators="New layers downloaded"
    fi

    local up_to_date_count=$(echo "$pull_output" | grep -ci "image is up to date\|already exists")
    local total_images_count=$(echo "$compose_images" | wc -l)

    if [ "$up_to_date_count" -ge "$total_images_count" ] && [ "$total_images_count" -gt 0 ]; then
        if ! echo "$pull_output" | grep -qi "downloading\|downloaded\|pulling fs layer\|extracting\|pull complete"; then
            images_updated=false
        fi
    fi

    if echo "$pull_output" | grep -qi "digest.*differs\|newer image\|status.*downloaded"; then
        images_updated=true
        update_indicators="$update_indicators, Newer versions detected"
    fi
    
    # Выводим детальную информацию для диагностики
    echo -e "\033[38;5;244mPull analysis:\033[0m"
    echo -e "\033[38;5;244m   Images checked: $total_images_count\033[0m"
    echo -e "\033[38;5;244m   Up-to-date responses: $up_to_date_count\033[0m"
    
    # Показываем результат
    if [ "$images_updated" = true ]; then
        echo -e "\033[1;32m✅ New image versions available!\033[0m"
        if [ -n "$update_indicators" ]; then
            echo -e "\033[38;5;244m   Indicators: $update_indicators\033[0m"
        fi
        
        # Показываем какие образы были обновлены (из вывода pull)
        local updated_images=$(echo "$pull_output" | grep -i "pulling\|downloaded" | head -3)
        if [ -n "$updated_images" ]; then
            echo -e "\033[38;5;244m   Update activity detected\033[0m"
        fi
    else
        echo -e "\033[1;32m✅ Все образы уже актуальны\033[0m"
        echo
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        echo -e "\033[1;37m🎉 No updates available!\033[0m"
        echo -e "\033[38;5;250m🎯 All components are running the latest versions\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        exit 0
    fi
    
    # Проверяем, запущен ли контейнер
    local was_running=false
    if is_remnawave_up; then
        was_running=true
        echo -e "\033[38;5;250m📝 Step 4:\033[0m Stopping services for update..."
        if down_remnawave; then
            echo -e "\033[1;32m✅ Services stopped\033[0m"
        else
            echo -e "\033[1;31m❌ Failed to stop services\033[0m"
            exit 1
        fi
    else
        echo -e "\033[38;5;250m📝 Step 4:\033[0m Services already stopped\033[0m"
    fi
    
    # Запускаем сервисы с новыми образами
    if [ "$was_running" = true ]; then
        echo -e "\033[38;5;250m📝 Step 5:\033[0m Starting updated services..."
        if up_remnawave; then
            echo -e "\033[1;32m✅ Services started successfully\033[0m"
            
            # Проверяем здоровье сервисов после запуска
            echo -e "\033[38;5;250m🔍 Waiting for services to become healthy...\033[0m"
            local attempts=0
            local max_attempts=30
            
            while [ $attempts -lt $max_attempts ]; do
                if is_remnawave_up; then
                    echo -e "\033[1;32m✅ All services are healthy\033[0m"
                    break
                fi
                
                sleep 2
                attempts=$((attempts + 1))
                
                if [ $attempts -eq $max_attempts ]; then
                    echo -e "\033[1;33m⚠️  Services started but may still be initializing\033[0m"
                    echo -e "\033[38;5;8m   Check status with '\033[38;5;15msudo $APP_NAME status\033[38;5;8m'\033[0m"
                fi
            done
        else
            echo -e "\033[1;31m❌ Failed to start services\033[0m"
            echo -e "\033[38;5;8m   Check logs with '\033[38;5;15msudo $APP_NAME logs\033[38;5;8m'\033[0m"
            exit 1
        fi
    else
        echo -e "\033[38;5;250m📝 Step 5:\033[0m Services were not running, skipping startup\033[0m"
        echo -e "\033[38;5;8m   Run '\033[38;5;15msudo $APP_NAME up\033[38;5;8m' to start when ready\033[0m"
    fi
    
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    echo -e "\033[1;37m🎉 Remnawave успешно обновлен!\033[0m"
    
    # Показываем итоговую информацию
    if [ "$was_running" = true ]; then
        echo -e "\033[38;5;250m💡 Services are running with latest versions\033[0m"
        echo -e "\033[38;5;8m   Check status: '\033[38;5;15msudo $APP_NAME status\033[38;5;8m'\033[0m"
    fi
    
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
}

edit_command() {
    detect_os
    check_editor
    if [ -f "$COMPOSE_FILE" ]; then
        $EDITOR "$COMPOSE_FILE"
    else
        colorized_echo red "Файл compose не найден по пути $COMPOSE_FILE"
        exit 1
    fi
}

edit_env_command() {
    detect_os
    check_editor
    if [ -f "$ENV_FILE" ]; then
        $EDITOR "$ENV_FILE"
    else
        colorized_echo red "Файл окружения не найден по пути $ENV_FILE"
        exit 1
    fi
}

edit_env_sub_command() {
    detect_os
    check_editor
    if [ -f "$SUB_ENV_FILE" ]; then
        $EDITOR "$SUB_ENV_FILE"
    else
        colorized_echo red "Файл окружения подписки не найден по пути $SUB_ENV_FILE"
        exit 1
    fi
}

console_command() {
        if ! is_remnawave_installed; then
            colorized_echo red "Remnawave не установлен!"
            exit 1
        fi
    
     detect_compose
 
        if ! is_remnawave_up; then
            colorized_echo red "Remnawave is not running. Start it first with 'remnawave up'"
            exit 1
        fi

    docker exec -it $APP_NAME remnawave
}

pm2_monitor() {
        if ! is_remnawave_installed; then
            colorized_echo red "Remnawave не установлен!"
            exit 1
        fi
    
     detect_compose
 
        if ! is_remnawave_up; then
            colorized_echo red "Remnawave is not running. Start it first with 'remnawave up'"
            exit 1
        fi

    docker exec -it $APP_NAME pm2 monit
}

main_menu() {
    while true; do
        clear
        echo -e "\033[1;37m╔══════════════════════════════════════════════════════════════╗\033[0m"
        echo -e "\033[1;37m║\033[0m  \033[1;36m⚡ $APP_NAME Panel Management\033[0m"
        echo -e "\033[1;37m╚══════════════════════════════════════════════════════════════╝\033[0m"
        echo
        
        # Проверка статуса панели
        if is_remnawave_installed; then
            if is_remnawave_up; then
                echo -e "\033[1;32m✅ Статус панели: ЗАПУЩЕНА\033[0m"
                
                if [ -f "$ENV_FILE" ]; then

                    local panel_domain=$(grep "FRONT_END_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs 2>/dev/null)
                    local sub_domain=$(grep "SUB_PUBLIC_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs 2>/dev/null)
                    
                    echo
                    echo -e "\033[1;37m🌐 URL доступа:\033[0m"
                    
                    local domains_found=0
                    
                    # Panel Domain (FRONT_END_DOMAIN)
                    if [ -n "$panel_domain" ] && [ "$panel_domain" != "null" ]; then
                        domains_found=$((domains_found + 1))
                        if [[ "$panel_domain" =~ ^https?:// ]]; then
                            printf "   \033[38;5;15m📊 Админ панель:\033[0m    \033[38;5;117m%s\033[0m\n" "$panel_domain"
                        else
                            printf "   \033[38;5;15m📊 Админ панель:\033[0m    \033[38;5;117mhttps://%s\033[0m\n" "$panel_domain"
                        fi
                    fi
                    
                    # Subscription Domain (SUB_PUBLIC_DOMAIN)
                    if [ -n "$sub_domain" ] && [ "$sub_domain" != "null" ]; then
                        domains_found=$((domains_found + 1))
                        if [[ "$sub_domain" =~ ^https?:// ]]; then
                            printf "   \033[38;5;15m📄 Подписки:\033[0m   \033[38;5;117m%s\033[0m\n" "$sub_domain"
                        else
                            printf "   \033[38;5;15m📄 Подписки:\033[0m   \033[38;5;117mhttps://%s\033[0m\n" "$sub_domain"
                        fi
                    fi
                    
                    echo
                    if [ "$domains_found" -gt 0 ]; then
                        echo -e "\033[38;5;32m✅ Домены настроены - Панель доступна по HTTPS\033[0m"
                    else
                        echo -e "\033[1;33m⚠️  Домены не настроены - Панель недоступна!\033[0m"
                        echo
                        echo -e "\033[1;37m🔧 Setup Required:\033[0m"
                        echo -e "\033[38;5;244m   1. Configure reverse proxy (nginx/cloudflare)\033[0m"
                        echo -e "\033[38;5;244m   2. Set domains in environment (option 13)\033[0m"
                        echo -e "\033[38;5;244m   3. Configure SSL certificates\033[0m"
                    fi
                fi
                
                # Показываем статус сервисов
                echo
                echo -e "\033[1;37m🔧 Services Status:\033[0m"
                detect_compose
                cd "$APP_DIR" 2>/dev/null || true
                local services_status=$($COMPOSE -f "$COMPOSE_FILE" ps --format "table" 2>/dev/null || echo "")
                
                if [ -n "$services_status" ]; then
                    # Подсчитываем сервисы
                    local total_services=$(echo "$services_status" | tail -n +2 | wc -l)
                    local running_services=$(echo "$services_status" | tail -n +2 | grep -c "Up" || echo "0")
                    local healthy_services=$(echo "$services_status" | tail -n +2 | grep -c "healthy" || echo "0")
                    
                    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s/%s running\033[0m\n" "Total Services:" "$running_services" "$total_services"
                    if [ "$healthy_services" -gt 0 ]; then
                        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s healthy\033[0m\n" "Health Checks:" "$healthy_services"
                    fi
                fi
                
                # Показываем использование ресурсов
                echo
    echo -e "\033[1;37m💾 Использование ресурсов:\033[0m"
                
                # CPU и Memory
                local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
                local mem_info=$(free -h | grep "Mem:" 2>/dev/null)
                local mem_used=$(echo "$mem_info" | awk '{print $3}' 2>/dev/null || echo "N/A")
                local mem_total=$(echo "$mem_info" | awk '{print $2}' 2>/dev/null || echo "N/A")
                
                printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s%%\033[0m\n" "CPU:" "$cpu_usage"
                printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s / %s\033[0m\n" "Память:" "$mem_used" "$mem_total"
                
                # Дисковое пространство
                local disk_usage=$(df -h "$APP_DIR" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' 2>/dev/null || echo "N/A")
                local disk_available=$(df -h "$APP_DIR" 2>/dev/null | tail -1 | awk '{print $4}' 2>/dev/null || echo "N/A")
                
                printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s%% использовано, %s доступно\033[0m\n" "Диск:" "$disk_usage" "$disk_available"
                
                # Информация о бэкапах
                if [ -f "$BACKUP_CONFIG_FILE" ]; then
                    echo
                    echo -e "\033[1;37m📅 Backup Status:\033[0m"
                    local backup_enabled=$(jq -r '.telegram.enabled // false' "$BACKUP_CONFIG_FILE" 2>/dev/null)
                    local backup_schedule=$(jq -r '.schedule // "Not configured"' "$BACKUP_CONFIG_FILE" 2>/dev/null)
                    local scheduler_status=$(schedule_get_status 2>/dev/null || echo "disabled")
                    
                    printf "   \033[38;5;15m%-15s\033[0m " "Scheduler:"
                    if [ "$scheduler_status" = "enabled" ]; then
                        echo -e "\033[1;32m✅ Enabled\033[0m"
                    else
                        echo -e "\033[1;31m❌ Disabled\033[0m"
                    fi
                    
                    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Schedule:" "$backup_schedule"
                    printf "   \033[38;5;15m%-15s\033[0m " "Telegram:"
                    if [ "$backup_enabled" = "true" ]; then
                        echo -e "\033[1;32m✅ Enabled\033[0m"
                    else
                        echo -e "\033[38;5;244m❌ Disabled\033[0m"
                    fi
                    
                    # Последний бэкап
                    if [ -d "$APP_DIR/backups" ]; then
                        local last_backup=$(ls -t "$APP_DIR/backups"/*.sql* 2>/dev/null | head -1)
                        if [ -n "$last_backup" ]; then
                            local backup_date=$(stat -c %y "$last_backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
                            printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Last Backup:" "$backup_date"
                        fi
                    fi
                fi
                
            else
                echo -e "\033[1;31m❌ Статус панели: ОСТАНОВЛЕНА\033[0m"
                echo -e "\033[38;5;244m   Сервисы установлены, но не запущены\033[0m"
                echo -e "\033[38;5;244m   Используйте опцию 4 для запуска сервисов\033[0m"
            fi
        else
            echo -e "\033[1;33m⚠️  Статус панели: НЕ УСТАНОВЛЕНА\033[0m"
            echo -e "\033[38;5;244m   Используйте опцию 1 для установки панели Remnawave\033[0m"
        fi
        
        echo
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;37m🚀 УСТАНОВКА И ОБНОВЛЕНИЯ\033[0m"
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "  \033[38;5;15m1)\033[0m 🛠️  Установить панель Remnawave"
        echo -e "  \033[38;5;15m2)\033[0m ⬆️  Обновить до последней версии"
        echo -e "  \033[38;5;15m3)\033[0m 🗑️  Полностью удалить панель"
        echo
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;37m⚙️  УПРАВЛЕНИЕ СЕРВИСАМИ\033[0m"
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "  \033[38;5;15m4)\033[0m ▶️  Запустить все сервисы"
        echo -e "  \033[38;5;15m5)\033[0m ⏹️  Остановить все сервисы"
        echo -e "  \033[38;5;15m6)\033[0m 🔄 Перезапустить все сервисы"
        echo -e "  \033[38;5;15m7)\033[0m 📊 Показать статус сервисов"
        echo
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;37m📊 МОНИТОРИНГ И ЛОГИ\033[0m"
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "  \033[38;5;15m8)\033[0m 📋 Просмотреть логи приложения"
        echo -e "  \033[38;5;15m9)\033[0m 📈 Монитор производительности системы"
        echo -e "  \033[38;5;15m10)\033[0m 🩺 Диагностика состояния здоровья"
        echo
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;37m💾 РЕЗЕРВНОЕ КОПИРОВАНИЕ И ВОССТАНОВЛЕНИЕ\033[0m"
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "  \033[38;5;15m11)\033[0m 💾 Ручное резервное копирование"
        echo -e "  \033[38;5;15m12)\033[0m 📅 Система запланированных бэкапов"
        echo -e "  \033[38;5;15m13)\033[0m 🔄 Восстановить из бэкапа"
        echo
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;37m🔧 КОНФИГУРАЦИЯ И ДОСТУП\033[0m"
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "  \033[38;5;15m14)\033[0m 📝 Редактировать файлы конфигурации"
        echo -e "  \033[38;5;15m15)\033[0m 🖥️  Доступ к оболочке контейнера"
        echo -e "  \033[38;5;15m16)\033[0m 📊 Монитор процессов PM2"
        echo
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;37m🚪 ВЫХОД\033[0m"
        echo -e "\033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "  \033[38;5;15m0)\033[0m 🚪 Выход в терминал"
        echo
        read -p "$(echo -e "\033[1;37mВыберите опцию [0-16]:\033[0m ")" choice

        case "$choice" in
            1) install_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            2) update_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            3) uninstall_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            4) up_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            5) down_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            6) restart_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            7) status_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            8) logs_command ;;
            9) monitor_command ;;
            10) health_check_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            11) backup_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            12) schedule_menu ;;
            13) restore_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;  
            14) edit_command_menu ;;  
            15) console_command ;;
            16) pm2_monitor ;;
            0) clear; exit 0 ;;
            *) 
                echo -e "\033[1;31mНеверная опция!\033[0m"
                sleep 1
                ;;
        esac
    done
}


edit_command_menu() {
    while true; do
        clear
        echo -e "\033[1;37m📝 Configuration Editor\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
        echo
        echo -e "   \033[38;5;15m1)\033[0m 📝 Edit docker-compose.yml"
        echo -e "   \033[38;5;15m2)\033[0m ⚙️  Edit main environment (.env)"
        echo -e "   \033[38;5;15m3)\033[0m 📄 Edit subscription environment (.env.subscription)"
        echo -e "   \033[38;5;244m0)\033[0m ⬅️  Back"
        echo
        
        read -p "Выберите опцию [0-3]: " choice
        
        case "$choice" in
            1) edit_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            2) edit_env_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            3) edit_env_sub_command; echo ""; echo -e "\033[1;32m✅ Операция завершена. Возврат в меню через 3 секунды...\033[0m"; sleep 3 ;;
            0) return 0 ;;
            *) 
                echo -e "\033[1;31mНеверная опция!\033[0m"
                sleep 1
                ;;
        esac
    done
}
usage() {
    echo -e "\033[1;37m⚡ $APP_NAME\033[0m \033[38;5;8mCLI управления панелью\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    echo
    echo -e "\033[1;37m🎯 Установка и обновления:\033[0m"
    printf "   \033[38;5;15m%-18s\033[0m %s\n" "install" "🛠️  Install Remnawave panel"
    printf "   \033[38;5;15m%-18s\033[0m %s\n" "update" "⬆️  Update to latest version"
    printf "   \033[38;5;15m%-18s\033[0m %s\n" "uninstall" "🗑️  Remove panel completely"
    echo

    echo -e "\033[1;37m⚙️  Service Management:\033[0m"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "up" "▶️  Start all services"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "down" "⏹️  Stop all services"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "restart" "🔄 Restart all services"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "status" "📊 Show services status"
    echo

    echo -e "\033[1;37m📊 Monitoring & Logs:\033[0m"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "logs" "📋 View application logs"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "monitor" "📈 System performance monitor"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "health" "🩺 Health check diagnostics"
    echo

    echo -e "\033[1;37m💾 Backup & Restore:\033[0m"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "backup" "💾 Manual database backup"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "schedule" "📅 Scheduled backup system"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "restore" "🔄 Restore from backup" 
    echo

    echo -e "\033[1;37m🔧 Configuration & Access:\033[0m"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "edit" "📝 Edit docker-compose.yml"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "edit-env" "⚙️  Edit environment variables"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "edit-env-sub" "⚙️  Edit subscription environment variables"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "console" "📥  Access container shell"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "pm2-monitor" "📊 PM2 process monitor"
    echo

    echo -e "\033[1;37m📊 Script Management:\033[0m"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "install-script" "📥 Install this script globally"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "uninstall-script" "📤 Remove script from system"
    echo
    echo -e "\033[38;5;8m💡 Flexible restore paths:\033[0m"
    echo -e "\033[38;5;244m   remnawave restore --path /root --name newpanel\033[0m"
    echo -e "\033[38;5;244m   # Installs to /root/newpanel/\033[0m"

    if is_remnawave_installed && [ -f "$ENV_FILE" ]; then
        local panel_domain=$(grep "FRONT_END_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs 2>/dev/null)
        if [ -n "$panel_domain" ] && [ "$panel_domain" != "null" ]; then
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
            if [[ "$panel_domain" =~ ^https?:// ]]; then
                echo -e "\033[1;37m🌐 Panel Access:\033[0m \033[38;5;117m$panel_domain\033[0m"
            else
                echo -e "\033[1;37m🌐 Panel Access:\033[0m \033[38;5;117mhttps://$panel_domain\033[0m"
            fi
        fi
    fi

    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    echo -e "\033[1;37m📖 Примеры:\033[0m"
    echo -e "\033[38;5;244m   sudo $APP_NAME install --name mypanel\033[0m"
    echo -e "\033[38;5;244m   sudo $APP_NAME schedule setup\033[0m"
    echo -e "\033[38;5;244m   sudo $APP_NAME backup --compress\033[0m"
    echo -e "\033[38;5;244m   $APP_NAME menu           # Interactive menu\033[0m"
    echo -e "\033[38;5;244m   $APP_NAME                # Same as menu\033[0m"
    echo
    echo -e "\033[38;5;8mUse '\033[38;5;15m$APP_NAME <command> --help\033[38;5;8m' for detailed command help\033[0m"
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    echo -e "\033[38;5;8m💬 Support: \033[38;5;250mhttps://t.me/remnawave\033[0m"
    echo -e "\033[38;5;8m👨‍💻 Author: \033[38;5;250mDigneZzZ\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
}

usage_minimal() {
    echo -e "\033[1;37m⚡ $APP_NAME\033[0m"
    echo
    echo -e "\033[1;37mMain:\033[0m"
    printf "   \033[38;5;15m%-12s\033[0m %s\n" "install" "🛠️  Install"
    printf "   \033[38;5;15m%-12s\033[0m %s\n" "update" "⬆️  Update"
    printf "   \033[38;5;15m%-12s\033[0m %s\n" "uninstall" "🗑️  Remove"
    echo
    echo -e "\033[1;37mControl:\033[0m"
    printf "   \033[38;5;250m%-12s\033[0m %s\n" "up" "▶️  Start"
    printf "   \033[38;5;250m%-12s\033[0m %s\n" "down" "⏹️  Stop"
    printf "   \033[38;5;250m%-12s\033[0m %s\n" "restart" "🔄 Restart"
    printf "   \033[38;5;250m%-12s\033[0m %s\n" "status" "📊 Status"
    echo
    echo -e "\033[1;37mTools:\033[0m"
    printf "   \033[38;5;244m%-12s\033[0m %s\n" "logs" "📋 Logs"
    printf "   \033[38;5;244m%-12s\033[0m %s\n" "monitor" "📈 Monitor"
    printf "   \033[38;5;244m%-12s\033[0m %s\n" "health" "🩺 Health"
    printf "   \033[38;5;244m%-12s\033[0m %s\n" "backup" "💾 Backup"
    printf "   \033[38;5;244m%-12s\033[0m %s\n" "schedule" "📅 Schedule"
    echo
    echo -e "\033[38;5;8mUse '\033[38;5;15m$APP_NAME help\033[38;5;8m' for full help\033[0m"
}

usage_compact() {
    echo -e "\033[1;37m⚡ $APP_NAME\033[0m \033[38;5;8mPanel CLI\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    echo
    
    echo -e "\033[1;37m🚀 Main:\033[0m"
    printf "   \033[38;5;15m%-16s\033[0m %s\n" "install" "🛠️  Install panel"
    printf "   \033[38;5;15m%-16s\033[0m %s\n" "update" "⬆️  Update system"
    printf "   \033[38;5;15m%-16s\033[0m %s\n" "uninstall" "🗑️  Remove panel"
    echo

    echo -e "\033[1;37m⚙️  Control:\033[0m"
    printf "   \033[38;5;250m%-16s\033[0m %s\n" "up" "▶️  Start services"
    printf "   \033[38;5;250m%-16s\033[0m %s\n" "down" "⏹️  Stop services"
    printf "   \033[38;5;250m%-16s\033[0m %s\n" "restart" "🔄 Restart services"
    printf "   \033[38;5;250m%-16s\033[0m %s\n" "status" "📊 Show status"
    echo

    echo -e "\033[1;37m📊 Monitoring:\033[0m"
    printf "   \033[38;5;244m%-16s\033[0m %s\n" "logs" "📋 View logs"
    printf "   \033[38;5;244m%-16s\033[0m %s\n" "monitor" "📈 Performance"
    printf "   \033[38;5;244m%-16s\033[0m %s\n" "health" "🩺 Health check"
    echo

    echo -e "\033[1;37m💾 Backup:\033[0m"
    printf "   \033[38;5;178m%-16s\033[0m %s\n" "backup" "💾 Manual backup"
    printf "   \033[38;5;178m%-16s\033[0m %s\n" "schedule" "📅 Auto backup"
    echo

    echo -e "\033[1;37m🔧 Config:\033[0m"
    printf "   \033[38;5;117m%-16s\033[0m %s\n" "edit" "📝 Edit compose"
    printf "   \033[38;5;117m%-16s\033[0m %s\n" "edit-env" "⚙️  Edit environment"
    printf "   \033[38;5;117m%-16s\033[0m %s\n" "edit-env-sub" "⚙️  Edit subscription environment"
    printf "   \033[38;5;117m%-16s\033[0m %s\n" "console" "🖥️  Shell access"
    echo

    if is_remnawave_installed && [ -f "$ENV_FILE" ]; then
        local panel_domain=$(grep "FRONT_END_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs 2>/dev/null)
        if [ -n "$panel_domain" ] && [ "$panel_domain" != "null" ]; then
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
            if [[ "$panel_domain" =~ ^https?:// ]]; then
                echo -e "\033[1;37m🌐 Panel Access:\033[0m \033[38;5;117m$panel_domain\033[0m"
            else
                echo -e "\033[1;37m🌐 Panel Access:\033[0m \033[38;5;117mhttps://$panel_domain\033[0m"
            fi
        fi
    fi
    echo
    echo -e "\033[38;5;8mUse '\033[38;5;15m$APP_NAME <command> help\033[38;5;8m' for details\033[0m"
    echo
}


show_version() {
    echo -e "\033[1;37m⚡ Remnawave Panel CLI\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    echo -e "\033[38;5;250mVersion: \033[38;5;15m$SCRIPT_VERSION\033[0m"
    echo -e "\033[38;5;250mAuthor:  \033[38;5;15mDigneZzZ\033[0m"
    echo -e "\033[38;5;250mCommunity: \033[38;5;15mhttps://openode.xyz\033[0m"
    echo -e "\033[38;5;250mSupport: \033[38;5;15mhttps://t.me/remnawave\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
}


command_help() {
    local cmd="$1"
    
    case "$cmd" in
        install)
            echo -e "\033[1;37m📖 Install Command Help\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
            echo
            echo -e "\033[1;37mИспользование:\033[0m"
            echo -e "   \033[38;5;15m$APP_NAME install [options]\033[0m"
            echo
            echo -e "\033[1;37mОпции:\033[0m"
            echo -e "   \033[38;5;15m--name <name>\033[0m    Custom installation name"
            echo -e "   \033[38;5;15m--dev\033[0m            Use development branch"
            echo
            echo -e "\033[1;37mПримеры:\033[0m"
            echo -e "   \033[38;5;244m$APP_NAME install\033[0m"
            echo -e "   \033[38;5;244m$APP_NAME install --name mypanel\033[0m"
            echo -e "   \033[38;5;244m$APP_NAME install --dev\033[0m"
            ;;
        schedule)
            echo -e "\033[1;37m📖 Schedule Command Help\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
            echo
            echo -e "\033[1;37mИспользование:\033[0m"
            echo -e "   \033[38;5;15m$APP_NAME schedule [action]\033[0m"
            echo
            echo -e "\033[1;37mActions:\033[0m"
            echo -e "   \033[38;5;15msetup\033[0m           Configure backup settings"
            echo -e "   \033[38;5;15menable\033[0m          Enable scheduler"
            echo -e "   \033[38;5;15mdisable\033[0m         Disable scheduler"
            echo -e "   \033[38;5;15mstatus\033[0m          Показать статус планировщика"
            echo -e "   \033[38;5;15mtest\033[0m            Тестовое создание бэкапа"
            echo -e "   \033[38;5;15mtest-telegram\033[0m   Тест отправки в Telegram"
            echo -e "   \033[38;5;15mrun\033[0m             Запустить бэкап сейчас"
            echo -e "   \033[38;5;15mlogs\033[0m            Просмотр логов бэкапа"
            echo -e "   \033[38;5;15mcleanup\033[0m         Очистка старых бэкапов"
            echo
            echo -e "\033[1;37mВозможности:\033[0m"
            echo -e "   \033[38;5;250m• Автоматические бэкапы базы данных\033[0m"
            echo -e "   \033[38;5;250m• Уведомления в Telegram с разбиением файлов\033[0m"
            echo -e "   \033[38;5;250m• Настраиваемая политика хранения\033[0m"
            echo -e "   \033[38;5;250m• Варианты сжатия\033[0m"
            echo -e "   \033[38;5;250m• Поддержка веток (thread) в групповых чатах\033[0m"
            ;;

        backup)
            echo -e "\033[1;37m📖 Справка по команде backup\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
            echo
            echo -e "\033[1;37mИспользование:\033[0m"
            echo -e "   \033[38;5;15m$APP_NAME backup [options]\033[0m"
            echo
            echo -e "\033[1;37mОпции:\033[0m"
            echo -e "   \033[38;5;15m--compress\033[0m       Создать сжатый бэкап"
            echo -e "   \033[38;5;15m--output <dir>\033[0m   Указать выходную директорию"
            echo
            echo -e "\033[1;37mПримечание:\033[0m"
            echo -e "   \033[38;5;250mДля автоматических бэкапов с отправкой в Telegram\033[0m"
            echo -e "   \033[38;5;250mиспользуйте команду '\033[38;5;15m$APP_NAME schedule\033[38;5;250m'.\033[0m"
            ;;
        monitor)
            echo -e "\033[1;37m📖 Справка по команде monitor\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
            echo
            echo -e "\033[1;37mОписание:\033[0m"
            echo -e "   \033[38;5;250mReal-time system monitoring dashboard\033[0m"
            echo
            echo -e "\033[1;37mОтображает:\033[0m"
            echo -e "   \033[38;5;250m• CPU and Memory usage\033[0m"
            echo -e "   \033[38;5;250m• Docker container stats\033[0m"
            echo -e "   \033[38;5;250m• Network I/O\033[0m"
            echo -e "   \033[38;5;250m• Disk usage\033[0m"
            echo -e "   \033[38;5;250m• Service health status\033[0m"
            echo
            echo -e "\033[1;37mУправление:\033[0m"
            echo -e "   \033[38;5;250mНажмите \033[38;5;15mCtrl+C\033[38;5;250m для выхода\033[0m"
            ;;
        health)
            echo -e "\033[1;37m📖 Справка по команде health\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 30))\033[0m"
            echo
            echo -e "\033[1;37mОписание:\033[0m"
            echo -e "   \033[38;5;250mComprehensive system health diagnostics\033[0m"
            echo
            echo -e "\033[1;37mПроверяет:\033[0m"
            echo -e "   \033[38;5;250m• Service availability\033[0m"
            echo -e "   \033[38;5;250m• Database connectivity\033[0m"
            echo -e "   \033[38;5;250m• Port accessibility\033[0m"
            echo -e "   \033[38;5;250m• Resource usage\033[0m"
            echo -e "   \033[38;5;250m• Docker health\033[0m"
            echo -e "   \033[38;5;250m• Configuration validation\033[0m"
            ;;
        *)
            echo -e "\033[1;37m📖 Справка по командам\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 20))\033[0m"
            echo
            echo -e "\033[1;31mНеизвестная команда: $cmd\033[0m"
            echo
            echo -e "\033[1;37mДоступные команды:\033[0m"
            echo -e "   \033[38;5;250minstall, update, uninstall, up, down, restart\033[0m"
            echo -e "   \033[38;5;250mstatus, logs, monitor, health, backup, schedule\033[0m"
            echo -e "   \033[38;5;250medit, edit-env, console, pm2-monitor\033[0m"
            echo
            echo -e "\033[38;5;8mИспользуйте '\033[38;5;15m$APP_NAME help\033[38;5;8m' для подробной справки\033[0m"
            ;;
    esac
}

smart_usage() {
    if [ "$1" = "help" ] && [ -n "$2" ]; then
        command_help "$2"
        return
    fi
    
    local terminal_width=$(tput cols 2>/dev/null || echo "80")
    local terminal_height=$(tput lines 2>/dev/null || echo "24")
    
    if [ "$terminal_width" -lt 50 ]; then
        usage_minimal
    elif [ "$terminal_width" -lt 80 ] || [ "$terminal_height" -lt 35 ]; then
        usage_compact
    else
        usage
    fi
}



case "$COMMAND" in
    install) install_command ;;
    update) update_command ;;
    uninstall) uninstall_command ;;
    up) up_command ;;
    down) down_command ;;
    restart) restart_command ;;
    status) status_command ;;
    logs) logs_command ;;
    monitor) monitor_command ;;
    health) health_check_command ;;
    schedule) schedule_command "$@" ;;
    install-script) install_remnawave_script ;;
    uninstall-script) uninstall_remnawave_script ;;
    edit) edit_command ;;
    edit-env) edit_env_command ;;
    edit-env-sub) edit_env_sub_command ;;
    console) console_command ;;
    pm2-monitor) pm2_monitor ;;
    backup) backup_command "$@" ;;
    restore) restore_command "$@" ;; 
    menu) main_menu ;;  
    help) smart_usage "help" "$1" ;;
    --version|-v) show_version ;;
    --help|-h) smart_usage ;;
    "") main_menu ;;    
    *) smart_usage ;;
esac