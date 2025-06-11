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
            echo 'edge_ip = ""' >> "$config
