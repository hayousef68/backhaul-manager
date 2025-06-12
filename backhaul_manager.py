#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import time
import shutil
import re
import random
import string

# رنگ‌ها
class C:
    RED, GREEN, YELLOW, CYAN, WHITE, BOLD, RESET = '\033[31m', '\033[32m', '\033[33m', '\033[36m', '\033[37m', '\033[1m', '\033[0m'
    BLUE = '\033[34m'

BACKHAUL_DIR, CONFIG_DIR, SERVICE_DIR = "/opt/backhaul", "/etc/backhaul", "/etc/systemd/system"
LOG_DIR, BINARY_PATH, TUNNELS_DIR = "/var/log/backhaul", f"{BACKHAUL_DIR}/backhaul", f"{CONFIG_DIR}/tunnels"

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

def is_port_in_use(port):
    result = run_cmd(['ss', '-tln'])
    return re.search(r':{}\s'.format(port), result.stdout) is not None

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

def get_service_status(service_name):
    result = run_cmd(['systemctl', 'is-active', service_name])
    if result.returncode == 0 and result.stdout.strip() == "active":
        return f"{C.GREEN}● Active{C.RESET}"
    else:
        return f"{C.RED}● Inactive{C.RESET}"

def parse_toml_config(config_path):
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
                tunnel_info["ports"] = port_entries
        elif "[client]" in content:
            tunnel_info["type"] = "Client"
            remote_match = re.search(r'remote_addr\s*=\s*["\']([^"\']+)["\']', content)
            if remote_match:
                tunnel_info["addr"] = remote_match.group(1)
    except Exception as e:
        print(f"Error parsing config {config_path}: {e}")
    return tunnel_info

def sanitize_for_print(name):
    return name.encode('ascii', 'ignore').decode('ascii')

# ----------------- ساخت سرور -----------------
def create_server_tunnel():
    clear_screen()
    colorize_server_type("Server", "Create Iran Server Tunnel", bold=True)

    tunnel_name = get_valid_tunnel_name()

    colorize("\nAvailable transport protocols:", C.CYAN)
    print("  tcp, tcpmux, udp, ws, wss, wsmux, wssmux")
    transport = input("Choose transport protocol (default: tcpmux): ") or "tcpmux"
    listen_port = input("Enter server listen port (e.g., 30370): ") or "30370"
    bind_addr = f"0.0.0.0:{listen_port}"

    token = input("Enter auth token (leave empty to generate): ")
    if not token:
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)

    ports_str = input("Enter forwarding ports (e.g., 2098): ") or "2098"
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

    config_dict = {
        "server": {
            "bind_addr": bind_addr,
            "transport": transport,
            "accept_udp": False,
            "token": token,
            "keepalive_period": 75,
            "nodelay": True,
            "channel_size": 2048,
            "heartbeat": 40,
            "mux_con": 8,
            "mux_version": 2,
            "mux_framesize": 32768,
            "mux_recievebuffer": 4194304,
            "mux_streambuffer": 2000000,
            "sniffer": False,
            "web_port": 0,
            "sniffer_log": "/root/log.json",
            "log_level": "info",
            "proxy_protocol": False,
            "tun_name": "backhaul",
            "tun_subnet": "10.10.10.0/24",
            "mtu": 1500,
            "ports": valid_ports_list,
        }
    }

    config_content = ""
    for section, params in config_dict.items():
        config_content += f"[{section}]\n"
        for key, value in params.items():
            if isinstance(value, list):
                config_content += f'{key} = {json.dumps(value)}\n'
            elif isinstance(value, bool):
                config_content += f'{key} = {str(value).lower()}\n'
            elif isinstance(value, str):
                config_content += f'{key} = "{value}"\n'
            else:
                config_content += f'{key} = {value}\n'

    with open(f"/tmp/{tunnel_name}.toml", "w") as f:
        f.write(config_content)

    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    colorize(f"\n✅ Tunnel '{tunnel_name}' created. Verifying status...", C.GREEN, bold=True)
    time.sleep(3)
    service_name = f'backhaul-{tunnel_name}.service'
    status_text = get_service_status(service_name)
    colorize(f"   Listening Port: {listen_port}", C.WHITE)
    colorize(f"   TCP_NODELAY: Enabled", C.WHITE)
    print(f"   Status: {status_text}")
    if valid_ports_list:
        colorize(f"   Forwarded Ports: {', '.join(valid_ports_list)}", C.WHITE)
    press_key()

