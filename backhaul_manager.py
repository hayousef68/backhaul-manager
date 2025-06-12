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
#    🚀 Backhaul Manager v8.2 (Manual Core Installation) 🚀
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

def check_requirements():
    requirements = ['wget', 'tar', 'systemctl', 'ss', 'pkill']
    missing = []
    for cmd in requirements:
        if not shutil.which(cmd):
            missing.append(cmd)
    
    if missing:
        colorize(f"Missing required packages: {', '.join(missing)}", C.RED, bold=True)
        colorize("Installing missing packages...", C.YELLOW)
        install_cmd = ['apt', 'update', '&&', 'apt', 'install', '-y'] + missing
        run_cmd(install_cmd, as_root=True)

def create_service(tunnel_name):
    try:
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
        with open(f"/tmp/{service_name}", "w") as f:
            f.write(service_content)
        run_cmd(['mv', f'/tmp/{service_name}', service_path], as_root=True)
        run_cmd(['systemctl', 'daemon-reload'], as_root=True)
        run_cmd(['systemctl', 'enable', service_name], as_root=True)
        return True
    except Exception as e:
        colorize(f"Service creation error: {e}", C.RED)
        return False

def is_port_in_use(port):
    try:
        result = run_cmd(['ss', '-tln'])
        return re.search(r':{}\s'.format(port), result.stdout) is not None
    except:
        return False

def sanitize_for_print(name):
    try:
        return name.encode('ascii', 'ignore').decode('ascii')
    except:
        return str(name)

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
    try:
        result = run_cmd(['systemctl', 'is-active', service_name])
        if result.returncode == 0 and result.stdout.strip() == "active":
            return f"{C.GREEN}● Active{C.RESET}"
        else:
            return f"{C.RED}● Inactive{C.RESET}"
    except:
        return f"{C.RED}● Unknown{C.RESET}"

# --- Feature Functions ---
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
                            # Try alternative verification methods
                            help_result = run_cmd([BINARY_PATH, '--help'], timeout=10)
                            if help_result.returncode == 0:
                                colorize("✅ Backhaul Core installed successfully (verified with --help)!", C.GREEN, bold=True)
                            else:
                                colorize("⚠️ Binary installed but verification failed", C.YELLOW)
                                colorize("Try running manually: /opt/backhaul/backhaul", C.CYAN)
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

