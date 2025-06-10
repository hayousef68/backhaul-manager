#!/bin/bash

# Backhaul Professional Tunnel Manager
# Version: 5.1 (tcpmux support added)
# Author: hayousef68
# Rewritten and Enhanced by Google Gemini

# --- Configuration ---
CONFIG_DIR="/etc/backhaul/configs"
BINARY_PATH="/usr/local/bin/backhaul"
SCRIPT_VERSION="v5.1"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper Functions ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root.${NC}"
        exit 1
    fi
}

get_core_version() {
    if [ -f "$BINARY_PATH" ]; then
        $BINARY_PATH -V 2>/dev/null | awk '{print $2}'
    else
        echo "Not Installed"
    fi
}

detect_arch() {
    case $(uname -m) in
        x86_64 | amd64) echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *) echo "" ;;
    esac
}

# --- Core Functions ---

install_or_update() {
    clear
    echo -e "${BLUE}Installing/Updating Backhaul Core...${NC}"
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
    echo -e "${GREEN}Backhaul Core installed/updated successfully!${NC}"
}

configure_new_tunnel() {
    clear
    echo -e "${PURPLE}--- Configure a New Tunnel ---${NC}"
    echo "1) Configure for IRAN server (Destination)"
    echo "2) Configure for KHAREJ server (Source/Client)"
    read -p "Enter your choice: " ROLE_CHOICE

    clear
    local name
    if [ "$ROLE_CHOICE" == "1" ]; then
        read -p "Enter a name for this IRAN server config: " name
        generate_server_config "$name"
    elif [ "$ROLE_CHOICE" == "2" ]; then
        read -p "Enter a name for this KHAREJ client config: " name
        generate_client_config "$name"
    else
        echo -e "${RED}Invalid choice.${NC}"
    fi
}

generate_server_config() {
    local name=$1
    if [[ -z "$name" || -f "$CONFIG_DIR/${name}.toml" ]]; then
        echo -e "${RED}Error: Config name cannot be empty or already exist.${NC}"
        return
    fi
    clear
    echo -e "${CYAN}--- Configuring IRAN Server: ${name} ---${NC}"
    
    # Transport Selection
    echo "Select Transport Protocol:"
    echo "1) tcp"
    echo "2) tcpmux (Advanced, for multiplexing)"
    echo "3) ws"
    echo "4) wss"
    read -p "Choose [1-4]: " TRANSPORT_CHOICE
    
    # Common settings
    read -p "[+] Tunnel port: " BIND_PORT
    read -p "[+] Security Token (press enter for default): " TOKEN
    read -p "[+] Channel Size (default 2048): " CHANNEL_SIZE; CHANNEL_SIZE=${CHANNEL_SIZE:-2048}
    read -p "[-] Enable TCP_NODELAY (true/false) [true]: " NODELAY; NODELAY=${NODELAY:-true}
    read -p "[-] Heartbeat (in seconds, default 40): " HEARTBEAT; HEARTBEAT=${HEARTBEAT:-40}
    
    local config="[server]\nbind_addr = \"0.0.0.0:${BIND_PORT}\"\ntoken = \"${TOKEN}\"\nchannel_size = ${CHANNEL_SIZE}\nnodelay = ${NODELAY}\nheartbeat = ${HEARTBEAT}\n"

    case $TRANSPORT_CHOICE in
        1) # TCP
            config+="transport = \"tcp\"\n"
            read -p "[-] Accept UDP connections (true/false) [false]: " ACCEPT_UDP; ACCEPT_UDP=${ACCEPT_UDP:-false}
            config+="accept_udp = ${ACCEPT_UDP}\n"
            ;;
        2) # TCPMUX
            config+="transport = \"tcpmux\"\n"
            echo -e "${YELLOW}--- Advanced MUX Settings ---${NC}"
            read -p "[-] MUX Connections (default 8): " MUX_CON; MUX_CON=${MUX_CON:-8}
            read -p "[-] MUX Frame Size (default 32768): " MUX_FRAMESIZE; MUX_FRAMESIZE=${MUX_FRAMESIZE:-32768}
            read -p "[-] MUX Receive Buffer (default 4194304): " MUX_RECEIVEBUFFER; MUX_RECEIVEBUFFER=${MUX_RECEIVEBUFFER:-4194304}
            read -p "[-] MUX Stream Buffer (default 65536): " MUX_STREAMBUFFER; MUX_STREAMBUFFER=${MUX_STREAMBUFFER:-65536}
            config+="mux_con = ${MUX_CON}\nmux_framesize = ${MUX_FRAMESIZE}\nmux_recievebuffer = ${MUX_RECEIVEBUFFER}\nmux_streambuffer = ${MUX_STREAMBUFFER}\n"
            ;;
        3) # WS
            config+="transport = \"ws\"\n"
            ;;
        4) # WSS
            config+="transport = \"wss\"\n"
            read -p "[-] Path to TLS certificate (.crt): " TLS_CERT
            read -p "[-] Path to TLS private key (.key): " TLS_KEY
            config+="tls_cert = \"${TLS_CERT}\"\ntls_key = \"${TLS_KEY}\"\n"
            ;;
        *) echo -e "${RED}Invalid transport selection.${NC}"; return ;;
    esac

    # Handle port list for TCP-based transports
    if [[ "$TRANSPORT_CHOICE" == "1" || "$TRANSPORT_CHOICE" == "2" ]]; then
        echo -e "\n${YELLOW}[*] Supported Port Formats for TCP/TCPMUX Server:${NC}"
        echo "  - 443-600 (range), 80 (single), 1000:2000 (local:remote), 443=1.1.1.1:5201 (local=remote_ip:port)"
        read -p "[+] Enter your ports (comma-separated): " PORTS
        ports_formatted=$(echo "$PORTS" | tr -d ' ' | sed 's/,/","/g')
        config+="ports = [\"${ports_formatted}\"]\n"
    fi

    # Save and create service
    echo -e "$config" > "$CONFIG_DIR/${name}.toml"
    echo -e "${GREEN}Server config '${name}' created successfully.${NC}"
    create_service "$name"
}

