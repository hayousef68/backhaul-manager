#!/bin/bash

# Backhaul Auto Setup Script - English Version
# Version: 1.3
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
NC='\033[0m' # No Color

# --- Global variables ---
CONFIG_DIR="/etc/backhaul"
LOG_FILE="/var/log/backhaul.log"
BINARY_PATH="/usr/local/bin/backhaul"

# --- Functions ---

clear_screen() {
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}            ${WHITE}Backhaul Auto Manager${CYAN}            ${NC}"
    echo -e "${CYAN}               ${YELLOW}v1.3 - English${CYAN}              ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then # 
        echo -e "${RED}Error: This script must be run as root!${NC}" # 
        echo -e "${YELLOW}Please run with sudo: sudo bash $0${NC}" # 
        exit 1
    fi
}

# Detect system architecture
detect_arch() {
    case $(uname -m) in # 
        x86_64|amd64) echo "linux-amd64" ;; # 
        aarch64|arm64) echo "linux-arm64" ;; # 
        armv7l) echo "linux-armv7" ;; # 
        i386|i686) echo "linux-386" ;; # 
        *) echo "unsupported" ;; # 
    esac # 
}

# Download and install Backhaul
install_backhaul() {
    echo -e "${BLUE}Installing Backhaul...${NC}" # 
    ARCH=$(detect_arch)
    if [ "$ARCH" == "unsupported" ]; then # 
        echo -e "${RED}Error: Unsupported system architecture!${NC}" # 
        return 1
    fi
    echo -e "${YELLOW}Getting latest version information...${NC}" # 
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    
    if [ -z "$LATEST_VERSION" ]; then # 
        echo -e "${RED}Error: Failed to get version information from GitHub!${NC}" # 
        return 1
    fi
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${LATEST_VERSION#v}_${ARCH}.tar.gz"
    
    echo -e "${YELLOW}Downloading Backhaul ${LATEST_VERSION}...${NC}"
    cd /tmp
    if ! wget -q --show-progress "$DOWNLOAD_URL" -O backhaul.tar.gz; then # 
        echo -e "${RED}Error: Download failed! Please check your network or the URL.${NC}" # 
        return 1
    fi
    
    tar -xzf backhaul.tar.gz
    chmod +x backhaul
    mv backhaul "$BINARY_PATH"
    
    mkdir -p "$CONFIG_DIR" # 
    echo -e "${GREEN}Backhaul installed successfully!${NC}" # 
    return 0
}

# Server type selection
select_server_type() {
    echo -e "${PURPLE}Select server location:${NC}" # 
    echo "1) Iran Server (Kharej will connect to this)"
    echo "2) Foreign Server (Iran will connect to this)"
    echo ""
    read -p "Enter your choice [1-2]: " SERVER_TYPE # 
    
    case $SERVER_TYPE in # 
        1) echo "iran" ;; # 
        2) echo "foreign" ;; # 
        *) echo "iran" ;; # 
    esac # 
}

