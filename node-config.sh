#!/usr/bin/env bash
# Node Configuration Script
# Version: 1.0.0

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Функция для проверки статуса UFW
check_ufw_status() {
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "${GRAY}❌ UFW не установлен${NC}"
        return 1
    fi
    
    if ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}✅ Активен${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Неактивен${NC}"
        return 1
    fi
}

# Функция для проверки статуса IPv6
check_ipv6_status() {
    local ipv6_disabled=false
    
    # Проверяем /etc/sysctl.conf
    if [ -f "/etc/sysctl.conf" ] && grep -q "net.ipv6.conf.all.disable_ipv6 = 1" "/etc/sysctl.conf"; then
        ipv6_disabled=true
    fi
    
    # Проверяем /etc/sysctl.d/99-sysctl.conf
    if [ -f "/etc/sysctl.d/99-sysctl.conf" ] && grep -q "net.ipv6.conf.all.disable_ipv6 = 1" "/etc/sysctl.d/99-sysctl.conf"; then
        ipv6_disabled=true
    fi
    
    # Проверяем текущее состояние
    if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "0")" = "1" ]; then
        ipv6_disabled=true
    fi
    
    if [ "$ipv6_disabled" = true ]; then
        echo -e "${GREEN}✅ Отключен${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Включен${NC}"
        return 1
    fi
}

# Функция для отображения шапки со статусами
show_status_header() {
    clear
    echo -e "${WHITE}⚙️  Настройка ноды${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo
    
    # Статус UFW
    echo -e "${WHITE}🛡️  Статус UFW:${NC} $(check_ufw_status)"
    
    # Статус IPv6
    echo -e "${WHITE}🌐 Статус IPv6:${NC} $(check_ipv6_status)"
    
    echo
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo
}

# Функция для отключения IPv6
disable_ipv6() {
    echo -e "${WHITE}🌐 Отключение IPv6${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    # Проверяем, не отключен ли уже
    if check_ipv6_status >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  IPv6 уже отключен${NC}"
        return 0
    fi
    
    echo -e "${BLUE}🔧 Настраиваем отключение IPv6...${NC}"
    
    # Создаем конфигурацию в /etc/sysctl.d/
    cat > /etc/sysctl.d/99-disable-ipv6.conf << EOF
# Отключение IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    
    # Применяем настройки
    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf
    
    echo -e "${GREEN}✅ IPv6 успешно отключен${NC}"
    echo -e "${GRAY}   Перезагрузка рекомендуется для полного применения настроек${NC}"
}

# Функция для включения IPv6
enable_ipv6() {
    echo -e "${WHITE}🌐 Включение IPv6${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    # Проверяем, не включен ли уже
    if ! check_ipv6_status >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  IPv6 уже включен${NC}"
        return 0
    fi
    
    echo -e "${BLUE}🔧 Настраиваем включение IPv6...${NC}"
    
    # Удаляем конфигурацию отключения
    rm -f /etc/sysctl.d/99-disable-ipv6.conf
    
    # Удаляем из /etc/sysctl.conf если есть
    if [ -f "/etc/sysctl.conf" ]; then
        sed -i '/net\.ipv6\.conf\.all\.disable_ipv6/d' /etc/sysctl.conf
        sed -i '/net\.ipv6\.conf\.default\.disable_ipv6/d' /etc/sysctl.conf
        sed -i '/net\.ipv6\.conf\.lo\.disable_ipv6/d' /etc/sysctl.conf
    fi
    
    # Применяем настройки
    sysctl -w net.ipv6.conf.all.disable_ipv6=0
    sysctl -w net.ipv6.conf.default.disable_ipv6=0
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0
    
    echo -e "${GREEN}✅ IPv6 успешно включен${NC}"
    echo -e "${GRAY}   Перезагрузка рекомендуется для полного применения настроек${NC}"
}

