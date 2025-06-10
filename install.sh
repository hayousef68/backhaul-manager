#!/bin/bash

# Backhaul Auto Setup Script - English Version
# Version: 1.2
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
    echo -e "<span class="math-inline">\{CYAN\}\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=</span>{NC}"
    echo -e "${CYAN}            <span class="math-inline">\{WHITE\}Backhaul Auto Manager</span>{CYAN}            <span class="math-inline">\{NC\}"
echo \-e "</span>{CYAN}               <span class="math-inline">\{YELLOW\}v1\.2 \- English</span>{CYAN}               <span class="math-inline">\{NC\}"
echo \-e "</span>{CYAN}================================================${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [[ <span class="math-inline">EUID \-ne 0 \]\]; then
echo \-e "</span>{RED}Error: This script must be run as root!<span class="math-inline">\{NC\}"
echo \-e "</span>{YELLOW}Please run with sudo: sudo bash <span class="math-inline">0</span>{NC}"
        exit 1
    fi
}

# Detect system architecture
detect_arch() {
    case <span class="math-inline">\(uname \-m\) in
x86\_64\|amd64\) echo "linux\-amd64" ;;
aarch64\|arm64\) echo "linux\-arm64" ;;
armv7l\) echo "linux\-armv7" ;;
i386\|i686\) echo "linux\-386" ;;
\*\) echo "unsupported" ;;
esac
\}
\# Download and install Backhaul
install\_backhaul\(\) \{
echo \-e "</span>{BLUE}Installing Backhaul...<span class="math-inline">\{NC\}"
ARCH\=</span>(detect_arch)
    if [ "<span class="math-inline">ARCH" \= "unsupported" \]; then
echo \-e "</span>{RED}Error: Unsupported system architecture!<span class="math-inline">\{NC\}"
return 1
fi
echo \-e "</span>{YELLOW}Getting latest version information...<span class="math-inline">\{NC\}"
LATEST\_VERSION\=</span>(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    
    if [ -z "<span class="math-inline">LATEST\_VERSION" \]; then
echo \-e "</span>{RED}Error: Failed to get version information from GitHub!<span class="math-inline">\{NC\}"
return 1
fi
DOWNLOAD\_URL\="https\://github\.com/Musixal/Backhaul/releases/download/</span>{LATEST_VERSION}/backhaul_${LATEST_VERSION#v}_${ARCH}.tar.gz"
    
    echo -e "${YELLOW}Downloading Backhaul <span class="math-inline">\{LATEST\_VERSION\}\.\.\.</span>{NC}"
    cd /tmp
    if ! wget -q --show-progress "<span class="math-inline">DOWNLOAD\_URL" \-O backhaul\.tar\.gz; then
echo \-e "</span>{RED}Error: Download failed! Please check your network or the URL.${NC}"
        return 1
    fi
    
    tar -xzf backhaul.tar.gz
    chmod +x backhaul
    mv backhaul "$BINARY_PATH"
    
    mkdir -p "<span class="math-inline">CONFIG\_DIR"
echo \-e "</span>{GREEN}Backhaul installed successfully!<span class="math-inline">\{NC\}"
return 0
\}
\# Server type selection
select\_server\_type\(\) \{
echo \-e "</span>{PURPLE}Select server location:${NC}"
    echo "1) Iran Server (Kharej will connect to this)"
    echo "2) Foreign Server (Iran will connect to this)"
    echo ""
    read -p "Enter your choice [1-2]: " SERVER_TYPE
    
    case <span class="math-inline">SERVER\_TYPE in
1\) echo "iran" ;;
2\) echo "foreign" ;;
\*\) echo "iran" ;;
esac
\}
\# Create server config
create\_server\_config\(\) \{
clear\_screen
echo \-e "</span>{PURPLE}Server Configuration${NC}"
    echo ""
    
    SERVER_LOCATION=$(select_server_type)
    
    if [ "<span class="math-inline">SERVER\_LOCATION" \= "iran" \]; then
echo \-e "</span>{CYAN}Configuring Iran Server (Kharej clients will connect)<span class="math-inline">\{NC\}"
DEFAULT\_PORT\=443
else
echo \-e "</span>{CYAN}Configuring Foreign Server (Iran clients will connect)${NC}"
        DEFAULT_PORT=7777
    fi
    
    read -p "Enter server port [<span class="math-inline">DEFAULT\_PORT\]\: " SERVER\_PORT
SERVER\_PORT\=</span>{SERVER_PORT:-<span class="math-inline">DEFAULT\_PORT\}
read \-p "Enter connection password \[mypassword\]\: " PASSWORD
PASSWORD\=</span>{PASSWORD:-mypassword}
    
    echo -e "<span class="math-inline">\{CYAN\}Select transport protocol\:</span>{NC}"
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
    
    HEARTBEAT_CONFIG=""
    SNI_CONFIG=""
    if [ "<span class="math-inline">SERVER\_LOCATION" \= "iran" \]; then
echo ""
echo \-e "</span>{YELLOW}Additional settings for Iran server:${NC}"
        
        read -p "Enable heartbeat? [y/N]: " ENABLE_HEARTBEAT
        if [[ <span class="math-inline">ENABLE\_HEARTBEAT \=\~ ^\[Yy\]</span> ]]; then
            HEARTBEAT_CONFIG="heartbeat = 40"
        fi
        
        if [ "<span class="math-inline">TRANSPORT" \= "wss" \]; then
read \-p "Enter SNI/Domain for WSS \[cloudflare\.com\]\: " SNI\_DOMAIN
SNI\_DOMAIN\=</span>{SNI_DOMAIN:-cloudflare.com}
            SNI_CONFIG="sni = \"$SNI_DOMAIN\""
        fi
    fi
    
    cat > "<span class="math-inline">CONFIG\_DIR/server\.toml" << EOF
\[server\]
bind\_addr \= "0\.0\.0\.0\:</span>{SERVER_PORT}"
transport = "<span class="math-inline">\{TRANSPORT\}"
token \= "</span>{PASSWORD}"
keepalive_period = 75
nodelay = true
$([ -n "$HEARTBEAT_CONFIG" ] && echo "$HEARTBEAT_CONFIG")
$([ -n "$SNI_CONFIG" ] && echo "<span class="math-inline">SNI\_CONFIG"\)
\[server\.channel\_size\]
queue\_size \= 2048
EOF
echo \-e "</span>{GREEN}Server config created successfully!<span class="math-inline">\{NC\}"
echo \-e "</span>{BLUE}Config file: <span class="math-inline">CONFIG\_DIR/server\.toml</span>{NC}"
    echo ""
    echo -e "<span class="math-inline">\{YELLOW\}Server Details\:</span>{NC}"
    echo -e "  Location: ${SERVER_LOCATION^}"
    echo -e "  Port: $SERVER_PORT"
    echo -e "  Transport: $TRANSPORT"
    echo -e "  Password: <span class="math-inline">PASSWORD"
\}
\# Create client config
create\_client\_config\(\) \{
clear\_screen
echo \-e "</span>{PURPLE}Client Configuration${NC}"
    echo ""
    
    echo -e "<span class="math-inline">\{PURPLE\}Select client location\:</span>{NC}"
    echo "1) Iran Client (connects to foreign server)"
    echo "2) Foreign Client (connects to Iran server)"
    echo ""
    read -p "Enter your choice [1-2]: " CLIENT_TYPE
    
    case <span class="math-inline">CLIENT\_TYPE in
1\) 
CLIENT\_LOCATION\="iran"
echo \-e "</span>{CYAN}Configuring Iran Client${NC}"
            ;;
        2) 
            CLIENT_LOCATION="foreign"
            echo -e "<span class="math-inline">\{CYAN\}Configuring Foreign Client</span>{NC}"
            ;;
        *) 
            CLIENT_LOCATION="iran"
            echo -e "<span class="math-inline">\{CYAN\}Configuring Iran Client</span>{NC}"
            ;;
    esac
    
    read -p "Enter server IP address: " SERVER_IP
    if [ -z "<span class="math-inline">SERVER\_IP" \]; then
