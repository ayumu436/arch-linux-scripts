#!/usr/bin/env bash
# arch-snapshot.sh - Pre-Change System Snapshot
#
# DESCRIPTION:
# A safety tool that captures the current state of the system before a user
# makes potentially risky changes. It backs up package lists, systemd services,
# hardware configuration, and the pacman database.
#
# DEPENDENCIES:
# - An AUR helper (e.g., yay, paru) is recommended for a complete package list.
#
# USAGE:
# ./arch-snapshot.sh
# This script can be run as a normal user, but will prompt for sudo to
# back up the pacman database.

set -euo pipefail

# --- Color Codes ---
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
BLUE=$(tput setaf 4)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# --- Helper Functions ---
log() {
    echo "${BLUE}${BOLD}[INFO]${RESET} $1"
}

ok() {
    echo "${GREEN}${BOLD}[OK]${RESET} $1"
}

step() {
    echo -e "\n${GREEN}${BOLD}>>> $1${RESET}"
}

# --- Main Logic ---
main() {
    log "Starting system snapshot..."

    # Define snapshot directory in the user's home
    local user_home
    user_home=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    
    local snapshot_base_dir="$user_home/snapshots"
    local timestamp
    timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local snapshot_dir="$snapshot_base_dir/$timestamp"

    mkdir -p "$snapshot_dir"
    log "Snapshot will be saved to: $snapshot_dir"

    # 1. Get list of explicitly installed packages
    step "Capturing installed package lists..."
    pacman -Qen > "$snapshot_dir/packages_pacman.list"
    log "Saved native package list."

    local aur_helper=""
    if command -v paru &>/dev/null; then
        aur_helper="paru"
    elif command -v yay &>/dev/null; then
        aur_helper="yay"
    fi

    if [[ -n "$aur_helper" ]]; then
        # Run as the original user to avoid issues with AUR helper config
        sudo -u "${SUDO_USER:-$USER}" "$aur_helper" -Qen > "$snapshot_dir/packages_aur.list"
        log "Saved AUR package list using $aur_helper."
    else
        log "No AUR helper found, skipping AUR package list."
    fi
    
    # 2. Backup the pacman database
    step "Backing up pacman database..."
    # Use sudo to elevate privileges just for this command if not already root
    if [[ "$EUID" -ne 0 ]]; then
        log "Sudo access is required to back up the pacman database."
    fi
    sudo tar -czf "$snapshot_dir/pacman_db.tar.gz" /var/lib/pacman/local
    log "Pacman database backed up."

    # 3. Get snapshot of active systemd services
    step "Capturing systemd service status..."
    systemctl list-units --state=enabled > "$snapshot_dir/services_enabled.list"
    systemctl list-units --state=running > "$snapshot_dir/services_running.list"
    log "Saved enabled and running services."

    # 4. Capture kernel and hardware info
    step "Capturing kernel and hardware information..."
    uname -a > "$snapshot_dir/kernel_info.txt"
    lspci -k > "$snapshot_dir/hardware_drivers.txt"
    log "Saved kernel and hardware info."

    # Set correct ownership for the created directory
    if [[ -n "${SUDO_USER}" ]]; then
        chown -R "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$snapshot_dir"
    fi

    echo
    ok "Snapshot created successfully!"
    log "Location: $snapshot_dir"
}

main "$@"
