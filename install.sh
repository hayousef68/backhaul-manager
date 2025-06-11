#!/bin/bash

# ====================================================================
#
#          🚀 Backhaul Manager v2.1 🚀
#
#   A complete management script for the Backhaul reverse tunnel.
#   Features a stable, flicker-free, and colorized English menu.
#   Inspired by rathole_v2.sh, powered by Backhaul core logic.
#
# ====================================================================

# --- Sanity Checks ---

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root. Please use 'sudo'."
   sleep 1
   exit 1
fi

# --- Global Variables and Configuration ---

# Directories and Files
BACKHAUL_DIR="/opt/backhaul"
CONFIG_DIR="/etc/backhaul"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log/backhaul"
BINARY_PATH="$BACKHAUL_DIR/backhaul"
TUNNELS_DIR="$CONFIG_DIR/tunnels"

# --- UI Helper Functions ---

# Define colors 
RED='\033[0;31m' 
GREEN='\033[0;32m' 
YELLOW='\033[1;33m' 
BLUE='\033[0;34m' 
PURPLE='\033[0;35m' 
CYAN='\033[0;36m' 
WHITE='\033[1;37m' 
NC='\033[0m' 

# Print colored output 
print_color() {
    printf "${1}${2}${NC}\n" 
}

# Wait for user to press Enter
press_key(){
    read -p "Press Enter to continue..." 
}

# Display header and logo
print_header() {
    clear 
    print_color $CYAN "======================================================================" 
    cat << "EOF"
               __               __  __          __
   ____  ____ _/ /_  ____ ______/ / / /_  ____  / /_
  / __ \/ __ `/ __ \/ __ `/ ___/ / / / / / __ \/ __/
 / /_/ / /_/ / / / / /_/ / /__/ /_/ / /_/ / / / /_
/ .___/\__,_/_/ /_/\__,_/\___/\____/ .___/_/ /_/\__/
/_/                               /_/
EOF
    print_color $CYAN "======================================================================" 
    print_color $WHITE "           🚀 Backhaul Manager v2.1 - Tunnel Management Solution 🚀" 
    echo 
}

# --- Core Logic Functions (Installation, Configuration, etc.) ---

# Create necessary directories
create_directories() {
    sudo mkdir -p "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TUNNELS_DIR" 
    sudo chmod -R 755 "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TUNNELS_DIR" 
}

# Detect system architecture and OS
detect_system() {
    ARCH=$(uname -m) 
    case $ARCH in 
        x86_64|amd64) ARCH="amd64" ;; 
        i386|i686) ARCH="386" ;; 
        aarch64|arm64) ARCH="arm64" ;; 
        armv7l) ARCH="arm" ;; 
        *)
            print_color $RED "❌ Unsupported architecture: $ARCH" 
            exit 1 
            ;; 
    esac 

    OS=$(uname -s | tr '[:upper:]' '[:lower:]') 
    case $OS in 
        linux) OS="linux" ;; 
        darwin) OS="darwin" ;; 
        *)
            print_color $RED "❌ Unsupported OS: $OS" 
            exit 1 
            ;; 
    esac 
}

# Get the latest version from GitHub
get_latest_version() {
    print_color $YELLOW "🔄 Checking for the latest Backhaul version..." 
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') 
    if [ -z "$LATEST_VERSION" ]; then 
        print_color $RED "❌ Failed to get the latest version." 
        exit 1 
    fi 
    print_color $GREEN "✅ Latest version available: $LATEST_VERSION" 
}

