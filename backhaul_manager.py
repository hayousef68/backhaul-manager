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
#
# 🚀 Backhaul Manager v7.6 (You$ef) 🚀
#
# ====================================================================

# --- Global Variables & Constants ---
class C:
    RED, GREEN, YELLOW, CYAN, WHITE, BOLD, RESET = '\033[31m', '\033[32m', '\033[33m', '\033[36m', '\033[37m', '\033[1m', '\033[0m'
    BLUE = '\033[34m'  # اضافه کردن رنگ آبی برای سرور خارج

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
    """رنگ‌بندی بر اساس نوع سرور"""
    style = C.BOLD if bold else ""
    if tunnel_type == "Server":
        # سرور ایران - رنگ سبز
        print(f"{style}{C.GREEN}🇮🇷 {text}{C.RESET}")
    elif tunnel_type == "Client":
        # سرور خارج - رنگ آبی
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
    service_content = f"[Unit]\nDescription=Backhaul Tunnel Service - {tunnel_name}\nAfter=network.target\n\n[Service]\nType=simple\nExecStart={BINARY_PATH} -c {TUNNELS_DIR}/{tunnel_name}.toml\nRestart=always\nRestartSec=3\nUser=root\nLimitNOFILE=1048576\n\n[Install]\nWantedBy=multi-user.target\n"
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
            
        # Check if it's server or client
        if "[server]" in content:
            tunnel_info["type"] = "Server"
            # Extract bind_addr
            bind_match = re.search(r'bind_addr\s*=\s*["\']([^"\']+)["\']', content)
            if bind_match:
                tunnel_info["addr"] = bind_match.group(1)
            
            # Extract ports array
            ports_match = re.search(r'ports\s*=\s*\[(.*?)\]', content, re.DOTALL)
            if ports_match:
                ports_str = ports_match.group(1)
                # Extract individual port entries
                port_entries = re.findall(r'["\']([^"\']+)["\']', ports_str)
                tunnel_info["ports"] = port_entries[:3]  # Show first 3 ports
        
        elif "[client]" in content:
            tunnel_info["type"] = "Client"
            # Extract remote_addr
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

# --- Feature Functions ---
def create_server_tunnel():
    clear_screen()
    colorize_server_type("Server", "Create Iran Server Tunnel", bold=True)
    
    tunnel_name = get_valid_tunnel_name()
    colorize("\nAvailable transport protocols:", C.CYAN)
    print("  tcp, tcpmux, udp, ws, wss, wsmux, wssmux")
    transport = input("Choose transport protocol (default: tcp): ") or "tcp"
    listen_port = input("Enter server listen port (e.g., 3080): ") or "3080"
    bind_addr = f"0.0.0.0:{listen_port}"
    token = input("Enter auth token (leave empty to generate): ")
    if not token: 
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)
    
    # TCP_NODELAY پیش‌فرض فعال
    nodelay_input = input("Disable TCP_NODELAY? (y/n, default: n - keeps enabled): ") or "n"
    nodelay = nodelay_input.lower() != 'y'
    
    sniffer_input = input("Enable Sniffer? (y/n, default: n): ") or "n"
    sniffer = sniffer_input.lower() == 'y'
    
    web_port = 0
    if sniffer:
        web_port = int(input("Enter sniffer web port (default: 0): ") or "0")
    
    ports_str = input("Enter forwarding ports (e.g., 443, 8080=8000): ")
    valid_ports_list = []
    if ports_str:
        raw_ports = [p.strip() for p in ports_str.split(',') if p.strip()]
        for port_entry in raw_ports:
            try:
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
    
    config_dict = {"server": {"bind_addr": bind_addr, "transport": transport, "token": token, "nodelay": nodelay, "sniffer": sniffer, "web_port": web_port, "log_level": "info", "ports": valid_ports_list}}
    if 'mux' in transport:
        colorize("\n--- Advanced MUX Configuration (Server) ---", C.CYAN)
        config_dict["server"]["mux"] = { "con": int(input("Enter mux_con (default: 8): ") or "8") }
    
    config_content = ""
    for section, params in config_dict.items():
        config_content += f"[{section}]\n"
        for key, value in params.items():
            if key == "mux": continue
            if isinstance(value, list): config_content += f'{key} = {json.dumps(value)}\n'
            elif isinstance(value, bool): config_content += f'{key} = {str(value).lower()}\n'
            else: config_content += f'{key} = "{value}"\n' if isinstance(value, str) else f'{key} = {value}\n'
        if "mux" in params:
            config_content += f"\n[{section}.mux]\n"
            for sub_key, sub_value in params["mux"].items(): config_content += f'{sub_key} = {sub_value}\n'
    
    with open(f"/tmp/{tunnel_name}.toml", "w") as f: f.write(config_content)
    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    colorize(f"\n✅ Tunnel '{tunnel_name}' created. Verifying status...", C.GREEN, bold=True)
    time.sleep(3)
    service_name = f'backhaul-{tunnel_name}.service'
    status_text = get_service_status(service_name)
    colorize(f"   Listening Port: {listen_port}", C.WHITE)
    colorize(f"   TCP_NODELAY: {'Enabled' if nodelay else 'Disabled'}", C.WHITE)
    print(f"   Status: {status_text}")
    if valid_ports_list:
        colorize(f"   Forwarded Ports: {', '.join(valid_ports_list[:3])}", C.WHITE)
    press_key()