# Create server config
create_server_config() {
    clear_screen
    echo -e "${PURPLE}Server Configuration${NC}" # 
    echo ""
    
    SERVER_LOCATION=$(select_server_type)
    
    if [ "$SERVER_LOCATION" == "iran" ]; then # 
        echo -e "${CYAN}Configuring Iran Server (Kharej clients will connect)${NC}" # 
        DEFAULT_PORT=443 # 
    else
        echo -e "${CYAN}Configuring Foreign Server (Iran clients will connect)${NC}" # 
        DEFAULT_PORT=7777 # 
    fi
    
    read -p "Enter server port [$DEFAULT_PORT]: " SERVER_PORT # 
    SERVER_PORT=${SERVER_PORT:-$DEFAULT_PORT} # 
    read -p "Enter connection password [mypassword]: " PASSWORD # 
    PASSWORD=${PASSWORD:-mypassword} # 
    
    echo -e "${CYAN}Select transport protocol:${NC}" # 
    echo "1) TCP (Fast, simple)"
    echo "2) WebSocket (WS)" # 
    echo "3) WebSocket Secure (WSS) - Recommended for Iran"
    echo "4) GRPC"
    echo ""
    read -p "Enter your choice [3]: " PROTOCOL_CHOICE
    PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-3}
    
    case $PROTOCOL_CHOICE in
        1) TRANSPORT="tcp" ;; # 
        2) TRANSPORT="ws" ;; # 
        3) TRANSPORT="wss" ;; # 
        4) TRANSPORT="grpc" ;; # 
        *) TRANSPORT="wss" ;; # 
    esac
    
    HEARTBEAT_CONFIG=""
    SNI_CONFIG=""
    if [ "$SERVER_LOCATION" == "iran" ]; then # 
        echo "" # 
        echo -e "${YELLOW}Additional settings for Iran server:${NC}" # 
        
        read -p "Enable heartbeat? [y/N]: " ENABLE_HEARTBEAT
        if [[ $ENABLE_HEARTBEAT =~ ^[Yy]$ ]]; then # 
            HEARTBEAT_CONFIG="heartbeat = 40" # 
        fi
        
        if [ "$TRANSPORT" == "wss" ]; then # 
            read -p "Enter SNI/Domain for WSS [cloudflare.com]: " SNI_DOMAIN # 
            SNI_DOMAIN=${SNI_DOMAIN:-cloudflare.com} # 
            SNI_CONFIG="sni = \"$SNI_DOMAIN\"" # 
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
    echo -e "${GREEN}Server config created successfully!${NC}" # 
    echo -e "${BLUE}Config file: $CONFIG_DIR/server.toml${NC}" # 
    echo ""
    echo -e "${YELLOW}Server Details:${NC}" # 
    echo -e "  Location: ${SERVER_LOCATION^}" # 
    echo -e "  Port: $SERVER_PORT"
    echo -e "  Transport: $TRANSPORT"
    echo -e "  Password: $PASSWORD" # 
}

