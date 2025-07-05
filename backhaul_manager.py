#!/usr/bin/env python3

import os
import sys
import subprocess
import json
import time
import shutil
import re
from urllib import request
import random
import string

# ====================================================================
# 🚀 Backhaul Manager v8.0 (Complete MUX Edition) 🚀
# ====================================================================

# --- Global Variables & Constants ---
class C:
    RED, GREEN, YELLOW, CYAN, WHITE, BOLD, RESET = '\033[31m', '\033[32m', '\033[33m', '\033[36m', '\033[37m', '\033[1m', '\033[0m'
    BLUE = '\033[34m'  # رنگ آبی برای سرور خارج

BACKHAUL_DIR, CONFIG_DIR, SERVICE_DIR = "/opt/backhaul", "/etc/backhaul", "/etc/systemd/system"
LOG_DIR, BINARY_PATH, TUNNELS_DIR = "/var/log/backhaul", f"{BACKHAUL_DIR}/backhaul", f"{CONFIG_DIR}/tunnels"

# --- Helper Functions ---
def run_cmd(command, as_root=False, capture=True):
    if as_root: command.insert(0, "sudo")
    if capture: return subprocess.run(command, capture_output=True, text=True, check=False)
    else: return subprocess.run(command)

def clear_screen(): os.system('clear')

def press_key(): input("\nPress Enter to continue...")

def colorize(text, color, bold=False):
    style = C.BOLD if bold else ""
    print(f"{style}{color}{text}{C.RESET}")

def colorize_server_type(tunnel_type, text, bold=False):
    """رنگبندی بر اساس نوع سرور"""
    style = C.BOLD if bold else ""
    if tunnel_type == "Server":
        print(f"{style}{C.GREEN}🇮🇷 {text}{C.RESET}")
    elif tunnel_type == "Client":
        print(f"{style}{C.BLUE}🌍 {text}{C.RESET}")
    else:
        print(f"{style}{C.WHITE}{text}{C.RESET}")

def get_valid_tunnel_name():
    while True:
        tunnel_name = input("Enter a name for this tunnel (e.g., my-tunnel): ")
        if tunnel_name and re.match(r'^[a-zA-Z0-9_-]+$', tunnel_name): return tunnel_name
        else: colorize("Invalid name! Use English letters, numbers, dash (-), and underscore (_).", C.RED)

def get_server_info():
    try:
        with request.urlopen('http://ip-api.com/json/?fields=query,country,isp', timeout=5) as response:
            data = json.loads(response.read().decode())
            return data.get('query', 'N/A'), data.get('country', 'N/A'), data.get('isp', 'N/A')
    except: return "N/A", "N/A", "N/A"

def get_core_version():
    if os.path.exists(BINARY_PATH):
        result = run_cmd([BINARY_PATH, '--version'])
        return result.stdout.strip().split('\n')[0] if result.returncode == 0 and result.stdout else "Unknown"
    return "N/A"

def check_requirements():
    requirements = ['wget', 'tar', 'systemctl', 'openssl', 'jq', 'ss', 'pkill']
    missing = [cmd for cmd in requirements if shutil.which(cmd) is None]
    if missing: colorize(f"Missing required packages: {', '.join(missing)}", C.RED, bold=True); sys.exit(1)

def create_service(tunnel_name):
    service_name = f"backhaul-{tunnel_name}.service"
    service_content = f"""[Unit]
Description=Backhaul Tunnel Service - {tunnel_name}
After=network.target

[Service]
Type=simple
ExecStart={BINARY_PATH} -c {TUNNELS_DIR}/{tunnel_name}.toml
Restart=always
RestartSec=3
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
"""
    service_path = f"{SERVICE_DIR}/{service_name}"
    with open(f"/tmp/{service_name}", "w") as f: f.write(service_content)
    run_cmd(['mv', f'/tmp/{service_name}', service_path], as_root=True)
    run_cmd(['systemctl', 'daemon-reload'], as_root=True)
    run_cmd(['systemctl', 'enable', service_name], as_root=True)

def is_port_in_use(port):
    result = run_cmd(['ss', '-tln'])
    return re.search(r':{}\s'.format(port), result.stdout) is not None

def sanitize_for_print(name):
    return name.encode('ascii', 'ignore').decode('ascii')

def parse_toml_config(config_path):
    """Parse TOML config file to extract tunnel information"""
    tunnel_info = {"type": "Unknown", "addr": "N/A", "ports": []}
    try:
        with open(config_path, 'r') as f:
            content = f.read()
        
        if "[server]" in content:
            tunnel_info["type"] = "Server"
            bind_match = re.search(r'bind_addr\s*=\s*["\']([^"\']+)["\']', content)
            if bind_match:
                tunnel_info["addr"] = bind_match.group(1)
            ports_match = re.search(r'ports\s*=\s*\[(.*?)\]', content, re.DOTALL)
            if ports_match:
                ports_str = ports_match.group(1)
                port_entries = re.findall(r'["\']([^"\']+)["\']', ports_str)
                tunnel_info["ports"] = port_entries[:3]
        
        elif "[client]" in content:
            tunnel_info["type"] = "Client"
            remote_match = re.search(r'remote_addr\s*=\s*["\']([^"\']+)["\']', content)
            if remote_match:
                tunnel_info["addr"] = remote_match.group(1)
    except Exception as e:
        print(f"Error parsing config {config_path}: {e}")
    
    return tunnel_info

def get_service_status(service_name):
    """Get detailed service status"""
    result = run_cmd(['systemctl', 'is-active', service_name])
    if result.returncode == 0 and result.stdout.strip() == "active":
        return f"{C.GREEN}● Active{C.RESET}"
    else:
        return f"{C.RED}● Inactive{C.RESET}"

