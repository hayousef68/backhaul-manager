#!/bin/bash

# ====================================================================
#
#          🚀 Backhaul Manager v2.0 🚀
#
#   A complete management script for the Backhaul reverse tunnel.
#   Inspired by rathole_v2.sh, powered by Backhaul core logic.
#   Github: https://github.com/Musixal/Backhaul
#
# ====================================================================

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "خطا: این اسکریپت باید با دسترسی root اجرا شود. لطفا از دستور 'sudo' استفاده کنید."
   sleep 1
   exit 1
fi

# --- Global Variables and Configuration ---

# Directories and Files
BACKHAUL_DIR="/opt/backhaul"
CONFIG_DIR="/etc/backhaul"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log/backhaul"
BINARY_PATH="$BACKHAUL_DIR/backhaul"
TUNNELS_DIR="$CONFIG_DIR/tunnels"

# --- UI Helper Functions ---

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Print colored output
print_color() {
    printf "${1}${2}${NC}\n"
}

# Wait for user to press Enter
press_key(){
    read -p "برای ادامه، کلید Enter را فشار دهید..."
}

# Display header and logo
print_header() {
    clear
    print_color $CYAN "======================================================================"
    cat << "EOF"
               __               __  __          __
   ____  ____ _/ /_  ____ ______/ / / /_  ____  / /_
  / __ \/ __ `/ __ \/ __ `/ ___/ / / / / / __ \/ __/
 / /_/ / /_/ / / / / /_/ / /__/ /_/ / /_/ / / / /_
/ .___/\__,_/_/ /_/\__,_/\___/\____/ .___/_/ /_/\__/
/_/                               /_/
EOF
    print_color $CYAN "======================================================================"
    print_color $WHITE "           🚀 Backhaul Manager v2.0 - راهکار مدیریت تونل 🚀"
    echo
}

# --- Core Logic Functions ---

# Create necessary directories
create_directories() {
    sudo mkdir -p "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TUNNELS_DIR"
    sudo chmod -R 755 "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TUNNELS_DIR"
}

# Detect system architecture and OS
detect_system() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64) ARCH="amd64" ;;
        i386|i686) ARCH="386" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="arm" ;;
        *)
            print_color $RED "❌ معماری پشتیبانی نمی‌شود: $ARCH"
            exit 1
            ;;
    esac

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case $OS in
        linux) OS="linux" ;;
        darwin) OS="darwin" ;;
        *)
            print_color $RED "❌ سیستم‌عامل پشتیبانی نمی‌شود: $OS"
            exit 1
            ;;
    esac
    
    print_color $GREEN "🔍 سیستم شناسایی شد: $OS-$ARCH"
}

# Get the latest version from GitHub
get_latest_version() {
    print_color $YELLOW "🔄 در حال بررسی آخرین نسخه Backhaul..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_VERSION" ]; then
        print_color $RED "❌ دریافت آخرین نسخه با شکست مواجه شد."
        exit 1
    fi
    print_color $GREEN "✅ آخرین نسخه: $LATEST_VERSION"
}

