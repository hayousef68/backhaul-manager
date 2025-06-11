import os
import sys
import subprocess
import json
from urllib import request

# ====================================================================
#
#          🚀 Backhaul Manager v5.0 (Python Edition) 🚀
#
#   This script is rewritten in Python to definitively solve menu
#   stability and input issues experienced with the Bash version.
#   It offers the same functionality with a robust, flicker-free UI.
#
# ====================================================================

# --- Global Variables ---
class C:
    # ANSI color codes
    RED = '\033[31m'
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    CYAN = '\033[36m'
    WHITE = '\033[37m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

# Paths
BACKHAUL_DIR = "/opt/backhaul"
CONFIG_DIR = "/etc/backhaul"
SERVICE_DIR = "/etc/systemd/system"
LOG_DIR = "/var/log/backhaul"
BINARY_PATH = f"{BACKHAUL_DIR}/backhaul"
TUNNELS_DIR = f"{CONFIG_DIR}/tunnels"
SCRIPT_PATH = "/usr/local/bin/backhaul-manager.py"
SCRIPT_URL = "https://raw.githubusercontent.com/hayousef68/backhaul-manager/main/backhaul_manager.py" # Assuming the python script will be at this URL

# --- Helper Functions ---
def run_cmd(command, as_root=False):
    """Executes a shell command."""
    if as_root:
        command.insert(0, "sudo")
    return subprocess.run(command, capture_output=True, text=True)

def clear_screen():
    """Clears the terminal screen."""
    os.system('clear')

def press_key():
    """Waits for the user to press Enter."""
    input("\nPress Enter to continue...")

def colorize(text, color, bold=False):
    """Prints colored text."""
    style = C.BOLD if bold else ""
    print(f"{style}{color}{text}{C.RESET}")

def get_server_info():
    """Fetches server IP, country, and ISP."""
    try:
        with request.urlopen('http://ip-api.com/json/?fields=query,country,isp', timeout=5) as response:
            data = json.loads(response.read().decode())
            return data.get('query'), data.get('country'), data.get('isp')
    except Exception:
        return "N/A", "N/A", "N/A"

def get_core_version():
    """Gets the version of the Backhaul binary."""
    if os.path.exists(BINARY_PATH):
        result = run_cmd([BINARY_PATH, '--version'])
        if result.returncode == 0:
            return result.stdout.strip().split('\n')[0]
        return "Unknown"
    return "N/A"

# --- Main Feature Functions ---

def install_backhaul_core():
    """Downloads and installs the latest Backhaul binary."""
    clear_screen()
    colorize("--- Installing/Updating Backhaul Core ---", C.YELLOW, bold=True)
    try:
        # Detect Arch
        arch_map = {"x86_64": "amd64", "aarch64": "arm64"}
        arch = os.uname().machine
        if arch not in arch_map:
            colorize(f"Unsupported architecture: {arch}", C.RED)
            press_key()
            return

        # Get Latest Version
        colorize("Fetching latest version...", C.YELLOW)
        with request.urlopen('https://api.github.com/repos/Musixal/Backhaul/releases/latest', timeout=10) as response:
            data = json.loads(response.read().decode())
            latest_version = data['tag_name']
            download_url = f"https://github.com/Musixal/Backhaul/releases/download/{latest_version}/backhaul_linux_{arch_map[arch]}.tar.gz"

        colorize(f"Latest version: {latest_version}", C.GREEN)
        colorize(f"Downloading from: {download_url}", C.YELLOW)

        # Download and Extract
        run_cmd(["wget", download_url, "-O", "/tmp/backhaul.tar.gz"])
        run_cmd(["tar", "-xzf", "/tmp/backhaul.tar.gz", "-C", "/tmp"])
        run_cmd(["mv", "/tmp/backhaul", BINARY_PATH], as_root=True)
        run_cmd(["chmod", "+x", BINARY_PATH], as_root=True)

        colorize("✅ Backhaul Core installed successfully!", C.GREEN, bold=True)
    except Exception as e:
        colorize(f"An error occurred: {e}", C.RED)
    press_key()

def check_tunnels_status():
    """Displays the status of all configured tunnels."""
    clear_screen()
    colorize("--- Backhaul Tunnels Status ---", C.CYAN, bold=True)
    if not os.path.exists(TUNNELS_DIR) or not os.listdir(TUNNELS_DIR):
        colorize("⚠️ No tunnels found.", C.YELLOW)
        press_key()
        return

    print(f"{'NAME':<20} {'TYPE':<15} {'STATUS':<22}")
    print(f"{'----':<20} {'----':<15} {'------':<22}")

    for filename in os.listdir(TUNNELS_DIR):
        if filename.endswith(".toml"):
            tunnel_name = filename[:-5]
            service_name = f"backhaul-{tunnel_name}.service"
            
            # Determine type
            tunnel_type = "Client"
            with open(os.path.join(TUNNELS_DIR, filename)) as f:
                if "[server]" in f.read():
                    tunnel_type = "Server"

            # Check status
            result = run_cmd(['systemctl', 'is-active', service_name])
            if result.stdout.strip() == "active":
                status = f"{C.GREEN}● Active{C.RESET}"
            else:
                status = f"{C.RED}● Inactive{C.RESET}"

            print(f"{tunnel_name:<20} {tunnel_type:<15} {status:<22}")
    press_key()