generate_client_config() {
    local name=$1
    if [[ -z "$name" || -f "$CONFIG_DIR/${name}.toml" ]]; then
        echo -e "${RED}Error: Config name cannot be empty or already exist.${NC}"
        return
    fi
    clear
    echo -e "${CYAN}--- Configuring KHAREJ Client: ${name} ---${NC}"
    
    # Transport Selection
    echo "Select Transport Protocol (must match server):"
    echo "1) tcp"
    echo "2) tcpmux"
    echo "3) ws"
    echo "4) wss"
    read -p "Choose [1-4]: " TRANSPORT_CHOICE

    # Common settings
    read -p "[+] Remote server address (IP:PORT): " REMOTE_ADDR
    read -p "[+] Security Token: " TOKEN
    read -p "[-] Enable TCP_NODELAY (true/false) [true]: " NODELAY; NODELAY=${NODELAY:-true}
    
    local config="[client]\nremote_addr = \"${REMOTE_ADDR}\"\ntoken = \"${TOKEN}\"\nnodelay = ${NODELAY}\n"

    case $TRANSPORT_CHOICE in
        1) config+="transport = \"tcp\"\n" ;;
        2) 
            config+="transport = \"tcpmux\"\n"
            echo -e "${YELLOW}--- Advanced MUX Settings ---${NC}"
            read -p "[-] Connection Pool Size (default 8): " CONN_POOL; CONN_POOL=${CONN_POOL:-8}
            read -p "[-] Use Aggressive Pooling (true/false) [false]: " AGGRESSIVE_POOL; AGGRESSIVE_POOL=${AGGRESSIVE_POOL:-false}
            config+="connection_pool = ${CONN_POOL}\naggressive_pool = ${AGGRESSIVE_POOL}\n"
            ;;
        3) config+="transport = \"ws\"\n" ;;
        4) 
            config+="transport = \"wss\"\n"
            read -p "[-] SNI for WSS (e.g., domain.com) [optional]: " SNI
            if [ -n "$SNI" ]; then config+="sni = \"${SNI}\"\n"; fi
            ;;
        *) echo -e "${RED}Invalid transport selection.${NC}"; return ;;
    esac
    
    # Write base config
    echo -e "$config" > "$CONFIG_DIR/${name}.toml"

    # Add services (port forwarding rules)
    echo -e "\n${PURPLE}--- Define Port Forwarding Rules ---${NC}"
    while true; do
        read -p "Add a port forwarding rule? [Y/n]: " ADD_PORT_CHOICE
        if [[ "$ADD_PORT_CHOICE" =~ ^[Nn]$ ]]; then break; fi
        read -p "  Local address to listen on (e.g., 0.0.0.0:8080): " LOCAL_ADDR
        read -p "  Remote address on the server (e.g., 127.0.0.1:22): " TARGET_ADDR
        {
            echo ""
            echo "[[client.services]]"
            echo "local_addr = \"${LOCAL_ADDR}\""
            echo "remote_addr = \"${TARGET_ADDR}\""
        } >> "$CONFIG_DIR/${name}.toml"
        echo -e "${GREEN}Rule: ${LOCAL_ADDR} -> ${TARGET_ADDR} added.${NC}"
    done
    
    echo -e "${GREEN}Client config '${name}' created successfully.${NC}"
    create_service "$name"
}

# --- Management Functions (mostly unchanged) ---

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
    echo -e "${CYAN}Service '${service_name}' created and enabled.${NC}"
    read -p "Start the service now? [Y/n]: " START_CHOICE
    if [[ ! "$START_CHOICE" =~ ^[Nn]$ ]]; then
        systemctl start "${service_name}"
        echo -e "${GREEN}Service started.${NC}"
    fi
}

