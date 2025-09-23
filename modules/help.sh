#!/usr/bin/env bash
###############################################################################
# CAD-Droid Help & Intro Module
# Introduction, help information, and boot screen configuration
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_HELP_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_HELP_LOADED=1

# Show CAD-Droid introduction with gradient styling like the main installer
show_cad_droid_intro(){
  printf "\n"
  gradient_section_header
  printf "${PASTEL_CYAN}                          CAD-Droid Setup                        ${RESET}\n"
  gradient_section_footer
  printf "\n"
  
  printf "${PASTEL_LAVENDER}Welcome to CAD-Droid - Computer-Aided Development for Android!${RESET}\n\n"
  
  printf "${PASTEL_YELLOW}What CAD-Droid provides:${RESET}\n"
  printf "${PASTEL_CYAN}• ${RESET}Complete development environment on Android\n"
  printf "${PASTEL_CYAN}• ${RESET}XFCE desktop with Linux containers (Ubuntu)\n" 
  printf "${PASTEL_CYAN}• ${RESET}ADB wireless setup with phantom process killer disable\n"
  printf "${PASTEL_CYAN}• ${RESET}Essential Termux APKs with automated installation\n"
  printf "${PASTEL_CYAN}• ${RESET}Pastel-themed interface with productivity shortcuts\n"
  printf "${PASTEL_CYAN}• ${RESET}Widget shortcuts for quick system management\n\n"
  
  printf "${PASTEL_YELLOW}Installation process:${RESET}\n"
  printf "${PASTEL_CYAN}1. ${RESET}System setup and package installation\n"
  printf "${PASTEL_CYAN}2. ${RESET}APK downloads and installation guidance\n"
  printf "${PASTEL_CYAN}3. ${RESET}ADB setup for system optimization\n"
  printf "${PASTEL_CYAN}4. ${RESET}Desktop environment configuration\n"
  printf "${PASTEL_CYAN}5. ${RESET}Final system optimization and reboot\n\n"
  
  printf "${PASTEL_RED}Important:${RESET} This process may take 15-30 minutes depending on your internet connection.\n"
  printf "${PASTEL_YELLOW}Make sure you have a stable internet connection and sufficient storage space.${RESET}\n\n"
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    printf "${PASTEL_PINK}Press Enter to begin CAD-Droid installation...${RESET} "
    read -r || true
  fi
}

# Show help information with gradient styling
show_cad_droid_help(){
  printf "\n"
  gradient_line "#F080C0" "#00CED1" "="
  printf "${PASTEL_CYAN}%s${RESET}\n" "$(center_text 'CAD-Droid Help & Commands')"
  gradient_line "#F080C0" "#00CED1" "="
  printf "\n"
  
  printf "${PASTEL_YELLOW}Quick Start:${RESET}\n"
  printf "${PASTEL_CYAN}  cad-status${RESET}           - Show system status\n"
  printf "${PASTEL_CYAN}  cad-help${RESET}             - Show this help\n"
  printf "${PASTEL_CYAN}  cad-update${RESET}           - Update system packages\n\n"
  
  printf "${PASTEL_YELLOW}Desktop Environment:${RESET}\n"
  printf "${PASTEL_CYAN}  ~/.cad/scripts/start-xfce-termux.sh${RESET}     - Start XFCE in Termux\n"
  printf "${PASTEL_CYAN}  ~/.cad/scripts/start-xfce-container.sh${RESET}  - Start XFCE in container\n"
  printf "${PASTEL_CYAN}  pkill -f xfce${RESET}                           - Stop XFCE desktop\n\n"
  
  printf "${PASTEL_YELLOW}Container Management:${RESET}\n"
  printf "${PASTEL_CYAN}  proot-distro login ubuntu${RESET}               - Access Ubuntu container\n"
  printf "${PASTEL_CYAN}  proot-distro list${RESET}                       - List installed containers\n\n"
  
  printf "${PASTEL_YELLOW}ADB & System:${RESET}\n"
  printf "${PASTEL_CYAN}  adb devices${RESET}                             - Check ADB connection\n"
  printf "${PASTEL_CYAN}  adb shell${RESET}                               - Android shell access\n\n"
  
  printf "${PASTEL_YELLOW}Widget Shortcuts:${RESET}\n"
  printf "${PASTEL_CYAN}  phantom-killer${RESET}     - Disable phantom process killer\n"
  printf "${PASTEL_CYAN}  adb-connect${RESET}        - Connect ADB wirelessly\n"
  printf "${PASTEL_CYAN}  system-info${RESET}        - Show system information\n"
  printf "${PASTEL_CYAN}  file-manager${RESET}       - Open file manager\n"
  printf "${PASTEL_CYAN}  pkg-update${RESET}         - Update packages\n\n"
  
  printf "${PASTEL_YELLOW}Configuration Files:${RESET}\n"
  printf "${PASTEL_CYAN}  ~/.termux/termux.properties${RESET}             - Termux configuration\n"
  printf "${PASTEL_CYAN}  ~/.bashrc${RESET}                               - Shell configuration\n"
  printf "${PASTEL_CYAN}  ~/.nanorc${RESET}                               - Text editor settings\n\n"
  
  printf "${PASTEL_RED}Troubleshooting:${RESET}\n"
  printf "${PASTEL_LAVENDER}- If apps keep closing: Run phantom-killer widget${RESET}\n"
  printf "${PASTEL_LAVENDER}- If ADB disconnects: Use adb-connect widget${RESET}\n"
  printf "${PASTEL_LAVENDER}- If desktop won't start: Check Termux:X11 app permissions${RESET}\n"
  printf "${PASTEL_LAVENDER}- For system issues: Run cad-status for diagnostics${RESET}\n\n"
}

# Configure boot screen message
configure_boot_screen(){
  info "Configuring Termux boot screen..."
  
  # Create motd (message of the day)
  local motd_file="$PREFIX/etc/motd"
  cat > "$motd_file" << 'MOTD_EOF'

  ╔═══════════════════════════════════════════════════════════╗
  ║                        CAD-Droid                          ║
  ║              Computer-Aided Development                   ║
  ║                     for Android                           ║
  ╚═══════════════════════════════════════════════════════════╝

  Quick Commands:
    cad-status    - System status      cad-help      - Help & commands
    cad-update    - Update packages    phantom-killer - Fix app crashes
    
  Desktop:
    ~/.cad/scripts/start-xfce-termux.sh     - Start XFCE Desktop
    proot-distro login ubuntu               - Ubuntu Container
    
  Add Termux widgets to your home screen for quick access!
  
MOTD_EOF

  # Create welcome script that shows on first login
  local bashrc_addition="
# CAD-Droid welcome message (shown once per session)
if [ ! -f \"/tmp/cad_welcome_shown_\$\$\" ]; then
    if command -v cad-status >/dev/null 2>&1; then
        echo
        echo -e \"\\033[1;35mCAD-Droid Development Environment Active\\033[0m\"
        echo -e \"Type \\033[1;36mcad-help\\033[0m for commands and \\033[1;36mcad-status\\033[0m for system info\"
        echo
    fi
    touch \"/tmp/cad_welcome_shown_\$\$\"
fi
"

  # Add to bashrc if not already present
  if ! grep -q "CAD-Droid welcome message" "$HOME/.bashrc" 2>/dev/null; then
    echo "$bashrc_addition" >> "$HOME/.bashrc"
  fi
  
  ok "Boot screen configured"
}

# Export functions for use by other modules
export -f show_cad_droid_intro
export -f show_cad_droid_help
export -f configure_boot_screen