import os
import sys
import subprocess
import json
import time
import shutil
from urllib import request
import random
import string

# ====================================================================
#
#       🚀 Backhaul Manager v5.4 (Python - Full Feature Set) 🚀
#
#   This version adds the full "Tunnel Management Menu", allowing
#   users to start, stop, restart, view status, logs, and delete
#   previously created tunnels.
#
# ====================================================================

# --- Global Variables ---
class C:
    RED, GREEN, YELLOW, CYAN, WHITE, BOLD, RESET = '\033[31m', '\033[32m', '\033[33m', '\033[36m', '\033[37m', '\033[1m', '\033[0m'

BACKHAUL_DIR, CONFIG_DIR, SERVICE_DIR = "/opt/backhaul", "/etc/backhaul", "/etc/systemd/system"
LOG_DIR, BINARY_PATH, TUNNELS_DIR = "/var/log/backhaul", f"{BACKHAUL_DIR}/backhaul", f"{CONFIG_DIR}/tunnels"
SCRIPT_PATH = "/usr/local/bin/backhaul-manager.py"

# --- Helper Functions ---
def run_cmd(command, as_root=False, capture=True):
    if as_root: command.insert(0, "sudo")
    if capture:
        return subprocess.run(command, capture_output=True, text=True, check=False)
    else:
        # For interactive commands like logs
        return subprocess.run(command)

def clear_screen(): os.system('clear')
def press_key(): input("\nPress Enter to continue...")
def colorize(text, color, bold=False):
    style = C.BOLD if bold else ""
    print(f"{style}{color}{text}{C.RESET}")

def get_server_info():
    try:
        with request.urlopen('http://ip-api.com/json/?fields=query,country,isp', timeout=5) as response:
            data = json.loads(response.read().decode())
            return data.get('query', 'N/A'), data.get('country', 'N/A'), data.get('isp', 'N/A')
    except Exception:
        return "N/A", "N/A", "N/A"

def get_core_version():
    if os.path.exists(BINARY_PATH):
        result = run_cmd([BINARY_PATH, '--version'])
        if result.returncode == 0 and result.stdout:
            return result.stdout.strip().split('\n')[0]
        return "Unknown"
    return "N/A"

def check_requirements():
    colorize("Checking for required packages...", C.YELLOW)
    requirements = ['wget', 'tar', 'systemctl', 'openssl', 'jq']
    missing = [cmd for cmd in requirements if shutil.which(cmd) is None]
    if missing:
        colorize(f"Missing required packages: {', '.join(missing)}", C.RED, bold=True)
        sys.exit(1)

def create_service(tunnel_name):
    service_content = f"""
[Unit]
Description=Backhaul Tunnel Service - {tunnel_name}
After=network.target
StartLimitIntervalSec=0

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
    try:
        # Write to a temporary file first
        with open("/tmp/temp_service", "w") as f:
            f.write(service_content)
        # Use sudo to move it to the final destination
        run_cmd(['mv', '/tmp/temp_service', service_path], as_root=True)
        run_cmd(['systemctl', 'daemon-reload'], as_root=True)
        run_cmd(['systemctl', 'enable', f'backhaul-{tunnel_name}.service'], as_root=True)
    except Exception as e:
        colorize(f"Error creating service: {e}", C.RED)


# --- Full Feature Functions ---

def create_server_tunnel():
    clear_screen()
    colorize("--- 🇮🇷 Create Iran Server Tunnel ---", C.GREEN, bold=True)
    
    tunnel_name = input("Enter a name for this tunnel: ")
    if not tunnel_name:
        colorize("Tunnel name cannot be empty.", C.RED); time.sleep(2); return

    print("\nAvailable transport protocols: tcp, tcpmux, udp, ws, wss, wsmux, wssmux")
    transport = input("Choose a transport protocol (default: tcp): ") or "tcp"
    
    bind_addr = input("Enter bind address (default: 0.0.0.0:3080): ") or "0.0.0.0:3080"
    
    token = input("Enter authentication token (leave empty to generate): ")
    if not token:
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)

    colorize("\nPort configuration examples (comma-separated):", C.CYAN)
    colorize("  443         (Listen on port 443)", C.WHITE)
    colorize("  443=5201    (Listen on 443, forward to 5201)", C.WHITE)
    ports_str = input("Enter port configurations: ")
    ports_list = [p.strip() for p in ports_str.split(',') if p.strip()]

    config_content = f"""
