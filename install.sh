#!/bin/bash

# Backhaul Tunnel Manager (for Official Core)
# Version: 7.1 (Final Reviewed Version)
# Author: hayousef68
# Rewritten and Polished by Google Gemini for the official v0.6.5 core

# --- Configuration ---
CONFIG_DIR="/etc/backhaul/configs"
BINARY_PATH="/usr/local/bin/backhaul"
CERT_DIR="/etc/backhaul/certs"
SCRIPT_VERSION="v7.1"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper Functions ---

# Ensures the script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root.${NC}"
        exit 1
    fi
}

# Gets the installed core version
get_core_version() {
    if [ -f "$BINARY_PATH" ]; then
        # The official v0.6.5 core might not have a --version flag, so we default
        $BINARY_PATH -V 2>/dev/null | awk '{print $2}' || echo "v0.6.5"
    else
        echo "Not Installed"
    fi
}

# Detects system architecture for downloading the correct binary
detect_arch() {
    case $(uname -m) in
        x86_64 | amd64) echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *) echo "" ;;
    esac
}

# --- Core Functions ---

# Installs or updates the official Backhaul core
install_or_update() {
    clear
    echo -e "${BLUE}Installing/Updating Official Backhaul Core (v0.6.5)...${NC}"
    ARCH=$(detect_arch)
    if [ -z "$ARCH" ]; then
        echo -e "${RED}Error: Unsupported system architecture '$(uname -m)'.${NC}"
        return
    fi
    local DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_${ARCH}.tar.gz"
    echo -e "${CYAN}Downloading official core for architecture: ${ARCH}...${NC}"
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
    echo -e "${GREEN}Backhaul Core v0.6.5 installed/updated successfully!${NC}"
}

# Generates a self-signed certificate for WSS transport
generate_self_signed_cert() {
    local name=$1
    if ! command -v openssl &> /dev/null; then
        echo -e "${YELLOW}OpenSSL not found. Attempting to install...${NC}"
        (apt-get update && apt-get install -y openssl) || (yum install -y openssl) || { echo -e "${RED}Failed to install OpenSSL.${NC}"; return 1; }
    fi
    mkdir -p "${CERT_DIR}/${name}"
    openssl req -x509 -nodes -newkey rsa:2048 -keyout "${CERT_DIR}/${name}/server.key" -out "${CERT_DIR}/${name}/server.crt" -days 3650 -subj "/CN=backhaul.local"
    echo -e "${GREEN}Self-signed certificate generated in ${CERT_DIR}/${name}${NC}"
}

# Main function to start the tunnel configuration process
configure_new_tunnel() {
    clear
    echo -e "${PURPLE}--- Configure a New Tunnel ---${NC}"
    read -p "Enter a unique name for this tunnel (e.g., iran_server): " name
    if [[ -z "$name" || -f "$CONFIG_DIR/${name}.toml" ]]; then
        echo -e "${RED}Error: Config name cannot be empty or already exist.${NC}"
        return
    fi

    echo "1) Configure as Server (Destination)"
    echo "2) Configure as Client (Source)"
    read -p "Enter your choice: " ROLE_CHOICE

    if [ "$ROLE_CHOICE" == "1" ]; then
        generate_server_config "$name"
    elif [ "$ROLE_CHOICE" == "2" ]; then
        generate_client_config "$name"
    else
        echo -e "${RED}Invalid choice.${NC}"
    fi
}

