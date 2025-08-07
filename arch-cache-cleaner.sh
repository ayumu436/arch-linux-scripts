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

PACMAN_CACHE="/var/cache/pacman/pkg"
YAY_CACHE="$HOME/.cache/yay"
PARU_CACHE="$HOME/.cache/paru"
MAKEPKG_CACHE="$HOME/.cache/makepkg"
JOURNAL_DIR="/var/log/journal"

KEEP_VERSIONS=2
DRY_RUN=false
VERBOSE=false
CLEAN_ALL=false

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Arch Linux Cache Cleaner                       ║"
    echo "║         Smart package cache management tool             ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

log_message() {
    local level=$1
    shift
    local message="$@"
    
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
        DEBUG)
            [ "$VERBOSE" = true ] && echo -e "${DIM}[DEBUG]${RESET} $message"
            ;;
    esac
}

human_readable_size() {
    local size=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    
    while (( $(echo "$size > 1024" | bc -l) )) && [ $unit -lt 4 ]; do
        size=$(echo "scale=2; $size / 1024" | bc)
        ((unit++))
    done
    
    echo "${size} ${units[$unit]}"
}

get_directory_size() {
    local dir=$1
    if [ -d "$dir" ]; then
        du -sb "$dir" 2>/dev/null | awk '{print $1}'
    else
        echo "0"
    fi
}

analyze_cache() {
    echo -e "${CYAN}${BOLD}Cache Analysis:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    local total_size=0
    local cache_sizes=()
    
    local pacman_size=$(get_directory_size "$PACMAN_CACHE")
    cache_sizes+=("Pacman cache|$PACMAN_CACHE|$pacman_size")
    total_size=$((total_size + pacman_size))
    
    if [ -d "$YAY_CACHE" ]; then
        local yay_size=$(get_directory_size "$YAY_CACHE")
        cache_sizes+=("Yay cache|$YAY_CACHE|$yay_size")
        total_size=$((total_size + yay_size))
    fi
    
    if [ -d "$PARU_CACHE" ]; then
        local paru_size=$(get_directory_size "$PARU_CACHE")
        cache_sizes+=("Paru cache|$PARU_CACHE|$paru_size")
        total_size=$((total_size + paru_size))
    fi
    
    if [ -d "$MAKEPKG_CACHE" ]; then
        local makepkg_size=$(get_directory_size "$MAKEPKG_CACHE")
        cache_sizes+=("Makepkg cache|$MAKEPKG_CACHE|$makepkg_size")
        total_size=$((total_size + makepkg_size))
    fi
    
    local journal_size=$(get_directory_size "$JOURNAL_DIR")
    cache_sizes+=("System journal|$JOURNAL_DIR|$journal_size")
    total_size=$((total_size + journal_size))
    
    local home_cache_size=$(get_directory_size "$HOME/.cache")
    cache_sizes+=("User cache|$HOME/.cache|$home_cache_size")
    
    for cache_info in "${cache_sizes[@]}"; do
        IFS='|' read -r name path size <<< "$cache_info"
        local human_size=$(human_readable_size "$size")
        
        printf "%-20s %15s" "$name:" "$human_size"
        
        if [ "$size" -gt 0 ]; then
            local percentage=$((size * 100 / total_size))
            echo -n "  ["
            local bar_length=20
            local filled=$((percentage * bar_length / 100))
            for ((i=0; i<filled; i++)); do echo -n "█"; done
            for ((i=filled; i<bar_length; i++)); do echo -n "░"; done
            echo "] $percentage%"
        else
            echo
        fi
    done
    
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    echo -e "${BOLD}Total cache size: $(human_readable_size "$total_size")${RESET}"
}