def create_client_tunnel():
    clear_screen()
    colorize_server_type("Client", "Create Kharej Client Tunnel", bold=True)
    
    tunnel_name = get_valid_tunnel_name()
    
    # جداسازی IP و پورت
    server_ip = input("Enter server IP address (e.g., 1.2.3.4): ")
    if not server_ip:
        colorize("Server IP is required!", C.RED)
        time.sleep(1)
        return
    
    # اعتبارسنجی IP ساده
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
    
    # Test connection (optional)
    test_connection = input("Test connection to server first? (y/n, default: n): ") or "n"
    if test_connection.lower() == 'y':
        colorize("Testing connection...", C.YELLOW)
        result = run_cmd(['nc', '-z', '-v', '-w5', server_ip, server_port])
        if result.returncode == 0:
            colorize("✅ Connection test successful!", C.GREEN)
        else:
            colorize("⚠️ Connection test failed. Continuing anyway...", C.YELLOW)
        time.sleep(2)
    
    colorize("\nAvailable transport protocols:", C.CYAN)
    print("  tcp, tcpmux, ws, wss, wsmux, wssmux")
    transport = input("Choose transport protocol (default: tcp): ") or "tcp"
    token = input("Enter auth token (must match server): ")
    connection_pool = int(input("Enter connection pool size (default: 8): ") or "8")
    
    # TCP_NODELAY پیش‌فرض فعال
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

    config_content = ""
    for section, params in config_dict.items():
        config_content += f"[{section}]\n"
        for key, value in params.items():
            if isinstance(value, bool): config_content += f'{key} = {str(value).lower()}\n'
            elif isinstance(value, str): config_content += f'{key} = "{value}"\n'
            else: config_content += f'{key} = {value}\n'

    with open(f"/tmp/{tunnel_name}.toml", "w") as f: f.write(config_content)
    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    colorize(f"\n✅ Tunnel '{tunnel_name}' created. Verifying status...", C.GREEN, bold=True)
    time.sleep(3)
    service_name = f'backhaul-{tunnel_name}.service'
    status_text = get_service_status(service_name)
    colorize(f"   Connecting to Port: {server_port}", C.WHITE)
    colorize(f"   TCP_NODELAY: {'Enabled' if nodelay else 'Disabled'}", C.WHITE)
    print(f"   Status: {status_text}")
    press_key()

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
        # رنگ‌بندی بر اساس نوع سرور
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
    choice = input("Enter your choice [1-2]: ")
    if choice == '1': 
        create_server_tunnel()
    elif choice == '2': 
        create_client_tunnel()
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
    colorize("--- 🚀 System Optimization (Hawshemi) ---", C.CYAN, bold=True)
    
    optimizations = [
        ("fs.file-max", "1048576"),
        ("net.core.somaxconn", "65535"),
        ("net.ipv4.tcp_tw_reuse", "1"),
        ("net.ipv4.tcp_fin_timeout", "30"),
        ("net.ipv4.tcp_congestion_control", "bbr")
    ]
    
    colorize("Applying kernel optimizations...", C.YELLOW)
    for param, value in optimizations:
        result = run_cmd(['sysctl', '-w', f'{param}={value}'], as_root=True)
        if result.returncode == 0:
            colorize(f"✓ {param} = {value}", C.GREEN)
        else:
            colorize(f"✗ Failed to set {param}", C.RED)
    
    # Apply limits.conf changes
    try:
        with open('/etc/security/limits.conf', 'a') as f:
            f.write("\n# Backhaul optimizations\n* soft nofile 1048576\n* hard nofile 1048576\n")
        colorize("✓ File descriptor limits updated", C.GREEN)
    except Exception as e:
        colorize(f"✗ Failed to update limits.conf: {e}", C.RED)
    
    colorize("\n✅ System optimization completed!", C.GREEN, bold=True)
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
            
            # Extract port from address
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
        # رنگ‌بندی بر اساس نوع سرور
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
    
    colorize("✅ Backhaul uninstalled completely.", C.GREEN, bold=True)
    sys.exit(0)

# --- Menu Display and Main Loop ---
def display_menu():
    clear_screen()
    server_ip, server_country, server_isp = get_server_info()
    core_version = get_core_version()
    
    colorize("Script Version: v7.6 (Iran/Kharej Color Coded Final)", C.CYAN)
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
    colorize(" 4. Run System Optimizer (Hawshemi)", C.WHITE)
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