def get_mux_configuration(transport_type):
    """Get complete MUX configuration based on transport type"""
    colorize(f"\n--- Complete {transport_type.upper()} MUX Configuration ---", C.CYAN, bold=True)
    
    mux_config = {}
    
    if transport_type in ['tcpmux', 'wsmux', 'wssmux']:
        # Core MUX settings
        mux_config['mux_version'] = int(input("Enter mux_version (1-2, default: 2): ") or "2")
        mux_config['mux_framesize'] = int(input("Enter mux_framesize (bytes, default: 65536): ") or "65536")
        mux_config['mux_recievebuffer'] = int(input("Enter mux_recievebuffer (bytes, default: 8388608): ") or "8388608")
        mux_config['mux_streambuffer'] = int(input("Enter mux_streambuffer (bytes, default: 4194304): ") or "4194304")
        
        # Advanced MUX settings
        mux_config['mux_con'] = int(input("Enter mux_con (concurrent connections, default: 16): ") or "16")
        mux_config['mux_bandwidth'] = int(input("Enter mux_bandwidth (Mbps, 0=unlimited, default: 0): ") or "0")
        
        # Session management
        reuse_session = input("Enable mux session reuse? (y/n, default: y): ") or "y"
        mux_config['mux_session_reuse'] = reuse_session.lower() == 'y'
        
        # Buffer optimization
        mux_config['mux_window_size'] = int(input("Enter mux_window_size (default: 262144): ") or "262144")
        mux_config['mux_keepalive'] = int(input("Enter mux_keepalive (seconds, default: 30): ") or "30")
        
        # Flow control
        flow_control = input("Enable mux flow control? (y/n, default: y): ") or "y"
        mux_config['mux_flow_control'] = flow_control.lower() == 'y'
        
        # Compression
        compression = input("Enable mux compression? (y/n, default: n): ") or "n"
        mux_config['mux_compression'] = compression.lower() == 'y'
        
        # Error handling
        mux_config['mux_retry_limit'] = int(input("Enter mux_retry_limit (default: 3): ") or "3")
        mux_config['mux_retry_interval'] = int(input("Enter mux_retry_interval (seconds, default: 1): ") or "1")
        
        # Quality of Service
        qos_enabled = input("Enable mux QoS? (y/n, default: n): ") or "n"
        mux_config['mux_qos'] = qos_enabled.lower() == 'y'
        
        if mux_config['mux_qos']:
            mux_config['mux_priority_levels'] = int(input("Enter mux_priority_levels (1-8, default: 3): ") or "3")
            mux_config['mux_rate_limit'] = int(input("Enter mux_rate_limit (Kbps, 0=unlimited, default: 0): ") or "0")
        
        # UDP over TCP specific settings
        if transport_type == 'tcpmux':
            colorize("\n--- UDP over TCP MUX Settings ---", C.YELLOW)
            udp_support = input("Enable UDP over TCP support? (y/n, default: y): ") or "y"
            mux_config['udp_over_tcp'] = udp_support.lower() == 'y'
            
            if mux_config['udp_over_tcp']:
                mux_config['udp_timeout'] = int(input("Enter udp_timeout (seconds, default: 60): ") or "60")
                mux_config['udp_buffer_size'] = int(input("Enter udp_buffer_size (bytes, default: 65536): ") or "65536")
                mux_config['udp_congestion_control'] = input("Enable UDP congestion control? (y/n, default: y): ") or "y"
                mux_config['udp_congestion_control'] = mux_config['udp_congestion_control'].lower() == 'y'
        
        # WebSocket specific settings
        if transport_type in ['wsmux', 'wssmux']:
            colorize("\n--- WebSocket MUX Settings ---", C.CYAN)
            mux_config['ws_handshake_timeout'] = int(input("Enter ws_handshake_timeout (seconds, default: 10): ") or "10")
            mux_config['ws_ping_interval'] = int(input("Enter ws_ping_interval (seconds, default: 30): ") or "30")
            mux_config['ws_pong_timeout'] = int(input("Enter ws_pong_timeout (seconds, default: 5): ") or "5")
            mux_config['ws_compression'] = input("Enable WebSocket compression? (y/n, default: n): ") or "n"
            mux_config['ws_compression'] = mux_config['ws_compression'].lower() == 'y'
            
            # WebSocket headers
            custom_headers = input("Add custom WebSocket headers? (y/n, default: n): ") or "n"
            if custom_headers.lower() == 'y':
                mux_config['ws_headers'] = {}
                while True:
                    header_name = input("Enter header name (empty to finish): ")
                    if not header_name:
                        break
                    header_value = input(f"Enter value for {header_name}: ")
                    mux_config['ws_headers'][header_name] = header_value
        
        # WSS (WebSocket Secure) specific settings
        if transport_type == 'wssmux':
            colorize("\n--- WSS (Secure WebSocket) MUX Settings ---", C.GREEN)
            mux_config['tls_version'] = input("Enter TLS version (1.2/1.3, default: 1.3): ") or "1.3"
            mux_config['tls_cipher_suites'] = input("Enter TLS cipher suites (default: auto): ") or "auto"
            mux_config['tls_verify_certificate'] = input("Verify TLS certificate? (y/n, default: y): ") or "y"
            mux_config['tls_verify_certificate'] = mux_config['tls_verify_certificate'].lower() == 'y'
            
            # Certificate settings
            cert_path = input("Enter custom certificate path (optional): ")
            if cert_path:
                mux_config['tls_cert_path'] = cert_path
            
            key_path = input("Enter custom private key path (optional): ")
            if key_path:
                mux_config['tls_key_path'] = key_path
    
    return mux_config

def create_server_tunnel():
    clear_screen()
    colorize_server_type("Server", "Create Iran Server Tunnel", bold=True)
    
    tunnel_name = get_valid_tunnel_name()
    
    colorize("\nAvailable transport protocols:", C.CYAN)
    print(" tcp, tcpmux, udp, ws, wss, wsmux, wssmux")
    transport = input("Choose transport protocol (default: tcp): ") or "tcp"
    
    listen_port = input("Enter server listen port (e.g., 3080): ") or "3080"
    bind_addr = f"0.0.0.0:{listen_port}"
    
    token = input("Enter auth token (leave empty to generate): ")
    if not token:
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)
    
    # Basic configuration
    nodelay_input = input("Disable TCP_NODELAY? (y/n, default: n - keeps enabled): ") or "n"
    nodelay = nodelay_input.lower() != 'y'
    
    sniffer_input = input("Enable Sniffer? (y/n, default: n): ") or "n"
    sniffer = sniffer_input.lower() == 'y'
    
    web_port = 0
    if sniffer:
        web_port = int(input("Enter sniffer web port (default: 0): ") or "0")
    
    config_dict = {
        "server": {
            "bind_addr": bind_addr,
            "transport": transport,
            "token": token,
            "nodelay": nodelay,
            "sniffer": sniffer,
            "web_port": web_port,
            "log_level": "info"
        }
    }
    
    # Get MUX configuration if applicable
    if 'mux' in transport:
        mux_config = get_mux_configuration(transport)
        config_dict["server"].update(mux_config)
    
    # Advanced server settings
    colorize("\n--- Advanced Server Configuration ---", C.CYAN)
    config_dict["server"]["keepalive_period"] = int(input("Enter keepalive_period (seconds, default: 30): ") or "30")
    config_dict["server"]["heartbeat"] = int(input("Enter heartbeat (seconds, default: 40): ") or "40")
    config_dict["server"]["channel_size"] = int(input("Enter channel_size (default: 2048): ") or "2048")
    
    # UDP support
    if transport in ['tcp', 'tcpmux']:
        accept_udp_input = input("Accept UDP traffic? (y/n, default: n): ") or "n"
        config_dict["server"]["accept_udp"] = accept_udp_input.lower() == 'y'
    
    # Proxy protocol
    proxy_protocol_input = input("Enable PROXY protocol? (y/n, default: n): ") or "n"
    config_dict["server"]["proxy_protocol"] = proxy_protocol_input.lower() == 'y'
    
    # Network interface settings
    config_dict["server"]["tun_name"] = input("Enter TUN interface name (default: backhaul): ") or "backhaul"
    config_dict["server"]["tun_subnet"] = input("Enter TUN subnet (default: 10.10.10.0/24): ") or "10.10.10.0/24"
    config_dict["server"]["mtu"] = int(input("Enter MTU (default: 1500): ") or "1500")
    
    # TCP buffer settings
    colorize("\n--- TCP Buffer Optimization ---", C.CYAN)
    config_dict["server"]["so_rcvbuf"] = int(input("Enter SO_RCVBUF (bytes, 0=system default): ") or "0")
    config_dict["server"]["so_sndbuf"] = int(input("Enter SO_SNDBUF (bytes, 0=system default): ") or "0")
    
    # Connection limits
    config_dict["server"]["max_connections"] = int(input("Enter max_connections (0=unlimited, default: 1000): ") or "1000")
    config_dict["server"]["connection_timeout"] = int(input("Enter connection_timeout (seconds, default: 300): ") or "300")
    
    # Port forwarding
    ports_str = input("\nEnter forwarding ports (e.g., 443, 8080=8000, 22-25): ")
    valid_ports_list = []
    
    if ports_str:
        raw_ports = [p.strip() for p in ports_str.split(',') if p.strip()]
        for port_entry in raw_ports:
            try:
                # Handle port ranges
                if '-' in port_entry and '=' not in port_entry:
                    start_port, end_port = port_entry.split('-')
                    for port in range(int(start_port), int(end_port) + 1):
                        if not is_port_in_use(port):
                            valid_ports_list.append(str(port))
                            colorize(f"Port {port} is available. Added.", C.GREEN)
                        else:
                            colorize(f"Port {port} is already in use. Skipped.", C.RED)
                else:
                    listen_part = port_entry.split('=')[0]
                    port_to_check_str = listen_part.split(':')[-1]
                    if port_to_check_str.isdigit() and not is_port_in_use(int(port_to_check_str)):
                        colorize(f"Port {port_to_check_str} is available. Added.", C.GREEN)
                        valid_ports_list.append(port_entry)
                    else:
                        colorize(f"Port {port_to_check_str} is already in use or invalid. Skipped.", C.RED)
            except:
                colorize(f"Could not parse '{port_entry}'. Added without validation.", C.YELLOW)
                valid_ports_list.append(port_entry)
    
    config_dict["server"]["ports"] = valid_ports_list
    
    # Generate configuration file
    config_content = ""
    for section, params in config_dict.items():
        config_content += f"[{section}]\n"
        for key, value in params.items():
            if isinstance(value, list):
                config_content += f'{key} = {json.dumps(value)}\n'
            elif isinstance(value, bool):
                config_content += f'{key} = {str(value).lower()}\n'
            elif isinstance(value, dict):
                config_content += f'{key} = {json.dumps(value)}\n'
            else:
                config_content += f'{key} = "{value}"\n' if isinstance(value, str) else f'{key} = {value}\n'
    
    # Save configuration
    with open(f"/tmp/{tunnel_name}.toml", "w") as f:
        f.write(config_content)
    
    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
    
    # Create and start service
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    
    colorize(f"\n✅ Tunnel '{tunnel_name}' created. Verifying status...", C.GREEN, bold=True)
    time.sleep(3)
    
    service_name = f'backhaul-{tunnel_name}.service'
    status_text = get_service_status(service_name)
    
    colorize(f" Listening Port: {listen_port}", C.WHITE)
    colorize(f" Transport: {transport.upper()}", C.WHITE)
    colorize(f" TCP_NODELAY: {'Enabled' if nodelay else 'Disabled'}", C.WHITE)
    print(f" Status: {status_text}")
    
    if valid_ports_list:
        colorize(f" Forwarded Ports: {', '.join(valid_ports_list[:3])}", C.WHITE)
    
    press_key()