echo \-e "</span>{RED}Error: Server IP is required!${NC}"
        return 1
    fi
    
    if [ "$CLIENT_LOCATION" = "iran" ]; then
        DEFAULT_SERVER_PORT=7777
        DEFAULT_LOCAL_PORT=8080
        DEFAULT_TARGET_IP="127.0.0.1"
        DEFAULT_TARGET_PORT="22" # Default to SSH port
    else
        DEFAULT_SERVER_PORT=443
        DEFAULT_LOCAL_PORT=22
        DEFAULT_TARGET_IP="127.0.0.1"
        DEFAULT_TARGET_PORT="8080" # Default to a web server port
    fi
    
    read -p "Enter server port [<span class="math-inline">DEFAULT\_SERVER\_PORT\]\: " SERVER\_PORT
SERVER\_PORT\=</span>{SERVER_PORT:-<span class="math-inline">DEFAULT\_SERVER\_PORT\}
read \-p "Enter connection password \[mypassword\]\: " PASSWORD
PASSWORD\=</span>{PASSWORD:-mypassword}
    
    read -p "Enter local port for this machine to listen on [<span class="math-inline">DEFAULT\_LOCAL\_PORT\]\: " LOCAL\_PORT
LOCAL\_PORT\=</span>{LOCAL_PORT:-<span class="math-inline">DEFAULT\_LOCAL\_PORT\}
echo ""
echo \-e "</span>{YELLOW}Enter the target service details on the OTHER server:${NC}"
    read -p "Enter target IP address (usually 127.0.0.1) [<span class="math-inline">DEFAULT\_TARGET\_IP\]\: " TARGET\_IP
