#!/bin/bash

set -euo pipefail

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'

SERVICE_CACHE_FILE="/tmp/arch-service-cache.json"
CACHE_TTL=300
SYSTEMD_DIR="/etc/systemd/system"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"

print_header() {
    echo -e "${MAGENTA}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Arch Linux Service Manager                     ║"
    echo "║        Advanced systemd service management tool         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

get_service_status() {
    local service=$1
    local is_user=${2:-false}
    
    if [ "$is_user" = true ]; then
        systemctl --user is-active "$service" 2>/dev/null || echo "inactive"
    else
        systemctl is-active "$service" 2>/dev/null || echo "inactive"
    fi
}

get_service_enabled() {
    local service=$1
    local is_user=${2:-false}
    
    if [ "$is_user" = true ]; then
        systemctl --user is-enabled "$service" 2>/dev/null || echo "disabled"
    else
        systemctl is-enabled "$service" 2>/dev/null || echo "disabled"
    fi
}

format_status() {
    local status=$1
    case "$status" in
        active|running)
            echo -e "${GREEN}● active${RESET}"
            ;;
        inactive|dead)
            echo -e "${DIM}○ inactive${RESET}"
            ;;
        failed)
            echo -e "${RED}✗ failed${RESET}"
            ;;
        activating|deactivating)
            echo -e "${YELLOW}◐ $status${RESET}"
            ;;
        *)
            echo -e "${BLUE}? $status${RESET}"
            ;;
    esac
}

format_enabled() {
    local enabled=$1
    case "$enabled" in
        enabled)
            echo -e "${GREEN}enabled${RESET}"
            ;;
        disabled)
            echo -e "${DIM}disabled${RESET}"
            ;;
        masked)
            echo -e "${RED}masked${RESET}"
            ;;
        static)
            echo -e "${BLUE}static${RESET}"
            ;;
        *)
            echo -e "${YELLOW}$enabled${RESET}"
            ;;
    esac
}

