#!/bin/bash

# Простой установщик Node Exporter

set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              ${GREEN}Node Exporter Installer v2.0${NC}                  ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Требуются права root. Запустите: sudo $0${NC}"
   exit 1
fi

# Определяем последнюю версию
echo -e "${YELLOW}[1/8]${NC} Получение последней версии..."
VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' || echo "1.8.2")
echo -e "${GREEN}✓${NC} Версия: $VERSION"

# Скачиваем
echo -e "${YELLOW}[2/8]${NC} Скачивание Node Exporter v$VERSION..."
cd /tmp
wget -q --show-progress "https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.linux-amd64.tar.gz"
echo -e "${GREEN}✓${NC} Скачано"

# Распаковываем
echo -e "${YELLOW}[3/8]${NC} Распаковка архива..."
tar xf "node_exporter-${VERSION}.linux-amd64.tar.gz"
echo -e "${GREEN}✓${NC} Распаковано"

# Удаляем архив
echo -e "${YELLOW}[4/8]${NC} Очистка..."
rm -f "node_exporter-${VERSION}.linux-amd64.tar.gz"

# Перемещаем папку
mv "node_exporter-${VERSION}.linux-amd64" node_exporter

# Делаем исполняемым
chmod +x node_exporter/node_exporter

# Останавливаем старый сервис если есть
systemctl stop exporterd.service 2>/dev/null || true
systemctl stop node_exporter.service 2>/dev/null || true

# Перемещаем бинарник
echo -e "${YELLOW}[5/8]${NC} Установка бинарника..."
mv -f node_exporter/node_exporter /usr/bin/
echo -e "${GREEN}✓${NC} Установлен в /usr/bin/node_exporter"

# Удаляем временную папку
rm -rf node_exporter/

# Создаём сервис
echo -e "${YELLOW}[6/8]${NC} Создание systemd сервиса..."
cat > /etc/systemd/system/exporterd.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN}✓${NC} Сервис создан"

# Запускаем
echo -e "${YELLOW}[7/8]${NC} Запуск сервиса..."
systemctl daemon-reload
systemctl enable exporterd.service
systemctl start exporterd.service
echo -e "${GREEN}✓${NC} Сервис запущен"

# Проверка
echo -e "${YELLOW}[8/8]${NC} Проверка статуса..."
sleep 2

echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║             ✓ Node Exporter успешно установлен               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

# Показываем статус
systemctl status exporterd.service --no-pager -l || true

echo
echo -e "${BLUE}Метрики: http://localhost:9100/metrics${NC}"
echo -e "${BLUE}Статус:  systemctl status exporterd.service${NC}"
echo -e "${BLUE}Логи:    journalctl -u exporterd.service -f${NC}"
echo

read -p "Нажмите Enter для продолжения..."