analyze_pacman_cache() {
    echo -e "${CYAN}${BOLD}Pacman Cache Details:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    if [ ! -d "$PACMAN_CACHE" ]; then
        log_message WARNING "Pacman cache directory not found"
        return
    fi
    
    cd "$PACMAN_CACHE"
    
    local total_packages=$(ls -1 *.pkg.tar* 2>/dev/null | wc -l)
    local unique_packages=$(ls -1 *.pkg.tar* 2>/dev/null | sed 's/-[0-9].*//' | sort -u | wc -l)
    local total_size=$(du -sb . | awk '{print $1}')
    
    echo -e "${BLUE}Total packages:${RESET} $total_packages"
    echo -e "${BLUE}Unique packages:${RESET} $unique_packages"
    echo -e "${BLUE}Total size:${RESET} $(human_readable_size "$total_size")"
    
    echo
    echo -e "${YELLOW}Packages with most versions:${RESET}"
    ls -1 *.pkg.tar* 2>/dev/null | sed 's/-[0-9].*//' | sort | uniq -c | sort -rn | head -5 | while read count pkg; do
        local pkg_size=$(du -cb ${pkg}-*.pkg.tar* 2>/dev/null | tail -1 | awk '{print $1}')
        echo "  $count versions - $pkg ($(human_readable_size "$pkg_size"))"
    done
    
    echo
    echo -e "${YELLOW}Largest packages:${RESET}"
    ls -lhS *.pkg.tar* 2>/dev/null | head -5 | awk '{print "  " $5 " - " $9}'
    
    local orphan_count=$(pacman -Qtdq 2>/dev/null | wc -l)
    if [ "$orphan_count" -gt 0 ]; then
        echo
        echo -e "${YELLOW}Orphaned packages installed:${RESET} $orphan_count"
        echo -e "${DIM}Tip: Remove with 'pacman -Rns \$(pacman -Qtdq)'${RESET}"
    fi
}

clean_pacman_cache() {
    local keep=$1
    
    echo -e "${BLUE}Cleaning Pacman cache (keeping $keep versions)...${RESET}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN - No files will be deleted${RESET}"
        paccache -drvk"$keep" 2>/dev/null || true
    else
        if command -v paccache &> /dev/null; then
            local before_size=$(get_directory_size "$PACMAN_CACHE")
            
            if paccache -rvk"$keep"; then
                local after_size=$(get_directory_size "$PACMAN_CACHE")
                local freed=$((before_size - after_size))
                log_message SUCCESS "Freed $(human_readable_size "$freed") from Pacman cache"
            else
                log_message ERROR "Failed to clean Pacman cache"
            fi
            
            if [ "$keep" -eq 0 ]; then
                echo -e "${BLUE}Removing uninstalled packages...${RESET}"
                paccache -ruvk0
            fi
        else
            log_message WARNING "paccache not found. Install pacman-contrib package"
        fi
    fi
}

clean_aur_cache() {
    echo -e "${BLUE}Cleaning AUR helper caches...${RESET}"
    
    local freed_total=0
    
    for cache_dir in "$YAY_CACHE" "$PARU_CACHE"; do
        if [ -d "$cache_dir" ]; then
            local helper_name=$(basename "$cache_dir")
            local before_size=$(get_directory_size "$cache_dir")
            
            if [ "$DRY_RUN" = true ]; then
                echo -e "${YELLOW}DRY RUN - Would clean $helper_name cache${RESET}"
                find "$cache_dir" -type d -name "pkg" -exec ls -lh {} \; 2>/dev/null | head -10
            else
                find "$cache_dir" -type d -name "src" -exec rm -rf {} + 2>/dev/null || true
                
                find "$cache_dir" -type f -name "*.pkg.tar*" -mtime +30 -delete 2>/dev/null || true
                
                local after_size=$(get_directory_size "$cache_dir")
                local freed=$((before_size - after_size))
                freed_total=$((freed_total + freed))
                
                if [ "$freed" -gt 0 ]; then
                    log_message SUCCESS "Freed $(human_readable_size "$freed") from $helper_name cache"
                fi
            fi
        fi
    done
    
    if [ "$freed_total" -gt 0 ]; then
        log_message SUCCESS "Total freed from AUR caches: $(human_readable_size "$freed_total")"
    fi
}