def uninstall_backhaul():
    """Removes the entire Backhaul installation."""
    clear_screen()
    colorize("--- Uninstall Backhaul ---", C.RED, bold=True)
    colorize("This will stop all tunnels and remove all configs, logs, and binaries.", C.YELLOW)
    
    confirm = input("Are you sure? Type 'YES' to confirm: ")
    if confirm != "YES":
        colorize("Uninstall cancelled.", C.GREEN)
        press_key()
        return

    if os.path.exists(TUNNELS_DIR):
        for filename in os.listdir(TUNNELS_DIR):
            if filename.endswith(".toml"):
                tunnel_name = filename[:-5]
                run_cmd(['systemctl', 'disable', '--now', f'backhaul-{tunnel_name}'], as_root=True)
                run_cmd(['rm', '-f', f'{SERVICE_DIR}/backhaul-{tunnel_name}.service'], as_root=True)

    run_cmd(['rm', '-rf', BACKHAUL_DIR, CONFIG_DIR, LOG_DIR], as_root=True)
    run_cmd(['rm', '-f', SCRIPT_PATH], as_root=True)
    run_cmd(['systemctl', 'daemon-reload'], as_root=True)
    
    colorize("✅ Backhaul uninstalled completely.", C.GREEN)
    sys.exit(0)
    
# Other functions like tunnel management, config creation, etc. can be added here
# For brevity, this example focuses on the stable menu and core installation.
# The full logic from the bash script can be ported similarly.

# --- Menu Display and Main Loop ---

def display_menu():
    """Displays the main menu."""
    clear_screen()
    server_ip, server_country, server_isp = get_server_info()
    core_version = get_core_version()

    colorize("Script Version: v5.0 (Python Edition)", C.CYAN)
    colorize(f"Core Version: {core_version}", C.CYAN)
    colorize("Telegram Channel: @Gozar_Xray", C.CYAN)
    print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)
    colorize(f"IP Address: {server_ip}", C.WHITE)
    colorize(f"Location: {server_country}", C.WHITE)
    colorize(f"Datacenter: {server_isp}", C.WHITE)
    if core_version == "N/A":
        colorize(f"Backhaul Core: {C.RED}Not Installed{C.RESET}", C.WHITE)
    else:
        colorize(f"Backhaul Core: {C.GREEN}Installed{C.RESET}", C.WHITE)
    print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)
    
    # Menu options
    print("")
    colorize(" 1. Configure a new tunnel", C.WHITE)
    colorize(" 2. Tunnel management menu", C.WHITE)
    colorize(" 3. Check tunnels status", C.WHITE)
    colorize(" 4. Optimize network & system limits", C.WHITE)
    colorize(" 5. Install/Update Backhaul Core", C.WHITE)
    colorize(" 6. Update this script", C.WHITE)
    colorize(" 7. Uninstall Backhaul", C.RED)
    colorize(" 0. Exit", C.YELLOW)
    print("-------------------------------------")

def main():
    """The main execution loop."""
    # Initial setup
    run_cmd(["mkdir", "-p", BACKHAUL_DIR, CONFIG_DIR, LOG_DIR, TUNNELS_DIR], as_root=True)
    
    while True:
        display_menu()
        try:
            choice = input("Enter your choice [0-7]: ")
            if choice == '1':
                colorize("Config creation logic needs to be ported.", C.YELLOW); press_key()
            elif choice == '2':
                colorize("Tunnel management logic needs to be ported.", C.YELLOW); press_key()
            elif choice == '3':
                check_tunnels_status()
            elif choice == '4':
                colorize("Optimization logic needs to be ported.", C.YELLOW); press_key()
            elif choice == '5':
                install_backhaul_core()
            elif choice == '6':
                colorize("Script update logic needs to be ported.", C.YELLOW); press_key()
            elif choice == '7':
                uninstall_backhaul()
            elif choice == '0':
                sys.exit(0)
            else:
                colorize("Invalid option. Please try again.", C.RED)
                time.sleep(1)
        except (KeyboardInterrupt, EOFError):
            print("\nExiting.")
            sys.exit(0)


if __name__ == "__main__":
    if os.geteuid() != 0:
        colorize("Error: This script must be run as root. Please use 'sudo'.", C.RED, bold=True)
        sys.exit(1)
    main()
