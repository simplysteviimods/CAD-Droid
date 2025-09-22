#!/usr/bin/env bash
###############################################################################
# CAD-Droid Completion Module
# Final setup completion and system reboot functionality
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_COMPLETION_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_COMPLETION_LOADED=1

# Show completion summary
show_completion_summary(){
  info "CAD-Droid setup completed successfully!"
  
  # Use the styled card function instead of ASCII art
  draw_card "CAD-Droid Setup Complete!" "Your Android device is now a powerful development workstation"
  
  printf "${PASTEL_CYAN}What's been installed:${RESET}\n"
  printf "${PASTEL_GREEN}✓${RESET} Core system packages and development tools\n"
  printf "${PASTEL_GREEN}✓${RESET} Optimized repository mirrors for your region\n"
  printf "${PASTEL_GREEN}✓${RESET} XFCE desktop environment (Termux + Container)\n"
  printf "${PASTEL_GREEN}✓${RESET} Essential Termux APKs downloaded and ready\n"
  printf "${PASTEL_GREEN}✓${RESET} SSH access and security configurations\n"
  printf "${PASTEL_GREEN}✓${RESET} Pastel-themed configurations throughout\n\n"
  
  printf "${PASTEL_CYAN}Quick Start Commands:${RESET}\n"
  printf "${PASTEL_LAVENDER}Start XFCE Desktop:${RESET} ~/.cad/scripts/start-xfce-termux.sh\n"
  printf "${PASTEL_LAVENDER}Container Desktop:${RESET} ~/.cad/scripts/start-xfce-container.sh\n"
  printf "${PASTEL_LAVENDER}Configuration:${RESET} ~/.cad/config/\n"
  printf "${PASTEL_LAVENDER}Scripts:${RESET} ~/.cad/scripts/\n\n"
  
  printf "${PASTEL_YELLOW}Note:${RESET} A Termux restart is recommended to apply all changes\n\n"
}

# Configure bash with pastel colors for the final restart
configure_completion_bashrc(){
  info "Applying final bash configuration..."
  
  local bashrc_addition="$HOME/.bashrc_cad_completion"
  
  cat > "$bashrc_addition" << 'BASHRC_COMPLETION_EOF'
# CAD-Droid Final Configuration - Pastel Theme
# Applied after successful setup completion

# Pastel color definitions for terminal
export PASTEL_CYAN='\033[38;2;175;238;238m'
export PASTEL_PINK='\033[38;2;255;201;217m'
export PASTEL_LAVENDER='\033[38;2;220;201;255m'
export PASTEL_GREEN='\033[38;2;201;255;209m'
export PASTEL_YELLOW='\033[38;2;255;235;169m'
export RESET='\033[0m'

# Enhanced prompt with pastel colors
PS1="\[$PASTEL_CYAN\]┌─[\[$PASTEL_PINK\]\u\[$PASTEL_LAVENDER\]@\[$PASTEL_PINK\]\h\[$PASTEL_CYAN\]]─[\[$PASTEL_GREEN\]\w\[$PASTEL_CYAN\]]\n└─\[$PASTEL_LAVENDER\]\$\[$RESET\] "

# Welcome message
echo -e "${PASTEL_PINK}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${PASTEL_CYAN}║                    🚀 CAD-Droid Ready! 🚀                   ║${RESET}"
echo -e "${PASTEL_PINK}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo -e "${PASTEL_LAVENDER}Your mobile development environment is ready to use!${RESET}\n"

# Helpful aliases with pastel feedback
alias cad-start='echo -e "${PASTEL_CYAN}Starting XFCE Desktop...${RESET}" && ~/.cad/scripts/start-xfce-termux.sh'
alias cad-container='echo -e "${PASTEL_CYAN}Starting Container Desktop...${RESET}" && ~/.cad/scripts/start-xfce-container.sh'
alias cad-stop='echo -e "${PASTEL_YELLOW}Stopping desktop environment...${RESET}" && pkill -f xfce'
alias cad-status='echo -e "${PASTEL_GREEN}Checking CAD-Droid status...${RESET}" && ps aux | grep -E "(xfce|termux-x11)" | grep -v grep'

# Enhanced ls with colors
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'

# Development shortcuts
alias py='python'
alias ipy='ipython'
alias nv='nvim'
alias clr='clear'

# Git shortcuts with pastel status
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline'

echo -e "${PASTEL_LAVENDER}Type 'cad-start' to launch your desktop environment${RESET}"
BASHRC_COMPLETION_EOF

  # Append to main bashrc
  if ! grep -q "CAD-Droid Final Configuration" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# Source CAD-Droid completion configuration" >> "$HOME/.bashrc"
    echo "[ -f ~/.bashrc_cad_completion ] && source ~/.bashrc_cad_completion" >> "$HOME/.bashrc"
  fi
  
  ok "Final bash configuration applied"
}

# Prompt for Termux restart
prompt_termux_reboot(){
  info "Setup completion process finished"
  
  printf "\n${PASTEL_PINK}═══════════════════════════════════════════════════════════════${RESET}\n"
  printf "${PASTEL_YELLOW}                      🔄 RESTART REQUIRED 🔄                   ${RESET}\n"
  printf "${PASTEL_PINK}═══════════════════════════════════════════════════════════════${RESET}\n\n"
  
  printf "${PASTEL_LAVENDER}To complete the installation and apply all configurations,${RESET}\n"
  printf "${PASTEL_LAVENDER}Termux needs to be restarted.${RESET}\n\n"
  
  printf "${PASTEL_CYAN}This will:${RESET}\n"
  printf "${PASTEL_GREEN}•${RESET} Apply all pastel color configurations\n"
  printf "${PASTEL_GREEN}•${RESET} Load enhanced bash prompt and aliases\n"
  printf "${PASTEL_GREEN}•${RESET} Activate desktop environment shortcuts\n"
  printf "${PASTEL_GREEN}•${RESET} Ensure all services start correctly\n\n"
  
  printf "${PASTEL_PINK}Press Enter to reboot Termux...${RESET} "
  
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    read -r || true
  else
    printf "(auto-restart in 5 seconds)\n"
    sleep 5
  fi
  
  # Show countdown
  printf "\n${PASTEL_YELLOW}Restarting Termux in...${RESET}\n"
  for i in 3 2 1; do
    printf "${PASTEL_CYAN}$i${RESET}..."
    sleep 1
  done
  printf "${PASTEL_GREEN}GO!${RESET}\n\n"
  
  # Execute the restart
  exec "$PREFIX/bin/bash" -l
}

# Main completion function
complete_setup(){
  info "Finalizing CAD-Droid setup..."
  
  # Show completion summary
  show_completion_summary
  
  # Apply final bash configuration
  configure_completion_bashrc
  
  # Prompt for restart
  prompt_termux_reboot
}

# Export functions for use by other modules
export -f show_completion_summary
export -f configure_completion_bashrc
export -f prompt_termux_reboot
export -f complete_setup