def create_client_tunnel():
    clear_screen()
    colorize_server_type("Client", "Create Kharej Client Tunnel", bold=True)
    
    tunnel_name = get_valid_tunnel_name()
    
    server_ip = input("Enter server IP address (e.g., 1.2.3.4): ")
    if not server_ip:
        colorize("Server IP is required!", C.RED)
        time.sleep(1)
        return
    
    # IP validation
    parts = server_ip.split('.')
    if len(parts) != 4 or not all(part.isdigit() and 0 <= int(part) <= 255 for part in parts):
        colorize("Invalid IP format! Use format like 1.2.3.4", C.RED)
        time.sleep(1)
        return
    
    server_port = input("Enter tunnel port (e.g., 3080): ")
    if not server_port or not server_port.isdigit() or not (1 <= int(server_port) <= 65535):
        colorize("Valid port number is required (1-65535)!", C.RED)
        time.sleep(1)
        return
    
    remote_addr = f"{server_ip}:{server_port}"
    colorize(f"Connecting to: {remote_addr}", C.CYAN)
    
    # Test connection
    test_connection = input("Test connection to server first? (y/n, default: n): ") or "n"
    if test_connection.lower() == 'y':
        colorize("Testing connection...", C.YELLOW)
        result = run_cmd(['nc', '-z', '-v', '-w5', server_ip, server_port])
        if result.returncode == 0:
            colorize("✅ Connection test successful!", C.GREEN)
        else:
            colorize("⚠️ Connection test failed. Continuing anyway...", C.YELLOW)
        time.sleep(2)
    
    # Transport selection
    colorize("\nAvailable transport protocols:", C.CYAN)
    print(" tcp, tcpmux, ws, wss, wsmux, wssmux")
    transport = input("Choose transport protocol (default: tcp): ") or "tcp"
    
    token = input("Enter auth token (must match server): ")
    
    # Edge IP for CDN
    edge_ip = input("Enter edge IP for CDN (optional): ") or ""
    
    # Basic client configuration
    connection_pool = int(input("Enter connection pool size (default: 16): ") or "16")
    
    nodelay_input = input("Disable TCP_NODELAY? (y/n, default: n - keeps enabled): ") or "n"
    nodelay = nodelay_input.lower() != 'y'
    
    sniffer_input = input("Enable Sniffer? (y/n, default: n): ") or "n"
    sniffer = sniffer_input.lower() == 'y'
    
    web_port = 0
    if sniffer:
        web_port = int(input("Enter sniffer web port (default: 0): ") or "0")
    
    config_dict = {
        "client": {
            "remote_addr": remote_addr,
            "transport": transport,
            "token": token,
            "connection_pool": connection_pool,
            "nodelay": nodelay,
            "sniffer": sniffer,
            "web_port": web_port,
            "log_level": "info"
        }
    }
    
    # Add edge IP if provided
    if edge_ip:
        config_dict["client"]["edge_ip"] = edge_ip
    
    # Get MUX configuration if applicable
    if 'mux' in transport:
        mux_config = get_mux_configuration(transport)
        config_dict["client"].update(mux_config)
    
    # Advanced client settings
    colorize("\n--- Advanced Client Configuration ---", C.CYAN)
    config_dict["client"]["keepalive_period"] = int(input("Enter keepalive_period (seconds, default: 30): ") or "30")
    config_dict["client"]["retry_interval"] = int(input("Enter retry_interval (seconds, default: 1): ") or "1")
    config_dict["client"]["dial_timeout"] = int(input("Enter dial_timeout (seconds, default: 30): ") or "30")
    
    # Connection management
    aggressive_pool_input = input("Enable aggressive_pool? (y/n, default: y): ") or "y"
    config_dict["client"]["aggressive_pool"] = aggressive_pool_input.lower() == 'y'
    
    ip_limit_input = input("Enable ip_limit? (y/n, default: n): ") or "n"
    config_dict["client"]["ip_limit"] = ip_limit_input.lower() == 'y'
    
    # Network interface settings
    config_dict["client"]["tun_name"] = input("Enter TUN interface name (default: backhaul): ") or "backhaul"
    config_dict["client"]["tun_subnet"] = input("Enter TUN subnet (default: 10.10.10.0/24): ") or "10.10.10.0/24"
    config_dict["client"]["mtu"] = int(input("Enter MTU (default: 1500): ") or "1500")
    
    # TCP buffer settings
    colorize("\n--- TCP Buffer Optimization ---", C.CYAN)
    config_dict["client"]["so_rcvbuf"] = int(input("Enter SO_RCVBUF (bytes, 0=system default): ") or "0")
    config_dict["client"]["so_sndbuf"] = int(input("Enter SO_SNDBUF (bytes, 0=system default): ") or "0")
    
    # Performance tuning
    config_dict["client"]["workers"] = int(input("Enter number of workers (0=auto, default: 0): ") or "0")
    config_dict["client"]["channel_size"] = int(input("Enter channel_size (default: 2048): ") or "2048")
    
    # WebSocket specific settings for client
    if transport in ['ws', 'wss', 'wsmux', 'wssmux']:
        colorize("\n--- WebSocket Client Settings ---", C.CYAN)
        config_dict["client"]["ws_path"] = input("Enter WebSocket path (default: /): ") or "/"
        config_dict["client"]["ws_host"] = input("Enter WebSocket host header (optional): ") or ""
        
        # Random settings
        random_ua = input("Use random User-Agent? (y/n, default: y): ") or "y"
        config_dict["client"]["random_user_agent"] = random_ua.lower() == 'y'
        
        random_path = input("Use random tunnel path? (y/n, default: n): ") or "n"
        config_dict["client"]["random_tunnel_path"] = random_path.lower() == 'y'
    
    # Generate configuration file
    config_content = ""
    for section, params in config_dict.items():
        config_content += f"[{section}]\n"
        for key, value in params.items():
            if isinstance(value, bool):
                config_content += f'{key} = {str(value).lower()}\n'
            elif isinstance(value, dict):
                config_content += f'{key} = {json.dumps(value)}\n'
            elif isinstance(value, str):
                config_content += f'{key} = "{value}"\n'
            else:
                config_content += f'{key} = {value}\n'
    
    # Save configuration
    with open(f"/tmp/{tunnel_name}.toml", "w") as f:
        f.write(config_content)
    
    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
    
    # Create and start service
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    
    colorize(f"\n✅ Tunnel '{tunnel_name}' created. Verifying status...", C.GREEN, bold=True)
    time.sleep(3)
    
    service_name = f'backhaul-{tunnel_name}.service'
    status_text = get_service_status(service_name)
    
    colorize(f" Connecting to Port: {server_port}", C.WHITE)
    colorize(f" Transport: {transport.upper()}", C.WHITE)
    colorize(f" TCP_NODELAY: {'Enabled' if nodelay else 'Disabled'}", C.WHITE)
    print(f" Status: {status_text}")
    
    if edge_ip:
        colorize(f" Edge IP: {edge_ip}", C.WHITE)
    
    press_key()

