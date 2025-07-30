# Arch Linux Power Scripts

A collection of powerful, innovative, and revolutionary bash scripts designed to automate complex tasks, enhance security, and improve the overall user experience on Arch Linux.

## Getting Started

To use these scripts, first make them executable:

```bash
chmod +x *.sh
```

## Scripts

This collection includes the following scripts:

### 1. `arch-update.sh` - The Intelligent System Updater

This script revolutionizes the update process by automating mirror list refreshing, checking for Arch News, handling `.pacnew` files, cleaning the system, and updating AUR packages.

**Dependencies:**
- `pacman-contrib`
- `reflector`
- An AUR helper (e.g., `yay`, `paru`) is recommended.

**Usage:**
```bash
sudo ./arch-update.sh
```

### 2. `arch-harden.sh` - Security Hardening Assistant

A one-stop tool for applying security best practices to your Arch Linux system. It checks the kernel, filesystem, network, and system configurations.

**Dependencies:**
- `audit`
- `fail2ban`

**Usage:**
```bash
sudo ./arch-harden.sh
```

### 3. `arch-snapshot.sh` - Pre-Change System Snapshot

A safety tool that captures the current state of the system before you make potentially risky changes. It backs up package lists, systemd services, hardware configuration, and the pacman database.

**Dependencies:**
- An AUR helper (e.g., `yay`, `paru`) is recommended for a complete package list.

**Usage:**
```bash
./arch-snapshot.sh
```

### 4. `arch-doctor.sh` - System Health and Diagnostics

A comprehensive diagnostic tool that checks for common problems on an Arch Linux system, including failed services, journal errors, disk space, broken symlinks, and package integrity.

**Dependencies:**
- None

**Usage:**
```bash
sudo ./arch-doctor.sh
```

### 5. `arch-kernel-manager.sh` - Kernel Management Utility

An interactive script to simplify managing multiple kernels on Arch Linux, including installing, removing, and listing them, with automatic bootloader updates.

**Dependencies:**
- A supported bootloader (GRUB or systemd-boot) must be properly configured.

**Usage:**
```bash
sudo ./arch-kernel-manager.sh
```

### 6. `pacman-forensics.sh` - The Package Archaeologist

An advanced tool to investigate package history, dependencies, and file ownership on an Arch Linux system.

**Usage:**
```bash
./pacman-forensics.sh <command> [argument]
```

### 7. `dotfile-manager.sh` - The Configuration Butler

A powerful script to manage your personal configuration files (dotfiles) by symlinking them from a central, version-controlled directory.

**Usage:**
```bash
./dotfile-manager.sh <command>
```

### 8. `aur-builder.sh` - The Safe AUR Assistant

A script that assists in the manual building of AUR packages by following the Arch Way. It automates the tedious steps but leaves the crucial inspection and confirmation steps to the user.

**Dependencies:**
- `git`
- `base-devel` group

**Usage:**
```bash
./aur-builder.sh <package_name>
```

### 9. `boot-analyzer.sh` - The Boot Time Doctor

A script that provides a user-friendly and actionable report on system boot performance using the power of `systemd-analyze`.

**Usage:**
```bash
./boot-analyzer.sh
```

### 10. `btrfs-snapshot-manager.sh` - The Btrfs Time Machine

A powerful, interactive script for managing Btrfs snapshots, making it easy to create, delete, and list system snapshots.

**Dependencies:**
- `btrfs-progs`
- A Btrfs filesystem mounted at /.

**Usage:**
```bash
sudo ./btrfs-snapshot-manager.sh <command>
```

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
