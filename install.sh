#!/bin/bash

# Backhaul Management Script
# Complete tunnel management solution with auto-detection and service management
# Compatible with all Backhaul protocols: tcp, tcpmux, udp, ws, wss, wsmux, wssmux

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration directories and files
BACKHAUL_DIR="/opt/backhaul"
CONFIG_DIR="/etc/backhaul"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log/backhaul"
BINARY_PATH="$BACKHAUL_DIR/backhaul"
TUNNELS_DIR="$CONFIG_DIR/tunnels"

# Create necessary directories
create_directories() {
    sudo mkdir -p "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TUNNELS_DIR"
    sudo chmod 755 "$BACKHAUL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TUNNELS_DIR"
}

# Print colored output
print_color() {
    printf "${1}${2}${NC}\n"
}

# Print header
print_header() {
    clear
    print_color $CYAN "======================================================================"
    print_color $CYAN "                     🚀 Backhaul Manager v2.0 🚀                    "
    print_color $CYAN "       Lightning-fast reverse tunneling solution manager            "
    print_color $CYAN "======================================================================"
    echo
}

# Detect system architecture and OS
detect_system() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        i386|i686)
            ARCH="386" 
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
        *)
            print_color $RED "❌ Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case $OS in
        linux)
            OS="linux"
            ;;
        darwin)
            OS="darwin"
            ;;
        *)
            print_color $RED "❌ Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    print_color $GREEN "🔍 Detected System: $OS-$ARCH"
}

# Get latest version from GitHub
get_latest_version() {
    print_color $YELLOW "🔄 Checking for latest Backhaul version..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_VERSION" ]; then
        print_color $RED "❌ Failed to get latest version"
        exit 1
    fi
    print_color $GREEN "✅ Latest version: $LATEST_VERSION"
}

# Download and install Backhaul
install_backhaul() {
    print_header
    print_color $YELLOW "📦 Installing Backhaul..."
    
    detect_system
    get_latest_version
    
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${OS}_${ARCH}.tar.gz"
    
    print_color $YELLOW "📥 Downloading from: $DOWNLOAD_URL"
    
    # Download and extract
    cd /tmp
    if ! curl -L -o "backhaul.tar.gz" "$DOWNLOAD_URL"; then
        print_color $RED "❌ Failed to download Backhaul"
        exit 1
    fi
    
    if ! tar -xzf backhaul.tar.gz; then
        print_color $RED "❌ Failed to extract Backhaul"
        exit 1
    fi
    
    # Install binary
    create_directories
    sudo mv backhaul "$BINARY_PATH"
    sudo chmod +x "$BINARY_PATH"
    
    # Create symlink for global access
    sudo ln -sf "$BINARY_PATH" /usr/local/bin/backhaul
    
    print_color $GREEN "✅ Backhaul installed successfully!"
    print_color $GREEN "📍 Binary location: $BINARY_PATH"
    
    read -p "Press Enter to continue..."
}

# Generate TLS certificate
generate_tls_cert() {
    print_header
    print_color $YELLOW "🔒 Generating TLS Certificate..."
    
    read -p "Enter domain or IP address: " domain
    if [ -z "$domain" ]; then
        domain="localhost"
    fi
    
    CERT_DIR="$CONFIG_DIR/certs"
    sudo mkdir -p "$CERT_DIR"
    
    # Generate private key
    sudo openssl genpkey -algorithm RSA -out "$CERT_DIR/server.key" -pkeyopt rsa_keygen_bits:2048
    
    # Generate certificate
    sudo openssl req -new -x509 -key "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" -days 365 -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain"
    
    sudo chmod 600 "$CERT_DIR/server.key"
    sudo chmod 644 "$CERT_DIR/server.crt"
    
    print_color $GREEN "✅ TLS Certificate generated successfully!"
    print_color $GREEN "📍 Certificate: $CERT_DIR/server.crt"
    print_color $GREEN "📍 Private Key: $CERT_DIR/server.key"
    
    read -p "Press Enter to continue..."
}

