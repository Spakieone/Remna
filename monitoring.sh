#!/bin/bash

# Simple Monitoring menu: Prometheus + Grafana (no Docker)

set -euo pipefail

# Colors
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}Эта операция требует root (sudo).${NC}"
    exit 1
  fi
}

ensure_tools() {
  for pkg in curl wget tar; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y "$pkg" >/dev/null 2>&1 || true
    fi
  done
}

install_prometheus() {
  echo -e "${CYAN}🚀 Установка Prometheus...${NC}"
  useradd --no-create-home --system --shell /usr/sbin/nologin prometheus 2>/dev/null || true

  mkdir -p /etc/prometheus /var/lib/prometheus /opt/prometheus

  # Получаем последнюю версию
  local ver
  ver=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' || echo "v2.52.0")
  local tarname="prometheus-${ver#v}.linux-amd64.tar.gz"
  local url="https://github.com/prometheus/prometheus/releases/download/${ver}/${tarname}"

  curl -fsSL "$url" -o "/tmp/$tarname"
  tar -xzf "/tmp/$tarname" -C /tmp
  local extracted="/tmp/prometheus-${ver#v}.linux-amd64"

  # Если сервис уже существует, останавливаем его перед заменой бинарников
  if systemctl list-unit-files 2>/dev/null | grep -q '^prometheus\.service'; then
    systemctl stop prometheus 2>/dev/null || true
    # Ждём, пока процесс отпустит бинарник
    for i in $(seq 1 10); do
      if pgrep -f "/usr/local/bin/prometheus" >/dev/null 2>&1; then
        sleep 1
      else
        break
      fi
    done
  fi

  # Копируем во временные файлы и заменяем атомарно
  install -m 0755 "$extracted/prometheus" /usr/local/bin/prometheus.new
  install -m 0755 "$extracted/promtool"   /usr/local/bin/promtool.new
  mv -f /usr/local/bin/prometheus.new /usr/local/bin/prometheus
  mv -f /usr/local/bin/promtool.new   /usr/local/bin/promtool

  # Консоли отсутствуют в новых релизах: пропускаем копирование и флаги
  rm -rf /opt/prometheus/console_libraries /opt/prometheus/consoles || true
  local flags=""
  rm -rf "$extracted" "/tmp/$tarname"

  chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus /opt/prometheus
  chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool

  if [ ! -f /etc/prometheus/prometheus.yml ]; then
    cat > /etc/prometheus/prometheus.yml <<'YAML'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
YAML
    chown prometheus:prometheus /etc/prometheus/prometheus.yml
  fi

  cat > /etc/systemd/system/prometheus.service <<UNIT
[Unit]
Description=Prometheus Monitoring
After=network-online.target
Wants=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now prometheus
  echo -e "${GREEN}✅ Prometheus установлен (http://<IP>:9090)${NC}"
}

install_grafana() {
  echo -e "${CYAN}🚀 Установка Grafana...${NC}"
  useradd --no-create-home --system --shell /usr/sbin/nologin grafana 2>/dev/null || true

  mkdir -p /opt/grafana /etc/grafana /var/lib/grafana /var/log/grafana /etc/grafana/provisioning/datasources

  # Последний релиз OSS
  local ver tgz url
  ver=$(curl -s https://api.github.com/repos/grafana/grafana/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' || echo "v11.0.0")
  tgz="grafana-${ver#v}.linux-amd64.tar.gz"
  url="https://dl.grafana.com/oss/release/${tgz}"
  curl -fsSL "$url" -o "/tmp/$tgz"
  tar -xzf "/tmp/$tgz" -C /opt/grafana --strip-components=1
  rm -f "/tmp/$tgz"

  # Datasource Prometheus
  cat > /etc/grafana/provisioning/datasources/datasource.yml <<'YAML'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
YAML

  # Конфиг Grafana (минимальный)
  cat > /etc/grafana/grafana.ini <<'INI'
[server]
http_addr =
http_port = 3000

[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning

[security]
admin_user = admin
admin_password = admin
INI

  chown -R grafana:grafana /etc/grafana /var/lib/grafana /var/log/grafana /opt/grafana

  cat > /etc/systemd/system/grafana.service <<'UNIT'
[Unit]
Description=Grafana Server
After=network-online.target
Wants=network-online.target

[Service]
User=grafana
Group=grafana
Type=simple
WorkingDirectory=/opt/grafana
ExecStart=/opt/grafana/bin/grafana-server --config=/etc/grafana/grafana.ini --homepath=/opt/grafana
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now grafana
  echo -e "${GREEN}✅ Grafana установлена (http://<IP>:3000, admin/admin)${NC}"
}

install_stack() {
  require_root
  ensure_tools
  install_prometheus
  install_grafana
  echo -e "${GREEN}🎉 Мониторинг установлен!${NC}"
  read -p "Нажмите Enter для продолжения..."
}

remove_stack() {
  require_root
  echo -e "${YELLOW}Удаление Prometheus и Grafana...${NC}"
  systemctl disable --now prometheus 2>/dev/null || true
  systemctl disable --now grafana 2>/dev/null || true
  rm -f /etc/systemd/system/prometheus.service /etc/systemd/system/grafana.service
  systemctl daemon-reload

  userdel prometheus 2>/dev/null || true
  userdel grafana 2>/dev/null || true

  rm -rf /etc/prometheus /var/lib/prometheus /opt/prometheus
  rm -rf /etc/grafana /var/lib/grafana /var/log/grafana /opt/grafana
  echo -e "${GREEN}✅ Удаление завершено${NC}"
  read -p "Нажмите Enter для продолжения..."
}

install_node_exporter_menu() {
  require_root
  # Пытаемся найти локальный скрипт, иначе скачиваем из GitHub
  if [ -f "./install_node_exporter.sh" ]; then
    bash "./install_node_exporter.sh"
  else
    bash <(curl -fsSL https://raw.githubusercontent.com/Spakieone/Remna/main/install_node_exporter.sh)
  fi
}

show_menu() {
  while true; do
    clear
    echo -e "${WHITE}📈 Мониторинг (Prometheus + Grafana)${NC}"
    echo
    
    # Проверяем статус Node Exporter
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
      echo -e "${GREEN}  [✓] Node Exporter: RUNNING${NC}"
    else
      echo -e "${RED}  [✗] Node Exporter: NOT RUNNING${NC}"
    fi
    
    # Проверяем статус Prometheus
    if systemctl is-active --quiet prometheus 2>/dev/null; then
      echo -e "${GREEN}  [✓] Prometheus: RUNNING${NC}"
    else
      echo -e "${RED}  [✗] Prometheus: NOT RUNNING${NC}"
    fi
    
    # Проверяем статус Grafana
    if systemctl is-active --quiet grafana 2>/dev/null; then
      echo -e "${GREEN}  [✓] Grafana: RUNNING${NC}"
    else
      echo -e "${RED}  [✗] Grafana: NOT RUNNING${NC}"
    fi
    
    echo
    echo -e "${CYAN}1) Установить Prometheus + Grafana${NC}"
    echo -e "${CYAN}2) Установить/проверить Node Exporter${NC}"
    echo -e "${CYAN}3) Удалить мониторинг${NC}"
    echo -e "${CYAN}0) Назад${NC}"
    echo
    read -p "Выберите [0-3]: " ans
    case "$ans" in
      1) install_stack ;;
      2) install_node_exporter_menu ;;
      3) remove_stack ;;
      0) exit 0 ;;
      *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
    esac
  done
}

show_menu