# Generate configuration file
generate_config() {
    local mode=$1; local tunnel_name=$2; local transport=$3; local bind_addr=$4
    local remote_addr=$5; local token=$6; local ports_config=$7; local edge_ip=$8
    
    local config_file="$TUNNELS_DIR/${tunnel_name}.toml" 
    
    # Server (Iran) Config
    if [ "$mode" == "server" ]; then 
        cat > "$config_file" << EOF
[server]
bind_addr = "$bind_addr"
transport = "$transport"
token = "$token"
keepalive_period = 75
nodelay = true
heartbeat = 40
channel_size = 2048
sniffer = false
web_port = 0 # Disabled by default
sniffer_log = "$LOG_DIR/${tunnel_name}.json"
log_level = "info"
accept_udp = false
EOF
        if [[ "$transport" == "wss" || "$transport" == "wssmux" ]]; then 
            cat >> "$config_file" << EOF
tls_cert = "$CONFIG_DIR/certs/server.crt"
tls_key = "$CONFIG_DIR/certs/server.key"
EOF
        fi 
        if [[ "$transport" == "tcpmux" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then 
            # In the new TOML format, this is a sub-table
            cat >> "$config_file" << EOF
[server.mux]
con = 8
version = 1
framesize = 32768
recievebuffer = 4194304
streambuffer = 65536
EOF
        fi 
        if [ ! -z "$ports_config" ]; then 
            echo "ports = [" >> "$config_file" 
            IFS=',' read -ra PORTS <<< "$ports_config" 
            for port in "${PORTS[@]}"; do 
                echo "    \"$port\"," >> "$config_file" 
            done 
            echo "]" >> "$config_file" 
        else 
            echo "ports = []" >> "$config_file" 
        fi 

    # Client (Kharej) Config
    else
        cat > "$config_file" << EOF
[client]
remote_addr = "$remote_addr"
transport = "$transport"
token = "$token"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
retry_interval = 3
nodelay = true
sniffer = false
web_port = 0 # Disabled by default
sniffer_log = "$LOG_DIR/${tunnel_name}.json"
log_level = "info"
EOF
        if [[ "$transport" == "ws" || "$transport" == "wss" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then 
            echo "edge_ip = \"$edge_ip\"" >> "$config_file" 
        fi 
        if [[ "$transport" == "tcpmux" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then 
            # In the new TOML format, this is a sub-table
            cat >> "$config_file" << EOF
[client.mux]
version = 1
framesize = 32768
recievebuffer = 4194304
streambuffer = 65536
EOF
        fi 
    fi 
}

# Create systemd service file
create_service() {
    local tunnel_name=$1 
    local config_file="$TUNNELS_DIR/${tunnel_name}.toml" 
    local service_file="$SERVICE_DIR/backhaul-${tunnel_name}.service" 
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Backhaul Tunnel Service - $tunnel_name
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$BINARY_PATH -c $config_file
Restart=always
RestartSec=3
User=root
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload 
    sudo systemctl enable "backhaul-${tunnel_name}.service" 
}

# Check for required commands
check_requirements() {
    local missing_commands=() 
    for cmd in curl tar systemctl openssl; do 
        if ! command -v $cmd &> /dev/null; then 
            missing_commands+=($cmd) 
        fi 
    done 
    
    if [ ${#missing_commands[@]} -ne 0 ]; then 
        print_color $RED "❌ Missing required commands: ${missing_commands[*]}" 
        print_color $YELLOW "Attempting to install missing packages..." 
        
        if command -v apt-get &> /dev/null; then 
            sudo apt-get update && sudo apt-get install -y curl tar systemd openssl 
        elif command -v yum &> /dev/null; then 
            sudo yum install -y curl tar systemd openssl 
        elif command -v dnf &> /dev/null; then 
            sudo dnf install -y curl tar systemd openssl 
        else 
            print_color $RED "❌ Unsupported package manager. Please install manually." 
            exit 1 
        fi 
    fi 
}

# --- Menu Functions ---

# 1. Install or Reinstall Backhaul
install_backhaul() {
    print_header 
    print_color $YELLOW "📦 Installing Backhaul..." 
    
    detect_system 
    get_latest_version 
    
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${OS}_${ARCH}.tar.gz" 
    
    print_color $YELLOW "📥 Downloading from: $DOWNLOAD_URL" 
    
    cd /tmp 
    if ! curl -L -o "backhaul.tar.gz" "$DOWNLOAD_URL"; then 
        print_color $RED "❌ Download failed." 
        exit 1 
    fi 
    
    if ! tar -xzf backhaul.tar.gz; then 
        print_color $RED "❌ Failed to extract archive." 
        exit 1 
    fi 
    
    create_directories 
    sudo mv backhaul "$BINARY_PATH" 
    sudo chmod +x "$BINARY_PATH" 
    sudo ln -sf "$BINARY_PATH" /usr/local/bin/backhaul 
    
    print_color $GREEN "✅ Backhaul installed successfully!" 
    print_color $GREEN "📍 Binary location: $BINARY_PATH" 
    
    press_key
}

# 2. Update Backhaul
update_backhaul() {
    print_header 
    print_color $YELLOW "🔄 Updating Backhaul..." 
    
    current_version=$($BINARY_PATH --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown") 
    
    get_latest_version 
    
    if [ "$current_version" == "$LATEST_VERSION" ]; then 
        print_color $GREEN "✅ You are already running the latest version: $LATEST_VERSION" 
        press_key 
        return 
    fi 
    
    print_color $YELLOW "📦 Current version: $current_version" 
    print_color $YELLOW "🆕 Latest version: $LATEST_VERSION" 
    
    read -p "Do you want to continue with the update? (y/n): " confirm 
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then 
        print_color $YELLOW "Update cancelled." 
        sleep 1
        return 
    fi 
    
    print_color $YELLOW "⏸️ Stopping all tunnel services..." 
    for service in $(systemctl list-units --type=service --state=running | grep 'backhaul-' | awk '{print $1}'); do
        sudo systemctl stop "$service"
    done
    
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${OS}_${ARCH}.tar.gz" 
    cd /tmp 
    if ! curl -L -o "backhaul_new.tar.gz" "$DOWNLOAD_URL"; then 
        print_color $RED "❌ Failed to download update." 
        exit 1 
    fi 
    
    if ! tar -xzf backhaul_new.tar.gz; then 
        print_color $RED "❌ Failed to extract update." 
        exit 1 
    fi 
    
    sudo mv backhaul "$BINARY_PATH" 
    sudo chmod +x "$BINARY_PATH" 
    
    print_color $YELLOW "🔄 Restarting all tunnel services..." 
    for service in $(systemctl list-units --type=service --all | grep 'backhaul-' | awk '{print $1}'); do
        sudo systemctl start "$service"
    done
    
    print_color $GREEN "✅ Backhaul updated successfully to $LATEST_VERSION!" 
    press_key 
}

# 3. Generate TLS Certificate
generate_tls_cert() {
    print_header 
    print_color $YELLOW "🔒 Generating TLS Certificate..." 
    
    read -p "Enter your domain or IP address (default: localhost): " domain 
    [ -z "$domain" ] && domain="localhost" 
    
    local CERT_DIR="$CONFIG_DIR/certs" 
    sudo mkdir -p "$CERT_DIR" 
    
    sudo openssl req -x509 -nodes -newkey rsa:2048 -keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" -days 3650 -subj "/CN=$domain"
    sudo chmod 600 "$CERT_DIR/server.key" 
    
    print_color $GREEN "✅ TLS Certificate generated successfully!" 
    print_color $GREEN "📍 Certificate: $CERT_DIR/server.crt" 
    print_color $GREEN "📍 Private Key: $CERT_DIR/server.key" 
    
    press_key 
}

# 4. Create Server Tunnel (Iran)
create_server_tunnel() {
    print_header 
    print_color $GREEN "🇮🇷 Create New Server Tunnel (Iran)" 
    echo 
    
    read -p "Enter a name for this tunnel: " tunnel_name 
    if [ -z "$tunnel_name" ]; then 
        print_color $RED "❌ Tunnel name cannot be empty." 
        sleep 2; return 
    fi 
    
    print_color $CYAN "Available transport protocols:" 
    echo "1) tcp      2) tcpmux   3) udp      4) ws"
    echo "5) wss      6) wsmux    7) wssmux"
    read -p "Choose a transport protocol (default: tcp): " choice
    case $choice in 
        1) transport="tcp" ;; 
        2) transport="tcpmux" ;; 
        3) transport="udp" ;; 
        4) transport="ws" ;; 
        5) transport="wss" ;; 
        6) transport="wsmux" ;; 
        7) transport="wssmux" ;; 
        *) transport="tcp" ;; 
    esac 
    
    read -p "Enter bind address (e.g., 0.0.0.0:3080): " bind_addr 
    if [ -z "$bind_addr" ]; then 
        print_color $RED "❌ Bind address cannot be empty." 
        sleep 2; return
    fi 
    
    read -p "Enter authentication token (leave empty to generate): " token 
    [ -z "$token" ] && token=$(openssl rand -hex 16) && print_color $YELLOW "🔑 Generated token: $token" 
    
    print_color $CYAN "Port configuration examples (comma-separated):" 
    print_color $WHITE "  443         (Listen on port 443)" 
    print_color $WHITE "  443-600     (Listen on port range 443-600)" 
    print_color $WHITE "  443=5201    (Listen on 443, forward to 5201)" 
    print_color $WHITE "  443=1.1.1.1:5201 (Listen on 443, forward to 1.1.1.1:5201)" 
    read -p "Enter port configurations (leave empty to skip): " ports_config 
    
    if [[ "$transport" == "wss" || "$transport" == "wssmux" ]]; then 
        if [ ! -f "$CONFIG_DIR/certs/server.crt" ]; then 
            print_color $YELLOW "⚠️ SSL certificate is required for '$transport'." 
            read -p "Do you want to generate one now? (y/n): " gen_ssl 
            if [[ "$gen_ssl" == "y" || "$gen_ssl" == "Y" ]]; then 
                generate_tls_cert
            else 
                print_color $RED "❌ Aborting. SSL certificate is required." 
                sleep 2; return 
            fi 
        fi 
    fi 
    
    generate_config "server" "$tunnel_name" "$transport" "$bind_addr" "" "$token" "$ports_config" ""
    create_service "$tunnel_name" 
    sudo systemctl start "backhaul-${tunnel_name}.service" 
    
    print_color $GREEN "✅ Server tunnel '$tunnel_name' created and started!" 
    print_color $PURPLE "   - Config: $TUNNELS_DIR/${tunnel_name}.toml" 
    print_color $PURPLE "   - Token: $token" 
    print_color $PURPLE "   - Bind Address: $bind_addr" 
    
    press_key 
}

# 5. Create Client Tunnel (Kharej)
create_client_tunnel() {
    print_header 
    print_color $BLUE "🌍 Create New Client Tunnel (Kharej)" 
    echo 
    
    read -p "Enter a name for this tunnel: " tunnel_name 
    if [ -z "$tunnel_name" ]; then 
        print_color $RED "❌ Tunnel name cannot be empty." 
        sleep 2; return 
    fi 
    
    print_color $CYAN "Available transport protocols:" 
    echo "1) tcp      2) tcpmux   3) udp      4) ws"
    echo "5) wss      6) wsmux    7) wssmux"
    read -p "Choose a transport protocol (default: tcp): " choice
    case $choice in 
        1) transport="tcp" ;; 
        2) transport="tcpmux" ;; 
        3) transport="udp" ;; 
        4) transport="ws" ;; 
        5) transport="wss" ;; 
        6) transport="wsmux" ;; 
        7) transport="wssmux" ;; 
        *) transport="tcp" ;; 
    esac 
    
    read -p "Enter the server address (Iran Server IP:PORT): " remote_addr 
    if [ -z "$remote_addr" ]; then 
        print_color $RED "❌ Server address cannot be empty." 
        sleep 2; return 
    fi 
    
    read -p "Enter the authentication token: " token 
    if [ -z "$token" ]; then 
        print_color $RED "❌ Token cannot be empty." 
        sleep 2; return 
    fi 
    
    local edge_ip="" 
    if [[ "$transport" == "ws" || "$transport" == "wss" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then 
        read -p "Enter Edge IP (optional, for CDN): " edge_ip 
    fi 
    
    generate_config "client" "$tunnel_name" "$transport" "" "$remote_addr" "$token" "" "$edge_ip"
    create_service "$tunnel_name" 
    sudo systemctl start "backhaul-${tunnel_name}.service" 
    
    print_color $GREEN "✅ Client tunnel '$tunnel_name' created and started!" 
    print_color $PURPLE "   - Config: $TUNNELS_DIR/${tunnel_name}.toml" 
    print_color $PURPLE "   - Target Server: $remote_addr" 
    
    press_key 
}

# 6. List All Tunnels
list_tunnels() {
    print_header 
    print_color $CYAN "📋 List of All Tunnels" 
    echo 
    
    if [ -z "$(ls -A $TUNNELS_DIR/*.toml 2>/dev/null)" ]; then 
        print_color $YELLOW "⚠️ No tunnels found." 
        press_key 
        return 
    fi 
    
    printf "%-20s %-18s %-15s %-22s %-25s\n" "NAME" "TYPE" "TRANSPORT" "STATUS" "ADDRESS" 
    printf "%-20s %-18s %-15s %-22s %-25s\n" "----" "----" "---------" "------" "-------" 
    
    for config_file in "$TUNNELS_DIR"/*.toml; do 
        tunnel_name=$(basename "$config_file" .toml) 
        
        if grep -q "\[server\]" "$config_file"; then 
            tunnel_type="🇮🇷 Server (Iran)" 
            address=$(grep "bind_addr" "$config_file" | cut -d'"' -f2) 
        else 
            tunnel_type="🌍 Client (Kharej)" 
            address=$(grep "remote_addr" "$config_file" | cut -d'"' -f2) 
        fi 
        
        transport=$(grep "transport" "$config_file" | cut -d'"' -f2) 
        
        if systemctl is-active --quiet "backhaul-${tunnel_name}.service"; then 
            status="${GREEN}● Active${NC}" 
        else 
            status="${RED}● Inactive${NC}" 
        fi 
        
        printf "%-20s %-18s %-15s %-22s %-25s\n" "$tunnel_name" "$tunnel_type" "$transport" "$status" "$address" 
    done 
    
    echo 
    press_key 
}

# 7. Manage Tunnels
manage_tunnel() {
    print_header 
    print_color $YELLOW "🔧 Tunnel Management" 
    echo 

    if [ -z "$(ls -A $TUNNELS_DIR/*.toml 2>/dev/null)" ]; then 
        print_color $YELLOW "⚠️ No tunnels found to manage." 
        press_key 
        return 
    fi 
    
    print_color $CYAN "Select a tunnel to manage:" 
    i=1 
    declare -a tunnel_names 
    for config_file in "$TUNNELS_DIR"/*.toml; do 
        tunnel_name=$(basename "$config_file" .toml) 
        tunnel_names[$i]=$tunnel_name 
        printf "%d) %s\n" $i "$tunnel_name" 
        ((i++)) 
    done 
    echo 
    read -p "Enter tunnel number (or 0 to cancel): " tunnel_num 
    
    if [[ "$tunnel_num" -eq 0 ]]; then return; fi
    if ! [[ "$tunnel_num" =~ ^[0-9]+$ ]] || [ "$tunnel_num" -lt 1 ] || [ "$tunnel_num" -ge "$i" ]; then 
        print_color $RED "❌ Invalid selection."; sleep 2; return 
    fi 
    
    selected_tunnel=${tunnel_names[$tunnel_num]} 
    service_name="backhaul-${selected_tunnel}.service" 

    print_header 
    print_color $CYAN "Actions for tunnel '$selected_tunnel':" 
    echo "1) Start" 
    echo "2) Stop" 
    echo "3) Restart" 
    echo "4) Show Status" 
    echo "5) View Logs (-f)" 
    echo "6) View Config" 
    print_color $RED "7) Delete Tunnel" 
    echo 
    read -p "Choose an action (or 0 to return): " action 
    
    case $action in 
        1) sudo systemctl start "$service_name"; print_color $GREEN "✅ Tunnel started." ;; 
        2) sudo systemctl stop "$service_name"; print_color $YELLOW "⏹️ Tunnel stopped." ;; 
        3) sudo systemctl restart "$service_name"; print_color $GREEN "🔄 Tunnel restarted." ;; 
        4) sudo systemctl status "$service_name" ;; 
        5) journalctl -u "$service_name" -n 50 -f ;; 
        6) print_color $CYAN "📄 Config for '$selected_tunnel':"; cat "$TUNNELS_DIR/${selected_tunnel}.toml";;
        7) 
            read -p "Are you sure you want to DELETE '$selected_tunnel'? (y/n): " confirm 
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then 
                sudo systemctl stop "$service_name" 
                sudo systemctl disable "$service_name" 
                sudo rm -f "$SERVICE_DIR/$service_name" 
                sudo rm -f "$TUNNELS_DIR/${selected_tunnel}.toml" 
                sudo systemctl daemon-reload 
                print_color $GREEN "✅ Tunnel '$selected_tunnel' has been deleted." 
            fi 
            ;; 
        0) return ;;
        *) print_color $RED "❌ Invalid action." ;; 
    esac 
    
    if [[ "$action" != "4" && "$action" != "5" ]]; then 
        press_key 
    fi 
}

# 8. Uninstall Backhaul
uninstall_backhaul() {
    print_header 
    print_color $RED "🗑️ Uninstall Backhaul" 
    echo 
    print_color $YELLOW "⚠️ WARNING: This will remove:" 
    print_color $WHITE "   - All tunnel configurations and services" 
    print_color $WHITE "   - The Backhaul binary and all related directories" 
    echo 
    read -p "To confirm, type 'YES': " confirm 
    if [ "$confirm" != "YES" ]; then 
        print_color $GREEN "❌ Uninstall cancelled." 
        press_key 
        return 
    fi 
    
    for service in $(systemctl list-units --type=service --all | grep 'backhaul-' | awk '{print $1}'); do
        sudo systemctl stop "$service" 
        sudo systemctl disable "$service" 
    done
    
    sudo rm -rf "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR" 
    sudo rm -f /usr/local/bin/backhaul 
    sudo rm -f $SERVICE_DIR/backhaul-*.service 
    sudo systemctl daemon-reload 
    
    print_color $GREEN "✅ Backhaul has been uninstalled successfully." 
    read -p "Press Enter to exit..." 
    exit 0 
}


# --- Main Menu and Execution Loop ---

# Display the main menu
display_menu() {
    print_header 
    
    # Display Status Info
    if [ -f "$BINARY_PATH" ]; then 
        version=$($BINARY_PATH --version 2>/dev/null | head -1 || echo "N/A") 
        print_color $WHITE "Status: ${GREEN}Installed (Version: $version)${NC}" 
    else 
        print_color $WHITE "Status: ${RED}Not Installed${NC}" 
    fi 
    tunnel_count=$(ls -1q "$TUNNELS_DIR"/*.toml 2>/dev/null | wc -l) 
    print_color $WHITE "Configured Tunnels: ${YELLOW}${tunnel_count}${NC}" 
    print_color $CYAN "----------------------------------------------------------------------"
    
    # Menu Options
    print_color $GREEN "   --- Installation & Updates ---" 
    print_color $WHITE "   1. Install or Reinstall Backhaul" 
    print_color $WHITE "   2. Update Backhaul" 
    print_color $WHITE "   3. Generate TLS Certificate" 
    
    print_color $BLUE "\n   --- Tunnel Management ---" 
    print_color $WHITE "   4. Create Server Tunnel (Iran)" 
    print_color $WHITE "   5. Create Client Tunnel (Kharej)" 
    print_color $WHITE "   6. List All Tunnels" 
    print_color $WHITE "   7. Manage a Tunnel" 
    
    print_color $RED "\n   --- Maintenance ---" 
    print_color $WHITE "   8. Uninstall Backhaul" 
    
    print_color $YELLOW "\n   0. Exit" 
    print_color $CYAN "----------------------------------------------------------------------"
}

# Read user choice and call the corresponding function
read_option() {
    read -p "Enter your choice [0-8]: " choice 
    
    case $choice in 
        1) install_backhaul ;; 
        2) update_backhaul ;; 
        3) generate_tls_cert ;; 
        4) create_server_tunnel ;; 
        5) create_client_tunnel ;; 
        6) list_tunnels ;; 
        7) manage_tunnel ;; 
        8) uninstall_backhaul ;; 
        0) print_color $GREEN "👋 Goodbye!"; exit 0 ;; 
        *) print_color $RED "❌ Invalid option. Please try again."; sleep 2 ;; 
    esac 
}

# --- Script Initialization ---

init_script() {
    check_requirements
    create_directories 
    
    # First run check
    if [ ! -f "$BINARY_PATH" ]; then 
        print_header 
        print_color $YELLOW "🎉 Welcome to the Backhaul Manager!" 
        print_color $WHITE "It seems this is your first time running the script." 
        read -p "Would you like to install Backhaul now? (y/n): " install_now 
        if [[ "$install_now" == "y" || "$install_now" == "Y" ]]; then 
            install_backhaul 
        fi 
    fi 
}

# Main execution loop
main() {
    init_script
    while true; do 
        display_menu
        read_option
    done 
}

# Run the script
main "$@"
