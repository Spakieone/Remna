#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   Добро пожаловать в установщик бэкапа Remnawave${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "${BLUE}Этот скрипт создаст файл ${YELLOW}backup.sh${BLUE} с вашими настройками.${NC}"
echo

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    echo -ne "${prompt} [${default}]: "
    read input
    eval "$var_name=\"${input:-$default}\""
}

echo -e "${YELLOW}📍 Укажите путь к docker-compose.yml для Remnawave:${NC}"
echo -e "${BLUE}  1) /root/remnawave${NC}"
echo -e "${BLUE}  2) /opt/remnawave${NC}"
echo -e "${BLUE}  3) Ввести вручную${NC}"
echo -e "${GREEN}Примечание:${NC} Информация из .env и других файлов будет прочитана из этого пути."
echo -ne "Выберите опцию (1-3) [2]: "
read choice
choice=${choice:-2}

case $choice in
    1) COMPOSE_PATH="/root/remnawave" ;;
    2) COMPOSE_PATH="/opt/remnawave" ;;
    3) prompt_input "${YELLOW}Введите путь вручную${NC}" COMPOSE_PATH "" ;;
    *) COMPOSE_PATH="/opt/remnawave" ;;
esac

if [ ! -f "$COMPOSE_PATH/docker-compose.yml" ]; then
    echo -e "${RED}✖ Ошибка: docker-compose.yml не найден в $COMPOSE_PATH${NC}"
    exit 1
fi

echo -e "${YELLOW}📁 Хотите ли вы создать бэкап всей папки ($COMPOSE_PATH)?${NC}"
echo -e "${BLUE}  1) Да, бэкап всех файлов и подпапок${NC}"
echo -e "${BLUE}  2) Нет, бэкап только определенных файлов (docker-compose.yml, .env, app-config.json)${NC}"
echo -ne "Выберите опцию (1-2) [2]: "
read backup_choice
backup_choice=${backup_choice:-2}

case $backup_choice in
    1) BACKUP_ENTIRE_FOLDER="true" ;;
    2) BACKUP_ENTIRE_FOLDER="false" ;;
    *) BACKUP_ENTIRE_FOLDER="false" ;;
esac

read_env_var() {
    local var_name="$1"
    local file="$2"
    local value
    # Читаем значение и обрабатываем случаи с пробелами и кавычками
    value=$(grep "^$var_name=" "$file" | cut -d '=' -f 2- | head -n 1)
    # Убираем возможные комментарии в конце строки
    value=$(echo "$value" | sed 's/[[:space:]]*#.*$//')
    echo "$value"
}

if [ -f "$COMPOSE_PATH/.env" ]; then
    echo -e "${GREEN}✔ Найден файл .env в $COMPOSE_PATH. Использую для подключения к БД.${NC}"
    USE_ENV=true
    POSTGRES_USER=$(read_env_var "POSTGRES_USER" "$COMPOSE_PATH/.env")
    POSTGRES_PASSWORD=$(read_env_var "POSTGRES_PASSWORD" "$COMPOSE_PATH/.env")
    POSTGRES_DB=$(read_env_var "POSTGRES_DB" "$COMPOSE_PATH/.env")
    POSTGRES_USER=$(echo "$POSTGRES_USER" | sed 's/^"//;s/"$//')
    POSTGRES_PASSWORD=$(echo "$POSTGRES_PASSWORD" | sed 's/^"//;s/"$//')
    POSTGRES_DB=$(echo "$POSTGRES_DB" | sed 's/^"//;s/"$//')
    
    # Проверяем что все необходимые переменные заданы
    if [ -z "$POSTGRES_USER" ]; then
        echo -e "${RED}✖ Ошибка: POSTGRES_USER не найден или пуст в .env!${NC}"
        exit 1
    fi
    if [ -z "$POSTGRES_DB" ]; then
        echo -e "${RED}✖ Ошибка: POSTGRES_DB не найден или пуст в .env!${NC}"
        exit 1
    fi
    if [ -z "$POSTGRES_PASSWORD" ]; then
        echo -e "${RED}✖ Ошибка: POSTGRES_PASSWORD не найден или пуст в .env!${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Использую настройки БД: Пользователь=$POSTGRES_USER, База=$POSTGRES_DB${NC}"