# Create client config
create_client_config() {
    clear_screen
    echo -e "${PURPLE}Client Configuration${NC}" # 
    echo ""
    
    echo -e "${PURPLE}Select client location:${NC}" # 
    echo "1) Iran Client (connects to foreign server)"
    echo "2) Foreign Client (connects to Iran server)"
    echo ""
    read -p "Enter your choice [1-2]: " CLIENT_TYPE # 
    
    case $CLIENT_TYPE in # 
        1) 
            CLIENT_LOCATION="iran" # 
            echo -e "${CYAN}Configuring Iran Client${NC}" # 
            ;;
        2) 
            CLIENT_LOCATION="foreign" # 
            echo -e "${CYAN}Configuring Foreign Client${NC}" # 
            ;;
        *) 
            CLIENT_LOCATION="iran" # 
            echo -e "${CYAN}Configuring Iran Client${NC}" # 
            ;;
    esac # 
    
    read -p "Enter server IP address: " SERVER_IP
    if [ -z "$SERVER_IP" ]; then # 
        echo -e "${RED}Error: Server IP is required!${NC}" # 
        return 1
    fi
    
    if [ "$CLIENT_LOCATION" = "iran" ]; then # 
        DEFAULT_SERVER_PORT=7777 # 
        DEFAULT_LOCAL_PORT=8080 # 
        DEFAULT_TARGET_IP="127.0.0.1" # 
        DEFAULT_TARGET_PORT="22" # Default to SSH port # 
    else
        DEFAULT_SERVER_PORT=443 # 
        DEFAULT_LOCAL_PORT=22 # 
        DEFAULT_TARGET_IP="127.0.0.1" # 
        DEFAULT_TARGET_PORT="8080" # Default to a web server port # 
    fi
    
    read -p "Enter server port [$DEFAULT_SERVER_PORT]: " SERVER_PORT # 
    SERVER_PORT=${SERVER_PORT:-$DEFAULT_SERVER_PORT} # 
    read -p "Enter connection password [mypassword]: " PASSWORD # 
    PASSWORD=${PASSWORD:-mypassword} # 
    
    read -p "Enter local port for this machine to listen on [$DEFAULT_LOCAL_PORT]: " LOCAL_PORT # 
    LOCAL_PORT=${LOCAL_PORT:-$DEFAULT_LOCAL_PORT} # 
    echo "" # 
    echo -e "${YELLOW}Enter the target service details on the OTHER server:${NC}" # 
    read -p "Enter target IP address (usually 127.0.0.1) [$DEFAULT_TARGET_IP]: " TARGET_IP # 
    TARGET_IP=${TARGET_IP:-$DEFAULT_TARGET_IP}
    
    read -p "Enter target port (e.g., 22 for SSH, 8080 for a panel) [$DEFAULT_TARGET_PORT]: " TARGET_PORT # 
    TARGET_PORT=${TARGET_PORT:-$DEFAULT_TARGET_PORT} # 
    TARGET_ADDR="${TARGET_IP}:${TARGET_PORT}" # 
    echo -e "${CYAN}Select transport protocol:${NC}" # 
    echo "1) TCP (Fast, simple)" # 
    echo "2) WebSocket (WS)" # 
    echo "3) WebSocket Secure (WSS) - Recommended for Iran" # 
    echo "4) GRPC" # 
    echo "" # 
    
    if [ "$CLIENT_LOCATION" == "iran" ]; then # 
        read -p "Enter your choice [3]: " PROTOCOL_CHOICE # 
        PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-3} # 
    else
        read -p "Enter your choice [1]: " PROTOCOL_CHOICE # 
        PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-1} # 
    fi
    
    case $PROTOCOL_CHOICE in
        1) TRANSPORT="tcp" ;; # 
        2) TRANSPORT="ws" ;; # 
        3) TRANSPORT="wss" ;; # 
        4) TRANSPORT="grpc" ;; # 
        *) TRANSPORT="tcp" ;; # 
    esac
    
    HEARTBEAT_CONFIG=""
    SNI_CONFIG=""
    if [ "$CLIENT_LOCATION" == "iran" ]; then # 
        echo "" # 
        echo -e "${YELLOW}Additional settings for Iran client:${NC}" # 
        
        read -p "Enable heartbeat? [y/N]: " ENABLE_HEARTBEAT
        if [[ $ENABLE_HEARTBEAT =~ ^[Yy]$ ]]; then # 
            HEARTBEAT_CONFIG="heartbeat = 40" # 
        fi
        
        if [ "$TRANSPORT" == "wss" ]; then # 
            read -p "Enter SNI/Domain for WSS [cloudflare.com]: " SNI_DOMAIN # 
            SNI_DOMAIN=${SNI_DOMAIN:-cloudflare.com} # 
            SNI_CONFIG="sni = \"$SNI_DOMAIN\"" # 
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
    echo -e "${GREEN}Client config created successfully!${NC}" # 
    echo -e "${BLUE}Config file: $CONFIG_DIR/client.toml${NC}" # 
    echo "" # 
    
    echo -e "${YELLOW}Client Details:${NC}" # 
    echo -e "  Location: ${CLIENT_LOCATION^}"
    echo -e "  Server: $SERVER_IP:$SERVER_PORT"
    echo -e "  Local Port (Listening): $LOCAL_PORT"
    echo -e "  Target Service (On other server): $TARGET_ADDR"
    echo -e "  Transport: $TRANSPORT" # 
}

# Create systemd service
create_service() {
    echo -e "${BLUE}Creating systemd service...${NC}" # 
    
    echo "Select service type:"
    echo "1) Server"
    echo "2) Client"
    read -p "Enter your choice: " SERVICE_CHOICE # 
     
    case $SERVICE_CHOICE in # 
        1)
            CONFIG_FILE="server.toml" # 
            SERVICE_NAME="backhaul-server" # 
            DESCRIPTION="Backhaul Server" # 
            ;;
        2)
            CONFIG_FILE="client.toml" # 
            SERVICE_NAME="backhaul-client" # 
            DESCRIPTION="Backhaul Client" # 
            ;;
        *)
            echo -e "${RED}Error: Invalid selection!${NC}" # 
            return 1
            ;;
    esac
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
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    echo -e "${GREEN}Service ${SERVICE_NAME} created and enabled successfully!${NC}" # 
    echo -e "${YELLOW}You can start it now from the 'Manage Service' menu.${NC}" # 
}

