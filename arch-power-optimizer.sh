#!/bin/bash

set -euo pipefail

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'

CONFIG_FILE="/etc/arch-power-optimizer.conf"
PROFILE_DIR="/etc/arch-power-optimizer/profiles"
CURRENT_PROFILE_FILE="/var/lib/arch-power-optimizer/current-profile"
LOG_FILE="/var/log/arch-power-optimizer.log"

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Arch Linux Power Optimizer                     ║"
    echo "║       Battery and Power Management Optimization         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

log_message() {
    local level=$1
    shift
    local message="$@"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    
    case "$level" in
        ERROR)
            echo -e "${RED}[ERROR]${RESET} $message" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${RESET} $message"
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${RESET} $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${RESET} $message"
            ;;
    esac
}

check_battery_info() {
    echo -e "${CYAN}${BOLD}Battery Information:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    local battery_count=0
    for bat in /sys/class/power_supply/BAT*; do
        if [ -d "$bat" ]; then
            ((battery_count++))
            local bat_name=$(basename "$bat")
            
            if [ -f "$bat/capacity" ]; then
                local capacity=$(cat "$bat/capacity")
                local status=$(cat "$bat/status" 2>/dev/null || echo "Unknown")
                
                echo -e "${BLUE}$bat_name:${RESET}"
                echo -e "  Capacity: ${capacity}%"
                echo -e "  Status: $status"
                
                if [ -f "$bat/energy_full" ] && [ -f "$bat/energy_full_design" ]; then
                    local full=$(cat "$bat/energy_full")
                    local design=$(cat "$bat/energy_full_design")
                    local health=$((full * 100 / design))
                    echo -e "  Health: ${health}%"
                fi
                
                if [ -f "$bat/power_now" ]; then
                    local power=$(cat "$bat/power_now")
                    local power_watts=$(echo "scale=2; $power / 1000000" | bc)
                    echo -e "  Power draw: ${power_watts}W"
                fi
                
                if [ -f "$bat/energy_now" ] && [ "$status" = "Discharging" ]; then
                    local energy_now=$(cat "$bat/energy_now")
                    local power_now=$(cat "$bat/power_now" 2>/dev/null || echo "0")
                    if [ "$power_now" -gt 0 ]; then
                        local hours=$(echo "scale=2; $energy_now / $power_now" | bc)
                        echo -e "  Time remaining: ${hours} hours"
                    fi
                fi
            fi
        fi
    done
    
    if [ $battery_count -eq 0 ]; then
        echo -e "${YELLOW}No battery detected (Desktop system?)${RESET}"
    fi
}

