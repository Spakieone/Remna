#!/bin/bash

# install_tblocker.sh
# Автоматическая установка Tblocker и настройка Remnanode
# Обновлённая версия: исправлена обработка ошибок dpkg и установка Tblocker
# Автор: ChatGPT
# Дата: 2025-08-30

set -uo pipefail

# ===== Проверка root =====
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите скрипт от root (sudo)."
    exit 1
fi

echo "✅ Запускаем скрипт Tblocker..."

# ===== Поддержка подкоманд =====
ACTION="install"
if [ $# -gt 0 ]; then
    case "$1" in
        uninstall|remove)
            ACTION="uninstall"
            ;;
        install)
            ACTION="install"
            ;;
        status)
            ACTION="status"
            ;;
        logs)
            ACTION="logs"
            ;;
        *)
            ACTION="install"
            ;;
    esac
fi

# ===== Функция показа статуса =====
show_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 СТАТУС TBLOCKER"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Проверка установки
    if [ ! -d "/opt/tblocker" ]; then
        echo "❌ Tblocker не установлен"
        echo ""
        echo "💡 Для установки используйте: ./install-tblocker.sh install"
        echo ""
        return 0 2>/dev/null || true
    fi
    
    # Статус systemd сервиса
    if systemctl list-unit-files 2>/dev/null | grep -q '^tblocker\.service'; then
        echo "📋 Статус сервиса:"
        systemctl status tblocker --no-pager -l
        echo ""
        
        # Дополнительная информация
        if systemctl is-active --quiet tblocker 2>/dev/null; then
            echo "✅ Сервис активен и работает"
        else
            echo "❌ Сервис не активен"
        fi
        
        if systemctl is-enabled --quiet tblocker 2>/dev/null; then
            echo "✅ Сервис включен в автозагрузку"
        else
            echo "⚠️  Сервис не включен в автозагрузку"
        fi
    else
        echo "❌ Сервис tblocker не найден в systemd"
    fi
    
    echo ""
    
    # Информация о конфигурации
    CONFIG_FILE="/opt/tblocker/config.yaml"
    if [ -f "$CONFIG_FILE" ]; then
        echo "📝 Конфигурация:"
        echo "   Файл: $CONFIG_FILE"
        if grep -q "LogFile:" "$CONFIG_FILE"; then
            LOG_FILE=$(grep "LogFile:" "$CONFIG_FILE" | cut -d'"' -f2)
            echo "   Лог файл: $LOG_FILE"
            if [ -f "$LOG_FILE" ]; then
                LOG_SIZE=$(du -h "$LOG_FILE" | cut -f1)
                echo "   Размер лога: $LOG_SIZE"
            fi
        fi
        if grep -q "BlockDuration:" "$CONFIG_FILE"; then
            BLOCK_DUR=$(grep "BlockDuration:" "$CONFIG_FILE" | awk '{print $2}')
            echo "   Время блокировки: $BLOCK_DUR минут"
        fi
        if grep -q "WebhookURL:" "$CONFIG_FILE"; then
            WEBHOOK=$(grep "WebhookURL:" "$CONFIG_FILE" | cut -d'"' -f2)
            echo "   Webhook URL: $WEBHOOK"
        fi
    else
        echo "⚠️  Конфигурационный файл не найден"
    fi
    
    echo ""
    
    # Заблокированные IP
    STORAGE_DIR="/opt/tblocker"
    if [ -f "$STORAGE_DIR/blocked_ips.json" ]; then
        BLOCKED_COUNT=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$STORAGE_DIR/blocked_ips.json" 2>/dev/null | sort -u | wc -l)
        echo "🚫 Заблокированных IP: $BLOCKED_COUNT"
    fi
    
    # Проверка iptables правил
    if iptables -L TBLOCKER_BLOCKED -n 2>/dev/null | grep -q "DROP\|REJECT"; then
        IPTABLES_COUNT=$(iptables -L TBLOCKER_BLOCKED -n -v 2>/dev/null | grep -E "DROP|REJECT" | wc -l)
        echo "🔒 Правил в iptables: $IPTABLES_COUNT"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ===== Функция показа логов =====
