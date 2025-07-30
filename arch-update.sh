#!/usr/bin/env bash
# arch-update.sh - The Intelligent System Updater
#
# DESCRIPTION:
# A revolutionary script for Arch Linux that automates system updates,
# including mirror list refreshing, checking Arch News, handling .pacnew files,
# cleaning up the system, and updating AUR packages.
#
# DEPENDENCIES:
# - pacman-contrib (for paccache)
#   sudo pacman -S --needed pacman-contrib
# - reflector
#   sudo pacman -S --needed reflector
# - An AUR helper (e.g., yay, paru) is recommended for AUR updates.
#
# USAGE:
# sudo ./arch-update.sh

set -euo pipefail

# --- Color Codes ---
# Using tput for compatibility and to avoid hardcoded escape sequences
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
BLUE=$(tput setaf 4)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# --- Helper Functions ---
log() {
    echo "${BLUE}${BOLD}[INFO]${RESET} $1"
}

warn() {
    echo "${YELLOW}${BOLD}[WARN]${RESET} $1"
}

error() {
    echo "${RED}${BOLD}[ERROR]${RESET} $1" >&2
    exit 1
}

step() {
    echo -e "\n${GREEN}${BOLD}>>> $1${RESET}"
}

# --- Pre-flight Checks ---
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be run as root. Please use sudo."
    fi
}

check_internet() {
    step "Checking for internet connectivity..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        error "No internet connection detected. Please connect to the internet and try again."
    fi
    log "Internet connection is active."
}

# --- Update Functions ---
refresh_mirrors() {
    step "Refreshing Pacman mirror list with Reflector..."
    log "Backing up current mirrorlist to /etc/pacman.d/mirrorlist.bak"
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    
    # Using reflector to get the 20 most recently synchronized HTTPS mirrors from your region, sorting by speed.
    # You can change the countries to better suit your location.
    log "Getting best mirrors for Germany and France. This may take a moment..."
    reflector --country Germany,France --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
    log "Mirrorlist updated successfully."
}

check_arch_news() {
    step "Checking for Arch Linux news..."
    # We fetch the news feed. A simple check for recent items.
    if ! news=$(curl -s "https://archlinux.org/news/" | grep -A 3 \'\'\'class="news-feed-item"\'\'\'); then
        warn "Could not fetch Arch news. Continuing without it."
        return
    fi

    if [[ -n "$news" ]]; then
        log "Latest Arch News (please review for manual interventions):"
        # Use sed to strip HTML tags for readability
        echo "$news" | sed -e \'\'\'s/<[^>]*>//g\'\'\' | sed \'\'\'/^\s*$/d\'\'\' | head -n 15
        read -p "Press [Enter] to continue, or [Ctrl+C] to abort."
    else
        log "No recent news found."
    fi
}

system_upgrade() {
    step "Performing full system upgrade (pacman -Syu)..."
    pacman -Syu --noconfirm
    log "System upgrade complete."
}

handle_pacnew() {
    step "Checking for .pacnew files..."
    pacnew_files=$(find /etc -type f -name "*.pacnew")
    if [[ -z "$pacnew_files" ]]; then
        log "No .pacnew files found."
        return
    fi

    warn "Found .pacnew files. Manual intervention is required."
    for file in $pacnew_files; do
        local orig_file="${file%.pacnew}"
        echo "---"
        log "Found: $file"
        log "Original: $orig_file"
        
        # Show a diff, preferably with color
        if command -v colordiff &>/dev/null; then
            colordiff -u "$orig_file" "$file" || true
        else
            diff -u "$orig_file" "$file" || true
        fi

        PS3="Choose an action for $file: "
        options=("Overwrite with .pacnew" "Discard .pacnew" "Open in editor (vimdiff)" "Skip")
        select opt in "${options[@]}"; do
            case $opt in
                "Overwrite with .pacnew")
                    mv "$file" "$orig_file"
                    log "$orig_file has been overwritten."
                    break
                    ;;
                "Discard .pacnew")
                    rm "$file"
                    log "$file has been discarded."
                    break
                    ;;
                "Open in editor (vimdiff)")
                    # Use a diff editor, vimdiff is common
                    vimdiff "$orig_file" "$file"
                    log "Manual editing finished. You may need to resolve the files yourself."
                    break
                    ;;
                "Skip")
                    log "Skipping for now. Please resolve manually later."
                    break
                    ;;
                *) echo "Invalid option $REPLY";;
            esac
        done
    done
}

cleanup_system() {
    step "Cleaning up the system..."
    
    # Remove orphaned packages
    log "Removing orphaned packages..."
    if orphans=$(pacman -Qtdq); then
        if [[ -n "$orphans" ]]; then
            pacman -Rns --noconfirm $orphans
            log "Removed orphan packages."
        else
            log "No orphaned packages to remove."
        fi
    else
        log "No orphaned packages to remove."
    fi

    # Clean pacman cache
    log "Cleaning pacman cache (keeping last 2 versions)..."
    paccache -rk2
    log "Cache cleaned."
}

update_aur() {
    step "Checking for AUR helper and updating AUR packages..."
    local aur_helper=""
    if command -v paru &>/dev/null; then
        aur_helper="paru"
    elif command -v yay &>/dev/null; then
        aur_helper="yay"
    fi

    if [[ -n "$aur_helper" ]]; then
        log "Found AUR helper: $aur_helper. Running AUR upgrade..."
        # We need to run this as the regular user, not root
        local regular_user
        regular_user=$(logname)
        sudo -u "$regular_user" "$aur_helper" -Sua --noconfirm
        log "AUR upgrade complete."
    else
        warn "No AUR helper (yay or paru) found. Skipping AUR updates."
    fi
}


# --- Main Execution ---
main() {
    check_root
    log "Starting the intelligent Arch Linux updater."
    
    check_internet
    refresh_mirrors
    check_arch_news
    system_upgrade
    handle_pacnew
    cleanup_system
    update_aur

    step "System update process finished successfully!"
    log "Have a great day!"
}

main "$@"
