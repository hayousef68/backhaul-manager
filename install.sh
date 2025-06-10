#!/bin/bash

# Backhaul Management Script
# Version: 1.0
# Author: Auto-generated

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ASCII Art
print_logo() {
    echo -e "${CYAN}"
    echo "██████╗  █████╗  ██████╗██╗  ██╗██╗  ██╗ █████╗ ██╗   ██╗██╗     "
    echo "██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║  ██║██╔══██╗██║   ██║██║     "
    echo "██████╔╝███████║██║     █████╔╝ ███████║███████║██║   ██║██║     "
    echo "██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══██║██╔══██║██║   ██║██║     "
    echo "██████╔╝██║  ██║╚██████╗██║  ██╗██║  ██║██║  ██║╚██████╔╝███████╗"
    echo "╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
    echo -e "${NC}"
    echo -e "${BLUE}Lightning-fast reverse tunneling solution${NC}"
    echo ""
}

# Configuration paths
CONFIG_DIR="/etc/backhaul"
BINARY_PATH="/usr/local/bin/backhaul"
SYSTEMD_PATH="/etc/systemd/system"
LOG_DIR="/var/log/backhaul"

# Create necessary directories
create_directories() {
    sudo mkdir -p "$CONFIG_DIR"
    sudo mkdir -p "$LOG_DIR"
}

# Check if backhaul is installed
check_installation() {
    if [ ! -f "$BINARY_PATH" ]; then
        echo -e "${RED}Backhaul binary not found at $BINARY_PATH${NC}"
        echo -e "${YELLOW}Please install Backhaul first${NC}"
        return 1
    fi
    return 0
}

# Get system information
get_system_info() {
    local ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
    local location=$(curl -s "https://ipapi.co/$ip/city/" 2>/dev/null || echo "Unknown")
    local datacenter=$(curl -s "https://ipapi.co/$ip/org/" 2>/dev/null || echo "Unknown")
    
    echo -e "${GREEN}Script Version:${NC} v0.6.0"
    echo -e "${GREEN}Core Version:${NC} v1.1.2"
    echo -e "${GREEN}Telegram Channel:${NC} @Gozar_Xray"
    echo ""
    echo -e "${BLUE}IP Address:${NC} $ip"
    echo -e "${BLUE}Location:${NC} $location"
    echo -e "${BLUE}Datacenter:${NC} $datacenter"
    echo -e "${BLUE}Backhaul Core:${NC} Installed"
    echo ""
}

# Main menu
show_menu() {
    clear
    print_logo
    get_system_info
    
    echo -e "${CYAN}1.${NC} Configure a new tunnel [IPv4/IPv6]"
    echo -e "${RED}2.${NC} Tunnel management menu"
    echo -e "${BLUE}3.${NC} Check tunnels status"
    echo -e "${GREEN}4.${NC} Optimize network & system limits"
    echo -e "${GREEN}5.${NC} Update & Install Backhaul Core"
    echo -e "${GREEN}6.${NC} Update & Install script"
    echo -e "${RED}7.${NC} Remove Backhaul Core"
    echo -e "${YELLOW}0.${NC} Exit"
    echo ""
    echo "------------------------------------"
    echo -n -e "${GREEN}Enter your choice [0-7]:${NC} "
}

# Configure new tunnel
configure_tunnel() {
    clear
    echo -e "${CYAN}--- Configuring NEW tunnel ---${NC}"
    
    # Get server type
    echo -e "${YELLOW}Select server type:${NC}"
    echo "1. IRAN server (Kharej client)"
    echo "2. KHAREJ server (Iran client)"
    echo -n "Enter choice [1-2]: "
    read server_type
    
    if [ "$server_type" == "1" ]; then
        configure_iran_server
    elif [ "$server_type" == "2" ]; then
        configure_kharej_server
    else
        echo -e "${RED}Invalid choice!${NC}"
        sleep 2
        return
    fi
}

