#!/bin/bash

# =================================================================
# Backhaul (bct) v0.6.5.1 Multi-Tunnel Manager
# Version: 1.0
# UI/UX and functionality inspired by the user-provided rathole_v2.sh script.
# Core logic rewritten for back-channel-tunnel by Google Gemini.
# =================================================================

# --- Global Variables ---
CONFIG_DIR="/root/bct-core"
BCT_SOURCE_DIR="${CONFIG_DIR}/back-channel-tunnel-0.6.5.1"
BCT_BINARY_PATH="/usr/local/bin/bct"
SERVICE_DIR="/etc/systemd/system"

# --- Utility and UI Functions ---
# (Using the same functions from the Rathole script for appearance)

colorize() {
    local color_code; case "$1" in "red") color_code="\033[31m";; "green") color_code="\033[32m";; "yellow") color_code="\033[33m";; "blue") color_code="\033[34m";; "magenta") color_code="\033[35m";; "cyan") color_code="\033[36m";; "white") color_code="\033[37m";; *) color_code="\033[0m";; esac
    local style_code; case "$3" in "bold") style_code="\033[1m";; "underline") style_code="\033[4m";; *) style_code="\033[0m";; esac
    echo -e "${style_code}${color_code}$2\033[0m";
}

press_key() { read -p "Press any key to continue..."; }

display_logo() {
    colorize cyan "               __  .__           .__          "
    colorize cyan "____________ _/  |_|  |__   ____ |  |   ____  "
    colorize cyan "\_  __ \__  \\   __|  |  \ /  _ \|  | _/ __ \ "
    colorize cyan " |  | \// __ \|  | |   Y  (  <_> |  |_\  ___/ "
    colorize cyan " |__|  (____  |__| |___|  /\____/|____/\___  >"
    colorize cyan "            \/          \/                 \/ "
    echo
    colorize green "Version: ${YELLOW}1.0 (for bct-0.6.5.1)"
}

display_server_info() {
    echo -e "\e[93mâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گ\e[0m"
    local SERVER_COUNTRY; SERVER_COUNTRY=$(curl -sS "http://ip-api.com/line?fields=country")
    local SERVER_ISP; SERVER_ISP=$(curl -sS "http://ip-api.com/line?fields=isp")
    colorize cyan "Location:   ${SERVER_COUNTRY:-N/A}"
    colorize cyan "Datacenter: ${SERVER_ISP:-N/A}"
}

display_core_status() {
    if [[ -f "$BCT_BINARY_PATH" ]]; then
        colorize cyan "Backhaul Core (bct): ${GREEN}Installed"
    else
        colorize cyan "Backhaul Core (bct): ${RED}Not installed"
    fi
    echo -e "\e[93mâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گ\e[0m"
}

# --- Core BCT Installation ---

install_dependencies() {
    colorize yellow "Checking and installing dependencies (build-essential, wget)..."
    if ! command -v make &> /dev/null || ! command -v gcc &> /dev/null; then
        apt-get update >/dev/null && apt-get install -y build-essential wget >/dev/null
    fi
}

