#!/usr/bin/env bash
# arch-doctor.sh - System Health and Diagnostics
#
# DESCRIPTION:
# A comprehensive diagnostic tool that checks for common problems on an
# Arch Linux system, including failed services, journal errors, disk space,
# broken symlinks, and package integrity.
#
# DEPENDENCIES:
# - None
#
# USAGE:
# sudo ./arch-doctor.sh

set -euo pipefail

# --- Color Codes ---
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# --- Helper Functions ---
ok() {
    echo "${GREEN}${BOLD}[OK]${RESET} $1"
}

warn() {
    echo "${YELLOW}${BOLD}[WARN]${RESET} $1"
}

critical() {
    echo "${RED}${BOLD}[CRITICAL]${RESET} $1"
}

step() {
    echo -e "\n${BOLD}--- $1 ---"${RESET}
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        critical "This script should be run as root to perform all checks." >&2
        exit 1
    fi
}

# --- Diagnostic Functions ---

check_systemd() {
    step "Checking systemd services"
    failed_units=$(systemctl list-units --state=failed --plain --no-legend)
    if [[ -z "$failed_units" ]]; then
        ok "No failed systemd units found."
    else
        critical "Found failed systemd units:"
        echo "$failed_units"
        warn "Use '''systemctl status <unit_name>''' for details."
    fi
}

check_journal() {
    step "Scanning journal for errors in the current boot"
    # journalctl -p 3: errors. -b: current boot
    journal_errors=$(journalctl -p 3 -b --no-pager)
    if [[ -z "$journal_errors" ]]; then
        ok "No critical errors found in the journal for the current boot."
    else
        critical "Found errors in the system journal (showing last 20 lines):"
        echo "$journal_errors" | tail -n 20
        warn "Review '''journalctl -p 3 -b''' for a full list."
    fi
}

check_disk_space() {
    step "Checking disk space usage"
    local has_warning=0
    # Exclude tmpfs, squashfs etc.
    df -hP | grep -vE '''^Filesystem|tmpfs|squashfs''' | while read -r line; do
        usage=$(echo "$line" | awk ''{ print $5 }''' | sed '''s/%//''')
        mount_point=$(echo "$line" | awk ''{ print $6 }''')
        if [[ "$usage" -gt 90 ]]; then
            critical "Filesystem $mount_point is at ${usage}% capacity."
            has_warning=1
        fi
    done
    if [[ "$has_warning" -eq 0 ]]; then
        ok "Disk space on all critical filesystems is within acceptable limits."
    fi
}

check_symlinks() {
    step "Checking for broken symbolic links"
    # Check common directories, ignore permission errors from /proc etc.
    broken_links=$(find /etc /usr /lib /var -xtype l -print 2>/dev/null)
    if [[ -z "$broken_links" ]]; then
        ok "No broken symbolic links found in common system directories."
    else
        warn "Found broken symbolic links:"
        echo "$broken_links"
    fi
}

check_package_integrity() {
    step "Verifying integrity of installed packages"
    warn "This may take a few minutes..."
    # pacman -Qkk returns non-zero if there are issues.
    # We capture stderr to show which files are problematic.
    if output=$(pacman -Qkk 2>&1); then
        ok "All packages passed the integrity check."
    else
        critical "Package integrity issues found. This can be normal for config files."
        # The output can be very long, so we show a summary of modified files.
        echo "$output" | grep -E '''(modified|is not a regular file)''' | grep -v '''backup file'''
        warn "Run '''sudo pacman -Qkk''' for a full report."
    fi
}

# --- Main Execution ---
main() {
    check_root
    echo "${BOLD}Starting Arch Linux Health and Diagnostics Doctor...${RESET}"
    
    check_systemd
    check_journal
    check_disk_space
    check_symlinks
    check_package_integrity

    echo
    ok "Health check complete."
}

main "$@"