clean_user_cache() {
    echo -e "${BLUE}Cleaning user cache...${RESET}"
    
    local cache_dirs=(
        "$HOME/.cache/thumbnails"
        "$HOME/.cache/mozilla"
        "$HOME/.cache/chromium"
        "$HOME/.cache/google-chrome"
        "$HOME/.cache/electron"
        "$HOME/.cache/pip"
        "$HOME/.cache/go-build"
        "$HOME/.cache/yarn"
        "$HOME/.cache/npm"
    )
    
    local freed_total=0
    
    for cache_dir in "${cache_dirs[@]}"; do
        if [ -d "$cache_dir" ]; then
            local dir_name=$(basename "$cache_dir")
            local before_size=$(get_directory_size "$cache_dir")
            
            if [ "$before_size" -gt $((100 * 1024 * 1024)) ]; then
                echo -e "  Cleaning $dir_name cache ($(human_readable_size "$before_size"))..."
                
                if [ "$DRY_RUN" = true ]; then
                    echo -e "${YELLOW}  DRY RUN - Would clean $dir_name${RESET}"
                else
                    case "$dir_name" in
                        thumbnails)
                            find "$cache_dir" -type f -atime +7 -delete 2>/dev/null || true
                            ;;
                        mozilla|chromium|google-chrome)
                            find "$cache_dir" -name "Cache" -type d -exec rm -rf {} + 2>/dev/null || true
                            ;;
                        *)
                            find "$cache_dir" -type f -atime +30 -delete 2>/dev/null || true
                            ;;
                    esac
                    
                    local after_size=$(get_directory_size "$cache_dir")
                    local freed=$((before_size - after_size))
                    freed_total=$((freed_total + freed))
                fi
            fi
        fi
    done
    
    if [ "$freed_total" -gt 0 ]; then
        log_message SUCCESS "Freed $(human_readable_size "$freed_total") from user caches"
    fi
}

clean_journal() {
    echo -e "${BLUE}Cleaning system journal...${RESET}"
    
    local before_size=$(get_directory_size "$JOURNAL_DIR")
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN - Would vacuum journal to 100M${RESET}"
        journalctl --disk-usage
    else
        if sudo journalctl --vacuum-size=100M; then
            local after_size=$(get_directory_size "$JOURNAL_DIR")
            local freed=$((before_size - after_size))
            
            if [ "$freed" -gt 0 ]; then
                log_message SUCCESS "Freed $(human_readable_size "$freed") from system journal"
            fi
        else
            log_message ERROR "Failed to clean system journal"
        fi
    fi
}

clean_orphans() {
    echo -e "${BLUE}Checking for orphaned packages...${RESET}"
    
    local orphans=$(pacman -Qtdq 2>/dev/null)
    
    if [ -z "$orphans" ]; then
        log_message INFO "No orphaned packages found"
        return
    fi
    
    echo -e "${YELLOW}Found orphaned packages:${RESET}"
    echo "$orphans" | while read pkg; do
        local size=$(pacman -Qi "$pkg" 2>/dev/null | grep "Installed Size" | awk '{print $4, $5}')
        echo "  • $pkg ($size)"
    done
    
    if [ "$DRY_RUN" = false ]; then
        echo
        echo -n "Remove orphaned packages? (y/N): "
        read -r choice
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if sudo pacman -Rns $(pacman -Qtdq) 2>/dev/null; then
                log_message SUCCESS "Orphaned packages removed"
            else
                log_message ERROR "Failed to remove orphaned packages"
            fi
        fi
    fi
}

optimize_databases() {
    echo -e "${BLUE}Optimizing package databases...${RESET}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN - Would optimize databases${RESET}"
    else
        echo "  Optimizing pacman database..."
        if sudo pacman-optimize 2>/dev/null || sudo pacman -Sc --noconfirm 2>/dev/null; then
            log_message SUCCESS "Pacman database optimized"
        fi
        
        echo "  Updating file database..."
        if sudo updatedb 2>/dev/null; then
            log_message SUCCESS "File database updated"
        fi
    fi
}

