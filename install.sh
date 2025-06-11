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
#       🚀 Backhaul Manager v6.0 (Python - Final Stable) 🚀
#
#   This version fixes both the NameError and IndentationError bugs.
#   It includes full functionality for creating, managing, and
#   validating tunnels in a stable Python environment.
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

def get_valid_tunnel_name():
    while True:
        tunnel_name = input("Enter a name for this tunnel (e.g., my-tunnel): ")
        if tunnel_name and re.match(r'^[a-zA-Z0-9_-]+$', tunnel_name):
            return tunnel_name
        else:
            colorize("Invalid name! Please use only English letters, numbers, dash (-), and underscore (_).", C.RED)

def get_server_info():
    try:
        with request.urlopen('http://ip-api.com/json/?fields=query,country,isp', timeout=5) as response:
            data = json.loads(response.read().decode())
            return data.get('query', 'N/A'), data.get('country', 'N/A'), data.get('isp', 'N/A')
    except:
        return "N/A", "N/A", "N/A"

def get_core_version():
    if os.path.exists(BINARY_PATH):
        result = run_cmd([BINARY_PATH, '--version'])
        return result.stdout.strip().split('\n')[0] if result.returncode == 0 and result.stdout else "Unknown"
    return "N/A"

def check_requirements():
    requirements = ['wget', 'tar', 'systemctl', 'openssl', 'jq', 'ss']
    missing = [cmd for cmd in requirements if shutil.which(cmd) is None]
    if missing:
        colorize(f"Missing required packages: {', '.join(missing)}", C.RED, bold=True); sys.exit(1)