# Функция для управления UFW
manage_ufw() {
    echo -e "${WHITE}🔥 Управление UFW${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "${RED}❌ UFW не установлен!${NC}"
        echo -e "${GRAY}Установите UFW: sudo apt install ufw${NC}"
        return 1
    fi
    
    echo -e "${WHITE}Выберите действие:${NC}"
    echo -e "   ${WHITE}1)${NC} 🔥 Включить UFW"
    echo -e "   ${WHITE}2)${NC} ❌ Выключить UFW"
    echo -e "   ${WHITE}3)${NC} 📋 Показать статус UFW"
    echo -e "   ${WHITE}4)${NC} 🌐 Открыть порты для IP"
    echo -e "   ${WHITE}5)${NC} 🗑️  Удалить правила по портам"
    echo -e "   ${WHITE}6)${NC} 🗑️  Удалить все правила UFW"
    echo -e "   ${WHITE}0)${NC} ⬅️  Назад"
    echo
    
    read -p "Выберите опцию [0-6]: " ufw_choice
    
    case "$ufw_choice" in
        1)
            if ufw status | grep -q "Status: active"; then
                echo -e "${YELLOW}⚠️  UFW уже активен${NC}"
            else
                echo -e "${BLUE}🔧 Включаем UFW...${NC}"
                
                # Отключаем IPv6 в UFW перед настройкой
                echo -e "${BLUE}🔧 Отключаем IPv6 в UFW...${NC}"
                sudo ufw --force disable
                
                # Настраиваем UFW для работы только с IPv4
                echo 'IPV6=no' | sudo tee -a /etc/default/ufw
                
                # Включаем UFW
                sudo ufw --force enable
                
                # Открываем основные порты только для IPv4
                echo -e "${BLUE}🔓 Открываем основные порты (только IPv4):${NC}"
                echo -e "  • SSH (22)..."
                sudo ufw allow 22/tcp
                echo -e "  • HTTPS (443)..."
                sudo ufw allow 443/tcp
                
                echo -e "${GREEN}✅ UFW включен с открытыми портами SSH и HTTPS (только IPv4)${NC}"
            fi
            ;;
        2)
            if ! ufw status | grep -q "Status: active"; then
                echo -e "${YELLOW}⚠️  UFW уже неактивен${NC}"
            else
                echo -e "${BLUE}🔧 Выключаем UFW...${NC}"
                sudo ufw --force disable
                echo -e "${GREEN}✅ UFW выключен${NC}"
            fi
            ;;
        3)
            echo -e "${BLUE}📋 Статус UFW:${NC}"
            sudo ufw status verbose
            ;;
        4)
            open_ports_for_ip
            ;;
        5)
            delete_ports_rules
            ;;
        6)
            reset_ufw_rules
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор!${NC}"
            ;;
    esac
}