# Configure Iran server
configure_iran_server() {
    clear
    echo -e "${CYAN}--- Configuring IRAN server ---${NC}"
    
    # Get tunnel port
    echo -n -e "${GREEN}[+] Tunnel port:${NC} "
    read tunnel_port
    
    # Get transport type
    echo -e "${GREEN}[+] Transport type:${NC}"
    echo "Available: tcp/tcpmux/utcpmux/ws/wsmux/uwsmux/udp/tcptun/faketcp/tcptun"
    echo -n "Enter transport type: "
    read transport_type
    
    # UDP over TCP
    echo -n -e "${YELLOW}[-] Accept UDP connections over TCP transport (true/false) (default false):${NC} "
    read accept_udp
    accept_udp=${accept_udp:-false}
    
    # Channel Size
    echo -n -e "${YELLOW}[-] Channel Size (default 2048):${NC} "
    read channel_size
    channel_size=${channel_size:-2048}
    
    # TCP_NODELAY
    echo -n -e "${YELLOW}[-] Enable TCP_NODELAY (true/false) (default true):${NC} "
    read tcp_nodelay
    tcp_nodelay=${tcp_nodelay:-true}
    
    # Heartbeat
    echo -n -e "${YELLOW}[-] Heartbeat (in seconds, default 40):${NC} "
    read heartbeat
    heartbeat=${heartbeat:-40}
    
    # Security Token
    echo -n -e "${YELLOW}[-] Security Token (press enter to use default value):${NC} "
    read security_token
    if [ -z "$security_token" ]; then
        security_token="YouSef$(date +%s)$(shuf -i 1000-9999 -n 1)"
    fi
    
    # Sniffer
    echo -n -e "${YELLOW}[-] Enable Sniffer (true/false) (default false):${NC} "
    read enable_sniffer
    enable_sniffer=${enable_sniffer:-false}
    
    # Web Port
    echo -n -e "${YELLOW}[-] Enter Web Port (default 0 to disable):${NC} "
    read web_port
    web_port=${web_port:-0}
    
    # Check if port is in use
    if [ "$web_port" != "0" ] && netstat -tulpn | grep ":$web_port " > /dev/null; then
        echo -e "${RED}Port $web_port is already in use. Please choose a different port.${NC}"
        echo -n -e "${YELLOW}[-] Enter Web Port (default 0 to disable):${NC} "
        read web_port
        web_port=${web_port:-0}
    fi
    
    # Proxy Protocol
    echo -n -e "${YELLOW}[-] Enable Proxy Protocol (true/false) (default false):${NC} "
    read proxy_protocol
    proxy_protocol=${proxy_protocol:-false}
    
    # Port configuration
    echo -e "${GREEN}[+] Supported Port Formats:${NC}"
    echo "1. 443-600                    - Listen on all ports in the range 443 to 600."
    echo "2. 443-600:5201               - Listen on all ports in the range 443 to 600 and forward traffic to 5201."
    echo "3. 443-600-1.1.1.1:5201       - Listen on all ports in the range 443 to 600 and forward traffic to 1.1.1.1:5201."
    echo "4. 443                        - Listen on local port 443 and forward to remote port 443 (default forwarding)."
    echo "5. 4000=5000                  - Listen on local port 4000 (bind to all local IPs) and forward to remote port 5000."
    echo "6. 127.0.0.2:443=5201         - Bind to specific local IP (127.0.0.2), listen on port 443, and forward to remote port 5201."
    echo "7. 443=1.1.1.1:5201           - Listen on local port 443 and forward to a specific remote IP (1.1.1.1) on port 5201."
    echo ""
    echo -n -e "${GREEN}[+] Enter your ports in the specified formats (separated by commas):${NC} "
    read port_config
    
    # Create server configuration
    create_server_config "$tunnel_port" "$transport_type" "$accept_udp" "$channel_size" "$tcp_nodelay" "$heartbeat" "$security_token" "$enable_sniffer" "$web_port" "$proxy_protocol" "$port_config"
    
    # Ask to start service
    echo ""
    echo -e "${GREEN}Configuration created successfully!${NC}"
    echo -n "Do you want to start the tunnel now? (y/n): "
    read start_now
    if [ "$start_now" == "y" ] || [ "$start_now" == "Y" ]; then
        start_tunnel_service "server"
    fi
}

