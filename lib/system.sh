#!/usr/bin/env bash
# system.sh - System detection and configuration with proper variable initialization
# This module handles Android/Termux-specific operations and system configuration

# Prevent multiple sourcing
if [[ "${CAD_SYSTEM_LOADED:-}" == "1" ]]; then
    return 0
fi
export CAD_SYSTEM_LOADED=1

# Source required modules
# Use SCRIPT_DIR from main script if available, otherwise determine it
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# If we're in the lib directory, look for modules there
if [[ "$(basename "$SCRIPT_DIR")" == "lib" ]]; then
  source "$SCRIPT_DIR/colors.sh"
  source "$SCRIPT_DIR/utils.sh"
  source "$SCRIPT_DIR/input.sh"
else
  source "$SCRIPT_DIR/lib/colors.sh"
  source "$SCRIPT_DIR/lib/utils.sh"
  source "$SCRIPT_DIR/lib/input.sh"
fi

# System configuration variables - ensure all have proper defaults
export DISTRO="${DISTRO:-ubuntu}"
export LINUX_SSH_PORT="${LINUX_SSH_PORT:-2222}"
export UBUNTU_USERNAME="${UBUNTU_USERNAME:-developer}"
export TERMUX_USERNAME="${TERMUX_USERNAME:-$(whoami 2>/dev/null || echo 'termux')}"

# Path configuration - ensure all are properly initialized
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
export TERMUX_TMPDIR="${TMPDIR:-${PREFIX}/tmp}"

# Git configuration - ensure variables exist
export GIT_USERNAME="${GIT_USERNAME:-}"
export GIT_EMAIL="${GIT_EMAIL:-}"

# Display and device detection constants
export MIN_PHONE_WIDTH="${MIN_PHONE_WIDTH:-600}"
export MAX_PHONE_WIDTH="${MAX_PHONE_WIDTH:-1200}"
export MIN_PHONE_ASPECT="${MIN_PHONE_ASPECT:-150}"

# Storage paths with fallbacks
declare -a STORAGE_CANDIDATES
STORAGE_CANDIDATES=(
  "${TERMUX_HOME}/storage/shared"
  "/storage/emulated/0" 
  "/sdcard"
  "$TERMUX_HOME"
)

# Detect primary storage location with comprehensive fallback
detect_primary_storage(){
  local storage_path=""
  
  # Test each candidate path
  for path in "${STORAGE_CANDIDATES[@]}"; do
    if [ -n "$path" ] && [ -d "$path" ] && [ -w "$path" ] 2>/dev/null; then
      storage_path="$path"
      break
    fi
  done
  
  # Final fallback to HOME if nothing else works
  if [ -z "$storage_path" ]; then
    storage_path="$TERMUX_HOME"
  fi
  
  echo "$storage_path"
}

# Detect if running on phone vs tablet based on screen characteristics
detect_phone(){
  local width="${1:-}" height="${2:-}"
  local detected=0
  
  # Try to get display dimensions if not provided
  if [ -z "$width" ] || [ -z "$height" ]; then
    # Try wm command first
    if command -v wm >/dev/null 2>&1; then
      local size_output
      size_output=$(wm size 2>/dev/null | grep "Physical size" | cut -d: -f2 | tr -d ' ')
      if [ -n "$size_output" ] && echo "$size_output" | grep -q "x"; then
        width=$(echo "$size_output" | cut -dx -f1)
        height=$(echo "$size_output" | cut -dx -f2)
        detected=1
      fi
    fi
    
    # Fallback to framebuffer info
    if [ "$detected" -eq 0 ] && [ -r /sys/class/graphics/fb0/virtual_size ]; then
      local fb_size
      fb_size=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)
      if [ -n "$fb_size" ] && echo "$fb_size" | grep -q ","; then
        width=$(echo "$fb_size" | cut -d, -f1)
        height=$(echo "$fb_size" | cut -d, -f2)
        detected=1
      fi
    fi
  fi
  
  # Validate dimensions are numeric
  case "$width" in *[!0-9]*) width="0" ;; esac
  case "$height" in *[!0-9]*) height="0" ;; esac
  
  # If we still don't have valid dimensions, assume phone
  if [ "$width" -le 0 ] || [ "$height" -le 0 ]; then
    return 0  # Default to phone
  fi
  
  # Calculate aspect ratio (width/height * 100 for integer math)
  local aspect_ratio=100
  if [ "$height" -gt 0 ]; then
    aspect_ratio=$((width * 100 / height))
  fi
  
  # Phone detection logic:
  # - Aspect ratio > 150 (1.5:1) suggests portrait/narrow device
  # - Width < 1200 suggests smaller screen
  if [ "$aspect_ratio" -gt "$MIN_PHONE_ASPECT" ] && [ "$width" -lt "$MAX_PHONE_WIDTH" ]; then
    return 0  # Phone
  else
    return 1  # Tablet/larger device
  fi
}

