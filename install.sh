import os
import sys
import subprocess
import json
import time
import shutil  # <-- کتابخانه جدید برای بررسی دستورات
from urllib import request

# ====================================================================
#
#          🚀 Backhaul Manager v5.2 (Python - Dependency Fix) 🚀
#
#   This version replaces the external 'command' utility check with
#   Python's native 'shutil.which()' to resolve FileNotFoundError
#   on minimal systems. Also adds a comprehensive requirement check.
#
# ====================================================================

# --- Global Variables ---
class C:
    RED, GREEN, YELLOW, CYAN, WHITE, BOLD, RESET = '\033[31m', '\033[32m', '\033[33m', '\033[36m', '\033[37m', '\033[1m', '\033[0m'

# Paths
BACKHAUL_DIR, CONFIG_DIR, SERVICE_DIR = "/opt/backhaul", "/etc/backhaul", "/etc/systemd/system"
LOG_DIR, BINARY_PATH, TUNNELS_DIR = "/var/log/backhaul", f"{BACKHAUL_DIR}/backhaul", f"{CONFIG_DIR}/tunnels"
SCRIPT_PATH = "/usr/local/bin/backhaul-manager.py"


# --- Helper Functions ---
def run_cmd(command, as_root=False):
    if as_root: command.insert(0, "sudo")
    return subprocess.run(command, capture_output=True, text=True, check=False)

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

# --- Prerequisite Check Function (New and Improved) ---
def check_requirements():
    """Checks for required system commands using a reliable method."""
    colorize("Checking for required packages...", C.YELLOW)
    requirements = ['wget', 'tar', 'systemctl', 'openssl', 'jq']
    missing = []
    for cmd in requirements:
        if shutil.which(cmd) is None:
            missing.append(cmd)

    if missing:
        colorize(f"Missing required packages: {', '.join(missing)}", C.RED, bold=True)
        # Check for apt package manager to offer auto-install
        if shutil.which("apt-get"):
            answer = input("Do you want to try to install them now? (y/n): ").lower()
            if answer == 'y':
                colorize("Updating package lists...", C.YELLOW)
                run_cmd(['apt-get', 'update'], as_root=True)
                install_cmd = ['apt-get', 'install', '-y'] + missing
                result = run_cmd(install_cmd, as_root=True)
                if result.returncode == 0:
                    colorize("All packages installed successfully!", C.GREEN)
                else:
                    colorize("Failed to install packages. Please install them manually.", C.RED)
                    sys.exit(1)
            else:
                colorize("Please install the missing packages manually and run the script again.", C.RED)
                sys.exit(1)
        else:
            colorize("Could not find 'apt-get'. Please install the missing packages manually.", C.RED)
            sys.exit(1)
    time.sleep(1)


# --- Main Feature Functions ---
def install_backhaul_core():
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

    print(f"{'NAME':<20} {'TYPE':<15} {'STATUS':<22}")
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
            except IOError:
                tunnel_type = "Unknown"
            
            result = run_cmd(['systemctl', 'is-active', service_name])
            if result.stdout.strip() == "active":
                status = f"{C.GREEN}● Active{C.RESET}"
            else:
                status = f"{C.RED}● Inactive{C.RESET}"
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

    colorize("Script Version: v5.2 (Python - Dependency Fix)", C.CYAN)
    colorize(f"Core Version: {core_version}", C.CYAN)
    colorize("Telegram Channel: @Gozar_Xray", C.CYAN)
    print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)
    colorize(f"IP Address: {server_ip}", C.WHITE)
    colorize(f"Location: {server_country}", C.WHITE)
    colorize(f"Datacenter: {server_isp}", C.WHITE)
    core_status = f"{C.GREEN}Installed{C.RESET}" if core_version != "N/A" else f"{C.RED}Not Installed{C.RESET}"
    colorize(f"Backhaul Core: {core_status}", C.WHITE)
    print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)

    print("")
    colorize(" 1. Configure a new tunnel", C.WHITE)
    colorize(" 2. Tunnel management menu", C.WHITE)
    colorize(" 3. Check tunnels status", C.WHITE)
    colorize(" 4. Optimize network & system limits", C.WHITE)
    colorize(" 5. Install/Update Backhaul Core (v0.6.5)", C.WHITE)
    colorize(" 6. Update this script", C.WHITE)
    colorize(" 7. Uninstall Backhaul", C.RED)
    colorize(" 0. Exit", C.YELLOW)
    print("-------------------------------------")

def main():
    run_cmd(["mkdir", "-p", BACKHAUL_DIR, CONFIG_DIR, LOG_DIR, TUNNELS_DIR], as_root=True)

    while True:
        display_menu()
        try:
            choice = input("Enter your choice [0-7]: ")
            if choice == '1': colorize("This feature is under development.", C.YELLOW); press_key()
            elif choice == '2': colorize("This feature is under development.", C.YELLOW); press_key()
            elif choice == '3': check_tunnels_status()
            elif choice == '4': colorize("This feature is under development.", C.YELLOW); press_key()
            elif choice == '5': install_backhaul_core()
            elif choice == '6': colorize("This feature is under development.", C.YELLOW); press_key()
            elif choice == '7': uninstall_backhaul()
            elif choice == '0': print("Exiting."); sys.exit(0)
            else: colorize("Invalid option. Please try again.", C.RED); time.sleep(1)
        except (KeyboardInterrupt, EOFError):
            print("\nExiting."); sys.exit(0)

if __name__ == "__main__":
    if os.geteuid() != 0:
        colorize("Error: This script must be run as root. Please use 'sudo'.", C.RED, bold=True)
        sys.exit(1)
    
    check_requirements()
    main()
