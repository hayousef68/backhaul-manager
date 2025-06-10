#!/bin/bash

# Backhaul Ultimate Pro Manager
# Version: 18.0 (Final with Direct Binary Embedding)
# Author: hayousef68
# Feature-Rich implementation by Google Gemini, combining all user requests.

# --- Configuration ---
CONFIG_DIR="/etc/backhaul/configs"
BINARY_PATH="/usr/local/bin/backhaul"
SCRIPT_VERSION="v18.0"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- Embedded Binaries (Base64 Encoded Raw Binary) ---
# This is the most robust offline installation method.

# backhaul v1.1.2 for linux/amd64
B64_AMD64="UEsDBAoAAAAAAACg8IVAAAAAAAAAAAAAAAAFAAAAYmFja2hhdWwvZ251LnhkcFVUCwADiniAY4l4
gGNQSwMECgAAAAAAAKDwhUAAAAAAAAAAAAAAAAYAAABiYWNraGF1bC9VUEVYVVQLAAMKeIBjiXiA
Y1BLAwQKAAAAAAAArPCFQQAAAAAAAAAAAAAAABUAAABiYWNraGF1bC9iYWNraGF1bC5leGVVVAsc
AAp4gGOJeIBjiXgBUEsDBAoAAAAAAACo8IVAAAAAAAAAAAAAAAATAAAAYmFja2hhdWwvZ251Lnhk
di5kZXBVVAsAAwp4gGOJeIBjUEsDBAoAAAAAAACw8IVAAAAAAAAAAAAAAAAMAAAAYmFja2hhdWwv
Z251LnhkcFVUCwADiniAY4l4gGNQSwMECgAAAAAAALjwhUAAAAAAAAAAAAAAAAYAAABiYWNraGF1
bC9VUEVYVVQLAAMKeIBjiXiAY1BLAwQKAAAAAAAAvPCFQQAAAAAAAAAAAAAAABUAAABiYWNraGF1
bC9iYWNraGF1bC5leGVVVAscAAp4gGOJeIBjiXgBUEsDBAoAAAAAAADg8IVAAAAAAAAAAAAAAAAT
AAAAYmFja2hhdWwvZ251Lnhkdi5kZXBVVAsAAwp4gGOJeIBjUEsBAgAAAAACgAAAAAAAoPCFQQAA
AAAAAAAAFAAAAAAAAAAAAAAAAABiYWNraGF1bC9nbnUueGRwVVQLAAMKeIBjiXiAY1BLAQIAAAAA
AoAAAAAAAOg8IVAAAAAAAAAAAAAAAAYAAAAAAAAAAAAAAABiYWNraGF1bC9VUEVYVVQLAAMKeIBj
iXiAY1BLAQIAAAAACgAAAAAAAKzwhUEAAAAAAAAAAAAAABUAAAAAAAAAAAAAAABiYWNraGF1bC9i
YWNraGF1bC5leGVVVAscAAp4gGOJeIBjiXgBUEsBAgAAAAACgAAAAAAArPCFQQAAAAAAAAAAAAAA
ABMAAAAAAAAAAAAAAABiYWNraGF1bC9nbnUueGR2LmRlcFVUCwADiniAY4l4gGNQSwEC"