# Generate configuration file
generate_config() {
    local mode=$1
    local tunnel_name=$2
    local transport=$3
    local bind_addr=$4
    local remote_addr=$5
    local token=$6
    local ports_config=$7
    
    config_file="$TUNNELS_DIR/${tunnel_name}.toml"
    
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
web_port = 2060
sniffer_log = "$LOG_DIR/${tunnel_name}.json"
log_level = "info"
accept_udp = false
EOF

        # Add SSL certificates for secure transports
        if [[ "$transport" == "wss" || "$transport" == "wssmux" ]]; then
            cat >> "$config_file" << EOF
tls_cert = "$CONFIG_DIR/certs/server.crt"
tls_key = "$CONFIG_DIR/certs/server.key"
EOF
        fi

        # Add multiplexing settings for mux transports
        if [[ "$transport" == "tcpmux" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
            cat >> "$config_file" << EOF
mux_con = 8
mux_version = 1
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 65536
EOF
        fi

        # Add ports configuration
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

    else # client mode
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
web_port = 2061
sniffer_log = "$LOG_DIR/${tunnel_name}.json"
log_level = "info"
EOF

        # Add edge IP for WebSocket transports
        if [[ "$transport" == "ws" || "$transport" == "wss" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
            echo 'edge_ip = ""' >> "$config_file"
        fi

        # Add multiplexing settings for mux transports
        if [[ "$transport" == "tcpmux" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
            cat >> "$config_file" << EOF
mux_version = 1
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 65536
EOF
        fi
    fi
}

# Create systemd service
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

# Create tunnel (Server/Iran)
create_server_tunnel() {
    print_header
    print_color $GREEN "🇮🇷 Creating Iran Server Tunnel"
    echo
    
    read -p "Enter tunnel name: " tunnel_name
    if [ -z "$tunnel_name" ]; then
        print_color $RED "❌ Tunnel name cannot be empty"
        return
    fi
    
    print_color $CYAN "Available transport protocols:"
    print_color $WHITE "1) tcp      - Simple TCP transport"
    print_color $WHITE "2) tcpmux   - TCP with multiplexing"
    print_color $WHITE "3) udp      - UDP transport"
    print_color $WHITE "4) ws       - WebSocket transport"
    print_color $WHITE "5) wss      - Secure WebSocket transport"
    print_color $WHITE "6) wsmux    - WebSocket with multiplexing"
    print_color $WHITE "7) wssmux   - Secure WebSocket with multiplexing"
    echo
    
    read -p "Choose transport protocol (1-7): " transport_choice
    case $transport_choice in
        1) transport="tcp" ;;
        2) transport="tcpmux" ;;
        3) transport="udp" ;;
        4) transport="ws" ;;
        5) transport="wss" ;;
        6) transport="wsmux" ;;
        7) transport="wssmux" ;;
        *) transport="tcp" ;;
    esac
    
    read -p "Enter bind address (default: 0.0.0.0:3080): " bind_addr
    if [ -z "$bind_addr" ]; then
        bind_addr="0.0.0.0:3080"
    fi
    
    read -p "Enter authentication token: " token
    if [ -z "$token" ]; then
        token=$(openssl rand -hex 16)
        print_color $YELLOW "🔑 Generated token: $token"
    fi
    
    print_color $CYAN "Port configuration examples:"
    print_color $WHITE "443         - Listen on port 443"
    print_color $WHITE "443-600     - Listen on port range 443-600"
    print_color $WHITE "443=5201    - Listen on 443, forward to 5201"
    print_color $WHITE "443=1.1.1.1:5201 - Listen on 443, forward to 1.1.1.1:5201"
    echo
    read -p "Enter ports configuration (comma separated, press Enter to skip): " ports_config
    
    # Check if SSL certificates are needed
    if [[ "$transport" == "wss" || "$transport" == "wssmux" ]]; then
        if [ ! -f "$CONFIG_DIR/certs/server.crt" ]; then
            print_color $YELLOW "⚠️  SSL certificates required for $transport"
            read -p "Generate SSL certificates now? (y/n): " gen_ssl
            if [[ "$gen_ssl" == "y" || "$gen_ssl" == "Y" ]]; then
                generate_tls_cert
            else
                print_color $RED "❌ SSL certificates required. Aborting."
                return
            fi
        fi
    fi
    
    generate_config "server" "$tunnel_name" "$transport" "$bind_addr" "" "$token" "$ports_config"
    create_service "$tunnel_name"
    
    sudo systemctl start "backhaul-${tunnel_name}.service"
    
    print_color $GREEN "✅ Server tunnel '$tunnel_name' created and started!"
    print_color $GREEN "📍 Config: $TUNNELS_DIR/${tunnel_name}.toml"
    print_color $GREEN "🔑 Token: $token"
    print_color $GREEN "🌐 Bind Address: $bind_addr"
    print_color $GREEN "🚀 Transport: $transport"
    
    read -p "Press Enter to continue..."
}