def create_server_tunnel():
    clear_screen()
    colorize("--- 🇮🇷 Create Iran Server Tunnel ---", C.GREEN, bold=True)
    
    # Check if core is installed
    if not os.path.exists(BINARY_PATH):
        colorize("⚠️ Backhaul Core is not installed!", C.RED, bold=True)
        colorize("Please install the core first using option 5 from the main menu.", C.YELLOW)
        press_key()
        return
    
    tunnel_name = get_valid_tunnel_name()
    if tunnel_name is None:
        return
    
    colorize("\nAvailable transport protocols:", C.CYAN)
    print("  tcp, tcpmux, udp, ws, wss, wsmux, wssmux")
    transport = get_valid_input("Choose transport protocol (default: tcp): ", input_type='str', allow_empty=True) or "tcp"
    if transport is None:
        return
    
    listen_port = get_valid_input("Enter server listen port (default: 3080): ", input_type='port', allow_empty=True) or "3080"
    if listen_port is None:
        return
    
    bind_addr = f"0.0.0.0:{listen_port}"
    
    token = get_valid_input("Enter auth token (leave empty to generate): ", input_type='str', allow_empty=True)
    if token is None:
        return
    if not token:
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        colorize(f"🔑 Generated token: {token}", C.YELLOW)
    
    # TCP_NODELAY پیش‌فرض فعال
    nodelay_input = get_valid_input("Disable TCP_NODELAY? (y/n, default: n - keeps enabled): ", input_type='str', allow_empty=True) or "n"
    if nodelay_input is None:
        return
    nodelay = nodelay_input.lower() != 'y'
    
    sniffer_input = get_valid_input("Enable Sniffer? (y/n, default: n): ", input_type='str', allow_empty=True) or "n"
    if sniffer_input is None:
        return
    sniffer = sniffer_input.lower() == 'y'
    
    web_port = 0
    if sniffer:
        web_port_input = get_valid_input("Enter sniffer web port (default: 0): ", input_type='port', allow_empty=True) or "0"
        if web_port_input is None:
            return
        web_port = int(web_port_input)
    
    ports_str = get_valid_input("Enter forwarding ports (e.g., 443, 8080=8000, leave empty to skip): ", input_type='str', allow_empty=True) or ""
    if ports_str is None:
        return
    
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
    
    # Create config
    config_dict = {
        "server": {
            "bind_addr": bind_addr,
            "transport": transport,
            "token": token,
            "nodelay": nodelay,
            "sniffer": sniffer,
            "web_port": web_port,
            "log_level": "info",
            "ports": valid_ports_list
        }
    }
    
    if 'mux' in transport:
        colorize("\n--- Advanced MUX Configuration (Server) ---", C.CYAN)
        mux_con = get_valid_input("Enter mux_con (default: 8): ", input_type='int', allow_empty=True) or 8
        if mux_con is None:
            return
        config_dict["server"]["mux"] = {"con": mux_con}
    
    # Generate config content
    config_content = ""
    for section, params in config_dict.items():
        config_content += f"[{section}]\n"
        for key, value in params.items():
            if key == "mux":
                continue
            if isinstance(value, list):
                config_content += f'{key} = {json.dumps(value)}\n'
            elif isinstance(value, bool):
                config_content += f'{key} = {str(value).lower()}\n'
            else:
                config_content += f'{key} = "{value}"\n' if isinstance(value, str) else f'{key} = {value}\n'
        if "mux" in params:
            config_content += f"\n[{section}.mux]\n"
            for sub_key, sub_value in params["mux"].items():
                config_content += f'{sub_key} = {sub_value}\n'
    
    # Save config and create service
    try:
        with open(f"/tmp/{tunnel_name}.toml", "w") as f:
            f.write(config_content)
        run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
        
        if create_service(tunnel_name):
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
        else:
            colorize("Failed to create service", C.RED)
    except Exception as e:
        colorize(f"Error creating tunnel: {e}", C.RED)
    
    press_key()