# Generates the server-side configuration file
generate_server_config() {
    local name=$1
    clear
    echo -e "${CYAN}--- Configuring Server: ${name} ---${NC}"
    
    echo "Select Transport (WSS is recommended for stability):"
    echo "1) tcp"
    echo "2) ws (WebSocket)"
    echo "3) wss (Secure WebSocket)"
    read -p "Choose [1-3]: " TRANSPORT_CHOICE

    read -p "[+] Bind Port [443]: " BIND_PORT; BIND_PORT=${BIND_PORT:-443}
    read -p "[+] Security Token: " TOKEN
    read -p "[-] Enable TCP_NODELAY (recommended) [true]: " NODELAY; NODELAY=${NODELAY:-true}

    local config="[server]\nbind_addr = \"0.0.0.0:${BIND_PORT}\"\ntoken = \"${TOKEN}\"\nnodelay = ${NODELAY}\n"

    case $TRANSPORT_CHOICE in
        1) config+="transport = \"tcp\"\n" ;;
        2) config+="transport = \"ws\"\n" ;;
        3) 
            config+="transport = \"wss\"\n"
            read -p "[-] Path to TLS certificate (.crt): " TLS_CERT
            read -p "[-] Path to TLS private key (.key): " TLS_KEY
            if [ -z "$TLS_CERT" ]; then
                read -p "No paths provided. Generate a self-signed cert? [Y/n]: " GEN_CERT
                if [[ ! "$GEN_CERT" =~ ^[Nn]$ ]]; then
                    generate_self_signed_cert "$name"
                    TLS_CERT="${CERT_DIR}/${name}/server.crt"
                    TLS_KEY="${CERT_DIR}/${name}/server.key"
                fi
            fi
            config+="tls_cert = \"${TLS_CERT}\"\ntls_key = \"${TLS_KEY}\"\n"
            ;;
        *) echo -e "${RED}Invalid transport.${NC}"; return ;;
    esac

    echo -e "$config" > "$CONFIG_DIR/${name}.toml"
    echo -e "${GREEN}Server config '${name}' created successfully.${NC}"
    create_service "$name"
}

# Generates the client-side configuration file
generate_client_config() {
    local name=$1
    clear
    echo -e "${CYAN}--- Configuring Client: ${name} ---${NC}"

    echo "Select Transport (must match server):"
    echo "1) tcp"
    echo "2) ws"
    echo "3) wss"
    read -p "Choose [1-3]: " TRANSPORT_CHOICE

    read -p "[+] Remote server address (IP:PORT): " REMOTE_ADDR
    read -p "[+] Security Token: " TOKEN
    read -p "[-] Enable TCP_NODELAY (recommended) [true]: " NODELAY; NODELAY=${NODELAY:-true}

    local config="[client]\nremote_addr = \"${REMOTE_ADDR}\"\ntoken = \"${TOKEN}\"\nnodelay = ${NODELAY}\n"
    
    case $TRANSPORT_CHOICE in
        1) config+="transport = \"tcp\"\n" ;;
        2) config+="transport = \"ws\"\n" ;;
        3) 
            config+="transport = \"wss\"\n"
            read -p "[-] SNI for WSS (e.g., a domain) [optional]: " SNI
            if [ -n "$SNI" ]; then config+="sni = \"${SNI}\"\n"; fi
            ;;
        *) echo -e "${RED}Invalid transport.${NC}"; return ;;
    esac
    
    # Save the base config first
    echo -e "$config" > "$CONFIG_DIR/${name}.toml"

    # Loop to add multiple port forwarding rules
    echo -e "\n${PURPLE}--- Define Port Forwarding Rules ---${NC}"
    while true; do
        read -p "Add a port forwarding rule? [Y/n]: " ADD_RULE
        if [[ "$ADD_RULE" =~ ^[Nn]$ ]]; then break; fi
        read -p "  Local address to listen on (e.g., 0.0.0.0:8080): " LOCAL_ADDR
        read -p "  Remote address on the server (e.g., 127.0.0.1:22): " TARGET_ADDR
        # Append the service block to the config file
        { echo ""; echo "[[client.services]]"; echo "local_addr = \"${LOCAL_ADDR}\""; echo "remote_addr = \"${TARGET_ADDR}\""; } >> "$CONFIG_DIR/${name}.toml"
        echo -e "${GREEN}Rule: ${LOCAL_ADDR} -> ${TARGET_ADDR} added.${NC}"
    done
    
    echo -e "${GREEN}Client config '${name}' created successfully.${NC}"
    create_service "$name"
}

# Creates a systemd service file for a given tunnel config
create_service() {
    local name=$1
    local service_name="backhaul-${name}"
    cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=Backhaul Tunnel (${name})
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
    read -p "Start the service now? [Y/n]: " START
    if [[ ! "$START" =~ ^[Nn]$ ]]; then
        systemctl start "${service_name}"
        echo -e "${GREEN}Service started.${NC}"
    fi
}

