#!/bin/bash

# Backhaul Advanced Multi-Tunnel Manager
# Version: 4.0
# Author: hayousef68
# Rewritten and Enhanced by Google Gemini

# --- Configuration ---
CONFIG_DIR="/etc/backhaul/configs"
BINARY_PATH="/usr/local/bin/backhaul"
CERT_DIR="/etc/backhaul/certs"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper Functions ---

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root.${NC}"
        exit 1
    fi
}

# Function to detect system architecture for v0.6.5
detect_arch() {
    case $(uname -m) in
        x86_64 | amd64) echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *) echo "" ;;
    esac
}

# --- Core Functions ---

install_backhaul() {
    clear
    echo -e "${BLUE}Installing Backhaul v0.6.5 with Auto-Arch Detection...${NC}"
    ARCH=$(detect_arch)
    if [ -z "$ARCH" ]; then
        echo -e "${RED}Error: Unsupported system architecture '$(uname -m)'.${NC}"
        return
    fi

    local DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_${ARCH}.tar.gz"
    
    echo -e "${CYAN}Downloading for architecture: ${ARCH}...${NC}"
    cd /tmp
    if ! wget -q --show-progress "$DOWNLOAD_URL" -O backhaul.tar.gz; then
        echo -e "${RED}Download failed! Please check your network or the URL.${NC}"
        return
    fi
    
    tar -xzf backhaul.tar.gz
    chmod +x backhaul
    mv backhaul "$BINARY_PATH"
    
    mkdir -p "$CONFIG_DIR"
    rm -f /tmp/backhaul.tar.gz
    echo -e "${GREEN}Backhaul v0.6.5 for ${ARCH} installed successfully!${NC}"
}

generate_self_signed_cert() {
    local name=$1
    if ! command -v openssl &> /dev/null; then
        echo -e "${YELLOW}OpenSSL is not installed. Trying to install...${NC}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y openssl
        elif command -v yum &> /dev/null; then
            yum install -y openssl
        else
            echo -e "${RED}Could not install OpenSSL. Please install it manually.${NC}"
            return 1
        fi
    fi
    mkdir -p "${CERT_DIR}/${name}"
    openssl req -x509 -nodes -newkey rsa:2048 -keyout "${CERT_DIR}/${name}/server.key" -out "${CERT_DIR}/${name}/server.crt" -days 3650 -subj "/CN=backhaul.local"
    echo -e "${GREEN}Self-signed certificate generated in ${CERT_DIR}/${name}${NC}"
}

create_tunnel_config() {
    clear
    echo -e "${PURPLE}--- Create New Tunnel ---${NC}"
    read -p "Enter a unique name for this tunnel (e.g., vps1_tcp): " TUNNEL_NAME
    if [[ -z "$TUNNEL_NAME" || -f "$CONFIG_DIR/${TUNNEL_NAME}.toml" ]]; then
        echo -e "${RED}Error: Tunnel name cannot be empty or already exist.${NC}"
        return
    fi

    echo "Select Role:"
    echo "1) Server (Destination)"
    echo "2) Client (Source)"
    read -p "Choose [1-2]: " ROLE_CHOICE

    clear
    echo "Select Transport Protocol:"
    echo "1) TCP (Simple, fast)"
    echo "2) WS (WebSocket, for traversing firewalls)"
    echo "3) WSS (Secure WebSocket, recommended)"
    read -p "Choose [1-3]: " TRANSPORT_CHOICE

    case $ROLE_CHOICE in
        1) generate_server_config "$TUNNEL_NAME" "$TRANSPORT_CHOICE" ;;
        2) generate_client_config "$TUNNEL_NAME" "$TRANSPORT_CHOICE" ;;
        *) echo -e "${RED}Invalid role selection.${NC}" ;;
    esac
}

