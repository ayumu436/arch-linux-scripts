#!/usr/bin/env bash
# btrfs-snapshot-manager.sh - The Btrfs Time Machine
#
# DESCRIPTION:
# A powerful, interactive script for managing Btrfs snapshots, making it easy
# to create, delete, and list system snapshots. Includes a helper to create
# an automatic pacman hook for pre-upgrade snapshots.
#
# DEPENDENCIES:
# - btrfs-progs
# - A Btrfs filesystem mounted at /. 
# - A standard subvolume layout (@ for root, @home for home) is assumed.
#
# USAGE:
# sudo ./btrfs-snapshot-manager.sh <command>
#
# COMMANDS:
#   create <description> - Create a new read-only snapshot of @ and @home.
#   list                 - List all existing snapshots.
#   delete               - Interactively delete one or more snapshots.
#   create-hook          - Create a pacman hook to auto-snapshot on upgrades.

set -euo pipefail

# --- Configuration ---
# The mount point for your top-level Btrfs volume.
# This is where your subvolumes (like @ and @home) and snapshots are.
BTRFS_TOP_LEVEL="/btrfs"
# The directory within the top-level volume to store snapshots.
SNAPSHOT_DIR="${BTRFS_TOP_LEVEL}/snapshots"

# --- Color Codes ---
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

error() {
    echo "${RED}${BOLD}[ERROR]${RESET} $1" >&2
    exit 1
}

ok() {
    echo "${GREEN}${BOLD}[OK]${RESET} $1"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be run as root."
    fi
}

pre_flight_checks() {
    if ! command -v btrfs &>/dev/null; then
        error "'btrfs-progs' is not installed. Please install it first."
    fi
    if [[ $(findmnt -n -o FSTYPE /) != "btrfs" ]]; then
        error "The root filesystem (/) is not Btrfs."
    fi
    if [[ ! -d "$BTRFS_TOP_LEVEL" ]]; then
        error "Btrfs top-level directory '$BTRFS_TOP_LEVEL' not found. Please configure it correctly."
    fi
    mkdir -p "$SNAPSHOT_DIR"
}

# --- Core Functions ---

create_snapshot() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local desc="$1"
    local snap_path_root="${SNAPSHOT_DIR}/@_${timestamp}_${desc}"
    local snap_path_home="${SNAPSHOT_DIR}/@home_${timestamp}_${desc}"

    log "Creating read-only snapshot for @ -> ${snap_path_root}"
    btrfs subvolume snapshot -r "${BTRFS_TOP_LEVEL}/@" "$snap_path_root"

    if [[ -d "${BTRFS_TOP_LEVEL}/@home" ]]; then
        log "Creating read-only snapshot for @home -> ${snap_path_home}"
        btrfs subvolume snapshot -r "${BTRFS_TOP_LEVEL}/@home" "$snap_path_home"
    fi
    ok "Snapshots created successfully."
}

list_snapshots() {
    log "Listing snapshots in ${SNAPSHOT_DIR}"
    # Use ls to get a simple, clean list. btrfs subvolume list is too verbose here.
    ls -l "$SNAPSHOT_DIR" | grep '^d'
}

delete_snapshots() {
    log "Select snapshots to delete (use space to mark, enter to confirm)."
    local options
    mapfile -t options < <(find "$SNAPSHOT_DIR" -maxdepth 1 -mindepth 1 -type d -printf "%f\n")
    if [[ ${#options[@]} -eq 0 ]]; then
        error "No snapshots found to delete."
    fi

    # A simple multi-select menu
    local selected=()
    for i in "${!options[@]}"; do selected+=("off"); done
    while true; do
        clear
        echo "Use ARROW keys, SPACE to toggle, ENTER to confirm."
        for i in "${!options[@]}"; do
            if [[ ${selected[i]} == "on" ]]; then
                echo "[x] ${options[i]}"
            else
                echo "[ ] ${options[i]}"
            fi
        done

        read -rsn1 key
        # This is a simplified selector, real implementation would be more complex
        # For this script, we will use a simpler tool: gum or fzf if available
        if command -v fzf &>/dev/null; then
            local to_delete
            mapfile -t to_delete < <(printf "%s\n" "${options[@]}" | fzf -m --prompt="Select snapshots to DELETE > ")
            if [[ ${#to_delete[@]} -gt 0 ]]; then
                for snap in "${to_delete[@]}"; do
                    log "Deleting ${SNAPSHOT_DIR}/${snap}"
                    btrfs subvolume delete "${SNAPSHOT_DIR}/${snap}"
                done
                ok "Deletion complete."
            fi
            return
        else
            error "Interactive deletion requires 'fzf'. Please install it."
        fi
    done
}

create_pacman_hook() {
    local hook_dir="/etc/pacman.d/hooks"
    local hook_file="${hook_dir}/btrfs-snapshot.hook"
    log "Creating pacman hook: ${hook_file}"

    mkdir -p "$hook_dir"
    # Use a subshell to avoid variable expansion issues with cat <<EOF
    ( cat > "$hook_file" <<EOF
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Creating Btrfs snapshot before transaction...
When = PreTransaction
Exec = /path/to/your/btrfs-snapshot-manager.sh create pre-pacman-upgrade
Depends = btrfs-progs
AbortOnFail
EOF
    )
    warn "Hook created. IMPORTANT: You MUST edit the 'Exec' line in the hook to point to the correct absolute path of this script."
    ok "Pacman hook created successfully."
}

# --- Main Execution ---
main() {
    check_root
    pre_flight_checks

    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <command> [argument]"
        echo "Commands: create, list, delete, create-hook"
        exit 1
    fi

    case "$1" in
        create)
            if [[ -z "${2:-}" ]]; then error "The 'create' command requires a description."; fi
            create_snapshot "$2"
            ;;
        list)
            list_snapshots
            ;;
        delete)
            delete_snapshots
            ;;
        create-hook)
            create_pacman_hook
            ;;
        *)
            error "Invalid command: $1"
            ;;
    esac
}

main "$@"