# Main menu for managing all existing tunnels
tunnel_management_menu() {
    clear
    echo -e "${PURPLE}--- Tunnel Management ---${NC}"
    mapfile -t configs < <(ls -1 "$CONFIG_DIR" 2>/dev/null | sed 's/\.toml$//')
    if [ ${#configs[@]} -eq 0 ]; then echo -e "${YELLOW}No tunnels found.${NC}"; return; fi
    
    echo "Select a service to manage:"
    select name in "${configs[@]}" "Back"; do
        if [ "$name" == "Back" ]; then break; fi
        if [ -n "$name" ]; then manage_single_tunnel "$name"; break; fi
    done
}

# Menu for managing a single, specific tunnel
manage_single_tunnel() {
    local name=$1; local service="backhaul-${name}"
    while true; do
        clear
        echo -e "${PURPLE}--- Managing: ${WHITE}${name}${NC} ---"
        systemctl is-active --quiet "$service" && echo -e "Status: ${GREEN}Active${NC}" || echo -e "Status: ${RED}Inactive${NC}"
        echo "--------------------------"
        echo "1) Start"; echo "2) Stop"; echo "3) Restart"; echo "4) Logs"; echo "5) Edit Config"; echo -e "6) ${RED}Delete${NC}"; echo "0) Back"
        read -p "Option: " choice
        case $choice in
            1) systemctl start "$service" ;; 2) systemctl stop "$service" ;; 3) systemctl restart "$service" ;; 4) journalctl -u "$service" -f --no-pager ;;
            5) 
                if ! command -v nano &> /dev/null; then echo -e "${RED}Editor 'nano' not found. Please install it first.${NC}"; else nano "$CONFIG_DIR/${name}.toml" && systemctl restart "$service"; fi
                ;;
            6) 
                read -p "Confirm deletion of tunnel '${name}' [y/N]: " D
                if [[ "$D" =~ ^[Yy]$ ]]; then
                    systemctl stop "$service" &>/dev/null; systemctl disable "$service" &>/dev/null
                    rm -f "/etc/systemd/system/${service}.service" "$CONFIG_DIR/${name}.toml"
                    systemctl daemon-reload
                    echo -e "${GREEN}Tunnel '${name}' deleted.${NC}"; return
                fi
                ;;
            0) return ;; *) echo -e "${RED}Invalid option.${NC}" ;;
        esac
        read -n 1 -s -r -p "Press any key..."
    done
}

# Uninstalls the Backhaul core and all related files
remove_backhaul() {
    read -p "Confirm removal of Backhaul and ALL configs [y/N]: " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        systemctl stop backhaul-* &>/dev/null; systemctl disable backhaul-* &>/dev/null
        rm -f /etc/systemd/system/backhaul-*.service; systemctl daemon-reload
        rm -rf "/etc/backhaul"; rm -f "$BINARY_PATH"
        echo -e "${GREEN}Backhaul removed successfully.${NC}"
    else
        echo -e "${YELLOW}Removal cancelled.${NC}"
    fi
}

# Displays the main menu of the script
show_main_menu() {
    clear
    local core_v=$(get_core_version)
    echo -e "${CYAN}Backhaul Manager (Official Core) - Script ${SCRIPT_VERSION}${NC}"
    echo -e "------------------------------------------------"
    if [[ "$core_v" == "Not Installed" ]]; then
        echo -e "${YELLOW}Core Status: Not Installed${NC}"
    else
        echo -e "${CYAN}Core Status: ${GREEN}Installed (v${core_v})${NC}"
    fi
    echo -e "------------------------------------------------"
    echo "1. Configure a New Tunnel"
    echo "2. Tunnel Management"
    echo "3. Update/Install Backhaul Core"
    echo "4. Remove Backhaul Core"
    echo "0. Exit"
    echo "------------------------------------------------"
}

# --- Main Loop ---
check_root
while true; do
    show_main_menu
    read -p "Enter your choice [0-4]: " main_choice
    case $main_choice in
        1) configure_new_tunnel ;; 2) tunnel_management_menu ;; 3) install_or_update ;;
        4) remove_backhaul ;; 0) exit 0 ;; *) echo -e "${RED}Invalid choice!${NC}" ;;
    esac
    read -n 1 -s -r -p $'\nPress any key to return to main menu...'
done
