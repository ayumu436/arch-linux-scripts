#!/usr/bin/env bash
# arch-kernel-manager.sh - Kernel Management Utility
#
# DESCRIPTION:
# An interactive script to simplify managing multiple kernels on Arch Linux,
# including installing, removing, and listing them, with automatic bootloader updates.
#
# DEPENDENCIES:
# - A supported bootloader (GRUB or systemd-boot) must be properly configured.
#
# USAGE:
# sudo ./arch-kernel-manager.sh

set -euo pipefail

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

warn() {
    echo "${YELLOW}${BOLD}[WARN]${RESET} $1"
}

error() {
    echo "${RED}${BOLD}[ERROR]${RESET} $1" >&2
    exit 1
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be run as root."
    fi
}

# --- Core Functions ---

list_kernels() {
    echo -e "\n${BOLD}--- Installed Kernels ---${RESET}"
    local current_kernel
    current_kernel=$(uname -r)
    
    # pacman -Qsq matches start-of-string, so it's safer
    # We also filter out common non-kernel packages that start with 'linux'
    pacman -Qsq '^linux' | grep -vE 'headers|firmware|api|tools|docs' | while read -r kernel; do
        local version
        version=$(pacman -Q "$kernel" | awk '{print $2}')
        # Match the base version number against uname -r
        if [[ "$current_kernel" == "${version%%-*}"* ]]; then
            echo "${GREEN}* $kernel $version (currently running)${RESET}"
        else
            echo "  $kernel $version"
        fi
    done
    echo
}

update_bootloader() {
    log "Updating bootloader..."
    if [[ -d /boot/grub ]]; then
        log "GRUB detected. Running grub-mkconfig..."
        grub-mkconfig -o /boot/grub/grub.cfg
        log "GRUB configuration updated."
    elif [[ -d /boot/loader && -f /boot/loader/loader.conf ]]; then
        log "systemd-boot detected. Running bootctl update..."
        bootctl update
        log "systemd-boot updated."
    else
        warn "Could not detect a supported bootloader (GRUB or systemd-boot)."
        warn "Please update your bootloader manually!"
    fi
}

install_kernel() {
    echo -e "\n${BOLD}--- Install New Kernel ---${RESET}"
    PS3="Select a kernel to install: "
    options=("linux (stable)" "linux-lts" "linux-zen" "linux-hardened" "Cancel")
    select opt in "${options[@]}"; do
        case $opt in
            "linux (stable)")
                pacman -S --needed linux linux-headers
                break
                ;;
            "linux-lts")
                pacman -S --needed linux-lts linux-lts-headers
                break
                ;;
            "linux-zen")
                pacman -S --needed linux-zen linux-zen-headers
                break
                ;;
            "linux-hardened")
                pacman -S --needed linux-hardened linux-hardened-headers
                break
                ;;
            "Cancel")
                return
                ;;
            *) echo "Invalid option $REPLY";;
        esac
    done
    update_bootloader
}

remove_kernel() {
    echo -e "\n${BOLD}--- Remove Old Kernel ---${RESET}"
    local current_kernel_pkg=""
    local current_kernel_ver
    current_kernel_ver=$(uname -r)

    # A simple heuristic to find the package name for the running kernel
    if [[ "$current_kernel_ver" == *"lts"* ]]; then
        current_kernel_pkg="linux-lts"
    elif [[ "$current_kernel_ver" == *"zen"* ]]; then
        current_kernel_pkg="linux-zen"
    elif [[ "$current_kernel_ver" == *"hardened"* ]]; then
        current_kernel_pkg="linux-hardened"
    else
        # This assumes the standard kernel if no other suffix is found
        current_kernel_pkg="linux"
    fi

    local installed_kernels
    installed_kernels=($(pacman -Qsq '^linux' | grep -vE 'headers|firmware|api|tools|docs'))
    
    local kernels_to_remove=()
    for kernel in "${installed_kernels[@]}"; do
        if [[ "$kernel" != "$current_kernel_pkg" ]]; then
            kernels_to_remove+=("$kernel")
        fi
    done

    if [[ ${#kernels_to_remove[@]} -eq 0 ]]; then
        warn "No other kernels available to remove. You cannot remove the running kernel."
        return
    }

    PS3="Select a kernel to REMOVE (cannot remove running kernel): "
    select kernel_to_remove in "${kernels_to_remove[@]}" "Cancel"; do
        if [[ "$kernel_to_remove" == "Cancel" ]]; then
            return
        fi
        if [[ -n "$kernel_to_remove" ]]; then
            read -p "${RED}This will permanently remove $kernel_to_remove and its headers. Are you sure? [y/N] ${RESET}" response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                pacman -Rns "$kernel_to_remove" "${kernel_to_remove}-headers"
                log "$kernel_to_remove has been removed."
                update_bootloader
            else
                log "Removal cancelled."
            fi
            break
        else
            echo "Invalid option $REPLY"
        fi
    done
}

# --- Main Execution ---
main() {
    check_root
    while true; do
        list_kernels
        PS3="${BOLD}Choose an action: ${RESET}"
        options=("Install a new kernel" "Remove an old kernel" "Exit")
        select opt in "${options[@]}"; do
            case $opt in
                "Install a new kernel")
                    install_kernel
                    break
                    ;;
                "Remove an old kernel")
                    remove_kernel
                    break
                    ;;
                "Exit")
                    log "Exiting Kernel Manager."
                    exit 0
                    ;;
                *) echo "Invalid option $REPLY";;
            esac
        done
    done
}

main "$@"
