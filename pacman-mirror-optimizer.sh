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

MIRRORLIST="/etc/pacman.d/mirrorlist"
BACKUP_DIR="/etc/pacman.d/mirrorlist-backups"
TEMP_FILE="/tmp/mirrorlist.tmp"
LOG_FILE="/var/log/pacman-mirror-optimizer.log"
COUNTRY_CODE=""
PROTOCOL="https"
MAX_MIRRORS=10
TEST_PACKAGE="core/pacman"

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Arch Linux Pacman Mirror Optimizer             ║"
    echo "║         Automatically rank and optimize mirrors         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

log_message() {
    local level=$1
    shift
    local message="$@"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        ERROR)
            echo -e "${RED}[ERROR]${RESET} $message" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${RESET} $message"
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${RESET} $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${RESET} $message"
            ;;
    esac
}

check_dependencies() {
    local deps=("reflector" "curl" "pacman-contrib")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null && ! pacman -Qi "$dep" &> /dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_message WARNING "Missing dependencies: ${missing[*]}"
        echo -e "${YELLOW}Installing missing dependencies...${RESET}"
        sudo pacman -S --noconfirm "${missing[@]}" || {
            log_message ERROR "Failed to install dependencies"
            exit 1
        }
    fi
}

backup_mirrorlist() {
    if [ ! -d "$BACKUP_DIR" ]; then
        sudo mkdir -p "$BACKUP_DIR"
    fi
    
    local backup_file="$BACKUP_DIR/mirrorlist-$(date +%Y%m%d-%H%M%S).bak"
    sudo cp "$MIRRORLIST" "$backup_file"
    log_message INFO "Mirrorlist backed up to $backup_file"
    
    local backup_count=$(find "$BACKUP_DIR" -name "mirrorlist-*.bak" | wc -l)
    if [ "$backup_count" -gt 10 ]; then
        log_message INFO "Removing old backups (keeping last 10)"
        find "$BACKUP_DIR" -name "mirrorlist-*.bak" -type f -printf '%T@ %p\n' | \
            sort -n | head -n -10 | cut -d' ' -f2- | xargs -r sudo rm
    fi
}