# Test if Termux:API is available and functional
test_termux_api(){
  # Check if termux-api package is installed
  if ! dpkg_is_installed termux-api; then
    return 1
  fi
  
  # Test if termux-api commands work
  if command -v termux-toast >/dev/null 2>&1; then
    # Test with a quick toast message
    if timeout 3 termux-toast "API test" 2>/dev/null; then
      return 0
    fi
  fi
  
  # Test with a safer command that doesn't show UI
  if command -v termux-battery-status >/dev/null 2>&1; then
    if timeout 3 termux-battery-status >/dev/null 2>&1; then
      return 0
    fi
  fi
  
  return 1
}

# Check if a Linux distribution is already installed
is_distro_installed(){ 
  local distro="${1:-$DISTRO}"
  
  # Validate distro name
  if [ -z "$distro" ]; then
    return 1
  fi
  
  # Check if the rootfs directory exists
  local rootfs_path="${PREFIX}/var/lib/proot-distro/installed-rootfs/$distro"
  [ -d "$rootfs_path" ]
}

# Detect host operating system in container with comprehensive fallback
detect_os(){ 
  local os_id="unknown"
  
  # Primary method: /etc/os-release
  if [ -f /etc/os-release ]; then
    os_id=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | head -1)
  fi
  
  # Fallback methods if primary fails
  if [ "$os_id" = "unknown" ] || [ -z "$os_id" ]; then
    if [ -f /etc/debian_version ]; then
      os_id="debian"
    elif [ -f /etc/alpine-release ]; then
      os_id="alpine"
    elif [ -f /etc/arch-release ]; then
      os_id="arch"
    elif [ -f /etc/redhat-release ]; then
      os_id="redhat"
    elif [ -f /etc/SuSE-release ]; then
      os_id="suse"
    fi
  fi
  
  # Ensure we return something valid
  if [ -z "$os_id" ]; then
    os_id="unknown"
  fi
  
  echo "$os_id"
}

# Install packages on Debian-based systems with error handling
pkg_install_debian(){
  local packages=("$@")
  
  if [ "${#packages[@]}" -eq 0 ]; then
    return 0
  fi
  
  # Update package list with error handling
  local update_result=0
  DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || update_result=$?
  
  if [ "$update_result" -ne 0 ]; then
    warn "Package list update failed, continuing anyway"
  fi
  
  # Install packages with proper error handling
  local install_result=0
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}" >/dev/null 2>&1 || install_result=$?
  
  return "$install_result"
}

# Install packages on Arch-based systems with error handling
pkg_install_arch(){
  local packages=("$@")
  
  if [ "${#packages[@]}" -eq 0 ]; then
    return 0
  fi
  
  # Update package list and install with error handling
  local result=0
  pacman -Sy --noconfirm "${packages[@]}" >/dev/null 2>&1 || result=$?
  
  return "$result"
}

# Install packages on Alpine-based systems with error handling
pkg_install_alpine(){
  local packages=("$@")
  
  if [ "${#packages[@]}" -eq 0 ]; then
    return 0
  fi
  
  # Update package list
  local update_result=0
  apk update >/dev/null 2>&1 || update_result=$?
  
  if [ "$update_result" -ne 0 ]; then
    warn "Alpine package list update failed"
  fi
  
  # Install packages
  local install_result=0
  apk add "${packages[@]}" >/dev/null 2>&1 || install_result=$?
  
  return "$install_result"
}

# Generic package installation that detects OS
install_packages(){
  local packages=("$@")
  
  if [ "${#packages[@]}" -eq 0 ]; then
    return 0
  fi
  
  local os
  os=$(detect_os)
  local result=0
  
  case "$os" in
    debian|ubuntu)
      pkg_install_debian "${packages[@]}" || result=$?
      ;;
    arch|manjaro)  
      pkg_install_arch "${packages[@]}" || result=$?
      ;;
    alpine)
      pkg_install_alpine "${packages[@]}" || result=$?
      ;;
    *)
      warn "Unknown OS: $os, attempting debian-style installation"
      pkg_install_debian "${packages[@]}" || result=$?
      ;;
  esac
  
  return "$result"
}