[server]
bind_addr = "{bind_addr}"
transport = "{transport}"
token = "{token}"
log_level = "info"
ports = {json.dumps(ports_list)}
"""
    
    config_path = f"{TUNNELS_DIR}/{tunnel_name}.toml"
    with open(f"/tmp/{tunnel_name}.toml", "w") as f:
        f.write(config_content)
    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', config_path], as_root=True)
        
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    
    colorize(f"\n✅ Server tunnel '{tunnel_name}' created and started!", C.GREEN, bold=True)
    press_key()


def create_client_tunnel():
    clear_screen()
    colorize("--- 🌍 Create Kharej Client Tunnel ---", C.CYAN, bold=True)

    tunnel_name = input("Enter a name for this tunnel: ")
    if not tunnel_name:
        colorize("Tunnel name cannot be empty.", C.RED); time.sleep(2); return

    remote_addr = input("Enter the Iran Server address (IP:PORT): ")
    if not remote_addr:
        colorize("Server address cannot be empty.", C.RED); time.sleep(2); return

    print("\nAvailable transport protocols: tcp, tcpmux, udp, ws, wss, wsmux, wssmux")
    transport = input("Choose a transport protocol (default: tcp): ") or "tcp"

    token = input("Enter the authentication token from the server: ")
    if not token:
        colorize("Token cannot be empty.", C.RED); time.sleep(2); return
        
    config_content = f"""