else
    echo -e "${YELLOW}⚠ Файл .env не найден по пути $COMPOSE_PATH.${NC}"
    echo -e "${BLUE}Вам нужно ввести параметры подключения к БД вручную.${NC}"
    USE_ENV=false
    prompt_input "${YELLOW}Введите POSTGRES_USER${NC}" POSTGRES_USER "postgres"
    prompt_input "${YELLOW}Введите POSTGRES_PASSWORD${NC}" POSTGRES_PASSWORD ""
    prompt_input "${YELLOW}Введите POSTGRES_DB${NC}" POSTGRES_DB "postgres"
fi

DB_CONTAINER=$(docker ps --filter "name=remnawave-db" --format "{{.Names}}")
if [ -z "$DB_CONTAINER" ]; then
    echo -e "${RED}✖ Ошибка: Контейнер БД 'remnawave-db' не найден!${NC}"
    echo -e "${BLUE}Укажите корректное имя контейнера базы данных:${NC}"
    prompt_input "${YELLOW}Введите имя контейнера БД${NC}" DB_CONTAINER "remnawave-db"
fi

echo -e "${YELLOW}📡 Настройки Telegram:${NC}"
prompt_input "${BLUE}Введите токен бота Telegram (от @BotFather)${NC}" TELEGRAM_BOT_TOKEN ""
prompt_input "${BLUE}Введите ID чата/канала (например, -1001234567890)${NC}" TELEGRAM_CHAT_ID ""
prompt_input "${BLUE}Введите ID темы (опционально, Enter чтобы пропустить)${NC}" TELEGRAM_TOPIC_ID ""

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo -e "${RED}✖ Ошибка: Нужны токен бота и ID чата Telegram!${NC}"
    exit 1
fi

BACKUP_SCRIPT="$COMPOSE_PATH/backup.sh"
cat << EOF > "$BACKUP_SCRIPT"
#!/bin/bash
cd "$COMPOSE_PATH" || { echo "Ошибка: Не удалось перейти в $COMPOSE_PATH"; exit 1; }
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
TELEGRAM_TOPIC_ID="$TELEGRAM_TOPIC_ID"
BACKUP_DIR="/tmp/backup_\$(date +%Y%m%d_%H%M%S)"
BACKUP_DATE="\$(date '+%Y-%m-%d %H:%M:%S UTC')"
ARCHIVE_NAME="\$BACKUP_DIR.tar.gz"
MAX_SIZE_MB=49
DB_CONTAINER="$DB_CONTAINER"
POSTGRES_USER="$POSTGRES_USER"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
POSTGRES_DB="$POSTGRES_DB"
mkdir -p "\$BACKUP_DIR"
export PGPASSWORD="\$POSTGRES_PASSWORD"
docker exec "\$DB_CONTAINER" pg_dump -U "\$POSTGRES_USER" -d "\$POSTGRES_DB" > "\$BACKUP_DIR/db_backup.sql"
if [ \$? -ne 0 ]; then
    echo "Ошибка: Не удалось создать бэкап базы данных"
    unset PGPASSWORD
    exit 1
fi
unset PGPASSWORD
EOF

if [ "$BACKUP_ENTIRE_FOLDER" = "true" ]; then
    cat << EOF >> "$BACKUP_SCRIPT"
TEMP_ARCHIVE_DIR="/tmp/archive_\$(date +%Y%m%d_%H%M%S)"
mkdir -p "\$TEMP_ARCHIVE_DIR"
cp -r "$COMPOSE_PATH/." "\$TEMP_ARCHIVE_DIR/"
mv "\$BACKUP_DIR/db_backup.sql" "\$TEMP_ARCHIVE_DIR/db_backup.sql"
tar -czvf "\$ARCHIVE_NAME" -C "\$TEMP_ARCHIVE_DIR" .
if [ \$? -ne 0 ]; then
    echo "Ошибка: Не удалось создать архив"
    rm -rf "\$TEMP_ARCHIVE_DIR"
    exit 1
fi
rm -rf "\$TEMP_ARCHIVE_DIR"
CONTENTS="📁 Entire folder ($COMPOSE_PATH)
📋 db_backup.sql"
EOF
else
    cat << 'EOF' >> "$BACKUP_SCRIPT"