# Create tunnel (Client/Kharej)
create_client_tunnel() {
    print_header
    print_color $BLUE "🌍 Creating Kharej Client Tunnel"
    echo
    
    read -p "Enter tunnel name: " tunnel_name
    if [ -z "$tunnel_name" ]; then
        print_color $RED "❌ Tunnel name cannot be empty"
        return
    fi
    
    print_color $CYAN "Available transport protocols:"
    print_color $WHITE "1) tcp      - Simple TCP transport"
    print_color $WHITE "2) tcpmux   - TCP with multiplexing"
    print_color $WHITE "3) udp      - UDP transport"
    print_color $WHITE "4) ws       - WebSocket transport"
    print_color $WHITE "5) wss      - Secure WebSocket transport"
    print_color $WHITE "6) wsmux    - WebSocket with multiplexing"
    print_color $WHITE "7) wssmux   - Secure WebSocket with multiplexing"
    echo
    
    read -p "Choose transport protocol (1-7): " transport_choice
    case $transport_choice in
        1) transport="tcp" ;;
        2) transport="tcpmux" ;;
        3) transport="udp" ;;
        4) transport="ws" ;;
        5) transport="wss" ;;
        6) transport="wsmux" ;;
        7) transport="wssmux" ;;
        *) transport="tcp" ;;
    esac
    
    read -p "Enter server address (Iran server IP:PORT): " remote_addr
    if [ -z "$remote_addr" ]; then
        print_color $RED "❌ Server address cannot be empty"
        return
    fi
    
    read -p "Enter authentication token: " token
    if [ -z "$token" ]; then
        print_color $RED "❌ Authentication token cannot be empty"
        return
    fi
    
    # Ask for edge IP if using WebSocket transports
    if [[ "$transport" == "ws" || "$transport" == "wss" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
        read -p "Enter edge IP (optional, for CDN): " edge_ip
    fi
    
    generate_config "client" "$tunnel_name" "$transport" "" "$remote_addr" "$token" ""
    
    # Add edge IP to config if provided
    if [ ! -z "$edge_ip" ]; then
        sed -i "s/edge_ip = \"\"/edge_ip = \"$edge_ip\"/" "$TUNNELS_DIR/${tunnel_name}.toml"
    fi
    
    create_service "$tunnel_name"
    sudo systemctl start "backhaul-${tunnel_name}.service"
    
    print_color $GREEN "✅ Client tunnel '$tunnel_name' created and started!"
    print_color $GREEN "📍 Config: $TUNNELS_DIR/${tunnel_name}.toml"
    print_color $GREEN "🎯 Server: $remote_addr"
    print_color $GREEN "🚀 Transport: $transport"
    
    read -p "Press Enter to continue..."
}

# List all tunnels
list_tunnels() {
    print_header
    print_color $CYAN "📋 Active Tunnels"
    echo
    
    if [ ! -d "$TUNNELS_DIR" ] || [ -z "$(ls -A $TUNNELS_DIR 2>/dev/null)" ]; then
        print_color $YELLOW "⚠️  No tunnels found"
        read -p "Press Enter to continue..."
        return
    fi
    
    printf "%-20s %-10s %-15s %-10s %-15s\n" "NAME" "TYPE" "TRANSPORT" "STATUS" "ADDRESS"
    printf "%-20s %-10s %-15s %-10s %-15s\n" "----" "----" "---------" "------" "-------"
    
    for config_file in "$TUNNELS_DIR"/*.toml; do
        if [ -f "$config_file" ]; then
            tunnel_name=$(basename "$config_file" .toml)
            
            # Determine type (server or client)
            if grep -q "\[server\]" "$config_file"; then
                tunnel_type="🇮🇷 Iran"
                address=$(grep "bind_addr" "$config_file" | cut -d'"' -f2)
            else
                tunnel_type="🌍 Kharej"
                address=$(grep "remote_addr" "$config_file" | cut -d'"' -f2)
            fi
            
            transport=$(grep "transport" "$config_file" | cut -d'"' -f2)
            
            # Check service status
            if systemctl is-active --quiet "backhaul-${tunnel_name}.service"; then
                status="${GREEN}●${NC} Active"
            else
                status="${RED}●${NC} Inactive"
            fi
            
            printf "%-20s %-10s %-15s %-22s %-15s\n" "$tunnel_name" "$tunnel_type" "$transport" "$status" "$address"
        fi
    done
    
    echo
    read -p "Press Enter to continue..."
}

# Manage tunnel (start/stop/restart/status)
manage_tunnel() {
    print_header
    print_color $YELLOW "🔧 Tunnel Management"
    echo
    
    if [ ! -d "$TUNNELS_DIR" ] || [ -z "$(ls -A $TUNNELS_DIR 2>/dev/null)" ]; then
        print_color $YELLOW "⚠️  No tunnels found"
        read -p "Press Enter to continue..."
        return
    fi
    
    print_color $CYAN "Available tunnels:"
    i=1
    declare -a tunnel_names
    for config_file in "$TUNNELS_DIR"/*.toml; do
        if [ -f "$config_file" ]; then
            tunnel_name=$(basename "$config_file" .toml)
            tunnel_names[$i]=$tunnel_name
            
            if systemctl is-active --quiet "backhaul-${tunnel_name}.service"; then
                status="${GREEN}[Active]${NC}"
            else
                status="${RED}[Inactive]${NC}"
            fi
            
            printf "%d) %s %s\n" $i "$tunnel_name" "$status"
            ((i++))
        fi
    done
    
    echo
    read -p "Select tunnel number: " tunnel_num
    
    if [[ ! "$tunnel_num" =~ ^[0-9]+$ ]] || [ "$tunnel_num" -lt 1 ] || [ "$tunnel_num" -ge "$i" ]; then
        print_color $RED "❌ Invalid selection"
        read -p "Press Enter to continue..."
        return
    fi
    
    selected_tunnel=${tunnel_names[$tunnel_num]}
    
    echo
    print_color $CYAN "Management options for '$selected_tunnel':"
    print_color $WHITE "1) Start tunnel"
    print_color $WHITE "2) Stop tunnel"
    print_color $WHITE "3) Restart tunnel"
    print_color $WHITE "4) Show status"
    print_color $WHITE "5) View logs"
    print_color $WHITE "6) Delete tunnel"
    echo
    
    read -p "Choose action (1-6): " action
    
    case $action in
        1)
            sudo systemctl start "backhaul-${selected_tunnel}.service"
            print_color $GREEN "✅ Tunnel '$selected_tunnel' started"
            ;;
        2)
            sudo systemctl stop "backhaul-${selected_tunnel}.service"
            print_color $YELLOW "⏹️  Tunnel '$selected_tunnel' stopped"
            ;;
        3)
            sudo systemctl restart "backhaul-${selected_tunnel}.service"
            print_color $GREEN "🔄 Tunnel '$selected_tunnel' restarted"
            ;;
        4)
            systemctl status "backhaul-${selected_tunnel}.service"
            ;;
        5)
            journalctl -u "backhaul-${selected_tunnel}.service" -n 50 -f
            ;;
        6)
            read -p "Are you sure you want to delete tunnel '$selected_tunnel'? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                sudo systemctl stop "backhaul-${selected_tunnel}.service"
                sudo systemctl disable "backhaul-${selected_tunnel}.service"
                sudo rm -f "$SERVICE_DIR/backhaul-${selected_tunnel}.service"
                sudo rm -f "$TUNNELS_DIR/${selected_tunnel}.toml"
                sudo systemctl daemon-reload
                print_color $GREEN "✅ Tunnel '$selected_tunnel' deleted"
            fi
            ;;
        *)
            print_color $RED "❌ Invalid action"
            ;;
    esac
    
    if [[ "$action" != "5" ]]; then
        read -p "Press Enter to continue..."
    fi
}

# View tunnel configuration
view_config() {
    print_header
    print_color $CYAN "📄 View Tunnel Configuration"
    echo
    
    if [ ! -d "$TUNNELS_DIR" ] || [ -z "$(ls -A $TUNNELS_DIR 2>/dev/null)" ]; then
        print_color $YELLOW "⚠️  No tunnels found"
        read -p "Press Enter to continue..."
        return
    fi
    
    print_color $CYAN "Available tunnels:"
    i=1
    declare -a tunnel_names
    for config_file in "$TUNNELS_DIR"/*.toml; do
        if [ -f "$config_file" ]; then
            tunnel_name=$(basename "$config_file" .toml)
            tunnel_names[$i]=$tunnel_name
            printf "%d) %s\n" $i "$tunnel_name"
            ((i++))
        fi
    done
    
    echo
    read -p "Select tunnel number: " tunnel_num
    
    if [[ ! "$tunnel_num" =~ ^[0-9]+$ ]] || [ "$tunnel_num" -lt 1 ] || [ "$tunnel_num" -ge "$i" ]; then
        print_color $RED "❌ Invalid selection"
        read -p "Press Enter to continue..."
        return
    fi
    
    selected_tunnel=${tunnel_names[$tunnel_num]}
    config_file="$TUNNELS_DIR/${selected_tunnel}.toml"
    
    print_color $GREEN "📄 Configuration for '$selected_tunnel':"
    echo
    cat "$config_file"
    echo
    
    read -p "Press Enter to continue..."
}

# Update Backhaul to latest version
update_backhaul() {
    print_header
    print_color $YELLOW "🔄 Updating Backhaul..."
    
    # Check current version
    current_version=""
    if [ -f "$BINARY_PATH" ]; then
        current_version=$($BINARY_PATH --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    fi
    
    detect_system
    get_latest_version
    
    if [ "$current_version" == "$LATEST_VERSION" ]; then
        print_color $GREEN "✅ Already running latest version: $LATEST_VERSION"
        read -p "Press Enter to continue..."
        return
    fi
    
    print_color $YELLOW "📦 Current version: $current_version"
    print_color $YELLOW "🆕 Latest version: $LATEST_VERSION"
    
    read -p "Continue with update? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return
    fi
    
    # Stop all services temporarily
    print_color $YELLOW "⏸️  Stopping all tunnel services..."
    for config_file in "$TUNNELS_DIR"/*.toml; do
        if [ -f "$config_file" ]; then
            tunnel_name=$(basename "$config_file" .toml)
            sudo systemctl stop "backhaul-${tunnel_name}.service" 2>/dev/null || true
        fi
    done
    
    # Download and install new version
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/${LATEST_VERSION}/backhaul_${OS}_${ARCH}.tar.gz"
    
    cd /tmp
    if ! curl -L -o "backhaul_new.tar.gz" "$DOWNLOAD_URL"; then
        print_color $RED "❌ Failed to download update"
        exit 1
    fi
    
    if ! tar -xzf backhaul_new.tar.gz; then
        print_color $RED "❌ Failed to extract update"
        exit 1
    fi
    
    # Backup old binary
    sudo cp "$BINARY_PATH" "${BINARY_PATH}.backup"
    
    # Install new binary
    sudo mv backhaul "$BINARY_PATH"
    sudo chmod +x "$BINARY_PATH"
    
    # Restart all services
    print_color $YELLOW "🔄 Restarting all tunnel services..."
    for config_file in "$TUNNELS_DIR"/*.toml; do
        if [ -f "$config_file" ]; then
            tunnel_name=$(basename "$config_file" .toml)
            sudo systemctl start "backhaul-${tunnel_name}.service" 2>/dev/null || true
        fi
    done
    
    print_color $GREEN "✅ Backhaul updated successfully to $LATEST_VERSION!"
    
    read -p "Press Enter to continue..."
}

# Uninstall Backhaul
uninstall_backhaul() {
    print_header
    print_color $RED "🗑️  Uninstall Backhaul"
    echo
    
    print_color $YELLOW "⚠️  This will remove:"
    print_color $WHITE "   • All tunnel configurations"
    print_color $WHITE "   • All tunnel services"
    print_color $WHITE "   • Backhaul binary"
    print_color $WHITE "   • Log files"
    echo
    
    read -p "Are you sure you want to uninstall Backhaul? (type 'YES' to confirm): " confirm
    if [ "$confirm" != "YES" ]; then
        print_color $GREEN "❌ Uninstall cancelled"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Stop and remove all services
    for config_file in "$TUNNELS_DIR"/*.toml; do
        if [ -f "$config_file" ]; then
            tunnel_name=$(basename "$config_file" .toml)
            sudo systemctl stop "backhaul-${tunnel_name}.service" 2>/dev/null || true
            sudo systemctl disable "backhaul-${tunnel_name}.service" 2>/dev/null || true
            sudo rm -f "$SERVICE_DIR/backhaul-${tunnel_name}.service"
        fi
    done
    
    # Remove directories and files
    sudo rm -rf "$BACKHAUL_DIR"
    sudo rm -rf "$CONFIG_DIR"
    sudo rm -rf "$LOG_DIR"
    sudo rm -f /usr/local/bin/backhaul
    
    sudo systemctl daemon-reload
    
    print_color $GREEN "✅ Backhaul uninstalled successfully!"
    
    read -p "Press Enter to exit..."
    exit 0
}

# System information
show_system_info() {
    print_header
    print_color $CYAN "💻 System Information"
    echo
    
    print_color $WHITE "🔧 System Details:"
    print_color $GREEN "   OS: $(uname -s)"
    print_color $GREEN "   Architecture: $(uname -m)"
    print_color $GREEN "   Kernel: $(uname -r)"
    print_color $GREEN "   Hostname: $(hostname)"
    echo
    
    if [ -f "$BINARY_PATH" ]; then
        version=$($BINARY_PATH --version 2>/dev/null | head -1 || echo "Unable to get version")
        print_color $WHITE "🚀 Backhaul Status:"
        print_color $GREEN "   Binary: $BINARY_PATH"
        print_color $GREEN "   Version: $version"
        print_color $GREEN "   Status: Installed"
    else
        print_color $RED "   Status: Not Installed"
    fi
    echo
    
    print_color $WHITE "📊 Active Tunnels:"
    tunnel_count=0
    if [ -d "$TUNNELS_DIR" ]; then
        for config_file in "$TUNNELS_DIR"/*.toml; do
            if [ -f "$config_file" ]; then
                tunnel_name=$(basename "$config_file" .toml)
                if systemctl is-active --quiet "backhaul-${tunnel_name}.service"; then
                    print_color $GREEN "   ✅ $tunnel_name (Active)"
                else
                    print_color $RED "   ❌ $tunnel_name (Inactive)"
                fi
                ((tunnel_count++))
            fi
        done
    fi
    
    if [ $tunnel_count -eq 0 ]; then
        print_color $YELLOW "   No tunnels configured"
    fi
    
    echo
    print_color $WHITE "💾 Disk Usage:"
    df -h / | tail -1 | awk '{print "   Free Space: " $4 " / " $2}'
    
    echo
    print_color $WHITE "🌐 Network:"
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -3 | while read ip; do
        print_color $GREEN "   IP: $ip"
    done
    
    read -p "Press Enter to continue..."
}

# Main menu
show_main_menu() {
    while true; do
        print_header
        print_color $WHITE "Please select an option:"
        echo
        print_color $GREEN "📦 Installation & Updates:"
        print_color $WHITE "   1) Install Backhaul"
        print_color $WHITE "   2) Update Backhaul"
        print_color $WHITE "   3) Generate TLS Certificate"
        echo
        print_color $BLUE "🔧 Tunnel Management:"
        print_color $WHITE "   4) Create Iran Server Tunnel"
        print_color $WHITE "   5) Create Kharej Client Tunnel"
        print_color $WHITE "   6) List All Tunnels"
        print_color $WHITE "   7) Manage Tunnel (Start/Stop/Restart)"
        print_color $WHITE "   8) View Tunnel Configuration"
        echo
        print_color $CYAN "ℹ️  Information & Utilities:"
        print_color $WHITE "   9) System Information"
        print_color $WHITE "   10) View Logs"
        echo
        print_color $RED "🗑️  Maintenance:"
        print_color $WHITE "   11) Uninstall Backhaul"
        echo
        print_color $YELLOW "   0) Exit"
        echo
        
        read -p "Enter your choice [0-11]: " choice
        
        case $choice in
            1) install_backhaul ;;
            2) update_backhaul ;;
            3) generate_tls_cert ;;
            4) create_server_tunnel ;;
            5) create_client_tunnel ;;
            6) list_tunnels ;;
            7) manage_tunnel ;;
            8) view_config ;;
            9) show_system_info ;;
            10) view_logs ;;
            11) uninstall_backhaul ;;
            0) 
                print_color $GREEN "👋 Thank you for using Backhaul Manager!"
                exit 0
                ;;
            *)
                print_color $RED "❌ Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# View logs function
view_logs() {
    print_header
    print_color $CYAN "📋 View Tunnel Logs"
    echo
    
    if [ ! -d "$TUNNELS_DIR" ] || [ -z "$(ls -A $TUNNELS_DIR 2>/dev/null)" ]; then
        print_color $YELLOW "⚠️  No tunnels found"
        read -p "Press Enter to continue..."
        return
    fi
    
    print_color $CYAN "Available tunnels:"
    i=1
    declare -a tunnel_names
    for config_file in "$TUNNELS_DIR"/*.toml; do
        if [ -f "$config_file" ]; then
            tunnel_name=$(basename "$config_file" .toml)
            tunnel_names[$i]=$tunnel_name
            printf "%d) %s\n" $i "$tunnel_name"
            ((i++))
        fi
    done
    
    echo
    read -p "Select tunnel number: " tunnel_num
    
    if [[ ! "$tunnel_num" =~ ^[0-9]+$ ]] || [ "$tunnel_num" -lt 1 ] || [ "$tunnel_num" -ge "$i" ]; then
        print_color $RED "❌ Invalid selection"
        read -p "Press Enter to continue..."
        return
    fi
    
    selected_tunnel=${tunnel_names[$tunnel_num]}
    
    print_color $GREEN "📋 Logs for '$selected_tunnel' (Press Ctrl+C to exit):"
    journalctl -u "backhaul-${selected_tunnel}.service" -f
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_color $RED "❌ This script must be run as root"
        print_color $YELLOW "Please run: sudo $0"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    # Check for required commands
    local missing_commands=()
    
    for cmd in curl tar systemctl openssl; do
        if ! command -v $cmd &> /dev/null; then
            missing_commands+=($cmd)
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        print_color $RED "❌ Missing required commands: ${missing_commands[*]}"
        print_color $YELLOW "Installing missing packages..."
        
        # Detect package manager and install
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y curl tar systemd openssl
        elif command -v yum &> /dev/null; then
            yum install -y curl tar systemd openssl
        elif command -v dnf &> /dev/null; then
            dnf install -y curl tar systemd openssl
        else
            print_color $RED "❌ Unable to install required packages automatically"
            print_color $YELLOW "Please install manually: ${missing_commands[*]}"
            exit 1
        fi
    fi
}

# Initialize script
init_script() {
    check_root
    check_requirements
    create_directories
}

# Main execution
main() {
    init_script
    
    # Show welcome message on first run
    if [ ! -f "$BINARY_PATH" ]; then
        print_header
        print_color $YELLOW "🎉 Welcome to Backhaul Manager!"
        print_color $WHITE "This appears to be your first time running the manager."
        print_color $WHITE "Would you like to install Backhaul now?"
        echo
        read -p "Install Backhaul? (y/n): " install_now
        if [[ "$install_now" == "y" || "$install_now" == "Y" ]]; then
            install_backhaul
        fi
    fi
    
    show_main_menu
}

# Run main function
main "$@"
