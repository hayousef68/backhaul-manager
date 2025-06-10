#!/bin/bash

# Backhaul Auto Setup Script
# Version: 2.3 (Auto-Arch Detection for v0.6.5)
# Author: hayousef68
# Improvements by Google Gemini

# --- Colors for better UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- Global variables ---
CONFIG_DIR="/etc/backhaul"
BINARY_PATH="/usr/local/bin/backhaul"

# --- Functions ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${NC}"
        exit 1
    fi
}

# This function now intelligently installs the correct version for the system architecture.
install_backhaul() {
    echo -e "${BLUE}Installing Backhaul v0.6.5 with Auto Architecture Detection...${NC}"
    
    # Detect architecture and set the correct download suffix
    local ARCH_SUFFIX
    case $(uname -m) in
        x86_64)
            ARCH_SUFFIX="amd64"
            ;;
        aarch64 | arm64)
            ARCH_SUFFIX="arm64"
            ;;
        *)
            echo -e "${RED}Error: Unsupported system architecture '$(uname -m)'!${NC}"
            echo -e "${YELLOW}This script only supports amd64 (x86_64) and arm64.${NC}"
            return 1
            ;;
    esac
    
    echo -e "${CYAN}Detected Architecture: $(uname -m) -> Using '${ARCH_SUFFIX}' package.${NC}"

    # Construct the download URL based on detected architecture
    local DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_${ARCH_SUFFIX}.tar.gz"
    
    echo -e "${YELLOW}Downloading from ${DOWNLOAD_URL}...${NC}"
    cd /tmp
    if ! wget -q --show-progress "$DOWNLOAD_URL" -O backhaul.tar.gz; then
        echo -e "${RED}Error: Download failed! Please check the URL or your network connection.${NC}"
        return 1
    fi
    
    tar -xzf backhaul.tar.gz
    chmod +x backhaul
    mv backhaul "$BINARY_PATH"
    
    mkdir -p "$CONFIG_DIR"
    rm -f /tmp/backhaul.tar.gz
    echo -e "${GREEN}Backhaul v0.6.5 for ${ARCH_SUFFIX} installed successfully!${NC}"
}


create_config() {
    local ROLE=$1
    clear
    if [ "$ROLE" == "server" ]; then
        echo -e "${PURPLE}Server Configuration${NC}"
        read -p "Enter server port [443]: " SERVER_PORT; SERVER_PORT=${SERVER_PORT:-443}
        read -p "Enter connection password [mypassword]: " PASSWORD; PASSWORD=${PASSWORD:-mypassword}
        
        cat > "$CONFIG_DIR/server.toml" << EOF
[server]
bind_addr = "0.0.0.0:${SERVER_PORT}"
transport = "wss"
token = "${PASSWORD}"
keepalive_period = 75
nodelay = true
heartbeat = 40
sni = "cloudflare.com"

[server.channel_size]
queue_size = 2048
EOF
        echo -e "${GREEN}Server config created: $CONFIG_DIR/server.toml${NC}"
    else
        echo -e "${PURPLE}Client Configuration${NC}"
        read -p "Enter server IP address: " SERVER_IP
        read -p "Enter server port [443]: " SERVER_PORT; SERVER_PORT=${SERVER_PORT:-443}
        read -p "Enter connection password [mypassword]: " PASSWORD; PASSWORD=${PASSWORD:-mypassword}
        read -p "Enter local port to listen on [8080]: " LOCAL_PORT; LOCAL_PORT=${LOCAL_PORT:-8080}
        read -p "Enter target port on the other server (e.g., 22 for SSH) [22]: " TARGET_PORT; TARGET_PORT=${TARGET_PORT:-22}
        
        cat > "$CONFIG_DIR/client.toml" << EOF
[client]
remote_addr = "${SERVER_IP}:${SERVER_PORT}"
transport = "wss"
token = "${PASSWORD}"
keepalive_period = 75
retry_interval = 1
nodelay = true
heartbeat = 40
sni = "cloudflare.com"

[[client.services]]
local_addr = "0.0.0.0:${LOCAL_PORT}"
remote_addr = "127.0.0.1:${TARGET_PORT}"

[client.channel_size]
queue_size = 2048
EOF
        echo -e "${GREEN}Client config created: $CONFIG_DIR/client.toml${NC}"
    fi
}