list_services() {
    local filter=${1:-all}
    local show_user=${2:-false}
    
    echo -e "${CYAN}${BOLD}System Services:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    printf "%-35s %-12s %-12s %s\n" "SERVICE" "STATUS" "ENABLED" "DESCRIPTION"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    local services
    services=$(systemctl list-units --type=service --all --no-pager --plain 2>/dev/null | tail -n +2 | head -n -7)
    
    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi
        
        local service=$(echo "$line" | awk '{print $1}')
        local load=$(echo "$line" | awk '{print $2}')
        local active=$(echo "$line" | awk '{print $3}')
        local sub=$(echo "$line" | awk '{print $4}')
        
        if [ "$filter" != "all" ]; then
            case "$filter" in
                active)
                    [ "$active" != "active" ] && continue
                    ;;
                failed)
                    [ "$sub" != "failed" ] && continue
                    ;;
                enabled)
                    local enabled_status
                    enabled_status=$(get_service_enabled "${service%.service}")
                    [ "$enabled_status" != "enabled" ] && continue
                    ;;
            esac
        fi
        
        local description=$(systemctl show -p Description --value "${service%.service}" 2>/dev/null | head -c 40)
        [ ${#description} -eq 40 ] && description="${description}..."
        
        local enabled_status
        enabled_status=$(get_service_enabled "${service%.service}")
        
        printf "%-35s " "${service%.service}"
        printf "%s" "$(format_status "$active")"
        printf "%-12s " ""
        printf "%s" "$(format_enabled "$enabled_status")"
        printf "%-12s " ""
        echo "$description"
    done <<< "$services"
    
    if [ "$show_user" = true ]; then
        echo
        echo -e "${CYAN}${BOLD}User Services:${RESET}"
        echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
        
        local user_services
        user_services=$(systemctl --user list-units --type=service --all --no-pager --plain 2>/dev/null | tail -n +2 | head -n -7)
        
        while IFS= read -r line; do
            if [ -z "$line" ]; then continue; fi
            
            local service=$(echo "$line" | awk '{print $1}')
            local active=$(echo "$line" | awk '{print $3}')
            
            if [ "$filter" != "all" ] && [ "$filter" = "active" ] && [ "$active" != "active" ]; then
                continue
            fi
            
            local enabled_status
            enabled_status=$(get_service_enabled "${service%.service}" true)
            
            printf "%-35s " "→ ${service%.service}"
            printf "%s" "$(format_status "$active")"
            printf "%-12s " ""
            printf "%s\n" "$(format_enabled "$enabled_status")"
        done <<< "$user_services"
    fi
}

analyze_boot_services() {
    echo -e "${CYAN}${BOLD}Boot Time Analysis:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    local boot_time=$(systemd-analyze time 2>/dev/null | head -n1)
    echo -e "${BLUE}Total boot time:${RESET} $boot_time"
    echo
    
    echo -e "${YELLOW}Slowest services:${RESET}"
    systemd-analyze blame 2>/dev/null | head -n 10 | while IFS= read -r line; do
        local time=$(echo "$line" | awk '{print $1}')
        local service=$(echo "$line" | awk '{print $2}')
        
        if [[ "$time" =~ min ]]; then
            echo -e "  ${RED}$time${RESET} - $service"
        elif [[ "$time" =~ ^[0-9]+(\.[0-9]+)?s$ ]]; then
            local seconds=${time%s}
            if (( $(echo "$seconds > 10" | bc -l) )); then
                echo -e "  ${YELLOW}$time${RESET} - $service"
            else
                echo -e "  ${GREEN}$time${RESET} - $service"
            fi
        else
            echo -e "  $time - $service"
        fi
    done
    
    echo
    echo -e "${CYAN}Critical chain:${RESET}"
    systemd-analyze critical-chain --no-pager 2>/dev/null | head -n 15 | tail -n +2
}

manage_service() {
    local service=$1
    local action=$2
    local is_user=${3:-false}
    
    local cmd_prefix=""
    [ "$is_user" = true ] && cmd_prefix="--user"
    
    case "$action" in
        start)
            echo -e "${BLUE}Starting $service...${RESET}"
            if sudo systemctl $cmd_prefix start "$service"; then
                echo -e "${GREEN}✓ Service started${RESET}"
            else
                echo -e "${RED}✗ Failed to start service${RESET}"
                return 1
            fi
            ;;
        stop)
            echo -e "${BLUE}Stopping $service...${RESET}"
            if sudo systemctl $cmd_prefix stop "$service"; then
                echo -e "${GREEN}✓ Service stopped${RESET}"
            else
                echo -e "${RED}✗ Failed to stop service${RESET}"
                return 1
            fi
            ;;
        restart)
            echo -e "${BLUE}Restarting $service...${RESET}"
            if sudo systemctl $cmd_prefix restart "$service"; then
                echo -e "${GREEN}✓ Service restarted${RESET}"
            else
                echo -e "${RED}✗ Failed to restart service${RESET}"
                return 1
            fi
            ;;
        enable)
            echo -e "${BLUE}Enabling $service...${RESET}"
            if sudo systemctl $cmd_prefix enable "$service"; then
                echo -e "${GREEN}✓ Service enabled${RESET}"
            else
                echo -e "${RED}✗ Failed to enable service${RESET}"
                return 1
            fi
            ;;
        disable)
            echo -e "${BLUE}Disabling $service...${RESET}"
            if sudo systemctl $cmd_prefix disable "$service"; then
                echo -e "${GREEN}✓ Service disabled${RESET}"
            else
                echo -e "${RED}✗ Failed to disable service${RESET}"
                return 1
            fi
            ;;
        mask)
            echo -e "${BLUE}Masking $service...${RESET}"
            if sudo systemctl $cmd_prefix mask "$service"; then
                echo -e "${GREEN}✓ Service masked${RESET}"
            else
                echo -e "${RED}✗ Failed to mask service${RESET}"
                return 1
            fi
            ;;
        unmask)
            echo -e "${BLUE}Unmasking $service...${RESET}"
            if sudo systemctl $cmd_prefix unmask "$service"; then
                echo -e "${GREEN}✓ Service unmasked${RESET}"
            else
                echo -e "${RED}✗ Failed to unmask service${RESET}"
                return 1
            fi
            ;;
    esac
}

