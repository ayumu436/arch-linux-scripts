#!/usr/bin/env bash
# pacman-forensics.sh - The Package Archaeologist
#
# DESCRIPTION:
# An advanced tool to investigate package history, dependencies, and file
# ownership on an Arch Linux system. It provides deep insights beyond
# standard pacman queries.
#
# USAGE:
# ./pacman-forensics.sh <command> [argument]
#
# COMMANDS:
#   depends-on <pkg>    - Show what a package depends on.
#   required-by <pkg>   - Show what packages require this package.
#   history <pkg>       - Show the installation/upgrade/removal history of a package.
#   why <pkg>           - Determine why a package is installed (explicitly or as a dependency).
#   owns <file_path>    - Find out which package owns a specific file.

set -euo pipefail

# --- Color Codes ---
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
BLUE=$(tput setaf 4)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# --- Helper Functions ---
header() {
    echo -e "\n${BLUE}${BOLD}--- $1 ---${RESET}"
}

error() {
    echo "${RED}${BOLD}[ERROR]${RESET} $1" >&2
    exit 1
}

check_package_exists() {
    if ! pacman -Q "$1" &>/dev/null; then
        error "Package '''$1''' is not installed."
    fi
}

# --- Core Functions ---

show_depends() {
    check_package_exists "$1"
    header "Dependencies for '''$1'''"
    pactree -c "$1"
}

show_required_by() {
    check_package_exists "$1"
    header "Packages that require '''$1'''"
    pactree -rc "$1"
}

show_history() {
    header "History for package '''$1''' from /var/log/pacman.log"
    grep -E "(installed|upgraded|removed) $1 " /var/log/pacman.log || echo "No history found for $1."
}

show_why() {
    check_package_exists "$1"
    header "Installation reason for '''$1'''"
    local reason
    reason=$(pacman -Qi "$1" | grep "Install Reason" | cut -d':' -f2- | xargs)
    echo "Install Reason: ${GREEN}$reason${RESET}"

    if [[ "$reason" == "Installed as a dependency for another package" ]]; then
        local required_by
        # Find packages that directly require this one
        required_by=$(pactree -r "$1")
        echo "Required by:"
        echo "$required_by" | sed '''s/^/  /'''
    fi
}

show_owner() {
    if [[ ! -e "$1" ]]; then
        error "File or directory '''$1''' does not exist."
    fi
    header "Owner of file '''$1'''"
    pacman -Qo "$1"
}

# --- Main Execution ---
main() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <command> [argument]"
        echo "Commands: depends-on, required-by, history, why, owns"
        exit 1
    fi

    local command="$1"
    local argument="$2"

    case "$command" in
        depends-on)
            show_depends "$argument"
            ;;
        required-by)
            show_required_by "$argument"
            ;;
        history)
            show_history "$argument"
            ;;
        why)
            show_why "$argument"
            ;;
        owns)
            show_owner "$argument"
            ;;
        *)
            error "Invalid command: $command"
            ;;
    esac
}

main "$@"
