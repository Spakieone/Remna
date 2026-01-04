#!/bin/bash

# Скрипт установки/удаления Remnawave Agent

AGENT_DIR="/root/remnawave-agent"
AGENT_PORT="${AGENT_PORT:-9111}"
SERVICE_NAME="remnawave-agent"

install_agent() {
    echo "Установка Remnawave Agent..."
    
    # Создаем директорию если не существует
    mkdir -p "$AGENT_DIR"
    
    # Переходим в директорию
    cd "$AGENT_DIR" || exit 1
    
    # Скачиваем файлы агента с GitHub
    echo "Скачивание файлов агента с GitHub..."
    GITHUB_REPO="https://raw.githubusercontent.com/Spakieone/Remna/main/remnawave-agent"
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${GITHUB_REPO}/agent.py" -o "agent.py" || {
            echo "Ошибка: Не удалось скачать agent.py"
            exit 1
        }
        curl -fsSL "${GITHUB_REPO}/requirements.txt" -o "requirements.txt" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
        wget -q "${GITHUB_REPO}/agent.py" -O "agent.py" || {
            echo "Ошибка: Не удалось скачать agent.py"
            exit 1
        }
        wget -q "${GITHUB_REPO}/requirements.txt" -O "requirements.txt" 2>/dev/null || true
    else
        echo "Ошибка: Не найден curl или wget"
        exit 1
    fi
    
    echo "✓ Файлы агента скачаны"
    
    # Устанавливаем зависимости
    echo "Установка зависимостей..."
    # Определяем команду для pip
    if command -v pip3 >/dev/null 2>&1; then
        PIP_CMD="pip3"
    elif command -v pip >/dev/null 2>&1; then
        PIP_CMD="pip"
    elif python3 -m pip --version >/dev/null 2>&1; then
        PIP_CMD="python3 -m pip"
    else
        echo "pip не найден, устанавливаем..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y python3-pip >/dev/null 2>&1 || {
                echo "Ошибка: Не удалось установить python3-pip"
                exit 1
            }
            PIP_CMD="pip3"
        else
            echo "Ошибка: pip не найден и apt-get недоступен"
            exit 1
        fi
    fi
    
    if [ -f "$AGENT_DIR/requirements.txt" ]; then
        $PIP_CMD install -q --break-system-packages -r "$AGENT_DIR/requirements.txt" 2>&1 | grep -v "already satisfied" || true
    else
        $PIP_CMD install -q --break-system-packages fastapi uvicorn pydantic python-dotenv 2>&1 | grep -v "already satisfied" || true
    fi
    
    # Запрашиваем токен у пользователя
    echo ""
    echo "Введите токен для агента (или нажмите Enter для автоматической генерации):"
    read -r user_token
    
    # Создаем .env файл
    echo "Создание .env файла..."
    if [ -z "$user_token" ]; then
        # Генерируем токен автоматически
        AGENT_TOKEN=$(openssl rand -hex 32)
        echo "✓ Токен сгенерирован автоматически"
    else
        # Используем токен пользователя
        AGENT_TOKEN="$user_token"
        echo "✓ Токен установлен"
    fi
    
    cat > "$AGENT_DIR/.env" << EOF
AGENT_TOKEN=$AGENT_TOKEN
AGENT_PORT=$AGENT_PORT
EOF
    
    # Создаем systemd service
    echo "Создание systemd service..."
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Remnawave Agent API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$AGENT_DIR
EnvironmentFile=$AGENT_DIR/.env
ExecStart=/usr/bin/python3 $AGENT_DIR/agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Перезагружаем systemd
    systemctl daemon-reload
    
    echo "✓ Remnawave Agent установлен"
    echo ""
    echo "Для запуска выполните:"
    echo "  systemctl start $SERVICE_NAME"
    echo "  systemctl enable $SERVICE_NAME"
    echo ""
    echo "Токен: $AGENT_TOKEN"
    echo "Токен также сохранен в: $AGENT_DIR/.env"
}

remove_agent() {
    echo "Удаление Remnawave Agent..."
    
    # Останавливаем и отключаем сервис
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "Остановка сервиса..."
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "Отключение автозапуска..."
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    fi
    
    # Удаляем systemd service
    if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        echo "Удаление systemd service..."
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    fi
    
    # Перезагружаем systemd
    systemctl daemon-reload
    
    # Удаляем директорию агента
    if [ -d "$AGENT_DIR" ]; then
        echo "Удаление директории агента..."
        rm -rf "$AGENT_DIR"
    fi
    
    echo "✓ Remnawave Agent удален"
}

# Проверяем аргумент
case "${1:-}" in
    install)
        install_agent
        ;;
    remove|uninstall|delete)
        remove_agent
        ;;
    *)
        echo "Использование: $0 {install|remove}"
        echo ""
        echo "  install  - Установить Remnawave Agent"
        echo "  remove   - Удалить Remnawave Agent"
        exit 1
        ;;
esac