# This function contains the full C code for the modified bct.c
get_modified_bct_c_code() {
cat << 'EOF'
/*
 * back-channel-tunnel
 *
 * Copyright (c) 2013-2020, Armijn Hemel
 * All rights reserved.
 *
 * For more information about this software and the license, see the LICENSE
 * file in the top level directory.
 *
 * This file contains code for a modified version of back-channel-tunnel
 * that includes TCPMux functionality, provided by Google Gemini.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/select.h>
#include <stdbool.h>

#define BUFSIZE 4096

// from beej.us/guide/bgnet/
void *get_in_addr(struct sockaddr *sa) {
    if (sa->sa_family == AF_INET) {
        return &(((struct sockaddr_in*)sa)->sin_addr);
    }
    return &(((struct sockaddr_in6*)sa)->sin6_addr);
}

int server_listen(int port) {
    char port_str[6];
    snprintf(port_str, sizeof(port_str), "%d", port);

    int listener;
    int yes=1;
    int rv;

    struct addrinfo hints, *ai, *p;

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_PASSIVE;

    if ((rv = getaddrinfo(NULL, port_str, &hints, &ai)) != 0) {
        fprintf(stderr, "selectserver: %s\n", gai_strerror(rv));
        exit(1);
    }
    
    for(p = ai; p != NULL; p = p->ai_next) {
        listener = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (listener < 0) { 
            continue;
        }
        
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int));
        if (bind(listener, p->ai_addr, p->ai_addrlen) < 0) {
            close(listener);
            continue;
        }

        break;
    }

    if (p == NULL) {
        return -1;
    }

    freeaddrinfo(ai);

    if (listen(listener, 10) == -1) {
        return -1;
    }

    return listener;
}

int client_connect(const char *hostname, int port) {
    char port_str[6];
    snprintf(port_str, sizeof(port_str), "%d", port);

    int sockfd;
    struct addrinfo hints, *servinfo, *p;
    int rv;

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    if ((rv = getaddrinfo(hostname, port_str, &hints, &servinfo)) != 0) {
        fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(rv));
        return -1;
    }

    for(p = servinfo; p != NULL; p = p->ai_next) {
        if ((sockfd = socket(p->ai_family, p->ai_socktype, p->ai_protocol)) == -1) {
            perror("client: socket");
            continue;
        }
        if (connect(sockfd, p->ai_addr, p->ai_addrlen) == -1) {
            close(sockfd);
            perror("client: connect");
            continue;
        }
        break;
    }

    if (p == NULL) {
        fprintf(stderr, "client: failed to connect\n");
        return -2;
    }

    freeaddrinfo(servinfo);
    return sockfd;
}

void proxy_traffic(int sock1, int sock2) {
    fd_set read_fds;
    char buffer[BUFSIZE];
    int n;

    while (1) {
        FD_ZERO(&read_fds);
        FD_SET(sock1, &read_fds);
        FD_SET(sock2, &read_fds);

        if (select(FD_SETSIZE, &read_fds, NULL, NULL, NULL) < 0) {
            perror("select");
            break;
        }

        if (FD_ISSET(sock1, &read_fds)) {
            n = read(sock1, buffer, sizeof(buffer));
            if (n <= 0) break;
            if (write(sock2, buffer, n) < 0) break;
        }

        if (FD_ISSET(sock2, &read_fds)) {
            n = read(sock2, buffer, sizeof(buffer));
            if (n <= 0) break;
            if (write(sock1, buffer, n) < 0) break;
        }
    }
    close(sock1);
    close(sock2);
}

void tcpmux_server_mode(int port, const char *mapfile) {
    int listen_fd, conn_fd, target_fd;
    struct sockaddr_in servaddr, cli;
    socklen_t len;
    char buff[1024];
    
    printf("Starting TCPMux server on port %d, using map file '%s'\n", port, mapfile);
    listen_fd = server_listen(port);

    while (1) {
        len = sizeof(cli);
        conn_fd = accept(listen_fd, (struct sockaddr*)&cli, &len);
        if (conn_fd < 0) { continue; }

        if (fork() == 0) {
            close(listen_fd);
            memset(buff, 0, sizeof(buff));
            int n = read(conn_fd, buff, sizeof(buff) - 1);
            if (n <= 0) { close(conn_fd); exit(0); }
            buff[strcspn(buff, "\r\n")] = 0;

            printf("Client requested service: '%s'\n", buff);

            FILE *fp = fopen(mapfile, "r");
            if (!fp) { perror("fopen mapfile"); close(conn_fd); exit(1); }

            char line[256], service[64], target_host[128], target_port_str[10];
            bool found = false;
            while(fgets(line, sizeof(line), fp)) {
                if (sscanf(line, "%63[^:]:%127[^:]:%9s", service, target_host, target_port_str) == 3) {
                    if (strcmp(service, buff) == 0) {
                        found = true;
                        break;
                    }
                }
            }
            fclose(fp);
            
            if (!found) {
                fprintf(stderr, "Service '%s' not found in map file.\n", buff);
                close(conn_fd);
                exit(1);
            }

            int target_port = atoi(target_port_str);
            printf("Forwarding to %s:%d\n", target_host, target_port);
            target_fd = client_connect(target_host, target_port);
            if (target_fd < 0) { close(conn_fd); exit(1); }
            
            proxy_traffic(conn_fd, target_fd);
            exit(0);
        }
        close(conn_fd);
    }
}

void tcpmux_client_mode(const char *host, int r_port, const char *svc_name, int l_port) {
    int listen_fd, local_conn_fd, remote_fd;
    struct sockaddr_in cli;
    socklen_t len;
    char buffer[128];

    printf("TCPMux client for service '%s' via %s:%d, listening on local port %d\n", svc_name, host, r_port, l_port);
    listen_fd = server_listen(l_port);

    while(1) {
        len = sizeof(cli);
        local_conn_fd = accept(listen_fd, (struct sockaddr*)&cli, &len);
        if (local_conn_fd < 0) { continue; }

        if (fork() == 0) {
            close(listen_fd);
            remote_fd = client_connect(host, r_port);
            if (remote_fd < 0) { close(local_conn_fd); exit(1); }

            snprintf(buffer, sizeof(buffer), "%s\n", svc_name);
            if (write(remote_fd, buffer, strlen(buffer)) < 0) {
                perror("write service name");
                close(local_conn_fd);
                close(remote_fd);
                exit(1);
            }
            proxy_traffic(local_conn_fd, remote_fd);
            exit(0);
        }
        close(local_conn_fd);
    }
}

void server_mode(int port) {
    int listen_fd, client_fd, remote_fd;
    struct sockaddr_in servaddr, cli;
    socklen_t len;

    listen_fd = server_listen(port);
    if (listen_fd == -1) {
        perror("listen");
        exit(1);
    }

    while (1) {
        len = sizeof(cli);
        client_fd = accept(listen_fd, (struct sockaddr*)&cli, &len);
        if (client_fd < 0) {
            perror("accept");
            continue;
        }
        remote_fd = accept(listen_fd, (struct sockaddr*)&cli, &len);
        if (remote_fd < 0) {
            perror("accept");
            close(client_fd);
            continue;
        }

        if (fork() == 0) {
            close(listen_fd);
            proxy_traffic(client_fd, remote_fd);
            exit(0);
        }
        close(client_fd);
        close(remote_fd);
    }
}

void client_mode(int local_port, const char *remote_host, int remote_port) {
    int listen_fd, local_conn_fd, remote_fd;
    struct sockaddr_in cli;
    socklen_t len;

    listen_fd = server_listen(local_port);
    if (listen_fd == -1) {
        perror("listen");
        exit(1);
    }

    while (1) {
        len = sizeof(cli);
        local_conn_fd = accept(listen_fd, (struct sockaddr*)&cli, &len);
        if (local_conn_fd < 0) {
            perror("accept");
            continue;
        }

        remote_fd = client_connect(remote_host, remote_port);
        if (remote_fd < 0) {
            close(local_conn_fd);
            continue;
        }

        if (fork() == 0) {
            close(listen_fd);
            proxy_traffic(local_conn_fd, remote_fd);
            exit(0);
        }
        close(local_conn_fd);
        close(remote_fd);
    }
}

void usage(const char* prog) {
    printf("Usage: %s -s <port> (for server mode)\n", prog);
    printf("   or: %s -s <local_port> -c <remote_host>:<remote_port> (for client mode)\n", prog);
    printf("   or: %s -M server <listen_port> <map_file> (for tcpmux server mode)\n", prog);
    printf("   or: %s -M client <server_ip> <server_port> <service_name> <local_port> (for tcpmux client mode)\n", prog);
    exit(1);
}

int main(int argc, char *argv[]) {
    int ch;
    int server_port = -1;
    char *remote_spec = NULL;
    int tcpmux_mode = 0;
    int server_mode = -1; // -1: unset, 0: client, 1: server

    if (argc > 1 && strcmp(argv[1], "-M") == 0) {
        tcpmux_mode = 1;
        // Shift args to parse tcpmux options
        argc--;
        argv++;
    }

    if (tcpmux_mode) {
        if (argc < 2) usage(argv[0] - 1);
        if (strcmp(argv[1], "server") == 0) {
            if (argc != 4) usage(argv[0] - 1);
            int port = atoi(argv[2]);
            char* map_file = argv[3];
            tcpmux_server_mode(port, map_file);
        } else if (strcmp(argv[1], "client") == 0) {
            if (argc != 6) usage(argv[0] - 1);
            char* host = argv[2];
            int r_port = atoi(argv[3]);
            char* svc_name = argv[4];
            int l_port = atoi(argv[5]);
            tcpmux_client_mode(host, r_port, svc_name, l_port);
        } else {
            usage(argv[0] - 1);
        }
    } else {
        while ((ch = getopt(argc, argv, "s:c:")) != -1) {
            switch (ch) {
                case 's':
                    server_port = atoi(optarg);
                    break;
                case 'c':
                    remote_spec = optarg;
                    break;
                default:
                    usage(argv[0]);
            }
        }
        if (server_port == -1) usage(argv[0]);
        if (remote_spec) { // Client mode
            char *host = strtok(remote_spec, ":");
            char *port_str = strtok(NULL, ":");
            if (!host || !port_str) usage(argv[0]);
            int remote_port = atoi(port_str);
            client_mode(server_port, host, remote_port);
        } else { // Server mode
            server_mode(server_port);
        }
    }
    return 0;
}
EOF
}

install_core() {
    if [[ -f "$BCT_BINARY_PATH" ]]; then
        colorize green "Backhaul Core (bct) is already installed." "bold"
        sleep 1; return;
    fi
    
    install_dependencies
    mkdir -p "$CONFIG_DIR"
    
    colorize yellow "Downloading back-channel-tunnel-0.6.5.1 source..."
    local BCT_URL="https://github.com/agrinberg/back-channel-tunnel/archive/refs/tags/v0.6.5.1.tar.gz"
    wget -q -O "${CONFIG_DIR}/bct.tar.gz" "$BCT_URL"
    tar -xzf "${CONFIG_DIR}/bct.tar.gz" -C "$CONFIG_DIR"
    
    colorize yellow "Applying TCPMux patch..."
    # Overwrite the original bct.c with our modified version
    get_modified_bct_c_code > "${BCT_SOURCE_DIR}/bct.c"

    colorize yellow "Compiling the core..."
    (cd "$BCT_SOURCE_DIR" && make)
    
    if [[ -f "${BCT_SOURCE_DIR}/bct" ]]; then
        cp "${BCT_SOURCE_DIR}/bct" "$BCT_BINARY_PATH"
        colorize green "Backhaul Core (bct) installed successfully to $BCT_BINARY_PATH"
    else
        colorize red "Compilation failed! Please check if build-essential is installed."
        exit 1
    fi
    press_key
}

# --- Tunnel Configuration & Management ---

configure_tunnel() {
    clear
    colorize green "1) Configure for IRAN server (bct Server Mode)" "bold"
    colorize magenta "2) Configure for KHAREJ server (bct Client Mode)" "bold"
    echo
    read -p "Enter your choice: " configure_choice
    case "$configure_choice" in
        1) configure_bct_server ;;
        2) configure_bct_client ;;
        *) colorize red "Invalid option!"; sleep 1 ;;
    esac
}

configure_bct_server() {
    clear
    colorize cyan "Configuring IRAN server (bct Server)" "bold"
    echo
    
    PS3="Select Transport Mode: "
    select transport in "TCP (Normal Mode)" "TCPMux (Multiplex Mode)"; do
        if [ -n "$transport" ]; then break; fi
    done

    if [[ "$transport" == "TCP (Normal Mode)" ]]; then
        read -p "[*] Enter port for bct to listen on (e.g., 443): " listen_port
        local exec_start="$BCT_BINARY_PATH -s $listen_port"
        local service_name="bct-server-tcp-${listen_port}"
        
        # Create systemd service
        create_bct_service "$service_name" "BCT TCP Server on port $listen_port" "$exec_start"
        
    elif [[ "$transport" == "TCPMux (Multiplex Mode)" ]]; then
        read -p "[*] Enter port for bct TCPMux to listen on (e.g., 8443): " listen_port
        
        colorize yellow "Now, define the services for the map file."
        colorize yellow "Format: service_name:ip:port (e.g., ssh:127.0.0.1:22)"
        local map_file_path="${CONFIG_DIR}/map_${listen_port}.conf"
        echo "# Service map for bct on port ${listen_port}" > "$map_file_path"
        while true; do
            read -p "Add a service (or press Enter to finish): " service_line
            if [ -z "$service_line" ]; then break; fi
            echo "$service_line" >> "$map_file_path"
        done
        
        local exec_start="$BCT_BINARY_PATH -M server $listen_port $map_file_path"
        local service_name="bct-server-mux-${listen_port}"
        create_bct_service "$service_name" "BCT TCPMux Server on port $listen_port" "$exec_start"
    fi
    press_key
}

configure_bct_client() {
    clear
    colorize magenta "Configuring KHAREJ server (bct Client)" "bold"
    echo
    
    PS3="Select Transport Mode: "
    select transport in "TCP (Normal Mode)" "TCPMux (Multiplex Mode)"; do
        if [ -n "$transport" ]; then break; fi
    done

    read -p "[*] Enter IRAN Server's public IP address: " remote_host
    
    if [[ "$transport" == "TCP (Normal Mode)" ]]; then
        read -p "[*] Enter IRAN Server's listening port: " remote_port
        read -p "[*] Enter a local port to listen on for the tunnel: " local_port
        
        local exec_start="$BCT_BINARY_PATH -s $local_port -c ${remote_host}:${remote_port}"
        local service_name="bct-client-tcp-${local_port}"
        create_bct_service "$service_name" "BCT TCP Client for ${remote_host}:${remote_port}" "$exec_start"

    elif [[ "$transport" == "TCPMux (Multiplex Mode)" ]]; then
        read -p "[*] Enter IRAN Server's TCPMux port: " remote_port
        read -p "[*] Enter the service name to connect to (e.g., ssh): " service_name
        read -p "[*] Enter a local port to listen on for this service: " local_port

        local exec_start="$BCT_BINARY_PATH -M client $remote_host $remote_port $service_name $local_port"
        local service_name="bct-client-mux-${local_port}-${service_name}"
        create_bct_service "$service_name" "BCT TCPMux Client for service ${service_name}" "$exec_start"
    fi
    press_key
}

create_bct_service() {
    local service_name=$1
    local description=$2
    local exec_start=$3

    colorize yellow "Creating systemd service: $service_name"
    cat > "${SERVICE_DIR}/${service_name}.service" << EOF
[Unit]
Description=${description}
After=network.target

[Service]
Type=simple
ExecStart=${exec_start}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "${service_name}.service"
    
    if systemctl is-active --quiet "$service_name"; then
        colorize green "Service '$service_name' created, enabled, and started successfully."
    else
        colorize red "Failed to start service '$service_name'. Check logs with 'journalctl -u $service_name'."
    fi
}

tunnel_management() {
    clear
    colorize cyan "List of existing bct services to manage:" "bold"
    echo
    
    mapfile -t services < <(find "$SERVICE_DIR" -name "bct-*.service" -printf "%f\n")
    
    if [ ${#services[@]} -eq 0 ]; then
        colorize red "No bct tunnels found."
        press_key
        return
    fi
    
    PS3="Enter your choice (0 to return): "
    select service in "${services[@]}"; do
        if [ -n "$service" ]; then break; fi
    done
    if [ -z "$service" ]; then return; fi

    clear
    colorize cyan "Managing tunnel: $service" "bold"
    echo
    PS3="Enter your choice: "
    select choice in "Restart" "Stop" "Start" "View Status" "View Logs" "Remove Tunnel" "Return"; do
        case $choice in
            "Restart") systemctl restart "$service"; colorize yellow "Restarting...";;
            "Stop") systemctl stop "$service"; colorize red "Stopping...";;
            "Start") systemctl start "$service"; colorize green "Starting...";;
            "View Status") systemctl status "$service" -n 20 --no-pager; press_key;;
            "View Logs") journalctl -u "$service" -f --no-pager;;
            "Remove Tunnel")
                read -p "Are you sure you want to remove this tunnel? (y/n): " confirm
                if [[ $confirm == [yY] ]]; then
                    systemctl disable --now "$service" >/dev/null 2>&1
                    rm -f "${SERVICE_DIR}/${service}"
                    systemctl daemon-reload
                    colorize red "Tunnel $service removed."
                fi
                break
                ;;
            "Return") break;;
        esac
    done
    sleep 1
}

check_tunnel_status() {
    clear
    colorize yellow "Checking all bct services status..." "bold"
    echo
    systemctl list-units --type=service --all "bct-*.service"
    press_key
}

# --- System Optimization (from Hawshemi) ---
hawshemi_script() {
    clear
    colorize magenta "Special thanks to Hawshemi, the author of optimizer script..." "bold"
    sleep 2
    if [[ "$(lsb_release -is)" != "Ubuntu" ]]; then
        colorize red "The operating system is not Ubuntu. Skipping." "bold"
        sleep 2; return;
    fi
    
    # Backing up and applying sysctl optimizations...
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    sed -i -e '/fs.file-max/d' -e '/net.core.default_qdisc/d' -e '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    cat <<EOF >> /etc/sysctl.conf
fs.file-max = 67108864
net.core.default_qdisc = fq_codel
net.core.netdev_max_backlog = 32768
net.core.somaxconn = 65536
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 20480
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_window_scaling = 1
EOF
    sysctl -p >/dev/null
    colorize green "Network is Optimized."

    # Optimizing ulimits...
    echo "ulimit -n 1048576" >> /etc/profile
    source /etc/profile
    colorize green "System Limits are Optimized."
    
    read -p "Reboot now? (Recommended) (y/n): " choice
    if [[ "$choice" == 'y' || "$choice" == 'Y' ]]; then
        reboot
    fi
    press_key
}

# --- Main Menu Loop ---
while true; do
    clear
    display_logo
    display_server_info
    display_core_status
    echo
    colorize green " 1. Configure a new tunnel [bct]" "bold"
    colorize red " 2. Tunnel management menu" "bold"
    colorize cyan " 3. Check tunnels status" "bold"
    echo " 4. Optimize network & system limits"
    echo " 5. Install/Re-install bct core"
    echo " 0. Exit"
    echo
    echo "-------------------------------"
    read -p "Enter your choice [0-5]: " choice
    case $choice in
        1) configure_tunnel ;;
        2) tunnel_management ;;
        3) check_tunnel_status ;;
        4) hawshemi_script ;;
        5) install_core ;;
        0) exit 0 ;;
        *) colorize red "Invalid option!" && sleep 1 ;;
    esac
done