show_service_details() {
    local service=$1
    
    echo -e "${CYAN}${BOLD}Service: $service${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    local status=$(systemctl status "$service" --no-pager 2>/dev/null)
    
    if [ -z "$status" ]; then
        echo -e "${RED}Service not found${RESET}"
        return 1
    fi
    
    local active_state=$(systemctl show -p ActiveState --value "$service" 2>/dev/null)
    local sub_state=$(systemctl show -p SubState --value "$service" 2>/dev/null)
    local load_state=$(systemctl show -p LoadState --value "$service" 2>/dev/null)
    local enabled_state=$(get_service_enabled "$service")
    local description=$(systemctl show -p Description --value "$service" 2>/dev/null)
    local main_pid=$(systemctl show -p MainPID --value "$service" 2>/dev/null)
    local memory=$(systemctl show -p MemoryCurrent --value "$service" 2>/dev/null)
    local cpu_usage=$(systemctl show -p CPUUsageNSec --value "$service" 2>/dev/null)
    
    echo -e "${BLUE}Description:${RESET} $description"
    echo -e "${BLUE}Status:${RESET} $(format_status "$active_state") ($sub_state)"
    echo -e "${BLUE}Enabled:${RESET} $(format_enabled "$enabled_state")"
    echo -e "${BLUE}Load State:${RESET} $load_state"
    
    if [ "$main_pid" != "0" ] && [ -n "$main_pid" ]; then
        echo -e "${BLUE}Main PID:${RESET} $main_pid"
    fi
    
    if [ "$memory" != "18446744073709551615" ] && [ -n "$memory" ]; then
        local memory_mb=$(echo "scale=2; $memory / 1048576" | bc 2>/dev/null || echo "0")
        echo -e "${BLUE}Memory:${RESET} ${memory_mb} MB"
    fi
    
    echo
    echo -e "${CYAN}Dependencies:${RESET}"
    local deps=$(systemctl list-dependencies "$service" --no-pager --plain 2>/dev/null | head -n 10 | tail -n +2)
    echo "$deps" | sed 's/^/  /'
    
    echo
    echo -e "${CYAN}Recent logs:${RESET}"
    journalctl -u "$service" -n 5 --no-pager 2>/dev/null | tail -n +2
}

find_failed_services() {
    echo -e "${RED}${BOLD}Failed Services:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    local failed_services=$(systemctl list-units --failed --no-pager --plain 2>/dev/null | tail -n +2 | head -n -7)
    
    if [ -z "$failed_services" ]; then
        echo -e "${GREEN}No failed services found!${RESET}"
        return
    fi
    
    echo "$failed_services" | while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi
        
        local service=$(echo "$line" | awk '{print $1}')
        echo -e "${RED}● $service${RESET}"
        
        local error=$(journalctl -u "$service" -n 1 --no-pager 2>/dev/null | tail -n 1)
        if [ -n "$error" ]; then
            echo -e "  ${DIM}Last error: ${error:0:70}...${RESET}"
        fi
    done
    
    echo
    echo -e "${YELLOW}Tip: Use 'systemctl reset-failed' to clear failed state${RESET}"
}

monitor_services() {
    local interval=${1:-5}
    
    echo -e "${CYAN}${BOLD}Real-time Service Monitor${RESET}"
    echo -e "${DIM}Refreshing every ${interval} seconds. Press Ctrl+C to exit.${RESET}"
    echo
    
    while true; do
        clear
        echo -e "${CYAN}${BOLD}Service Monitor - $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
        echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
        
        printf "%-30s %-15s %-10s %-10s %s\n" "SERVICE" "STATUS" "CPU%" "MEMORY" "RESTARTS"
        echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
        
        local services=$(systemctl list-units --type=service --state=running --no-pager --plain 2>/dev/null | tail -n +2 | head -n -7)
        
        echo "$services" | while IFS= read -r line; do
            if [ -z "$line" ]; then continue; fi
            
            local service=$(echo "$line" | awk '{print $1}')
            service=${service%.service}
            
            local status=$(get_service_status "$service")
            local memory=$(systemctl show -p MemoryCurrent --value "$service" 2>/dev/null)
            local restarts=$(systemctl show -p NRestarts --value "$service" 2>/dev/null)
            
            local memory_mb="N/A"
            if [ "$memory" != "18446744073709551615" ] && [ -n "$memory" ] && [ "$memory" != "0" ]; then
                memory_mb=$(echo "scale=1; $memory / 1048576" | bc 2>/dev/null || echo "0")
                memory_mb="${memory_mb}M"
            fi
            
            [ -z "$restarts" ] && restarts="0"
            
            printf "%-30s " "$service"
            printf "%s" "$(format_status "$status")"
            printf "%-15s %-10s %-10s %s\n" "" "N/A" "$memory_mb" "$restarts"
        done
        
        echo
        local failed_count=$(systemctl list-units --failed --no-pager --plain 2>/dev/null | tail -n +2 | head -n -7 | wc -l)
        if [ "$failed_count" -gt 0 ]; then
            echo -e "${RED}⚠ $failed_count failed service(s) detected${RESET}"
        fi
        
        sleep "$interval"
    done
}