# Configure nano editor with enhanced settings and error handling
configure_nano_editor(){
  local nano_config="${TERMUX_HOME}/.nanorc"
  
  info "Setting up nano editor configuration..."
  
  # Backup existing config if it exists
  if [ -f "$nano_config" ]; then
    backup_file "$nano_config" >/dev/null 2>&1 || true
  fi
  
  # Create nano configuration with error handling
  if cat > "$nano_config" << 'NANO_CONFIG_EOF'
# Nano configuration for mobile development
# Enhanced settings for Termux environment

# Visual enhancements
set linenumbers
set titlecolor brightwhite,blue
set statuscolor brightwhite,green
set numbercolor cyan
set keycolor cyan
set functioncolor green

# Editing behavior
set tabsize 4
set tabstospaces
set autoindent
set smooth
set mouse
set softwrap

# Show whitespace characters
set whitespace "»·"

# Better search and replace
set casesensitive
set regexp

# Include syntax files if available
include "/data/data/com.termux/files/usr/share/nano/*.nanorc"

# Additional syntax highlighting if directory exists
include "/data/data/com.termux/files/usr/share/nano/extra/*.nanorc"
NANO_CONFIG_EOF
then
    ok "Nano editor configured with enhanced settings"
    return 0
  else
    warn "Failed to create nano configuration"
    return 1
  fi
}

# Configure enhanced Bash environment with comprehensive error handling
configure_bash_environment(){
  info "Configuring enhanced Bash environment..."
  
  # Initialize user variables
  initialize_user_vars
  
  local bashrc="${TERMUX_HOME}/.bashrc"
  local current_user="${TERMUX_USERNAME:-termux}"
  local current_date
  current_date=$(date 2>/dev/null || echo "unknown")
  
  # Backup existing .bashrc
  if [ -f "$bashrc" ]; then
    backup_file "$bashrc" >/dev/null 2>&1 || true
  fi
  
  # Create enhanced .bashrc with comprehensive configuration
  if cat > "$bashrc" << BASH_CONFIG_EOF
# Enhanced Bash configuration for CAD-Droid Mobile Development
# Generated by CAD-Droid Setup for user: $current_user
# Configuration date: $current_date

# Shell safety and options
set -o noclobber        # Prevent accidental file overwrites
set -o pipefail         # Better pipeline error handling  
shopt -s extglob        # Advanced globbing
shopt -s checkwinsize   # Update window size after commands
set +H                  # Disable history expansion (safer)

# History configuration
export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTCONTROL=ignoreboth:erasedups
export HISTIGNORE="ls:ps:history:exit:clear:pwd"
shopt -s histappend     # Append to history file
shopt -s cmdhist        # Save multi-line commands as one

# User environment variables
export CAD_TERMUX_USER="$current_user"
export CAD_GIT_USER="${GIT_USERNAME:-}"
export CAD_GIT_EMAIL="${GIT_EMAIL:-}"
export CAD_SETUP_DATE="$current_date"
export CAD_SETUP_VERSION="${SCRIPT_VERSION:-2.0.0}"

# Path enhancements
export PATH="\$HOME/.local/bin:\$PREFIX/bin:\$PATH"

# Color support detection and setup
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "\$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  # Enhanced color palette with proper fallbacks
  export PASTEL_PURPLE='\033[38;2;221;160;221m'
  export PASTEL_PINK='\033[38;2;255;182;193m'
  export PASTEL_MAGENTA='\033[38;2;255;192;203m'
  export PASTEL_CYAN='\033[38;2;175;238;238m'
  export PASTEL_GREEN='\033[38;2;144;238;144m'
  export PASTEL_YELLOW='\033[38;2;255;255;224m'
  export PASTEL_BLUE='\033[38;2;173;216;230m'
  export PASTEL_ORANGE='\033[38;2;255;218;185m'
  export RESET='\033[0m'
  
  # Enhanced colorful prompt
  if [ -n "\${PS1-}" ]; then
    PS1="\[\${PASTEL_PINK}\]\u\[\${RESET}\]@\[\${PASTEL_MAGENTA}\]\h\[\${RESET}\]:\[\${PASTEL_CYAN}\]\w\[\${RESET}\]\[\${PASTEL_GREEN}\]\\\$\[\${RESET}\] \[\${PASTEL_PURPLE}\]"
    # Reset color after each command
    PROMPT_COMMAND="echo -ne '\${RESET}'"
  fi
else
  # Fallback for limited terminals
  if [ -n "\${PS1-}" ]; then
    PS1='\u@\h:\w\\\$ '
  fi
fi

# Development-focused aliases
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias lla='ls -la --color=auto'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Navigation aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'

# Git shortcuts with error handling
alias gs='git status 2>/dev/null || echo "Not in a git repository"'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'

# Development aliases
alias py='python3'
alias pip='pip3'
alias serve='python3 -m http.server'
alias ports='netstat -tuln'

# Termux-specific aliases
alias termux-info='echo "User: \$CAD_TERMUX_USER | Setup: \$CAD_SETUP_DATE | Version: \$CAD_SETUP_VERSION"'
alias storage-info='df -h \$HOME'
alias update-all='pkg update && pkg upgrade'

# Container management
alias ubuntu='proot-distro login ubuntu'
alias container-list='proot-distro list'
alias container-status='proot-distro list --installed'

# Function to change terminal colors
change_terminal_color() {
  local color="\$1"
  case "\$color" in
    cyan|blue|green|yellow|purple|pink|magenta|orange)
      sed -i "s/PASTEL_PURPLE/PASTEL_\${color^^}/g" ~/.bashrc
      echo "Terminal color changed to \$color. Restart terminal to see changes."
      ;;
    *)
      echo "Available colors: cyan, blue, green, yellow, purple, pink, magenta, orange"
      ;;
  esac
}

