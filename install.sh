#!/bin/bash

# Backhaul Auto Setup Script
# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variables
CONFIG_DIR="/etc/backhaul"
LOG_FILE="/var/log/backhaul.log"
SERVICE_FILE="/etc/systemd/system/backhaul.service"
BINARY_PATH="/usr/local/bin/backhaul"

# Clear screen function
clear_screen() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    ${WHITE}Backhaul Auto Manager${CYAN}                     ║${NC}"
    echo -e "${CYAN}║                        ${YELLOW}v1.0 - Persian${CYAN}                         ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ این اسکریپت باید با دسترسی root اجرا شود!${NC}"
        echo -e "${YELLOW}لطفاً با sudo اجرا کنید: sudo bash $0${NC}"
        exit 1
    fi
}

# Detect system architecture
detect_arch() {
    case $(uname -m) in
        x86_64|amd64) echo "linux-amd64" ;;
        aarch64|arm64) echo "linux-arm64" ;;
        armv7l) echo "linux-armv7" ;;
        i386|i686) echo "linux-386" ;;
        *) echo "unsupported" ;;
    esac
}

# Download and install Backhaul
install_backhaul() {
    echo -e "${BLUE}🔄 در حال نصب Backhaul...${NC}"
    
    ARCH=$(detect_arch)
    if [ "$ARCH" = "unsupported" ]; then
        echo -e "${RED}❌ معماری سیستم شما پشتیبانی نمی‌شود!${NC}"
        return 1
    fi
    
    # Get latest version
    echo -e "${YELLOW}📡 دریافت آخرین نسخه...${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    
    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}❌ خطا در دریافت اطلاعات نسخه!${NC}"
        return 1
    fi
    
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${LATEST_VERSION#v}_${ARCH}.tar.gz"
    
    # Download
    echo -e "${YELLOW}⬇️  دانلود Backhaul ${LATEST_VERSION}...${NC}"
    cd /tmp
    wget -q --show-progress "$DOWNLOAD_URL" -O backhaul.tar.gz
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ خطا در دانلود!${NC}"
        return 1
    fi
    
    # Extract and install
    tar -xzf backhaul.tar.gz
    chmod +x backhaul
    mv backhaul "$BINARY_PATH"
    
    # Create directories
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${GREEN}✅ Backhaul با موفقیت نصب شد!${NC}"
    return 0
}

# Create server config
create_server_config() {
    clear_screen
    echo -e "${PURPLE}🔧 تنظیمات سرور (Server)${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}پورت سرور را وارد کنید [7777]: ${NC})" SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7777}
    
    read -p "$(echo -e ${YELLOW}پسورد اتصال را وارد کنید [mypassword]: ${NC})" PASSWORD
    PASSWORD=${PASSWORD:-mypassword}
    
    # Protocol selection
    echo -e "${CYAN}پروتکل را انتخاب کنید:${NC}"
    echo "1) TCP"
    echo "2) WebSocket (WS)"
    echo "3) WebSocket Secure (WSS)"
    read -p "$(echo -e ${YELLOW}انتخاب شما [1]: ${NC})" PROTOCOL_CHOICE
    PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-1}
    
    case $PROTOCOL_CHOICE in
        1) TRANSPORT="tcp" ;;
        2) TRANSPORT="ws" ;;
        3) TRANSPORT="wss" ;;
        *) TRANSPORT="tcp" ;;
    esac
    
    # Create server config
    cat > "$CONFIG_DIR/server.toml" << EOF
[server]
bind_addr = "0.0.0.0:${SERVER_PORT}"
transport = "${TRANSPORT}"
token = "${PASSWORD}"
keepalive_period = 75
nodelay = true

[server.channel_size]
queue_size = 2048
EOF

    echo -e "${GREEN}✅ کانفیگ سرور ایجاد شد!${NC}"
    echo -e "${BLUE}📁 مسیر: $CONFIG_DIR/server.toml${NC}"
}