# Функция для открытия портов для IP
open_ports_for_ip() {
    echo -e "${WHITE}🌐 Открытие портов для IP${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    # Получаем порт RemnaNode из конфигурации
    local node_port="6001"
    if [ -f "/opt/remnanode/.env" ]; then
        node_port=$(grep "APP_PORT=" "/opt/remnanode/.env" | cut -d'=' -f2 2>/dev/null || echo "6001")
    fi
    
    echo -e "${WHITE}Выберите порт для открытия:${NC}"
    echo -e "   ${WHITE}1)${NC} \033[1;32m9100\033[0m - Node Exporter (мониторинг)"
    echo -e "   ${WHITE}2)${NC} \033[1;32m$node_port\033[0m - RemnaNode (текущий порт)"
    echo -e "   ${WHITE}3)${NC} \033[1;32m22\033[0m - SSH"
    echo -e "   ${WHITE}4)${NC} \033[1;32m443\033[0m - HTTPS"
    echo -e "   ${WHITE}5)${NC} \033[1;32m80\033[0m - HTTP"
    echo -e "   ${WHITE}6)${NC} \033[1;32mДругой порт\033[0m - ввести вручную"
    echo
    
    read -p "Выберите опцию [1-6]: " port_choice
    
    local selected_port=""
    case "$port_choice" in
        1) selected_port="9100" ;;
        2) selected_port="$node_port" ;;
        3) selected_port="22" ;;
        4) selected_port="443" ;;
        5) selected_port="80" ;;
        6) 
            read -p "Введите номер порта: " selected_port
            if ! [[ "$selected_port" =~ ^[0-9]+$ ]] || [ "$selected_port" -lt 1 ] || [ "$selected_port" -gt 65535 ]; then
                echo -e "${RED}❌ Неверный номер порта! Должен быть от 1 до 65535${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор!${NC}"
            return 1
            ;;
    esac
    
    echo
    echo -e "${WHITE}Введите IP адрес для открытия порта $selected_port:${NC}"
    echo -e "${GRAY}Пример: 192.168.1.100 или 10.0.0.0/8${NC}"
    read -p "IP адрес: " target_ip
    
    if [ -z "$target_ip" ]; then
        echo -e "${RED}❌ IP адрес не может быть пустым${NC}"
        return 1
    fi
    
    echo
    echo -e "${BLUE}🔧 Открываем порт $selected_port для $target_ip...${NC}"
    
    # Убеждаемся что IPv6 отключен в UFW
    if ! grep -q "IPV6=no" /etc/default/ufw; then
        echo 'IPV6=no' | sudo tee -a /etc/default/ufw
    fi
    
    # Открываем порт только для IPv4
    if sudo ufw allow from "$target_ip" to any port "$selected_port"; then
        echo -e "${GREEN}✅ Порт $selected_port успешно открыт для $target_ip (только IPv4)${NC}"
    else
        echo -e "${RED}❌ Ошибка при открытии порта $selected_port${NC}"
    fi
}

# Функция для удаления правил по портам
delete_ports_rules() {
    echo -e "${WHITE}🗑️  Удаление правил по портам${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    # Получаем порт RemnaNode из конфигурации
    local node_port="6001"
    if [ -f "/opt/remnanode/.env" ]; then
        node_port=$(grep "APP_PORT=" "/opt/remnanode/.env" | cut -d'=' -f2 2>/dev/null || echo "6001")
    fi
    
    echo -e "${WHITE}Выберите порт для удаления правил:${NC}"
    echo -e "   ${WHITE}1)${NC} \033[1;32m22\033[0m - SSH"
    echo -e "   ${WHITE}2)${NC} \033[1;32m443\033[0m - HTTPS"
    echo -e "   ${WHITE}3)${NC} \033[1;32m80\033[0m - HTTP"
    echo -e "   ${WHITE}4)${NC} \033[1;32m9100\033[0m - Node Exporter"
    echo -e "   ${WHITE}5)${NC} \033[1;32m$node_port\033[0m - RemnaNode"
    echo -e "   ${WHITE}6)${NC} \033[1;32mДругой порт\033[0m - ввести вручную"
    echo -e "   ${WHITE}7)${NC} \033[1;32mВсе порты\033[0m - удалить все правила"
    echo
    
    read -p "Выберите опцию [1-7]: " port_choice
    
    case "$port_choice" in
        1) delete_port_rule "22" ;;
        2) delete_port_rule "443" ;;
        3) delete_port_rule "80" ;;
        4) delete_port_rule "9100" ;;
        5) delete_port_rule "$node_port" ;;
        6) 
            read -p "Введите номер порта: " custom_port
            if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1 ] && [ "$custom_port" -le 65535 ]; then
                delete_port_rule "$custom_port"
            else
                echo -e "${RED}❌ Неверный номер порта!${NC}"
            fi
            ;;
        7)
            echo -e "${YELLOW}⚠️  Удаляем все правила UFW...${NC}"
            sudo ufw --force reset
            echo -e "${GREEN}✅ Все правила UFW удалены${NC}"
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор!${NC}"
            ;;
    esac
}

