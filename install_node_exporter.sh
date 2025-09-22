#!/bin/bash

# Node Exporter Installation Script
# For Remnawave by Spakie

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
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

get_installed_version() {
  if command -v node_exporter >/dev/null 2>&1; then
    local line
    line=$(node_exporter --version 2>/dev/null | head -n1)
    # Ищем первый токен вида X.Y.Z
    echo "$line" | awk '{for(i=1;i<=NF;i++){if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/){print $i; exit}}}'
  fi
}

is_unit_present() {
  systemctl list-unit-files 2>/dev/null | grep -q '^node_exporter\.service'
}

show_status_header() {
  local state="Not installed"
  local color='\033[38;5;244m'
  if is_unit_present || command -v node_exporter >/dev/null 2>&1; then
    state="STOPPED"
    color="$RED"
  fi
  if systemctl is-active --quiet node_exporter 2>/dev/null; then
    state="RUNNING"
    color="$GREEN"
  fi
  local ip=$(get_node_ip)
  local ver=$(get_installed_version)
  [ -n "$ver" ] && ver="v$ver" || ver="—"
  echo -e "${BLUE}================ Node Exporter =================${NC}"
  echo -e "Статус: ${color}${state}${NC}  |  Версия: ${WHITE}${ver}${NC}  |  Порт: 9100"
  echo -e "URL:    http://${ip:-127.0.0.1}:9100/metrics"
  if ss -tln 2>/dev/null | grep -q ":9100 "; then
    echo -e "Прослушивание порта: ${GREEN}✅ да${NC}"
  else
    echo -e "Прослушивание порта: ${RED}🔴 нет${NC}"
  fi
  echo -e "${BLUE}===============================================${NC}"
}

ensure_unit_with_envfile() {
  # Создаём/обновляем unit с поддержкой EnvironmentFile
  local unit="/etc/systemd/system/node_exporter.service"
  if [ -f "$unit" ]; then
    # Добавляем EnvironmentFile, если отсутствует
    if ! grep -q '^EnvironmentFile=' "$unit"; then
      sed -i '/^\[Service\]/a EnvironmentFile=/etc/default/node_exporter' "$unit"
    fi
    # Заменяем ExecStart на вариант с $OPTIONS
    if grep -q '^ExecStart=' "$unit"; then
      sed -i 's|^ExecStart=.*|ExecStart=/usr/local/bin/node_exporter $OPTIONS|g' "$unit"
    fi
  else
    cat > "$unit" << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
EnvironmentFile=/etc/default/node_exporter
ExecStart=/usr/local/bin/node_exporter $OPTIONS
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  fi
  mkdir -p /etc/default
  [ -f /etc/default/node_exporter ] || echo 'OPTIONS=""' > /etc/default/node_exporter
}

cmd_change_port() {
  read -p "Введите порт для Node Exporter (текущий 9100): " NEW_PORT
  NEW_PORT=${NEW_PORT:-9100}
  if ! [[ "$NEW_PORT" =~ ^[0-9]{2,5}$ ]]; then
    error "Некорректный порт"; return
  fi
  ensure_unit_with_envfile
  sed -i 's/^OPTIONS=.*/OPTIONS="--web.listen-address=:'"$NEW_PORT"'"/' /etc/default/node_exporter
  systemctl daemon-reload
  systemctl restart node_exporter || systemctl start node_exporter
  success "Порт обновлён на $NEW_PORT"
}

cmd_configure_collectors() {
  ensure_unit_with_envfile
  echo "Введите дополнительные опции (например: --collector.textfile.directory=/var/lib/node_exporter/textfile_collector)"
  echo "Оставьте пустым, чтобы очистить. Текущие:"
  grep -E '^OPTIONS=' /etc/default/node_exporter || true
  read -p "OPTIONS= " EXTRA
  echo "OPTIONS=\"$EXTRA\"" > /etc/default/node_exporter
  systemctl daemon-reload
  systemctl restart node_exporter || systemctl start node_exporter
  success "Опции сохранены"
}

cmd_uninstall() {
  systemctl stop node_exporter 2>/dev/null || true
  systemctl disable node_exporter 2>/dev/null || true
  rm -f /etc/systemd/system/node_exporter.service
  systemctl daemon-reload 2>/dev/null || true
  rm -f /usr/local/bin/node_exporter
  userdel node_exporter 2>/dev/null || true
  rm -f /etc/default/node_exporter
  success "Node Exporter удалён"
}