# Create client config  
create_client_config() {
    clear_screen
    echo -e "${PURPLE}🔧 تنظیمات کلاینت (Client)${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}آدرس IP سرور را وارد کنید: ${NC})" SERVER_IP
    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}❌ آدرس IP الزامی است!${NC}"
        return 1
    fi
    
    read -p "$(echo -e ${YELLOW}پورت سرور را وارد کنید [7777]: ${NC})" SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7777}
    
    read -p "$(echo -e ${YELLOW}پسورد اتصال را وارد کنید [mypassword]: ${NC})" PASSWORD
    PASSWORD=${PASSWORD:-mypassword}
    
    read -p "$(echo -e ${YELLOW}پورت محلی برای تانل [8080]: ${NC})" LOCAL_PORT
    LOCAL_PORT=${LOCAL_PORT:-8080}
    
    read -p "$(echo -e ${YELLOW}آدرس مقصد [127.0.0.1:22]: ${NC})" TARGET_ADDR
    TARGET_ADDR=${TARGET_ADDR:-127.0.0.1:22}
    
    # Protocol selection
    echo -e "${CYAN}پروتکل را انتخاب کنید:${NC}"
    echo "1) TCP"
    echo "2) WebSocket (WS)"  
    echo "3) WebSocket Secure (WSS)"
    read -p "$(echo -e ${YELLOW}انتخاب شما [1]: ${NC})" PROTOCOL_CHOICE
    PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-1}
    
    case $PROTOCOL_CHOICE in
        1) TRANSPORT="tcp" ;;
        2) TRANSPORT="ws" ;;
        3) TRANSPORT="wss" ;;
        *) TRANSPORT="tcp" ;;
    esac
    
    # Create client config
    cat > "$CONFIG_DIR/client.toml" << EOF
[client]
remote_addr = "${SERVER_IP}:${SERVER_PORT}"
transport = "${TRANSPORT}"
token = "${PASSWORD}"
keepalive_period = 75
retry_interval = 1
nodelay = true

[[client.services]]
local_addr = "0.0.0.0:${LOCAL_PORT}"
remote_addr = "${TARGET_ADDR}"

[client.channel_size]
queue_size = 2048
EOF

    echo -e "${GREEN}✅ کانفیگ کلاینت ایجاد شد!${NC}"
    echo -e "${BLUE}📁 مسیر: $CONFIG_DIR/client.toml${NC}"
}

# Create systemd service
create_service() {
    echo -e "${BLUE}🔧 ایجاد سرویس systemd...${NC}"
    
    echo "نوع سرویس را انتخاب کنید:"
    echo "1) Server"
    echo "2) Client"
    read -p "$(echo -e ${YELLOW}انتخاب شما: ${NC})" SERVICE_TYPE
    
    case $SERVICE_TYPE in
        1)
            CONFIG_FILE="server.toml"
            SERVICE_NAME="backhaul-server"
            ;;
        2)
            CONFIG_FILE="client.toml"
            SERVICE_NAME="backhaul-client"
            ;;
        *)
            echo -e "${RED}❌ انتخاب نامعتبر!${NC}"
            return 1
            ;;
    esac
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Backhaul ${SERVICE_TYPE^}
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=3
User=root
ExecStart=${BINARY_PATH} -c ${CONFIG_DIR}/${CONFIG_FILE}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    echo -e "${GREEN}✅ سرویس ${SERVICE_NAME} ایجاد شد!${NC}"
}

# Service management
manage_service() {
    clear_screen
    echo -e "${PURPLE}🔧 مدیریت سرویس${NC}"
    echo ""
    
    # List available services
    echo -e "${CYAN}سرویس‌های موجود:${NC}"
    ls /etc/systemd/system/backhaul-* 2>/dev/null | sed 's|/etc/systemd/system/||' | sed 's|.service||' | nl
    echo ""
    
    read -p "$(echo -e ${YELLOW}نام سرویس را وارد کنید: ${NC})" SERVICE_NAME
    
    if [ -z "$SERVICE_NAME" ]; then
        echo -e "${RED}❌ نام سرویس الزامی است!${NC}"
        return 1
    fi
    
    echo ""
    echo "عملیات مورد نظر را انتخاب کنید:"
    echo "1) شروع سرویس"
    echo "2) توقف سرویس" 
    echo "3) ری‌استارت سرویس"
    echo "4) وضعیت سرویس"
    echo "5) مشاهده لاگ"
    echo "6) فعال‌سازی خودکار"
    echo "7) غیرفعال‌سازی خودکار"
    
    read -p "$(echo -e ${YELLOW}انتخاب شما: ${NC})" ACTION
    
    case $ACTION in
        1) systemctl start "$SERVICE_NAME" && echo -e "${GREEN}✅ سرویس شروع شد${NC}" ;;
        2) systemctl stop "$SERVICE_NAME" && echo -e "${GREEN}✅ سرویس متوقف شد${NC}" ;;
        3) systemctl restart "$SERVICE_NAME" && echo -e "${GREEN}✅ سرویس ری‌استارت شد${NC}" ;;
        4) systemctl status "$SERVICE_NAME" ;;
        5) journalctl -u "$SERVICE_NAME" -f ;;
        6) systemctl enable "$SERVICE_NAME" && echo -e "${GREEN}✅ سرویس فعال شد${NC}" ;;
        7) systemctl disable "$SERVICE_NAME" && echo -e "${GREEN}✅ سرویس غیرفعال شد${NC}" ;;
        *) echo -e "${RED}❌ انتخاب نامعتبر!${NC}" ;;
    esac
}

