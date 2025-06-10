#!/bin/bash

# Backhaul Auto Setup Script - English Version
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

# Clear screen and show header
clear_screen() {
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}            ${WHITE}Backhaul Auto Manager${CYAN}            ${NC}"
    echo -e "${CYAN}               ${YELLOW}v1.1 - English${CYAN}               ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${NC}"
        echo -e "${YELLOW}Please run with sudo: sudo bash $0${NC}"
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
    echo -e "${BLUE}Installing Backhaul...${NC}"
    
    ARCH=$(detect_arch)
    if [ "$ARCH" = "unsupported" ]; then
        echo -e "${RED}Error: Unsupported system architecture!${NC}"
        return 1
    fi
    
    # Get latest version
    echo -e "${YELLOW}Getting latest version...${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    
    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}Error: Failed to get version information!${NC}"
        return 1
    fi
    
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${LATEST_VERSION#v}_${ARCH}.tar.gz"
    
    # Download
    echo -e "${YELLOW}Downloading Backhaul ${LATEST_VERSION}...${NC}"
    cd /tmp
    wget -q --show-progress "$DOWNLOAD_URL" -O backhaul.tar.gz
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Download failed!${NC}"
        return 1
    fi
    
    # Extract and install
    tar -xzf backhaul.tar.gz
    chmod +x backhaul
    mv backhaul "$BINARY_PATH"
    
    # Create directories
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${GREEN}Backhaul installed successfully!${NC}"
    return 0
}

# Server type selection
select_server_type() {
    echo -e "${PURPLE}Select server location:${NC}"
    echo "1) Iran Server (Kharej will connect to this)"
    echo "2) Foreign Server (Iran will connect to this)"
    echo ""
    read -p "Enter your choice [1-2]: " SERVER_TYPE
    
    case $SERVER_TYPE in
        1) echo "iran" ;;
        2) echo "foreign" ;;
        *) echo "iran" ;;
    esac
}

# Create server config
create_server_config() {
    clear_screen
    echo -e "${PURPLE}Server Configuration${NC}"
    echo ""
    
    # Server location selection
    SERVER_LOCATION=$(select_server_type)
    
    if [ "$SERVER_LOCATION" = "iran" ]; then
        echo -e "${CYAN}Configuring Iran Server (Kharej clients will connect)${NC}"
        DEFAULT_PORT=443
        RECOMMENDED_TRANSPORT="wss"
    else
        echo -e "${CYAN}Configuring Foreign Server (Iran clients will connect)${NC}"
        DEFAULT_PORT=7777
        RECOMMENDED_TRANSPORT="tcp"
    fi
    
    read -p "Enter server port [$DEFAULT_PORT]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-$DEFAULT_PORT}
    
    read -p "Enter connection password [mypassword]: " PASSWORD
    PASSWORD=${PASSWORD:-mypassword}
    
    # Protocol selection
    echo -e "${CYAN}Select transport protocol:${NC}"
    echo "1) TCP (Fast, simple)"
    echo "2) WebSocket (WS)"
    echo "3) WebSocket Secure (WSS) - Recommended for Iran"
    echo "4) GRPC"
    echo ""
    read -p "Enter your choice [3]: " PROTOCOL_CHOICE
    PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-3}
    
    case $PROTOCOL_CHOICE in
        1) TRANSPORT="tcp" ;;
        2) TRANSPORT="ws" ;;
        3) TRANSPORT="wss" ;;
        4) TRANSPORT="grpc" ;;
        *) TRANSPORT="wss" ;;
    esac
    
    # Additional settings for Iran server
    if [ "$SERVER_LOCATION" = "iran" ]; then
        echo ""
        echo -e "${YELLOW}Additional settings for Iran server:${NC}"
        
        # Heartbeat settings
        read -p "Enable heartbeat? [y/N]: " ENABLE_HEARTBEAT
        if [[ $ENABLE_HEARTBEAT =~ ^[Yy]$ ]]; then
            HEARTBEAT_CONFIG="heartbeat = 40"
        else
            HEARTBEAT_CONFIG=""
        fi
        
        # SNI settings for WSS
        if [ "$TRANSPORT" = "wss" ]; then
            read -p "Enter SNI/Domain for WSS [cloudflare.com]: " SNI_DOMAIN
            SNI_DOMAIN=${SNI_DOMAIN:-cloudflare.com}
            SNI_CONFIG="sni = \"$SNI_DOMAIN\""
        else
            SNI_CONFIG=""
        fi
    fi
    
    # Create server config
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

    echo -e "${GREEN}Server config created successfully!${NC}"
    echo -e "${BLUE}Config file: $CONFIG_DIR/server.toml${NC}"
    echo ""
    echo -e "${YELLOW}Server Details:${NC}"
    echo -e "  Location: ${SERVER_LOCATION^}"
    echo -e "  Port: $SERVER_PORT"
    echo -e "  Transport: $TRANSPORT"
    echo -e "  Password: $PASSWORD"
}