generate_server_config() {
    local name=$1
    local transport_choice=$2
    local transport=""
    local config=""

    # Common settings
    read -p "Enter bind port for the server [443]: " BIND_PORT; BIND_PORT=${BIND_PORT:-443}
    read -p "Enter a connection token (password) [my_secret_pass]: " TOKEN; TOKEN=${TOKEN:-my_secret_pass}
    read -p "Enable nodelay? (reduces latency) [Y/n]: " NODELAY_CHOICE; [[ "$NODELAY_CHOICE" =~ ^[Nn]$ ]] && NODELAY="false" || NODELAY="true"
    read -p "Log level (e.g., info, warn, error, debug) [info]: " LOG_LEVEL; LOG_LEVEL=${LOG_LEVEL:-info}

    config="[server]\nbind_addr = \"0.0.0.0:${BIND_PORT}\"\ntoken = \"${TOKEN}\"\nnodelay = ${NODELAY}\nlog_level = \"${LOG_LEVEL}\"\n"

    case $transport_choice in
        1) # TCP
            transport="tcp"
            read -p "Accept UDP? [y/N]: " ACCEPT_UDP; [[ "$ACCEPT_UDP" =~ ^[Yy]$ ]] && UDP="true" || UDP="false"
            read -p "Enter ports to forward (comma-separated, e.g., 80,443,22): " PORTS
            ports_formatted=$(echo "$PORTS" | tr ',' '\n' | sed 's/^[ \t]*//;s/[ \t]*$//' | awk '{printf "%s, ", $0}' | sed 's/, $//')
            config+="transport = \"${transport}\"\naccept_udp = ${UDP}\nports = [${ports_formatted}]\n"
            ;;
        2) # WS
            transport="ws"
            config+="transport = \"${transport}\"\n"
            ;;
        3) # WSS
            transport="wss"
            read -p "Enter path to TLS certificate (.crt): " TLS_CERT
            read -p "Enter path to TLS private key (.key): " TLS_KEY
            if [ -z "$TLS_CERT" ]; then
                read -p "No paths provided. Generate a self-signed cert in ${CERT_DIR}/${name}? [Y/n]: " GEN_CERT
                if [[ ! "$GEN_CERT" =~ ^[Nn]$ ]]; then
                    generate_self_signed_cert "$name"
                    TLS_CERT="${CERT_DIR}/${name}/server.crt"
                    TLS_KEY="${CERT_DIR}/${name}/server.key"
                fi
            fi
            config+="transport = \"${transport}\"\ntls_cert = \"${TLS_CERT}\"\ntls_key = \"${TLS_KEY}\"\n"
            ;;
        *) echo -e "${RED}Invalid transport selection.${NC}"; return ;;
    esac
    
    echo -e "$config" > "$CONFIG_DIR/${name}.toml"
    echo -e "${GREEN}Server config '${name}' created successfully.${NC}"
    create_service "$name"
}

generate_client_config() {
    local name=$1
    local transport_choice=$2
    local transport=""
    local config=""

    # Common settings
    read -p "Enter the remote server's IP address: " SERVER_IP
    read -p "Enter the remote server's port [443]: " SERVER_PORT; SERVER_PORT=${SERVER_PORT:-443}
    read -p "Enter the server's token: " TOKEN
    read -p "Enable nodelay? [Y/n]: " NODELAY_CHOICE; [[ "$NODELAY_CHOICE" =~ ^[Nn]$ ]] && NODELAY="false" || NODELAY="true"
    
    config="[client]\nremote_addr = \"${SERVER_IP}:${SERVER_PORT}\"\ntoken = \"${TOKEN}\"\nnodelay = ${NODELAY}\nretry_interval = 3\n"
    
    case $transport_choice in
        1) transport="tcp" ;;
        2) transport="ws" ;;
        3) transport="wss"; read -p "Enter SNI for WSS (e.g., a domain) [none]: " SNI; SNI=${SNI:-}; config+="sni = \"${SNI}\"\n" ;;
        *) echo -e "${RED}Invalid transport selection.${NC}"; return ;;
    esac
    config+="transport = \"${transport}\"\n"
    
    # Write initial config
    echo -e "$config" > "$CONFIG_DIR/${name}.toml"

    # Add services
    echo -e "\n${PURPLE}--- Define Port Forwarding Rules ---${NC}"
    while true; do
        read -p "Add a port forwarding rule? [Y/n]: " ADD_PORT_CHOICE
        if [[ "$ADD_PORT_CHOICE" =~ ^[Nn]$ ]]; then break; fi
        read -p "  Local port to listen on (on this machine): " LOCAL_PORT
        read -p "  Remote address and port (on the server): " REMOTE_ADDR
        {
            echo "[[client.services]]"
            echo "local_addr = \"0.0.0.0:${LOCAL_PORT}\""
            echo "remote_addr = \"${REMOTE_ADDR}\""
            echo ""
        } >> "$CONFIG_DIR/${name}.toml"
        echo -e "${GREEN}Rule: 0.0.0.0:${LOCAL_PORT} -> ${REMOTE_ADDR} added.${NC}"
    done

    echo -e "${GREEN}Client config '${name}' created successfully.${NC}"
    create_service "$name"
}


# --- Management Functions (Unchanged) ---

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
    systemctl enable "${service_name}" &>/dev/null
    echo -e "${CYAN}Service '${service_name}' created and enabled for auto-start.${NC}"
    read -p "Start the service now? [Y/n]: " START_CHOICE
    if [[ ! "$START_CHOICE" =~ ^[Nn]$ ]]; then
        systemctl start "${service_name}"
        echo -e "${GREEN}Service started.${NC}"
    fi
}

