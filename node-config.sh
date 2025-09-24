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
    echo -e "   ${WHITE}0)${NC} ⬅️  Назад"
    echo
    
    read -p "Выберите опцию [0-3]: " ufw_choice
    
    case "$ufw_choice" in
        1)
            if ufw status | grep -q "Status: active"; then
                echo -e "${YELLOW}⚠️  UFW уже активен${NC}"
            else
                echo -e "${BLUE}🔧 Включаем UFW...${NC}"
                sudo ufw --force enable
                echo -e "${GREEN}✅ UFW включен${NC}"
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