# Configure Kharej server
configure_kharej_server() {
    clear
    echo -e "${CYAN}--- Configuring KHAREJ client: iran ---${NC}"
    
    # Get remote server details
    echo -n -e "${GREEN}[+] Remote server address (IP:PORT):${NC} "
    read remote_server
    
    # Get transport type
    echo -e "${GREEN}[+] Transport type (must match server):${NC}"
    echo "Available: tcp/tcpmux/utcpmux/ws/wsmux/uwsmux/udp/tcptun/faketcp/tcptun"
    echo -n "Enter transport type: "
    read transport_type
    
    # Security Token
    echo -n -e "${GREEN}[+] Security Token (must match server):${NC} "
    read security_token
    
    # Connection retry
    echo -n -e "${YELLOW}[-] Connection retry interval (seconds, default 3):${NC} "
    read retry_interval
    retry_interval=${retry_interval:-3}
    
    # Heartbeat
    echo -n -e "${YELLOW}[-] Heartbeat (in seconds, default 40):${NC} "
    read heartbeat
    heartbeat=${heartbeat:-40}
    
    # Channel Size
    echo -n -e "${YELLOW}[-] Channel Size (default 2048):${NC} "
    read channel_size
    channel_size=${channel_size:-2048}
    
    # Create client configuration
    create_client_config "$remote_server" "$transport_type" "$security_token" "$retry_interval" "$heartbeat" "$channel_size"
    
    # Ask to start service
    echo ""
    echo -e "${GREEN}Configuration created successfully!${NC}"
    echo -n "Do you want to start the tunnel now? (y/n): "
    read start_now
    if [ "$start_now" == "y" ] || [ "$start_now" == "Y" ]; then
        start_tunnel_service "client"
    fi
}

# Create server configuration file
create_server_config() {
    local tunnel_port=$1
    local transport_type=$2
    local accept_udp=$3
    local channel_size=$4
    local tcp_nodelay=$5
    local heartbeat=$6
    local security_token=$7
    local enable_sniffer=$8
    local web_port=$9
    local proxy_protocol=${10}
    local port_config=${11}
    
    local config_file="$CONFIG_DIR/server_config.toml"
    
    cat > "$config_file" << EOF
[server]
bind_addr = "0.0.0.0:$tunnel_port"
transport = "$transport_type"
token = "$security_token"
channel_size = $channel_size
tcp_nodelay = $tcp_nodelay
tcp_fast_open = false
tcp_no_delay = $tcp_nodelay
heartbeat = $heartbeat
accept_udp = $accept_udp

[server.tls]
cert = ""
key = ""

EOF

    if [ "$web_port" != "0" ]; then
        cat >> "$config_file" << EOF
[web]
bind_addr = "0.0.0.0:$web_port"
username = "admin"
password = "admin"

EOF
    fi

    if [ "$enable_sniffer" == "true" ]; then
        cat >> "$config_file" << EOF
[sniffer]
enabled = true
interface = "any"

EOF
    fi

    # Add port forwarding rules
    if [ ! -z "$port_config" ]; then
        echo "" >> "$config_file"
        echo "# Port forwarding rules" >> "$config_file"
        echo "# Format: $port_config" >> "$config_file"
    fi
    
    echo -e "${GREEN}Server configuration saved to: $config_file${NC}"
}

# Create client configuration file
create_client_config() {
    local remote_server=$1
    local transport_type=$2
    local security_token=$3
    local retry_interval=$4
    local heartbeat=$5
    local channel_size=$6
    
    local config_file="$CONFIG_DIR/client_config.toml"
    
    cat > "$config_file" << EOF
[client]
remote_addr = "$remote_server"
transport = "$transport_type"
token = "$security_token"
retry_interval = $retry_interval
heartbeat = $heartbeat
channel_size = $channel_size
tcp_nodelay = true
tcp_fast_open = false

[client.tls]
sni = ""
insecure = false

EOF
    
    echo -e "${GREEN}Client configuration saved to: $config_file${NC}"
}