# Вспомогательная функция для удаления правил порта
delete_port_rule() {
    local port="$1"
    echo -e "${BLUE}🔧 Удаляем правила для порта $port...${NC}"
    
    # Удаляем все правила для порта
    local deleted=false
    
    # Удаляем правила allow
    if sudo ufw delete allow "$port" 2>/dev/null; then
        echo -e "  ✅ Удалено правило allow для порта $port"
        deleted=true
    fi
    
    # Удаляем правила deny
    if sudo ufw delete deny "$port" 2>/dev/null; then
        echo -e "  ✅ Удалено правило deny для порта $port"
        deleted=true
    fi
    
    # Удаляем правила с протоколом tcp
    if sudo ufw delete allow "$port/tcp" 2>/dev/null; then
        echo -e "  ✅ Удалено правило allow для порта $port/tcp"
        deleted=true
    fi
    
    if sudo ufw delete deny "$port/tcp" 2>/dev/null; then
        echo -e "  ✅ Удалено правило deny для порта $port/tcp"
        deleted=true
    fi
    
    if [ "$deleted" = true ]; then
        echo -e "${GREEN}✅ Правила для порта $port успешно удалены${NC}"
    else
        echo -e "${YELLOW}⚠️  Правила для порта $port не найдены${NC}"
    fi
}

# Функция для сброса всех правил UFW
reset_ufw_rules() {
    echo -e "${WHITE}🗑️  Сброс всех правил UFW${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    echo -e "${YELLOW}⚠️  ВНИМАНИЕ: Это удалит ВСЕ правила UFW!${NC}"
    echo -e "${GRAY}Это действие нельзя отменить.${NC}"
    echo
    read -p "Вы уверены? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}🔧 Сбрасываем все правила UFW...${NC}"
        if sudo ufw --force reset; then
            echo -e "${GREEN}✅ Все правила UFW успешно удалены${NC}"
            echo -e "${GRAY}UFW теперь имеет только базовые правила по умолчанию${NC}"
        else
            echo -e "${RED}❌ Ошибка при сбросе правил UFW${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Операция отменена${NC}"
    fi
}

# ===== Функции системных настроек =====

# Настройка hostname
configure_hostname() {
    echo -e "${WHITE}🖥️  Настройка hostname${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    local current_hostname=$(hostname)
    echo -e "${BLUE}Текущий hostname: ${YELLOW}$current_hostname${NC}"
    echo
    
    echo -e "${WHITE}Выберите действие:${NC}"
    echo -e "   ${WHITE}1)${NC} 📝 Изменить hostname"
    echo -e "   ${WHITE}2)${NC} 📋 Показать текущий hostname"
    echo -e "   ${WHITE}0)${NC} ⬅️  Назад"
    echo
    
    read -p "Выберите опцию [0-2]: " hostname_choice
    
    case "$hostname_choice" in
        1)
            echo
            read -p "Введите новый hostname: " new_hostname
            
            if [ -z "$new_hostname" ]; then
                echo -e "${RED}❌ Hostname не может быть пустым${NC}"
                return 1
            fi
            
            # Проверяем формат hostname
            if ! [[ "$new_hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]] && [ ${#new_hostname} -gt 1 ]; then
                echo -e "${RED}❌ Неверный формат hostname! Используйте только буквы, цифры и дефисы${NC}"
                return 1
            fi
            
            echo -e "${BLUE}🔧 Изменяем hostname на $new_hostname...${NC}"
            
            # Изменяем hostname
            echo "$new_hostname" | sudo tee /etc/hostname > /dev/null
            sudo hostnamectl set-hostname "$new_hostname"
            
            # Обновляем /etc/hosts
            sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/" /etc/hosts
            
            echo -e "${GREEN}✅ Hostname изменен на $new_hostname${NC}"
            echo -e "${YELLOW}⚠️  Перезагрузка рекомендуется для полного применения изменений${NC}"
            ;;
        2)
            echo -e "${BLUE}📋 Информация о hostname:${NC}"
            echo -e "  Hostname: ${YELLOW}$current_hostname${NC}"
            echo -e "  FQDN: ${YELLOW}$(hostname -f)${NC}"
            echo -e "  Domain: ${YELLOW}$(hostname -d)${NC}"
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор!${NC}"
            ;;
    esac
}