# Generate configuration file
generate_config() {
    local mode=$1; local tunnel_name=$2; local transport=$3; local bind_addr=$4
    local remote_addr=$5; local token=$6; local ports_config=$7; local edge_ip=$8
    
    local config_file="$TUNNELS_DIR/${tunnel_name}.toml"
    
    # Server (Iran) Config
    if [ "$mode" == "server" ]; then
        cat > "$config_file" << EOF
[server]
bind_addr = "$bind_addr"
transport = "$transport"
token = "$token"
keepalive_period = 75
nodelay = true
heartbeat = 40
channel_size = 2048
sniffer = false
web_port = 0 # Disabled by default
sniffer_log = "$LOG_DIR/${tunnel_name}.json"
log_level = "info"
accept_udp = false
EOF
        if [[ "$transport" == "wss" || "$transport" == "wssmux" ]]; then
            cat >> "$config_file" << EOF
tls_cert = "$CONFIG_DIR/certs/server.crt"
tls_key = "$CONFIG_DIR/certs/server.key"
EOF
        fi
        if [[ "$transport" == "tcpmux" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
            cat >> "$config_file" << EOF
[server.mux]
con = 8
version = 1
framesize = 32768
recievebuffer = 4194304
streambuffer = 65536
EOF
        fi
        if [ ! -z "$ports_config" ]; then
            echo "ports = [" >> "$config_file"
            IFS=',' read -ra PORTS <<< "$ports_config"
            for port in "${PORTS[@]}"; do
                echo "    \"$port\"," >> "$config_file"
            done
            echo "]" >> "$config_file"
        else
            echo "ports = []" >> "$config_file"
        fi

    # Client (Kharej) Config
    else
        cat > "$config_file" << EOF
[client]
remote_addr = "$remote_addr"
transport = "$transport"
token = "$token"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
retry_interval = 3
nodelay = true
sniffer = false
web_port = 0 # Disabled by default
sniffer_log = "$LOG_DIR/${tunnel_name}.json"
log_level = "info"
EOF
        if [[ "$transport" == "ws" || "$transport" == "wss" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
            echo "edge_ip = \"$edge_ip\"" >> "$config_file"
        fi
        if [[ "$transport" == "tcpmux" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
            cat >> "$config_file" << EOF
[client.mux]
version = 1
framesize = 32768
recievebuffer = 4194304
streambuffer = 65536
EOF
        fi
    fi
}

# Create systemd service file
create_service() {
    local tunnel_name=$1
    local config_file="$TUNNELS_DIR/${tunnel_name}.toml"
    local service_file="$SERVICE_DIR/backhaul-${tunnel_name}.service"
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Backhaul Tunnel Service - $tunnel_name
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$BINARY_PATH -c $config_file
Restart=always
RestartSec=3
User=root
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "backhaul-${tunnel_name}.service"
}

# Check for required commands
check_requirements() {
    local missing_commands=()
    for cmd in curl tar systemctl openssl; do
        if ! command -v $cmd &> /dev/null; then
            missing_commands+=($cmd)
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        print_color $RED "❌ دستورات مورد نیاز یافت نشد: ${missing_commands[*]}"
        print_color $YELLOW "در حال تلاش برای نصب خودکار..."
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y curl tar systemd openssl
        elif command -v yum &> /dev/null; then
            sudo yum install -y curl tar systemd openssl
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y curl tar systemd openssl
        else
            print_color $RED "❌ مدیر بسته پشتیبانی نمی‌شود. لطفا به صورت دستی نصب کنید."
            exit 1
        fi
    fi
}

# --- User-Facing Menu Functions ---

# 1. Install Backhaul
install_backhaul() {
    print_header
    print_color $YELLOW "📦 در حال نصب Backhaul..."
    
    detect_system
    get_latest_version
    
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${OS}_${ARCH}.tar.gz"
    
    print_color $YELLOW "📥 در حال دانلود از: $DOWNLOAD_URL"
    
    cd /tmp
    if ! curl -L -o "backhaul.tar.gz" "$DOWNLOAD_URL"; then
        print_color $RED "❌ دانلود با شکست مواجه شد."
        exit 1
    fi
    
    if ! tar -xzf backhaul.tar.gz; then
        print_color $RED "❌ استخراج فایل با شکست مواجه شد."
        exit 1
    fi
    
    create_directories
    sudo mv backhaul "$BINARY_PATH"
    sudo chmod +x "$BINARY_PATH"
    sudo ln -sf "$BINARY_PATH" /usr/local/bin/backhaul
    
    print_color $GREEN "✅ Backhaul با موفقیت نصب شد!"
    print_color $GREEN "📍 مسیر فایل اجرایی: $BINARY_PATH"
    
    press_key
}

# 2. Update Backhaul
update_backhaul() {
    print_header
    print_color $YELLOW "🔄 در حال به‌روزرسانی Backhaul..."
    
    current_version=$($BINARY_PATH --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    
    get_latest_version
    
    if [ "$current_version" == "$LATEST_VERSION" ]; then
        print_color $GREEN "✅ شما در حال حاضر از آخرین نسخه ($LATEST_VERSION) استفاده می‌کنید."
        press_key
        return
    fi
    
    print_color $YELLOW "📦 نسخه فعلی: $current_version"
    print_color $YELLOW "🆕 آخرین نسخه: $LATEST_VERSION"
    
    read -p "آیا می‌خواهید ادامه دهید؟ (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return
    fi
    
    print_color $YELLOW "⏸️ در حال توقف تمام سرویس‌های تونل..."
    for service in $(systemctl list-units --type=service --state=running | grep 'backhaul-' | awk '{print $1}'); do
        sudo systemctl stop "$service"
    done
    
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${OS}_${ARCH}.tar.gz"
    cd /tmp
    curl -L -o "backhaul_new.tar.gz" "$DOWNLOAD_URL"
    tar -xzf backhaul_new.tar.gz
    sudo mv backhaul "$BINARY_PATH"
    sudo chmod +x "$BINARY_PATH"
    
    print_color $YELLOW "🔄 در حال راه‌اندازی مجدد سرویس‌های تونل..."
    for service in $(systemctl list-units --type=service --all | grep 'backhaul-' | awk '{print $1}'); do
        sudo systemctl start "$service"
    done
    
    print_color $GREEN "✅ Backhaul با موفقیت به نسخه $LATEST_VERSION به‌روزرسانی شد!"
    press_key
}

# 3. Generate TLS Certificate
generate_tls_cert() {
    print_header
    print_color $YELLOW "🔒 در حال ساخت گواهی TLS..."
    
    read -p "لطفا دامنه یا آدرس IP را وارد کنید (پیش‌فرض: localhost): " domain
    [ -z "$domain" ] && domain="localhost"
    
    CERT_DIR="$CONFIG_DIR/certs"
    sudo mkdir -p "$CERT_DIR"
    
    sudo openssl req -x509 -nodes -newkey rsa:2048 -keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" -days 3650 -subj "/CN=$domain"
    sudo chmod 600 "$CERT_DIR/server.key"
    
    print_color $GREEN "✅ گواهی TLS با موفقیت ساخته شد!"
    print_color $GREEN "📍 مسیر گواهی: $CERT_DIR/server.crt"
    print_color $GREEN "📍 مسیر کلید خصوصی: $CERT_DIR/server.key"
    
    press_key
}

# 4. Create Iran Server Tunnel
create_server_tunnel() {
    print_header
    print_color $GREEN "🇮🇷 ساخت تونل سرور ایران (Server)"
    echo
    
    read -p "یک نام برای تونل وارد کنید: " tunnel_name
    if [ -z "$tunnel_name" ]; then
        print_color $RED "❌ نام تونل نمی‌تواند خالی باشد."
        sleep 2; return
    fi
    
    print_color $CYAN "پروتکل‌های ارتباطی موجود:"
    echo "1) tcp      2) tcpmux   3) udp      4) ws"
    echo "5) wss      6) wsmux    7) wssmux"
    read -p "پروتکل مورد نظر را انتخاب کنید (پیش‌فرض: tcp): " choice
    case $choice in
        1) transport="tcp" ;; 2) transport="tcpmux" ;; 3) transport="udp" ;;
        4) transport="ws" ;; 5) transport="wss" ;; 6) transport="wsmux" ;;
        7) transport="wssmux" ;; *) transport="tcp" ;;
    esac
    
    read -p "آدرس bind را وارد کنید (پیش‌فرض: 0.0.0.0:3080): " bind_addr
    [ -z "$bind_addr" ] && bind_addr="0.0.0.0:3080"
    
    read -p "توکن احراز هویت را وارد کنید (برای ساخت خودکار Enter بزنید): " token
    [ -z "$token" ] && token=$(openssl rand -hex 16) && print_color $YELLOW "🔑 توکن ساخته شد: $token"
    
    print_color $CYAN "مثال برای تنظیمات پورت (با کاما جدا کنید):"
    print_color $WHITE "443         (گوش دادن روی پورت 443)"
    print_color $WHITE "443-600     (گوش دادن روی بازه پورت 443 تا 600)"
    print_color $WHITE "443=5201    (دریافت روی 443 و ارسال به 5201)"
    print_color $WHITE "443=1.1.1.1:5201 (دریافت روی 443 و ارسال به 1.1.1.1:5201)"
    read -p "تنظیمات پورت‌ها را وارد کنید (برای رد شدن Enter بزنید): " ports_config
    
    if [[ "$transport" == "wss" || "$transport" == "wssmux" ]]; then
        if [ ! -f "$CONFIG_DIR/certs/server.crt" ]; then
            print_color $YELLOW "⚠️ برای این پروتکل به گواهی SSL نیاز است."
            read -p "آیا می‌خواهید اکنون گواهی بسازید؟ (y/n): " gen_ssl
            if [[ "$gen_ssl" == "y" || "$gen_ssl" == "Y" ]]; then
                generate_tls_cert
            else
                print_color $RED "❌ عملیات لغو شد."
                sleep 2; return
            fi
        fi
    fi
    
    generate_config "server" "$tunnel_name" "$transport" "$bind_addr" "" "$token" "$ports_config" ""
    create_service "$tunnel_name"
    sudo systemctl start "backhaul-${tunnel_name}.service"
    
    print_color $GREEN "✅ تونل سرور '$tunnel_name' با موفقیت ساخته و اجرا شد!"
    print_color $PURPLE "   - نام: $tunnel_name"
    print_color $PURPLE "   - конфиг: $TUNNELS_DIR/${tunnel_name}.toml"
    print_color $PURPLE "   - توکن: $token"
    
    press_key
}

