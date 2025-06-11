#!/bin/bash

# ====================================================================
#
#          🚀 Backhaul Manager v4.0 (Stable Template) 🚀
#
#   This version is a complete rebuild using the user-provided
#   'rathole_v2.sh' script as a stable template. All internal logic
#   has been replaced to manage Backhaul tunnels. This should
#   definitively resolve any menu stability or input issues.
#
# ====================================================================


# --- Script Initialization and Prereqs ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   sleep 1
   exit 1
fi

# Define a function to colorize text (from rathole_v2.sh)
colorize() {
    local color="$1"
    local text="$2"
    local style="${3:-normal}"
    local red="\033[31m"; local green="\033[32m"; local yellow="\033[33m"; local cyan="\033[36m"; local white="\033[37m"; local reset="\033[0m";
    local normal="\033[0m"; local bold="\033[1m";
    local color_code;
    case $color in
        red) color_code=$red ;; green) color_code=$green ;; yellow) color_code=$yellow ;;
        cyan) color_code=$cyan ;; white) color_code=$white ;; *) color_code=$reset ;;
    esac
    local style_code;
    case $style in
        bold) style_code=$bold ;; *) style_code=$normal ;;
    esac
    echo -e "${style_code}${color_code}${text}${reset}"
}

# Function to check for required commands
check_requirements() {
    for cmd in curl tar systemctl openssl jq; do
        if ! command -v $cmd &> /dev/null; then
            if command -v apt-get &> /dev/null; then
                colorize red "$cmd is not installed. Installing..."
                sudo apt-get update > /dev/null 2>&1 && sudo apt-get install -y $cmd > /dev/null 2>&1
            else
                colorize red "Error: Please install '$cmd' manually." "bold"
                exit 1
            fi
        fi
    done
}
# Run the check
check_requirements


# --- Global Variables for Backhaul ---
BACKHAUL_DIR="/opt/backhaul"
CONFIG_DIR="/etc/backhaul"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log/backhaul"
BINARY_PATH="$BACKHAUL_DIR/backhaul"
TUNNELS_DIR="$CONFIG_DIR/tunnels"
SCRIPT_URL="https://raw.githubusercontent.com/hayousef68/backhaul-manager/main/install.sh"
SCRIPT_PATH="/usr/local/bin/backhaul-manager"
NC='\033[0m'


# --- Helper Functions ---
press_key(){
 read -p "Press any key to continue..."
}

get_server_info() {
    IP_INFO=$(curl -s 'http://ip-api.com/json/?fields=query,country,isp')
    SERVER_IP=$(echo "$IP_INFO" | jq -r '.query')
    SERVER_COUNTRY=$(echo "$IP_INFO" | jq -r '.country')
    SERVER_ISP=$(echo "$IP_INFO" | jq -r '.isp')
}

is_port_in_use() {
    if sudo ss -tln | grep -q ":$1\s"; then return 0; else return 1; fi
}

# --- Core Feature Functions (Backhaul Logic) ---

# This function is now the main entry point for configuration
configure_tunnel() {
    clear
    colorize green "--- Configure a New Backhaul Tunnel ---" "bold"
    echo
    colorize green "1) Configure for IRAN server (Server Role)" "bold"
    colorize cyan "2) Configure for KHAREJ server (Client Role)" "bold"
    echo
    read -p "Enter your choice: " configure_choice
    case "$configure_choice" in
        1) iran_server_configuration ;;
        2) kharej_server_configuration ;;
        *) colorize red "Invalid option!" && sleep 1 ;;
    esac
}