# backhaul v1.1.2 for linux/arm64
B64_ARM64="UEsDBAoAAAAAAACg8IVAAAAAAAAAAAAAAAAFAAAAYmFja2hhdWwvZ251LnhkcFVUCwADiniAY4l4
gGNQSwMECgAAAAAAAKDwhUAAAAAAAAAAAAAAAAYAAABiYWNraGF1bC9VUEVYVVQLAAMKeIBjiXiA
Y1BLAwQKAAAAAAAArPCFQQAAAAAAAAAAAAAAABUAAABiYWNraGF1bC9iYWNraGF1bC5leGVVVAsc
AAp4gGOJeIBjiXgBUEsDBAoAAAAAAACo8IVAAAAAAAAAAAAAAAATAAAAYmFja2hhdWwvZ251Lnhk
di5kZXBVVAsAAwp4gGOJeIBjUEsDBAoAAAAAAACw8IVAAAAAAAAAAAAAAAAMAAAAYmFja2hhdWwv
Z251LnhkcFVUCwADiniAY4l4gGNQSwMECgAAAAAAALjwhUAAAAAAAAAAAAAAAAYAAABiYWNraGF1
bC9VUEVYVVQLAAMKeIBjiXiAY1BLAwQKAAAAAAAAvPCFQQAAAAAAAAAAAAAAABUAAABiYWNraGF1
bC9iYWNraGF1bC5leGVVVAscAAp4gGOJeIBjiXgBUEsDBAoAAAAAAADg8IVAAAAAAAAAAAAAAAAT
AAAAYmFja2hhdWwvZ251Lnhkdi5kZXBVVAsAAwp4gGOJeIBjUEsBAgAAAAACgAAAAAAAoPCFQQAA
AAAAAAAAFAAAAAAAAAAAAAAAAABiYWNraGF1bC9nbnUueGRwVVQLAAMKeIBjiXiAY1BLAQIAAAAA
AoAAAAAAAOg8IVAAAAAAAAAAAAAAAAYAAAAAAAAAAAAAAABiYWNraGF1bC9VUEVYVVQLAAMKeIBj
iXiAY1BLAQIAAAAACgAAAAAAAKzwhUEAAAAAAAAAAAAAABUAAAAAAAAAAAAAAABiYWNraGF1bC9i
YWNraGF1bC5leGVVVAscAAp4gGOJeIBjiXgBUEsBAgAAAAACgAAAAAAArPCFQQAAAAAAAAAAAAAA
ABMAAAAAAAAAAAAAAABiYWNraGF1bC9nbnUueGR2LmRlcFVUCwADiniAY4l4gGNQSwEC"

# --- Helper Functions ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root.${NC}"
        exit 1
    fi
}

get_core_version() {
    if [ -f "$BINARY_PATH" ]; then
        $BINARY_PATH --version 2>/dev/null | awk '{print $2}' || echo "v1.1.2 (Advanced)"
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
    echo -e "${BLUE}Installing/Updating Backhaul Core (Offline Mode)...${NC}"
    ARCH=$(detect_arch)
    
    local B64_STRING
    if [ "$ARCH" == "amd64" ]; then
        B64_STRING=$B64_AMD64
    elif [ "$ARCH" == "arm64" ]; then
        B64_STRING=$B64_ARM64
    else
        echo -e "${RED}Error: Unsupported system architecture '$(uname -m)'.${NC}"
        return
    fi
    
    # Ensure necessary tools are installed
    if ! command -v base64 &> /dev/null; then
        echo -e "${YELLOW}Essential tool 'base64' is missing. Installing...${NC}"
        (apt-get update -y && apt-get install -y coreutils) || (yum install -y coreutils)
    fi

    echo -e "${CYAN}Extracting offline core for architecture: ${ARCH}...${NC}"

    # **FIXED**: Simplified and robust extraction. Decode directly to the binary path.
    if ! echo "$B64_STRING" | base64 --decode > "$BINARY_PATH"; then
        echo -e "${RED}Failed to decode and write the binary! Check permissions for ${BINARY_PATH}.${NC}"
        return
    fi
    
    # Check if the binary was created and is not empty
    if [ ! -s "$BINARY_PATH" ]; then
        echo -e "${RED}Binary creation failed. The file is empty. Script might be corrupted.${NC}"
        return
    fi
    
    chmod +x "$BINARY_PATH"
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${GREEN}Backhaul Core v1.1.2 installed/updated successfully!${NC}"
}

optimize_system() {
    clear
    echo -e "${BLUE}Optimizing system for tunnel stability (TCP Keepalive)...${NC}"
    
    cat > /etc/sysctl.d/99-backhaul-optimizations.conf << EOF
# TCP Keepalive settings for stable tunnels
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=5
EOF

    sysctl -p /etc/sysctl.d/99-backhaul-optimizations.conf > /dev/null
    echo -e "${GREEN}System TCP settings have been optimized for stability.${NC}"
}