def create_client_tunnel():
    clear_screen()
    colorize("--- 🌍 Create Kharej Client Tunnel ---", C.GREEN, bold=True)
    
    # Check if core is installed
    if not os.path.exists(BINARY_PATH):
        colorize("⚠️ Backhaul Core is not installed!", C.RED, bold=True)
        colorize("Please install the core first using option 5 from the main menu.", C.YELLOW)
        press_key()
        return
    
    tunnel_name = get_valid_tunnel_name()
    if tunnel_name is None:
        return
    
    # جداسازی IP و پورت
    server_ip = get_valid_input("Enter server IP address (e.g., 1.2.3.4): ", input_type='ip')
    if server_ip is None:
        return
    
    server_port = get_valid_input("Enter tunnel port (e.g., 3080): ", input_type='port')
    if server_port is None:
        return
    
    remote_addr = f"{server_ip}:{server_port}"
    colorize(f"Connecting to: {remote_addr}", C.CYAN)
    
    # Test connection (optional)
    test_connection = get_valid_input("Test connection to server first? (y/n, default: n): ", input_type='str', allow_empty=True) or "n"
    if test_connection is None:
        return
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
    transport = get_valid_input("Choose transport protocol (default: tcp): ", input_type='str', allow_empty=True) or "tcp"
    if transport is None:
        return
    
    token = get_valid_input("Enter auth token (must match server): ", input_type='str')
    if token is None:
        return
    
    connection_pool = get_valid_input("Enter connection pool size (default: 8): ", input_type='int', allow_empty=True) or 8
    if connection_pool is None:
        return
    
    # TCP_NODELAY پیش‌فرض فعال
    nodelay_input = get_valid_input("Disable TCP_NODELAY? (y/n, default: n - keeps enabled): ", input_type='str', allow_empty=True) or "n"
    if nodelay_input is None:
        return
    nodelay = nodelay_input.lower() != 'y'
    
    sniffer_input = get_valid_input("Enable Sniffer? (y/n, default: n): ", input_type='str', allow_empty=True) or "n"
    if sniffer_input is None:
        return
    sniffer = sniffer_input.lower() == 'y'
    
    web_port = 0
    if sniffer:
        web_port_input = get_valid_input("Enter sniffer web port (default: 0): ", input_type='port', allow_empty=True) or "0"
        if web_port_input is None:
            return
        web_port = int(web_port_input)

    # Create config
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

    # Generate config content
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

    # Save config and create service
    try:
        with open(f"/tmp/{tunnel_name}.toml", "w") as f:
            f.write(config_content)
        run_cmd(['mv', f'/tmp/{tunnel_name}.toml', f"{TUNNELS_DIR}/{tunnel_name}.toml"], as_root=True)
        
        if create_service(tunnel_name):
            run_cmd(['systemctl', 'start', f'backhaul-{tunnel_name}.service'], as_root=True)
            colorize(f"\n✅ Tunnel '{tunnel_name}' created. Verifying status...", C.GREEN, bold=True)
            time.sleep(3)
            
            service_name = f'backhaul-{tunnel_name}.service'
            status_text = get_service_status(service_name)
            colorize(f"   Connecting to Port: {server_port}", C.WHITE)
            colorize(f"   TCP_NODELAY: {'Enabled' if nodelay else 'Disabled'}", C.WHITE)
            print(f"   Status: {status_text}")
        else:
            colorize("Failed to create service", C.RED)
    except Exception as e:
        colorize(f"Error creating tunnel: {e}", C.RED)
    
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
    
    print(f"{C.BOLD}{'#':<4} {'NAME':<20} {'TYPE':<8} {'ADDRESS/PORT'}{C.RESET}")
    print(f"{'---':<4} {'----':<20} {'----':<8} {'------------'}")
    for i, info in enumerate(tunnels_info, 1):
        safe_name = sanitize_for_print(info['name'])
        print(f"{i:<4} {safe_name:<20} {info['type']:<8} {info['addr']}")

    choice = get_valid_input("\nSelect a tunnel to manage (or 0 to return): ", valid_range=list(range(0, len(tunnels_info) + 1)))
    if choice is None or choice == 0:
        return
    
    try:
        selected_tunnel = tunnels_info[choice - 1]['name']
    except IndexError:
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
        
        action = get_valid_input("Choose an action: ", valid_range=list(range(0, 7)))
        if action is None:
            continue
        
        service_name = f"backhaul-{selected_tunnel}.service"

        if action == 6:
            confirm = get_valid_input(f"DELETE '{safe_selected_tunnel}'? (y/n): ", input_type='str')
            if confirm is None:
                continue
            if confirm.lower() == 'y':
                try:
                    colorize(f"Stopping service: {service_name}", C.YELLOW)
                    run_cmd(['systemctl', 'stop', service_name], as_root=True)
                    time.sleep(1)
                    
                    config_path = f"{TUNNELS_DIR}/{selected_tunnel}.toml"
                    colorize("Disabling and removing service files...", C.YELLOW)
                    run_cmd(['systemctl', 'disable', service_name], as_root=True)
                    run_cmd(['rm', '-f', f"{SERVICE_DIR}/{service_name}"], as_root=True)
                    run_cmd(['rm', '-f', config_path], as_root=True)
                    run_cmd(['systemctl', 'daemon-reload'], as_root=True)
                    
                    colorize(f"✅ Tunnel '{safe_selected_tunnel}' has been completely deleted.", C.GREEN, bold=True)
                except Exception as e:
                    colorize(f"Error deleting tunnel: {e}", C.RED)
                press_key()
                return
            else:
                colorize("Deletion cancelled.", C.YELLOW)

        elif action in [1, 2, 3, 4, 5, 0]:
            try:
                if action == 1:
                    run_cmd(['systemctl', 'start', service_name], as_root=True)
                    colorize("Started.", C.GREEN)
                elif action == 2:
                    run_cmd(['systemctl', 'stop', service_name], as_root=True)
                    colorize("Stopped.", C.YELLOW)
                elif action == 3:
                    run_cmd(['systemctl', 'restart', service_name], as_root=True)
                    colorize("Restarted.", C.GREEN)
                elif action == 4:
                    clear_screen()
                    run_cmd(['systemctl', 'status', service_name], as_root=True, capture=False)
                    press_key()
                elif action == 5:
                    clear_screen()
                    try:
                        run_cmd(['journalctl', '-u', service_name, '-f', '--no-pager'], as_root=True, capture=False)
                    except KeyboardInterrupt:
                        pass
                elif action == 0:
                    return
            except Exception as e:
                colorize(f"Action error: {e}", C.RED)
        
        if action in [1, 2, 3]:
            time.sleep(2)