[client]
remote_addr = "{remote_addr}"
transport = "{transport}"
token = "{token}"
log_level = "info"
"""
    
    config_path = f"{TUNNELS_DIR}/{tunnel_name}.toml"
    with open(f"/tmp/{tunnel_name}.toml", "w") as f:
        f.write(config_content)
    run_cmd(['mv', f'/tmp/{tunnel_name}.toml', config_path], as_root=True)
        
    create_service(tunnel_name)
    run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
    
    colorize(f"\n✅ Client tunnel '{tunnel_name}' created and started!", C.GREEN, bold=True)
    press_key()

def configure_new_tunnel():
    clear_screen()
    colorize("--- Configure a New Tunnel ---", C.CYAN, bold=True)
    print("\n1) Create Iran Server Tunnel (Server Role)")
    print("2) Create Kharej Client Tunnel (Client Role)")
    choice = input("Enter your choice [1-2]: ")
    if choice == '1':
        create_server_tunnel()
    elif choice == '2':
        create_client_tunnel()
    else:
        colorize("Invalid choice.", C.RED); time.sleep(1)

def manage_tunnel():
    clear_screen()
    colorize("--- 🔧 Tunnel Management Menu ---", C.YELLOW, bold=True)
    
    tunnels = [f[:-5] for f in os.listdir(TUNNELS_DIR) if f.endswith(".toml")]
    if not tunnels:
        colorize("⚠️ No tunnels found to manage.", C.YELLOW); press_key(); return

    print("Available tunnels:")
    for i, tunnel_name in enumerate(tunnels, 1):
        print(f"{i}) {tunnel_name}")

    try:
        choice = int(input("\nSelect a tunnel to manage (or 0 to return): "))
        if choice == 0: return
        selected_tunnel = tunnels[choice - 1]
    except (ValueError, IndexError):
        colorize("Invalid selection.", C.RED); time.sleep(1); return
    
    # Sub-menu for actions
    while True:
        clear_screen()
        colorize(f"--- Managing '{selected_tunnel}' ---", C.CYAN)
        print("1) Start Tunnel")
        print("2) Stop Tunnel")
        print("3) Restart Tunnel")
        print("4) View Status")
        print("5) View Logs")
        colorize("6) Delete Tunnel", C.RED)
        print("\n0) Back to main menu")
        
        action = input("Choose an action: ")
        service_name = f"backhaul-{selected_tunnel}.service"
        
        if action == '1':
            run_cmd(['systemctl', 'start', service_name], as_root=True)
            colorize(f"'{selected_tunnel}' started.", C.GREEN); time.sleep(2)
        elif action == '2':
            run_cmd(['systemctl', 'stop', service_name], as_root=True)
            colorize(f"'{selected_tunnel}' stopped.", C.YELLOW); time.sleep(2)
        elif action == '3':
            run_cmd(['systemctl', 'restart', service_name], as_root=True)
            colorize(f"'{selected_tunnel}' restarted.", C.GREEN); time.sleep(2)
        elif action == '4':
            clear_screen()
            run_cmd(['systemctl', 'status', service_name], as_root=True, capture=False)
            press_key()
        elif action == '5':
            clear_screen()
            try:
                run_cmd(['journalctl', '-u', service_name, '-f', '--no-pager'], as_root=True, capture=False)
            except KeyboardInterrupt:
                pass # Allow user to exit logs with Ctrl+C
        elif action == '6':
            confirm = input(f"Are you sure you want to DELETE '{selected_tunnel}'? This cannot be undone. (Type YES to confirm): ")
            if confirm == "YES":
                run_cmd(['systemctl', 'disable', '--now', service_name], as_root=True)
                run_cmd(['rm', '-f', f"{SERVICE_DIR}/{service_name}"], as_root=True)
                run_cmd(['rm', '-f', f"{TUNNELS_DIR}/{selected_tunnel}.toml"], as_root=True)
                run_cmd(['systemctl', 'daemon-reload'], as_root=True)
                colorize(f"Tunnel '{selected_tunnel}' has been deleted.", C.GREEN)
                press_key()
                return # Exit management menu for this tunnel
            else:
                colorize("Deletion cancelled.", C.YELLOW); time.sleep(2)
        elif action == '0':
            return
        else:
            colorize("Invalid action.", C.RED); time.sleep(1)

def install_backhaul_core():
    # This function remains unchanged from v5.2
    clear_screen()
    colorize("--- Installing/Updating Backhaul Core (v0.6.5 - Direct Link) ---", C.YELLOW, bold=True)
    try:
        arch = os.uname().machine
        download_url = ""
        if arch == "x86_64":
            download_url = "https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_amd64.tar.gz"
        elif arch == "aarch64":
            download_url = "https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_arm64.tar.gz"
        else:
            colorize(f"Unsupported architecture: {arch}", C.RED); press_key(); return

        colorize(f"Using direct link for v0.6.5 ({arch})", C.GREEN)
        colorize(f"Downloading from: {download_url}", C.YELLOW)
        run_cmd(["wget", download_url, "-O", "/tmp/backhaul.tar.gz"])
        run_cmd(["tar", "-xzf", "/tmp/backhaul.tar.gz", "-C", "/tmp"])
        run_cmd(["mv", "/tmp/backhaul", BINARY_PATH], as_root=True)
        run_cmd(["chmod", "+x", BINARY_PATH], as_root=True)
        colorize("✅ Backhaul Core v0.6.5 installed successfully!", C.GREEN, bold=True)
    except Exception as e:
        colorize(f"An error occurred: {e}", C.RED)
    press_key()

def check_tunnels_status():
    clear_screen()
    colorize("--- Backhaul Tunnels Status ---", C.CYAN, bold=True)
    if not os.path.exists(TUNNELS_DIR) or not os.listdir(TUNNELS_DIR):
        colorize("⚠️ No tunnels found.", C.YELLOW); press_key(); return

    print(f"{C.BOLD}{'NAME':<20} {'TYPE':<15} {'STATUS':<22}{C.RESET}")
    print(f"{'----':<20} {'----':<15} {'------':<22}")

    for filename in sorted(os.listdir(TUNNELS_DIR)):
        if filename.endswith(".toml"):
            tunnel_name = filename[:-5]
            service_name = f"backhaul-{tunnel_name}.service"
            tunnel_type = "Client"
            try:
                with open(os.path.join(TUNNELS_DIR, filename), 'r') as f:
                    if "[server]" in f.read():
                        tunnel_type = "Server"
            except IOError: tunnel_type = "Unknown"
            
            result = run_cmd(['systemctl', 'is-active', service_name])
            status = f"{C.GREEN}● Active{C.RESET}" if result.stdout.strip() == "active" else f"{C.RED}● Inactive{C.RESET}"
            print(f"{tunnel_name:<20} {tunnel_type:<15} {status}")
    press_key()

def uninstall_backhaul():
    clear_screen()
    colorize("--- Uninstall Backhaul ---", C.RED, bold=True)
    colorize("This will stop all tunnels and remove all configs, logs, and binaries.", C.YELLOW)
    confirm = input("Are you sure? Type 'YES' to confirm: ")
    if confirm != "YES":
        colorize("Uninstall cancelled.", C.GREEN); press_key(); return

    if os.path.exists(TUNNELS_DIR):
        for filename in os.listdir(TUNNELS_DIR):
            if filename.endswith(".toml"):
                tunnel_name = filename[:-5]
                run_cmd(['systemctl', 'disable', '--now', f'backhaul-{tunnel_name}'], as_root=True)
                run_cmd(['rm', '-f', f'{SERVICE_DIR}/backhaul-{tunnel_name}.service'], as_root=True)

    run_cmd(['rm', '-rf', BACKHAUL_DIR, CONFIG_DIR, LOG_DIR], as_root=True)
    if os.path.exists(SCRIPT_PATH): run_cmd(['rm', '-f', SCRIPT_PATH], as_root=True)
    run_cmd(['systemctl', 'daemon-reload'], as_root=True)

    colorize("✅ Backhaul uninstalled completely.", C.GREEN)
    sys.exit(0)

# --- Menu Display and Main Loop ---
def display_menu():
    clear_screen()
    server_ip, server_country, server_isp = get_server_info()
    core_version = get_core_version()

    colorize("Script Version: v5.4 (Python - Full Feature Set)", C.CYAN)
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
    colorize(" 4. Install/Update Backhaul Core (v0.6.5)", C.WHITE)
    colorize(" 5. Uninstall Backhaul", C.RED, bold=True)
    colorize(" 0. Exit", C.YELLOW)
    print("-------------------------------------")

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
            else: colorize("Invalid option. Please try again.", C.RED); time.sleep(1)
        except (KeyboardInterrupt, EOFError):
            print("\nExiting."); sys.exit(0)

if __name__ == "__main__":
    if os.geteuid() != 0:
        colorize("Error: This script must be run as root.", C.RED, bold=True); sys.exit(1)
    check_requirements()
    main()