def create_optimized_tunnel():
    clear_screen()
    colorize("--- High-Performance Tunnel Presets ---", C.CYAN, bold=True)
    
    print("1) High-Performance Server (Iran) - 800+ Users")
    print("2) High-Performance Client (Kharej) - 800+ Users")
    print("3) Gaming Optimized (Low Latency)")
    print("4) Streaming Optimized (High Bandwidth)")
    print("5) CDN Optimized (Edge Performance)")
    print("0) Back to main menu")
    
    choice = input("\nSelect preset: ")
    
    if choice == '1':
        create_high_performance_server()
    elif choice == '2':
        create_high_performance_client()
    elif choice == '3':
        create_gaming_optimized()
    elif choice == '4':
        create_streaming_optimized()
    elif choice == '5':
        create_cdn_optimized()
    elif choice == '0':
        return
    else:
        colorize("Invalid choice.", C.RED)
        time.sleep(1)

def create_high_performance_server():
    clear_screen()
    colorize_server_type("Server", "Create High-Performance Iran Server (800+ Users)", bold=True)
    
    tunnel_name = get_valid_tunnel_name()
    listen_port = input("Enter server listen port (default: 3080): ") or "3080"
    
    token = input("Enter auth token (leave empty to generate): ")
    if not token:
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
        colorize(f"🔑 Generated strong token: {token}", C.YELLOW)
    
    # High-performance preset configuration
    config_dict = {
        "server": {
            "bind_addr": f"0.0.0.0:{listen_port}",
            "transport": "wssmux",
            "token": token,
            "nodelay": True,
            "sniffer": False,
            "web_port": 2060,
            "log_level": "info",
            
            # High-performance MUX settings
            "mux_version": 2,
            "mux_framesize": 131072,  # 128KB
            "mux_recievebuffer": 16777216,  # 16MB
            "mux_streambuffer": 8388608,  # 8MB
            "mux_con": 32,
            "mux_session_reuse": True,
            "mux_flow_control": True,
            "mux_window_size": 524288,  # 512KB
            "mux_keepalive": 20,
            
            # Server optimization
            "keepalive_period": 20,
            "heartbeat": 30,
            "channel_size": 4096,
            "accept_udp": True,
            "proxy_protocol": True,
            
            # Network settings
            "tun_name": "backhaul-hp",
            "tun_subnet": "10.10.10.0/24",
            "mtu": 1500,
            
            # Buffer optimization
            "so_rcvbuf": 16777216,  # 16MB
            "so_sndbuf": 16777216,  # 16MB
            
            # Connection management
            "max_connections": 2000,
            "connection_timeout": 600,
            
            # WebSocket settings
            "ws_ping_interval": 20,
            "ws_pong_timeout": 10,
            "ws_compression": False,
            
            # TLS optimization
            "tls_version": "1.3",
            "tls_cipher_suites": "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256"
        }
    }
    
    # Port forwarding
    ports_str = input("Enter forwarding ports (e.g., 80,443,8080): ") or "80,443,8080"
    if ports_str:
        ports_list = [p.strip() for p in ports_str.split(',')]
        config_dict["server"]["ports"] = ports_list
    
    # Generate and save configuration
    config_content = generate_config_content(config_dict)
    save_and_start_tunnel(tunnel_name, config_content)
    
    colorize(f"\n✅ High-Performance Server '{tunnel_name}' created!", C.GREEN, bold=True)
    colorize("\n🚀 Optimizations Applied:", C.CYAN, bold=True)
    colorize("  ⚡ Transport: WSS MUX (Secure WebSocket Multiplexing)", C.WHITE)
    colorize("  ⚡ Frame Size: 128KB (4x default)", C.WHITE)
    colorize("  ⚡ Buffer Size: 16MB RX/TX", C.WHITE)
    colorize("  ⚡ Max Connections: 2000", C.WHITE)
    colorize("  ⚡ MUX Connections: 32", C.WHITE)
    colorize("  ⚡ TLS 1.3 with optimized cipher suites", C.WHITE)
    colorize("  ⚡ Session reuse and flow control enabled", C.WHITE)
    
    press_key()

def create_high_performance_client():
    clear_screen()
    colorize_server_type("Client", "Create High-Performance Kharej Client (800+ Users)", bold=True)
    
    tunnel_name = get_valid_tunnel_name()
    server_ip = input("Enter server IP address: ")
    server_port = input("Enter server port (default: 3080): ") or "3080"
    token = input("Enter auth token (must match server): ")
    edge_ip = input("Enter edge IP for CDN (optional): ") or ""
    
    # High-performance preset configuration
    config_dict = {
        "client": {
            "remote_addr": f"{server_ip}:{server_port}",
            "transport": "wssmux",
            "token": token,
            "connection_pool": 64,
            "nodelay": True,
            "sniffer": False,
            "web_port": 2060,
            "log_level": "info",
            
            # High-performance MUX settings
            "mux_version": 2,
            "mux_framesize": 131072,  # 128KB
            "mux_recievebuffer": 16777216,  # 16MB
            "mux_streambuffer": 8388608,  # 8MB
            "mux_session_reuse": True,
            "mux_flow_control": True,
            "mux_window_size": 524288,  # 512KB
            "mux_keepalive": 20,
            
            # Client optimization
            "keepalive_period": 20,
            "retry_interval": 1,
            "dial_timeout": 30,
            "aggressive_pool": True,
            "ip_limit": True,
            
            # Network settings
            "tun_name": "backhaul-hp",
            "tun_subnet": "10.10.10.0/24",
            "mtu": 1500,
            
            # Buffer optimization
            "so_rcvbuf": 16777216,  # 16MB
            "so_sndbuf": 16777216,  # 16MB
            
            # Performance tuning
            "workers": 0,  # Auto-detect
            "channel_size": 4096,
            
            # WebSocket settings
            "ws_path": "/",
            "random_user_agent": True,
            "random_tunnel_path": True,
            "ws_ping_interval": 20,
            "ws_pong_timeout": 10,
            "ws_compression": False,
            
            # TLS optimization
            "tls_version": "1.3",
            "tls_verify_certificate": True
        }
    }
    
    # Add edge IP if provided
    if edge_ip:
        config_dict["client"]["edge_ip"] = edge_ip
    
    # Generate and save configuration
    config_content = generate_config_content(config_dict)
    save_and_start_tunnel(tunnel_name, config_content)
    
    colorize(f"\n✅ High-Performance Client '{tunnel_name}' created!", C.GREEN, bold=True)
    colorize("\n🚀 Optimizations Applied:", C.CYAN, bold=True)
    colorize("  ⚡ Transport: WSS MUX (Secure WebSocket Multiplexing)", C.WHITE)
    colorize("  ⚡ Connection Pool: 64 connections", C.WHITE)
    colorize("  ⚡ Frame Size: 128KB (4x default)", C.WHITE)
    colorize("  ⚡ Buffer Size: 16MB RX/TX", C.WHITE)
    colorize("  ⚡ Aggressive pool management enabled", C.WHITE)
    colorize("  ⚡ Random User-Agent and path enabled", C.WHITE)
    if edge_ip:
        colorize(f"  ⚡ Edge IP: {edge_ip} (CDN optimized)", C.WHITE)
    
    press_key()