# Настройка timezone
configure_timezone() {
    echo -e "${WHITE}🕐 Настройка timezone${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    local current_tz=$(timedatectl show --property=Timezone --value)
    echo -e "${BLUE}Текущий timezone: ${YELLOW}$current_tz${NC}"
    echo
    
    echo -e "${WHITE}Выберите действие:${NC}"
    echo -e "   ${WHITE}1)${NC} 🌍 Выбрать timezone из списка"
    echo -e "   ${WHITE}2)${NC} 🔍 Поиск timezone"
    echo -e "   ${WHITE}3)${NC} 📋 Показать текущий timezone"
    echo -e "   ${WHITE}0)${NC} ⬅️  Назад"
    echo
    
    read -p "Выберите опцию [0-3]: " tz_choice
    
    case "$tz_choice" in
        1)
            echo -e "${BLUE}🌍 Популярные timezone:${NC}"
            echo -e "   ${WHITE}1)${NC} Europe/Moscow"
            echo -e "   ${WHITE}2)${NC} Europe/London"
            echo -e "   ${WHITE}3)${NC} America/New_York"
            echo -e "   ${WHITE}4)${NC} Asia/Tokyo"
            echo -e "   ${WHITE}5)${NC} UTC"
            echo -e "   ${WHITE}6)${NC} Другой timezone"
            echo
            
            read -p "Выберите timezone [1-6]: " tz_select
            
            local selected_tz=""
            case "$tz_select" in
                1) selected_tz="Europe/Moscow" ;;
                2) selected_tz="Europe/London" ;;
                3) selected_tz="America/New_York" ;;
                4) selected_tz="Asia/Tokyo" ;;
                5) selected_tz="UTC" ;;
                6) 
                    read -p "Введите timezone (например, Europe/Moscow): " selected_tz
                    ;;
                *)
                    echo -e "${RED}❌ Неверный выбор!${NC}"
                    return 1
                    ;;
            esac
            
            if [ -n "$selected_tz" ]; then
                echo -e "${BLUE}🔧 Устанавливаем timezone $selected_tz...${NC}"
                if sudo timedatectl set-timezone "$selected_tz"; then
                    echo -e "${GREEN}✅ Timezone установлен: $selected_tz${NC}"
                    echo -e "${BLUE}Текущее время: ${YELLOW}$(date)${NC}"
                else
                    echo -e "${RED}❌ Ошибка при установке timezone${NC}"
                fi
            fi
            ;;
        2)
            read -p "Введите часть названия timezone для поиска: " search_term
            if [ -n "$search_term" ]; then
                echo -e "${BLUE}🔍 Результаты поиска:${NC}"
                timedatectl list-timezones | grep -i "$search_term" | head -10
            fi
            ;;
        3)
            echo -e "${BLUE}📋 Информация о времени:${NC}"
            echo -e "  Timezone: ${YELLOW}$current_tz${NC}"
            echo -e "  Время: ${YELLOW}$(date)${NC}"
            echo -e "  UTC: ${YELLOW}$(date -u)${NC}"
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор!${NC}"
            ;;
    esac
}