# 5. Create Kharej Client Tunnel
create_client_tunnel() {
    print_header
    print_color $BLUE "🌍 ساخت تونل کلاینت خارج (Client)"
    echo
    
    read -p "یک نام برای تونل وارد کنید: " tunnel_name
    if [ -z "$tunnel_name" ]; then
        print_color $RED "❌ نام تونل نمی‌تواند خالی باشد."
        sleep 2; return
    fi
    
    print_color $CYAN "پروتکل‌های ارتباطی موجود:"
    echo "1) tcp      2) tcpmux   3) udp      4) ws"
    echo "5) wss      6) wsmux    7) wssmux"
    read -p "پروتکل مورد نظر را انتخاب کنید (پیش‌فرض: tcp): " choice
    case $choice in
        1) transport="tcp" ;; 2) transport="tcpmux" ;; 3) transport="udp" ;;
        4) transport="ws" ;; 5) transport="wss" ;; 6) transport="wsmux" ;;
        7) transport="wssmux" ;; *) transport="tcp" ;;
    esac
    
    read -p "آدرس سرور ایران را وارد کنید (IP:PORT): " remote_addr
    if [ -z "$remote_addr" ]; then
        print_color $RED "❌ آدرس سرور نمی‌تواند خالی باشد."
        sleep 2; return
    fi
    
    read -p "توکن احراز هویت را وارد کنید: " token
    if [ -z "$token" ]; then
        print_color $RED "❌ توکن نمی‌تواند خالی باشد."
        sleep 2; return
    fi
    
    local edge_ip=""
    if [[ "$transport" == "ws" || "$transport" == "wss" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
        read -p "آدرس Edge IP را وارد کنید (اختیاری، برای CDN): " edge_ip
    fi
    
    generate_config "client" "$tunnel_name" "$transport" "" "$remote_addr" "$token" "" "$edge_ip"
    create_service "$tunnel_name"
    sudo systemctl start "backhaul-${tunnel_name}.service"
    
    print_color $GREEN "✅ تونل کلاینت '$tunnel_name' با موفقیت ساخته و اجرا شد!"
    print_color $PURPLE "   - نام: $tunnel_name"
    print_color $PURPLE "   - конфиг: $TUNNELS_DIR/${tunnel_name}.toml"
    print_color $PURPLE "   - سرور مقصد: $remote_addr"
    
    press_key
}

# 6. List All Tunnels
list_tunnels() {
    print_header
    print_color $CYAN "📋 لیست تمام تونل‌ها"
    echo
    
    if [ -z "$(ls -A $TUNNELS_DIR/*.toml 2>/dev/null)" ]; then
        print_color $YELLOW "⚠️ هیچ تونلی یافت نشد."
        press_key
        return
    fi
    
    printf "%-20s %-15s %-15s %-22s %-25s\n" "NAMA" "JENIS" "PROTOKOL" "STATUS" "ALAMAT"
    printf "%-20s %-15s %-15s %-22s %-25s\n" "----" "----" "--------" "------" "-------"
    
    for config_file in "$TUNNELS_DIR"/*.toml; do
        tunnel_name=$(basename "$config_file" .toml)
        
        if grep -q "\[server\]" "$config_file"; then
            tunnel_type="🇮🇷 Iran (Server)"
            address=$(grep "bind_addr" "$config_file" | cut -d'"' -f2)
        else
            tunnel_type="🌍 Kharej (Client)"
            address=$(grep "remote_addr" "$config_file" | cut -d'"' -f2)
        fi
        
        transport=$(grep "transport" "$config_file" | cut -d'"' -f2)
        
        if systemctl is-active --quiet "backhaul-${tunnel_name}.service"; then
            status="${GREEN}●${NC} Fa'al"
        else
            status="${RED}●${NC} Ghair-fa'al"
        fi
        
        printf "%-20s %-15s %-15s %-22s %-25s\n" "$tunnel_name" "$tunnel_type" "$transport" "$status" "$address"
    done
    
    echo
    press_key
}

# 7. Manage Tunnel
manage_tunnel() {
    print_header
    print_color $YELLOW "🔧 مدیریت تونل‌ها"
    echo

    if [ -z "$(ls -A $TUNNELS_DIR/*.toml 2>/dev/null)" ]; then
        print_color $YELLOW "⚠️ هیچ تونلی برای مدیریت یافت نشد."
        press_key; return
    fi
    
    print_color $CYAN "تونل مورد نظر را انتخاب کنید:"
    i=1
    declare -a tunnel_names
    for config_file in "$TUNNELS_DIR"/*.toml; do
        tunnel_name=$(basename "$config_file" .toml)
        tunnel_names[$i]=$tunnel_name
        printf "%d) %s\n" $i "$tunnel_name"
        ((i++))
    done
    echo
    read -p "شماره تونل را وارد کنید: " tunnel_num
    
    if ! [[ "$tunnel_num" =~ ^[0-9]+$ ]] || [ "$tunnel_num" -lt 1 ] || [ "$tunnel_num" -ge "$i" ]; then
        print_color $RED "❌ انتخاب نامعتبر است."; sleep 2; return
    fi
    
    selected_tunnel=${tunnel_names[$tunnel_num]}
    service_name="backhaul-${selected_tunnel}.service"

    clear
    print_header
    print_color $CYAN "عملیات مورد نظر برای تونل '$selected_tunnel' را انتخاب کنید:"
    echo "1) شروع (Start)"
    echo "2) توقف (Stop)"
    echo "3) راه‌اندازی مجدد (Restart)"
    echo "4) نمایش وضعیت (Status)"
    echo "5) نمایش لاگ‌ها (Logs)"
    echo "6) مشاهده کانفیگ (View Config)"
    print_color $RED "7) حذف تونل (Delete)"
    echo
    read -p "عملیات را انتخاب کنید (1-7): " action
    
    case $action in
        1) sudo systemctl start "$service_name"; print_color $GREEN "✅ تونل شروع شد." ;;
        2) sudo systemctl stop "$service_name"; print_color $YELLOW "⏹️ تونل متوقف شد." ;;
        3) sudo systemctl restart "$service_name"; print_color $GREEN "🔄 تونل مجددا راه‌اندازی شد." ;;
        4) sudo systemctl status "$service_name" ;;
        5) journalctl -u "$service_name" -n 50 -f ;;
        6) print_color $CYAN "📄 کانفیگ برای '$selected_tunnel':"; cat "$TUNNELS_DIR/${selected_tunnel}.toml" ;;
        7) 
            read -p "آیا از حذف تونل '$selected_tunnel' مطمئن هستید؟ (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                sudo systemctl stop "$service_name"
                sudo systemctl disable "$service_name"
                sudo rm -f "$SERVICE_DIR/$service_name"
                sudo rm -f "$TUNNELS_DIR/${selected_tunnel}.toml"
                sudo systemctl daemon-reload
                print_color $GREEN "✅ تونل با موفقیت حذف شد."
            fi
            ;;
        *) print_color $RED "❌ عملیات نامعتبر." ;;
    esac
    
    if [[ "$action" != "4" && "$action" != "5" ]]; then
        press_key
    fi
}

# 8. Uninstall Backhaul
uninstall_backhaul() {
    print_header
    print_color $RED "🗑️ حذف کامل Backhaul"
    echo
    print_color $YELLOW "⚠️ هشدار: این عملیات موارد زیر را حذف خواهد کرد:"
    print_color $WHITE "- تمام کانفیگ‌ها و سرویس‌های تونل"
    print_color $WHITE "- فایل اجرایی Backhaul و دایرکتوری‌های مربوطه"
    echo
    read -p "برای تایید، عبارت 'YES' را تایپ کنید: " confirm
    if [ "$confirm" != "YES" ]; then
        print_color $GREEN "❌ عملیات حذف لغو شد."
        press_key
        return
    fi
    
    for service in $(systemctl list-units --type=service --all | grep 'backhaul-' | awk '{print $1}'); do
        sudo systemctl stop "$service"
        sudo systemctl disable "$service"
    done
    
    sudo rm -rf "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR"
    sudo rm -f /usr/local/bin/backhaul
    sudo rm -f $SERVICE_DIR/backhaul-*.service
    sudo systemctl daemon-reload
    
    print_color $GREEN "✅ Backhaul با موفقیت حذف شد."
    read -p "برای خروج Enter را فشار دهید..."
    exit 0
}

# Main Menu
show_main_menu() {
    while true; do
        print_header
        
        # Display Server Info
        if [ -f "$BINARY_PATH" ]; then
            version=$($BINARY_PATH --version 2>/dev/null | head -1 || echo "نامشخص")
            print_color $WHITE "وضعیت سیستم: ${GREEN}نصب شده (نسخه: $version)${NC}"
        else
            print_color $WHITE "وضعیت سیستم: ${RED}نصب نشده${NC}"
        fi
        tunnel_count=$(ls -1q "$TUNNELS_DIR"/*.toml 2>/dev/null | wc -l)
        print_color $WHITE "تعداد تونل‌ها: ${YELLOW}${tunnel_count}${NC}"
        print_color $CYAN "----------------------------------------------------------------------"
        
        # Menu Options
        print_color $GREEN "   --- نصب و به‌روزرسانی ---"
        print_color $WHITE "   1. نصب یا переустановка Backhaul"
        print_color $WHITE "   2. به‌روزرسانی Backhaul"
        print_color $WHITE "   3. ساخت گواهی TLS"
        
        print_color $BLUE "\n   --- مدیریت تونل ---"
        print_color $WHITE "   4. 🇮🇷 ساخت تونل سرور ایران"
        print_color $WHITE "   5. 🌍 ساخت تونل کلاینت خارج"
        print_color $WHITE "   6. 📋 لیست تمام تونل‌ها"
        print_color $WHITE "   7. 🔧 مدیریت یک تونل"
        
        print_color $RED "\n   --- نگهداری ---"
        print_color $WHITE "   8. حذف کامل Backhaul"
        
        print_color $YELLOW "\n   0. خروج"
        print_color $CYAN "----------------------------------------------------------------------"
        
        read -p "گزینه مورد نظر را انتخاب کنید [0-8]: " choice
        
        case $choice in
            1) install_backhaul ;;
            2) update_backhaul ;;
            3) generate_tls_cert ;;
            4) create_server_tunnel ;;
            5) create_client_tunnel ;;
            6) list_tunnels ;;
            7) manage_tunnel ;;
            8) uninstall_backhaul ;;
            0) print_color $GREEN "👋 با تشکر از استفاده شما!"; exit 0 ;;
            *) print_color $RED "❌ گزینه نامعتبر است. لطفا دوباره تلاش کنید."; sleep 2 ;;
        esac
    done
}

# --- Main Execution ---
main() {
    check_requirements
    create_directories
    
    if [ ! -f "$BINARY_PATH" ]; then
        print_header
        print_color $YELLOW "🎉 به مدیر Backhaul خوش آمدید!"
        print_color $WHITE "به نظر می‌رسد Backhaul هنوز نصب نشده است."
        read -p "آیا می‌خواهید اکنون آن را نصب کنید؟ (y/n): " install_now
        if [[ "$install_now" == "y" || "$install_now" == "Y" ]]; then
            install_backhaul
        fi
    fi
    
    show_main_menu
}

main "$@"