# Create systemd service
create_systemd_service() {
    local service_type=$1
    local config_file=$2
    local service_name="backhaul-$service_type"
    
    cat > "$SYSTEMD_PATH/$service_name.service" << EOF
[Unit]
Description=Backhaul $service_type
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$BINARY_PATH -c $config_file
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=backhaul-$service_type

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    echo -e "${GREEN}Systemd service created: $service_name${NC}"
}

# Start tunnel service
start_tunnel_service() {
    local service_type=$1
    local config_file=""
    local service_name="backhaul-$service_type"
    
    if [ "$service_type" == "server" ]; then
        config_file="$CONFIG_DIR/server_config.toml"
    else
        config_file="$CONFIG_DIR/client_config.toml"
    fi
    
    create_systemd_service "$service_type" "$config_file"
    
    sudo systemctl start "$service_name"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Tunnel service started successfully!${NC}"
        echo -e "${BLUE}Service name: $service_name${NC}"
        echo -e "${BLUE}Config file: $config_file${NC}"
        echo -e "${BLUE}Log file: $LOG_DIR/$service_type.log${NC}"
    else
        echo -e "${RED}Failed to start tunnel service!${NC}"
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Tunnel management menu
tunnel_management() {
    while true; do
        clear
        echo -e "${CYAN}=== Tunnel Management Menu ===${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} Start tunnel service"
        echo -e "${RED}2.${NC} Stop tunnel service"
        echo -e "${YELLOW}3.${NC} Restart tunnel service"
        echo -e "${BLUE}4.${NC} View tunnel status"
        echo -e "${BLUE}5.${NC} View tunnel logs"
        echo -e "${CYAN}6.${NC} Edit configuration"
        echo -e "${RED}7.${NC} Remove tunnel"
        echo -e "${YELLOW}0.${NC} Back to main menu"
        echo ""
        echo -n -e "${GREEN}Enter your choice [0-7]:${NC} "
        read choice
        
        case $choice in
            1) manage_service "start" ;;
            2) manage_service "stop" ;;
            3) manage_service "restart" ;;
            4) show_service_status ;;
            5) show_service_logs ;;
            6) edit_configuration ;;
            7) remove_tunnel ;;
            0) break ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 2 ;;
        esac
    done
}

# Manage service
manage_service() {
    local action=$1
    echo ""
    echo -e "${YELLOW}Select service to $action:${NC}"
    echo "1. Server service"
    echo "2. Client service"
    echo -n "Enter choice [1-2]: "
    read service_choice
    
    local service_name=""
    case $service_choice in
        1) service_name="backhaul-server" ;;
        2) service_name="backhaul-client" ;;
        *) echo -e "${RED}Invalid choice!${NC}"; sleep 2; return ;;
    esac
    
    sudo systemctl $action $service_name
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Service $service_name ${action}ed successfully!${NC}"
    else
        echo -e "${RED}Failed to $action service $service_name!${NC}"
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Show service status
show_service_status() {
    clear
    echo -e "${CYAN}=== Tunnel Services Status ===${NC}"
    echo ""
    
    # Check server service
    if systemctl is-active --quiet backhaul-server; then
        echo -e "${GREEN}Server Service: Active${NC}"
    else
        echo -e "${RED}Server Service: Inactive${NC}"
    fi
    
    # Check client service
    if systemctl is-active --quiet backhaul-client; then
        echo -e "${GREEN}Client Service: Active${NC}"
    else
        echo -e "${RED}Client Service: Inactive${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Detailed Status:${NC}"
    systemctl status backhaul-server --no-pager -l 2>/dev/null || echo "Server service not found"
    echo ""
    systemctl status backhaul-client --no-pager -l 2>/dev/null || echo "Client service not found"
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Show service logs
show_service_logs() {
    echo ""
    echo -e "${YELLOW}Select service to view logs:${NC}"
    echo "1. Server service"
    echo "2. Client service"
    echo -n "Enter choice [1-2]: "
    read service_choice
    
    local service_name=""
    case $service_choice in
        1) service_name="backhaul-server" ;;
        2) service_name="backhaul-client" ;;
        *) echo -e "${RED}Invalid choice!${NC}"; sleep 2; return ;;
    esac
    
    clear
    echo -e "${CYAN}=== $service_name Logs ===${NC}"
    echo ""
    journalctl -u $service_name -f --no-pager
}