# Create client config  
create_client_config() {
    clear_screen
    echo -e "${PURPLE}Client Configuration${NC}"
    echo ""
    
    # Client location selection
    echo -e "${PURPLE}Select client location:${NC}"
    echo "1) Iran Client (connects to foreign server)"
    echo "2) Foreign Client (connects to Iran server)"
    echo ""
    read -p "Enter your choice [1-2]: " CLIENT_TYPE
    
    case $CLIENT_TYPE in
        1) 
            CLIENT_LOCATION="iran"
            echo -e "${CYAN}Configuring Iran Client${NC}"
            ;;
        2) 
            CLIENT_LOCATION="foreign"
            echo -e "${CYAN}Configuring Foreign Client${NC}"
            ;;
        *) 
            CLIENT_LOCATION="iran"
            echo -e "${CYAN}Configuring Iran Client${NC}"
            ;;
    esac
    
    read -p "Enter server IP address: " SERVER_IP
    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}Error: Server IP is required!${NC}"
        return 1
    fi
    
    if [ "$CLIENT_LOCATION" = "iran" ]; then
        DEFAULT_SERVER_PORT=7777
        DEFAULT_LOCAL_PORT=8080
    else
        DEFAULT_SERVER_PORT=443
        DEFAULT_LOCAL_PORT=22
    fi
    
    read -p "Enter server port [$DEFAULT_SERVER_PORT]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-$DEFAULT_SERVER_PORT}
    
    read -p "Enter connection password [mypassword]: " PASSWORD
    PASSWORD=${PASSWORD:-mypassword}
    
    read -p "Enter local port [$DEFAULT_LOCAL_PORT]: " LOCAL_PORT
    LOCAL_PORT=${LOCAL_PORT:-$DEFAULT_LOCAL_PORT}
    
    if [ "$CLIENT_LOCATION" = "iran" ]; then
        DEFAULT_TARGET="127.0.0.1:22"
    else
        DEFAULT_TARGET="127.0.0.1:8080"
    fi
    
    read -p "Enter target address [$DEFAULT_TARGET]: " TARGET_ADDR
    TARGET_ADDR=${TARGET_ADDR:-$DEFAULT_TARGET}
    
    # Protocol selection
    echo -e "${CYAN}Select transport protocol:${NC}"
    echo "1) TCP (Fast, simple)"
    echo "2) WebSocket (WS)"
    echo "3) WebSocket Secure (WSS) - Recommended for Iran"
    echo "4) GRPC"
    echo ""
    
    if [ "$CLIENT_LOCATION" = "iran" ]; then
        read -p "Enter your choice [3]: " PROTOCOL_CHOICE
        PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-3}
    else
        read -p "Enter your choice [1]: " PROTOCOL_CHOICE
        PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-1}
    fi
    
    case $PROTOCOL_CHOICE in
        1) TRANSPORT="tcp" ;;
        2) TRANSPORT="ws" ;;
        3) TRANSPORT="wss" ;;
        4) TRANSPORT="grpc" ;;
        *) TRANSPORT="tcp" ;;
    esac
    
    # Additional settings for Iran client
    if [ "$CLIENT_LOCATION" = "iran" ]; then
        echo ""
        echo -e "${YELLOW}Additional settings for Iran client:${NC}"
        
        # Heartbeat settings
        read -p "Enable heartbeat? [y/N]: " ENABLE_HEARTBEAT
        if [[ $ENABLE_HEARTBEAT =~ ^[Yy]$ ]]; then
            HEARTBEAT_CONFIG="heartbeat = 40"
        else
            HEARTBEAT_CONFIG=""
        fi
        
        # SNI settings for WSS
        if [ "$TRANSPORT" = "wss" ]; then
            read -p "Enter SNI/Domain for WSS [cloudflare.com]: " SNI_DOMAIN
            SNI_DOMAIN=${SNI_DOMAIN:-cloudflare.com}
            SNI_CONFIG="sni = \"$SNI_DOMAIN\""
        else
            SNI_CONFIG=""
        fi
    fi
    
    # Create client config
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

    echo -e "${GREEN}Client config created successfully!${NC}"
    echo -e "${BLUE}Config file: $CONFIG_DIR/client.toml${NC}"
    echo ""
    echo -e "${YELLOW}Client Details:${NC}"
    echo -e "  Location: ${CLIENT_LOCATION^}"
    echo -e "  Server: $SERVER_IP:$SERVER_PORT"
    echo -e "  Local Port: $LOCAL_PORT"
    echo -e "  Transport: $TRANSPORT"
}