detect_country() {
    echo -e "${BLUE}Detecting your location...${RESET}"
    local country=$(curl -s https://ipapi.co/country_code/ 2>/dev/null || echo "")
    
    if [ -n "$country" ]; then
        COUNTRY_CODE="$country"
        log_message INFO "Detected country: $COUNTRY_CODE"
        echo -e "${GREEN}Detected country: ${BOLD}$COUNTRY_CODE${RESET}"
    else
        log_message WARNING "Could not detect country automatically"
        echo -e "${YELLOW}Could not detect country automatically${RESET}"
        echo -n "Enter your country code (e.g., US, GB, DE) or press Enter to skip: "
        read -r country_input
        if [ -n "$country_input" ]; then
            COUNTRY_CODE="$country_input"
        fi
    fi
}

test_mirror_speed() {
    local mirror=$1
    local url="${mirror}${TEST_PACKAGE}"
    
    local speed=$(curl -o /dev/null -s -w '%{speed_download}' --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "0")
    
    speed=$(echo "$speed" | awk '{printf "%.0f", $1}')
    echo "$speed"
}

rank_mirrors_reflector() {
    echo -e "${BLUE}Ranking mirrors using reflector...${RESET}"
    
    local reflector_args=(
        "--save" "$TEMP_FILE"
        "--protocol" "$PROTOCOL"
        "--latest" "20"
        "--sort" "rate"
        "--number" "$MAX_MIRRORS"
        "--threads" "5"
    )
    
    if [ -n "$COUNTRY_CODE" ]; then
        reflector_args+=("--country" "$COUNTRY_CODE")
    fi
    
    if sudo reflector "${reflector_args[@]}" 2>/dev/null; then
        log_message SUCCESS "Mirrors ranked successfully with reflector"
        return 0
    else
        log_message ERROR "Reflector failed to rank mirrors"
        return 1
    fi
}

rank_mirrors_manual() {
    echo -e "${BLUE}Testing mirror speeds manually...${RESET}"
    
    declare -A mirror_speeds
    local mirrors=()
    
    while IFS= read -r line; do
        if [[ $line =~ ^Server[[:space:]]*=[[:space:]]*(.*) ]]; then
            mirrors+=("${BASH_REMATCH[1]}")
        fi
    done < "$MIRRORLIST"
    
    if [ ${#mirrors[@]} -eq 0 ]; then
        log_message ERROR "No mirrors found in mirrorlist"
        return 1
    fi
    
    echo -e "${CYAN}Testing ${#mirrors[@]} mirrors...${RESET}"
    local count=0
    
    for mirror in "${mirrors[@]}"; do
        ((count++))
        echo -ne "\rTesting mirror $count/${#mirrors[@]}"
        
        local speed=$(test_mirror_speed "$mirror")
        if [ "$speed" -gt 0 ]; then
            mirror_speeds["$mirror"]=$speed
        fi
    done
    echo
    
    {
        echo "##"
        echo "## Arch Linux mirrorlist - Optimized on $(date)"
        echo "##"
        echo
        
        for mirror in $(for m in "${!mirror_speeds[@]}"; do
            echo "${mirror_speeds[$m]} $m"
        done | sort -rn | head -n "$MAX_MIRRORS" | cut -d' ' -f2-); do
            echo "Server = $mirror"
        done
    } | sudo tee "$TEMP_FILE" > /dev/null
    
    log_message SUCCESS "Manual mirror ranking completed"
    return 0
}

optimize_mirrors() {
    echo -e "${CYAN}${BOLD}Starting mirror optimization...${RESET}"
    
    backup_mirrorlist
    
    if ! rank_mirrors_reflector; then
        echo -e "${YELLOW}Reflector failed, falling back to manual testing...${RESET}"
        if ! rank_mirrors_manual; then
            log_message ERROR "Both ranking methods failed"
            return 1
        fi
    fi
    
    if [ -f "$TEMP_FILE" ] && [ -s "$TEMP_FILE" ]; then
        sudo cp "$TEMP_FILE" "$MIRRORLIST"
        sudo rm -f "$TEMP_FILE"
        log_message SUCCESS "Mirrorlist updated successfully"
        echo -e "${GREEN}${BOLD}Mirrorlist optimized successfully!${RESET}"
        
        echo -e "\n${CYAN}Top mirrors in your new mirrorlist:${RESET}"
        head -n 10 "$MIRRORLIST" | grep "^Server" | sed 's/Server = /  • /'
        
        echo -e "\n${BLUE}Updating package database...${RESET}"
        if sudo pacman -Sy; then
            log_message SUCCESS "Package database updated"
            echo -e "${GREEN}Package database updated successfully${RESET}"
        else
            log_message WARNING "Failed to update package database"
            echo -e "${YELLOW}Warning: Failed to update package database${RESET}"
        fi
    else
        log_message ERROR "Failed to generate new mirrorlist"
        echo -e "${RED}Failed to generate new mirrorlist${RESET}"
        return 1
    fi
}

restore_backup() {
    echo -e "${CYAN}Available backups:${RESET}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_message ERROR "No backup directory found"
        echo -e "${RED}No backups found${RESET}"
        return 1
    fi
    
    local backups=($(find "$BACKUP_DIR" -name "mirrorlist-*.bak" -type f | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        log_message ERROR "No backup files found"
        echo -e "${RED}No backup files found${RESET}"
        return 1
    fi
    
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local date=$(basename "$backup" | sed 's/mirrorlist-\(.*\)\.bak/\1/')
        echo "  $((i+1)). $date"
    done
    
    echo -n "Select backup to restore (1-${#backups[@]}) or 'q' to quit: "
    read -r choice
    
    if [[ "$choice" == "q" ]]; then
        return 0
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ]; then
        local selected_backup="${backups[$((choice-1))]}"
        
        backup_mirrorlist
        
        sudo cp "$selected_backup" "$MIRRORLIST"
        log_message SUCCESS "Restored backup: $selected_backup"
        echo -e "${GREEN}Backup restored successfully${RESET}"
        
        echo -e "${BLUE}Updating package database...${RESET}"
        sudo pacman -Sy
    else
        echo -e "${RED}Invalid selection${RESET}"
        return 1
    fi
}

benchmark_current() {
    echo -e "${CYAN}Benchmarking current mirrorlist...${RESET}"
    
    local servers=($(grep "^Server" "$MIRRORLIST" | head -n 5 | sed 's/Server = //'))
    
    if [ ${#servers[@]} -eq 0 ]; then
        echo -e "${RED}No servers found in mirrorlist${RESET}"
        return 1
    fi
    
    echo -e "${BLUE}Testing top ${#servers[@]} mirrors:${RESET}\n"
    
    for i in "${!servers[@]}"; do
        local server="${servers[$i]}"
        echo -e "${CYAN}Mirror $((i+1)): ${RESET}$(echo "$server" | sed 's|.*/||' | sed 's|/.*||')"
        
        local speed=$(test_mirror_speed "$server")
        
        if [ "$speed" -gt 0 ]; then
            local speed_mb=$(echo "scale=2; $speed / 1048576" | bc)
            echo -e "  Speed: ${GREEN}${speed_mb} MB/s${RESET}"
        else
            echo -e "  Speed: ${RED}Failed to connect${RESET}"
        fi
        
        local ping_time=$(ping -c 1 -W 2 "$(echo "$server" | sed 's|.*://||' | sed 's|/.*||')" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/')
        if [ -n "$ping_time" ]; then
            echo -e "  Ping:  ${GREEN}${ping_time} ms${RESET}"
        else
            echo -e "  Ping:  ${YELLOW}N/A${RESET}"
        fi
        echo
    done
}

interactive_menu() {
    while true; do
        print_header
        echo -e "${CYAN}Select an option:${RESET}"
        echo
        echo "  1. Optimize mirrors (automatic)"
        echo "  2. Optimize mirrors (select country)"
        echo "  3. Benchmark current mirrors"
        echo "  4. Restore from backup"
        echo "  5. View current mirrorlist"
        echo "  6. Exit"
        echo
        echo -n "Enter your choice (1-6): "
        read -r choice
        
        case "$choice" in
            1)
                detect_country
                optimize_mirrors
                ;;
            2)
                echo -n "Enter country code (e.g., US, GB, DE): "
                read -r COUNTRY_CODE
                optimize_mirrors
                ;;
            3)
                benchmark_current
                ;;
            4)
                restore_backup
                ;;
            5)
                echo -e "${CYAN}Current mirrorlist:${RESET}"
                grep "^Server" "$MIRRORLIST" | head -n 10 | nl
                ;;
            6)
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
    if [ "$EUID" -ne 0 ] && [ $# -eq 0 ]; then
        echo -e "${YELLOW}This script requires root privileges. Re-running with sudo...${RESET}"
        exec sudo "$0" "$@"
    fi
    
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    
    check_dependencies
    
    if [ $# -eq 0 ]; then
        interactive_menu
    else
        case "$1" in
            --optimize)
                detect_country
                optimize_mirrors
                ;;
            --benchmark)
                benchmark_current
                ;;
            --restore)
                restore_backup
                ;;
            --country)
                if [ -n "${2:-}" ]; then
                    COUNTRY_CODE="$2"
                    optimize_mirrors
                else
                    echo -e "${RED}Country code required${RESET}"
                    exit 1
                fi
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --optimize      Automatically optimize mirrors"
                echo "  --benchmark     Benchmark current mirrors"
                echo "  --restore       Restore from backup"
                echo "  --country CODE  Optimize for specific country"
                echo "  --help          Show this help message"
                echo
                echo "Run without options for interactive mode"
                ;;
            *)
                echo -e "${RED}Unknown option: $1${RESET}"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    fi
}

main "$@"