# Настройка DNS
configure_dns() {
    echo -e "${WHITE}🌐 Настройка DNS${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    echo -e "${BLUE}Текущие DNS серверы:${NC}"
    if [ -f "/etc/resolv.conf" ]; then
        grep "nameserver" /etc/resolv.conf | sed 's/^/  /'
    fi
    echo
    
    echo -e "${WHITE}Выберите действие:${NC}"
    echo -e "   ${WHITE}1)${NC} 🔧 Настроить DNS серверы"
    echo -e "   ${WHITE}2)${NC} 📋 Показать текущие DNS"
    echo -e "   ${WHITE}3)${NC} 🧪 Тест DNS"
    echo -e "   ${WHITE}0)${NC} ⬅️  Назад"
    echo
    
    read -p "Выберите опцию [0-3]: " dns_choice
    
    case "$dns_choice" in
        1)
            echo -e "${BLUE}🔧 Настройка DNS серверов:${NC}"
            echo -e "   ${WHITE}1)${NC} Cloudflare (1.1.1.1, 1.0.0.1)"
            echo -e "   ${WHITE}2)${NC} Google (8.8.8.8, 8.8.4.4)"
            echo -e "   ${WHITE}3)${NC} Quad9 (9.9.9.9, 149.112.112.112)"
            echo -e "   ${WHITE}4)${NC} OpenDNS (208.67.222.222, 208.67.220.220)"
            echo -e "   ${WHITE}5)${NC} Пользовательские DNS"
            echo
            
            read -p "Выберите DNS провайдера [1-5]: " dns_provider
            
            local dns1="" dns2=""
            case "$dns_provider" in
                1) dns1="1.1.1.1"; dns2="1.0.0.1" ;;
                2) dns1="8.8.8.8"; dns2="8.8.4.4" ;;
                3) dns1="9.9.9.9"; dns2="149.112.112.112" ;;
                4) dns1="208.67.222.222"; dns2="208.67.220.220" ;;
                5) 
                    read -p "Введите первый DNS сервер: " dns1
                    read -p "Введите второй DNS сервер: " dns2
                    ;;
                *)
                    echo -e "${RED}❌ Неверный выбор!${NC}"
                    return 1
                    ;;
            esac
            
            if [ -n "$dns1" ] && [ -n "$dns2" ]; then
                echo -e "${BLUE}🔧 Настраиваем DNS серверы...${NC}"
                
                # Создаем резервную копию
                sudo cp /etc/resolv.conf /etc/resolv.conf.backup
                
                # Настраиваем DNS
                cat > /tmp/resolv.conf << EOF
# DNS серверы настроены через node-config.sh
nameserver $dns1
nameserver $dns2
options edns0
EOF
                
                sudo mv /tmp/resolv.conf /etc/resolv.conf
                sudo chmod 644 /etc/resolv.conf
                
                echo -e "${GREEN}✅ DNS серверы настроены:${NC}"
                echo -e "  Primary: ${YELLOW}$dns1${NC}"
                echo -e "  Secondary: ${YELLOW}$dns2${NC}"
            fi
            ;;
        2)
            echo -e "${BLUE}📋 Текущие DNS настройки:${NC}"
            if [ -f "/etc/resolv.conf" ]; then
                cat /etc/resolv.conf
            else
                echo -e "${RED}❌ Файл /etc/resolv.conf не найден${NC}"
            fi
            ;;
        3)
            echo -e "${BLUE}🧪 Тестируем DNS...${NC}"
            echo -e "Тест Google DNS:"
            nslookup google.com 8.8.8.8
            echo
            echo -e "Тест Cloudflare DNS:"
            nslookup google.com 1.1.1.1
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор!${NC}"
            ;;
    esac
}

# Настройка TCP параметров
configure_tcp_params() {
    echo -e "${WHITE}🚀 Настройка TCP параметров${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    echo -e "${WHITE}Выберите профиль оптимизации:${NC}"
    echo -e "   ${WHITE}1)${NC} 🏠 Домашний сервер (базовая оптимизация)"
    echo -e "   ${WHITE}2)${NC} 🏢 Корпоративный сервер (средняя оптимизация)"
    echo -e "   ${WHITE}3)${NC} 🚀 Высоконагруженный сервер (максимальная оптимизация)"
    echo -e "   ${WHITE}4)${NC} 📋 Показать текущие параметры"
    echo -e "   ${WHITE}5)${NC} 🔄 Сбросить к значениям по умолчанию"
    echo -e "   ${WHITE}0)${NC} ⬅️  Назад"
    echo
    
    read -p "Выберите опцию [0-5]: " tcp_choice
    
    case "$tcp_choice" in
        1|2|3)
            local profile_name=""
            case "$tcp_choice" in
                1) profile_name="домашний сервер" ;;
                2) profile_name="корпоративный сервер" ;;
                3) profile_name="высоконагруженный сервер" ;;
            esac
            
            echo -e "${BLUE}🔧 Применяем настройки для $profile_name...${NC}"
            
            # Создаем конфигурацию TCP
            cat > /tmp/99-tcp-optimization.conf << EOF
# TCP оптимизация для $profile_name
# Настроено через node-config.sh

# Базовые настройки
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 65535