show_logs() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 ЛОГИ TBLOCKER"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Проверка установки
    if [ ! -d "/opt/tblocker" ]; then
        echo "❌ Tblocker не установлен"
        echo ""
        echo "💡 Для установки используйте: ./install-tblocker.sh install"
        echo ""
        return 0 2>/dev/null || true
    fi
    
    # Логи systemd
    if systemctl list-unit-files 2>/dev/null | grep -q '^tblocker\.service'; then
        echo "📊 Логи systemd (последние 50 строк):"
        echo ""
        journalctl -u tblocker -n 50 --no-pager
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "💡 Для просмотра логов в реальном времени используйте:"
        echo "   journalctl -u tblocker -f"
        echo ""
    else
        echo "❌ Сервис tblocker не найден в systemd"
    fi
    
    # Логи из файла конфигурации
    CONFIG_FILE="/opt/tblocker/config.yaml"
    if [ -f "$CONFIG_FILE" ] && grep -q "LogFile:" "$CONFIG_FILE"; then
        LOG_FILE=$(grep "LogFile:" "$CONFIG_FILE" | cut -d'"' -f2)
        if [ -f "$LOG_FILE" ]; then
            echo "📄 Логи из файла $LOG_FILE (последние 30 строк):"
            echo ""
            tail -n 30 "$LOG_FILE" 2>/dev/null || echo "   Не удалось прочитать файл логов"
            echo ""
        fi
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ===== Удаление Tblocker =====
if [ "$ACTION" = "uninstall" ]; then
    echo "🗑 Удаление Tblocker..."
    if systemctl list-unit-files 2>/dev/null | grep -q '^tblocker\.service'; then
        systemctl stop tblocker 2>/dev/null || true
        systemctl disable tblocker 2>/dev/null || true
        [ -f "/etc/systemd/system/tblocker.service" ] && rm -f "/etc/systemd/system/tblocker.service"
        [ -f "/lib/systemd/system/tblocker.service" ] && rm -f "/lib/systemd/system/tblocker.service"
        systemctl daemon-reload 2>/dev/null || true
        echo "✅ Сервис tBlocker остановлен и отключён"
    else
        echo "ℹ️  Сервис tBlocker не найден"
    fi
    [ -d "/opt/tblocker" ] && rm -rf "/opt/tblocker" && echo "✅ Удалена директория /opt/tblocker"
    [ -f "/etc/logrotate.d/tblocker" ] && rm -f "/etc/logrotate.d/tblocker"
    
    # Удаляем том логов из docker-compose.yml если он был добавлен Tblocker
    if [ -f "$COMPOSE_FILE" ] && grep -q "/var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"; then
        echo "➡ Удаляем том логов из docker-compose.yml..."
        sed -i '/\/var\/log\/remnanode:\/var\/log\/remnanode/d' "$COMPOSE_FILE"
        echo "✅ Том логов удален из docker-compose.yml"
    fi
    
    echo "✅ Готово. tBlocker удалён."
    exit 0
fi

# ===== Показать статус =====
if [ "$ACTION" = "status" ]; then
    show_status
    exit 0
fi

# ===== Показать логи =====
if [ "$ACTION" = "logs" ]; then
    show_logs
    exit 0
fi

echo "➡ Режим: установка"

# ===== Исправление прерванного dpkg =====
if sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
    echo "❌ dpkg занят, завершите другие установки и попробуйте снова."
    echo "💡 Попробуйте позже или завершите другие процессы установки"
    return 1 2>/dev/null || exit 1
fi

if [ -f /var/lib/dpkg/lock ]; then
    echo "⚠ Предыдущая установка прервана. Исправляем dpkg..."
    sudo dpkg --configure -a
fi

# ===== Удаление старого Tblocker =====
if dpkg -l | grep -q tblocker; then
    echo "➡ Найден старый Tblocker, удаляем..."
    apt remove -y tblocker