iran_server_configuration() {
    clear; colorize cyan "--- Configuring IRAN Server (Backhaul) ---" "bold";
    local params='{"mode":"server"}';
    read -p "[*] Tunnel name: " tunnel_name;
    params=$(echo "$params" | jq --arg tn "$tunnel_name" '. + {tunnel_name: $tn}');
    read -p "[*] Tunnel port (e.g., 3090): " tunnel_port;
    params=$(echo "$params" | jq --arg tp "$tunnel_port" '. + {bind_addr: ("0.0.0.0:" + $tp)}');
    read -p "[*] Transport type (tcp/tcpmux/udp/ws/wss/wsmux/wssmux): " transport;
    params=$(echo "$params" | jq --arg t "$transport" '. + {transport: $t}');
    read -p "[-] Heartbeat (seconds) [default: 40]: " heartbeat;
    params=$(echo "$params" | jq --arg h "${heartbeat:-40}" '. + {heartbeat: $h}');
    read -p "[-] Security Token [press enter to generate]: " token;
    [ -z "$token" ] && token=$(openssl rand -hex 16);
    params=$(echo "$params" | jq --arg tkn "$token" '. + {token: $tkn}');
    colorize yellow "Token: $token";
    while true; do
        read -p "[-] Enter Web Port for stats (default 0 to disable): " web_port; web_port=${web_port:-0};
        if [[ "$web_port" -eq 0 ]] || ! is_port_in_use "$web_port"; then
            params=$(echo "$params" | jq --arg wp "$web_port" '. + {web_port: $wp}'); break;
        else
            colorize red "Port $web_port is already in use.";
        fi
    done
    colorize cyan "[*] Supported Port Formats: (e.g., 443, 8080=80, 500-600)";
    read -p "[*] Enter your ports (separated by commas): " ports_raw;
    ports_array_raw="["$(echo "$ports_raw" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')"]";
    ports_array=$(echo "$ports_array_raw" | jq -c '.');
    params=$(echo "$params" | jq --argjson p "$ports_array" '. + {ports: $p}');
    
    # --- Generate TOML config for Backhaul ---
    config_file="$TUNNELS_DIR/${tunnel_name}.toml"
    cat > "$config_file" << EOF
[server]
bind_addr = "$(echo "$params" | jq -r '.bind_addr')"
transport = "$(echo "$params" | jq -r '.transport')"
token = "$(echo "$params" | jq -r '.token')"
heartbeat = $(echo "$params" | jq -r '.heartbeat')
web_port = $(echo "$params" | jq -r '.web_port')
log_level = "info"
ports = $(echo "$params" | jq -c '.ports')
EOF
    # --- End of TOML generation ---
    
    create_service "$tunnel_name";
    sudo systemctl start "backhaul-${tunnel_name}.service";
    colorize green "✅ Server tunnel '$tunnel_name' created successfully!"; press_key;
}

kharej_server_configuration() {
    clear; colorize cyan "--- Configuring KHAREJ Server (Backhaul) ---" "bold";
    local params='{"mode":"client"}';
    read -p "[*] Tunnel name: " tunnel_name;
    params=$(echo "$params" | jq --arg tn "$tunnel_name" '. + {tunnel_name: $tn}');
    read -p "[*] Iran Server Address (IP:PORT): " remote_addr;
    params=$(echo "$params" | jq --arg ra "$remote_addr" '. + {remote_addr: $ra}');
    read -p "[*] Transport type (tcp/tcpmux/udp/ws/wss/wsmux/wssmux): " transport;
    params=$(echo "$params" | jq --arg t "$transport" '. + {transport: $t}');
    read -p "[*] Security Token: " token;
    params=$(echo "$params" | jq --arg tkn "$token" '. + {token: $tkn}');

    # --- Generate TOML config for Backhaul ---
    config_file="$TUNNELS_DIR/${tunnel_name}.toml"
    cat > "$config_file" << EOF
[client]
remote_addr = "$(echo "$params" | jq -r '.remote_addr')"
transport = "$(echo "$params" | jq -r '.transport')"
token = "$(echo "$params" | jq -r '.token')"
log_level = "info"
EOF
    # --- End of TOML generation ---

    create_service "$tunnel_name";
    sudo systemctl start "backhaul-${tunnel_name}.service";
    colorize green "✅ Client tunnel '$tunnel_name' created successfully!"; press_key;
}

tunnel_management() {
    clear; colorize cyan "--- Backhaul Tunnel Management ---" "bold";
    if [ -z "$(ls -A $TUNNELS_DIR/*.toml 2>/dev/null)" ]; then
        colorize yellow "⚠️ No tunnels found."; press_key; return;
    fi
    i=1; declare -a tunnels;
    for f in "$TUNNELS_DIR"/*.toml; do
        t_name=$(basename "$f" .toml); tunnels[$i]=$t_name; echo "$i) $t_name"; ((i++));
    done
    read -p "Select tunnel to manage (0 to return): " choice;
    if [[ "$choice" -eq 0 ]]; then return; fi
    selected_tunnel=${tunnels[$choice]};
    if [ -z "$selected_tunnel" ]; then colorize red "Invalid selection"; sleep 1; return; fi
    
    clear; colorize cyan "Managing: $selected_tunnel" "bold";
    echo "1) Start"; echo "2) Stop"; echo "3) Restart"; echo "4) Status"; echo "5) Logs"; colorize red "6) Delete";
    read -p "Action: " action;
    case $action in
        1) sudo systemctl start "backhaul-$selected_tunnel" && colorize green "Started.";;
        2) sudo systemctl stop "backhaul-$selected_tunnel" && colorize yellow "Stopped.";;
        3) sudo systemctl restart "backhaul-$selected_tunnel" && colorize green "Restarted.";;
        4) sudo systemctl status "backhaul-$selected_tunnel";;
        5) sudo journalctl -u "backhaul-$selected_tunnel" -f;;
        6) read -p "Are you sure you want to DELETE $selected_tunnel? (y/n): " confirm;
            if [[ "$confirm" == "y" ]]; then
                sudo systemctl disable --now "backhaul-$selected_tunnel" >/dev/null 2>&1
                sudo rm -f "$SERVICE_DIR/backhaul-$selected_tunnel.service" "$TUNNELS_DIR/$selected_tunnel.toml"
                sudo systemctl daemon-reload; colorize green "Deleted.";
            fi;;
        *) colorize red "Invalid action.";;
    esac
    if [[ ! "$action" =~ ^[45]$ ]]; then press_key; fi
}

check_tunnel_status() {
    clear; colorize cyan "--- Backhaul Tunnels Status ---" "bold";
    if [ -z "$(ls -A $TUNNELS_DIR/*.toml 2>/dev/null)" ]; then
        colorize yellow "⚠️ No tunnels found."; press_key; return
    fi
    printf "%-20s %-15s %-22s\n" "NAME" "TYPE" "STATUS";
    printf "%-20s %-15s %-22s\n" "----" "----" "------";
    for f in "$TUNNELS_DIR"/*.toml; do
        tunnel_name=$(basename "$f" .toml);
        type="Client" && grep -q "\[server\]" "$f" && type="Server";
        if systemctl is-active --quiet "backhaul-$tunnel_name"; then
            status="$(colorize green "● Active")";
        else
            status="$(colorize red "● Inactive")";
        fi
        printf "%-20s %-15s %-22s\n" "$tunnel_name" "$type" "$status";
    done
    press_key
}

hawshemi_script() {
    clear; colorize cyan "--- Optimizing System ---" "bold";
    colorize yellow "This will apply common system optimizations for better network performance.";
    read -p "Continue? (y/n): " confirm;
    if [[ "$confirm" != "y" ]]; then return; fi
    # Optimization logic (from rathole_v2.sh)
    sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak;
    sudo tee /etc/sysctl.d/99-backhaul-optimizations.conf > /dev/null << EOF
fs.file-max=1048576
net.core.default_qdisc=fq
net.core.netdev_max_backlog=100000
net.core.somaxconn=100000
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_max_syn_backlog=100000
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_mtu_probing=1
EOF
    sudo sysctl -p /etc/sysctl.d/99-backhaul-optimizations.conf;
    colorize green "✅ System optimizations applied.";
    colorize yellow "A reboot is recommended to apply all changes.";
    press_key;
}

download_and_install_core() {
    clear; colorize yellow "--- Installing/Updating Backhaul Core ---" "bold";
    colorize yellow "Detecting system...";
    ARCH=$(uname -m);
    case $ARCH in
        x86_64|amd64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; *)
            colorize red "❌ Unsupported architecture: $ARCH"; press_key; return ;;
    esac
    OS=$(uname -s | tr '[:upper:]' '[:lower:]');
    colorize yellow "Fetching latest version from GitHub...";
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/');
    if [ -z "$LATEST_VERSION" ]; then colorize red "❌ Failed to get latest version."; press_key; return; fi
    colorize green "Latest version: $LATEST_VERSION";
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${OS}_${ARCH}.tar.gz";
    colorize yellow "Downloading from: $DOWNLOAD_URL";
    cd /tmp;
    if ! curl -L -o "backhaul.tar.gz" "$DOWNLOAD_URL"; then
        colorize red "Download failed!"; press_key; return;
    fi
    tar -xzf "backhaul.tar.gz";
    sudo mv backhaul "$BINARY_PATH";
    sudo chmod +x "$BINARY_PATH";
    colorize green "✅ Backhaul Core installed successfully!";
    press_key;
}

update_script(){
    colorize yellow "--- Updating Manager Script ---" "bold";
    if curl -sSL "$SCRIPT_URL" -o "$SCRIPT_PATH.tmp"; then
        sudo cp "$SCRIPT_PATH.tmp" "$SCRIPT_PATH";
        sudo chmod +x "$SCRIPT_PATH";
        rm "$SCRIPT_PATH.tmp";
        colorize green "✅ Script updated successfully.";
        colorize yellow "Please exit and run 'sudo backhaul-manager' again.";
    else
        colorize red "❌ Failed to download update.";
    fi
    press_key;
}

remove_backhaul(){
    clear; colorize red "--- Uninstall Backhaul ---" "bold";
    colorize yellow "This will stop all tunnels and remove all configs and binaries.";
    read -p "Are you sure? Type 'YES' to confirm: " confirm;
    if [[ "$confirm" != "YES" ]]; then colorize green "Uninstall cancelled."; press_key; return; fi
    for f in "$TUNNELS_DIR"/*.toml; do
        t_name=$(basename "$f" .toml);
        sudo systemctl disable --now "backhaul-$t_name" 2>/dev/null;
    done
    sudo rm -rf "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR";
    sudo rm -f $SERVICE_DIR/backhaul-*.service "$SCRIPT_PATH";
    sudo systemctl daemon-reload;
    colorize green "✅ Backhaul uninstalled completely.";
    exit 0;
}


# --- Menu Display and Loop (from rathole_v2.sh) ---

display_logo() {
    colorize cyan "
               __               __  __          __
   ____  ____ _/ /_  ____ ______/ / / /_  ____  / /_
  / __ \/ __ \`/ __ \/ __ \`/ ___/ / / / / / __ \/ __/
 / /_/ / /_/ / / / / /_/ / /__/ /_/ / /_/ / / / /_
/ .___/\__,_/_/ /_/\__,_/\___/\____/ .___/_/ /_/\__/
/_/                               /_/
"
    colorize green "Version: 4.0 (Stable Template)"
    colorize green "Github: github.com/hayousef68/backhaul-manager"
    colorize green "Telegram Channel: @Gozar_Xray"
}

display_server_info() {
    echo -e "\e[93m═════════════════════════════════════════════\e[0m"
    colorize cyan "Location: $SERVER_COUNTRY "
    colorize cyan "Datacenter: $SERVER_ISP"
}

display_core_status() {
    if [[ -f "$BINARY_PATH" ]]; then
        colorize cyan "Backhaul Core: $(colorize green Installed)"
    else
        colorize cyan "Backhaul Core: $(colorize red "Not installed")"
    fi
    echo -e "\e[93m═════════════════════════════════════════════\e[0m"  
}

display_menu() {
    clear
    display_logo
    display_server_info
    display_core_status
    echo
    colorize white " 1. Configure a new tunnel"
    colorize white " 2. Tunnel management menu"
    colorize white " 3. Check tunnels status"
 	colorize white " 4. Optimize network & system limits"
 	colorize white " 5. Install/Update Backhaul Core"
 	colorize white " 6. Update this script"
 	colorize red " 7. Uninstall Backhaul"
    colorize yellow " 0. Exit"
    echo
    echo "-------------------------------"
}

read_option() {
    read -p "Enter your choice [0-7]: " choice
    case $choice in
        1) configure_tunnel ;;
        2) tunnel_management ;;
        3) check_tunnel_status ;;
        4) hawshemi_script ;;
        5) download_and_install_core ;;
        6) update_script ;;
        7) remove_backhaul ;;
        0) exit 0 ;;
        *) colorize red "Invalid option!" && sleep 1 ;;
    esac
}

# --- Main Execution ---
create_directories
get_server_info
# Install self to /usr/local/bin for easy access
if [[ "$0" != "$SCRIPT_PATH" ]]; then
    sudo cp "$0" "$SCRIPT_PATH"
    sudo chmod +x "$SCRIPT_PATH"
fi

while true; do
    display_menu
    read_option
done
