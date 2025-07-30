#!/usr/bin/env bash
# arch-harden.sh - Security Hardening Assistant
#
# DESCRIPTION:
# A script to apply and recommend security best practices for an Arch Linux system.
# It checks kernel, filesystem, network, and system configurations.
#
# DEPENDENCIES:
# - audit
#   sudo pacman -S --needed audit
# - fail2ban
#   sudo pacman -S --needed fail2ban
#
# USAGE:
# sudo ./arch-harden.sh

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

ok() {
    echo "${GREEN}${BOLD}[OK]${RESET} $1"
}

step() {
    echo -e "\n${GREEN}${BOLD}>>> $1${RESET}"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "${RED}${BOLD}[ERROR]${RESET} This script must be run as root." >&2
        exit 1
    fi
}

# --- Hardening Functions ---

check_kernel() {
    step "Checking installed kernel..."
    if pacman -Q linux-hardened &>/dev/null; then
        ok "Found '''linux-hardened''' kernel installed."
    else
        warn "The '''linux-hardened''' kernel is not installed. It provides many security enhancements."
        read -p "Do you want to install it now? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            pacman -S --needed linux-hardened
            log "Remember to update your bootloader and reboot to use the new kernel."
        fi
    fi
}

check_fstab() {
    step "Analyzing /etc/fstab for secure mount options..."
    log "This check is informational. It will not modify your fstab."
    
    # Check /tmp
    if grep -q ''' /tmp ''' /etc/fstab; then
        if grep ''' /tmp ''' /etc/fstab | grep -q '''noexec,nodev,nosuid'''; then
            ok "/tmp is mounted with noexec, nodev, nosuid."
        else
            warn "/tmp is not mounted with noexec,nodev,nosuid. Recommended for security."
        fi
    else
        warn "/tmp is not on a separate partition. Consider creating one."
    fi

    # Check /dev/shm
    if grep -q ''' /dev/shm ''' /etc/fstab; then
         if grep ''' /dev/shm ''' /etc/fstab | grep -q '''noexec,nodev,nosuid'''; then
            ok "/dev/shm is mounted with noexec, nodev, nosuid."
        else
            warn "/dev/shm is not mounted with noexec,nodev,nosuid. Recommended for security."
        fi
    else
        warn "/dev/shm is not configured in fstab with secure options."
    fi
}

configure_sysctl() {
    step "Applying secure kernel parameters via sysctl..."
    local conf_file="/etc/sysctl.d/99-hardening.conf"
    
    cat > "$conf_file" <<EOF
# Kernel Hardening settings from arch-harden.sh
# Restrict access to kernel pointers in /proc
kernel.kptr_restrict=1
# Enable TCP SYN cookie protection
net.ipv4.tcp_syncookies=1
# Protect against IP spoofing
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts=1
# Log martian packets
net.ipv4.conf.all.log_martians=1
EOF
    
    # Apply settings
    sysctl -p "$conf_file" >/dev/null
    ok "Secure sysctl settings applied to $conf_file."
}

configure_fail2ban() {
    step "Configuring fail2ban for SSH protection..."
    if ! pacman -Q fail2ban &>/dev/null; then
        log "fail2ban is not installed. Installing..."
        pacman -S --noconfirm --needed fail2ban
    fi

    local jail_local="/etc/fail2ban/jail.local"
    if [[ ! -f "$jail_local" ]]; then
        log "Creating fail2ban local configuration for SSH."
        cat > "$jail_local" <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
        ok "Created $jail_local."
    else
        ok "fail2ban local config already exists. Skipping creation."
    fi

    if ! systemctl is-enabled --quiet fail2ban; then
        log "Enabling and starting fail2ban service..."
        systemctl enable --now fail2ban
        ok "fail2ban service enabled and started."
    else
        ok "fail2ban service is already enabled."
        log "Restarting fail2ban to apply any changes."
        systemctl restart fail2ban
    fi
}

configure_auditd() {
    step "Configuring auditd for system call monitoring..."
    if ! pacman -Q audit &>/dev/null; then
        log "audit is not installed. Installing..."
        pacman -S --noconfirm --needed audit
    fi

    local rules_file="/etc/audit/rules.d/99-hardening.rules"
    log "Adding baseline audit rules to $rules_file"
    cat > "$rules_file" <<EOF
# Audit rules from arch-harden.sh
# Monitor changes to system time
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -k time-change

# Monitor changes to user/group info
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity

# Monitor changes to network environment
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale

# Monitor for privilege escalation
-w /bin/su -p x -k priv_esc
-w /usr/bin/sudo -p x -k priv_esc
EOF
    
    if ! systemctl is-enabled --quiet auditd; then
        log "Enabling and starting auditd service..."
        systemctl enable --now auditd
        ok "auditd service enabled and started."
    else
        ok "auditd service is already enabled."
    fi
    # Force reload of rules
    augenrules --load
    ok "Baseline audit rules configured and loaded."
}

scan_permissions() {
    step "Scanning for world-writable files in sensitive locations..."
    local found=0
    # We check key system directories
    for dir in /etc /usr/bin /usr/sbin /bin /sbin; do
        if [[ -d "$dir" ]]; then
            find "$dir" -xdev -type f -perm -0002 -print -o -type d -perm -0002 -print | while read -r line; do
                warn "World-writable item found: $line"
                found=1
            done
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        ok "No world-writable files or directories found in sensitive locations."
    fi
}


# --- Main Execution ---
main() {
    check_root
    log "Starting Arch Linux Security Hardening Assistant..."
    
    check_kernel
    check_fstab
    configure_sysctl
    configure_fail2ban
    configure_auditd
    scan_permissions

    step "Hardening script finished."
    warn "A reboot may be required for some changes to take full effect (e.g., new kernel)."
}

main "$@"