cmd_status() {
  show_status_header
  systemctl status node_exporter --no-pager 2>/dev/null || true
}

cmd_menu() {
  while true; do
    clear
    show_status_header
    echo -e "${WHITE}\n🛠️  Установка:${NC}"
    echo "  1) Установить/обновить (последняя версия)"
    echo "  2) Установить конкретную версию…"
    echo "  3) Удалить Node Exporter"
    echo -e "\n${WHITE}▶️  Сервис:${NC}"
    echo "  4) Запустить"
    echo "  5) Остановить"
    echo "  6) Перезапустить"
    echo "  7) Включить автозапуск (enable)"
    echo "  8) Отключить автозапуск (disable)"
    echo -e "\n${WHITE}📊 Статус и диагностика:${NC}"
    echo "  9) Показать статус"
    echo "  10) Показать логи"
    echo "  11) Информация (версия, путь, владелец)"
    echo "  12) Проверить прослушивание порта 9100"
    echo "  13) Показать URL метрик"
    echo -e "\n${WHITE}⚙️  Настройки:${NC}"
    echo "  14) Изменить порт…"
    echo "  15) Открыть порт в firewall"
    echo "  16) Закрыть порт в firewall"
    echo "  17) Настроить collectors…"
    echo "  0) Выход"
    echo -n "Выбор: "
    read choice
    case "$choice" in
      1) exec "$0" install ;; 
      2) read -p "Введите версию (например v1.9.1): " VER; [ -n "$VER" ] && exec "$0" install-version "$VER" || true ;;
      3) cmd_uninstall; echo; read -p "Нажмите Enter..." _ ;;
      4) systemctl start node_exporter ;;
      5) systemctl stop node_exporter ;;
      6) systemctl restart node_exporter ;;
      7) systemctl enable node_exporter ;;
      8) systemctl disable node_exporter ;;
      9) cmd_status; echo; read -p "Нажмите Enter..." _ ;;
      10) journalctl -u node_exporter -n 200 --no-pager | sed -e 's/^/  /'; echo; read -p "Нажмите Enter..." _ ;;
      11) which node_exporter 2>/dev/null || echo "/usr/local/bin/node_exporter"; ls -l /usr/local/bin/node_exporter 2>/dev/null || true; echo "Версия: $(get_installed_version || echo '-')"; echo; read -p "Нажмите Enter..." _ ;;
      12) if ss -tln 2>/dev/null | grep -q ":9100 "; then echo "Порт 9100 слушается"; else echo "Порт 9100 не слушается"; fi; echo; read -p "Нажмите Enter..." _ ;;
      13) echo "URL: http://$(get_node_ip):9100/metrics"; echo; read -p "Нажмите Enter..." _ ;;
      14) cmd_change_port ;;
      15) if command -v ufw >/dev/null 2>&1; then ufw allow 9100/tcp || true; elif command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --add-port=9100/tcp --permanent && firewall-cmd --reload; else echo "Нет поддерживаемого firewall (ufw/firewalld)"; fi ;;
      16) if command -v ufw >/dev/null 2>&1; then ufw deny 9100/tcp || ufw delete allow 9100/tcp || true; elif command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --remove-port=9100/tcp --permanent && firewall-cmd --reload; else echo "Нет поддерживаемого firewall (ufw/firewalld)"; fi ;;
      17) cmd_configure_collectors ;;
      0) clear; return ;;
      *) : ;;
    esac
  done
}