check_power_consumers() {
    echo -e "${CYAN}${BOLD}Top Power Consumers:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    if command -v powertop &> /dev/null; then
        echo -e "${BLUE}Running powertop analysis...${RESET}"
        sudo timeout 5 powertop --csv=/tmp/powertop.csv 2>/dev/null || true
        
        if [ -f /tmp/powertop.csv ]; then
            echo -e "${YELLOW}Top processes by power usage:${RESET}"
            grep -A 10 "Top 10 Power Consumers" /tmp/powertop.csv 2>/dev/null | tail -n 10 | head -n 5 || true
            rm -f /tmp/powertop.csv
        fi
    else
        echo -e "${YELLOW}Install powertop for detailed power analysis${RESET}"
    fi
    
    echo
    echo -e "${BLUE}CPU Frequency:${RESET}"
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        if [ -f "$cpu" ]; then
            local cpu_num=$(echo "$cpu" | grep -o "cpu[0-9]*")
            local freq=$(cat "$cpu")
            local freq_ghz=$(echo "scale=2; $freq / 1000000" | bc)
            echo "  $cpu_num: ${freq_ghz} GHz"
        fi
    done | head -n 4
    
    echo
    echo -e "${BLUE}Disk Activity:${RESET}"
    for disk in /sys/block/*/stat; do
        if [ -f "$disk" ]; then
            local disk_name=$(echo "$disk" | cut -d'/' -f4)
            local stats=$(cat "$disk")
            local reads=$(echo "$stats" | awk '{print $1}')
            local writes=$(echo "$stats" | awk '{print $5}')
            if [ "$reads" -gt 0 ] || [ "$writes" -gt 0 ]; then
                echo "  $disk_name: R:$reads W:$writes"
            fi
        fi
    done | head -n 3
}

configure_cpu_governor() {
    local governor=$1
    
    echo -e "${BLUE}Setting CPU governor to: $governor${RESET}"
    
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        if [ -f "$cpu" ]; then
            echo "$governor" | sudo tee "$cpu" > /dev/null
        fi
    done
    
    log_message SUCCESS "CPU governor set to $governor"
}

configure_laptop_mode() {
    echo -e "${BLUE}Configuring laptop mode tools...${RESET}"
    
    if ! command -v laptop_mode &> /dev/null; then
        echo -e "${YELLOW}Installing laptop-mode-tools...${RESET}"
        sudo pacman -S --needed laptop-mode-tools
    fi
    
    sudo systemctl enable laptop-mode
    sudo systemctl start laptop-mode
    
    sudo sed -i 's/ENABLE_LAPTOP_MODE_ON_AC=.*/ENABLE_LAPTOP_MODE_ON_AC=0/' /etc/laptop-mode/laptop-mode.conf
    sudo sed -i 's/ENABLE_LAPTOP_MODE_ON_BATTERY=.*/ENABLE_LAPTOP_MODE_ON_BATTERY=1/' /etc/laptop-mode/laptop-mode.conf
    sudo sed -i 's/ENABLE_LAPTOP_MODE_WHEN_LID_CLOSED=.*/ENABLE_LAPTOP_MODE_WHEN_LID_CLOSED=1/' /etc/laptop-mode/laptop-mode.conf
    
    sudo laptop_mode auto
    
    log_message SUCCESS "Laptop mode tools configured"
}

configure_tlp() {
    echo -e "${BLUE}Configuring TLP power management...${RESET}"
    
    if ! command -v tlp &> /dev/null; then
        echo -e "${YELLOW}Installing TLP...${RESET}"
        sudo pacman -S --needed tlp tlp-rdw
    fi
    
    sudo systemctl stop laptop-mode 2>/dev/null || true
    sudo systemctl disable laptop-mode 2>/dev/null || true
    
    sudo tee /etc/tlp.d/00-custom.conf > /dev/null << 'EOF'
# TLP Custom Configuration

# CPU Settings
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power
CPU_MIN_PERF_ON_AC=0
CPU_MAX_PERF_ON_AC=100
CPU_MIN_PERF_ON_BAT=0
CPU_MAX_PERF_ON_BAT=50
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0

# Disk Settings
DISK_IDLE_SECS_ON_AC=0
DISK_IDLE_SECS_ON_BAT=2
DISK_APM_LEVEL_ON_AC="254 254"
DISK_APM_LEVEL_ON_BAT="128 128"

# Network Settings
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on
WOL_DISABLE=Y

# USB Settings
USB_AUTOSUSPEND=1
USB_BLACKLIST_PHONE=1

# PCI Settings
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto
PCIE_ASPM_ON_AC=performance
PCIE_ASPM_ON_BAT=powersupersave

# Graphics Settings
RADEON_POWER_PROFILE_ON_AC=high
RADEON_POWER_PROFILE_ON_BAT=low
RADEON_DPM_STATE_ON_AC=performance
RADEON_DPM_STATE_ON_BAT=battery
RADEON_DPM_PERF_LEVEL_ON_AC=auto
RADEON_DPM_PERF_LEVEL_ON_BAT=low

# Intel GPU
INTEL_GPU_MIN_FREQ_ON_AC=0
INTEL_GPU_MIN_FREQ_ON_BAT=0
INTEL_GPU_MAX_FREQ_ON_AC=0
INTEL_GPU_MAX_FREQ_ON_BAT=500
INTEL_GPU_BOOST_FREQ_ON_AC=0
INTEL_GPU_BOOST_FREQ_ON_BAT=0

# Battery Care
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
EOF
    
    sudo systemctl enable tlp
    sudo systemctl start tlp
    
    log_message SUCCESS "TLP configured and started"
}

