#!/bin/bash

# Backhaul Multi-Tunnel Manager
# Version: 3.1
# Author: hayousef68
# Rewritten and Fixed by Google Gemini

# --- Configuration ---
CONFIG_DIR="/etc/backhaul/configs"
BINARY_PATH="/usr/local/bin/backhaul"
LATEST_VERSION_URL="https://api.github.com/repos/Musixal/Backhaul/releases/latest"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- Helper Functions ---

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}خطا: این اسکریپت باید با دسترسی root اجرا شود!${NC}"
        exit 1
    fi
}

# Robust function to get public IP from multiple sources
get_public_ip() {
    local IP
    IP=$(curl -s --max-time 5 https://api.ipify.org)
    if [ -z "$IP" ]; then
        IP=$(curl -s --max-time 5 https://icanhazip.com)
    fi
    if [ -z "$IP" ]; then
        IP=$(curl -s --max-time 5 https://ipinfo.io/ip)
    fi
    
    if [[ -z "$IP" || "$IP" == *"html"* ]]; then
        echo "در دسترس نیست"
    else
        echo "$IP"
    fi
}

# Function to detect system architecture
detect_arch() {
    case $(uname -m) in
        x86_64 | amd64) echo "x86_64-unknown-linux-musl" ;;
        aarch64 | arm64) echo "aarch64-unknown-linux-musl" ;;
        *) echo "" ;;
    esac
}

# --- Core Functions ---

install_backhaul() {
    clear
    echo -e "${BLUE}در حال نصب یا به‌روزرسانی Backhaul...${NC}"
    ARCH=$(detect_arch)
    if [ -z "$ARCH" ]; then
        echo -e "${RED}خطا: معماری سیستم شما '$(uname -m)' پشتیبانی نمی‌شود.${NC}"
        return
    fi

    echo -e "${YELLOW}در حال دریافت اطلاعات آخرین نسخه...${NC}"
    LATEST_TAG=$(curl -s $LATEST_VERSION_URL | grep '"tag_name"' | cut -d'"' -f4)
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${RED}خطا: دریافت اطلاعات نسخه از GitHub ناموفق بود.${NC}"
        return
    fi

    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_TAG}/backhaul-${LATEST_TAG}-${ARCH}.tar.gz"
    
    echo -e "${CYAN}در حال دانلود نسخه ${LATEST_TAG} برای معماری ${ARCH}...${NC}"
    cd /tmp
    if ! wget -q --show-progress "$DOWNLOAD_URL" -O backhaul.tar.gz; then
        echo -e "${RED}خطا در دانلود! لطفاً اتصال اینترنت خود را بررسی کنید.${NC}"
        return
    fi
    
    tar -xzf backhaul.tar.gz
    chmod +x backhaul
    mv backhaul "$BINARY_PATH"
    
    mkdir -p "$CONFIG_DIR"
    rm -f /tmp/backhaul.tar.gz
    echo -e "${GREEN}Backhaul ${LATEST_TAG} با موفقیت نصب شد!${NC}"
}

create_tunnel_config() {
    clear
    echo -e "${PURPLE}--- ساخت کانفیگ تانل جدید ---${NC}"
    read -p "یک نام منحصر به فرد برای این تانل وارد کنید (مثال: vps1_ssh): " TUNNEL_NAME
    if [[ -z "$TUNNEL_NAME" || -f "$CONFIG_DIR/${TUNNEL_NAME}.toml" || -f "/etc/systemd/system/backhaul-${TUNNEL_NAME}.service" ]]; then
        echo -e "${RED}خطا: نام تانل نمی‌تواند خالی باشد یا از قبل وجود داشته باشد.${NC}"
        return
    fi

    echo "نقش این سرور چیست؟"
    echo "1) سرور (مقصد)"
    echo "2) کلاینت (مبدا)"
    read -p "انتخاب کنید [1-2]: " ROLE_CHOICE

    if [ "$ROLE_CHOICE" == "1" ]; then
        create_server_config "$TUNNEL_NAME"
    elif [ "$ROLE_CHOICE" == "2" ]; then
        create_client_config "$TUNNEL_NAME"
    else
        echo -e "${RED}انتخاب نامعتبر است.${NC}"
    fi
}

