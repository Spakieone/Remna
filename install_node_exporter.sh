#!/bin/bash

# Оптимизированный установщик Node Exporter
# Исправлены проблемы с версиями, скачиванием, проверками

set -euo pipefail

# Цвета и константы
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

readonly NODE_EXPORTER_USER="node_exporter"
readonly NODE_EXPORTER_SERVICE="/etc/systemd/system/node_exporter.service"
readonly NODE_EXPORTER_BINARY="/usr/local/bin/node_exporter"
readonly GITHUB_API="https://api.github.com/repos/prometheus/node_exporter/releases/latest"
readonly DOWNLOAD_DIR="/tmp/node_exporter_install"

# Функции логирования (пишем в stderr, чтобы не мешать командным подстановкам)
log()  { echo -e "${GREEN}[✓]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1" >&2; }
err()  { echo -e "${RED}[✗]${NC} $1" >&2; }
info() { echo -e "${BLUE}[ℹ]${NC} $1" >&2; }

# Проверка прав root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        err "Требуются права root. Запустите: sudo $0"
        exit 1
    fi
}

# Определение архитектуры
detect_architecture() {
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        armv6l)
            echo "armv6"
            ;;
        i386|i686)
            echo "386"
            ;;
        *)
            err "Неподдерживаемая архитектура: $arch"
            exit 1
            ;;
    esac
}