TARGET\_IP\=</span>{TARGET_IP:-$DEFAULT_TARGET_IP}
    
    read -p "Enter target port (e.g., 22 for SSH, 8080 for a panel) [<span class="math-inline">DEFAULT\_TARGET\_PORT\]\: " TARGET\_PORT
TARGET\_PORT\=</span>{TARGET_PORT:-<span class="math-inline">DEFAULT\_TARGET\_PORT\}
TARGET\_ADDR\="</span>{TARGET_IP}:<span class="math-inline">\{TARGET\_PORT\}"
echo \-e "</span>{CYAN}Select transport protocol:${NC}"
    echo "1) TCP (Fast, simple)"
    echo "2) WebSocket (WS)"
    echo "3) WebSocket Secure (WSS) - Recommended for Iran"
    echo "4) GRPC"
    echo ""
    
    if [ "<span class="math-inline">CLIENT\_LOCATION" \= "iran" \]; then
read \-p "Enter your choice \[3\]\: " PROTOCOL\_CHOICE
PROTOCOL\_CHOICE\=</span>{PROTOCOL_CHOICE:-3}
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
    
    HEARTBEAT_CONFIG=""
    SNI_CONFIG=""
    if [ "<span class="math-inline">CLIENT\_LOCATION" \= "iran" \]; then
echo ""
echo \-e "</span>{YELLOW}Additional settings for Iran client:${NC}"
        
        read -p "Enable heartbeat? [y/N]: " ENABLE_HEARTBEAT
        if [[ <span class="math-inline">ENABLE\_HEARTBEAT \=\~ ^\[Yy\]</span> ]]; then
            HEARTBEAT_CONFIG="heartbeat = 40"
        fi
        
        if [ "<span class="math-inline">TRANSPORT" \= "wss" \]; then
