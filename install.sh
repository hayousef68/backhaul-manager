#!/bin/bash

# ====================================================================
#
#          🚀 Backhaul Manager v3.1 (Stable Menu) 🚀
#
#   This version implements a more robust menu loop to prevent
#   flickering and input issues on various terminal emulators.
#
# ====================================================================


# --- Sanity Checks ---
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root. Please use 'sudo'."
   sleep 1
   exit 1
fi


# --- Global Variables ---
BACKHAUL_DIR="/opt/backhaul"
CONFIG_DIR="/etc/backhaul"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log/backhaul"
BINARY_PATH="$BACKHAUL_DIR/backhaul"
TUNNELS_DIR="$CONFIG_DIR/tunnels"
SCRIPT_URL="https://raw.githubusercontent.com/hayousef68/backhaul-manager/main/install.sh"
SCRIPT_PATH="/usr/local/bin/backhaul-manager"


# --- UI & Helper Functions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

print_color() { printf "${1}${2}${NC}\n"; }
press_key() { read -p "Press Enter to continue..."; }


# --- Core Logic Functions ---

# Check for required commands
check_requirements() {
    # This function remains unchanged
    local missing_commands=()
    for cmd in curl tar systemctl openssl jq; do
        if ! command -v $cmd &> /dev/null; then
            missing_commands+=($cmd)
        fi
    done
    if [ ${#missing_commands[@]} -ne 0 ]; then
        print_color $RED "❌ Missing required commands: ${missing_commands[*]}"
        print_color $YELLOW "Attempting to install..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y curl tar systemd openssl jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y curl tar systemd openssl jq
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y curl tar systemd openssl jq
        else
            print_color $RED "❌ Unsupported package manager. Please install manually."
            exit 1
        fi
    fi
}

# Get server information
get_server_info() {
    # This function remains unchanged
    IP_INFO=$(curl -s 'http://ip-api.com/json/?fields=query,country,isp')
    SERVER_IP=$(echo "$IP_INFO" | jq -r '.query')
    SERVER_COUNTRY=$(echo "$IP_INFO" | jq -r '.country')
    SERVER_ISP=$(echo "$IP_INFO" | jq -r '.isp')
}

# Create necessary directories
create_directories() {
    # This function remains unchanged
    sudo mkdir -p "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TUNNELS_DIR" "$CONFIG_DIR/certs"
    sudo chmod -R 755 "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TUNNELS_DIR"
}

# Check if a port is in use
is_port_in_use() {
    # This function remains unchanged
    local port=$1
    if sudo ss -tln | grep -q ":$port\s"; then
        return 0 # In use
    else
        return 1 # Not in use
    fi
}

# Generate configuration file (Advanced)
generate_config_advanced() {
    # This function remains unchanged
    local params=$1
    local tunnel_name=$(echo "$params" | jq -r '.tunnel_name')
    local config_file="$TUNNELS_DIR/${tunnel_name}.toml"

    if [ "$(echo "$params" | jq -r '.mode')" == "server" ]; then
        cat > "$config_file" << EOF
# Server Config for Tunnel: ${tunnel_name}
[server]
bind_addr = "$(echo "$params" | jq -r '.bind_addr')"
transport = "$(echo "$params" | jq -r '.transport')"
token = "$(echo "$params" | jq -r '.token')"
heartbeat = $(echo "$params" | jq -r '.heartbeat')
nodelay = $(echo "$params" | jq -r '.nodelay')
channel_size = $(echo "$params" | jq -r '.channel_size')
accept_udp = $(echo "$params" | jq -r '.accept_udp')
sniffer = $(echo "$params" | jq -r '.sniffer')
proxy_protocol = $(echo "$params" | jq -r '.proxy_protocol')
web_port = $(echo "$params" | jq -r '.web_port')
log_level = "info"
EOF
        if [[ "$(echo "$params" | jq -r '.transport')" == "wss" || "$(echo "$params" | jq -r '.transport')" == "wssmux" ]]; then
            cat >> "$config_file" << EOF
tls_cert = "$CONFIG_DIR/certs/server.crt"
tls_key = "$CONFIG_DIR/certs/server.key"
EOF
        fi
        if echo "$(echo "$params" | jq -r '.transport')" | grep -q "mux"; then
            cat >> "$config_file" << EOF
[server.mux]
con = 8
version = 1
framesize = 32768
EOF
        fi
        ports_json=$(echo "$params" | jq -r '.ports')
        if [ ! -z "$ports_json" ] && [ "$ports_json" != "[]" ]; then
            echo "ports = $(echo "$params" | jq -c '.ports')" >> "$config_file"
        else
            echo "ports = []" >> "$config_file"
        fi
    else # Client mode
        cat > "$config_file" << EOF
# Client Config for Tunnel: ${tunnel_name}
[client]
remote_addr = "$(echo "$params" | jq -r '.remote_addr')"
transport = "$(echo "$params" | jq -r '.transport')"
token = "$(echo "$params" | jq -r '.token')"
connection_pool = 8
dial_timeout = 10
retry_interval = 3
nodelay = true
log_level = "info"
EOF
        if echo "$(echo "$params" | jq -r '.transport')" | grep -q "mux"; then
            cat >> "$config_file" << EOF
[client.mux]
version = 1
framesize = 32768
EOF
        fi
    fi
}

# Create systemd service
create_service() {
    # This function remains unchanged
    local tunnel_name=$1
    local service_file="$SERVICE_DIR/backhaul-${tunnel_name}.service"
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Backhaul Tunnel Service - $tunnel_name
After=network.target
StartLimitIntervalSec=0
[Service]
Type=simple
ExecStart=$BINARY_PATH -c $TUNNELS_DIR/${tunnel_name}.toml
Restart=always
RestartSec=3
User=root
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "backhaul-${tunnel_name}.service"
}


# --- Feature Functions ---

# 1. Configure a new tunnel
configure_new_tunnel() {
    clear
    print_color $CYAN "--- Configure a New Tunnel ---"
    echo "1) Configure IRAN server (Server)"
    echo "2) Configure KHAREJ server (Client)"
    read -p "Enter your choice: " configure_choice
    case "$configure_choice" in
        1) configure_iran_server ;;
        2) configure_kharej_server ;;
        *) print_color $RED "Invalid option!"; sleep 1 ;;
    esac
}