# Edit configuration
edit_configuration() {
    echo ""
    echo -e "${YELLOW}Select configuration to edit:${NC}"
    echo "1. Server configuration"
    echo "2. Client configuration"
    echo -n "Enter choice [1-2]: "
    read config_choice
    
    local config_file=""
    case $config_choice in
        1) config_file="$CONFIG_DIR/server_config.toml" ;;
        2) config_file="$CONFIG_DIR/client_config.toml" ;;
        *) echo -e "${RED}Invalid choice!${NC}"; sleep 2; return ;;
    esac
    
    if [ -f "$config_file" ]; then
        ${EDITOR:-nano} "$config_file"
        echo -e "${GREEN}Configuration updated!${NC}"
        echo -e "${YELLOW}Remember to restart the service to apply changes${NC}"
    else
        echo -e "${RED}Configuration file not found: $config_file${NC}"
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Remove tunnel
remove_tunnel() {
    echo ""
    echo -e "${RED}WARNING: This will remove all tunnel configurations and services!${NC}"
    echo -n "Are you sure? (y/N): "
    read confirm
    
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        # Stop and disable services
        sudo systemctl stop backhaul-server 2>/dev/null
        sudo systemctl stop backhaul-client 2>/dev/null
        sudo systemctl disable backhaul-server 2>/dev/null
        sudo systemctl disable backhaul-client 2>/dev/null
        
        # Remove service files
        sudo rm -f "$SYSTEMD_PATH/backhaul-server.service"
        sudo rm -f "$SYSTEMD_PATH/backhaul-client.service"
        
        # Remove configuration files
        sudo rm -rf "$CONFIG_DIR"
        
        # Reload systemd
        sudo systemctl daemon-reload
        
        echo -e "${GREEN}All tunnels removed successfully!${NC}"
    else
        echo -e "${YELLOW}Operation cancelled${NC}"
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Check tunnels status
check_tunnels_status() {
    clear
    echo -e "${CYAN}=== Tunnels Status Check ===${NC}"
    echo ""
    
    # Check if services exist and their status
    if systemctl list-unit-files | grep -q "backhaul-server"; then
        echo -e "${BLUE}Server Tunnel:${NC}"
        if systemctl is-active --quiet backhaul-server; then
            echo -e "  Status: ${GREEN}Running${NC}"
            echo -e "  Uptime: $(systemctl show backhaul-server --property=ActiveEnterTimestamp --value)"
        else
            echo -e "  Status: ${RED}Stopped${NC}"
        fi
        
        if [ -f "$CONFIG_DIR/server_config.toml" ]; then
            local port=$(grep "bind_addr" "$CONFIG_DIR/server_config.toml" | cut -d'"' -f2 | cut -d':' -f2)
            local transport=$(grep "transport" "$CONFIG_DIR/server_config.toml" | cut -d'"' -f2)
            echo -e "  Port: $port"
            echo -e "  Transport: $transport"
        fi
    else
        echo -e "${YELLOW}Server Tunnel: Not configured${NC}"
    fi
    
    echo ""
    
    if systemctl list-unit-files | grep -q "backhaul-client"; then
        echo -e "${BLUE}Client Tunnel:${NC}"
        if systemctl is-active --quiet backhaul-client; then
            echo -e "  Status: ${GREEN}Running${NC}"
            echo -e "  Uptime: $(systemctl show backhaul-client --property=ActiveEnterTimestamp --value)"
        else
            echo -e "  Status: ${RED}Stopped${NC}"
        fi
        
        if [ -f "$CONFIG_DIR/client_config.toml" ]; then
            local remote=$(grep "remote_addr" "$CONFIG_DIR/client_config.toml" | cut -d'"' -f2)
            local transport=$(grep "transport" "$CONFIG_DIR/client_config.toml" | cut -d'"' -f2)
            echo -e "  Remote: $remote"
            echo -e "  Transport: $transport"
        fi
    else
        echo -e "${YELLOW}Client Tunnel: Not configured${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Network Connections:${NC}"
    netstat -tulpn | grep backhaul || echo "No active connections found"
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# System optimization
optimize_system() {
    clear
    echo -e "${CYAN}=== System Optimization ===${NC}"
    echo ""
    echo -e "${YELLOW}This will optimize your system for high-performance tunneling${NC}"
    echo -n "Continue? (y/N): "
    read confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        return
    fi
    
    echo -e "${BLUE}Optimizing system limits...${NC}"
    
    # Backup original limits
    sudo cp /etc/security/limits.conf /etc/security/limits.conf.backup
    
    # Set new limits
    cat << EOF | sudo tee -a /etc/security/limits.conf > /dev/null
# Backhaul optimization
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 1048576
root hard nproc 1048576
EOF
    
    # Optimize sysctl
    sudo cp /etc/sysctl.conf /etc/sysctl.conf.backup
    
    cat << EOF | sudo tee -a /etc/sysctl.conf > /dev/null
# Backhaul network optimization
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
fs.file-max = 1048576
EOF
    
    # Apply sysctl changes
    sudo sysctl -p
    
    echo -e "${GREEN}System optimization completed!${NC}"
    echo -e "${YELLOW}Please reboot your system to apply all changes${NC}"
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Update/Install Backhaul
update_backhaul() {
    clear
    echo -e "${CYAN}=== Update/Install Backhaul Core ===${NC}"
    echo ""
    
    # Download latest release
    echo -e "${BLUE}Downloading latest Backhaul release...${NC}"
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH_SUFFIX="amd64" ;;
        aarch64) ARCH_SUFFIX="arm64" ;;
        armv7l) ARCH_SUFFIX="arm" ;;
        *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; return ;;
    esac
    
    # Get download URL
    DOWNLOAD_URL="https://github.com/musixal/backhaul/releases/latest/download/backhaul-linux-$ARCH_SUFFIX"
    
    # Download and install
    sudo wget -O "$BINARY_PATH" "$DOWNLOAD_URL"
    if [ $? -eq 0 ]; then
        sudo chmod +x "$BINARY_PATH"
        echo -e "${GREEN}Backhaul installed successfully!${NC}"
        echo -e "${BLUE}Version: $($BINARY_PATH --version 2>/dev/null || echo 'Unknown')${NC}"
    else
        echo -e "${RED}Failed to download Backhaul!${NC}"
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Update script
update_script() {
    clear
    echo -e "${CYAN}=== Update Script ===${NC}"
    echo ""
    echo -e "${YELLOW}This feature is not implemented yet.${NC}"
    echo -e "${BLUE}Please download the latest version manually.${NC}"
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Remove Backhaul
remove_backhaul() {
    clear
    echo -e "${RED}=== Remove Backhaul Core ===${NC}"
    echo ""
    echo -e "${RED}WARNING: This will remove Backhaul completely!${NC}"
    echo -n "Are you sure? (y/N): "
    read confirm
    
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        # Stop all services
        sudo systemctl stop backhaul-server 2>/dev/null
        sudo systemctl stop backhaul-client 2>/dev/null
        sudo systemctl disable backhaul-server 2>/dev/null
        sudo systemctl disable backhaul-client 2>/dev/null
        
        # Remove files
        sudo rm -f "$BINARY_PATH"
        sudo rm -f "$SYSTEMD_PATH/backhaul-server.service"
        sudo rm -f "$SYSTEMD_PATH/backhaul-client.service"
        sudo rm -rf "$CONFIG_DIR"
        sudo rm -rf "$LOG_DIR"
        
        # Reload systemd
        sudo systemctl daemon-reload
        
        echo