fi

# ===== Обновление и установка зависимостей =====
echo "➡ Обновляем пакеты и ставим зависимости..."

# Обновляем apt с игнорированием ошибок от проблемных репозиториев
echo "➡ Обновление списка пакетов..."
apt update -y 2>&1 | grep -v -E "(403|Access Denied|Failed to fetch)" || true

# Устанавливаем зависимости
echo "➡ Установка зависимостей..."
apt install -y curl logrotate 2>&1 | grep -v -E "(403|Failed to fetch)" || true

# Пытаемся установить docker-compose-plugin если доступен
apt install -y docker-compose-plugin 2>/dev/null || echo "ℹ️  docker-compose-plugin не доступен, используем существующий Docker Compose"

# ===== Настройка docker-compose.yml =====
# Всегда используем фиксированное имя приложения
APP_NAME="remnanode"
COMPOSE_FILE="/opt/${APP_NAME}/docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "❌ Файл $COMPOSE_FILE не найден. Проверьте путь!"
    echo "💡 Убедитесь, что RemnaNode установлен"
    return 1 2>/dev/null || exit 1
fi

# Удаляем ненужный том /var/lib/toblock
if grep -q "/var/lib/toblock:/var/lib/toblock" "$COMPOSE_FILE"; then
    echo "➡ Удаляем лишний том /var/lib/toblock из docker-compose.yml..."
    sed -i '/\/var\/lib\/toblock:\/var\/lib\/toblock/d' "$COMPOSE_FILE"
fi

# ===== Функции для корректных отступов в docker-compose.yml =====
get_property_indent() {
    awk '
        BEGIN{in_remna=0}
        /^[[:space:]]*remnanode:[[:space:]]*$/ {in_remna=1; next}
        in_remna && /^[[:space:]]*[A-Za-z0-9_-]+:[[:space:]]/ {
            match($0,/^[[:space:]]*/); print substr($0,1,RLENGTH); exit
        }
    ' "$COMPOSE_FILE"
}

get_volumes_item_indent() {
    awk '
        BEGIN{in_remna=0; in_vol=0}
        /^[[:space:]]*remnanode:[[:space:]]*$/ {in_remna=1; next}
        in_remna && /^[[:space:]]*volumes:[[:space:]]*$/ {in_vol=1; next}
        in_vol && /^[[:space:]]*-[[:space:]]/ { match($0,/^[[:space:]]*/); print substr($0,1,RLENGTH); exit }
        in_vol && /^[[:space:]]*[A-Za-z0-9_-]+:[[:space:]]*$/ {exit}
    ' "$COMPOSE_FILE"
}

escape_sed() { echo "$1" | sed 's/[\\\/*.$^[]/\\&/g' ; }

# Проверяем, что volumes существует и не дублируется
if grep -c "^[[:space:]]*volumes:" "$COMPOSE_FILE" | grep -q "^1$"; then
    echo "✅ Секция volumes корректна"
elif grep -c "^[[:space:]]*volumes:" "$COMPOSE_FILE" | grep -q "^[2-9]"; then
    echo "⚠️  Обнаружено дублирование volumes, исправляем..."
    # Удаляем все дублирующиеся volumes и оставляем только первую секцию
    awk '
    BEGIN{in_remna=0; volumes_count=0; in_volumes=0}
    /^[[:space:]]*remnanode:[[:space:]]*$/ {in_remna=1; print; next}
    in_remna && /^[[:space:]]*volumes:[[:space:]]*$/ {
        volumes_count++
        if(volumes_count == 1) {
            print
            in_volumes=1
        }
        next
    }
    in_remna && in_volumes && /^[[:space:]]*-[[:space:]]/ {
        print
        next
    }
    in_remna && in_volumes && /^[[:space:]]*[a-zA-Z]/ && !/^[[:space:]]*-/ {
        in_volumes=0
        print
        next
    }
    in_remna && in_volumes && /^[[:space:]]*$/ {
        print
        next
    }
    {print}
    ' "$COMPOSE_FILE" > "$COMPOSE_FILE.tmp" && mv "$COMPOSE_FILE.tmp" "$COMPOSE_FILE"
    echo "✅ Дублирующиеся volumes исправлены"