create_service_template() {
    echo -e "${CYAN}${BOLD}Service Template Generator${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    echo -n "Service name (without .service): "
    read -r service_name
    
    echo -n "Description: "
    read -r description
    
    echo -n "Executable path: "
    read -r exec_path
    
    echo -n "Working directory (optional): "
    read -r working_dir
    
    echo -n "User to run as (optional): "
    read -r run_user
    
    echo -n "Restart policy (no/on-success/on-failure/always) [on-failure]: "
    read -r restart_policy
    [ -z "$restart_policy" ] && restart_policy="on-failure"
    
    local service_file="/tmp/${service_name}.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=$description
After=network.target

[Service]
Type=simple
ExecStart=$exec_path
Restart=$restart_policy
RestartSec=10
EOF
    
    [ -n "$working_dir" ] && echo "WorkingDirectory=$working_dir" >> "$service_file"
    [ -n "$run_user" ] && echo "User=$run_user" >> "$service_file"
    
    cat >> "$service_file" << EOF

[Install]
WantedBy=multi-user.target
EOF
    
    echo
    echo -e "${GREEN}Service file created: $service_file${RESET}"
    echo
    cat "$service_file"
    echo
    echo -n "Install this service? (y/N): "
    read -r install_choice
    
    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        sudo cp "$service_file" "$SYSTEMD_DIR/${service_name}.service"
        sudo systemctl daemon-reload
        echo -e "${GREEN}Service installed successfully${RESET}"
        echo -e "${BLUE}Enable with: systemctl enable ${service_name}${RESET}"
        echo -e "${BLUE}Start with: systemctl start ${service_name}${RESET}"
    fi
}

interactive_menu() {
    while true; do
        print_header
        echo -e "${CYAN}Select an option:${RESET}"
        echo
        echo "  1. List all services"
        echo "  2. List active services"
        echo "  3. Show failed services"
        echo "  4. Service details"
        echo "  5. Manage service (start/stop/enable/disable)"
        echo "  6. Boot time analysis"
        echo "  7. Monitor services (real-time)"
        echo "  8. Create service template"
        echo "  9. Exit"
        echo
        echo -n "Enter your choice (1-9): "
        read -r choice
        
        case "$choice" in
            1)
                list_services all true
                ;;
            2)
                list_services active true
                ;;
            3)
                find_failed_services
                ;;
            4)
                echo -n "Enter service name: "
                read -r service
                show_service_details "$service"
                ;;
            5)
                echo -n "Enter service name: "
                read -r service
                echo "Actions: 1)start 2)stop 3)restart 4)enable 5)disable 6)mask 7)unmask"
                echo -n "Select action: "
                read -r action_choice
                case "$action_choice" in
                    1) manage_service "$service" start ;;
                    2) manage_service "$service" stop ;;
                    3) manage_service "$service" restart ;;
                    4) manage_service "$service" enable ;;
                    5) manage_service "$service" disable ;;
                    6) manage_service "$service" mask ;;
                    7) manage_service "$service" unmask ;;
                    *) echo -e "${RED}Invalid action${RESET}" ;;
                esac
                ;;
            6)
                analyze_boot_services
                ;;
            7)
                monitor_services
                ;;
            8)
                create_service_template
                ;;
            9)
                echo -e "${GREEN}Goodbye!${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${RESET}"
                ;;
        esac
        
        echo
        echo -n "Press Enter to continue..."
        read -r
    done
}

main() {
    if [ $# -eq 0 ]; then
        interactive_menu
    else
        case "$1" in
            list)
                list_services "${2:-all}" true
                ;;
            failed)
                find_failed_services
                ;;
            details)
                if [ -z "${2:-}" ]; then
                    echo -e "${RED}Service name required${RESET}"
                    exit 1
                fi
                show_service_details "$2"
                ;;
            monitor)
                monitor_services "${2:-5}"
                ;;
            boot)
                analyze_boot_services
                ;;
            --help)
                echo "Usage: $0 [COMMAND] [OPTIONS]"
                echo
                echo "Commands:"
                echo "  list [all|active|failed|enabled]  List services"
                echo "  failed                             Show failed services"
                echo "  details SERVICE                    Show service details"
                echo "  monitor [INTERVAL]                 Monitor services"
                echo "  boot                              Analyze boot services"
                echo "  --help                            Show this help"
                echo
                echo "Run without arguments for interactive mode"
                ;;
            *)
                echo -e "${RED}Unknown command: $1${RESET}"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    fi
}

main "$@"