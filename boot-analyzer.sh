#!/usr/bin/env bash
# boot-analyzer.sh - The Boot Time Doctor
#
# DESCRIPTION:
# A script that provides a user-friendly and actionable report on system
# boot performance using the power of `systemd-analyze`.
#
# USAGE:
# ./boot-analyzer.sh

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

# --- Core Functions ---

analyze_blame() {
    header "Top 10 Services by Boot Time (systemd-analyze blame)"
    systemd-analyze blame | head -n 10 | sed -E "s/^([ 0-9\.]+[a-z]+)/${RED}\1${RESET}/"
}

analyze_critical_chain() {
    header "Critical Chain Analysis (systemd-analyze critical-chain)"
    # Colorize the service names in the output
    systemd-analyze critical-chain | sed -E "s/(@[0-9\.]+s)/${YELLOW}\1${RESET}/g" | sed -E "s/([a-zA-Z\.-]+\.service)/${GREEN}\1${RESET}/g"
}

plot_boot() {
    header "Generating SVG Boot Plot"
    local plot_file="${HOME}/boot-plot_$(date +%Y-%m-%d_%H%M).svg"
    log "Generating plot, this may take a second..."
    systemd-analyze plot > "$plot_file"
    echo "${GREEN}${BOLD}[OK]${RESET} Boot plot saved to: ${BOLD}${plot_file}${RESET}"
    log "You can open this file in any web browser to see a detailed boot chart."
}

show_tips() {
    header "General Performance Tips"
    echo " - Review the services in the '''blame''' list. Do you need all of them?"
    echo "   Use '''sudo systemctl disable <service_name>''' to disable unnecessary services."
    echo " - Check the '''critical-chain'''. A slow network or disk can delay many other units."
    echo " - For a deep dive, open the generated SVG plot in a browser."
}

# --- Main Execution ---
main() {
    echo "${BOLD}Starting Boot Time Analysis...${RESET}"
    
    analyze_blame
    analyze_critical_chain
    plot_boot
    show_tips

    echo -e "\n${GREEN}Analysis complete.${RESET}"
}

main "$@"