# Quick system information function
sysinfo() {
  echo "=== CAD-Droid System Information ==="
  echo "User: \$CAD_TERMUX_USER"
  echo "Setup Date: \$CAD_SETUP_DATE"
  echo "Architecture: \$(uname -m 2>/dev/null || echo 'unknown')"
  echo "Kernel: \$(uname -r 2>/dev/null || echo 'unknown')"
  if command -v df >/dev/null 2>&1; then
    echo "Storage: \$(df -h \$HOME | tail -1 | awk '{print \$4}') available"
  fi
  echo "=================================="
}

# Load bash completions if available
if [ -f "\${PREFIX}/etc/bash_completion" ] && ! shopt -oq posix; then
    source "\${PREFIX}/etc/bash_completion"
fi

# Load custom user configurations if they exist
if [ -f "\$HOME/.bashrc.local" ]; then
    source "\$HOME/.bashrc.local"
fi

# Welcome message for new sessions
if [ -t 0 ] && [ -t 1 ] && [ -n "\$PS1" ]; then
  echo -e "\${PASTEL_MAGENTA}Welcome to CAD-Droid Mobile Development Environment!\${RESET}"
  echo -e "\${PASTEL_CYAN}Type 'sysinfo' for system information or 'termux-info' for user details\${RESET}"
fi
BASH_CONFIG_EOF
then
    ok "Enhanced Bash environment configured"
    return 0
  else
    warn "Failed to create Bash configuration"
    return 1
  fi
}