manage_service() {
    clear
    echo "Select service type to create/manage:"
    echo "1) Server"
    echo "2) Client"
    read -p "Enter your choice: " SERVICE_CHOICE

    case $SERVICE_CHOICE in
        1) CONFIG_FILE="server.toml"; SERVICE_NAME="backhaul-server" ;;
        2) CONFIG_FILE="client.toml"; SERVICE_NAME="backhaul-client" ;;
        *) echo -e "${RED}Invalid selection!${NC}"; return ;;
    esac

    if [ ! -f "$CONFIG_DIR/$CONFIG_FILE" ]; then
        echo -e "${RED}Config file $CONFIG_DIR/$CONFIG_FILE not found! Please create it first.${NC}"
        return
    fi
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Backhaul Tunnel Service (${SERVICE_NAME})
After=network.target
StartLimitIntervalSec=0
[Service]
Type=simple
Restart=always
RestartSec=3
User=root
ExecStart=${BINARY_PATH} -c ${CONFIG_DIR}/${CONFIG_FILE}
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl restart "${SERVICE_NAME}"
    echo -e "${GREEN}Service ${SERVICE_NAME} created and started successfully!${NC}"
}

uninstall_backhaul() {
    clear
    echo -e "${RED}This will stop and remove all backhaul services, configs, and the binary.${NC}"
    read -p "Are you sure? Enter 'yes' to confirm: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${YELLOW}Uninstallation cancelled.${NC}"
        return
    fi
    systemctl stop backhaul-server backhaul-client &>/dev/null
    systemctl disable backhaul-server backhaul-client &>/dev/null
    rm -f /etc/systemd/system/backhaul-*.service
    systemctl daemon-reload
    rm -rf "$CONFIG_DIR"
    rm -f "$BINARY_PATH"
    echo -e "${GREEN}Backhaul has been completely uninstalled.${NC}"
}

show_status() {
    clear
    echo -e "${CYAN}=========== Backhaul Manager v2.3 (Auto-Arch Detect) ===========${NC}"
    
    if [ -f "$BINARY_PATH" ]; then
        local VERSION=$($BINARY_PATH -V 2>/dev/null || echo "v0.6.5")
        echo -e " ${GREEN}●${NC} Backhaul: ${WHITE}Installed (${VERSION})${NC}"
    else
        echo -e " ${RED}●${NC} Backhaul: ${YELLOW}Not Installed${NC}"
        echo -e "${CYAN}=================================================================${NC}"
        return
    fi

    if systemctl is-active --quiet backhaul-server; then
        local PORT=$(grep 'bind_addr' $CONFIG_DIR/server.toml | cut -d'"' -f2)
        echo -e " ${GREEN}●${NC} Server Service: ${WHITE}Active | Listening on: ${PORT}${NC}"
    else
        echo -e " ${RED}●${NC} Server Service: ${YELLOW}Inactive${NC}"
    fi

    if systemctl is-active --quiet backhaul-client; then
        local PORT=$(grep 'local_addr' $CONFIG_DIR/client.toml | cut -d'"' -f2)
        local TARGET_SERVER=$(grep 'remote_addr' $CONFIG_DIR/client.toml | head -n 1 | cut -d'"' -f2)
        echo -e " ${GREEN}●${NC} Client Service: ${WHITE}Active | Port ${PORT} -> ${TARGET_SERVER}${NC}"
    else
        echo -e " ${RED}●${NC} Client Service: ${YELLOW}Inactive${NC}"
    fi
    echo -e "${CYAN}=================================================================${NC}"
}

main_menu() {
    show_status
    echo ""
    echo -e "${PURPLE}Select an option:${NC}"
    echo " 1) Install Backhaul (v0.6.5, Auto-Arch)"
    echo " 2) Configure Server"
    echo " 3) Configure Client"
    echo " 4) Create & Start Service"
    echo ""
    echo -e "${CYAN}--- Management ---${NC}"
    echo " 5) Restart Services"
    echo " 6) Stop Services"
    echo " 7) View Server Logs"
    echo " 8) View Client Logs"
    echo " 9) Uninstall Backhaul"
    echo " 0) Exit"
    echo ""
    read -p "Enter your choice [0-9]: " choice
    
    case $choice in
        1) install_backhaul ;;
        2) create_config "server" ;;
        3) create_config "client" ;;
        4) manage_service ;;
        5) systemctl restart backhaul-server backhaul-client &>/dev/null && echo -e "${GREEN}Services restarted.${NC}" || echo -e "${YELLOW}No active services to restart.${NC}" ;;
        6) systemctl stop backhaul-server backhaul-client &>/dev/null && echo -e "${GREEN}Services stopped.${NC}" || echo -e "${YELLOW}No active services to stop.${NC}" ;;
        7) journalctl -u backhaul-server -f --no-pager ;;
        8) journalctl -u backhaul-client -f --no-pager ;;
        9) uninstall_backhaul ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid choice!${NC}" ;;
    esac
    
    echo ""
    read -n 1 -s -r -p "Press any key to return to the main menu..."
}

# --- Script execution ---
check_root
while true; do
    main_menu
done