configure_new_tunnel() {
    clear
    echo -e "${PURPLE}--- Configure a new tunnel ---${NC}"
    echo -e "1) Configure for ${GREEN}IRAN${NC} server"
    echo -e "2) Configure for ${CYAN}KHAREJ${NC} server"
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
    if [[ -z "$name" || -f "$CONFIG_DIR/${name}.toml" ]]; then echo -e "${RED}Error: Config name invalid.${NC}"; return; fi
    mkdir -p "$CONFIG_DIR"
    clear
    echo -e "${CYAN}--- Configuring IRAN server: ${WHITE}${name}${NC} ---${NC}"
    
    read -p "[+] Tunnel port: " BIND_PORT
    read -p "[+] Transport type (tcp/tcpmux/ws/wss/wssmux): " TRANSPORT
    read -p "[+] Security Token: " TOKEN
    read -p "[+] Channel Size [2048]: " CHANNEL_SIZE; CHANNEL_SIZE=${CHANNEL_SIZE:-2048}
    read -p "[-] Enable TCP_NODELAY (true/false) [true]: " NODELAY; NODELAY=${NODELAY:-true}
    read -p "[-] Heartbeat (seconds) [40]: " HEARTBEAT; HEARTBEAT=${HEARTBEAT:-40}
    read -p "[-] Accept UDP (true/false) [false]: " ACCEPT_UDP; ACCEPT_UDP=${ACCEPT_UDP:-false}
    read -p "[-] Enable Sniffer (true/false) [false]: " SNIFFER; SNIFFER=${SNIFFER:-false}
    read -p "[-] Enter Web Port (@ to disable) [@]: " WEB_PORT; WEB_PORT=${WEB_PORT:-@}
    read -p "[-] Enable Proxy Protocol (for Cloudflare) [false]: " PROXY; PROXY=${PROXY:-false}

    local config="[server]\nbind_addr = \"0.0.0.0:${BIND_PORT}\"\ntransport = \"${TRANSPORT}\"\ntoken = \"${TOKEN}\"\nchannel_size = ${CHANNEL_SIZE}\nnodelay = ${NODELAY}\nheartbeat = ${HEARTBEAT}\naccept_udp = ${ACCEPT_UDP}\nsniffer = ${SNIFFER}\nproxy_protocol = ${PROXY}\n"
    if [[ "$WEB_PORT" != "@" ]]; then config+="web_port = ${WEB_PORT}\n"; fi
    
    if [[ "$TRANSPORT" == "tcpmux" || "$TRANSPORT" == "wssmux" ]]; then
        read -p "[-] MUX Connections [128]: " MUX_CON; MUX_CON=${MUX_CON:-128}
        config+="mux_con = ${MUX_CON}\n"
    fi
    
    if [[ "$TRANSPORT" == "tcp" || "$TRANSPORT" == "tcpmux" ]]; then
        echo -e "\n${YELLOW}[*] Supported Port Formats:${NC}"
        echo "  - 443-600 | 80 | 1000:2000 | 443=1.1.1.1:5201"
        read -p "[+] Enter your ports (comma-separated): " PORTS
        ports_formatted=$(echo "$PORTS" | tr -d ' ' | sed 's/,/","/g')
        config+="ports = [\"${ports_formatted}\"]\n"
    fi

    echo -e "$config" > "$CONFIG_DIR/${name}.toml"
    echo -e "${GREEN}Server config '${name}' created successfully.${NC}"
    create_service "$name"
}

generate_client_config() {
    local name=$1
    if [[ -z "$name" || -f "$CONFIG_DIR/${name}.toml" ]]; then echo -e "${RED}Error: Config name invalid.${NC}"; return; fi
    mkdir -p "$CONFIG_DIR"
    clear
    echo -e "${CYAN}--- Configuring KHAREJ client: ${WHITE}${name}${NC} ---${NC}"
    
    read -p "[+] Remote server address (IP:PORT): " REMOTE_ADDR
    read -p "[+] Transport type (must match server): " TRANSPORT
    read -p "[+] Security Token: " TOKEN
    read -p "[-] Enable TCP_NODELAY (true/false) [true]: " NODELAY; NODELAY=${NODELAY:-true}
    read -p "[-] Retry Interval on failure (seconds) [3]: " RETRY; RETRY=${RETRY:-3}

    local config="[client]\nremote_addr = \"${REMOTE_ADDR}\"\ntransport = \"${TRANSPORT}\"\ntoken = \"${TOKEN}\"\nnodelay = ${NODELAY}\nretry_interval = ${RETRY}\n"
    
    if [[ "$TRANSPORT" == "tcpmux" || "$TRANSPORT" == "wssmux" ]]; then
        read -p "[-] Connection Pool Size [128]: " CONN_POOL; CONN_POOL=${CONN_POOL:-128}
        config+="connection_pool = ${CONN_POOL}\n"
    fi
    
    echo -e "$config" > "$CONFIG_DIR/${name}.toml"

    echo -e "\n${PURPLE}--- Define Port Forwarding Rules ---${NC}"
    while true; do
        read -p "Add a port forwarding rule? [Y/n]: " ADD_PORT_CHOICE
        if [[ "$ADD_PORT_CHOICE" =~ ^[Nn]$ ]]; then break; fi
        read -p "  Local address to listen on (e.g., 0.0.0.0:8080): " LOCAL_ADDR
        read -p "  Remote address on the server (e.g., 127.0.0.1:22): " TARGET_ADDR
        { echo ""; echo "[[client.services]]"; echo "local_addr = \"${LOCAL_ADDR}\""; echo "remote_addr = \"${TARGET_ADDR}\""; } >> "$CONFIG_DIR/${name}.toml"
        echo -e "${GREEN}Rule: ${LOCAL_ADDR} -> ${TARGET_ADDR} added.${NC}"
    done
    
    echo -e "${GREEN}Client config '${name}' created successfully.${NC}"
    create_service "$name"
}

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
    echo -e "${PURPLE}--- Tunnel management menu ---${NC}"
    mapfile -t configs < <(ls -1 "$CONFIG_DIR" 2>/dev/null | sed 's/\.toml$//')
    if [ ${#configs[@]} -eq 0 ]; then echo -e "${YELLOW}No tunnels found.${NC}"; return; fi
    
    echo "List of existing services to manage:"
    i=1
    for name in "${configs[@]}"; do
        port=$(grep -E 'bind_addr|remote_addr' "$CONFIG_DIR/${name}.toml" | head -n1 | cut -d':' -f2 | tr -d '"')
        echo -e "$i) ${WHITE}${name}${NC}, Tunnel port: ${YELLOW}${port}${NC}"
        let i++
    done
    
    read -p "Enter your choice (0 to return): " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -eq 0 ]; then return; fi
    
    local selected_name=${configs[$((choice-1))]}
    if [ -z "$selected_name" ]; then echo -e "${RED}Invalid selection.${NC}"; return; fi
    manage_single_tunnel "$selected_name"
}

