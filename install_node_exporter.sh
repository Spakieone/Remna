#!/bin/bash

# Node Exporter Installation Script
# For Remnawave by Spakie

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# ===== Helpers =====
get_node_ip() {
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  if [ -z "$ip" ]; then
    ip=$(curl -s -4 ifconfig.me 2>/dev/null || true)
  fi
  echo "$ip"
}

show_status_header() {
  local state="STOPPED"
  local color="$RED"
  if systemctl is-active --quiet node_exporter 2>/dev/null; then
    state="RUNNING"
    color="$GREEN"
  fi
  local ip=$(get_node_ip)
  echo -e "${BLUE}================ Node Exporter =================${NC}"
  echo -e "Статус: ${color}${state}${NC}  |  Порт: 9100  |  URL: http://${ip:-127.0.0.1}:9100/metrics"
  if ss -tln 2>/dev/null | grep -q ":9100 "; then
    echo -e "Прослушивание порта: ${GREEN}OK${NC}"
  else
    echo -e "Прослушивание порта: ${YELLOW}нет\(возможно сервис выключен\)${NC}"
  fi
  echo -e "${BLUE}===============================================${NC}"
}

cmd_status() {
  show_status_header
  systemctl status node_exporter --no-pager 2>/dev/null || true
}

cmd_menu() {
  while true; do
    clear
    show_status_header
    echo -e "${WHITE:-}\nДоступные действия:${NC}"
    echo "  1) Запустить"
    echo "  2) Остановить"
    echo "  3) Перезапустить"
    echo "  4) Статус"
    echo "  5) Логи"
    echo "  0) Выход"
    echo -n "Выбор: "
    read choice
    case "$choice" in
      1) systemctl start node_exporter ;; 
      2) systemctl stop node_exporter ;; 
      3) systemctl restart node_exporter ;; 
      4) cmd_status; echo; read -p "Нажмите Enter..." _ ;; 
      5) journalctl -u node_exporter -n 200 --no-pager | sed -e 's/^/  /'; echo; read -p "Нажмите Enter..." _ ;;
      0) clear; return ;;
      *) : ;;
    esac
  done
}

# Обработка команд до установки
case "$1" in
  status) cmd_status; exit 0 ;;
  start) systemctl start node_exporter; cmd_status; exit 0 ;;
  stop) systemctl stop node_exporter; cmd_status; exit 0 ;;
  restart) systemctl restart node_exporter; cmd_status; exit 0 ;;
  logs) journalctl -u node_exporter -n 200 --no-pager; exit 0 ;;
  menu) cmd_menu; exit 0 ;;
  ""|install) : ;; # продолжим установку ниже
  *) echo "Неизвестная команда: $1"; echo "Доступно: install|status|start|stop|restart|logs|menu"; exit 1 ;;
esac

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "Этот скрипт должен быть запущен с правами root"
    exit 1
fi

log "Установка Node Exporter..."

# Определяем архитектуру и подбираем архив
ARCH_SUFFIX=""
case "$(uname -m)" in
  x86_64|amd64)
    ARCH_SUFFIX="linux-amd64"
    ;;
  aarch64|arm64)
    ARCH_SUFFIX="linux-arm64"
    ;;
  i386|i686)
    ARCH_SUFFIX="linux-386"
    ;;
  armv7l)
    ARCH_SUFFIX="linux-armv7"
    ;;
  *)
    warning "Неподдерживаемая архитектура: $(uname -m). Пытаюсь использовать linux-amd64 по умолчанию."
    ARCH_SUFFIX="linux-amd64"
    ;;
esac

# Проверяем зависимости
need_pkg=false
command -v curl >/dev/null 2>&1 || need_pkg=true
command -v wget >/dev/null 2>&1 || need_pkg=true
if $need_pkg; then
  warning "Не найдены зависимости (curl/wget). Пытаюсь установить..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq || true
    apt-get install -y -qq curl wget || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q curl wget || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q curl wget || true
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install -y curl wget || true
  fi
fi

# Get latest version
LATEST_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    error "Не удалось получить версию Node Exporter"
    exit 1
fi

log "Последняя версия: $LATEST_VERSION"

# Проверка systemd
if ! pidof systemd >/dev/null 2>&1 && [ ! -d /run/systemd/system ]; then
  warning "Выглядит, что systemd недоступен. Юнит будет создан, но автозапуск может не сработать."
fi

# Download and install
cd /tmp
wget "https://github.com/prometheus/node_exporter/releases/download/${LATEST_VERSION}/node_exporter-${LATEST_VERSION#v}.${ARCH_SUFFIX}.tar.gz"

tar xzf "node_exporter-${LATEST_VERSION#v}.${ARCH_SUFFIX}.tar.gz"
cp "node_exporter-${LATEST_VERSION#v}.${ARCH_SUFFIX}/node_exporter" /usr/local/bin/
chmod +x /usr/local/bin/node_exporter

# Create systemd service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Create user
useradd -r node_exporter 2>/dev/null || true
chown root:root /usr/local/bin/node_exporter 2>/dev/null || true

# Enable and start service
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Cleanup
rm -rf /tmp/node_exporter-*

success "Node Exporter установлен и запущен!"
log "Порт: 9100"
log "URL: http://$(curl -s ifconfig.me):9100/metrics"

# Check status
if systemctl is-active --quiet node_exporter; then
    success "Node Exporter работает"
else
    error "Node Exporter не запустился"
    systemctl status node_exporter
fi