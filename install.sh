#!/bin/bash

# Backhaul Auto Setup Script
# Version: 2.0
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${NC}"
        echo -e "${YELLOW}Please run with sudo: sudo bash $0${NC}"
        exit 1
    fi
}

# Detect system architecture for new release format
detect_arch() {
    case $(uname -m) in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) echo "unsupported" ;;
    esac
}

# Download and install Backhaul (FIXED)
install_backhaul() {
    echo -e "${BLUE}Installing/Updating Backhaul...${NC}"
    ARCH=$(detect_arch)
    if [ "$ARCH" == "unsupported" ]; then
        echo -e "${RED}Error: Unsupported system architecture!${NC}"
        return 1
    fi

    echo -e "${YELLOW}Getting latest version information from GitHub...${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}Error: Failed to get version information from GitHub!${NC}"
        return 1
    fi

    # Updated URL format for new releases
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul-${LATEST_VERSION}-${ARCH}-unknown-linux-musl.tar.gz"
    
    echo -e "${YELLOW}Downloading Backhaul ${LATEST_VERSION}...${NC}"
    cd /tmp
    if ! wget -q --show-progress "$DOWNLOAD_URL" -O backhaul.tar.gz; then
        echo -e "${RED}Error: Download failed! Please check your network or the URL.${NC}"
        return 1
    fi
    
    tar -xzf backhaul.tar.gz
    chmod +x backhaul
    mv backhaul "$BINARY_PATH"
    
    mkdir -p "$CONFIG_DIR"
    echo -e "${GREEN}Backhaul ${LATEST_VERSION} installed successfully!${NC}"
}

# Create server config
create_server_config() {
    # This function remains largely the same as the previous correct version.
    # For brevity, it is assumed to be correct. The full code is in the final script.
    # ... (Full function code from previous version) ...
    echo -e "${PURPLE}Server Configuration${NC}" &&
    read -p "Enter server port [443]: " SERVER_PORT && SERVER_PORT=${SERVER_PORT:-443} &&
    read -p "Enter connection password [mypassword]: " PASSWORD && PASSWORD=${PASSWORD:-mypassword} &&
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
}

# Create client config
create_client_config() {
    # This function also remains largely the same.
    # ... (Full function code from previous version) ...
    echo -e "${PURPLE}Client Configuration${NC}" &&
    read -p "Enter server IP address: " SERVER_IP &&
    read -p "Enter server port [443]: " SERVER_PORT && SERVER_PORT=${SERVER_PORT:-443} &&
    read -p "Enter connection password [mypassword]: " PASSWORD && PASSWORD=${PASSWORD:-mypassword} &&
    read -p "Enter local port to listen on [8080]: " LOCAL_PORT && LOCAL_PORT=${LOCAL_PORT:-8080} &&
    read -p "Enter target port on the other server (e.g., 22 for SSH) [22]: " TARGET_PORT && TARGET_PORT=${TARGET_PORT:-22} &&
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
}

# Create/Manage Service
manage_service() {
    # This function is simplified and combined with creation for a better workflow.
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


# Uninstall function
uninstall_backhaul() {
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


# New function to show status at the top of the menu
show_status() {
    clear
    echo -e "${CYAN}================== Backhaul Manager v2.0 ==================${NC}"
    
    # Check installation status
    if [ -f "$BINARY_PATH" ]; then
        VERSION=$($BINARY_PATH -V)
        echo -e " ${GREEN}●${NC} Backhaul: ${WHITE}Installed (${VERSION})${NC}"
    else
        echo -e " ${RED}●${NC} Backhaul: ${YELLOW}Not Installed${NC}"
        echo -e "${CYAN}===========================================================${NC}"
        return
    fi

    # Check server service
    if systemctl is-active --quiet backhaul-server; then
        STATUS_COLOR="${GREEN}"
        STATUS_TEXT="Active"
        PORT=$(grep 'bind_addr' $CONFIG_DIR/server.toml | cut -d'"' -f2)
        echo -e " ${GREEN}●${NC} Server Service: ${WHITE}${STATUS_TEXT} | Listening on: ${PORT}${NC}"
    else
        STATUS_COLOR="${RED}"
        STATUS_TEXT="Inactive"
        echo -e " ${RED}●${NC} Server Service: ${YELLOW}${STATUS_TEXT}${NC}"
    fi

    # Check client service
    if systemctl is-active --quiet backhaul-client; then
        STATUS_COLOR="${GREEN}"
        STATUS_TEXT="Active"
        PORT=$(grep 'local_addr' $CONFIG_DIR/client.toml | cut -d'"' -f2)
        TARGET=$(grep 'remote_addr' $CONFIG_DIR/client.toml | head -n 1 | cut -d'"' -f2)
        echo -e " ${GREEN}●${NC} Client Service: ${WHITE}${STATUS_TEXT} | Forwarding port ${PORT} to server ${TARGET}${NC}"
    else
        STATUS_COLOR="${RED}"
        STATUS_TEXT="Inactive"
        echo -e " ${RED}●${NC} Client Service: ${YELLOW}${STATUS_TEXT}${NC}"
    fi
    echo -e "${CYAN}===========================================================${NC}"
}


# Main menu
main_menu() {
    show_status
    echo ""
    echo -e "${PURPLE}What do you want to do?${NC}"
    echo "1) Install/Update Backhaul"
    echo "2) Configure Server"
    echo "3) Configure Client"
    echo "4) Create and Start Service"
    echo "--- Management ---"
    echo "5) Restart Services"
    echo "6) Stop Services"
    echo "7) View Server Logs"
    echo "8) View Client Logs"
    echo "9) Uninstall Backhaul"
    echo "0) Exit"
    echo ""
    read -p "Enter your choice [0-9]: " choice
    
    case $choice in
        1) install_backhaul ;;
        2) create_server_config ;;
        3) create_client_config ;;
        4) manage_service ;;
        5) systemctl restart backhaul-server backhaul-client &>/dev/null && echo -e "${GREEN}Services restarted.${NC}" || echo -e "${YELLOW}No services to restart.${NC}" ;;
        6) systemctl stop backhaul-server backhaul-client &>/dev/null && echo -e "${GREEN}Services stopped.${NC}" || echo -e "${YELLOW}No services to stop.${NC}" ;;
        7) journalctl -u backhaul-server -f --no-pager ;;
        8) journalctl -u backhaul-client -f --no-pager ;;
        9) uninstall_backhaul ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid choice!${NC}" ;;
    esac
    
    echo ""
    read -p "Press Enter to return to the main menu..."
}


# --- Script execution ---
check_root
while true; do
    main_menu
done