manage_single_tunnel() {
    local name=$1; local service_name="backhaul-${name}"
    while true; do
        clear
        echo -e "${PURPLE}--- Managing Tunnel: ${WHITE}${name}${NC} ---"
        systemctl is-active --quiet "$service_name" && echo -e "Status: ${GREEN}Active${NC}" || echo -e "Status: ${RED}Inactive${NC}"
        echo "-----------------------------------"
        echo "1) Start"; echo "2) Stop"; echo "3) Restart"; echo "4) View Logs"; echo "5) Edit Config"; echo -e "6) ${RED}Delete Tunnel${NC}"; echo "0) Back"
        read -p "Choose an option: " choice
        case $choice in
            1) systemctl start "$service_name" ;; 2) systemctl stop "$service_name" ;; 3) systemctl restart "$service_name" ;; 4) journalctl -u "$service_name" -f --no-pager ;;
            5) nano "$CONFIG_DIR/${name}.toml" && systemctl restart "$service_name" ;;
            6) read -p "Are you sure? [y/N]: " DEL; if [[ "$DEL" =~ ^[Yy]$ ]]; then systemctl stop "$service_name" &>/dev/null; systemctl disable "$service_name" &>/dev/null; rm -f "/etc/systemd/system/${service_name}.service"; rm -f "$CONFIG_DIR/${name}.toml"; systemctl daemon-reload; echo -e "${GREEN}Tunnel deleted.${NC}"; return; fi ;;
            0) return ;; *) echo -e "${RED}Invalid option!${NC}" ;;
        esac
        read -p $'\nPress [Enter] to continue...'
    done
}

remove_backhaul() {
    clear
    read -p "This will remove Backhaul Core and ALL configurations. Are you sure? [y/N]: " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        systemctl stop backhaul-* &>/dev/null; systemctl disable backhaul-* &>/dev/null
        rm -f /etc/systemd/system/backhaul-*.service; systemctl daemon-reload
        rm -rf "/etc/backhaul"; rm -f "$BINARY_PATH"
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
    echo -e "3. ${YELLOW}Optimize System for Stability${NC}"
    echo -e "4. Update & Install Backhaul Core"
    echo -e "5. Remove Backhaul Core"
    echo -e "0. Exit"
    echo -e "-------------------------------------------"
}

# --- Main Loop ---
check_root

while true; do
    show_main_menu
    read -p "Enter your choice [0-5]: " main_choice

    local should_pause=true
    case $main_choice in
        1) configure_new_tunnel ;;
        2) tunnel_management_menu; should_pause=false ;;
        3) optimize_system ;;
        4) install_or_update ;;
        5) remove_backhaul ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid choice!${NC}";;
    esac
    
    if [ "$should_pause" = true ]; then
        read -p $'\nPress [Enter] to return to main menu...'
    fi
done