manage_tunnels() {
    clear
    echo -e "${PURPLE}--- Manage Tunnels ---${NC}"
    mapfile -t configs < <(ls -1 "$CONFIG_DIR" 2>/dev/null | sed 's/\.toml$//')
    if [ ${#configs[@]} -eq 0 ]; then
        echo -e "${YELLOW}No tunnels found to manage.${NC}"
        return
    fi
    
    select TUNNEL_NAME in "${configs[@]}" "Back"; do
        if [ "$TUNNEL_NAME" == "Back" ]; then break; fi
        if [ -n "$TUNNEL_NAME" ]; then
            manage_single_tunnel "$TUNNEL_NAME"
            break
        fi
    done
}

manage_single_tunnel() {
    local name=$1
    local service_name="backhaul-${name}"
    while true; do
        clear
        echo -e "${PURPLE}--- Managing Tunnel: ${WHITE}${name}${NC} ---"
        systemctl is-active --quiet "$service_name" && echo -e "Status: ${GREEN}Active${NC}" || echo -e "Status: ${RED}Inactive${NC}"
        echo "-----------------------------------"
        echo "1) Start Service"
        echo "2) Stop Service"
        echo "3) Restart Service"
        echo "4) View Logs"
        echo "5) View/Edit Config"
        echo -e "6) ${RED}Delete Tunnel${NC}"
        echo "7) Back to Main Menu"
        read -p "Choose an option: " choice
        
        case $choice in
            1) systemctl start "$service_name" && echo -e "${GREEN}Service started.${NC}" ;;
            2) systemctl stop "$service_name" && echo -e "${GREEN}Service stopped.${NC}" ;;
            3) systemctl restart "$service_name" && echo -e "${GREEN}Service restarted.${NC}" ;;
            4) journalctl -u "$service_name" -f --no-pager ;;
            5) nano "$CONFIG_DIR/${name}.toml"; systemctl restart "$service_name" ;;
            6)
                read -p "Are you sure you want to delete the tunnel '${name}'? [y/N]: " DEL_CHOICE
                if [[ "$DEL_CHOICE" =~ ^[Yy]$ ]]; then
                    systemctl stop "$service_name" >/dev/null 2>&1
                    systemctl disable "$service_name" >/dev/null 2>&1
                    rm -f "/etc/systemd/system/${service_name}.service"
                    rm -f "$CONFIG_DIR/${name}.toml"
                    systemctl daemon-reload
                    echo -e "${GREEN}Tunnel '${name}' has been deleted.${NC}"
                    return
                fi
                ;;
            7) return ;;
            *) echo -e "${RED}Invalid option!${NC}" ;;
        esac
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

uninstall_backhaul() {
    clear
    read -p "Are you sure you want to completely uninstall Backhaul and ALL tunnels? [y/N]: " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Uninstallation cancelled.${NC}"
        return
    fi
    
    echo "Stopping and deleting all Backhaul services..."
    mapfile -t services < <(ls /etc/systemd/system/backhaul-*.service 2>/dev/null)
    if [ ${#services[@]} -gt 0 ]; then
        for s in "${services[@]}"; do
            systemctl stop "$(basename "$s")"
            systemctl disable "$(basename "$s")"
        done
        rm -f /etc/systemd/system/backhaul-*.service
        systemctl daemon-reload
    fi
    
    echo "Deleting configuration files, certs, and binary..."
    rm -rf "/etc/backhaul"
    rm -f "$BINARY_PATH"
    
    echo -e "${GREEN}Backhaul has been completely uninstalled.${NC}"
}

show_main_menu() {
    clear
    echo -e "${CYAN}================= Backhaul Advanced Manager v4.0 =================${NC}"
    
    if [ ! -f "$BINARY_PATH" ]; then
        echo -e "\n${YELLOW}Backhaul is not installed. Please use option 1 to install.${NC}\n"
    else
        echo -e "\n${PURPLE}--- Existing Tunnels ---${NC}"
        mapfile -t configs < <(ls -1 "$CONFIG_DIR" 2>/dev/null | sed 's/\.toml$//')
        if [ ${#configs[@]} -eq 0 ]; then
            echo -e "${YELLOW}No tunnels found. Create a new one to get started.${NC}"
        else
            for name in "${configs[@]}"; do
                local STATUS
                systemctl is-active --quiet "backhaul-${name}" && STATUS="[${GREEN}Active${NC}]" || STATUS="[${RED}Inactive${NC}]"
                local ROLE=$(grep -q '\[server\]' "$CONFIG_DIR/${name}.toml" && echo "Server" || echo "Client")
                printf " %-12s ${WHITE}%-20s${NC} ${CYAN}(%s)${NC}\n" "$STATUS" "$name" "$ROLE"
            done
        fi
    fi
    
    echo -e "\n${CYAN}--- Main Menu ---${NC}"
    echo "1) Install or Update Backhaul (v0.6.5)"
    echo "2) Create New Tunnel"
    echo "3) Manage Existing Tunnels"
    echo -e "4) ${RED}Uninstall Backhaul Completely${NC}"
    echo "0) Exit"
    echo ""
}

# --- Main Loop ---
check_root
while true; do
    show_main_menu
    read -p "Please select an option: " main_choice
    case $main_choice in
        1) install_backhaul ;;
        2) create_tunnel_config ;;
        3) manage_tunnels ;;
        4) uninstall_backhaul ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option!${NC}" ;;
    esac
    read -n 1 -s -r -p $'\nPress any key to return to the main menu...'
done