create_server_config() {
    local name=$1
    echo -e "\n${CYAN}--- تنظیمات سرور: ${name} ---${NC}"
    read -p "پورتی که سرور روی آن شنود کند [443]: " BIND_PORT; BIND_PORT=${BIND_PORT:-443}
    read -p "یک رمز عبور (token) برای اتصال وارد کنید [my_secret_pass]: " TOKEN; TOKEN=${TOKEN:-my_secret_pass}
    read -p "آیا Nodelay فعال باشد؟ (برای کاهش تاخیر) [y/N]: " NODELAY_CHOICE
    local NODELAY_STATUS=$( [[ "$NODELAY_CHOICE" =~ ^[Yy]$ ]] && echo "true" || echo "false" )

    cat > "$CONFIG_DIR/${name}.toml" << EOF
# Server Config: ${name}
[server]
bind_addr = "0.0.0.0:${BIND_PORT}"
transport = "wss"
token = "${TOKEN}"
nodelay = ${NODELAY_STATUS}
keepalive_period = 75
heartbeat = 40
sni = "cloudflare.com"

[server.channel_size]
queue_size = 2048
EOF
    echo -e "${GREEN}کانفیگ سرور '${name}' با موفقیت ساخته شد.${NC}"
    create_service "$name"
}

create_client_config() {
    local name=$1
    echo -e "\n${CYAN}--- تنظیمات کلاینت: ${name} ---${NC}"
    read -p "آدرس IP سرور مقصد: " SERVER_IP
    read -p "پورت سرور مقصد [443]: " SERVER_PORT; SERVER_PORT=${SERVER_PORT:-443}
    read -p "رمز عبور (token) سرور: " TOKEN
    read -p "آیا Nodelay فعال باشد؟ (برای کاهش تاخیر) [y/N]: " NODELAY_CHOICE
    local NODELAY_STATUS=$( [[ "$NODELAY_CHOICE" =~ ^[Yy]$ ]] && echo "true" || echo "false" )

    {
        echo "# Client Config: ${name}"
        echo "[client]"
        echo "remote_addr = \"${SERVER_IP}:${SERVER_PORT}\""
        echo "transport = \"wss\""
        echo "token = \"${TOKEN}\""
        echo "nodelay = ${NODELAY_STATUS}"
        echo "keepalive_period = 75"
        echo "retry_interval = 3"
        echo "heartbeat = 40"
        echo "sni = \"cloudflare.com\""
        echo ""
        echo "[client.channel_size]"
        echo "queue_size = 2048"
        echo ""
    } > "$CONFIG_DIR/${name}.toml"

    echo -e "\n${PURPLE}--- تعریف پورت‌های تانل ---${NC}"
    while true; do
        read -p "آیا می‌خواهید یک پورت جدید برای تانل تعریف کنید؟ [y/N]: " ADD_PORT_CHOICE
        if [[ ! "$ADD_PORT_CHOICE" =~ ^[Yy]$ ]]; then
            break
        fi
        read -p "  پورت محلی (روی این ماشین) که شنود شود (مثال: 8080): " LOCAL_PORT
        read -p "  آدرس و پورت مقصد (روی سرور دیگر) (مثال: 127.0.0.1:22): " REMOTE_ADDR

        {
            echo "[[client.services]]"
            echo "local_addr = \"0.0.0.0:${LOCAL_PORT}\""
            echo "remote_addr = \"${REMOTE_ADDR}\""
            echo ""
        } >> "$CONFIG_DIR/${name}.toml"
        echo -e "${GREEN}پورت ${LOCAL_PORT} به مقصد ${REMOTE_ADDR} اضافه شد.${NC}"
    done
    
    echo -e "${GREEN}کانفیگ کلاینت '${name}' با موفقیت ساخته شد.${NC}"
    create_service "$name"
}