# Service management
manage_service() {
    clear_screen
    echo -e "${PURPLE}Service Management${NC}" # 
    echo ""
    
    SERVICES=$(ls /etc/systemd/system/backhaul-*.service 2>/dev/null | xargs -n 1 basename | sed 's/\.service$//') # 
    
    if [ -z "$SERVICES" ]; then # 
        echo -e "${RED}No Backhaul services found! Please create a config and service first.${NC}" # 
        return
    fi

    echo -e "${CYAN}Available services:${NC}"
    select SERVICE in $SERVICES; do
        if [ -n "$SERVICE" ]; then
            break
        fi
    done

    echo ""
    echo -e "${YELLOW}Selected service: ${SERVICE}${NC}"
    echo ""
    echo "1) Start Service"
    echo "2) Stop Service"
    echo "3) Restart Service"
    echo "4) View Status"
    echo "5) View Logs"
    echo "6) Delete Service"
    echo "7) Back to Main Menu"
    read -p "Enter your choice [1-7]: " ACTION

    case $ACTION in
        1) systemctl start "$SERVICE" && echo -e "${GREEN}Service started.${NC}" ;;
        2) systemctl stop "$SERVICE" && echo -e "${GREEN}Service stopped.${NC}" ;;
        3) systemctl restart "$SERVICE" && echo -e "${GREEN}Service restarted.${NC}" ;;
        4) systemctl status "$SERVICE" ;;
        5) journalctl -u "$SERVICE" -f --no-pager ;;
        6) 
            systemctl stop "$SERVICE"
            systemctl disable "$SERVICE"
            rm "/etc/systemd/system/${SERVICE}.service"
            systemctl daemon-reload
            echo -e "${GREEN}Service ${SERVICE} deleted.${NC}"
            ;;
        7) return ;;
        *) echo -e "${RED}Invalid choice.${NC}" ;;
    esac
}

# Uninstall function
uninstall_backhaul() {
    echo -e "${RED}This will stop and remove all backhaul services and delete the binary. Are you sure?${NC}"
    read -p "Enter 'yes' to confirm: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${YELLOW}Uninstallation cancelled.${NC}"
        return
    fi

    # Stop and remove services
    SERVICES=$(ls /etc/systemd/system/backhaul-*.service 2>/dev/null | xargs -n 1 basename)
    if [ -n "$SERVICES" ]; then
        for SERVICE in $SERVICES; do
            echo "Stopping and disabling $SERVICE..."
            systemctl stop "$SERVICE"
            systemctl disable "$SERVICE"
            rm "/etc/systemd/system/$SERVICE"
        done
        systemctl daemon-reload
    fi

    # Remove files
    echo "Removing binary and configuration files..."
    rm -f "$BINARY_PATH"
    rm -rf "$CONFIG_DIR"
    
    echo -e "${GREEN}Backhaul has been uninstalled.${NC}"
}

# Main menu
main_menu() {
    clear_screen
    echo -e "${PURPLE}Select an option:${NC}"
    echo "1) Install/Update Backhaul"
    echo "2) Create Server Config"
    echo "3) Create Client Config"
    echo "4) Create Systemd Service"
    echo "5) Manage Service (Start, Stop, Status, Logs)"
    echo "6) Uninstall Backhaul"
    echo "7) Exit"
    echo ""
    read -p "Enter your choice [1-7]: " choice
    
    case $choice in
        1) install_backhaul ;;
        2) create_server_config ;;
        3) create_client_config ;;
        4) create_service ;;
        5) manage_service ;;
        6) uninstall_backhaul ;;
        7) exit 0 ;;
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