# Configure Termux properties with comprehensive settings and error handling
configure_termux_properties(){
  local termux_dir="${TERMUX_HOME}/.termux"
  local properties_file="$termux_dir/termux.properties"
  local current_user="${TERMUX_USERNAME:-termux}"
  local current_date
  current_date=$(date 2>/dev/null || echo "unknown")
  
  # Create .termux directory
  if ! mkdir -p "$termux_dir" 2>/dev/null; then
    warn "Failed to create .termux directory"
    return 1
  fi
  
  info "Configuring enhanced Termux properties..."
  
  # Initialize user variables if not set
  initialize_user_vars
  
  # Backup existing properties
  if [ -f "$properties_file" ]; then
    backup_file "$properties_file" >/dev/null 2>&1 || true
  fi
  
  # Create comprehensive termux.properties
  if cat > "$properties_file" << TERMUX_PROPERTIES_EOF
# Enhanced Termux Properties Configuration
# Generated by CAD-Droid Mobile Development Setup
# User: $current_user
# Git User: ${GIT_USERNAME:-Not Set}${GIT_EMAIL:+ <$GIT_EMAIL>}
# Configuration Date: $current_date
# Setup Version: ${SCRIPT_VERSION:-2.0.0}

# Security and permissions
allow-external-apps = true

# Enhanced extra keys optimized for mobile development
extra-keys = [[ \\
  {key: ESC, popup: {macro: "CTRL f d", display: "tmux exit"}}, \\
  {key: "/", popup: "?"}, \\
  {key: "-", popup: "_"}, \\
  {key: HOME, popup: {macro: "CTRL a", display: "line start"}}, \\
  {key: UP, popup: {macro: "CTRL p", display: "prev cmd"}}, \\
  {key: END, popup: {macro: "CTRL e", display: "line end"}}, \\
  {key: PGUP, popup: {macro: "CTRL u", display: "clear line"}} \\
], [ \\
  {key: TAB, popup: {macro: "CTRL i", display: "complete"}}, \\
  {key: CTRL, popup: {macro: "CTRL c", display: "interrupt"}}, \\
  {key: ALT, popup: {macro: "ALT b ALT f", display: "word nav"}}, \\
  {key: LEFT, popup: {macro: "CTRL b", display: "char left"}}, \\
  {key: DOWN, popup: {macro: "CTRL n", display: "next cmd"}}, \\
  {key: RIGHT, popup: {macro: "CTRL f", display: "char right"}}, \\
  {key: PGDN, popup: {macro: "CTRL k", display: "del to end"}} \\
]]

# UI and interaction settings optimized for mobile development
use-black-ui = true
hide-soft-keyboard-on-startup = false
enforce-char-based-input = true
disable-hardware-keyboard-shortcuts = false

# Terminal behavior settings
bell-character = ignore
terminal-transcript-rows = 10000
bracketed-paste-mode = true
handle-resize = true
terminal-cursor-blink-rate = 500
terminal-cursor-style = block

# Font and display settings
terminal-cursor-inactive-style = bar
fullscreen = false
use-fullscreen-workaround = false

# Performance optimizations
terminal-margin-horizontal = 0
terminal-margin-vertical = 0

# Additional developer-focused settings
shortcut-create-session = ctrl + alt + n
shortcut-previous-session = ctrl + alt + left
shortcut-next-session = ctrl + alt + right
shortcut-rename-session = ctrl + alt + r
TERMUX_PROPERTIES_EOF
then
    info "Termux properties configured for user: $current_user"
    info "Extra keys include developer shortcuts and navigation macros"
    
    # Reload settings if possible
    if command -v termux-reload-settings >/dev/null 2>&1; then
      if termux-reload-settings 2>/dev/null; then
        ok "Termux settings reloaded successfully"
      else
        info "Settings will take effect on next Termux restart"
      fi
    else
      info "Settings will take effect on next Termux restart"
    fi
    
    return 0
  else
    warn "Failed to create Termux properties file"
    return 1
  fi
}