tunnel_management_menu() {
    clear
    echo -e "${PURPLE}--- Tunnel Management Menu ---${NC}"
    mapfile -t configs < <(ls -1 "$CONFIG_DIR" 2>/dev/null | sed 's/\.toml$//')
    if [ ${#configs[@]} -eq 0 ]; then
        echo -e "${YELLOW}No tunnels found to manage.${NC}"
        return
    fi
    
    echo "List of existing services to manage:"
    i=1
    for name in "${configs[@]}"; do
        local BIND_PORT=$(grep 'bind_addr' "$CONFIG_DIR/${name}.toml" 2>/dev/null | cut -d':' -f2 | tr -d '"')
        if [ -z "$BIND_PORT" ]; then
             BIND_PORT=$(grep 'remote_addr' "$CONFIG_DIR/${name}.toml" 2>/dev/null | cut -d':' -f2 | tr -d '"')
        fi
        echo "$i) $name, Tunnel port: $BIND_PORT"
        let i++
    done
    
    read -p "Enter your choice (0 to return): " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -eq 0 ]; then return; fi
    
    local selected_name=${configs[$((choice-1))]}
    if [ -z "$selected_name" ]; then
        echo -e "${RED}Invalid selection.${NC}"
        return
    fi
    manage_single_tunnel "$selected_name"
}

manage_single_tunnel() {
    local name=$1
    local service_name="backhaul-${name}"
    while true; do
        clear
        echo -e "${PURPLE}--- Managing Tunnel: ${WHITE}${name}${NC} ---"
        systemctl is-active --quiet "$service_name" && echo -e "Status: ${GREEN}Active${NC}" || echo -e "Status: ${RED}Inactive${NC}"
        echo "-----------------------------------"
        echo "1) Start"
        echo "2) Stop"
        echo "3) Restart"
        echo "4) View Logs"
        echo "5) Edit Config"
        echo -e "6) ${RED}Delete Tunnel${NC}"
        echo "0) Back"
        read -p "Choose an option: " choice
        
        case $choice in
            1) systemctl start "$service_name" ;;
            2) systemctl stop "$service_name" ;;
            3) systemctl restart "$service_name" ;;
            4) journalctl -u "$service_name" -f --no-pager ;;
            5) nano "$CONFIG_DIR/${name}.toml" && systemctl restart "$service_name" ;;
            6)
                read -p "Are you sure? [y/N]: " DEL_CHOICE
                if [[ "$DEL_CHOICE" =~ ^[Yy]$ ]]; then
                    systemctl stop "$service_name" >/dev/null 2>&1
                    systemctl disable "$service_name" >/dev/null 2>&1
                    rm -f "/etc/systemd/system/${service_name}.service"
                    rm -f "$CONFIG_DIR/${name}.toml"
                    systemctl daemon-reload
                    echo -e "${GREEN}Tunnel deleted.${NC}"
                    return
                fi
                ;;
            0) return ;;
            *) echo -e "${RED}Invalid option!${NC}" ;;
        esac
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

remove_backhaul() {
    clear
    read -p "This will remove Backhaul Core and ALL configurations. Are you sure? [y/N]: " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        systemctl stop backhaul-* &>/dev/null
        systemctl disable backhaul-* &>/dev/null
        rm -f /etc/systemd/system/backhaul-*.service
        systemctl daemon-reload
        rm -rf "/etc/backhaul"
        rm -f "$BINARY_PATH"
        echo -e "${GREEN}Backhaul has been completely removed.${NC}"
    else
        echo -e "${YELLOW}Removal cancelled.${NC}"
    fi
}

show_main_menu() {
    clear
    local core_v=$(get_core_version)
    echo -e "${CYAN}Script Version : ${WHITE}${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}Core Version   : ${WHITE}${core_v}${NC}"
    echo -e "-------------------------------------------"
    if [[ "$core_v" == "Not Installed" ]]; then
      echo -e "${YELLOW}Backhaul Core: Not Installed${NC}"
    else
      echo -e "${CYAN}Backhaul Core: ${GREEN}Installed${NC}"
    fi
    echo -e "-------------------------------------------"
    echo -e "1. Configure a new tunnel"
    echo -e "2. Tunnel management menu"
    echo -e "3. Update & Install Backhaul Core"
    echo -e "4. Remove Backhaul Core"
    echo -e "0. Exit"
    echo -e "-------------------------------------------"
}

# --- Main Loop ---
check_root
while true; do
    show_main_menu
    read -p "Enter your choice [0-4]: " main_choice
    case $main_choice in
        1) configure_new_tunnel ;;
        2) tunnel_management_menu ;;
        3) install_or_update ;;
        4) remove_backhaul ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid choice!${NC}" ;;
    esac
    read -n 1 -s -r -p $'\nPress any key to return to main menu...'
done