# TCP настройки
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_fastopen = 3
EOF
            
            # Дополнительные настройки для высоконагруженных серверов
            if [ "$tcp_choice" = "3" ]; then
                cat >> /tmp/99-tcp-optimization.conf << EOF

# Дополнительные настройки для высоконагруженных серверов
net.core.netdev_budget = 600
net.ipv4.tcp_workaround_signed_windows = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
EOF
            fi
            
            # Применяем настройки
            sudo mv /tmp/99-tcp-optimization.conf /etc/sysctl.d/99-tcp-optimization.conf
            sudo chmod 644 /etc/sysctl.d/99-tcp-optimization.conf
            sudo sysctl -p /etc/sysctl.d/99-tcp-optimization.conf
            
            echo -e "${GREEN}✅ TCP параметры настроены для $profile_name${NC}"
            echo -e "${YELLOW}⚠️  Перезагрузка рекомендуется для полного применения изменений${NC}"
            ;;
        4)
            echo -e "${BLUE}📋 Текущие TCP параметры:${NC}"
            echo -e "Congestion Control: ${YELLOW}$(sysctl net.ipv4.tcp_congestion_control | cut -d'=' -f2)${NC}"
            echo -e "Max Connections: ${YELLOW}$(sysctl net.core.somaxconn | cut -d'=' -f2)${NC}"
            echo -e "TCP Window Scaling: ${YELLOW}$(sysctl net.ipv4.tcp_window_scaling | cut -d'=' -f2)${NC}"
            echo -e "TCP SACK: ${YELLOW}$(sysctl net.ipv4.tcp_sack | cut -d'=' -f2)${NC}"
            ;;
        5)
            echo -e "${BLUE}🔄 Сбрасываем TCP параметры к значениям по умолчанию...${NC}"
            sudo rm -f /etc/sysctl.d/99-tcp-optimization.conf
            sudo sysctl --system
            echo -e "${GREEN}✅ TCP параметры сброшены${NC}"
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор!${NC}"
            ;;
    esac
}

# Главное меню
main_menu() {
    while true; do
        show_status_header
        
        echo -e "${WHITE}📋 Доступные настройки:${NC}"
        echo
        echo -e "${WHITE}🔥 UFW:${NC}"
        echo -e "   ${WHITE}1)${NC} 🔥 Управление UFW"
        echo
        echo -e "${WHITE}🌐 IPv6:${NC}"
        echo -e "   ${WHITE}2)${NC} ❌ Отключить IPv6"
        echo -e "   ${WHITE}3)${NC} ✅ Включить IPv6"
        echo
        echo -e "${WHITE}⚙️  Системные настройки:${NC}"
        echo -e "   ${WHITE}4)${NC} 🖥️  Настройка hostname"
        echo -e "   ${WHITE}5)${NC} 🕐 Настройка timezone"
        echo -e "   ${WHITE}6)${NC} 🌐 Настройка DNS"
        echo -e "   ${WHITE}7)${NC} 🚀 Настройка TCP параметров"
        echo
        echo -e "   ${GRAY}0)${NC} ⬅️  Выход"
        echo
        
        read -p "Выберите опцию [0-7]: " choice
        
        case "$choice" in
            1)
                manage_ufw
                read -p "Нажмите Enter для продолжения..."
                ;;
            2)
                disable_ipv6
                read -p "Нажмите Enter для продолжения..."
                ;;
            3)
                enable_ipv6
                read -p "Нажмите Enter для продолжения..."
                ;;
            4)
                configure_hostname
                read -p "Нажмите Enter для продолжения..."
                ;;
            5)
                configure_timezone
                read -p "Нажмите Enter для продолжения..."
                ;;
            6)
                configure_dns
                read -p "Нажмите Enter для продолжения..."
                ;;
            7)
                configure_tcp_params
                read -p "Нажмите Enter для продолжения..."
                ;;
            0)
                echo -e "${GREEN}👋 Возврат в главное меню...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Неверный выбор! Пожалуйста, выберите опцию от 0 до 7.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Запуск скрипта
main_menu
