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
import ipaddress

# ====================================================================
#
#    🚀 Backhaul Manager v7.6 (NodeDelay Default Enabled) 🚀
#
# ====================================================================

# --- Global Variables & Constants ---
class C:
    RED, GREEN, YELLOW, CYAN, WHITE, BOLD, RESET = '\033[31m', '\033[32m', '\033[33m', '\033[36m', '\033[37m', '\033[1m', '\033[0m'

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

def get_valid_input(prompt, valid_range=None, input_type='int'):
    """Get valid input with retry loop for menu choices and other inputs"""
    while True:
        try:
            user_input = input(prompt).strip()
            
            if input_type == 'int':
                value = int(user_input)
                if valid_range and value not in valid_range:
                    colorize(f"Please enter a number between {min(valid_range)} and {max(valid_range)}.", C.RED)
                    continue
                return value
            elif input_type == 'str':
                if user_input:
                    return user_input
                else:
                    colorize("Please enter a valid text.", C.RED)
                    continue
            elif input_type == 'ip':
                try:
                    ipaddress.ip_address(user_input)
                    return user_input
                except ValueError:
                    colorize("Invalid IP address format! Please enter a valid IP (e.g., 1.2.3.4).", C.RED)
                    continue
            elif input_type == 'port':
                port = int(user_input)
                if 1 <= port <= 65535:
                    return str(port)
                else:
                    colorize("Port must be between 1 and 65535.", C.RED)
                    continue
                    
        except ValueError:
            colorize("Invalid input! Please enter a valid number.", C.RED)
            continue
        except (KeyboardInterrupt, EOFError):
            colorize("\nOperation cancelled by user.", C.YELLOW)
            return None

