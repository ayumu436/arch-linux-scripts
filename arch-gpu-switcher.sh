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

CONFIG_FILE="$HOME/.config/arch-gpu-switcher/config"
LOG_FILE="/var/log/arch-gpu-switcher.log"
XORG_CONF_DIR="/etc/X11/xorg.conf.d"
MODPROBE_DIR="/etc/modprobe.d"
CURRENT_MODE_FILE="/var/lib/arch-gpu-switcher/current-mode"

print_header() {
    echo -e "${MAGENTA}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Arch Linux GPU Switcher                        ║"
    echo "║      Hybrid Graphics Management (Intel/NVIDIA/AMD)      ║"
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

detect_gpus() {
    echo -e "${CYAN}${BOLD}Detecting GPUs...${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    local intel_gpu=$(lspci | grep -i "vga.*intel" || true)
    local nvidia_gpu=$(lspci | grep -i "vga.*nvidia\|3d.*nvidia" || true)
    local amd_gpu=$(lspci | grep -i "vga.*amd\|vga.*ati" | grep -v "intel" || true)
    
    local gpu_count=0
    local available_gpus=()
    
    if [ -n "$intel_gpu" ]; then
        echo -e "${BLUE}Intel GPU detected:${RESET}"
        echo "  $intel_gpu"
        available_gpus+=("intel")
        ((gpu_count++))
    fi
    
    if [ -n "$nvidia_gpu" ]; then
        echo -e "${GREEN}NVIDIA GPU detected:${RESET}"
        echo "  $nvidia_gpu"
        available_gpus+=("nvidia")
        ((gpu_count++))
        
        if lsmod | grep -q "^nvidia"; then
            echo -e "  ${GREEN}NVIDIA driver loaded${RESET}"
        else
            echo -e "  ${YELLOW}NVIDIA driver not loaded${RESET}"
        fi
    fi
    
    if [ -n "$amd_gpu" ]; then
        echo -e "${RED}AMD GPU detected:${RESET}"
        echo "  $amd_gpu"
        available_gpus+=("amd")
        ((gpu_count++))
    fi
    
    if [ $gpu_count -lt 2 ]; then
        log_message WARNING "Only $gpu_count GPU detected. Hybrid graphics switching requires at least 2 GPUs."
    fi
    
    echo "${available_gpus[@]}"
}

check_current_gpu() {
    echo -e "${CYAN}${BOLD}Current GPU Configuration:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    local current_renderer=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs)
    local current_vendor=$(glxinfo 2>/dev/null | grep "OpenGL vendor" | cut -d: -f2 | xargs)
    
    if [ -n "$current_renderer" ]; then
        echo -e "${BLUE}OpenGL Renderer:${RESET} $current_renderer"
        echo -e "${BLUE}OpenGL Vendor:${RESET} $current_vendor"
    else
        log_message WARNING "Could not determine current GPU (glxinfo not available or X not running)"
    fi
    
    if [ -f "$CURRENT_MODE_FILE" ]; then
        local mode=$(cat "$CURRENT_MODE_FILE")
        echo -e "${BLUE}Configured Mode:${RESET} $mode"
    fi
    
    echo
    echo -e "${CYAN}Loaded GPU Modules:${RESET}"
    lsmod | grep -E "^(nvidia|nouveau|i915|amdgpu|radeon)" | awk '{print "  • " $1}' || echo "  None detected"
    
    if command -v nvidia-smi &> /dev/null; then
        echo
        echo -e "${CYAN}NVIDIA GPU Status:${RESET}"
        nvidia-smi --query-gpu=name,driver_version,power.draw,temperature.gpu,utilization.gpu --format=csv,noheader,nounits | \
            awk -F', ' '{printf "  GPU: %s\n  Driver: %s\n  Power: %sW\n  Temp: %s°C\n  Usage: %s%%\n", $1, $2, $3, $4, $5}'
    fi
}

check_power_usage() {
    echo -e "${CYAN}${BOLD}Power Management Status:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    if [ -f "/sys/class/power_supply/BAT0/power_now" ]; then
        local power_usage=$(cat /sys/class/power_supply/BAT0/power_now)
        local power_watts=$(echo "scale=2; $power_usage / 1000000" | bc)
        echo -e "${BLUE}Current Power Draw:${RESET} ${power_watts}W"
    fi
    
    if [ -d "/sys/bus/pci/devices" ]; then
        echo -e "${BLUE}GPU Power States:${RESET}"
        
        for gpu in /sys/bus/pci/devices/*/; do
            if grep -q "VGA\|3D" "${gpu}class" 2>/dev/null; then
                local vendor=$(cat "${gpu}vendor" 2>/dev/null)
                local device=$(cat "${gpu}device" 2>/dev/null)
                local power_state="unknown"
                
                if [ -f "${gpu}power_state" ]; then
                    power_state=$(cat "${gpu}power_state")
                elif [ -f "${gpu}power/runtime_status" ]; then
                    power_state=$(cat "${gpu}power/runtime_status")
                fi
                
                case "$vendor" in
                    "0x8086") echo "  Intel GPU: $power_state" ;;
                    "0x10de") echo "  NVIDIA GPU: $power_state" ;;
                    "0x1002") echo "  AMD GPU: $power_state" ;;
                esac
            fi
        done
    fi
    
    if command -v tlp-stat &> /dev/null; then
        echo
        echo -e "${BLUE}TLP Status:${RESET}"
        tlp-stat -g 2>/dev/null | grep -E "Runtime PM|power/" | head -5 | sed 's/^/  /'
    fi
}

switch_to_intel() {
    echo -e "${BLUE}${BOLD}Switching to Intel GPU...${RESET}"
    
    if [ -f "$XORG_CONF_DIR/20-nvidia.conf" ]; then
        sudo mv "$XORG_CONF_DIR/20-nvidia.conf" "$XORG_CONF_DIR/20-nvidia.conf.bak"
        log_message INFO "Disabled NVIDIA Xorg configuration"
    fi
    
    cat << EOF | sudo tee "$XORG_CONF_DIR/20-intel.conf" > /dev/null
Section "Device"
    Identifier  "Intel Graphics"
    Driver      "modesetting"
    BusID       "$(lspci | grep -i "vga.*intel" | cut -d' ' -f1 | sed 's/\./:/g' | sed 's/^/PCI:/')"
    Option      "TearFree"    "true"
    Option      "DRI"         "3"
EndSection
EOF
    
    cat << EOF | sudo tee "$MODPROBE_DIR/nvidia-power.conf" > /dev/null
# Disable NVIDIA GPU for power saving
options nouveau modeset=0
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
EOF
    
    echo "bbswitch" | sudo tee /etc/modules-load.d/bbswitch.conf > /dev/null
    echo "options bbswitch load_state=0 unload_state=0" | sudo tee "$MODPROBE_DIR/bbswitch.conf" > /dev/null
    
    sudo mkdir -p "$(dirname "$CURRENT_MODE_FILE")"
    echo "intel" | sudo tee "$CURRENT_MODE_FILE" > /dev/null
    
    log_message SUCCESS "Switched to Intel GPU mode"
    echo -e "${YELLOW}Please reboot for changes to take effect${RESET}"
}

switch_to_nvidia() {
    echo -e "${GREEN}${BOLD}Switching to NVIDIA GPU...${RESET}"
    
    if [ -f "$XORG_CONF_DIR/20-intel.conf" ]; then
        sudo mv "$XORG_CONF_DIR/20-intel.conf" "$XORG_CONF_DIR/20-intel.conf.bak"
        log_message INFO "Disabled Intel Xorg configuration"
    fi
    
    cat << EOF | sudo tee "$XORG_CONF_DIR/20-nvidia.conf" > /dev/null
Section "ServerLayout"
    Identifier     "Layout0"
    Screen      0  "Screen0"
EndSection

Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "$(lspci | grep -i "3d.*nvidia\|vga.*nvidia" | head -1 | cut -d' ' -f1 | sed 's/\./:/g' | sed 's/^/PCI:/')"
    Option         "NoLogo" "true"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    DefaultDepth    24
    Option         "Coolbits" "28"
    SubSection     "Display"
        Depth       24
    EndSubSection
EndSection
EOF
    
    if [ -f "$MODPROBE_DIR/nvidia-power.conf" ]; then
        sudo rm "$MODPROBE_DIR/nvidia-power.conf"
    fi
    
    if [ -f /etc/modules-load.d/bbswitch.conf ]; then
        sudo rm /etc/modules-load.d/bbswitch.conf
    fi
    
    echo "nvidia" | sudo tee /etc/modules-load.d/nvidia.conf > /dev/null
    echo "nvidia_drm" | sudo tee -a /etc/modules-load.d/nvidia.conf > /dev/null
    echo "nvidia_uvm" | sudo tee -a /etc/modules-load.d/nvidia.conf > /dev/null
    
    sudo mkdir -p "$(dirname "$CURRENT_MODE_FILE")"
    echo "nvidia" | sudo tee "$CURRENT_MODE_FILE" > /dev/null
    
    log_message SUCCESS "Switched to NVIDIA GPU mode"
    echo -e "${YELLOW}Please reboot for changes to take effect${RESET}"
}

switch_to_hybrid() {
    echo -e "${CYAN}${BOLD}Switching to Hybrid Graphics (PRIME)...${RESET}"
    
    for conf in "$XORG_CONF_DIR"/20-{intel,nvidia,amd}.conf; do
        [ -f "$conf" ] && sudo mv "$conf" "$conf.bak"
    done
    
    cat << EOF | sudo tee "$XORG_CONF_DIR/20-prime.conf" > /dev/null
Section "Device"
    Identifier  "iGPU"
    Driver      "modesetting"
    BusID       "$(lspci | grep -i "vga.*intel" | cut -d' ' -f1 | sed 's/\./:/g' | sed 's/^/PCI:/')"
EndSection

Section "Device"
    Identifier  "dGPU"
    Driver      "nvidia"
    BusID       "$(lspci | grep -i "3d.*nvidia\|vga.*nvidia" | head -1 | cut -d' ' -f1 | sed 's/\./:/g' | sed 's/^/PCI:/')"
EndSection

Section "Screen"
    Identifier "iGPU"
    Device "iGPU"
EndSection

Section "ServerLayout"
    Identifier "layout"
    Screen 0 "iGPU"
    Option "AllowNVIDIAGPUScreens"
EndSection
EOF
    
    echo "nvidia_drm modeset=1" | sudo tee "$MODPROBE_DIR/nvidia-drm.conf" > /dev/null
    
    cat << 'EOF' | sudo tee /usr/local/bin/prime-run > /dev/null
#!/bin/bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
exec "$@"
EOF
    sudo chmod +x /usr/local/bin/prime-run
    
    sudo mkdir -p "$(dirname "$CURRENT_MODE_FILE")"
    echo "hybrid" | sudo tee "$CURRENT_MODE_FILE" > /dev/null
    
    log_message SUCCESS "Switched to Hybrid Graphics mode"
    echo -e "${GREEN}Use 'prime-run <application>' to run apps on NVIDIA GPU${RESET}"
    echo -e "${YELLOW}Please reboot for changes to take effect${RESET}"
}

install_dependencies() {
    echo -e "${CYAN}${BOLD}Checking dependencies...${RESET}"
    
    local packages=()
    local nvidia_type=""
    
    if lspci | grep -qi nvidia; then
        echo -e "${YELLOW}NVIDIA GPU detected. Select driver type:${RESET}"
        echo "  1. Proprietary (nvidia)"
        echo "  2. Open source (nouveau)"
        echo -n "Choice (1-2): "
        read -r driver_choice
        
        if [ "$driver_choice" = "1" ]; then
            packages+=("nvidia" "nvidia-utils" "nvidia-settings")
            nvidia_type="proprietary"
        else
            packages+=("xf86-video-nouveau" "mesa")
            nvidia_type="nouveau"
        fi
    fi
    
    if lspci | grep -qi "vga.*intel"; then
        packages+=("xf86-video-intel" "mesa" "vulkan-intel")
    fi
    
    if lspci | grep -qi "vga.*amd\|vga.*ati"; then
        packages+=("xf86-video-amdgpu" "mesa" "vulkan-radeon")
    fi
    
    packages+=("bbswitch" "acpi_call")
    
    local missing=()
    for pkg in "${packages[@]}"; do
        if ! pacman -Qi "$pkg" &> /dev/null; then
            missing+=("$pkg")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing missing packages: ${missing[*]}${RESET}"
        sudo pacman -S --needed "${missing[@]}"
    else
        echo -e "${GREEN}All dependencies installed${RESET}"
    fi
    
    if [ "$nvidia_type" = "proprietary" ] && ! lsmod | grep -q "^nvidia"; then
        echo -e "${YELLOW}Loading NVIDIA modules...${RESET}"
        sudo modprobe nvidia
        sudo modprobe nvidia_drm
        sudo modprobe nvidia_uvm
    fi
}

configure_optimus_manager() {
    echo -e "${CYAN}${BOLD}Installing Optimus Manager...${RESET}"
    
    if ! command -v optimus-manager &> /dev/null; then
        if command -v yay &> /dev/null; then
            yay -S optimus-manager optimus-manager-qt
        elif command -v paru &> /dev/null; then
            paru -S optimus-manager optimus-manager-qt
        else
            log_message WARNING "AUR helper not found. Please install optimus-manager manually"
            return 1
        fi
    fi
    
    sudo systemctl enable optimus-manager
    sudo systemctl start optimus-manager
    
    mkdir -p "$HOME/.config/optimus-manager"
    cat << EOF > "$HOME/.config/optimus-manager/optimus-manager.conf"
[intel]
DRI=3
accel=
driver=modesetting
modeset=yes
tearfree=yes

[nvidia]
DPI=96
PAT=yes
allow_external_gpus=no
dynamic_power_management=no
ignore_abi=no
modeset=yes
options=overclocking

[optimus]
auto_logout=yes
pci_power_control=no
pci_remove=no
pci_reset=no
startup_auto_battery_mode=intel
startup_auto_extpower_mode=nvidia
startup_mode=intel
switching=none
EOF
    
    log_message SUCCESS "Optimus Manager configured"
}

benchmark_gpu() {
    echo -e "${CYAN}${BOLD}GPU Benchmark:${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    
    if ! command -v glxgears &> /dev/null; then
        echo -e "${YELLOW}Installing mesa-demos for benchmarking...${RESET}"
        sudo pacman -S --needed mesa-demos
    fi
    
    echo -e "${BLUE}Running glxgears benchmark (5 seconds)...${RESET}"
    timeout 5 glxgears 2>&1 | grep FPS | tail -n 5
    
    if command -v glmark2 &> /dev/null; then
        echo
        echo -e "${BLUE}Running glmark2 benchmark...${RESET}"
        glmark2 --off-screen --validate 2>&1 | grep Score
    else
        echo -e "${DIM}Install glmark2 for more detailed benchmarking${RESET}"
    fi
    
    if command -v nvidia-smi &> /dev/null; then
        echo
        echo -e "${BLUE}NVIDIA GPU Performance:${RESET}"
        nvidia-smi dmon -c 1
    fi
}

interactive_menu() {
    while true; do
        print_header
        detect_gpus > /dev/null 2>&1
        check_current_gpu
        echo
        echo -e "${CYAN}Select an option:${RESET}"
        echo
        echo "  1. Switch to Intel GPU (Power Saving)"
        echo "  2. Switch to NVIDIA GPU (Performance)"
        echo "  3. Switch to Hybrid Mode (PRIME)"
        echo "  4. Check power usage"
        echo "  5. Benchmark current GPU"
        echo "  6. Install dependencies"
        echo "  7. Configure Optimus Manager"
        echo "  8. Exit"
        echo
        echo -n "Enter your choice (1-8): "
        read -r choice
        
        case "$choice" in
            1)
                switch_to_intel
                ;;
            2)
                switch_to_nvidia
                ;;
            3)
                switch_to_hybrid
                ;;
            4)
                check_power_usage
                ;;
            5)
                benchmark_gpu
                ;;
            6)
                install_dependencies
                ;;
            7)
                configure_optimus_manager
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
    if [ "$EUID" -eq 0 ] && [ "$1" != "--internal-sudo" ]; then
        log_message ERROR "Do not run as root directly"
        exit 1
    fi
    
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    sudo chmod 666 "$LOG_FILE"
    
    if [ $# -eq 0 ]; then
        interactive_menu
    else
        case "$1" in
            intel)
                switch_to_intel
                ;;
            nvidia)
                switch_to_nvidia
                ;;
            hybrid)
                switch_to_hybrid
                ;;
            status)
                detect_gpus
                echo
                check_current_gpu
                echo
                check_power_usage
                ;;
            benchmark)
                benchmark_gpu
                ;;
            install)
                install_dependencies
                ;;
            --help)
                echo "Usage: $0 [COMMAND]"
                echo
                echo "Commands:"
                echo "  intel      Switch to Intel GPU"
                echo "  nvidia     Switch to NVIDIA GPU"
                echo "  hybrid     Switch to Hybrid mode (PRIME)"
                echo "  status     Show current GPU status"
                echo "  benchmark  Run GPU benchmark"
                echo "  install    Install dependencies"
                echo "  --help     Show this help message"
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