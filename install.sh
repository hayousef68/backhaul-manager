#!/bin/bash

# ==========================================================
# Backhaul Auto Setup & Management Script
# Version: 2.1
# Based on the sample provided by the user.
# Enhanced, corrected, and completed by Google Gemini.
# ==========================================================

# --- Global Variables ---
CONFIG_DIR="/etc/backhaul"
BINARY_PATH="/usr/local/bin/backhaul"

# --- Colors for better UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# --- Functions ---

# Clear the screen smoothly and show a header
clear_screen() {
    # Use ANSI escape codes to clear screen and move cursor to home, which prevents flickering
    printf "\033[2J\033[H"
    
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}            ${WHITE}Backhaul Auto Manager${CYAN}            ${NC}"
    echo -e "${CYAN}               ${YELLOW}v2.1 - English${CYAN}             ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

# Check if the script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}Error: This script must be run as root!${NC}"
       echo -e "${YELLOW}Please run with: sudo bash $0${NC}"
       exit 1
    fi
}

# Detect system architecture for downloading the correct binary
detect_arch() {
    case $(uname -m) in
        x86_64|amd64) echo "linux-amd64" ;;
        aarch64|arm64) echo "linux-arm64" ;;
        armv7l) echo "linux-armv7" ;;
        i386|i686) echo "linux-386" ;;
        *) echo "unsupported" ;;
    esac
}

# Download and install the latest version of Backhaul
install_backhaul() {
    echo -e "${BLUE}Installing/Updating Backhaul...${NC}"
    local ARCH
    ARCH=$(detect_arch)
    if [ "$ARCH" = "unsupported" ]; then
        echo -e "${RED}Error: Unsupported system architecture!${NC}"
        return 1
    fi

    echo -e "${YELLOW}Getting latest version information from GitHub...${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}Error: Failed to get version information from GitHub!${NC}"
        return 1
    fi

    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${LATEST_VERSION#v}_${ARCH}.tar.gz"
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
    rm backhaul.tar.gz
    echo -e "${GREEN}Backhaul installed successfully!${NC}"
    return 0
}

# Create a server configuration file
create_server_config() {
    clear_screen
    echo -e "${PURPLE}--- Server Configuration ---${NC}\n"

    PS3="Please select server location: "
    select server_location_choice in "Iran Server (Foreign will connect to this)" "Foreign Server (Iran will connect to this)"; do
        case $server_location_choice in
            "Iran Server (Foreign will connect to this)") SERVER_LOCATION="iran"; DEFAULT_PORT=443; break ;;
            "Foreign Server (Iran will connect to this)") SERVER_LOCATION="foreign"; DEFAULT_PORT=7777; break ;;
        esac
    done

    read -p "Enter server port [Default: ${DEFAULT_PORT}]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-$DEFAULT_PORT}
    read -p "Enter connection password [Default: mypassword]: " PASSWORD
    PASSWORD=${PASSWORD:-mypassword}

    echo -e "\n${CYAN}Select transport protocol:${NC}"
    PS3="Your choice: "
    select protocol_choice in "TCP (Fast, simple)" "WebSocket (WS)" "WebSocket Secure (WSS) - Recommended" "GRPC"; do
        case $protocol_choice in
            "TCP (Fast, simple)") TRANSPORT="tcp"; break ;;
            "WebSocket (WS)") TRANSPORT="ws"; break ;;
            "WebSocket Secure (WSS) - Recommended") TRANSPORT="wss"; break ;;
            "GRPC") TRANSPORT="grpc"; break ;;
        esac
    done

    HEARTBEAT_CONFIG=""
    SNI_CONFIG=""
    if [ "$SERVER_LOCATION" = "iran" ]; then
        echo ""
        read -p "Enable heartbeat for stability? [y/N]: " ENABLE_HEARTBEAT
        if [[ $ENABLE_HEARTBEAT =~ ^[Yy]$ ]]; then
            HEARTBEAT_CONFIG="heartbeat = 40"
        fi
        if [ "$TRANSPORT" = "wss" ]; then
            read -p "Enter SNI/Domain for WSS [Default: cloudflare.com]: " SNI_DOMAIN
            SNI_DOMAIN=${SNI_DOMAIN:-cloudflare.com}
            SNI_CONFIG="sni = \"$SNI_DOMAIN\""
        fi
    fi

    cat > "$CONFIG_DIR/server.toml" << EOF
[server]
bind_addr = "0.0.0.0:${SERVER_PORT}"
transport = "${TRANSPORT}"
token = "${PASSWORD}"
keepalive_period = 75
nodelay = true
$([ -n "$HEARTBEAT_CONFIG" ] && echo "$HEARTBEAT_CONFIG")
$([ -n "$SNI_CONFIG" ] && echo "$SNI_CONFIG")
[server.channel_size]
queue_size = 2048
EOF
    echo -e "\n${GREEN}Server config created successfully!${NC}"
    echo -e "${BLUE}Config file: ${CONFIG_DIR}/server.toml${NC}"
    echo -e "\n${YELLOW}--- Server Details ---${NC}"
    echo -e "  Location:  ${SERVER_LOCATION^}"
    echo -e "  Port:      ${SERVER_PORT}"
    echo -e "  Transport: ${TRANSPORT}"
    echo -e "  Password:  ${PASSWORD}"
}

