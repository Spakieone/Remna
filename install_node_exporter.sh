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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "Этот скрипт должен быть запущен с правами root"
    exit 1
fi

log "Установка Node Exporter..."

# Get latest version
LATEST_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    error "Не удалось получить версию Node Exporter"
    exit 1
fi

log "Последняя версия: $LATEST_VERSION"

# Download and install
cd /tmp
wget "https://github.com/prometheus/node_exporter/releases/download/${LATEST_VERSION}/node_exporter-${LATEST_VERSION#v}.linux-amd64.tar.gz"

tar xzf "node_exporter-${LATEST_VERSION#v}.linux-amd64.tar.gz"
cp "node_exporter-${LATEST_VERSION#v}.linux-amd64/node_exporter" /usr/local/bin/
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