def create_gaming_optimized():
    clear_screen()
    colorize("--- Gaming Optimized Tunnel ---", C.CYAN, bold=True)
    
    tunnel_type = input("Server (s) or Client (c)? ").lower()
    tunnel_name = get_valid_tunnel_name()
    
    if tunnel_type == 's':
        listen_port = input("Enter server listen port (default: 3080): ") or "3080"
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)
        
        config_dict = {
            "server": {
                "bind_addr": f"0.0.0.0:{listen_port}",
                "transport": "tcpmux",
                "token": token,
                "nodelay": True,
                "sniffer": False,
                "web_port": 2060,
                "log_level": "info",
                
                # Gaming-optimized MUX settings
                "mux_version": 2,
                "mux_framesize": 16384,  # Smaller frames for lower latency
                "mux_recievebuffer": 2097152,  # 2MB
                "mux_streambuffer": 1048576,  # 1MB
                "mux_con": 8,
                "mux_keepalive": 10,  # Aggressive keepalive
                "mux_flow_control": True,
                "mux_window_size": 65536,  # 64KB
                
                # Low latency settings
                "keepalive_period": 10,
                "heartbeat": 15,
                "channel_size": 1024,
                "accept_udp": True,
                
                # Network settings
                "tun_name": "backhaul-gaming",
                "tun_subnet": "10.10.10.0/24",
                "mtu": 1500,
                
                # Buffer optimization for low latency
                "so_rcvbuf": 2097152,  # 2MB
                "so_sndbuf": 2097152,  # 2MB
                
                # Connection management
                "max_connections": 500,
                "connection_timeout": 60,
                
                # UDP optimization
                "udp_over_tcp": True,
                "udp_timeout": 30,
                "udp_buffer_size": 32768,
                "udp_congestion_control": True
            }
        }
        
        # Gaming ports
        gaming_ports = input("Enter gaming ports (default: 7777,7778,27015): ") or "7777,7778,27015"
        config_dict["server"]["ports"] = [p.strip() for p in gaming_ports.split(',')]
        
    else:  # Client
        server_ip = input("Enter server IP address: ")
        server_port = input("Enter server port (default: 3080): ") or "3080"
        token = input("Enter auth token: ")
        
        config_dict = {
            "client": {
                "remote_addr": f"{server_ip}:{server_port}",
                "transport": "tcpmux",
                "token": token,
                "connection_pool": 8,
                "nodelay": True,
                "sniffer": False,
                "web_port": 2060,
                "log_level": "info",
                
                # Gaming-optimized MUX settings
                "mux_version": 2,
                "mux_framesize": 16384,  # Smaller frames for lower latency
                "mux_recievebuffer": 2097152,  # 2MB
                "mux_streambuffer": 1048576,  # 1MB
                "mux_keepalive": 10,  # Aggressive keepalive
                "mux_flow_control": True,
                "mux_window_size": 65536,  # 64KB
                
                # Low latency settings
                "keepalive_period": 10,
                "retry_interval": 1,
                "dial_timeout": 10,
                "aggressive_pool": True,
                
                # Network settings
                "tun_name": "backhaul-gaming",
                "tun_subnet": "10.10.10.0/24",
                "mtu": 1500,
                
                # Buffer optimization for low latency
                "so_rcvbuf": 2097152,  # 2MB
                "so_sndbuf": 2097152,  # 2MB
                
                # Performance tuning
                "workers": 4,
                "channel_size": 1024,
                
                # UDP optimization
                "udp_over_tcp": True,
                "udp_timeout": 30,
                "udp_buffer_size": 32768,
                "udp_congestion_control": True
            }
        }
    
    # Generate and save configuration
    config_content = generate_config_content(config_dict)
    save_and_start_tunnel(tunnel_name, config_content)
    
    colorize(f"\n✅ Gaming Optimized Tunnel '{tunnel_name}' created!", C.GREEN, bold=True)
    colorize("\n🎮 Gaming Optimizations Applied:", C.CYAN, bold=True)
    colorize("  ⚡ Transport: TCP MUX (Low latency multiplexing)", C.WHITE)
    colorize("  ⚡ Small frame size: 16KB (reduced latency)", C.WHITE)
    colorize("  ⚡ Aggressive keepalive: 10 seconds", C.WHITE)
    colorize("  ⚡ UDP over TCP with congestion control", C.WHITE)
    colorize("  ⚡ Optimized buffer sizes for gaming", C.WHITE)
    
    press_key()

def create_streaming_optimized():
    clear_screen()
    colorize("--- Streaming Optimized Tunnel ---", C.CYAN, bold=True)
    
    tunnel_type = input("Server (s) or Client (c)? ").lower()
    tunnel_name = get_valid_tunnel_name()
    
    if tunnel_type == 's':
        listen_port = input("Enter server listen port (default: 3080): ") or "3080"
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)
        
        config_dict = {
            "server": {
                "bind_addr": f"0.0.0.0:{listen_port}",
                "transport": "wssmux",
                "token": token,
                "nodelay": True,
                "sniffer": False,
                "web_port": 2060,
                "log_level": "info",
                
                # Streaming-optimized MUX settings
                "mux_version": 2,
                "mux_framesize": 262144,  # 256KB - Large frames for streaming
                "mux_recievebuffer": 33554432,  # 32MB
                "mux_streambuffer": 16777216,  # 16MB
                "mux_con": 16,
                "mux_keepalive": 30,
                "mux_flow_control": True,
                "mux_window_size": 1048576,  # 1MB
                "mux_bandwidth": 0,  # Unlimited
                "mux_qos": True,
                "mux_priority_levels": 4,
                
                # High bandwidth settings
                "keepalive_period": 30,
                "heartbeat": 45,
                "channel_size": 8192,
                "accept_udp": True,
                
                # Network settings
                "tun_name": "backhaul-streaming",
                "tun_subnet": "10.10.10.0/24",
                "mtu": 1500,
                
                # Buffer optimization for streaming
                "so_rcvbuf": 33554432,  # 32MB
                "so_sndbuf": 33554432,  # 32MB
                
                # Connection management
                "max_connections": 1000,
                "connection_timeout": 300,
                
                # WebSocket settings
                "ws_compression": True,  # Enable compression for streaming
                "ws_ping_interval": 30,
                "ws_pong_timeout": 15,
                
                # TLS optimization
                "tls_version": "1.3",
                "tls_cipher_suites": "ECDHE-RSA-AES256-GCM-SHA384"
            }
        }
        
        # Streaming ports
        streaming_ports = input("Enter streaming ports (default: 80,443,1935,8080): ") or "80,443,1935,8080"
        config_dict["server"]["ports"] = [p.strip() for p in streaming_ports.split(',')]
        
    else:  # Client
        server_ip = input("Enter server IP address: ")
        server_port = input("Enter server port (default: 3080): ") or "3080"
        token = input("Enter auth token: ")
        edge_ip = input("Enter edge IP for CDN (optional): ") or ""
        
        config_dict = {
            "client": {
                "remote_addr": f"{server_ip}:{server_port}",
                "transport": "wssmux",
                "token": token,
                "connection_pool": 32,
                "nodelay": True,
                "sniffer": False,
                "web_port": 2060,
                "log_level": "info",
                
                # Streaming-optimized MUX settings
                "mux_version": 2,
                "mux_framesize": 262144,  # 256KB - Large frames for streaming
                "mux_recievebuffer": 33554432,  # 32MB
                "mux_streambuffer": 16777216,  # 16MB
                "mux_keepalive": 30,
                "mux_flow_control": True,
                "mux_window_size": 1048576,  # 1MB
                "mux_bandwidth": 0,  # Unlimited
                "mux_qos": True,
                "mux_priority_levels": 4,
                
                # High bandwidth settings
                "keepalive_period": 30,
                "retry_interval": 2,
                "dial_timeout": 30,
                "aggressive_pool": True,
                
                # Network settings
                "tun_name": "backhaul-streaming",
                "tun_subnet": "10.10.10.0/24",
                "mtu": 1500,
                
                # Buffer optimization for streaming
                "so_rcvbuf": 33554432,  # 32MB
                "so_sndbuf": 33554432,  # 32MB
                
                # Performance tuning
                "workers": 0,  # Auto-detect
                "channel_size": 8192,
                
                # WebSocket settings
                "ws_path": "/",
                "random_user_agent": True,
                "ws_compression": True,  # Enable compression
                "ws_ping_interval": 30,
                "ws_pong_timeout": 15,
                
                # TLS optimization
                "tls_version": "1.3",
                "tls_verify_certificate": True
            }
        }
        
        # Add edge IP if provided
        if edge_ip:
            config_dict["client"]["edge_ip"] = edge_ip
    
    # Generate and save configuration
    config_content = generate_config_content(config_dict)
    save_and_start_tunnel(tunnel_name, config_content)
    
    colorize(f"\n✅ Streaming Optimized Tunnel '{tunnel_name}' created!", C.GREEN, bold=True)
    colorize("\n📺 Streaming Optimizations Applied:", C.CYAN, bold=True)
    colorize("  ⚡ Transport: WSS MUX (Secure WebSocket Multiplexing)", C.WHITE)
    colorize("  ⚡ Large frame size: 256KB (high bandwidth)", C.WHITE)
    colorize("  ⚡ Buffer size: 32MB RX/TX", C.WHITE)
    colorize("  ⚡ WebSocket compression enabled", C.WHITE)
    colorize("  ⚡ QoS with 4 priority levels", C.WHITE)
    colorize("  ⚡ Optimized for video streaming", C.WHITE)
    
    press_key()