# Обработка команд до установки
install_version_by_tag() {
  local TAG="$1"  # формата v1.9.1
  [ -n "$TAG" ] || { error "Не указана версия"; return 1; }
  log "Установка Node Exporter версии $TAG..."
  # Определяем архитектуру
  ARCH_SUFFIX=""
  case "$(uname -m)" in
    x86_64|amd64) ARCH_SUFFIX="linux-amd64" ;;
    aarch64|arm64) ARCH_SUFFIX="linux-arm64" ;;
    i386|i686) ARCH_SUFFIX="linux-386" ;;
    armv7l) ARCH_SUFFIX="linux-armv7" ;;
    *) ARCH_SUFFIX="linux-amd64" ;;
  esac
  cd /tmp
  rm -f "node_exporter-${TAG#v}."*.tar.gz 2>/dev/null || true
  wget -q "https://github.com/prometheus/node_exporter/releases/download/${TAG}/node_exporter-${TAG#v}.${ARCH_SUFFIX}.tar.gz" || { error "Не удалось скачать релиз ${TAG}"; return 1; }
  tar xzf "node_exporter-${TAG#v}.${ARCH_SUFFIX}.tar.gz"
  SRC_DIR="node_exporter-${TAG#v}.${ARCH_SUFFIX}"
  TARGET_BIN="/usr/local/bin/node_exporter"
  NEW_BIN="${TARGET_BIN}.new"
  cp "${SRC_DIR}/node_exporter" "${NEW_BIN}"
  chmod 0755 "${NEW_BIN}"
  SERVICE_WAS_RUNNING=false
  if systemctl is-active --quiet node_exporter 2>/dev/null; then SERVICE_WAS_RUNNING=true; fi
  if mv -f "${NEW_BIN}" "${TARGET_BIN}" 2>/dev/null; then :; else systemctl stop node_exporter 2>/dev/null || true; mv -f "${NEW_BIN}" "${TARGET_BIN}"; fi
  ensure_unit_with_envfile
  useradd -r node_exporter 2>/dev/null || true
  chown root:root /usr/local/bin/node_exporter 2>/dev/null || true
  systemctl daemon-reload
  systemctl enable node_exporter 2>/dev/null || true
  if [ "$SERVICE_WAS_RUNNING" = true ]; then systemctl restart node_exporter || systemctl start node_exporter; else systemctl start node_exporter; fi
  rm -rf /tmp/node_exporter-*
  success "Node Exporter ${TAG} установлен"
}

case "$1" in
  status) cmd_status; exit 0 ;;
  start) systemctl start node_exporter; cmd_status; exit 0 ;;
  stop) systemctl stop node_exporter; cmd_status; exit 0 ;;
  restart) systemctl restart node_exporter; cmd_status; exit 0 ;;
  logs) journalctl -u node_exporter -n 200 --no-pager; exit 0 ;;
  uninstall) cmd_uninstall; exit 0 ;;
  port) cmd_change_port; exit 0 ;;
  collectors) cmd_configure_collectors; exit 0 ;;
  install-version) shift; install_version_by_tag "$1"; exit 0 ;;
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

# Download and install (latest)
cd /tmp
# Чистим возможные предыдущие архивы той же версии, чтобы избежать суффикса .2
rm -f "node_exporter-${LATEST_VERSION#v}."*.tar.gz 2>/dev/null || true
wget "https://github.com/prometheus/node_exporter/releases/download/${LATEST_VERSION}/node_exporter-${LATEST_VERSION#v}.${ARCH_SUFFIX}.tar.gz"

tar xzf "node_exporter-${LATEST_VERSION#v}.${ARCH_SUFFIX}.tar.gz"

# Безопасная замена бинарника (обходит ошибку "Text file busy")
SRC_DIR="node_exporter-${LATEST_VERSION#v}.${ARCH_SUFFIX}"
TARGET_BIN="/usr/local/bin/node_exporter"
NEW_BIN="${TARGET_BIN}.new"
cp "${SRC_DIR}/node_exporter" "${NEW_BIN}"
chmod 0755 "${NEW_BIN}"

# Если сервис запущен, пометим для перезапуска после замены
SERVICE_WAS_RUNNING=false
if systemctl is-active --quiet node_exporter 2>/dev/null; then
  SERVICE_WAS_RUNNING=true
fi

# Пытаемся атомарно подменить бинарь
if mv -f "${NEW_BIN}" "${TARGET_BIN}" 2>/dev/null; then
  :
else
  # Если не удалось (редко), останавливаем и повторяем
  systemctl stop node_exporter 2>/dev/null || true
  mv -f "${NEW_BIN}" "${TARGET_BIN}"
fi

# Ensure systemd unit with EnvironmentFile
ensure_unit_with_envfile

# Create user
useradd -r node_exporter 2>/dev/null || true
chown root:root /usr/local/bin/node_exporter 2>/dev/null || true

# Enable and start service
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Перезапускаем если ранее был запущен и был апдейт
if [ "$SERVICE_WAS_RUNNING" = true ]; then
  systemctl restart node_exporter || systemctl start node_exporter
fi

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