# Получение последней версии
get_latest_version() {
    info "Получение информации о последней версии Node Exporter..."
    
    local version
    if command -v curl >/dev/null 2>&1; then
        version=$(curl -s "$GITHUB_API" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' | head -1 | tr -d '\r')
    elif command -v wget >/dev/null 2>&1; then
        version=$(wget -qO- "$GITHUB_API" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' | head -1 | tr -d '\r')
    else
        err "Не найден curl или wget для скачивания"
        exit 1
    fi
    
    if [[ -z "$version" || "$version" == "null" ]]; then
        warn "Не удалось получить последнюю версию, используем 1.8.2"
        version="1.8.2"
    fi
    
    echo "$version"
}

# Проверка существующей установки
check_existing_installation() {
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        local current_version
        current_version=$($NODE_EXPORTER_BINARY --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        
        warn "Node Exporter уже установлен и запущен (версия: $current_version)"
        
        if [[ "${FORCE_REINSTALL:-false}" != "true" ]]; then
            echo -n "Переустановить? [y/N]: "
            read -r response
            if [[ "$response" != [yY] ]]; then
                info "Установка отменена"
                exit 0
            fi
        fi
        
        info "Останавливаем существующий сервис..."
        systemctl stop node_exporter || true
        systemctl disable node_exporter || true
    fi
}

# Создание пользователя
create_user() {
    if id "$NODE_EXPORTER_USER" >/dev/null 2>&1; then
        info "Пользователь $NODE_EXPORTER_USER уже существует"
    else
        info "Создание пользователя $NODE_EXPORTER_USER..."
        useradd --system --no-create-home --shell /bin/false "$NODE_EXPORTER_USER" || {
            err "Не удалось создать пользователя $NODE_EXPORTER_USER"
            exit 1
        }
        log "Пользователь $NODE_EXPORTER_USER создан"
    fi
}

# Скачивание и установка
download_and_install() {
    local version="$1"
    local arch="$2"
    local filename="node_exporter-${version}.linux-${arch}"
    local tarball="${filename}.tar.gz"
    local download_url="https://github.com/prometheus/node_exporter/releases/download/v${version}/${tarball}"
    
    info "Скачивание Node Exporter v$version для $arch..."
    
    # Создаем временную директорию
    rm -rf "$DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR"
    cd "$DOWNLOAD_DIR"
    
    # Скачиваем с проверкой
    local download_success=false
    if command -v curl >/dev/null 2>&1; then
        if curl -L -f -o "$tarball" "$download_url" 2>/dev/null; then
            download_success=true
        fi
    fi
    
    if [[ "$download_success" == "false" ]] && command -v wget >/dev/null 2>&1; then
        if wget -q -O "$tarball" "$download_url" 2>/dev/null; then
            download_success=true
        fi
    fi
    
    if [[ "$download_success" == "false" ]]; then
        err "Не удалось скачать Node Exporter"
        err "URL: $download_url"
        exit 1
    fi
    
    # Проверяем размер файла
    local file_size
    file_size=$(stat -c%s "$tarball" 2>/dev/null || echo "0")
    if [[ "$file_size" -lt 1000000 ]]; then  # Меньше 1MB
        err "Скачанный файл слишком мал ($file_size байт), возможно поврежден"
        exit 1
    fi
    
    log "Файл скачан (размер: $file_size байт)"
    
    # Распаковываем
    info "Распаковка архива..."
    if ! tar xzf "$tarball" 2>/dev/null; then
        err "Не удалось распаковать архив"
        exit 1
    fi
    
    # Проверяем что бинарник существует
    if [[ ! -f "$filename/node_exporter" ]]; then
        err "Бинарный файл node_exporter не найден в архиве"
        exit 1
    fi
    
    # Проверяем что бинарник исполняемый
    if ! "$filename/node_exporter" --version >/dev/null 2>&1; then
        err "Скачанный бинарник не работает"
        exit 1
    fi
    
    # Устанавливаем
    info "Установка бинарного файла..."
    cp "$filename/node_exporter" "$NODE_EXPORTER_BINARY"
    chmod +x "$NODE_EXPORTER_BINARY"
    chown root:root "$NODE_EXPORTER_BINARY"
    
    log "Node Exporter установлен в $NODE_EXPORTER_BINARY"
    
    # Проверяем установку
    local installed_version
    installed_version=$($NODE_EXPORTER_BINARY --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    log "Установленная версия: $installed_version"
}

# Создание systemd сервиса
create_systemd_service() {
    info "Создание systemd сервиса..."
    
    cat > "$NODE_EXPORTER_SERVICE" << EOF
[Unit]
Description=Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$NODE_EXPORTER_USER
Group=$NODE_EXPORTER_USER
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=$NODE_EXPORTER_BINARY \\
    --web.listen-address=:9100 \\
    --path.procfs=/proc \\
    --path.rootfs=/ \\
    --path.sysfs=/sys \\
    --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc|rootfs/var/lib/docker/containers|rootfs/var/lib/docker/overlay2|rootfs/run/docker/netns|rootfs/var/lib/docker/aufs)($$|/)' \\
    --collector.filesystem.fs-types-exclude='^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$$'

# Security settings
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=strict
ProtectHostname=true
ProtectClock=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6
RestrictNamespaces=true
LockPersonality=true
RestrictRealtime=true
RestrictSUIDSGID=true
RemoveIPC=true
PrivateMounts=true

# Restart settings
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=3

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=node_exporter

[Install]
WantedBy=multi-user.target
EOF
    
    log "Systemd сервис создан"
}

# Настройка firewall
setup_firewall() {
    info "Настройка firewall для порта 9100..."
    
    # Определяем ОС
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        local os_id="$ID"
    else
        warn "Не удалось определить ОС, пропускаем настройку firewall"
        return 0
    fi
    
    case "$os_id" in
        ubuntu|debian)
            if command -v ufw >/dev/null 2>&1; then
                ufw --force enable 2>/dev/null || true
                if ufw allow 9100/tcp 2>/dev/null; then
                    log "Порт 9100 открыт в UFW"
                else
                    warn "Не удалось открыть порт 9100 в UFW"
                fi
            else
                warn "UFW не найден"
            fi
            ;;
        centos|rhel|fedora)
            if command -v firewall-cmd >/dev/null 2>&1; then
                systemctl enable firewalld 2>/dev/null || true
                systemctl start firewalld 2>/dev/null || true
                if firewall-cmd --permanent --add-port=9100/tcp 2>/dev/null && firewall-cmd --reload 2>/dev/null; then
                    log "Порт 9100 открыт в firewalld"
                else
                    warn "Не удалось открыть порт 9100 в firewalld"
                fi
            else
                warn "Firewalld не найден"
            fi
            ;;
        *)
            warn "Неизвестная ОС ($os_id), пропускаем настройку firewall"
            ;;
    esac
}