cp docker-compose.yml "$BACKUP_DIR/" || { echo "Error: Failed to copy docker-compose.yml"; exit 1; }
[ -f .env ] && cp .env "$BACKUP_DIR/" || echo "File .env not found, skipping"
[ -f app-config.json ] && cp app-config.json "$BACKUP_DIR/" || echo "File app-config.json not found, skipping"
CONTENTS=""
[ -f "$BACKUP_DIR/db_backup.sql" ] && CONTENTS="$CONTENTS📋 db_backup.sql
"
[ -f "$BACKUP_DIR/docker-compose.yml" ] && CONTENTS="$CONTENTS📄 docker-compose.yml
"
[ -f "$BACKUP_DIR/.env" ] && CONTENTS="$CONTENTS🔑 .env
"
[ -f "$BACKUP_DIR/app-config.json" ] && CONTENTS="$CONTENTS⚙️ app-config.json
"
tar -czvf "$ARCHIVE_NAME" -C "$BACKUP_DIR" .
if [ $? -ne 0 ]; then
    echo "Error: Failed to create archive"
    exit 1
fi
EOF
fi

cat << 'EOF' >> "$BACKUP_SCRIPT"
ARCHIVE_SIZE=$(du -m "$ARCHIVE_NAME" | cut -f1)
MESSAGE=$(printf "🔔 Бэкап Remnawave\n📅 Дата: %s\n📦 Состав архива:\n%s" "$BACKUP_DATE" "$CONTENTS")
send_telegram() {
    local file="$1"
    local caption="$2"
    local curl_cmd="curl -F chat_id=\"\$TELEGRAM_CHAT_ID\""
    [ -n "$TELEGRAM_TOPIC_ID" ] && curl_cmd="$curl_cmd -F message_thread_id=\"\$TELEGRAM_TOPIC_ID\""
    curl_cmd="$curl_cmd -F document=@\"\$file\" -F \"caption=\$caption\" \"https://api.telegram.org/bot\$TELEGRAM_BOT_TOKEN/sendDocument\" -o telegram_response.json"
    eval "$curl_cmd"
}
if [ "$ARCHIVE_SIZE" -gt "$MAX_SIZE_MB" ]; then
    echo "Размер архива ($ARCHIVE_SIZE MB) превышает $MAX_SIZE_MB MB, выполняю разбиение..."
    split -b 49m "$ARCHIVE_NAME" "$BACKUP_DIR/part_"
    PARTS=("$BACKUP_DIR"/part_*)
    PART_COUNT=${#PARTS[@]}
    for i in "${!PARTS[@]}"; do
        PART_FILE="${PARTS[$i]}"
        PART_NUM=$((i + 1))
        PART_MESSAGE=$(printf "🔔 Бэкап Remnawave (Часть %d из %d)\n📅 Дата: %s\n📦 Состав архива:\n\n%s" "$PART_NUM" "$PART_COUNT" "$BACKUP_DATE" "$CONTENTS")
        send_telegram "$PART_FILE" "$PART_MESSAGE"
        if [ $? -ne 0 ] || grep -q '"ok":false' telegram_response.json; then
            echo "Ошибка отправки части $PART_NUM:"
            cat telegram_response.json
            exit 1
        fi
        echo "Часть $PART_NUM из $PART_COUNT успешно отправлена"
    done
else
    send_telegram "$ARCHIVE_NAME" "$MESSAGE"
    if [ $? -ne 0 ]; then
        echo "Ошибка отправки архива в Telegram"
        cat telegram_response.json
        exit 1
    fi
    if grep -q '"ok":false' telegram_response.json; then
        echo "Telegram вернул ошибку:"
        cat telegram_response.json
    else
        echo "Архив успешно отправлен в Telegram"
    fi
fi
rm -rf "$BACKUP_DIR"
rm "$ARCHIVE_NAME"
rm telegram_response.json
EOF

chmod +x "$BACKUP_SCRIPT"

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   Скрипт бэкапа успешно создан: $BACKUP_SCRIPT${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "${BLUE}Для запуска используйте: ${YELLOW}$BACKUP_SCRIPT${NC}"
echo -e "${BLUE}Чтобы добавить в crontab, выполните '${YELLOW}crontab -e${BLUE}' и добавьте, например:${NC}"
echo -e "${YELLOW}0 */2 * * * $BACKUP_SCRIPT${NC}"