smart_clean() {
    local aggressive=${1:-false}
    
    echo -e "${CYAN}${BOLD}Starting Smart Clean...${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    local before_total=0
    for dir in "$PACMAN_CACHE" "$YAY_CACHE" "$PARU_CACHE" "$HOME/.cache" "$JOURNAL_DIR"; do
        [ -d "$dir" ] && before_total=$((before_total + $(get_directory_size "$dir")))
    done
    
    if [ "$aggressive" = true ]; then
        KEEP_VERSIONS=1
        clean_pacman_cache 1
    else
        clean_pacman_cache "$KEEP_VERSIONS"
    fi
    
    clean_aur_cache
    clean_user_cache
    clean_journal
    
    if [ "$aggressive" = true ]; then
        clean_orphans
        optimize_databases
    fi
    
    local after_total=0
    for dir in "$PACMAN_CACHE" "$YAY_CACHE" "$PARU_CACHE" "$HOME/.cache" "$JOURNAL_DIR"; do
        [ -d "$dir" ] && after_total=$((after_total + $(get_directory_size "$dir")))
    done
    
    local total_freed=$((before_total - after_total))
    
    echo
    echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}Total space freed: $(human_readable_size "$total_freed")${RESET}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
}

schedule_cleaning() {
    echo -e "${CYAN}${BOLD}Setting up automatic cache cleaning...${RESET}"
    
    local service_file="/etc/systemd/system/arch-cache-clean.service"
    local timer_file="/etc/systemd/system/arch-cache-clean.timer"
    local script_path=$(readlink -f "$0")
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Arch Linux Cache Cleaner
After=network.target

[Service]
Type=oneshot
ExecStart=$script_path --auto-clean
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    sudo tee "$timer_file" > /dev/null << EOF
[Unit]
Description=Run Arch Cache Cleaner weekly
Requires=arch-cache-clean.service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable arch-cache-clean.timer
    sudo systemctl start arch-cache-clean.timer
    
    log_message SUCCESS "Automatic cleaning scheduled weekly"
    echo -e "${BLUE}Check status with: systemctl status arch-cache-clean.timer${RESET}"
}

interactive_menu() {
    while true; do
        print_header
        analyze_cache
        echo
        echo -e "${CYAN}Select an option:${RESET}"
        echo
        echo "  1. Analyze cache details"
        echo "  2. Smart clean (safe)"
        echo "  3. Aggressive clean"
        echo "  4. Clean specific cache"
        echo "  5. Remove orphaned packages"
        echo "  6. Schedule automatic cleaning"
        echo "  7. Dry run (preview changes)"
        echo "  8. Exit"
        echo
        echo -n "Enter your choice (1-8): "
        read -r choice
        
        case "$choice" in
            1)
                analyze_pacman_cache
                ;;
            2)
                smart_clean false
                ;;
            3)
                echo -e "${YELLOW}Warning: Aggressive cleaning will remove more files${RESET}"
                echo -n "Continue? (y/N): "
                read -r confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && smart_clean true
                ;;
            4)
                echo "Select cache to clean:"
                echo "  1. Pacman cache"
                echo "  2. AUR helper caches"
                echo "  3. User cache"
                echo "  4. System journal"
                echo -n "Choice: "
                read -r cache_choice
                case "$cache_choice" in
                    1) clean_pacman_cache "$KEEP_VERSIONS" ;;
                    2) clean_aur_cache ;;
                    3) clean_user_cache ;;
                    4) clean_journal ;;
                esac
                ;;
            5)
                clean_orphans
                ;;
            6)
                schedule_cleaning
                ;;
            7)
                DRY_RUN=true
                smart_clean false
                DRY_RUN=false
                ;;
            8)
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
            --analyze)
                analyze_cache
                analyze_pacman_cache
                ;;
            --clean)
                smart_clean false
                ;;
            --aggressive)
                smart_clean true
                ;;
            --auto-clean)
                VERBOSE=false
                smart_clean false
                ;;
            --dry-run)
                DRY_RUN=true
                smart_clean false
                ;;
            --schedule)
                schedule_cleaning
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --analyze      Analyze cache usage"
                echo "  --clean        Perform safe cleaning"
                echo "  --aggressive   Perform aggressive cleaning"
                echo "  --auto-clean   Silent mode for automation"
                echo "  --dry-run      Preview changes without deleting"
                echo "  --schedule     Set up automatic cleaning"
                echo "  --help         Show this help message"
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