# Create a client configuration file
create_client_config() {
    clear_screen
    echo -e "${PURPLE}--- Client Configuration ---${NC}\n"

    PS3="Please select client location: "
    select client_location_choice in "Iran Client (connects to foreign server)" "Foreign Client (connects to Iran server)"; do
        case $client_location_choice in
            "Iran Client (connects to foreign server)") CLIENT_LOCATION="iran"; break ;;
            "Foreign Client (connects to Iran server)") CLIENT_LOCATION="foreign"; break ;;
        esac
    done

    read -p "Enter the Server's public IP address: " SERVER_IP
    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}Error: Server IP is required!${NC}"
        return 1
    fi

    if [ "$CLIENT_LOCATION" = "iran" ]; then
        DEFAULT_SERVER_PORT=7777; DEFAULT_LOCAL_PORT=8080; DEFAULT_TARGET_IP="127.0.0.1"; DEFAULT_TARGET_PORT="22";
    else
        DEFAULT_SERVER_PORT=443; DEFAULT_LOCAL_PORT=22; DEFAULT_TARGET_IP="127.0.0.1"; DEFAULT_TARGET_PORT="8080";
    fi

    read -p "Enter server port [Default: $DEFAULT_SERVER_PORT]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-$DEFAULT_SERVER_PORT}
    read -p "Enter connection password [Default: mypassword]: " PASSWORD
    PASSWORD=${PASSWORD:-mypassword}
    read -p "Enter local port for this machine to listen on [Default: $DEFAULT_LOCAL_PORT]: " LOCAL_PORT
    LOCAL_PORT=${LOCAL_PORT:-$DEFAULT_LOCAL_PORT}

    echo -e "\n${YELLOW}Enter the target service details on the OTHER server:${NC}"
    read -p "Enter target IP address (usually 127.0.0.1) [Default: $DEFAULT_TARGET_IP]: " TARGET_IP
    TARGET_IP=${TARGET_IP:-$DEFAULT_TARGET_IP}
    read -p "Enter target port (e.g., 22 for SSH) [Default: $DEFAULT_TARGET_PORT]: " TARGET_PORT
    TARGET_PORT=${TARGET_PORT:-$DEFAULT_TARGET_PORT}
    TARGET_ADDR="${TARGET_IP}:${TARGET_PORT}"

    echo -e "\n${CYAN}Select transport protocol:${NC}"
    PS3="Your choice: "
    select protocol_choice in "TCP" "WebSocket (WS)" "WebSocket Secure (WSS)" "GRPC"; do
        case $protocol_choice in
            "TCP") TRANSPORT="tcp"; break ;;
            "WebSocket (WS)") TRANSPORT="ws"; break ;;
            "WebSocket Secure (WSS)") TRANSPORT="wss"; break ;;
            "GRPC") TRANSPORT="grpc"; break ;;
        esac
    done

    HEARTBEAT_CONFIG=""
    SNI_CONFIG=""
    if [ "$CLIENT_LOCATION" = "iran" ]; then
        read -p "Enable heartbeat? [y/N]: " ENABLE_HEARTBEAT
        if [[ $ENABLE_HEARTBEAT =~ ^[Yy]$ ]]; then
            HEARTBEAT_CONFIG="heartbeat = 40"
        fi
        if [ "$TRANSPORT" = "wss" ]; then
            read -p "Enter SNI/Domain for WSS [Default: cloudflare.com]: " SNI_DOMAIN
            SNI_DOMAIN=${SNI_DOMAIN:-cloudflare.com}
            SNI_CONFIG="sni = \"$SNI_DOMAIN\""
        fi
    fi

    cat > "$CONFIG_DIR/client.toml" << EOF
[client]
remote_addr = "${SERVER_IP}:${SERVER_PORT}"
transport = "${TRANSPORT}"
token = "${PASSWORD}"
keepalive_period = 75
retry_interval = 1
nodelay = true
$([ -n "$HEARTBEAT_CONFIG" ] && echo "$HEARTBEAT_CONFIG")
$([ -n "$SNI_CONFIG" ] && echo "$SNI_CONFIG")
[[client.services]]
local_addr = "0.0.0.0:${LOCAL_PORT}"
remote_addr = "${TARGET_ADDR}"
[client.channel_size]
queue_size = 2048
EOF
    echo -e "\n${GREEN}Client config created successfully!${NC}"
    echo -e "${BLUE}Config file: ${CONFIG_DIR}/client.toml${NC}"
    echo -e "\n${YELLOW}--- Client Details ---${NC}"
    echo -e "  Location:              ${CLIENT_LOCATION^}"
    echo -e "  Server:                $SERVER_IP:$SERVER_PORT"
    echo -e "  Local Port (Listening): $LOCAL_PORT"
    echo -e "  Target Service:        $TARGET_ADDR"
    echo -e "  Transport:             $TRANSPORT"
}

