#!/usr/bin/env bash
# aur-builder.sh - The Safe AUR Assistant
#
# DESCRIPTION:
# A script that assists in the manual building of AUR packages by following
# the Arch Way. It automates the tedious steps but leaves the crucial
# inspection and confirmation steps to the user.
#
# DEPENDENCIES:
# - git
# - base-devel group (for makepkg)
#
# USAGE:
# ./aur-builder.sh <package_name>

set -euo pipefail

# --- Configuration ---
# Directory to build packages in.
BUILD_DIR="${HOME}/aur_builds"

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

step() {
    echo -e "\n${GREEN}${BOLD}>>> $1${RESET}"
}

# --- Core Functions ---

fetch_pkgbuild() {
    local pkg_name="$1"
    local pkg_url="https://aur.archlinux.org/${pkg_name}.git"
    
    step "Fetching package source..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    if [[ -d "$pkg_name" ]]; then
        warn "Directory ''''$pkg_name'''' already exists. Pulling latest changes."
        cd "$pkg_name"
        git pull
    else
        log "Cloning from ${pkg_url}"
        git clone "$pkg_url"
        cd "$pkg_name"
    fi
}

inspect_pkgbuild() {
    step "Inspecting PKGBUILD..."
    if [[ ! -f PKGBUILD ]]; then
        error "PKGBUILD not found in the current directory."
    fi

    warn "It is CRITICAL to inspect the PKGBUILD for security and correctness."
    warn "The script will now open it in your default editor ($EDITOR)."
    read -p "Press [Enter] to continue..."

    # Open in editor, default to vim if not set
    ${EDITOR:-vim} PKGBUILD

    read -p "Did you finish inspecting the PKGBUILD and do you trust it? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        error "Build aborted by user."
    fi
}

build_and_install() {
    step "Building and installing the package..."
    log "Running ''''makepkg -si''''. This will resolve dependencies and install the package."
    # -s: sync dependencies, -i: install package
    makepkg -si
}

cleanup() {
    step "Cleaning up..."
    read -p "Do you want to remove the build directory ''''$BUILD_DIR/$1''''? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log "Removing build directory."
        rm -rf "${BUILD_DIR}/$1"
    fi
}

# --- Main Execution ---
main() {
    if [[ $# -ne 1 ]]; then
        error "Usage: $0 <package_name>"
    fi

    local pkg_name="$1"

    fetch_pkgbuild "$pkg_name"
    inspect_pkgbuild
    build_and_install
    cleanup "$pkg_name"

    log "${GREEN}${BOLD}Package ''''$pkg_name'''' has been successfully built and installed.${RESET}"
}

main "$@"