configure_iran_server() {
    clear
    print_color $CYAN "--- Configuring IRAN Server ---"
    
    local params='{"mode":"server"}'
    
    read -p "[*] Tunnel name: " tunnel_name
    params=$(echo "$params" | jq --arg tn "$tunnel_name" '. + {tunnel_name: $tn}')

    read -p "[*] Tunnel port (e.g., 3090): " tunnel_port
    params=$(echo "$params" | jq --arg tp "$tunnel_port" '. + {bind_addr: ("0.0.0.0:" + $tp)}')

    read -p "[*] Transport type (tcp/tcpmux/udp/ws/wss/wsmux/wssmux): " transport
    params=$(echo "$params" | jq --arg t "$transport" '. + {transport: $t}')

    read -p "[-] Accept UDP connections over TCP transport (true/false) [default: false]: " accept_udp
    params=$(echo "$params" | jq --arg au "${accept_udp:-false}" '. + {accept_udp: $au}')

    read -p "[-] Channel Size [default: 2048]: " channel_size
    params=$(echo "$params" | jq --arg cs "${channel_size:-2048}" '. + {channel_size: $cs}')

    read -p "[-] Enable TCP_NODELAY (true/false) [default: true]: " nodelay
    params=$(echo "$params" | jq --arg n "${nodelay:-true}" '. + {nodelay: $n}')

    read -p "[-] Heartbeat (in seconds) [default: 40]: " heartbeat
    params=$(echo "$params" | jq --arg h "${heartbeat:-40}" '. + {heartbeat: $h}')

    read -p "[-] Security Token [press enter to generate]: " token
    [ -z "$token" ] && token=$(openssl rand -hex 16)
    params=$(echo "$params" | jq --arg tkn "$token" '. + {token: $tkn}')
    print_color $YELLOW "Token: $token"

    read -p "[-] Enable Sniffer (true/false) [default: false]: " sniffer
    params=$(echo "$params" | jq --arg s "${sniffer:-false}" '. + {sniffer: $s}')

    while true; do
        read -p "[-] Enter Web Port (default 0 to disable): " web_port
        web_port=${web_port:-0}
        if [[ "$web_port" -eq 0 ]] || ! is_port_in_use "$web_port"; then
            params=$(echo "$params" | jq --arg wp "$web_port" '. + {web_port: $wp}')
            break
        else
            print_color $RED "Port $web_port is already in use. Please choose a different port."
        fi
    done

    read -p "[-] Enable Proxy Protocol (true/false) [default: false]: " proxy_protocol
    params=$(echo "$params" | jq --arg pp "${proxy_protocol:-false}" '. + {proxy_protocol: $pp}')
    
    print_color $CYAN "[*] Supported Port Formats:"
    echo "1. 443-600              - Listen on all ports in the range 443 to 600"
    echo "2. 443-600:5201          - Listen on all ports in the range 443 to 600 and forward traffic to 5201"
    echo "3. 443=600=1.1.1.1:5201 - Listen on local port 443 and forward to a specific remote IP"
    
    read -p "[*] Enter your ports in the specified formats (separated by commas): " ports_raw
    ports_array_raw="["$(echo "$ports_raw" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')"]"
    ports_array=$(echo "$ports_array_raw" | jq -c '.')
    params=$(echo "$params" | jq --argjson p "$ports_array" '. + {ports: $p}')

    generate_config_advanced "$params"
    create_service "$tunnel_name"
    sudo systemctl start "backhaul-${tunnel_name}.service"

    print_color $GREEN "✅ Server tunnel '$tunnel_name' created successfully!"
    press_key
}

configure_kharej_server() {
    clear
    print_color $CYAN "--- Configuring KHAREJ Server ---"
    
    local params='{"mode":"client"}'

    read -p "[*] Tunnel name: " tunnel_name
    params=$(echo "$params" | jq --arg tn "$tunnel_name" '. + {tunnel_name: $tn}')

    read -p "[*] Iran Server Address (IP:PORT): " remote_addr
    params=$(echo "$params" | jq --arg ra "$remote_addr" '. + {remote_addr: $ra}')

    read -p "[*] Transport type (tcp/tcpmux/udp/ws/wss/wsmux/wssmux): " transport
    params=$(echo "$params" | jq --arg t "$transport" '. + {transport: $t}')

    read -p "[*] Security Token: " token
    params=$(echo "$params" | jq --arg tkn "$token" '. + {token: $tkn}')

    generate_config_advanced "$params"
    create_service "$tunnel_name"
    sudo systemctl start "backhaul-${tunnel_name}.service"

    print_color $GREEN "✅ Client tunnel '$tunnel_name' created successfully!"
    press_key
}

# 2. Tunnel management menu
manage_tunnel() {
    # This function remains unchanged
    clear
    print_color $CYAN "--- Tunnel Management ---"
    if [ -z "$(ls -A $TUNNELS_DIR/*.toml 2>/dev/null)" ]; then
        print_color $YELLOW "⚠️ No tunnels found."; press_key; return
    fi
    
    i=1; declare -a tunnels
    for f in "$TUNNELS_DIR"/*.toml; do
        t_name=$(basename "$f" .toml)
        tunnels[$i]=$t_name
        echo "$i) $t_name"
        ((i++))
    done
    read -p "Select tunnel to manage: " choice
    selected_tunnel=${tunnels[$choice]}

    if [ -z "$selected_tunnel" ]; then
        print_color $RED "Invalid selection"; sleep 1; return
    fi
    
    clear
    print_color $CYAN "Managing: $selected_tunnel"
    echo "1) Start"; echo "2) Stop"; echo "3) Restart"; echo "4) Status"; echo "5) Logs"; print_color $RED "6) Delete";
    read -p "Action: " action
    case $action in
        1) sudo systemctl start "backhaul-$selected_tunnel" && print_color $GREEN "Started.";;
        2) sudo systemctl stop "backhaul-$selected_tunnel" && print_color $YELLOW "Stopped.";;
        3) sudo systemctl restart "backhaul-$selected_tunnel" && print_color $GREEN "Restarted.";;
        4) sudo systemctl status "backhaul-$selected_tunnel";;
        5) sudo journalctl -u "backhaul-$selected_tunnel" -f;;
        6) 
            read -p "Are you sure you want to DELETE $selected_tunnel? (y/n): " confirm
            if [[ "$confirm" == "y" ]]; then
                sudo systemctl disable --now "backhaul-$selected_tunnel"
                sudo rm -f "$SERVICE_DIR/backhaul-$selected_tunnel.service"
                sudo rm -f "$TUNNELS_DIR/$selected_tunnel.toml"
                sudo systemctl daemon-reload
                print_color $GREEN "Deleted."
            fi
            ;;
        *) print_color $RED "Invalid action.";;
    esac
    if [[ ! "$action" =~ ^[45]$ ]]; then press_key; fi
}

# 3. Check tunnels status
check_tunnels_status() {
    # This function remains unchanged
    clear
    print_color $CYAN "--- Tunnels Status ---"
    if [ -z "$(ls -A $TUNNELS_DIR/*.toml 2>/dev/null)" ]; then
        print_color $YELLOW "⚠️ No tunnels found."; press_key; return
    fi

    printf "%-20s %-15s %-22s\n" "NAME" "TYPE" "STATUS"
    printf "%-20s %-15s %-22s\n" "----" "----" "------"
    
    for f in "$TUNNELS_DIR"/*.toml; do
        tunnel_name=$(basename "$f" .toml)
        type="Client" && grep -q "\[server\]" "$f" && type="Server"
        if systemctl is-active --quiet "backhaul-$tunnel_name"; then
            status="${GREEN}● Active${NC}"
        else
            status="${RED}● Inactive${NC}"
        fi
        printf "%-20s %-15s %-22s\n" "$tunnel_name" "$type" "$status"
    done
    press_key
}

# 4. Optimize network & system limits
optimize_server() {
    # This function remains unchanged
    clear
    print_color $CYAN "--- Optimizing System ---"
    print_color $YELLOW "This will apply common system optimizations for better network performance."
    read -p "This is an experimental feature. Continue? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi

    cat > /etc/sysctl.d/99-backhaul-optimizations.conf << EOF
fs.file-max = 67108864
net.core.default_qdisc = fq_codel
net.core.netdev_max_backlog = 32768
net.core.somaxconn = 65536
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_max_syn_backlog = 20480
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_mtu_probing = 1
vm.swappiness = 10
EOF
    sudo sysctl -p /etc/sysctl.d/99-backhaul-optimizations.conf
    
    cat > /etc/security/limits.d/99-backhaul-optimizations.conf << EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65536
* hard nproc 65536
EOF

    print_color $GREEN "✅ System optimizations applied."
    print_color $YELLOW "A reboot is recommended to apply all changes."
    press_key
}

# 5. Update & Install Backhaul Core
install_backhaul_core() {
    clear
    print_color $YELLOW "--- Installing/Updating Backhaul Core ---"
    
    print_color $YELLOW "Detecting system..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; *)
            print_color $RED "❌ Unsupported architecture: $ARCH"; press_key; return ;;
    esac
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    print_color $YELLOW "Fetching latest version from GitHub..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_VERSION" ]; then
        print_color $RED "❌ Failed to get latest version."; press_key; return
    fi
    print_color $GREEN "Latest version: $LATEST_VERSION"

    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${OS}_${ARCH}.tar.gz"
    
    print_color $YELLOW "Downloading from: $DOWNLOAD_URL"
    cd /tmp
    curl -L -o "backhaul.tar.gz" "$DOWNLOAD_URL"
    tar -xzf backhaul.tar.gz
    sudo mv backhaul "$BINARY_PATH"
    sudo chmod +x "$BINARY_PATH"
    
    print_color $GREEN "✅ Backhaul Core installed successfully!"
    press_key
}

# 6. Update & install script
update_script() {
    print_color $YELLOW "--- Updating Manager Script ---"
    if curl -sSL "$SCRIPT_URL" -o "$SCRIPT_PATH.tmp"; then
        # The move might fail if the script is currently running from SCRIPT_PATH
        # So we copy, make executable, and then ask the user to re-run
        sudo cp "$SCRIPT_PATH.tmp" "$SCRIPT_PATH"
        sudo chmod +x "$SCRIPT_PATH"
        rm "$SCRIPT_PATH.tmp"
        print_color $GREEN "✅ Script updated successfully."
        print_color $YELLOW "Please exit and run 'sudo backhaul-manager' again."
    else
        print_color $RED "❌ Failed to download update."
    fi
    press_key
}

# 7. Remove Backhaul Core
uninstall_backhaul() {
    # This function remains unchanged
    clear
    print_color $RED "--- Uninstall Backhaul ---"
    print_color $YELLOW "This will stop all tunnels and remove all configs and binaries."
    read -p "Are you sure? Type 'YES' to confirm: " confirm
    if [[ "$confirm" != "YES" ]]; then
        print_color $GREEN "Uninstall cancelled."; press_key; return
    fi

    for f in "$TUNNELS_DIR"/*.toml; do
        t_name=$(basename "$f" .toml)
        sudo systemctl disable --now "backhaul-$t_name" 2>/dev/null
    done
    sudo rm -rf "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR"
    sudo rm -f $SERVICE_DIR/backhaul-*.service
    sudo rm -f "$SCRIPT_PATH"
    sudo systemctl daemon-reload
    print_color $GREEN "✅ Backhaul uninstalled completely."
    exit 0
}


# --- Menu Display and Input Handling (New Stable Structure) ---

# This function ONLY displays the menu
display_menu() {
    clear
    get_server_info
    
    print_color $CYAN "Script Version: v3.1 (Stable Menu)"
    if [ -f "$BINARY_PATH" ]; then
        CORE_VERSION=$($BINARY_PATH --version | head -n 1)
        print_color $CYAN "Core Version: $CORE_VERSION"
        CORE_STATUS="${GREEN}Installed${NC}"
    else
        print_color $CYAN "Core Version: N/A"
        CORE_STATUS="${RED}Not Installed${NC}"
    fi
    print_color $CYAN "Telegram Channel: @Gozar_Xray"
    echo "-------------------------------------"
    print_color $WHITE "IP Address: $SERVER_IP"
    print_color $WHITE "Location: $SERVER_COUNTRY"
    print_color $WHITE "Datacenter: $SERVER_ISP"
    print_color $WHITE "Backhaul Core: $CORE_STATUS"
    echo "-------------------------------------"

    print_color $WHITE "1. Configure a new tunnel [IPv4/IPv6]"
    print_color $WHITE "2. Tunnel management menu"
    print_color $WHITE "3. Check tunnels status"
    print_color $WHITE "4. Optimize network & system limits"
    print_color $WHITE "5. Update & Install Backhaul Core"
    print_color $WHITE "6. Update & install script"
    print_color $RED   "7. Remove Backhaul Core"
    print_color $YELLOW "0. Exit"
    echo "-------------------------------------"
}

# This function ONLY reads the user's choice and calls other functions
read_option() {
    read -p "Enter your choice [0-7]: " choice
    case $choice in
        1) configure_new_tunnel ;;
        2) manage_tunnel ;;
        3) check_tunnels_status ;;
        4) optimize_server ;;
        5) install_backhaul_core ;;
        6) update_script ;;
        7) uninstall_backhaul ;;
        0) exit 0 ;;
        *) print_color $RED "Invalid option. Please try again."; sleep 1 ;;
    esac
}


# --- Main Execution ---
check_requirements
create_directories
# Install self to /usr/local/bin for easy access on first run
if [ ! -f "$SCRIPT_PATH" ]; then
    sudo cp "$0" "$SCRIPT_PATH"
    sudo chmod +x "$SCRIPT_PATH"
fi

# The new, stable main loop
while true; do
    display_menu
    read_option
done
