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
    echo -e "   ${WHITE}5)${NC} 🗑️  Удалить все правила UFW"
    echo -e "   ${WHITE}0)${NC} ⬅️  Назад"
    echo
    
    read -p "Выберите опцию [0-5]: " ufw_choice
    
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
                sudo ufw allow in on any to any port 22 proto tcp
                echo -e "  • HTTPS (443)..."
                sudo ufw allow in on any to any port 443 proto tcp
                
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
    if sudo ufw allow from "$target_ip" to any port "$selected_port" proto tcp; then
        echo -e "${GREEN}✅ Порт $selected_port успешно открыт для $target_ip (только IPv4)${NC}"
    else
        echo -e "${RED}❌ Ошибка при открытии порта $selected_port${NC}"
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
        echo -e "   ${GRAY}0)${NC} ⬅️  Выход"
        echo
        
        read -p "Выберите опцию [0-3]: " choice
        
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
            0)
                echo -e "${GREEN}👋 Возврат в главное меню...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Неверный выбор! Пожалуйста, выберите опцию от 0 до 3.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Запуск скрипта
main_menu