configure_powertop_autotune() {
    echo -e "${BLUE}Configuring PowerTOP auto-tune...${RESET}"
    
    if ! command -v powertop &> /dev/null; then
        echo -e "${YELLOW}Installing PowerTOP...${RESET}"
        sudo pacman -S --needed powertop
    fi
    
    sudo tee /etc/systemd/system/powertop.service > /dev/null << 'EOF'
[Unit]
Description=PowerTOP auto-tune

[Service]
Type=oneshot
Environment="TERM=dumb"
RemainAfterExit=yes
ExecStart=/usr/bin/powertop --auto-tune

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable powertop
    sudo systemctl start powertop
    
    log_message SUCCESS "PowerTOP auto-tune configured"
}

create_power_profile() {
    local profile_name=$1
    
    echo -e "${CYAN}Creating power profile: $profile_name${RESET}"
    
    sudo mkdir -p "$PROFILE_DIR"
    
    case "$profile_name" in
        powersave)
            sudo tee "$PROFILE_DIR/powersave.conf" > /dev/null << 'EOF'
# Power Save Profile
CPU_GOVERNOR=powersave
CPU_MAX_FREQ=50
DISPLAY_BRIGHTNESS=30
WIFI_POWER=on
BLUETOOTH=off
USB_AUTOSUSPEND=on
DISK_APM=128
EOF
            ;;
        balanced)
            sudo tee "$PROFILE_DIR/balanced.conf" > /dev/null << 'EOF'
# Balanced Profile
CPU_GOVERNOR=schedutil
CPU_MAX_FREQ=80
DISPLAY_BRIGHTNESS=60
WIFI_POWER=off
BLUETOOTH=on
USB_AUTOSUSPEND=on
DISK_APM=192
EOF
            ;;
        performance)
            sudo tee "$PROFILE_DIR/performance.conf" > /dev/null << 'EOF'
# Performance Profile
CPU_GOVERNOR=performance
CPU_MAX_FREQ=100
DISPLAY_BRIGHTNESS=100
WIFI_POWER=off
BLUETOOTH=on
USB_AUTOSUSPEND=off
DISK_APM=254
EOF
            ;;
        *)
            log_message ERROR "Unknown profile: $profile_name"
            return 1
            ;;
    esac
    
    log_message SUCCESS "Profile $profile_name created"
}

