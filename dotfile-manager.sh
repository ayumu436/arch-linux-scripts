#!/usr/bin/env bash
# dotfile-manager.sh - The Configuration Butler
#
# DESCRIPTION:
# A powerful script to manage your personal configuration files (dotfiles)
# by symlinking them from a central, version-controlled directory.
#
# USAGE:
# ./dotfile-manager.sh <command>
#
# COMMANDS:
#   init [git_repo_url] - Initialize dotfiles directory, optionally cloning a remote repo.
#   stow                - Create symlinks from dotfiles repo to home directory.
#   unstow              - Remove symlinks from home directory.
#   status              - Show the status of managed dotfiles.

set -euo pipefail

# --- Configuration ---
# The directory where your dotfiles are stored.
DOTFILES_DIR="${HOME}/dotfiles"
# Backup directory for existing files.
BACKUP_DIR="${HOME}/dotfiles_backup_$(date +%Y%m%d%H%M%S)"

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

ok() {
    echo "${GREEN}${BOLD}[OK]${RESET} $1"
}

# --- Core Functions ---

init_dotfiles() {
    log "Initializing dotfiles directory at ${DOTFILES_DIR}"
    if [[ -d "$DOTFILES_DIR" ]]; then
        warn "Dotfiles directory already exists. Skipping creation."
    else
        if [[ -n "${1:-}" ]]; then
            log "Cloning remote repository from $1..."
            git clone "$1" "$DOTFILES_DIR"
        else
            log "Creating a new, empty dotfiles directory."
            mkdir -p "$DOTFILES_DIR"
            echo "# My Dotfiles" > "${DOTFILES_DIR}/README.md"
        fi
        ok "Dotfiles directory initialized."
    fi
}

stow_files() {
    log "Stowing dotfiles from ${DOTFILES_DIR} to ${HOME}"
    mkdir -p "$BACKUP_DIR"
    # Find all files in the dotfiles dir, excluding the .git dir
    find "$DOTFILES_DIR" -mindepth 1 -not -path "*/.git*" | while read -r src_path; do
        # Construct the destination path relative to HOME
        dest_path="${HOME}/${src_path#$DOTFILES_DIR/}"
        
        # Ensure parent directory exists in destination
        mkdir -p "$(dirname "$dest_path")"

        # If it's a file we are processing
        if [[ -f "$src_path" ]]; then
            # If a file/link already exists at the destination
            if [[ -e "$dest_path" ]]; then
                if [[ -L "$dest_path" && "$(readlink "$dest_path")" == "$src_path" ]]; then
                    log "Skipping ${dest_path}, already correctly linked."
                else
                    warn "Existing file found at ${dest_path}. Backing it up."
                    mv "$dest_path" "$BACKUP_DIR/"
                    ln -sv "$src_path" "$dest_path"
                fi
            else
                ln -sv "$src_path" "$dest_path"
            fi
        fi
    done
    ok "Stow complete. Backups are in ${BACKUP_DIR}"
}

unstow_files() {
    log "Unstowing dotfiles, removing symlinks from ${HOME}"
    find "$DOTFILES_DIR" -mindepth 1 -not -path "*/.git*" -type f | while read -r src_path; do
        dest_path="${HOME}/${src_path#$DOTFILES_DIR/}"
        if [[ -L "$dest_path" && "$(readlink "$dest_path")" == "$src_path" ]]; then
            rm -v "$dest_path"
        fi
    done
    warn "You can optionally restore backups from a backup directory."
    ok "Unstow complete."
}

show_status() {
    log "Checking status of managed dotfiles..."
    find "$DOTFILES_DIR" -mindepth 1 -not -path "*/.git*" -type f | while read -r src_path; do
        dest_path="${HOME}/${src_path#$DOTFILES_DIR/}"
        if [[ ! -e "$dest_path" ]]; then
            echo "${YELLOW}[MISSING]${RESET} ${dest_path}"
        elif [[ -L "$dest_path" && "$(readlink "$dest_path")" == "$src_path" ]]; then
            echo "${GREEN}[LINKED]${RESET}  ${dest_path}"
        else
            echo "${RED}[CONFLICT]${RESET} ${dest_path} is a real file, not a symlink."
        fi
    done
}

# --- Main Execution ---
main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <command>"
        echo "Commands: init, stow, unstow, status"
        exit 1
    fi

    case "$1" in
        init)
            init_dotfiles "${2:-}"
            ;;
        stow)
            stow_files
            ;;
        unstow)
            unstow_files
            ;;
        status)
            show_status
            ;;
        *)
            error "Invalid command: $1"
            ;;
    esac
}

main "$@"