# Create a systemd service
create_service() {
    clear_screen
    echo -e "${BLUE}Creating systemd service...${NC}\n"
    PS3="Please select the service type to create: "
    select service_choice in "Server" "Client"; do
        case $service_choice in
            "Server")
                CONFIG_FILE="server.toml"; SERVICE_NAME="backhaul-server"; DESCRIPTION="Backhaul Server"; break ;;
            "Client")
                CONFIG_FILE="client.toml"; SERVICE_NAME="backhaul-client"; DESCRIPTION="Backhaul Client"; break ;;
        esac
    done

    if [ ! -f "$CONFIG_DIR/$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Config file '$CONFIG_DIR/$CONFIG_FILE' not found! Please create it first.${NC}"
        return 1
    fi

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=${DESCRIPTION}
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
    systemctl enable "$SERVICE_NAME"
    echo -e "\n${GREEN}Service ${SERVICE_NAME} created and enabled successfully!${NC}"
    echo -e "${YELLOW}You can start it now from the 'Manage Service' menu.${NC}"
}

# Manage existing services
manage_service() {
    clear_screen
    echo -e "${PURPLE}--- Service Management ---${NC}\n"
    
    mapfile -t SERVICES < <(ls /etc/systemd/system/backhaul-*.service 2>/dev/null | xargs -n 1 basename | sed 's/\.service//')
    
    if [ ${#SERVICES[@]} -eq 0 ]; then
        echo -e "${RED}No Backhaul services found! Please create a service first.${NC}"
        return
    fi
    
    PS3="Select a service to manage: "
    select SERVICE in "${SERVICES[@]}"; do
        if [ -n "$SERVICE" ]; then
            break
        fi
    done

    clear_screen
    echo -e "${CYAN}Managing service: ${WHITE}${SERVICE}${NC}"
    systemctl is-active --quiet "$SERVICE" && echo -e "Status: ${GREEN}Active${NC}" || echo -e "Status: ${RED}Inactive${NC}"
    echo "---"

    PS3="Your choice: "
    select action in "Start" "Stop" "Restart" "View Status" "View Logs (real-time)" "Back to Main Menu"; do
        case $action in
            "Start") systemctl start "$SERVICE" && echo -e "${GREEN}Service started.${NC}"; break ;;
            "Stop") systemctl stop "$SERVICE" && echo -e "${RED}Service stopped.${NC}"; break ;;
            "Restart") systemctl restart "$SERVICE" && echo -e "${YELLOW}Service restarted.${NC}"; break ;;
            "View Status") systemctl status "$SERVICE" -n 20 --no-pager; echo "Press Enter to continue..."; read -n 1; break ;;
            "View Logs (real-time)") journalctl -u "$SERVICE" -f --no-pager; break ;;
            "Back to Main Menu") break 2;;
        esac
    done
}

# Uninstall function
uninstall_backhaul() {
    clear_screen
    echo -e "${RED}--- Uninstall Backhaul ---${NC}"
    read -p "Are you sure you want to completely remove Backhaul and all its configs? [y/N]: " CONFIRM
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        systemctl stop backhaul-server backhaul-client &>/dev/null
        systemctl disable backhaul-server backhaul-client &>/dev/null
        rm -f /etc/systemd/system/backhaul-*.service
        rm -f "$BINARY_PATH"
        rm -rf "$CONFIG_DIR"
        systemctl daemon-reload
        echo -e "${GREEN}Backhaul has been completely uninstalled.${NC}"
    else
        echo -e "${YELLOW}Uninstall cancelled.${NC}"
    fi
}


# --- Main Menu ---
main_menu() {
    while true; do
        clear_screen
        echo -e "${PURPLE}Main Menu:${NC}"
        echo "1) Install/Update Backhaul"
        echo "2) Create Server Config"
        echo "3) Create Client Config"
        echo "4) Create Systemd Service"
        echo "5) Manage Service"
        echo "6) Uninstall Backhaul"
        echo "0) Exit"
        echo ""
        read -p "Enter your choice: " choice

        case $choice in
            1) install_backhaul ;;
            2) create_server_config ;;
            3) create_client_config ;;
            4) create_service ;;
            5) manage_service ;;
            6) uninstall_backhaul ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid choice, please try again.${NC}" ;;
        esac
        echo -e "\n${YELLOW}Press Enter to return to the main menu...${NC}"
        read -r
    done
}

# --- Script Start ---
check_root
main_menu