# Запуск сервиса
start_service() {
    info "Запуск Node Exporter сервиса..."
    
  systemctl daemon-reload
    
    if systemctl enable node_exporter; then
        log "Node Exporter добавлен в автозапуск"
    else
        err "Не удалось добавить Node Exporter в автозапуск"
    exit 1
fi

    if systemctl start node_exporter; then
        log "Node Exporter сервис запущен"
    else
        err "Не удалось запустить Node Exporter сервис"
        info "Проверьте логи: journalctl -u node_exporter -f"
        exit 1
    fi
    
    # Проверяем что сервис действительно работает
    sleep 3
    if systemctl is-active --quiet node_exporter; then
        log "Node Exporter сервис активен"
    else
        err "Node Exporter сервис не активен после запуска"
        info "Логи сервиса:"
        journalctl -u node_exporter --no-pager -n 10
    exit 1
fi
}

# Финальная проверка
final_check() {
    info "Выполнение финальной проверки..."
    
    # Проверяем метрики endpoint
    sleep 2
    local metrics_available=false
    
    for i in {1..5}; do
        if curl -s http://localhost:9100/metrics >/dev/null 2>&1; then
            metrics_available=true
            break
        fi
        sleep 1
    done
    
    if [[ "$metrics_available" == "true" ]]; then
        log "Endpoint метрик отвечает"
        
        # Проверяем количество метрик
        local metrics_count
        metrics_count=$(curl -s http://localhost:9100/metrics | wc -l)
        if [[ "$metrics_count" -gt 100 ]]; then
            log "Получено $metrics_count метрик"
        else
            warn "Получено только $metrics_count метрик (ожидалось больше 100)"
        fi
    else
        warn "Endpoint метрик не отвечает (возможно, сервис еще запускается)"
    fi
    
    # Показываем информацию
    echo
    info "Установка Node Exporter завершена!"
    echo -e "${BLUE}Метрики доступны по адресу: http://localhost:9100/metrics${NC}"
    echo -e "${BLUE}Проверка статуса: systemctl status node_exporter${NC}"
    echo -e "${BLUE}Просмотр логов: journalctl -u node_exporter -f${NC}"
}

# Cleanup функция
cleanup() {
    local exit_code=$?
    
    # Удаляем временную директорию
    if [[ -d "$DOWNLOAD_DIR" ]]; then
        rm -rf "$DOWNLOAD_DIR"
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        err "Установка прервана с ошибкой (код: $exit_code)"
        warn "Для очистки выполните:"
        warn "sudo systemctl stop node_exporter"
        warn "sudo systemctl disable node_exporter"
        warn "sudo rm -f $NODE_EXPORTER_BINARY $NODE_EXPORTER_SERVICE"
        warn "sudo userdel $NODE_EXPORTER_USER"
    fi
}

# Основная функция
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}              ${GREEN}Node Exporter Installer v1.2.0${NC}                 ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                     ${YELLOW}Optimized Edition${NC}                       ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    trap cleanup EXIT
    
    require_root
    
    local arch
    arch=$(detect_architecture)
    info "Определена архитектура: $arch"
    
    local version
    version=$(get_latest_version)
    info "Последняя версия: $version"
    
    check_existing_installation
    create_user
    download_and_install "$version" "$arch"
    create_systemd_service
    setup_firewall
    start_service
    final_check
    
    echo
    log "🎉 Node Exporter успешно установлен!"
}

# Запуск
main "$@"