def create_cdn_optimized():
    clear_screen()
    colorize("--- CDN Optimized Tunnel ---", C.CYAN, bold=True)
    
    tunnel_type = input("Server (s) or Client (c)? ").lower()
    tunnel_name = get_valid_tunnel_name()
    
    if tunnel_type == 's':
        listen_port = input("Enter server listen port (default: 3080): ") or "3080"
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)
        
        config_dict = {
            "server": {
                "bind_addr": f"0.0.0.0:{listen_port}",
                "transport": "wssmux",
                "token": token,
                "nodelay": True,
                "sniffer": False,
                "web_port": 2060,
                "log_level": "info",
                
                # CDN-optimized MUX settings
                "mux_version": 2,
                "mux_framesize": 131072,  # 128KB
                "mux_recievebuffer": 16777216,  # 16MB
                "mux_streambuffer": 8388608,  # 8MB
                "mux_con": 24,
                "mux_keepalive": 25,
                "mux_flow_control": True,
                "mux_window_size": 524288,  # 512KB
                "mux_session_reuse": True,
                "mux_compression": True,  # Enable compression for CDN
                
                # CDN optimization settings
                "keepalive_period": 25,
                "heartbeat": 35,
                "channel_size": 4096,
                "accept_udp": True,
                "proxy_protocol": True,
                
                # Network settings
                "tun_name": "backhaul-cdn",
                "tun_subnet": "10.10.10.0/24",
                "mtu": 1500,
                
                # Buffer optimization
                "so_rcvbuf": 16777216,  # 16MB
                "so_sndbuf": 16777216,  # 16MB
                
                # Connection management
                "max_connections": 1500,
                "connection_timeout": 300,
                
                # WebSocket settings optimized for CDN
                "ws_compression": True,
                "ws_ping_interval": 25,
                "ws_pong_timeout": 10,
                
                # TLS optimization for CDN
                "tls_version": "1.3",
                "tls_cipher_suites": "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256"
            }
        }
        
        # CDN ports
        cdn_ports = input("Enter CDN ports (default: 80,443,8080,8443): ") or "80,443,8080,8443"
        config_dict["server"]["ports"] = [p.strip() for p in cdn_ports.split(',')]
        
    else:  # Client
        server_ip = input("Enter server IP address: ")
        server_port = input("Enter server port (default: 3080): ") or "3080"
        token = input("Enter auth token: ")
        edge_ip = input("Enter edge IP for CDN (required): ")
        
        if not edge_ip:
            colorize("Edge IP is required for CDN optimization!", C.RED)
            time.sleep(2)
            return
        
        config_dict = {
            "client": {
                "remote_addr": f"{server_ip}:{server_port}",
                "transport": "wssmux",
                "token": token,
                "connection_pool": 48,
                "nodelay": True,
                "sniffer": False,
                "web_port": 2060,
                "log_level": "info",
                "edge_ip": edge_ip,
                
                # CDN-optimized MUX settings
                "mux_version": 2,
                "mux_framesize": 131072,  # 128KB
                "mux_recievebuffer": 16777216,  # 16MB
                "mux_streambuffer": 8388608,  # 8MB
                "mux_keepalive": 25,
                "mux_flow_control": True,
                "mux_window_size": 524288,  # 512KB
                "mux_session_reuse": True,
                "mux_compression": True,  # Enable compression for CDN
                
                # CDN optimization settings
                "keepalive_period": 25,
                "retry_interval": 1,
                "dial_timeout": 30,
                "aggressive_pool": True,
                "ip_limit": True,
                
                # Network settings
                "tun_name": "backhaul-cdn",
                "tun_subnet": "10.10.10.0/24",
                "mtu": 1500,
                
                # Buffer optimization
                "so_rcvbuf": 16777216,  # 16MB
                "so_sndbuf": 16777216,  # 16MB
                
                # Performance tuning
                "workers": 0,  # Auto-detect
                "channel_size": 4096,
                
                # WebSocket settings optimized for CDN
                "ws_path": "/",
                "random_user_agent": True,
                "random_tunnel_path": True,
                "ws_compression": True,
                "ws_ping_interval": 25,
                "ws_pong_timeout": 10,
                
                # TLS optimization
                "tls_version": "1.3",
                "tls_verify_certificate": True
            }
        }
    
    # Generate and save configuration
    config_content = generate_config_content(config_dict)
    save_and_start_tunnel(tunnel_name, config_content)
    
    colorize(f"\n✅ CDN Optimized Tunnel '{tunnel_name}' created!", C.GREEN, bold=True)
    colorize("\n🌐 CDN Optimizations Applied:", C.CYAN, bold=True)
    colorize("  ⚡ Transport: WSS MUX (Secure WebSocket Multiplexing)", C.WHITE)
    colorize("  ⚡ MUX compression enabled", C.WHITE)
    colorize("  ⚡ WebSocket compression enabled", C.WHITE)
    colorize("  ⚡ Session reuse for better performance", C.WHITE)
    colorize("  ⚡ Optimized for CDN edge servers", C.WHITE)
    if tunnel_type == 'c':
        colorize(f"  ⚡ Edge IP: {edge_ip}", C.WHITE)
    
    press_key()

def generate_config_content(config_dict):
    """Generate configuration file content from config dictionary"""
    config_content = ""
    for section, params in config_dict.items():
        config_content += f"[{section}]\n"
        for key, value in params.items():
            if isinstance(value, list):
                config_content += f'{key} = {json.dumps(value)}\n'
            elif isinstance(value, bool):
                config_content += f'{key} = {str(value).lower()}\n'
            elif isinstance(value, dict):
                config_content += f'{key} = {json.dumps(value)}\n'
            else:
                config_content += f'{key} = "{value}"\n' if isinstance(value, str) else f'{key} = {value}\n'
    return config_content

def save_and_start_tunnel(tunnel_name, config_content):
    """Save configuration and start tunnel service"""
    # Save configuration
    with open(f"/tmp/{tunnel_name}.toml", "w") as f:
        f.write(config_content)
    
    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
    
    # Create and start service
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    
    colorize(f"\n✅ Tunnel '{tunnel_name}' created and started!", C.GREEN, bold=True)
    time.sleep(2)