def get_valid_tunnel_name():
    while True:
        tunnel_name = get_valid_input("Enter a name for this tunnel (e.g., my-tunnel): ", input_type='str')
        if tunnel_name is None:
            return None
        if re.match(r'^[a-zA-Z0-9_-]+$', tunnel_name):
            return tunnel_name
        else:
            colorize("Invalid name! Use English letters, numbers, dash (-), and underscore (_).", C.RED)

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
    clear_screen(); colorize("--- 🇮🇷 Create Iran Server Tunnel ---", C.GREEN, bold=True)
    tunnel_name = get_valid_tunnel_name()
    if tunnel_name is None: return
    
    colorize("\nAvailable transport protocols:", C.CYAN); print("  tcp, tcpmux, udp, ws, wss, wsmux, wssmux")
    transport = get_valid_input("Choose transport protocol (default: tcp): ", input_type='str') or "tcp"
    if transport is None: return
    
    listen_port = get_valid_input("Enter server listen port (e.g., 3080): ", input_type='port') or "3080"
    if listen_port is None: return
    
    bind_addr = f"0.0.0.0:{listen_port}"
    token = get_valid_input("Enter auth token (leave empty to generate): ", input_type='str')
    if token is None: return
    if not token: 
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)
    
    # TCP_NODELAY پیش‌فرض فعال - سؤال برای غیرفعال کردن
    nodelay_input = get_valid_input("Disable TCP_NODELAY? (y/n, default: n - keeps enabled): ", input_type='str') or "n"
    if nodelay_input is None: return
    nodelay = nodelay_input.lower() != 'y'  # اگر y گفت غیرفعال شود، در غیر این صورت فعال باقی بماند
    
    sniffer_input = get_valid_input("Enable Sniffer? (y/n, default: n): ", input_type='str') or "n"
    if sniffer_input is None: return
    sniffer = sniffer_input.lower() == 'y'
    
    web_port = 0
    if sniffer:
        web_port_input = get_valid_input("Enter sniffer web port (default: 0): ", input_type='port') or "0"
        if web_port_input is None: return
        web_port = int(web_port_input)
    
    ports_str = get_valid_input("Enter forwarding ports (e.g., 443, 8080=8000): ", input_type='str') or ""
    if ports_str is None: return
    
    valid_ports_list = []
    if ports_str:
        raw_ports = [p.strip() for p in ports_str.split(',') if p.strip()]
        for port_entry in raw_ports:
            try:
                listen_part = port_entry.split('=')[0]; port_to_check_str = listen_part.split(':')[-1]
                if port_to_check_str.isdigit() and not is_port_in_use(int(port_to_check_str)):
                    colorize(f"Port {port_to_check_str} is available. Added.", C.GREEN); valid_ports_list.append(port_entry)
                else: colorize(f"Port {port_to_check_str} is already in use or invalid. Skipped.", C.RED)
            except: colorize(f"Could not parse '{port_entry}'. Added without validation.", C.YELLOW); valid_ports_list.append(port_entry)
    
    config_dict = {"server": {"bind_addr": bind_addr, "transport": transport, "token": token, "nodelay": nodelay, "sniffer": sniffer, "web_port": web_port, "log_level": "info", "ports": valid_ports_list}}
    if 'mux' in transport:
        colorize("\n--- Advanced MUX Configuration (Server) ---", C.CYAN)
        mux_con = get_valid_input("Enter mux_con (default: 8): ", input_type='int') or 8
        if mux_con is None: return
        config_dict["server"]["mux"] = { "con": mux_con }
    
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
    create_service(tunnel_name); run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
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
    clear_screen(); colorize("--- 🌍 Create Kharej Client Tunnel ---", C.GREEN, bold=True)
    tunnel_name = get_valid_tunnel_name()
    if tunnel_name is None: return
    
    # جداسازی IP و پورت برای راحتی کاربر
    server_ip = get_valid_input("Enter server IP address (e.g., 1.2.3.4): ", input_type='ip')
    if server_ip is None: return
    
    server_port = get_valid_input("Enter tunnel port (e.g., 3080): ", input_type='port')
    if server_port is None: return
    
    remote_addr = f"{server_ip}:{server_port}"
    colorize(f"Connecting to: {remote_addr}", C.CYAN)
    
    # بررسی اتصال به سرور (اختیاری)
    test_connection = get_valid_input("Test connection to server first? (y/n, default: n): ", input_type='str') or "n"
    if test_connection is None: return
    if test_connection.lower() == 'y':
        colorize("Testing connection...", C.YELLOW)
        result = run_cmd(['nc', '-z', '-v', '-w5', server_ip, server_port])
        if result.returncode == 0:
            colorize("✅ Connection test successful!", C.GREEN)
        else:
            colorize("⚠️ Connection test failed. Continuing anyway...", C.YELLOW)
        time.sleep(2)
    
    colorize("\nAvailable transport protocols:", C.CYAN); print("  tcp, tcpmux, ws, wss, wsmux, wssmux")
    transport = get_valid_input("Choose transport protocol (default: tcp): ", input_type='str') or "tcp"
    if transport is None: return
    
    token = get_valid_input("Enter auth token (must match server): ", input_type='str')
    if token is None: return
    
    connection_pool = get_valid_input("Enter connection pool size (default: 8): ", input_type='int') or 8
    if connection_pool is None: return
    
    # TCP_NODELAY پیش‌فرض فعال - سؤال برای غیرفعال کردن
    nodelay_input = get_valid_input("Disable TCP_NODELAY? (y/n, default: n - keeps enabled): ", input_type='str') or "n"
    if nodelay_input is None: return
    nodelay = nodelay_input.lower() != 'y'  # اگر y گفت غیرفعال شود، در غیر این صورت فعال باقی بماند
    
    sniffer_input = get_valid_input("Enable Sniffer? (y/n, default: n): ", input_type='str') or "n"
    if sniffer_input is None: return
    sniffer = sniffer_input.lower() == 'y'
    
    web_port = 0
    if sniffer:
        web_port_input = get_valid_input("Enter sniffer web port (default: 0): ", input_type='port') or "0"
        if web_port_input is None: return
        web_port = int(web_port_input)

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

# ادامه کد... (سایر توابع بدون تغییر)