read \-p "Enter SNI/Domain for WSS \[cloudflare\.com\]\: " SNI\_DOMAIN
SNI\_DOMAIN\=</span>{SNI_DOMAIN:-cloudflare.com}
            SNI_CONFIG="sni = \"$SNI_DOMAIN\""
        fi
    fi
    
    cat > "<span class="math-inline">CONFIG\_DIR/client\.toml" << EOF
\[client\]
remote\_addr \= "</span>{SERVER_IP}:<span class="math-inline">\{SERVER\_PORT\}"
transport \= "</span>{TRANSPORT}"
token = "${PASSWORD}"
keepalive_period = 75
retry_interval = 1
nodelay = true
$([ -n "$HEARTBEAT_CONFIG" ] && echo "$HEARTBEAT_CONFIG")
$([ -n "$SNI_CONFIG" ] && echo "<span class="math-inline">SNI\_CONFIG"\)
\[\[client\.services\]\]
local\_addr \= "0\.0\.0\.0\:</span>{LOCAL_PORT}"
remote_addr = "<span class="math-inline">\{TARGET\_ADDR\}"
\[client\.channel\_size\]
queue\_size \= 2048
EOF
echo \-e "</span>{GREEN}Client config created successfully!<span class="math-inline">\{NC\}"
echo \-e "</span>{BLUE}Config file: <span class="math-inline">CONFIG\_DIR/client\.toml</span>{NC}"
    echo ""
    echo -e "<span class="math-inline">\{YELLOW\}Client Details\:</span>{NC}"
    echo -e "  Location: ${CLIENT_LOCATION^}"
    echo -e "  Server: $SERVER_IP:$SERVER_PORT"
    echo -e "  Local Port (Listening): $LOCAL_PORT"
    echo -e "  Target Service (On other server): $TARGET_ADDR"
    echo -e "  Transport: <span class="math-inline">TRANSPORT"
\}
\# Create systemd service
create\_service\(\) \{
echo \-e "</span>{BLUE}Creating systemd service...${NC}"
    
    echo "Select service type:"
    echo "1) Server"
    echo "2) Client"
    read -p "Enter your choice: " SERVICE_CHOICE
    
    case <span class="math-inline">SERVICE\_CHOICE in
1\)
CONFIG\_FILE\="server\.toml"
SERVICE\_NAME\="backhaul\-server"
DESCRIPTION\="Backhaul Server"
;;
2\)
CONFIG\_FILE\="client\.toml"
SERVICE\_NAME\="backhaul\-client"
DESCRIPTION\="Backhaul Client"
;;
\*\)
echo \-e "</span>{RED}Error: Invalid selection!<span class="math-inline">\{NC\}"
return 1
;;
esac
cat \> "/etc/systemd/system/</span>{SERVICE_NAME}.service" << EOF
[Unit]
Description=<span class="math-inline">\{DESCRIPTION\}
After\=network\.target
StartLimitIntervalSec\=0
\[Service\]
Type\=simple
Restart\=always
RestartSec\=3
User\=root
ExecStart\=</span>{BINARY_PATH} -c <span class="math-inline">\{CONFIG\_DIR\}/</span>{CONFIG_FILE}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "<span class="math-inline">SERVICE\_NAME"
echo \-e "</span>{GREEN}Service <span class="math-inline">\{SERVICE\_NAME\} created and enabled successfully\!</span>{NC}"
    echo -e "<span class="math-inline">\{YELLOW\}You can start it now from the 'Manage Service' menu\.</span>{NC}"
}

# Service management
manage_service() {
    clear_screen
    echo -e "<span class="math-inline">\{PURPLE\}Service Management</span>{NC}"
    echo ""
    
    SERVICES=<span class="math-inline">\(ls /etc/systemd/system/backhaul\-\*\.service 2\>/dev/null \| xargs \-n 1 basename \| sed 's/\\\.service</span>//')
    
    if [ -z "<span class="math-inline">SERVICES" \]; then
echo \-e "</span>{RED}No Backhaul services found!