def manage_tunnel():
    clear_screen()
    colorize("--- 🔧 Tunnel Management Menu ---", C.YELLOW, bold=True)
    
    try:
        tunnel_files = [f for f in sorted(os.listdir(TUNNELS_DIR)) if f.endswith(".toml")]
        tunnels_info = []
        
        for filename in tunnel_files:
            tunnel_name = filename[:-5]
            config_path = os.path.join(TUNNELS_DIR, filename)
            tunnel_data = parse_toml_config(config_path)
            tunnels_info.append({
                'name': tunnel_name,
                'type': tunnel_data['type'],
                'addr': tunnel_data['addr']
            })
    except FileNotFoundError:
        tunnels_info = []
    
    if not tunnels_info:
        colorize("⚠️ No tunnels found.", C.YELLOW)
        press_key()
        return
    
    print(f"{C.BOLD}{'#':<4} {'TYPE':<15} {'NAME':<20} {'ADDRESS/PORT'}{C.RESET}")
    print(f"{'---':<4} {'----':<15} {'----':<20} {'------------'}")
    
    for i, info in enumerate(tunnels_info, 1):
        safe_name = sanitize_for_print(info['name'])
        if info['type'] == "Server":
            type_display = f"{C.GREEN}🇮🇷 Iran{C.RESET}"
        elif info['type'] == "Client":
            type_display = f"{C.RED}🌍 Kharej{C.RESET}"
        else:
            type_display = f"{C.WHITE}Unknown{C.RESET}"
        
        print(f"{i:<4} {type_display:<23} {safe_name:<20} {info['addr']}")
    
    try:
        choice = int(input("\nSelect a tunnel to manage (or 0 to return): "))
        if choice == 0: return
        selected_tunnel = tunnels_info[choice - 1]['name']
    except (ValueError, IndexError):
        colorize("Invalid selection.", C.RED)
        time.sleep(1)
        return
    
    safe_selected_tunnel = sanitize_for_print(selected_tunnel)
    
    while True:
        clear_screen()
        colorize(f"--- Managing '{safe_selected_tunnel}' ---", C.CYAN)
        print("1) Start\n2) Stop\n3) Restart\n4) View Status\n5) View Logs")
        colorize("6) Delete Tunnel", C.RED)
        print("\n0) Back")
        
        action = input("Choose an action: ")
        service_name = f"backhaul-{selected_tunnel}.service"
        
        if action == '6':
            confirm = input(f"DELETE '{safe_selected_tunnel}'? (y/n): ").lower()
            if confirm == 'y':
                colorize(f"Stopping service: {service_name}", C.YELLOW)
                run_cmd(['systemctl', 'stop', service_name], as_root=True)
                time.sleep(1)
                
                config_path = f"{TUNNELS_DIR}/{selected_tunnel}.toml"
                colorize(f"Forcefully terminating any process using {config_path}...", C.YELLOW)
                run_cmd(['pkill', '-f', config_path], as_root=True)
                
                colorize("Disabling and removing service files...", C.YELLOW)
                run_cmd(['systemctl', 'disable', service_name], as_root=True)
                run_cmd(['rm', '-f', f"{SERVICE_DIR}/{service_name}"], as_root=True)
                run_cmd(['rm', '-f', config_path], as_root=True)
                run_cmd(['systemctl', 'daemon-reload'], as_root=True)
                
                colorize(f"✅ Tunnel '{safe_selected_tunnel}' has been completely deleted.", C.GREEN, bold=True)
                press_key()
                return
            else:
                colorize("Deletion cancelled.", C.YELLOW)
        
        elif action in ['1','2','3','4','5','0']:
            if action == '1':
                run_cmd(['systemctl', 'start', service_name], as_root=True)
                colorize("Started.", C.GREEN)
            elif action == '2':
                run_cmd(['systemctl', 'stop', service_name], as_root=True)
                colorize("Stopped.", C.YELLOW)
            elif action == '3':
                run_cmd(['systemctl', 'restart', service_name], as_root=True)
                colorize("Restarted.", C.GREEN)
            elif action == '4':
                clear_screen()
                run_cmd(['systemctl', 'status', service_name], as_root=True, capture=False)
                press_key()
            elif action == '5':
                clear_screen()
                try:
                    run_cmd(['journalctl', '-u', service_name, '-f', '--no-pager'], as_root=True, capture=False)
                except KeyboardInterrupt:
                    pass
            elif action == '0':
                return
        else:
            colorize("Invalid action.", C.RED)
        
        if action in ['1','2','3']:
            time.sleep(2)

def configure_new_tunnel():
    clear_screen()
    colorize("--- Configure a New Tunnel ---", C.CYAN, bold=True)
    
    print(f"{C.GREEN}1) Create Iran Server Tunnel (🇮🇷){C.RESET}")
    print(f"{C.RED}2) Create Kharej Client Tunnel (🌍){C.RESET}")
    print(f"{C.CYAN}3) High-Performance Presets{C.RESET}")
    
    choice = input("Enter your choice [1-3]: ")
    
    if choice == '1':
        create_server_tunnel()
    elif choice == '2':
        create_client_tunnel()
    elif choice == '3':
        create_optimized_tunnel()
    else:
        colorize("Invalid choice.", C.RED)
        time.sleep(1)

def install_backhaul_core():
    clear_screen()
    colorize("--- Installing Backhaul Core (v0.6.5) ---", C.YELLOW, bold=True)
    
    try:
        arch = os.uname().machine
        if arch == "x86_64":
            url = "https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_amd64.tar.gz"
        elif arch == "aarch64":
            url = "https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_arm64.tar.gz"
        else:
            colorize(f"Unsupported architecture: {arch}", C.RED)
            press_key()
            return
        
        colorize(f"Downloading from GitHub for {arch}...", C.YELLOW)
        
        # Download
        result = run_cmd(["wget", url, "-O", "/tmp/backhaul.tar.gz"])
        if result.returncode != 0:
            colorize("Download failed. Trying with curl...", C.YELLOW)
            result = run_cmd(["curl", "-L", url, "-o", "/tmp/backhaul.tar.gz"])
            if result.returncode != 0:
                colorize("Download failed with both wget and curl.", C.RED)
                press_key()
                return
        
        # Extract and install
        run_cmd(["tar", "-xzf", "/tmp/backhaul.tar.gz", "-C", "/tmp"])
        run_cmd(["mv", "/tmp/backhaul", BINARY_PATH], as_root=True)
        run_cmd(["chmod", "+x", BINARY_PATH], as_root=True)
        
        # Clean up
        run_cmd(["rm", "-f", "/tmp/backhaul.tar.gz"], as_root=True)
        
        colorize("✅ Backhaul Core v0.6.5 installed successfully!", C.GREEN, bold=True)
        
    except Exception as e:
        colorize(f"Installation error: {e}", C.RED)
    
    press_key()