# Set up Git configuration with comprehensive error handling
configure_git(){
  if ! command -v git >/dev/null 2>&1; then
    warn "Git not installed, skipping configuration"
    return 1
  fi
  
  info "Configuring Git for development..."
  
  local config_changes=0
  
  # Get or prompt for Git configuration in interactive mode
  if [ -z "${GIT_USERNAME:-}" ] && [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    read_nonempty "Git username" "GIT_USERNAME" "" "username"
  fi
  
  if [ -z "${GIT_EMAIL:-}" ] && [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    read_nonempty "Git email" "GIT_EMAIL" "" "email"
  fi
  
  # Set Git configuration with error handling
  if [ -n "${GIT_USERNAME:-}" ]; then
    if git config --global user.name "$GIT_USERNAME" 2>/dev/null; then
      info "Git username set to: $GIT_USERNAME"
      config_changes=$((config_changes + 1))
    else
      warn "Failed to set Git username"
    fi
  fi
  
  if [ -n "${GIT_EMAIL:-}" ]; then
    if git config --global user.email "$GIT_EMAIL" 2>/dev/null; then
      info "Git email set to: $GIT_EMAIL"
      config_changes=$((config_changes + 1))
    else
      warn "Failed to set Git email"
    fi
  fi
  
  # Additional Git configuration for better mobile development experience
  local additional_configs=(
    "init.defaultBranch:main"
    "pull.rebase:false"
    "core.editor:nano"
    "color.ui:auto"
    "push.default:simple"
    "merge.tool:vimdiff"
    "core.autocrlf:false"
  )
  
  for config in "${additional_configs[@]}"; do
    local key="${config%%:*}"
    local value="${config#*:}"
    
    if git config --global "$key" "$value" 2>/dev/null; then
      config_changes=$((config_changes + 1))
    fi
  done
  
  if [ "$config_changes" -gt 0 ]; then
    ok "Git configured with $config_changes settings"
    return 0
  else
    warn "Git configuration completed with limited success"
    return 1
  fi
}

# Initialize system-wide configuration with comprehensive error handling
initialize_system(){
  info "Initializing system configuration..."
  
  local initialization_errors=0
  
  # Initialize user variables first
  if ! initialize_user_vars; then
    warn "User variable initialization had issues"
    initialization_errors=$((initialization_errors + 1))
  fi
  
  # Configure core system components
  if ! configure_bash_environment; then
    warn "Bash environment configuration failed"
    initialization_errors=$((initialization_errors + 1))
  fi
  
  if ! configure_nano_editor; then
    warn "Nano editor configuration failed"
    initialization_errors=$((initialization_errors + 1))
  fi
  
  if ! configure_termux_properties; then
    warn "Termux properties configuration failed"
    initialization_errors=$((initialization_errors + 1))
  fi
  
  if ! configure_git; then
    warn "Git configuration failed"
    initialization_errors=$((initialization_errors + 1))
  fi
  
  # Create additional useful directories
  local dirs_to_create=(
    "${TERMUX_HOME}/.local/bin"
    "${TERMUX_HOME}/.config"
    "${TERMUX_HOME}/projects"
    "${TERMUX_HOME}/scripts"
  )
  
  for dir in "${dirs_to_create[@]}"; do
    if ! mkdir -p "$dir" 2>/dev/null; then
      warn "Failed to create directory: $dir"
      initialization_errors=$((initialization_errors + 1))
    fi
  done
  
  # Set appropriate permissions
  chmod 755 "${TERMUX_HOME}/.local/bin" 2>/dev/null || true
  chmod 755 "${TERMUX_HOME}/projects" 2>/dev/null || true
  chmod 755 "${TERMUX_HOME}/scripts" 2>/dev/null || true
  
  # Report results
  if [ "$initialization_errors" -eq 0 ]; then
    ok "System initialization completed successfully"
    return 0
  else
    warn "System initialization completed with $initialization_errors errors"
    return 1
  fi
}

# System information and diagnostics
get_device_info(){
  local info=""
  
  # Device type detection
  if detect_phone; then
    info="$info\nDevice Type: Phone/Mobile"
  else
    info="$info\nDevice Type: Tablet/Large Screen"
  fi
  
  # Storage information
  local primary_storage
  primary_storage=$(detect_primary_storage)
  info="$info\nPrimary Storage: $primary_storage"
  
  # Termux API availability
  if test_termux_api; then
    info="$info\nTermux API: Available"
  else
    info="$info\nTermux API: Not Available"
  fi
  
  # Architecture and system info
  if command -v uname >/dev/null 2>&1; then
    info="$info\nArchitecture: $(uname -m 2>/dev/null || echo 'unknown')"
    info="$info\nKernel: $(uname -r 2>/dev/null || echo 'unknown')"
  fi
  
  printf "%b\n" "$info"
}

# Initialize system module
initialize_system_module(){
  # Validate critical paths exist
  if [ ! -d "${PREFIX}" ]; then
    warn "Termux PREFIX directory not found: ${PREFIX}"
    return 1
  fi
  
  if [ ! -d "${TERMUX_HOME}" ]; then
    warn "Termux HOME directory not found: ${TERMUX_HOME}"
    return 1
  fi
  
  # Create essential directories
  mkdir -p "${TERMUX_TMPDIR}" "${TERMUX_HOME}/.ssh" "${TERMUX_HOME}/.config" 2>/dev/null || true
  
  # Set secure permissions
  chmod 700 "${TERMUX_HOME}/.ssh" 2>/dev/null || true
  
  # Export all critical variables
  export PREFIX TERMUX_HOME TERMUX_TMPDIR TERMUX_USERNAME DISTRO
  export UBUNTU_USERNAME GIT_USERNAME GIT_EMAIL LINUX_SSH_PORT
  
  return 0
}

# Call initialization when module is sourced
initialize_system_module || warn "System module initialization had issues"