create_service() {
    local name=$1
    local service_name="backhaul-${name}"
    
    cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=Backhaul Tunnel Service (${name})
After=network.target
[Service]
Type=simple
User=root
ExecStart=${BINARY_PATH} -c ${CONFIG_DIR}/${name}.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${service_name}" >/dev/null 2>&1
    echo -e "${CYAN}سرویس '${service_name}' ساخته و برای اجرای خودکار فعال شد.${NC}"
    read -p "آیا می‌خواهید سرویس را هم اکنون اجرا کنید؟ [y/N]: " START_CHOICE
    if [[ "$START_CHOICE" =~ ^[Yy]$ ]]; then
        systemctl start "${service_name}"
        echo -e "${GREEN}سرویس اجرا شد.${NC}"
    fi
}

manage_tunnels() {
    clear
    echo -e "${PURPLE}--- مدیریت تانل‌ها ---${NC}"
    mapfile -t configs < <(ls -1 "$CONFIG_DIR" 2>/dev/null | sed 's/\.toml$//')
    if [ ${#configs[@]} -eq 0 ]; then
        echo -e "${YELLOW}هیچ تانلی برای مدیریت یافت نشد.${NC}"
        return
    fi
    
    select TUNNEL_NAME in "${configs[@]}" "بازگشت"; do
        if [ "$TUNNEL_NAME" == "بازگشت" ]; then
            break
        elif [ -n "$TUNNEL_NAME" ]; then
            manage_single_tunnel "$TUNNEL_NAME"
            break
        else
            echo -e "${RED}انتخاب نامعتبر.${NC}"
        fi
    done
}

manage_single_tunnel() {
    local name=$1
    local service_name="backhaul-${name}"
    while true; do
        clear
        echo -e "${PURPLE}--- مدیریت تانل: ${WHITE}${name}${NC} ---"
        if systemctl is-active --quiet "$service_name"; then
            echo -e "وضعیت: ${GREEN}فعال${NC}"
        else
            echo -e "وضعیت: ${RED}غیرفعال${NC}"
        fi
        echo "-----------------------------------"
        echo "1) شروع سرویس (Start)"
        echo "2) توقف سرویس (Stop)"
        echo "3) راه‌اندازی مجدد (Restart)"
        echo "4) مشاهده لاگ‌ها (Logs)"
        echo "5) مشاهده فایل کانفیگ"
        echo -e "6) ${RED}حذف کامل تانل${NC}"
        echo "7) بازگشت به منوی اصلی"
        read -p "انتخاب کنید: " choice
        
        case $choice in
            1) systemctl start "$service_name" && echo -e "${GREEN}سرویس شروع شد.${NC}" ;;
            2) systemctl stop "$service_name" && echo -e "${GREEN}سرویس متوقف شد.${NC}" ;;
            3) systemctl restart "$service_name" && echo -e "${GREEN}سرویس مجددا راه‌اندازی شد.${NC}" ;;
            4) journalctl -u "$service_name" -f --no-pager ;;
            5) less "$CONFIG_DIR/${name}.toml" ;;
            6)
                read -p "آیا از حذف کامل تانل '${name}' مطمئن هستید؟ [y/N]: " DEL_CHOICE
                if [[ "$DEL_CHOICE" =~ ^[Yy]$ ]]; then
                    systemctl stop "$service_name" >/dev/null 2>&1
                    systemctl disable "$service_name" >/dev/null 2>&1
                    rm -f "/etc/systemd/system/${service_name}.service"
                    rm -f "$CONFIG_DIR/${name}.toml"
                    systemctl daemon-reload
                    echo -e "${GREEN}تانل '${name}' به طور کامل حذف شد.${NC}"
                    return
                fi
                ;;
            7) return ;;
            *) echo -e "${RED}انتخاب نامعتبر!${NC}" ;;
        esac
        read -n 1 -s -r -p "برای ادامه کلیدی را فشار دهید..."
    done
}