else
    echo "ℹ️  Секция volumes не найдена"
fi

# Удаляем старый том /var/lib/remnanode:/var/lib/remnanode если он есть
if grep -q "/var/lib/remnanode:/var/lib/remnanode" "$COMPOSE_FILE"; then
    echo "➡ Удаляем старый том /var/lib/remnanode:/var/lib/remnanode..."
    sed -i '/\/var\/lib\/remnanode:\/var\/lib\/remnanode/d' "$COMPOSE_FILE"
    echo "✅ Старый том /var/lib/remnanode:/var/lib/remnanode удален"
fi

# Проверяем наличие тома логов
if grep -q "/var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"; then
    echo "✅ Том /var/log/remnanode уже присутствует в docker-compose.yml"
else
    echo "➡ Добавляем том /var/log/remnanode в docker-compose.yml..."

    prop_indent="$(get_property_indent)"
    [ -n "$prop_indent" ] || prop_indent="    "
    # элементы списка отступаются на один уровень глубже свойства
    item_indent="${prop_indent}  "

    # Если уже есть volumes: — добавляем в существующую секцию
    if grep -q "^[[:space:]]*volumes:" "$COMPOSE_FILE"; then
        detected_item_indent="$(get_volumes_item_indent)"
        [ -n "$detected_item_indent" ] && item_indent="$detected_item_indent"
        
        # Проверяем, что том логов еще не добавлен
        if ! grep -q "/var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"; then
            # Находим последний элемент в секции volumes и добавляем после него
            # Ищем все строки с volumes и берем последнюю
            last_volumes_line=$(grep -n "^[[:space:]]*volumes:" "$COMPOSE_FILE" | tail -1 | cut -d: -f1)
            if [ -n "$last_volumes_line" ]; then
                # Ищем последний элемент в этой секции volumes
                last_volume_item=$(awk -v start="$last_volumes_line" '
                    NR >= start && /^[[:space:]]*-[[:space:]]/ { last_line=NR }
                    NR >= start && /^[[:space:]]*[a-zA-Z]/ && !/^[[:space:]]*-/ { exit }
                    END { print last_line }
                ' "$COMPOSE_FILE")
                
                if [ -n "$last_volume_item" ]; then
                    sed -i "${last_volume_item}a\\${item_indent}- /var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"
                else
                    # Если нет элементов, добавляем после volumes:
                    sed -i "${last_volumes_line}a\\${item_indent}- /var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"
                fi
            else
                esc_prop="$(escape_sed "$prop_indent")"
                sed -i "/^${esc_prop}volumes:/a\\${item_indent}- /var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"
            fi
            echo "✅ Том логов добавлен в существующую секцию volumes"
        else
            echo "ℹ️  Том логов уже присутствует в volumes"
        fi
    else
        # Вставляем блок volumes после restart: always в секции remnanode
        esc_prop="$(escape_sed "$prop_indent")"
        awk -v prop="$prop_indent" -v item="$item_indent" '
            BEGIN{in_remna=0}
            /^[[:space:]]*remnanode:[[:space:]]*$/ {in_remna=1; print; next}
            in_remna && /^[[:space:]]*restart:[[:space:]]*always[[:space:]]*$/ {
                print
                print prop "volumes:"
                print item "- /var/log/remnanode:/var/log/remnanode"
                next
            }
            { print }
        ' "$COMPOSE_FILE" > "$COMPOSE_FILE.tmp" && mv "$COMPOSE_FILE.tmp" "$COMPOSE_FILE"
        echo "✅ Создана новая секция volumes с томом логов"
    fi
fi

# ===== Создание папки логов =====
mkdir -p /var/log/remnanode
chmod 755 /var/log/remnanode

# ===== Настройка logrotate =====
LOGROTATE_FILE="/etc/logrotate.d/remnanode"
if [ ! -f "$LOGROTATE_FILE" ]; then
    echo "➡ Создаём конфиг logrotate..."
    cat > "$LOGROTATE_FILE" <<EOL
/var/log/remnanode/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
EOL
    echo "✅ logrotate настроен."
else
    echo "✅ logrotate уже настроен."
fi

# ===== Установка Tblocker =====
echo "➡ Устанавливаем Tblocker..."
bash <(curl -fsSL git.new/install) <<EOF
/var/log/remnanode/access.log
1
EOF

# Проверяем, установился ли Tblocker
if [ ! -d /opt/tblocker ]; then
    echo "❌ Установка Tblocker не удалась. Проверьте вывод установки."
    echo "ℹ️  Вы можете установить Tblocker позже вручную"
    echo "💡 Попробуйте запустить установку еще раз"
    return 1 2>/dev/null || exit 1
fi

# ===== Ввод параметров =====
read -p "Введите домен бота (пример: vpn-bot.site): " BOT_DOMAIN
read -p "Введите время блокировки (в минутах): " BLOCK_DURATION

# ===== Создание конфига Tblocker =====
CONFIG_FILE="/opt/tblocker/config.yaml"
echo "➡ Создаём конфиг $CONFIG_FILE..."
cat > "$CONFIG_FILE" <<EOL
LogFile: "/var/log/remnanode/access.log"
BlockDuration: $BLOCK_DURATION
TorrentTag: "TORRENT"
BlockMode: "iptables"
BypassIPS:
  - "127.0.0.1"
  - "::1"
StorageDir: "/opt/tblocker"
UsernameRegex: "email: (\\\\S+)"
SendWebhook: true
WebhookURL: "https://$BOT_DOMAIN/tblocker/webhook"
WebhookTemplate: '{"username":"%s","ip":"%s","server":"%s","action":"%s","duration":%d,"timestamp":"%s"}'
EOL

# ===== Создание systemd сервиса =====
echo "➡ Создание systemd сервиса..."

# Проверяем, что исполняемый файл существует
if [ ! -f "/opt/tblocker/tblocker" ]; then
    echo "❌ Исполняемый файл /opt/tblocker/tblocker не найден!"
    echo "Проверьте установку Tblocker."
    echo "💡 Попробуйте переустановить Tblocker"
    return 1 2>/dev/null || exit 1
fi

# Делаем файл исполняемым
chmod +x /opt/tblocker/tblocker

cat > "/etc/systemd/system/tblocker.service" <<EOL
[Unit]
Description=Tblocker - Torrent Blocker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/tblocker
ExecStart=/opt/tblocker/tblocker
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# ===== Перезапуск Tblocker =====
echo "➡ Перезапуск Tblocker..."
systemctl daemon-reload
systemctl enable tblocker
systemctl restart tblocker

# ===== Перезапуск RemnaNode =====
echo ""
echo "➡ Перезапуск RemnaNode для применения изменений в docker-compose.yml..."

# Определяем команду docker compose
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    echo "⚠️  Команда docker compose не найдена. Перезапустите RemnaNode вручную:"
    echo "   cd /opt/remnanode && docker compose restart"
    COMPOSE_CMD=""
fi

if [ -n "$COMPOSE_CMD" ]; then
    cd /opt/remnanode
    if $COMPOSE_CMD ps -q >/dev/null 2>&1; then
        echo "➡ Перезапускаем RemnaNode..."
        $COMPOSE_CMD restart
        echo "✅ RemnaNode перезапущен"
    else
        echo "ℹ️  RemnaNode не запущен, пропускаем перезапуск"
    fi
fi

echo ""
echo "✅ Установка завершена!"
echo ""
echo "📊 Статус tBlocker:"
systemctl status tblocker --no-pager

echo ""
echo "📝 Полезные команды:"
echo "   systemctl status tblocker   - Статус сервиса"
echo "   systemctl restart tblocker  - Перезапуск"
echo "   journalctl -u tblocker -f   - Просмотр логов"
