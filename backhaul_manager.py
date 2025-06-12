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

# === Check Python version and handle ipaddress import ===
def safe_import_ipaddress():
    try:
        import ipaddress
        return ipaddress
    except ImportError:
        print("Warning: ipaddress module not available. Using basic validation.")
        return None

ipaddress = safe_import_ipaddress()

# ====================================================================
#
#    🚀 Backhaul Manager v8.1 (Fixed Core Installation) 🚀
#
# ====================================================================

# --- Global Variables & Constants ---
class C:
    RED, GREEN, YELLOW, CYAN, WHITE, BOLD, RESET = '\033[31m', '\033[32m', '\033[33m', '\033[36m', '\033[37m', '\033[1m', '\033[0m'

BACKHAUL_DIR, CONFIG_DIR, SERVICE_DIR = "/opt/backhaul", "/etc/backhaul", "/etc/systemd/system"
LOG_DIR, BINARY_PATH, TUNNELS_DIR = "/var/log/backhaul", f"{BACKHAUL_DIR}/backhaul", f"{CONFIG_DIR}/tunnels"

# --- Helper Functions ---
def run_cmd(command, as_root=False, capture=True, timeout=120):
    try:
        cmd = command.copy()
        if as_root and os.geteuid() != 0:
            cmd.insert(0, "sudo")
        if capture:
            return subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=timeout)
        else:
            return subprocess.run(cmd, timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"Command timed out after {timeout} seconds: {' '.join(command)}")
        return subprocess.CompletedProcess(command, 1, "", "Command timed out")
    except Exception as e:
        print(f"Command execution error: {e}")
        return subprocess.CompletedProcess(command, 1, "", str(e))

def clear_screen(): 
    os.system('clear')

def press_key(): 
    input("\nPress Enter to continue...")

def colorize(text, color, bold=False):
    try:
        style = C.BOLD if bold else ""
        print(f"{style}{color}{text}{C.RESET}")
    except:
        print(text)

def detect_architecture():
    """تشخیص دقیق معماری سیستم با چندین روش پشتیبان"""
    methods = [
        (['uname', '-m'], 'uname'),
        (['arch'], 'arch'), 
        (['dpkg', '--print-architecture'], 'dpkg'),
        (['getconf', 'LONG_BIT'], 'getconf')
    ]
    
    arch_result = None
    for cmd, method in methods:
        try:
            result = run_cmd(cmd, timeout=5)
            if result.returncode == 0 and result.stdout.strip():
                arch_output = result.stdout.strip().lower()
                colorize(f"Architecture detection via {method}: {arch_output}", C.CYAN)
                
                if arch_output in ['x86_64', 'amd64']:
                    arch_result = 'amd64'
                    break
                elif arch_output in ['aarch64', 'arm64', 'armv8']:
                    arch_result = 'arm64'
                    break
                elif arch_output == '64':  # getconf LONG_BIT output
                    # Additional check needed for getconf
                    uname_result = run_cmd(['uname', '-m'], timeout=5)
                    if 'aarch64' in uname_result.stdout.lower():
                        arch_result = 'arm64'
                    else:
                        arch_result = 'amd64'
                    break
        except:
            continue
    
    if not arch_result:
        colorize("Could not detect architecture automatically. Defaulting to amd64.", C.YELLOW)
        arch_result = 'amd64'
    
    colorize(f"Final detected architecture: {arch_result}", C.GREEN, bold=True)
    return arch_result

def download_with_fallback(url, output_path, max_retries=3):
    """دانلود فایل با روش‌های مختلف و retry mechanism"""
    methods = [
        (['wget', '--timeout=30', '--tries=3', '-O', output_path, url], 'wget'),
        (['curl', '-L', '--connect-timeout', '30', '--max-time', '120', '-o', output_path, url], 'curl'),
        (['wget', '--no-check-certificate', '--timeout=60', '-O', output_path, url], 'wget-insecure'),
        (['curl', '-k', '-L', '--connect-timeout', '60', '--max-time', '180', '-o', output_path, url], 'curl-insecure')
    ]
    
    for attempt in range(max_retries):
        colorize(f"Download attempt {attempt + 1}/{max_retries}", C.YELLOW)
        
        for cmd, method in methods:
            try:
                colorize(f"Trying download with {method}...", C.CYAN)
                result = run_cmd(cmd, timeout=180)
                
                if result.returncode == 0 and os.path.exists(output_path):
                    file_size = os.path.getsize(output_path)
                    if file_size > 1000:  # Check if file is not empty (> 1KB)
                        colorize(f"✅ Download successful with {method} (Size: {file_size} bytes)", C.GREEN)
                        return True
                    else:
                        colorize(f"Downloaded file is too small, trying next method...", C.YELLOW)
                        try:
                            os.remove(output_path)
                        except:
                            pass
                else:
                    colorize(f"Download failed with {method}: {result.stderr}", C.RED)
                    
            except Exception as e:
                colorize(f"Error with {method}: {e}", C.RED)
                continue
        
        if attempt < max_retries - 1:
            colorize(f"All methods failed, waiting 5 seconds before retry...", C.YELLOW)
            time.sleep(5)
    
    return False