# ----------------- ساخت کلاینت -----------------
def create_client_tunnel():
    clear_screen()
    colorize_server_type("Client", "Create Kharej Client Tunnel", bold=True)

    tunnel_name = get_valid_tunnel_name()

    server_ip = input("Enter server IP address (e.g., 86.99.54.8): ")
    if not server_ip:
        colorize("Server IP is required!", C.RED)
        time.sleep(1)
        return

    parts = server_ip.split('.')
    if len(parts) != 4 or not all(part.isdigit() and 0 <= int(part) <= 255 for part in parts):
        colorize("Invalid IP format! Use format like 1.2.3.4", C.RED)
        time.sleep(1)
        return

    server_port = input("Enter tunnel port (e.g., 8769): ")
    if not server_port or not server_port.isdigit() or not (1 <= int(server_port) <= 65535):
        colorize("Valid port number is required (1-65535)!", C.RED)
        time.sleep(1)
        return

    remote_addr = f"{server_ip}:{server_port}"
    colorize(f"Connecting to: {remote_addr}", C.CYAN)

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
    transport = input("Choose transport protocol (default: tcpmux): ") or "tcpmux"
    token = input("Enter auth token (must match server): ")
    connection_pool = int(input("Enter connection pool size (default: 8): ") or "8")

    config_dict = {
        "client": {
            "remote_addr": remote_addr,
            "transport": transport,
            "token": token,
            "connection_pool": connection_pool,
            "aggressive_pool": False,
            "keepalive_period": 75,
            "nodelay": True,
            "retry_interval": 3,
            "dial_timeout": 10,
            "mux_version": 2,
            "mux_framesize": 32768,
            "mux_recievebuffer": 4194304,
            "mux_streambuffer": 2000000,
            "sniffer": False,
            "web_port": 0,
            "sniffer_log": "/root/log.json",
            "log_level": "info",
            "ip_limit": False,
            "tun_name": "backhaul",
            "tun_subnet": "10.10.10.0/24",
            "mtu": 1500
        }
    }

    config_content = ""
    for section, params in config_dict.items():
        config_content += f"[{section}]\n"
        for key, value in params.items():
            if isinstance(value, bool):
                config_content += f'{key} = {str(value).lower()}\n'
            elif isinstance(value, str):
                config_content += f'{key} = "{value}"\n'
            else:
                config_content += f'{key} = {value}\n'

    with open(f"/tmp/{tunnel_name}.toml", "w") as f:
        f.write(config_content)

    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    colorize(f"\n✅ Tunnel '{tunnel_name}' created. Verifying status...", C.GREEN, bold=True)
    time.sleep(3)
    service_name = f'backhaul-{tunnel_name}.service'
    status_text = get_service_status(service_name)
    colorize(f"   Connecting to Port: {server_port}", C.WHITE)
    colorize(f"   TCP_NODELAY: Enabled", C.WHITE)
    print(f"   Status: {status_text}")
    press_key()

# ----------------- مدیریت تانل‌ها -----------------
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
                'addr': tunnel_data['addr'],
                'ports': tunnel_data['ports']
            })
    except FileNotFoundError:
        tunnels_info = []
    if not tunnels_info:
        colorize("⚠️ No tunnels found.", C.YELLOW)
        press_key()
        return
    print(f"{C.BOLD}{'#':<4} {'TYPE':<15} {'NAME':<20} {'ADDRESS/PORT':<22} {'PORTS'}{C.RESET}")
    print(f"{'---':<4} {'----':<15} {'----':<20} {'------------':<22} {'-----'}")
    for i, info in enumerate(tunnels_info, 1):
        safe_name = sanitize_for_print(info['name'])
        type_display = f"{C.GREEN}🇮🇷 Iran{C.RESET}" if info['type'] == "Server" else f"{C.RED}🌍 Kharej{C.RESET}"
        port_display = ', '.join(info['ports']) if info['ports'] else "N/A"
        print(f"{i:<4} {type_display:<23} {safe_name:<20} {info['addr']:<22} {port_display}")
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

# ----------------- منوی اصلی -----------------
def display_menu():
    clear_screen()
    colorize("Backhaul Manager - نسخه حرفه‌ای با پشتیبانی کامل tcpmux/wssmux", C.CYAN, bold=True)
    print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)
    colorize(" 1. Configure a new tunnel", C.WHITE, bold=True)
    colorize(" 2. Tunnel management menu", C.WHITE, bold=True)
    colorize(" 0. Exit", C.YELLOW)
    print("-------------------------------------")

def main():
    os.makedirs(BACKHAUL_DIR, exist_ok=True)
    os.makedirs(CONFIG_DIR, exist_ok=True)
    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(TUNNELS_DIR, exist_ok=True)
    while True:
        display_menu()
        try:
            choice = input("Enter your choice [0-2]: ")
            if choice == '1': configure_new_tunnel()
            elif choice == '2': manage_tunnel()
            elif choice == '0':
                colorize("Goodbye!", C.GREEN)
                sys.exit(0)
            else:
                colorize("Invalid option. Please choose 0-2.", C.RED)
                time.sleep(1)
        except (KeyboardInterrupt, EOFError):
            print("\nExiting...")
            sys.exit(0)

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

if __name__ == "__main__":
    if os.geteuid() != 0:
        colorize("Error: This script must be run as root.", C.RED, bold=True)
        sys.exit(1)
    main()