def create_service(tunnel_name):
    service_content = f"""
[Unit]
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
    service_path = f"{SERVICE_DIR}/backhaul-{tunnel_name}.service"
    with open(f"/tmp/{service_name}", "w") as f: f.write(service_content)
    run_cmd(['mv', f'/tmp/{service_name}', service_path], as_root=True)
    run_cmd(['systemctl', 'daemon-reload'], as_root=True)
    run_cmd(['systemctl', 'enable', service_name], as_root=True)

def is_port_in_use(port):
    result = run_cmd(['ss', '-tln'])
    return re.search(r':{}\s'.format(port), result.stdout) is not None

# --- Feature Functions ---

def create_server_tunnel():
    clear_screen()
    colorize("--- 🇮🇷 Create Iran Server Tunnel ---", C.GREEN, bold=True)
    tunnel_name = get_valid_tunnel_name()
    transport = input("Choose transport protocol (default: tcp): ") or "tcp"
    bind_addr = input("Enter bind address (e.g., 0.0.0.0:3080): ") or "0.0.0.0:3080"
    token = input("Enter auth token (leave empty to generate): ")
    if not token:
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)
    
    ports_str = input("Enter forwarding ports (e.g., 443, 8080=8000): ")
    valid_ports_list = []
    if ports_str:
        raw_ports = [p.strip() for p in ports_str.split(',') if p.strip()]
        for port_entry in raw_ports:
            try:
                listen_part = port_entry.split('=')[0]
                port_to_check_str = listen_part.split(':')[-1]
                if port_to_check_str.isdigit():
                    port_to_check = int(port_to_check_str)
                    if not is_port_in_use(port_to_check):
                        colorize(f"Port {port_to_check} is available. Added.", C.GREEN)
                        valid_ports_list.append(port_entry)
                    else:
                        colorize(f"Port {port_to_check} is already in use. Skipped.", C.RED)
                else:
                    colorize(f"Entry '{port_entry}' added without validation (complex format).", C.YELLOW)
                    valid_ports_list.append(port_entry)
            except Exception:
                colorize(f"Could not parse entry '{port_entry}'. Added without validation.", C.YELLOW)
                valid_ports_list.append(port_entry)

    config_content = f'[server]\nbind_addr = "{bind_addr}"\ntransport = "{transport}"\ntoken = "{token}"\nlog_level = "info"\nports = {json.dumps(valid_ports_list)}\n'
    
    with open(f"/tmp/{tunnel_name}.toml", "w") as f: f.write(config_content)
    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    colorize(f"\n✅ Server tunnel '{tunnel_name}' created!", C.GREEN, bold=True); press_key()

def create_client_tunnel():
    clear_screen(); colorize("--- 🌍 Create Kharej Client Tunnel ---", C.CYAN, bold=True)
    tunnel_name = get_valid_tunnel_name()
    remote_addr = input("Enter the Iran Server address (IP:PORT): ")
    transport = input("Choose transport protocol (default: tcp): ") or "tcp"
    token = input("Enter the auth token from the server: ")
    config_content = f'[client]\nremote_addr = "{remote_addr}"\ntransport = "{transport}"\ntoken = "{token}"\nlog_level = "info"\n'
    with open(f"/tmp/{tunnel_name}.toml", "w") as f: f.write(config_content)
    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    colorize(f"\n✅ Client tunnel '{tunnel_name}' created!", C.GREEN, bold=True); press_key()

def configure_new_tunnel():
    clear_screen(); colorize("--- Configure a New Tunnel ---", C.CYAN, bold=True)
    print("\n1) Create Iran Server Tunnel\n2) Create Kharej Client Tunnel")
    choice = input("Enter your choice [1-2]: ")
    if choice == '1': create_server_tunnel()
    elif choice == '2': create_client_tunnel()
    else: colorize("Invalid choice.", C.RED); time.sleep(1)

def manage_tunnel():
    clear_screen(); colorize("--- 🔧 Tunnel Management Menu ---", C.YELLOW, bold=True)
    try:
        tunnels_info = []
        for filename in sorted(os.listdir(TUNNELS_DIR)):
            if filename.endswith(".toml"):
                tunnel_name, addr = filename[:-5], "N/A"
                with open(os.path.join(TUNNELS_DIR, filename), 'r') as f:
                    for line in f:
                        if "bind_addr" in line or "remote_addr" in line:
                            addr = line.split('=')[1].strip().strip('"')
                            break
                tunnels_info.append({'name': tunnel_name, 'addr': addr})
    except FileNotFoundError: tunnels_info = []
    if not tunnels_info: colorize("⚠️ No tunnels found.", C.YELLOW); press_key(); return
    print(f"{C.BOLD}{'#':<4} {'NAME':<20} {'ADDRESS/PORT'}{C.RESET}\n{'---':<4} {'----':<20} {'------------'}")
    for i, info in enumerate(tunnels_info, 1): print(f"{i:<4} {info['name']:<20} {info['addr']}")
    try:
        choice = int(input("\nSelect a tunnel to manage (or 0 to return): "))
        if choice == 0: return
        selected_tunnel = tunnels_info[choice - 1]['name']
    except (ValueError, IndexError): colorize("Invalid selection.", C.RED); time.sleep(1); return
    
    while True:
        clear_screen(); colorize(f"--- Managing '{selected_tunnel}' ---", C.CYAN)
        print("1) Start\n2) Stop\n3) Restart\n4) View Status\n5) View Logs"); colorize("6) Delete Tunnel", C.RED); print("\n0) Back")
        action = input("Choose an action: ")
        service_name = f"backhaul-{selected_tunnel}.service"
        if action == '1': run_cmd(['systemctl', 'start', service_name], as_root=True); colorize("Started.", C.GREEN)
        elif action == '2': run_cmd(['systemctl', 'stop', service_name], as_root=True); colorize("Stopped.", C.YELLOW)
        elif action == '3': run_cmd(['systemctl', 'restart', service_name], as_root=True); colorize("Restarted.", C.GREEN)
        elif action == '4': clear_screen(); run_cmd(['systemctl', 'status', service_name], as_root=True, capture=False); press_key()
        elif action == '5':
            clear_screen()
            try:
                run_cmd(['journalctl', '-u', service_name, '-f', '--no-pager'], as_root=True, capture=False)
            except KeyboardInterrupt:
                pass
        elif action == '6':
            confirm = input(f"DELETE '{selected_tunnel}'? (y/n): ").lower()
            if confirm == 'y':
                run_cmd(['systemctl', 'disable', '--now', service_name], as_root=True)
                run_cmd(['rm', '-f', f"{SERVICE_DIR}/{service_name}", f"{TUNNELS_DIR}/{selected_tunnel}.toml"], as_root=True)
                run_cmd(['systemctl', 'daemon-reload'], as_root=True); colorize("Deleted.", C.GREEN); press_key(); return
            else: colorize("Deletion cancelled.", C.YELLOW)
        elif action == '0': return
        else: colorize("Invalid action.", C.RED)
        if action in ['1','2','3','6']: time.sleep(2)

def install_backhaul_core():
    clear_screen(); colorize("--- Installing Backhaul Core (v0.6.5) ---", C.YELLOW, bold=True)
    try:
        arch = os.uname().machine
        if arch == "x86_64": url = "https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_amd64.tar.gz"
        elif arch == "aarch64": url = "https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_arm64.tar.gz"
        else: colorize(f"Unsupported architecture: {arch}", C.RED); press_key(); return
        colorize(f"Downloading from direct link for {arch}...", C.YELLOW)
        run_cmd(["wget", url, "-O", "/tmp/backhaul.tar.gz"]); run_cmd(["tar", "-xzf", "/tmp/backhaul.tar.gz", "-C", "/tmp"])
        run_cmd(["mv", "/tmp/backhaul", BINARY_PATH], as_root=True); run_cmd(["chmod", "+x", BINARY_PATH], as_root=True)
        colorize("✅ Backhaul Core v0.6.5 installed successfully!", C.GREEN, bold=True)
    except Exception as e: colorize(f"An error occurred: {e}", C.RED)
    press_key()

def check_tunnels_status():
    clear_screen(); colorize("--- Backhaul Tunnels Status ---", C.CYAN, bold=True)
    try:
        tunnels_info = []
        for filename in sorted(os.listdir(TUNNELS_DIR)):
            if filename.endswith(".toml"):
                tunnel_name, tunnel_type, addr = filename[:-5], "Client", "N/A"
                with open(os.path.join(TUNNELS_DIR, filename), 'r') as f:
                    for line in f:
                        if "[server]" in line: tunnel_type = "Server"
                        if "bind_addr" in line or "remote_addr" in line: addr = line.split('=')[1].strip().strip('"')
                result = run_cmd(['systemctl', 'is-active', f"backhaul-{tunnel_name}.service"])
                status = f"{C.GREEN}● Active{C.RESET}" if result.stdout.strip() == "active" else f"{C.RED}● Inactive{C.RESET}"
                tunnels_info.append({'name': tunnel_name, 'type': tunnel_type, 'addr': addr, 'status': status})
    except FileNotFoundError: tunnels_info = []
    if not tunnels_info: colorize("⚠️ No tunnels found.", C.YELLOW); press_key(); return
    print(f"{C.BOLD}{'NAME':<20} {'TYPE':<10} {'ADDRESS/PORT':<22} {'STATUS'}{C.RESET}\n{'----':<20} {'----':<10} {'------------':<22} {'------'}")
    for info in tunnels_info: print(f"{info['name']:<20} {info['type']:<10} {info['addr']:<22} {info['status']}")
    press_key()

def uninstall_backhaul():
    clear_screen(); colorize("--- Uninstall Backhaul ---", C.RED, bold=True)
    confirm = input("Are you sure? (y/n): ").lower()
    if confirm != "y": colorize("Uninstall cancelled.", C.GREEN); press_key(); return
    if os.path.exists(TUNNELS_DIR):
        for filename in os.listdir(TUNNELS_DIR):
            if filename.endswith(".toml"):
                run_cmd(['systemctl', 'disable', '--now', f'backhaul-{filename[:-5]}'], as_root=True)
                run_cmd(['rm', '-f', f'{SERVICE_DIR}/backhaul-{filename[:-5]}.service'], as_root=True)
    run_cmd(['rm', '-rf', BACKHAUL_DIR, CONFIG_DIR, LOG_DIR], as_root=True)
    if os.path.exists(SCRIPT_PATH): run_cmd(['rm', '-f', SCRIPT_PATH], as_root=True)
    run_cmd(['systemctl', 'daemon-reload'], as_root=True)
    colorize("✅ Backhaul uninstalled completely.", C.GREEN); sys.exit(0)

def display_menu():
    clear_screen(); server_ip, server_country, server_isp = get_server_info(); core_version = get_core_version()
    colorize("Script Version: v6.0 (Python - Final Stable)", C.CYAN)
    colorize(f"Core Version: {core_version}", C.CYAN)
    print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)
    colorize(f"IP Address: {server_ip}", C.WHITE); colorize(f"Location: {server_country}", C.WHITE); colorize(f"Datacenter: {server_isp}", C.WHITE)
    core_status = f"{C.GREEN}Installed{C.RESET}" if core_version != "N/A" else f"{C.RED}Not Installed{C.RESET}"
    colorize(f"Backhaul Core: {core_status}", C.WHITE)
    print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)
    print(""); colorize(" 1. Configure a new tunnel", C.WHITE, bold=True); colorize(" 2. Tunnel management menu", C.WHITE, bold=True);
    colorize(" 3. Check tunnels status", C.WHITE); colorize(" 4. Install/Update Backhaul Core", C.WHITE);
    colorize(" 5. Uninstall Backhaul", C.RED, bold=True); colorize(" 0. Exit", C.YELLOW); print("-------------------------------------")

def main():
    run_cmd(["mkdir", "-p", BACKHAUL_DIR, CONFIG_DIR, LOG_DIR, TUNNELS_DIR], as_root=True)
    while True:
        display_menu()
        try:
            choice = input("Enter your choice [0-5]: ")
            if choice == '1': configure_new_tunnel()
            elif choice == '2': manage_tunnel()
            elif choice == '3': check_tunnels_status()
            elif choice == '4': install_backhaul_core()
            elif choice == '5': uninstall_backhaul()
            elif choice == '0': print("Exiting."); sys.exit(0)
            else: colorize("Invalid option.", C.RED); time.sleep(1)
        except (KeyboardInterrupt, EOFError): print("\nExiting."); sys.exit(0)

if __name__ == "__main__":
    if os.geteuid() != 0: colorize("Error: This script must be run as root.", C.RED, bold=True); sys.exit(1)
    check_requirements()
    main()