# Create systemd service
create_service() {
    echo -e "${BLUE}Creating systemd service...${NC}"
    
    echo "Select service type:"
    echo "1) Server"
    echo "2) Client"
    read -p "Enter your choice: " SERVICE_TYPE
    
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
            echo -e "${RED}Error: Invalid selection!${NC}"
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
    
    echo -e "${GREEN}Service ${SERVICE_NAME} created successfully!${NC}"
}

# Service management
manage_service() {
    clear_screen
    echo -e "${PURPLE}Service Management${NC}"
    echo ""
    
    # List available services
    echo -e "${CYAN}Available services:${NC}"
    SERVICES=$(ls /etc/systemd/system/backhaul-*.service 2>/dev/null | sed 's|/etc/systemd/system/||' | sed 's|.service||')
    
    if [ -z "$SERVICES" ]; then
        echo -e "${RED}No Backhaul services found!${NC}"
        echo -e "${YELLOW}Please create a service first (option 4)${NC}"
        return 1
    fi
    
    echo "$SERVICES" | nl
    echo ""
    
    read -p "Enter service name: " SERVICE_NAME
    
    if [ -z "$SERVICE_NAME" ]; then
        echo -e "${RED}Error: Service name is required!${NC}"
        return 1
    fi
    
    echo ""
    echo "Select action:"
    echo "1) Start service"
    echo "2) Stop service" 
    echo "3) Restart service"
    echo "4) Service status"
    echo "5) View logs"
    echo "6) Enable auto-start"
    echo "7) Disable auto-start"
    echo ""
    
    read -p "Enter your choice: " ACTION
    
    case $ACTION in
        1) 
            systemctl start "$SERVICE_NAME" 
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Service started successfully!${NC}"
            else
                echo -e "${RED}Failed to start service!${NC}"
                systemctl status "$SERVICE_NAME" --no-pager -l
            fi
            ;;
        2) 
            systemctl stop "$SERVICE_NAME" 
            echo -e "${GREEN}Service stopped!${NC}"
            ;;
        3) 
            systemctl restart "$SERVICE_NAME" 
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Service restarted successfully!${NC}"
            else
                echo -e "${RED}Failed to restart service!${NC}"
                systemctl status "$SERVICE_NAME" --no-pager -l
            fi
            ;;
        4) 
            systemctl status "$SERVICE_NAME" --no-pager -l
            ;;
        5) 
            echo -e "${BLUE}Press Ctrl+C to exit logs${NC}"
            sleep 2
            journalctl -u "$SERVICE_NAME" -f
            ;;
        6) 
            systemctl enable "$SERVICE_NAME" 
            echo -e "${GREEN}Service enabled for auto-start!${NC}"
            ;;
        7) 
            systemctl disable "$SERVICE_NAME" 
            echo -e "${GREEN}Service disabled from auto-start!${NC}"
            ;;
        *) 
            echo -e "${RED}Error: Invalid selection!${NC}"
            ;;
    esac
}

# View logs
view_logs() {
    echo -e "${BLUE}Viewing logs...${NC}"
    echo ""
    
    # List available services
    SERVICES=$(ls /etc/systemd/system/backhaul-*.service 2>/dev/null | sed 's|/etc/systemd/system/||' | sed 's|.service||')
    
    if [ -z "$SERVICES" ]; then
        echo -e "${RED}No Backhaul services found!${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Available services:${NC}"
    echo "$SERVICES" | nl
    echo ""
    
    read -p "Enter service name (or press Enter for all): " SERVICE_NAME
    
    if [ -n "$SERVICE_NAME" ]; then
        journalctl -u "$SERVICE_NAME" --no-pager -n 50
    else
        journalctl -u "backhaul-*" --no-pager -n 50
    fi
}