def system_optimizer():
    clear_screen()
    colorize("--- 🚀 System Optimization (Enhanced) ---", C.CYAN, bold=True)
    
    optimizations = [
        ("fs.file-max", "2097152"),
        ("net.core.somaxconn", "65535"),
        ("net.ipv4.tcp_tw_reuse", "1"),
        ("net.ipv4.tcp_fin_timeout", "30"),
        ("net.ipv4.tcp_congestion_control", "bbr"),
        ("net.core.rmem_max", "134217728"),
        ("net.core.wmem_max", "134217728"),
        ("net.core.netdev_max_backlog", "5000"),
        ("net.ipv4.tcp_rmem", "4096 87380 134217728"),
        ("net.ipv4.tcp_wmem", "4096 65536 134217728"),
        ("net.ipv4.tcp_mtu_probing", "1"),
        ("net.ipv4.tcp_window_scaling", "1"),
        ("net.ipv4.tcp_timestamps", "1"),
        ("net.ipv4.tcp_sack", "1"),
        ("net.ipv4.tcp_fack", "1"),
        ("net.ipv4.tcp_slow_start_after_idle", "0"),
        ("net.ipv4.tcp_no_metrics_save", "1"),
        ("net.ipv4.tcp_moderate_rcvbuf", "1"),
        ("net.core.default_qdisc", "fq"),
        ("net.ipv4.tcp_fastopen", "3"),
        ("net.ipv4.tcp_max_syn_backlog", "8192"),
        ("net.ipv4.tcp_max_tw_buckets", "2000000"),
        ("net.ipv4.tcp_keepalive_time", "600"),
        ("net.ipv4.tcp_keepalive_intvl", "60"),
        ("net.ipv4.tcp_keepalive_probes", "3")
    ]
    
    colorize("Applying advanced kernel optimizations...", C.YELLOW)
    
    for param, value in optimizations:
        result = run_cmd(['sysctl', '-w', f'{param}={value}'], as_root=True)
        if result.returncode == 0:
            colorize(f"✓ {param} = {value}", C.GREEN)
        else:
            colorize(f"✗ Failed to set {param}", C.RED)
    
    # Make optimizations persistent
    try:
        with open('/etc/sysctl.d/99-backhaul.conf', 'w') as f:
            f.write("# Backhaul optimizations\n")
            for param, value in optimizations:
                f.write(f"{param} = {value}\n")
        colorize("✓ Optimizations made persistent", C.GREEN)
    except Exception as e:
        colorize(f"✗ Failed to make optimizations persistent: {e}", C.RED)
    
    # Apply limits.conf changes
    try:
        with open('/etc/security/limits.conf', 'a') as f:
            f.write("\n# Backhaul optimizations\n")
            f.write("* soft nofile 1048576\n")
            f.write("* hard nofile 1048576\n")
            f.write("* soft nproc 1048576\n")
            f.write("* hard nproc 1048576\n")
        colorize("✓ File descriptor limits updated", C.GREEN)
    except Exception as e:
        colorize(f"✗ Failed to update limits.conf: {e}", C.RED)
    
    # Apply systemd limits
    try:
        with open('/etc/systemd/system.conf', 'a') as f:
            f.write("\n# Backhaul optimizations\n")
            f.write("DefaultLimitNOFILE=1048576\n")
            f.write("DefaultLimitNPROC=1048576\n")
        colorize("✓ Systemd limits updated", C.GREEN)
    except Exception as e:
        colorize(f"✗ Failed to update systemd limits: {e}", C.RED)
    
    colorize("\n✅ Advanced system optimization completed!", C.GREEN, bold=True)
    colorize("Note: Some changes may require a reboot to take effect.", C.YELLOW)
    
    press_key()

def check_tunnels_status():
    clear_screen()
    colorize("--- Backhaul Tunnels Status ---", C.CYAN, bold=True)
    
    try:
        tunnel_files = [f for f in sorted(os.listdir(TUNNELS_DIR)) if f.endswith(".toml")]
        tunnels_info = []
        
        for filename in tunnel_files:
            tunnel_name = filename[:-5]
            config_path = os.path.join(TUNNELS_DIR, filename)
            tunnel_data = parse_toml_config(config_path)
            service_name = f"backhaul-{tunnel_name}.service"
            status = get_service_status(service_name)
            
            port_display = "N/A"
            if tunnel_data['addr'] != "N/A" and ':' in tunnel_data['addr']:
                port_display = tunnel_data['addr'].split(':')[-1]
            
            tunnels_info.append({
                'name': sanitize_for_print(tunnel_name),
                'type': tunnel_data['type'],
                'addr': tunnel_data['addr'],
                'port': port_display,
                'status': status
            })
    except FileNotFoundError:
        tunnels_info = []
    
    if not tunnels_info:
        colorize("⚠️ No tunnels found.", C.YELLOW)
        press_key()
        return
    
    print(f"{C.BOLD}{'NAME':<20} {'TYPE':<15} {'PORT':<8} {'ADDRESS/PORT':<22} {'STATUS'}{C.RESET}")
    print(f"{'----':<20} {'----':<15} {'----':<8} {'------------':<22} {'------'}")
    
    for info in tunnels_info:
        if info['type'] == "Server":
            type_display = f"{C.GREEN}🇮🇷 Iran{C.RESET}"
        elif info['type'] == "Client":
            type_display = f"{C.RED}🌍 Kharej{C.RESET}"
        else:
            type_display = f"{C.WHITE}Unknown{C.RESET}"
        
        print(f"{info['name']:<20} {type_display:<23} {info['port']:<8} {info['addr']:<22} {info['status']}")
    
    press_key()

def uninstall_backhaul():
    clear_screen()
    colorize("--- Uninstall Backhaul ---", C.RED, bold=True)
    
    confirm = input("Are you sure? This will remove all tunnels and configurations (y/n): ").lower()
    if confirm != "y":
        colorize("Uninstall cancelled.", C.GREEN)
        press_key()
        return
    
    colorize("Stopping all Backhaul processes...", C.YELLOW)
    run_cmd(['pkill', '-f', BINARY_PATH], as_root=True)
    
    if os.path.exists(TUNNELS_DIR):
        tunnel_files = [f for f in os.listdir(TUNNELS_DIR) if f.endswith(".toml")]
        for filename in tunnel_files:
            tunnel_name = filename[:-5]
            service_name = f'backhaul-{tunnel_name}.service'
            colorize(f"Removing tunnel: {tunnel_name}", C.YELLOW)
            run_cmd(['systemctl', 'disable', '--now', service_name], as_root=True)
            run_cmd(['rm', '-f', f'{SERVICE_DIR}/{service_name}'], as_root=True)
    
    colorize("Removing directories and files...", C.YELLOW)
    run_cmd(['rm', '-rf', BACKHAUL_DIR, CONFIG_DIR, LOG_DIR], as_root=True)
    run_cmd(['systemctl', 'daemon-reload'], as_root=True)
    
    # Remove optimization files
    run_cmd(['rm', '-f', '/etc/sysctl.d/99-backhaul.conf'], as_root=True)
    
    colorize("✅ Backhaul uninstalled completely.", C.GREEN, bold=True)
    sys.exit(0)

def display_menu():
    clear_screen()
    
    server_ip, server_country, server_isp = get_server_info()
    core_version = get_core_version()
    
    colorize("Script Version: v8.0 (Complete MUX Edition)", C.CYAN)
    colorize(f"Core Version: {core_version}", C.CYAN)
    print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)
    colorize(f"IP Address: {server_ip}", C.WHITE)
    colorize(f"Location: {server_country}", C.WHITE)
    colorize(f"Datacenter: {server_isp}", C.WHITE)
    
    core_status = f"{C.GREEN}Installed{C.RESET}" if core_version != "N/A" else f"{C.RED}Not Installed{C.RESET}"
    colorize(f"Backhaul Core: {core_status}", C.WHITE)
    print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)
    print("")
    
    colorize(" 1. Configure a new tunnel", C.WHITE, bold=True)
    colorize(" 2. Tunnel management menu", C.WHITE, bold=True)
    colorize(" 3. Check tunnels status", C.WHITE)
    colorize(" 4. Run System Optimizer (Enhanced)", C.WHITE)
    colorize(" 5. Install/Update Backhaul Core", C.WHITE)
    colorize(" 6. Uninstall Backhaul", C.RED, bold=True)
    colorize(" 0. Exit", C.YELLOW)
    print("-------------------------------------")

def main():
    # Create necessary directories
    run_cmd(["mkdir", "-p", BACKHAUL_DIR, CONFIG_DIR, LOG_DIR, TUNNELS_DIR], as_root=True)
    
    # Auto-install core if missing
    if not os.path.exists(BINARY_PATH):
        colorize("Backhaul core not found. Installing automatically...", C.YELLOW)
        install_backhaul_core()
    
    while True:
        display_menu()
        try:
            choice = input("Enter your choice [0-6]: ")
            
            if choice == '1': configure_new_tunnel()
            elif choice == '2': manage_tunnel()
            elif choice == '3': check_tunnels_status()
            elif choice == '4': system_optimizer()
            elif choice == '5': install_backhaul_core()
            elif choice == '6': uninstall_backhaul()
            elif choice == '0':
                colorize("Goodbye!", C.GREEN)
                sys.exit(0)
            else:
                colorize("Invalid option. Please choose 0-6.", C.RED)
                time.sleep(1)
        
        except (KeyboardInterrupt, EOFError):
            print("\nExiting...")
            sys.exit(0)

if __name__ == "__main__":
    if os.geteuid() != 0:
        colorize("Error: This script must be run as root.", C.RED, bold=True)
        sys.exit(1)
    
    check_requirements()
    main()