uninstall_backhaul() {
    clear
    read -p "آیا از حذف کامل Backhaul و تمام تانل‌ها مطمئن هستید؟ [y/N]: " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}عملیات لغو شد.${NC}"
        return
    fi
    
    echo "در حال توقف و حذف تمام سرویس‌های Backhaul..."
    mapfile -t services < <(ls -1 /etc/systemd/system/backhaul-*.service 2>/dev/null)
    if [ ${#services[@]} -gt 0 ]; then
        for s in "${services[@]}"; do
            systemctl stop "$(basename "$s")"
            systemctl disable "$(basename "$s")"
        done
        rm -f /etc/systemd/system/backhaul-*.service
        systemctl daemon-reload
    fi
    
    echo "در حال حذف فایل‌های کانفیگ و فایل اجرایی..."
    rm -rf "/etc/backhaul"
    rm -f "$BINARY_PATH"
    
    echo -e "${GREEN}Backhaul به طور کامل حذف شد.${NC}"
}

show_main_menu() {
    clear
    local PUBLIC_IP=$(get_public_ip)
    echo -e "${CYAN}================== Backhaul Manager v3.1 ==================${NC}"
    echo -e " ${WHITE}آی پی عمومی سرور: ${YELLOW}${PUBLIC_IP}${NC}"
    echo -e "${CYAN}===========================================================${NC}"
    
    if [ ! -f "$BINARY_PATH" ]; then
        echo -e "\n${YELLOW}Backhaul نصب نشده است. لطفاً ابتدا از گزینه 1 برای نصب استفاده کنید.${NC}\n"
    else
        echo -e "\n${PURPLE}--- لیست تانل‌های موجود ---${NC}"
        mapfile -t configs < <(ls -1 "$CONFIG_DIR" 2>/dev/null | sed 's/\.toml$//')
        if [ ${#configs[@]} -eq 0 ]; then
            echo -e "${YELLOW}هیچ تانلی یافت نشد. برای شروع یک تانل جدید بسازید.${NC}"
        else
            for name in "${configs[@]}"; do
                local STATUS
                if systemctl is-active --quiet "backhaul-${name}"; then
                    STATUS="[${GREEN}فعال${NC}]"
                else
                    STATUS="[${RED}غیرفعال${NC}]"
                fi
                local ROLE=$(grep -q '\[server\]' "$CONFIG_DIR/${name}.toml" && echo "سرور" || echo "کلاینت")
                local DETAILS
                if [ "$ROLE" == "سرور" ]; then
                    DETAILS=$(grep 'bind_addr' "$CONFIG_DIR/${name}.toml" | cut -d'"' -f2)
                else
                    DETAILS=$(grep 'remote_addr' "$CONFIG_DIR/${name}.toml" | head -n1 | cut -d'"' -f2)
                fi
                printf " %-12s ${WHITE}%-20s${NC} ${CYAN}(%s)${NC} ${WHITE}-> %s${NC}\n" "$STATUS" "$name" "$ROLE" "$DETAILS"
            done
        fi
    fi
    
    echo -e "\n${CYAN}--- منوی اصلی ---${NC}"
    echo "1) نصب یا به‌روزرسانی Backhaul"
    echo "2) ساخت تانل جدید"
    echo "3) مدیریت تانل‌های موجود"
    echo -e "4) ${RED}حذف کامل Backhaul${NC}"
    echo "0) خروج"
    echo ""
}

# --- Main Loop ---
check_root
while true; do
    show_main_menu
    read -p "لطفا یک گزینه را انتخاب کنید: " main_choice
    case $main_choice in
        1) install_backhaul ;;
        2) create_tunnel_config ;;
        3) manage_tunnels ;;
        4) uninstall_backhaul ;;
        0) exit 0 ;;
        *) echo -e "${RED}انتخاب نامعتبر!${NC}" ;;
    esac
    read -n 1 -s -r -p $'\nبرای بازگشت به منو، یک کلید را فشار دهید...'
done