def verify_and_extract(archive_path, extract_dir):
    """تأیید و استخراج فایل آرشیو"""
    if not os.path.exists(archive_path):
        colorize("Archive file not found!", C.RED)
        return False
    
    file_size = os.path.getsize(archive_path)
    if file_size < 1000:
        colorize(f"Archive file is too small ({file_size} bytes)", C.RED)
        return False
    
    colorize(f"Archive file verified (Size: {file_size} bytes)", C.GREEN)
    
    # Test archive integrity
    test_result = run_cmd(['tar', '-tzf', archive_path], timeout=30)
    if test_result.returncode != 0:
        colorize("Archive integrity check failed!", C.RED)
        return False
    
    colorize("Archive integrity verified", C.GREEN)
    
    # Extract archive
    extract_result = run_cmd(['tar', '-xzf', archive_path, '-C', extract_dir], timeout=60)
    if extract_result.returncode == 0:
        colorize("Archive extracted successfully", C.GREEN)
        return True
    else:
        colorize(f"Extraction failed: {extract_result.stderr}", C.RED)
        return False

def install_backhaul_core():
    """نصب بهبود یافته هسته Backhaul با تشخیص خودکار معماری"""
    clear_screen()
    colorize("--- 🔄 Installing/Updating Backhaul Core v0.6.5 ---", C.YELLOW, bold=True)
    
    try:
        # Create necessary directories
        colorize("Creating directories...", C.CYAN)
        run_cmd(["mkdir", "-p", BACKHAUL_DIR, "/tmp"], as_root=True)
        
        # Detect architecture
        colorize("Detecting system architecture...", C.CYAN)
        arch = detect_architecture()
        
        # Set download URL based on architecture
        if arch == 'arm64':
            url = "https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_arm64.tar.gz"
            colorize("Selected ARM64 architecture", C.GREEN)
        else:
            url = "https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_amd64.tar.gz"
            colorize("Selected AMD64/x86_64 architecture", C.GREEN)
        
        colorize(f"Download URL: {url}", C.WHITE)
        
        # Download with multiple fallback methods
        archive_path = "/tmp/backhaul.tar.gz"
        colorize("Starting download...", C.YELLOW)
        
        if download_with_fallback(url, archive_path):
            # Verify and extract
            if verify_and_extract(archive_path, "/tmp"):
                # Check if binary exists after extraction
                binary_candidates = ["/tmp/backhaul", "/tmp/backhaul_linux_amd64", "/tmp/backhaul_linux_arm64"]
                source_binary = None
                
                for candidate in binary_candidates:
                    if os.path.exists(candidate):
                        source_binary = candidate
                        break
                
                if source_binary:
                    colorize(f"Found binary: {source_binary}", C.GREEN)
                    
                    # Move binary and set permissions
                    move_result = run_cmd(['mv', source_binary, BINARY_PATH], as_root=True)
                    if move_result.returncode == 0:
                        run_cmd(['chmod', '+x', BINARY_PATH], as_root=True)
                        
                        # Verify installation
                        verify_result = run_cmd([BINARY_PATH, '--version'], timeout=10)
                        if verify_result.returncode == 0:
                            version_info = verify_result.stdout.strip()
                            colorize("✅ Backhaul Core installed successfully!", C.GREEN, bold=True)
                            colorize(f"Version: {version_info}", C.WHITE)
                        else:
                            colorize("⚠️ Binary installed but version check failed", C.YELLOW)
                    else:
                        colorize("Failed to move binary to destination", C.RED)
                        return False
                else:
                    colorize("Binary not found after extraction", C.RED)
                    # List contents of /tmp for debugging
                    ls_result = run_cmd(['ls', '-la', '/tmp/'], timeout=5)
                    colorize(f"Temp directory contents: {ls_result.stdout}", C.WHITE)
                    return False
            else:
                colorize("Failed to extract archive", C.RED)
                return False
        else:
            colorize("All download methods failed!", C.RED)
            colorize("Please check your internet connection and try again.", C.YELLOW)
            return False
        
        # Cleanup
        colorize("Cleaning up temporary files...", C.CYAN)
        cleanup_files = ["/tmp/backhaul.tar.gz", "/tmp/backhaul", "/tmp/backhaul_linux_amd64", "/tmp/backhaul_linux_arm64"]
        for file_path in cleanup_files:
            try:
                if os.path.exists(file_path):
                    run_cmd(['rm', '-f', file_path], as_root=True)
            except:
                pass
        
        return True
        
    except Exception as e:
        colorize(f"Installation error: {e}", C.RED)
        return False
    finally:
        press_key()