# Connection test
test_connection() {
    clear_screen
    echo -e "${PURPLE}Connection Test${NC}"
    echo ""
    
    # Check if services are running
    SERVICES=$(systemctl list-units --type=service --state=active | grep backhaul | awk '{print $1}')
    
    if [ -z "$SERVICES" ]; then
        echo -e "${RED}No active Backhaul services found!${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Active services:${NC}"
    echo "$SERVICES"
    echo ""
    
    # Test network connectivity
    echo -e "${YELLOW}Testing network connectivity...${NC}"
    
    # Check if client config exists and test connection
    if [ -f "$CONFIG_DIR/client.toml" ]; then
        SERVER_IP=$(grep "remote_addr" "$CONFIG_DIR/client.toml" | cut -d'"' -f2 | cut -d':' -f1)
        SERVER_PORT=$(grep "remote_addr" "$CONFIG_DIR/client.toml" | cut -d'"' -f2 | cut -d':' -f2)
        
        echo -e "${BLUE}Testing connection to server: $SERVER_IP:$SERVER_PORT${NC}"
        
        if timeout 5 bash -c "</dev/tcp/$SERVER_IP/$SERVER_PORT" 2>/dev/null; then
            echo -e "${GREEN}✓ Server is reachable${NC}"
        else
            echo -e "${RED}✗ Cannot reach server${NC}"
        fi
    fi
    
    # Show service status
    echo ""
    echo -e "${YELLOW}Service status:${NC}"
    systemctl status backhaul-* --no-pager -l
}

# Uninstall Backhaul
uninstall_backhaul() {
    clear_screen
    echo -e "${RED}Uninstall Backhaul${NC}"
    echo ""
    echo -e "${YELLOW}WARNING: This will remove all files and configurations!${NC}"
    read -p "Are you sure? [y/N]: " CONFIRM
    
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
        
        echo -e "${GREEN}Backhaul completely removed!${NC}"
    else
        echo -e "${YELLOW}Operation cancelled${NC}"
    fi
}

# Update Backhaul
update_backhaul() {
    echo -e "${BLUE}Updating Backhaul...${NC}"
    
    # Check current version
    if [ -f "$BINARY_PATH" ]; then
        CURRENT_VERSION=$($BINARY_PATH --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown")
        echo -e "${CYAN}Current version: $CURRENT_VERSION${NC}"
    fi
    
    # Stop services
    systemctl stop backhaul-* 2>/dev/null
    
    # Install new version
    if install_backhaul; then
        # Restart services
        systemctl start backhaul-* 2>/dev/null
        echo -e "${GREEN}Update completed!${NC}"
    else
        echo -e "${RED}Update failed!${NC}"
    fi
}

# Main menu
show_menu() {
    clear_screen
    echo -e "${WHITE}Main Menu:${NC}"
    echo ""
    echo -e "${CYAN}1)${NC}  Install Backhaul"
    echo -e "${CYAN}2)${NC}  Create Server Config"
    echo -e "${CYAN}3)${NC}  Create Client Config"
    echo -e "${CYAN}4)${NC}  Create systemd Service"
    echo -e "${CYAN}5)${NC}  Manage Service"
    echo -e "${CYAN}6)${NC}  View Logs"
    echo -e "${CYAN}7)${NC}  Test Connection"
    echo -e "${CYAN}8)${NC}  Update Backhaul"
    echo -e "${CYAN}9)${NC}  Uninstall"
    echo -e "${CYAN}0)${NC}  Exit"
    echo ""
    echo -e "${BLUE}================================================${NC}"
}

# Main function
main() {
    check_root
    
    while true; do
        show_menu
        echo ""
        read -p "Enter your choice [0-9]: " choice
        echo ""
        
        case $choice in
            1) install_backhaul ;;
            2) create_server_config ;;
            3) create_client_config ;;
            4) create_service ;;
            5) manage_service ;;
            6) view_logs ;;
            7) test_connection ;;
            8) update_backhaul ;;
            9) uninstall_backhaul ;;
            0) 
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0 
                ;;
            *)
                echo -e "${RED}Error: Invalid choice! Please try again.${NC}"
                ;;
        esac
        
        echo ""
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read
    done
}

# Run main function
main