def configure_new_tunnel():
    clear_screen()
    colorize("--- Configure a New Tunnel ---", C.CYAN, bold=True)
    print("\n1) Create Iran Server Tunnel\n2) Create Kharej Client Tunnel")
    choice = get_valid_input("Enter your choice [1-2]: ", valid_range=[1, 2])
    if choice is None:
        return
    if choice == 1:
        create_server_tunnel()
    elif choice == 2:
        create_client_tunnel()

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
        try:
            result = run_cmd(['sysctl', '-w', f'{param}={value}'], as_root=True)
            if result.returncode == 0:
                colorize(f"✓ {param} = {value}", C.GREEN)
            else:
                colorize(f"✗ Failed to set {param}", C.RED)
        except:
            colorize(f"✗ Error setting {param}", C.RED)
    
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
    
    print(f"{C.BOLD}{'NAME':<20} {'TYPE':<8} {'PORT':<8} {'ADDRESS/PORT':<22} {'STATUS'}{C.RESET}")
    print(f"{'----':<20} {'----':<8} {'----':<8} {'------------':<22} {'------'}")
    
    for info in tunnels_info:
        print(f"{info['name']:<20} {info['type']:<8} {info['port']:<8} {info['addr']:<22} {info['status']}")
    
    press_key()

def uninstall_backhaul():
    clear_screen()
    colorize("--- Uninstall Backhaul ---", C.RED, bold=True)
    
    confirm = get_valid_input("Are you sure? This will remove all tunnels and configurations (y/n): ", input_type='str')
    if confirm is None or confirm.lower() != "y":
        colorize("Uninstall cancelled.", C.GREEN)
        press_key()
        return
    
    try:
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
        
    except Exception as e:
        colorize(f"Uninstall error: {e}", C.RED)
    
    sys.exit(0)

# --- Menu Display and Main Loop ---
def display_menu():
    clear_screen()
    
    try:
        server_ip, server_country, server_isp = get_server_info()
        core_version = get_core_version()
        
        colorize("Script Version: v8.2 (Manual Core Installation)", C.CYAN)
        colorize(f"Core Version: {core_version}", C.CYAN)
        print(C.YELLOW + "═════════════════════════════════════════════" + C.RESET)
        colorize(f"IP Address: {server_ip}", C.WHITE)
        colorize(f"Location: {server_country}", C.WHITE)
        colorize(f"Datacenter: {server_isp}", C.WHITE)
        core_status = f"{C.GREEN}Installed{C.RESET}" if core_version != "N/A" else f"{C.RED}Not Installed - Use Option 5{C.RESET}"
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
        
        # حذف بخش نصب خودکار هسته
        # بخش قبلی که حذف شده:
        # if not os.path.exists(BINARY_PATH):
        #     colorize("Backhaul core not found. Installing automatically...", C.YELLOW)
        #     install_backhaul_core()
        
        # Main loop
        while True:
            display_menu()
            choice = get_valid_input("Enter your choice [0-6]: ", valid_range=list(range(0, 7)))
            if choice is None:
                continue
            
            if choice == 1:
                configure_new_tunnel()
            elif choice == 2:
                manage_tunnel()
            elif choice == 3:
                check_tunnels_status()
            elif choice == 4:
                system_optimizer()
            elif choice == 5:
                install_backhaul_core()
            elif choice == 6:
                uninstall_backhaul()
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
        # Check basic requirements
        check_requirements()
        # Start main application
        main()
    except Exception as e:
        print(f"Startup error: {e}")
        print("The script encountered an error during startup.")
        sys.exit(1)