apply_power_profile() {
    local profile=$1
    local profile_file="$PROFILE_DIR/${profile}.conf"
    
    if [ ! -f "$profile_file" ]; then
        log_message ERROR "Profile not found: $profile"
        return 1
    fi
    
    echo -e "${BLUE}Applying power profile: $profile${RESET}"
    
    source "$profile_file"
    
    [ -n "${CPU_GOVERNOR:-}" ] && configure_cpu_governor "$CPU_GOVERNOR"
    
    if [ -n "${CPU_MAX_FREQ:-}" ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
            if [ -f "$cpu" ]; then
                local max_freq=$(cat "${cpu%_max_freq}_cpuinfo_max_freq")
                local target_freq=$((max_freq * CPU_MAX_FREQ / 100))
                echo "$target_freq" | sudo tee "$cpu" > /dev/null
            fi
        done
    fi
    
    if [ -n "${DISPLAY_BRIGHTNESS:-}" ]; then
        for backlight in /sys/class/backlight/*/brightness; do
            if [ -f "$backlight" ]; then
                local max_brightness=$(cat "${backlight%brightness}max_brightness")
                local target_brightness=$((max_brightness * DISPLAY_BRIGHTNESS / 100))
                echo "$target_brightness" | sudo tee "$backlight" > /dev/null
            fi
        done
    fi
    
    if [ -n "${WIFI_POWER:-}" ]; then
        for wifi in /sys/class/net/*/device/power/control; do
            if [ -f "$wifi" ]; then
                local control="auto"
                [ "$WIFI_POWER" = "off" ] && control="on"
                echo "$control" | sudo tee "$wifi" > /dev/null
            fi
        done
    fi
    
    if [ -n "${BLUETOOTH:-}" ]; then
        if [ "$BLUETOOTH" = "off" ]; then
            sudo rfkill block bluetooth
        else
            sudo rfkill unblock bluetooth
        fi
    fi
    
    sudo mkdir -p "$(dirname "$CURRENT_PROFILE_FILE")"
    echo "$profile" | sudo tee "$CURRENT_PROFILE_FILE" > /dev/null
    
    log_message SUCCESS "Profile $profile applied"
}

monitor_power() {
    echo -e "${CYAN}${BOLD}Real-time Power Monitor${RESET}"
    echo -e "${DIM}Press Ctrl+C to exit${RESET}"
    echo
    
    while true; do
        clear
        echo -e "${CYAN}${BOLD}Power Monitor - $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
        echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
        
        for bat in /sys/class/power_supply/BAT*; do
            if [ -d "$bat" ]; then
                local bat_name=$(basename "$bat")
                local capacity=$(cat "$bat/capacity" 2>/dev/null || echo "0")
                local status=$(cat "$bat/status" 2>/dev/null || echo "Unknown")
                
                echo -ne "${BLUE}$bat_name:${RESET} ${capacity}% [$status] "
                
                local bar_length=20
                local filled=$((capacity * bar_length / 100))
                echo -n "["
                for ((i=0; i<filled; i++)); do
                    if [ $capacity -gt 50 ]; then
                        echo -ne "${GREEN}█${RESET}"
                    elif [ $capacity -gt 20 ]; then
                        echo -ne "${YELLOW}█${RESET}"
                    else
                        echo -ne "${RED}█${RESET}"
                    fi
                done
                for ((i=filled; i<bar_length; i++)); do echo -n "░"; done
                echo "]"
                
                if [ -f "$bat/power_now" ]; then
                    local power=$(cat "$bat/power_now")
                    local power_watts=$(echo "scale=2; $power / 1000000" | bc)
                    echo "  Power: ${power_watts}W"
                fi
            fi
        done
        
        echo
        echo -e "${CYAN}CPU Frequencies:${RESET}"
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
            if [ -f "$cpu" ]; then
                local cpu_num=$(echo "$cpu" | grep -o "cpu[0-9]*" | sed 's/cpu//')
                local freq=$(cat "$cpu")
                local freq_ghz=$(echo "scale=2; $freq / 1000000" | bc)
                printf "  CPU%d: %.2f GHz  " "$cpu_num" "$freq_ghz"
                [ $((cpu_num % 4)) -eq 3 ] && echo
            fi
        done | head -n 2
        echo
        
        if [ -f "$CURRENT_PROFILE_FILE" ]; then
            local current_profile=$(cat "$CURRENT_PROFILE_FILE")
            echo -e "${CYAN}Active Profile:${RESET} $current_profile"
        fi
        
        local temp_file="/sys/class/thermal/thermal_zone0/temp"
        if [ -f "$temp_file" ]; then
            local temp=$(cat "$temp_file")
            local temp_c=$((temp / 1000))
            echo -e "${CYAN}CPU Temperature:${RESET} ${temp_c}°C"
        fi
        
        sleep 2
    done
}

optimize_services() {
    echo -e "${BLUE}Optimizing system services for power saving...${RESET}"
    
    local unnecessary_services=(
        "bluetooth.service"
        "cups.service"
        "avahi-daemon.service"
        "ModemManager.service"
    )
    
    for service in "${unnecessary_services[@]}"; do
        if systemctl is-active "$service" &> /dev/null; then
            echo -n "Disable $service? (y/N): "
            read -r choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                sudo systemctl stop "$service"
                sudo systemctl disable "$service"
                log_message INFO "Disabled $service"
            fi
        fi
    done
    
    echo -e "${BLUE}Configuring runtime power management...${RESET}"
    for i in /sys/bus/{pci,usb}/devices/*/power/control; do
        [ -f "$i" ] && echo "auto" | sudo tee "$i" > /dev/null
    done
    
    echo -e "${BLUE}Configuring SATA power management...${RESET}"
    for i in /sys/class/scsi_host/*/link_power_management_policy; do
        [ -f "$i" ] && echo "med_power_with_dipm" | sudo tee "$i" > /dev/null
    done
    
    log_message SUCCESS "Services optimized for power saving"
}

interactive_menu() {
    while true; do
        print_header
        check_battery_info
        echo
        echo -e "${CYAN}Select an option:${RESET}"
        echo
        echo "  1. Check power consumers"
        echo "  2. Apply power profile (powersave/balanced/performance)"
        echo "  3. Configure TLP"
        echo "  4. Configure PowerTOP auto-tune"
        echo "  5. Optimize services"
        echo "  6. Monitor power (real-time)"
        echo "  7. Create custom profile"
        echo "  8. Exit"
        echo
        echo -n "Enter your choice (1-8): "
        read -r choice
        
        case "$choice" in
            1)
                check_power_consumers
                ;;
            2)
                echo "Select profile:"
                echo "  1. Power Save"
                echo "  2. Balanced"
                echo "  3. Performance"
                echo -n "Choice (1-3): "
                read -r profile_choice
                case "$profile_choice" in
                    1) 
                        create_power_profile "powersave"
                        apply_power_profile "powersave"
                        ;;
                    2) 
                        create_power_profile "balanced"
                        apply_power_profile "balanced"
                        ;;
                    3) 
                        create_power_profile "performance"
                        apply_power_profile "performance"
                        ;;
                esac
                ;;
            3)
                configure_tlp
                ;;
            4)
                configure_powertop_autotune
                ;;
            5)
                optimize_services
                ;;
            6)
                monitor_power
                ;;
            7)
                echo -n "Enter profile name: "
                read -r profile_name
                create_power_profile "$profile_name"
                ;;
            8)
                echo -e "${GREEN}Goodbye!${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${RESET}"
                ;;
        esac
        
        echo
        echo -n "Press Enter to continue..."
        read -r
    done
}

main() {
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    sudo chmod 666 "$LOG_FILE"
    
    if [ $# -eq 0 ]; then
        interactive_menu
    else
        case "$1" in
            status)
                check_battery_info
                echo
                check_power_consumers
                ;;
            profile)
                if [ -z "${2:-}" ]; then
                    echo -e "${RED}Profile name required${RESET}"
                    exit 1
                fi
                apply_power_profile "$2"
                ;;
            monitor)
                monitor_power
                ;;
            tlp)
                configure_tlp
                ;;
            powertop)
                configure_powertop_autotune
                ;;
            optimize)
                optimize_services
                ;;
            --help)
                echo "Usage: $0 [COMMAND] [OPTIONS]"
                echo
                echo "Commands:"
                echo "  status            Show battery and power status"
                echo "  profile NAME      Apply power profile"
                echo "  monitor           Real-time power monitoring"
                echo "  tlp               Configure TLP"
                echo "  powertop          Configure PowerTOP"
                echo "  optimize          Optimize services"
                echo "  --help            Show this help"
                echo
                echo "Run without arguments for interactive mode"
                ;;
            *)
                echo -e "${RED}Unknown command: $1${RESET}"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    fi
}

main "$@"