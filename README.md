# Arch Linux Power User Scripts Collection

A comprehensive collection of advanced Bash scripts designed specifically for Arch Linux users. These scripts automate common system administration tasks, optimize performance, and enhance the overall Arch Linux experience.

## 🚀 Featured Scripts

### System Management & Optimization

#### 📦 **pacman-mirror-optimizer.sh**
Automatically test, rank, and optimize Pacman mirrors for faster package downloads.
- **Features:**
  - Auto-detects your country for optimal mirror selection
  - Tests mirror speeds and ranks them by performance
  - Creates automatic backups before changes
  - Supports both reflector and manual testing methods
  - Interactive and command-line modes
- **Usage:** `./pacman-mirror-optimizer.sh [--optimize|--benchmark|--restore|--country CODE]`

#### ⚙️ **arch-service-manager.sh**
Advanced systemd service management with enhanced monitoring and control.
- **Features:**
  - Visual service status overview with color coding
  - Real-time service monitoring
  - Boot time analysis and optimization
  - Service template generator
  - Failed service detection and troubleshooting
- **Usage:** `./arch-service-manager.sh [list|failed|details SERVICE|monitor|boot]`

#### 🧹 **arch-cache-cleaner.sh**
Intelligent package cache management to free up disk space.
- **Features:**
  - Analyzes cache usage across pacman, AUR helpers, and user caches
  - Smart cleaning with configurable retention policies
  - Dry-run mode to preview changes
  - Automatic orphan package detection
  - Scheduled cleaning via systemd timers
- **Usage:** `./arch-cache-cleaner.sh [--analyze|--clean|--aggressive|--dry-run]`

#### 🎮 **arch-gpu-switcher.sh**
Manage hybrid graphics systems (Intel/NVIDIA/AMD) for laptops.
- **Features:**
  - Switch between integrated and discrete GPUs
  - PRIME render offload configuration
  - Power management optimization
  - GPU benchmarking tools
  - Optimus Manager integration
- **Usage:** `./arch-gpu-switcher.sh [intel|nvidia|hybrid|status|benchmark]`

#### 🔋 **arch-power-optimizer.sh**
Comprehensive battery and power management optimization.
- **Features:**
  - Multiple power profiles (powersave/balanced/performance)
  - Real-time power consumption monitoring
  - TLP and PowerTOP integration
  - Service optimization for battery life
  - Custom profile creation
- **Usage:** `./arch-power-optimizer.sh [status|profile NAME|monitor|optimize]`

### Previously Added Scripts

#### 🏥 **arch-doctor.sh**
System health checker and diagnostic tool that identifies and fixes common Arch Linux issues.

#### 🔒 **arch-harden.sh**
Security hardening script that implements best practices for system security.

#### 🐧 **arch-kernel-manager.sh**
Kernel management utility for installing, configuring, and switching between different kernels.

#### 📸 **arch-snapshot.sh**
System snapshot tool for creating and managing backups before major updates.

#### 🔄 **arch-update.sh**
Intelligent system updater with automatic snapshot creation and rollback capabilities.

#### 🏗️ **aur-builder.sh**
AUR helper wrapper that simplifies building and managing AUR packages.

#### 🥾 **boot-analyzer.sh**
Boot performance analyzer that identifies slow services and optimizes startup time.

#### 🗂️ **btrfs-snapshot-manager.sh**
Advanced Btrfs snapshot management with automatic cleanup and rollback features.

#### 📝 **dotfile-manager.sh**
Dotfile synchronization and management across multiple machines.

#### 🔍 **pacman-forensics.sh**
Package history analyzer for tracking system changes and dependencies.

#### 🖼️ **screenshot_organizer.sh**
Automatically organizes screenshots into dated folders with metadata preservation.

## 🚀 Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/arch-scripts.git
   cd arch-scripts
   ```

2. Make scripts executable:
   ```bash
   chmod +x *.sh
   ```

3. Run any script with `--help` for usage information:
   ```bash
   ./script-name.sh --help
   ```

## 📋 Requirements

- Arch Linux (or Arch-based distribution)
- Bash 4.0+
- sudo privileges for system modifications
- Optional: yay or paru for AUR support

## ⚠️ Important Notes

- Always review scripts before running them with sudo privileges
- Most scripts create backups before making system changes
- Use dry-run modes when available to preview changes
- Some scripts may require additional packages (will prompt for installation)

## 🤝 Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## 📄 License

These scripts are provided as-is for the Arch Linux community. Use at your own risk.