# View logs
view_logs() {
    echo -e "${BLUE}📋 مشاهده لاگ‌ها${NC}"
    echo ""
    
    if [ -f "$LOG_FILE" ]; then
        tail -n 50 "$LOG_FILE"
    else
        echo "لاگ‌های systemd:"
        journalctl -u backhaul-* --no-pager -n 50
    fi
}

# Uninstall Backhaul
uninstall_backhaul() {
    clear_screen
    echo -e "${RED}🗑️  حذف Backhaul${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  این عمل تمام فایل‌ها و تنظیمات را حذف خواهد کرد!${NC}"
    read -p "$(echo -e ${RED}آیا مطمئن هستید؟ [y/N]: ${NC})" CONFIRM
    
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        # Stop and disable services
        systemctl stop backhaul-* 2>/dev/null
        systemctl disable backhaul-* 2>/dev/null
        
        # Remove files
        rm -f /etc/systemd/system/backhaul-*.service
        rm -rf "$CONFIG_DIR"
        rm -f "$BINARY_PATH"
        rm -f "$LOG_FILE"
        
        systemctl daemon-reload
        
        echo -e "${GREEN}✅ Backhaul به طور کامل حذف شد!${NC}"
    else
        echo -e "${YELLOW}❌ عملیات لغو شد${NC}"
    fi
}

# Update Backhaul
update_backhaul() {
    echo -e "${BLUE}🔄 به‌روزرسانی Backhaul...${NC}"
    
    # Check current version
    if [ -f "$BINARY_PATH" ]; then
        CURRENT_VERSION=$($BINARY_PATH --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown")
        echo -e "${CYAN}نسخه فعلی: $CURRENT_VERSION${NC}"
    fi
    
    # Stop services
    systemctl stop backhaul-* 2>/dev/null
    
    # Install new version
    if install_backhaul; then
        # Restart services
        systemctl start backhaul-* 2>/dev/null
        echo -e "${GREEN}✅ به‌روزرسانی انجام شد!${NC}"
    else
        echo -e "${RED}❌ خطا در به‌روزرسانی!${NC}"
    fi
}

# Main menu
show_menu() {
    clear_screen
    echo -e "${WHITE}🎯 منوی اصلی:${NC}"
    echo ""
    echo -e "${CYAN}1)${NC}  نصب Backhaul"
    echo -e "${CYAN}2)${NC}  ایجاد کانفیگ سرور"
    echo -e "${CYAN}3)${NC}  ایجاد کانفیگ کلاینت"
    echo -e "${CYAN}4)${NC}  ایجاد سرویس systemd"
    echo -e "${CYAN}5)${NC}  مدیریت سرویس"
    echo -e "${CYAN}6)${NC}  مشاهده لاگ‌ها"
    echo -e "${CYAN}7)${NC}  به‌روزرسانی"
    echo -e "${CYAN}8)${NC}  حذف کامل"
    echo -e "${CYAN}0)${NC}  خروج"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main function
main() {
    check_root
    
    while true; do
        show_menu
        read -p "$(echo -e ${YELLOW}انتخاب شما: ${NC})" choice
        echo ""
        
        case $choice in
            1) install_backhaul ;;
            2) create_server_config ;;
            3) create_client_config ;;
            4) create_service ;;
            5) manage_service ;;
            6) view_logs ;;
            7) update_backhaul ;;
            8) uninstall_backhaul ;;
            0) 
                echo -e "${GREEN}👋 خروج از برنامه${NC}"
                exit 0 
                ;;
            *)
                echo -e "${RED}❌ انتخاب نامعتبر! لطفاً دوباره تلاش کنید.${NC}"
                ;;
        esac
        
        echo ""
        read -p "$(echo -e ${YELLOW}برای ادامه Enter را فشار دهید...${NC})"
    done
}

# Run main function
main