# [باقی توابع بدون تغییر...]
def get_valid_input(prompt, valid_range=None, input_type='int', allow_empty=False):
    """Get valid input with retry loop and better error handling"""
    while True:
        try:
            user_input = input(prompt).strip()
            
            if allow_empty and not user_input:
                return ""
                
            if input_type == 'int':
                if not user_input and allow_empty:
                    return None
                value = int(user_input)
                if valid_range and value not in valid_range:
                    colorize(f"Please enter a number between {min(valid_range)} and {max(valid_range)}.", C.RED)
                    continue
                return value
            elif input_type == 'str':
                if user_input or allow_empty:
                    return user_input
                else:
                    colorize("Please enter a valid text.", C.RED)
                    continue
            elif input_type == 'ip':
                if ipaddress:
                    try:
                        ipaddress.ip_address(user_input)
                        return user_input
                    except ValueError:
                        colorize("Invalid IP address format! Please enter a valid IP (e.g., 1.2.3.4).", C.RED)
                        continue
                else:
                    # Basic IP validation without ipaddress module
                    parts = user_input.split('.')
                    if len(parts) == 4 and all(part.isdigit() and 0 <= int(part) <= 255 for part in parts):
                        return user_input
                    else:
                        colorize("Invalid IP format! Use format like 1.2.3.4", C.RED)
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
        except Exception as e:
            colorize(f"Input error: {e}", C.RED)
            continue

def get_server_info():
    try:
        with request.urlopen('http://ip-api.com/json/?fields=query,country,isp', timeout=5) as response:
            data = json.loads(response.read().decode())
            return data.get('query', 'N/A'), data.get('country', 'N/A'), data.get('isp', 'N/A')
    except:
        return "N/A", "N/A", "N/A"

def get_core_version():
    try:
        if os.path.exists(BINARY_PATH):
            result = run_cmd([BINARY_PATH, '--version'], timeout=10)
            if result.returncode == 0 and result.stdout:
                return result.stdout.strip().split('\n')[0]
        return "N/A"
    except:
        return "N/A"

def display_menu():
    clear_screen()
    
    try:
        server_ip, server_country, server_isp = get_server_info()
        core_version = get_core_version()
        
        colorize("Script Version: v8.1 (Fixed Core Installation)", C.CYAN)
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
        colorize(" 5. Install/Update Backhaul Core", C.WHITE, bold=True)
        colorize(" 6. Uninstall Backhaul", C.RED, bold=True)
        colorize(" 0. Exit", C.YELLOW)
        print("-------------------------------------")
        
    except Exception as e:
        colorize(f"Menu display error: {e}", C.RED)
        print("1. Configure a new tunnel")
        print("2. Tunnel management menu")
        print("3. Check tunnels status")
        print("4. Run System Optimizer")
        print("5. Install/Update Backhaul Core")
        print("6. Uninstall Backhaul")
        print("0. Exit")

def main():
    try:
        # Create necessary directories
        colorize("Initializing Backhaul Manager...", C.CYAN)
        run_cmd(["mkdir", "-p", BACKHAUL_DIR, CONFIG_DIR, LOG_DIR, TUNNELS_DIR], as_root=True)
        
        # Auto-install core if missing
        if not os.path.exists(BINARY_PATH):
            colorize("Backhaul core not found. Installing automatically...", C.YELLOW)
            install_backhaul_core()
        
        # Main loop
        while True:
            display_menu()
            choice = get_valid_input("Enter your choice [0-6]: ", valid_range=list(range(0, 7)))
            if choice is None:
                continue
            
            if choice == 1:
                colorize("Configure new tunnel - Feature implementation needed", C.YELLOW)
                press_key()
            elif choice == 2:
                colorize("Tunnel management - Feature implementation needed", C.YELLOW)
                press_key()
            elif choice == 3:
                colorize("Check tunnels status - Feature implementation needed", C.YELLOW)
                press_key()
            elif choice == 4:
                colorize("System optimizer - Feature implementation needed", C.YELLOW)
                press_key()
            elif choice == 5:
                install_backhaul_core()
            elif choice == 6:
                colorize("Uninstall Backhaul - Feature implementation needed", C.YELLOW)
                press_key()
            elif choice == 0:
                colorize("Goodbye!", C.GREEN)
                sys.exit(0)
                
    except KeyboardInterrupt:
        colorize("\nExiting on user request...", C.YELLOW)
        sys.exit(0)
    except Exception as e:
        colorize(f"Fatal error: {e}", C.RED, bold=True)
        colorize("Please check your system and try again.", C.YELLOW)
        sys.exit(1)

if __name__ == "__main__":
    # Check root privileges
    if os.geteuid() != 0:
        colorize("Error: This script must be run as root.", C.RED, bold=True)
        colorize("Please run: sudo python3 backhaul_manager.py", C.YELLOW)
        sys.exit(1)
    
    try:
        # Start main application
        main()
    except Exception as e:
        print(f"Startup error: {e}")
        print("The script encountered an error during startup.")
        sys.exit(1)
