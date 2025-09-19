#!/usr/bin/env bash
# steps.sh - Installation step functions with proper variable initialization
# This module handles the actual installation steps and progress tracking

# Prevent multiple sourcing
if [[ "${CAD_STEPS_LOADED:-}" == "1" ]]; then
    return 0
fi
export CAD_STEPS_LOADED=1

# Source required modules
# Use SCRIPT_DIR from main script if available, otherwise determine it
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# If we're in the lib directory, look for modules there
if [[ "$(basename "$SCRIPT_DIR")" == "lib" ]]; then
  source "$SCRIPT_DIR/colors.sh"
  source "$SCRIPT_DIR/utils.sh"  
  source "$SCRIPT_DIR/display.sh"
  source "$SCRIPT_DIR/system.sh"
else
  source "$SCRIPT_DIR/lib/colors.sh"
  source "$SCRIPT_DIR/lib/utils.sh"  
  source "$SCRIPT_DIR/lib/display.sh"
  source "$SCRIPT_DIR/lib/system.sh"
fi

# Step management variables - ensure all are properly initialized
declare -a INSTALLATION_STEPS
INSTALLATION_STEPS=()

declare -A STEP_STATUS
# Initialize with empty associative array

export CURRENT_STEP_INDEX="${CURRENT_STEP_INDEX:-0}"
export TOTAL_STEPS="${TOTAL_STEPS:-0}"
export STEP_TIMEOUT="${STEP_TIMEOUT:-300}"  # Maximum time per step in seconds

# Installation configuration - ensure all have defaults
export DISTRO="${DISTRO:-ubuntu}"
export UBUNTU_USERNAME="${UBUNTU_USERNAME:-developer}"
export ENABLE_SUNSHINE="${ENABLE_SUNSHINE:-1}"
export ENABLE_ADB="${ENABLE_ADB:-1}"

# Package categories - ensure arrays are declared and populated
declare -a XFCE_PACKAGES
XFCE_PACKAGES=(
  "xfce4"
  "xfce4-terminal"
  "xfce4-panel"
  "xfce4-session"
  "xfce4-settings"
  "thunar"
  "xfce4-appfinder"
)

declare -a DEV_TOOL_PACKAGES  
DEV_TOOL_PACKAGES=(
  "build-essential"
  "clang"
  "cmake"
  "make"
  "pkg-config"
  "python"
  "nodejs" 
  "golang"
  "rust"
  "gdb"
)

# Register an installation step
register_step(){
  local name="${1:-}" function_name="${2:-}" estimated_time="${3:-30}"
  
  if [ -z "$name" ] || [ -z "$function_name" ]; then
    warn "register_step: name and function name required"
    return 1
  fi
  
  # Validate function name format
  if ! echo "$function_name" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; then
    warn "register_step: invalid function name format: $function_name"
    return 1
  fi
  
  # Validate estimated time
  case "$estimated_time" in
    *[!0-9]*) estimated_time=30 ;;
    *) 
      if [ "$estimated_time" -lt 1 ]; then estimated_time=30; fi
      if [ "$estimated_time" -gt 3600 ]; then estimated_time=3600; fi
      ;;
  esac
  
  # Add to installation steps
  INSTALLATION_STEPS+=("$name:$function_name:$estimated_time")
  STEP_STATUS["$name"]="pending"
  TOTAL_STEPS=$((TOTAL_STEPS + 1))
  
  if [ "${DEBUG:-0}" = "1" ]; then
    info "Registered step: $name -> $function_name (${estimated_time}s estimated)"
  fi
}

# Mark step status with validation
mark_step_status(){
  local status="${1:-unknown}"
  local step_name=""
  
  # Validate status
  case "$status" in
    pending|running|success|failed|skipped) ;;
    *) status="unknown" ;;
  esac
  
  # Get current step name safely
  if [ "${CURRENT_STEP_INDEX:-0}" -lt "${#INSTALLATION_STEPS[@]}" ] && [ "${CURRENT_STEP_INDEX:-0}" -ge 0 ]; then
    local step_info="${INSTALLATION_STEPS[$CURRENT_STEP_INDEX]}"
    step_name="${step_info%%:*}"
  fi
  
  if [ -n "$step_name" ]; then
    STEP_STATUS["$step_name"]="$status"
    
    case "$status" in
      success) ok "Step completed: $step_name" ;;
      failed) err "Step failed: $step_name" ;;
      skipped) info "Step skipped: $step_name" ;;
      running) info "Step running: $step_name" ;;
    esac
  fi
}

# Execute a step with comprehensive error handling
execute_step(){
  local step_info="${1:-}"
  local name="" function_name="" estimated_time=""
  
  if [ -z "$step_info" ]; then
    warn "execute_step: step info required"
    return 1
  fi
  
  # Parse step information safely
  IFS=':' read -r name function_name estimated_time <<< "$step_info"
  
  if [ -z "$name" ] || [ -z "$function_name" ]; then
    warn "execute_step: invalid step format: $step_info"
    return 1
  fi
  
  info "Starting step: $name"
  draw_phase_header "Step $((CURRENT_STEP_INDEX + 1))/$TOTAL_STEPS: $name"
  
  # Mark step as running
  mark_step_status "running"
  
  # Check if function exists
  if ! declare -f "$function_name" >/dev/null 2>&1; then
    warn "Function $function_name not found, skipping step: $name"
    mark_step_status "skipped"
    return 0
  fi
  
  # Execute the step function with timeout if available
  local start_time end_time duration=0
  start_time=$(date +%s 2>/dev/null || echo 0)
  
  local step_result=0
  if command -v timeout >/dev/null 2>&1 && [ "${estimated_time:-30}" -gt 0 ]; then
    # Use timeout command if available
    local timeout_duration=$((${estimated_time:-30} * 2))  # Allow double the estimated time
    if timeout "$timeout_duration" "$function_name"; then
      step_result=0
    else
      step_result=$?
      if [ "$step_result" = 124 ]; then
        warn "Step '$name' timed out after ${timeout_duration}s"
      fi
    fi
  else
    # Execute without timeout
    if "$function_name"; then
      step_result=0
    else
      step_result=$?
    fi
  fi
  
  end_time=$(date +%s 2>/dev/null || echo 0)
  if [ "$end_time" -gt "$start_time" ]; then
    duration=$((end_time - start_time))
  fi
  
  # Mark step result
  if [ "$step_result" -eq 0 ]; then
    mark_step_status "success"
    ok "Step '$name' completed in ${duration}s"
  else
    mark_step_status "failed"
    warn "Step '$name' failed (exit code: $step_result) after ${duration}s"
  fi
  
  return "$step_result"
}

# Package installation with comprehensive retry logic
apt_install_if_needed(){
  local package="${1:-}"
  local max_retries="${2:-3}"
  local update_first="${3:-0}"
  
  if [ -z "$package" ]; then
    warn "apt_install_if_needed: package name required"
    return 1
  fi
  
  # Validate max_retries
  case "$max_retries" in
    *[!0-9]*) max_retries=3 ;;
    *) 
      if [ "$max_retries" -lt 1 ]; then max_retries=1; fi
      if [ "$max_retries" -gt 10 ]; then max_retries=10; fi
      ;;
  esac
  
  # Check if already installed
  if dpkg_is_installed "$package"; then
    if [ "${DEBUG:-0}" = "1" ]; then
      info "$package is already installed"
    fi
    return 0
  fi
  
  info "Installing $package..."
  
  # Update package lists if requested or if they're very old
  if [ "$update_first" = "1" ] || [ ! -f "${PREFIX}/var/lib/apt/lists/packages.termux.org_packages_dists_stable_main_binary-$(dpkg --print-architecture)_Packages" ]; then
    info "Updating package lists..."
    local update_result=0
    if command -v pkg >/dev/null 2>&1; then
      pkg update -y >/dev/null 2>&1 || update_result=$?
    fi
    if [ "$update_result" -ne 0 ] && command -v apt >/dev/null 2>&1; then
      apt update -y >/dev/null 2>&1 || update_result=$?
    fi
    
    if [ "$update_result" -ne 0 ]; then
      warn "Package list update failed, continuing anyway..."
    fi
  fi
  
  # Install package with retries
  local attempts=0
  while [ "$attempts" -lt "$max_retries" ]; do
    local install_result=0
    
    # Try pkg first, then apt
    if command -v pkg >/dev/null 2>&1; then
      pkg install -y "$package" >/dev/null 2>&1 || install_result=$?
    fi
    
    if [ "$install_result" -ne 0 ] && command -v apt >/dev/null 2>&1; then
      apt install -y "$package" >/dev/null 2>&1 || install_result=$?
    fi
    
    if [ "$install_result" -eq 0 ]; then
      ok "$package installed successfully"
      return 0
    fi
    
    attempts=$((attempts + 1))
    if [ "$attempts" -lt "$max_retries" ]; then
      warn "Installation attempt $attempts failed for $package, retrying in 3s..."
      sleep 3
    fi
  done
  
  warn "Failed to install $package after $max_retries attempts"
  return 1
}

# Step 1: Update package repositories
step_update_repos(){
  info "Updating package repositories..."
  
  local update_success=0
  
  # Update Termux repositories
  if command -v pkg >/dev/null 2>&1; then
    info "Updating with pkg..."
    if pkg update -y >/dev/null 2>&1; then
      update_success=1
    fi
  fi
  
  # Fallback to apt if pkg failed
  if [ "$update_success" -eq 0 ] && command -v apt >/dev/null 2>&1; then
    info "Fallback to apt update..."
    if apt update -y >/dev/null 2>&1; then
      update_success=1
    fi
  fi
  
  if [ "$update_success" -eq 0 ]; then
    warn "Package list update failed, but continuing"
  fi
  
  # Add additional repositories
  local repo_added=0
  
  if ! dpkg_is_installed x11-repo; then
    info "Adding X11 repository..."
    if apt_install_if_needed x11-repo 2 0; then
      repo_added=1
    fi
  fi
  
  if ! dpkg_is_installed unstable-repo; then
    info "Adding unstable repository..."  
    if apt_install_if_needed unstable-repo 2 0; then
      repo_added=1
    fi
  fi
  
  # Update again if we added repositories
  if [ "$repo_added" -eq 1 ]; then
    info "Updating package lists after adding repositories..."
    pkg update -y >/dev/null 2>&1 || apt update -y >/dev/null 2>&1 || true
  fi
  
  ok "Repository update completed"
  return 0
}

# Step 2: Install core packages
step_install_core(){
  info "Installing core packages..."
  
  # Ensure CORE_PACKAGES array is available
  if [ -z "${CORE_PACKAGES[0]:-}" ]; then
    warn "CORE_PACKAGES array not initialized, using defaults"
    local core_packages=("curl" "wget" "git" "nano" "openssh" "termux-exec" "proot-distro")
  else
    local core_packages=("${CORE_PACKAGES[@]}")
  fi
  
  # Check if all core packages are already installed
  local missing_count=0
  local pkg
  for pkg in "${core_packages[@]}"; do
    if [ -n "$pkg" ] && ! dpkg_is_installed "$pkg"; then
      missing_count=$((missing_count + 1))
    fi
  done
  
  if [ "$missing_count" -eq 0 ]; then
    info "All core packages already installed - skipping installation"
    return 0
  fi
  
  info "Installing $missing_count core packages..."
  
  # Install each core package
  local failed=0 installed=0
  for pkg in "${core_packages[@]}"; do
    if [ -n "$pkg" ]; then
      if apt_install_if_needed "$pkg" 3 0; then
        installed=$((installed + 1))
      else
        failed=$((failed + 1))
        warn "Failed to install core package: $pkg"
      fi
    fi
  done
  
  info "Core packages: $installed installed, $failed failed"
  
  if [ "$failed" -eq 0 ]; then
    ok "All core packages installed successfully"
  elif [ "$installed" -gt 0 ]; then
    ok "Core packages installation completed with some failures"
  else
    warn "Core package installation had significant issues"
    return 1
  fi
  
  return 0
}

# Step 3: Install XFCE desktop environment
step_install_xfce(){
  info "Installing XFCE desktop environment..."
  
  # Check if XFCE is already installed
  if dpkg_is_installed xfce4; then
    info "XFCE desktop environment already installed"
    return 0
  fi
  
  # Ensure X11 repository is available
  if ! dpkg_is_installed x11-repo; then
    info "Installing X11 repository first..."
    apt_install_if_needed x11-repo 3 1
  fi
  
  # Install XFCE components
  local failed=0 installed=0
  for package in "${XFCE_PACKAGES[@]}"; do
    if [ -n "$package" ]; then
      if apt_install_if_needed "$package" 3 0; then
        installed=$((installed + 1))
      else
        failed=$((failed + 1))
        warn "Failed to install XFCE component: $package"
      fi
    fi
  done
  
  info "XFCE packages: $installed installed, $failed failed"
  
  if [ "$installed" -gt 0 ]; then
    ok "XFCE desktop environment installation completed"
    return 0
  else
    warn "XFCE installation failed completely"
    return 1
  fi
}

# Step 4: Install development tools
step_install_dev_tools(){
  info "Installing development tools..."
  
  # Use DEV_TOOL_PACKAGES if available, otherwise fallback
  local dev_packages
  if [ -n "${DEV_TOOL_PACKAGES[0]:-}" ]; then
    dev_packages=("${DEV_TOOL_PACKAGES[@]}")
  else
    dev_packages=("build-essential" "clang" "cmake" "make" "pkg-config" "python" "nodejs" "golang")
  fi
  
  local installed=0 failed=0
  for package in "${dev_packages[@]}"; do
    if [ -n "$package" ]; then
      if apt_install_if_needed "$package" 2 0; then
        installed=$((installed + 1))
      else
        failed=$((failed + 1))
      fi
    fi
  done
  
  info "Development tools: $installed installed, $failed failed"
  
  if [ "$installed" -gt 0 ]; then
    ok "Development tools installation completed"
    return 0
  else
    warn "No development tools were installed"
    return 1
  fi
}

# Step 5: Configure Linux container
step_configure_container(){
  if ! command -v proot-distro >/dev/null 2>&1; then
    warn "proot-distro not available, skipping container setup"
    return 0
  fi
  
  info "Setting up Linux container..."
  
  local distro_name="${DISTRO:-ubuntu}"
  local username="${UBUNTU_USERNAME:-developer}"
  
  # Install container if not already installed
  if ! is_distro_installed "$distro_name"; then
    info "Installing $distro_name container (this may take several minutes)..."
    if proot-distro install "$distro_name" >/dev/null 2>&1; then
      ok "$distro_name container installed successfully"
    else
      warn "Failed to install $distro_name container"
      return 1
    fi
  else
    info "$distro_name container already installed"
  fi
  
  # Configure container with comprehensive development environment
  info "Configuring container with development environment..."
  
  # Create container setup script with error handling
  local container_setup_script="#!/bin/bash
set -e

# Update system
export DEBIAN_FRONTEND=noninteractive
apt update -qq 
apt upgrade -y -qq

# Essential development tools
apt install -y -qq \\
  sudo curl wget git nano build-essential gcc g++ make cmake \\
  python3 python3-pip nodejs npm openjdk-11-jdk maven \\
  openssh-server xrdp || echo 'Some packages failed to install'

# Create user account
useradd -m -s /bin/bash '$username' 2>/dev/null || true
usermod -aG sudo '$username' 2>/dev/null || true
echo '$username ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Configure services
systemctl enable ssh 2>/dev/null || true
systemctl enable xrdp 2>/dev/null || true

echo 'Container setup completed successfully'
"
  
  # Execute container setup
  if printf "%s" "$container_setup_script" | proot-distro login "$distro_name" -- bash >/dev/null 2>&1; then
    ok "Container configured successfully"
    return 0
  else
    warn "Container configuration had issues but continuing"
    return 0
  fi
}

# Step 6: Configure Git and GitHub integration
step_configure_git(){
  info "Configuring Git and GitHub integration..."
  
  # Configure Git using system module
  if command -v configure_git >/dev/null 2>&1; then
    configure_git
  else
    warn "Git configuration function not available"
  fi
  
  # Generate SSH keys if needed
  local ssh_key="${TERMUX_HOME:-$HOME}/.ssh/id_ed25519"
  if [ ! -f "$ssh_key" ]; then
    info "Generating SSH key for Git..."
    local hostname
    hostname=$(hostname 2>/dev/null || echo "mobile")
    local email_part
    email_part="${GIT_EMAIL:-${TERMUX_USERNAME:-termux}@$hostname}"
    
    if command -v ssh-keygen >/dev/null 2>&1; then
      ssh-keygen -t ed25519 -f "$ssh_key" -N "" -C "$email_part" >/dev/null 2>&1 && {
        chmod 600 "$ssh_key"
        chmod 644 "$ssh_key.pub"
        ok "SSH key generated: $ssh_key"
      } || warn "Failed to generate SSH key"
    else
      warn "ssh-keygen not available, skipping SSH key generation"
    fi
  else
    info "SSH key already exists"
  fi
  
  # GitHub CLI setup if available
  if command -v gh >/dev/null 2>&1; then
    info "GitHub CLI is available"
    if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
      info "You can run 'gh auth login' later to authenticate with GitHub"
    fi
  fi
  
  return 0
}

# Step 7: ADB wireless setup
step_configure_adb(){
  if [ "${ENABLE_ADB:-1}" != "1" ]; then
    info "ADB setup disabled, skipping"
    return 0
  fi
  
  info "Setting up ADB wireless debugging..."
  
  # Install ADB if not available
  if ! command -v adb >/dev/null 2>&1; then
    apt_install_if_needed android-tools 3 0
  fi
  
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    info "To enable ADB wireless debugging:"
    pecho "${PASTEL_GREEN:-\033[92m}" "  1. Go to Settings > About phone"
    pecho "${PASTEL_GREEN:-\033[92m}" "  2. Tap 'Build number' 7 times to enable Developer options"
    pecho "${PASTEL_GREEN:-\033[92m}" "  3. Go to Settings > System > Developer options"
    pecho "${PASTEL_GREEN:-\033[92m}" "  4. Enable 'Wireless debugging'"
    pecho "${PASTEL_GREEN:-\033[92m}" "  5. Tap 'Pair device with pairing code'"
    
    wait_for_confirmation "Press Enter when ready to continue with ADB setup"
    
    # Try to detect ADB debugging
    if command -v adb >/dev/null 2>&1; then
      info "Attempting to detect wireless debugging..."
      timeout 5 adb devices 2>/dev/null | grep -q "device" && ok "ADB connection detected" || info "No ADB devices found (normal for first setup)"
    fi
  else
    info "ADB tools installed (manual wireless setup required)"
  fi
  
  return 0
}

# Step 8: System configuration
step_system_config(){
  info "Applying system configuration..."
  
  # Initialize all system configurations
  if command -v initialize_system >/dev/null 2>&1; then
    initialize_system
  else
    warn "System initialization function not available"
    return 1
  fi
  
  return 0
}

# Register all installation steps
register_installation_steps(){
  info "Registering installation steps..."
  
  # Clear any existing steps
  INSTALLATION_STEPS=()
  STEP_STATUS=()
  TOTAL_STEPS=0
  CURRENT_STEP_INDEX=0
  
  register_step "Update Repositories" "step_update_repos" 30
  register_step "Install Core Packages" "step_install_core" 120 
  register_step "Install XFCE Desktop" "step_install_xfce" 180
  register_step "Install Development Tools" "step_install_dev_tools" 90
  register_step "Configure Container" "step_configure_container" 300
  register_step "Configure Git/GitHub" "step_configure_git" 60
  register_step "Configure ADB" "step_configure_adb" 60
  register_step "System Configuration" "step_system_config" 30
  
  info "Registered $TOTAL_STEPS installation steps"
  return 0
}

# Execute all installation steps
execute_installation_steps(){
  info "Starting installation process with $TOTAL_STEPS steps..."
  
  if [ "${#INSTALLATION_STEPS[@]}" -eq 0 ]; then
    warn "No installation steps registered"
    return 1
  fi
  
  CURRENT_STEP_INDEX=0
  local failed_steps=0
  
  for step_info in "${INSTALLATION_STEPS[@]}"; do
    if ! execute_step "$step_info"; then
      failed_steps=$((failed_steps + 1))
      warn "Step failed but continuing with installation"
    fi
    CURRENT_STEP_INDEX=$((CURRENT_STEP_INDEX + 1))
  done
  
  if [ "$failed_steps" -eq 0 ]; then
    ok "Installation process completed successfully"
  else
    warn "Installation process completed with $failed_steps failed steps"
  fi
  
  info "Installation process completed"
  return 0
}

# Check prerequisites before starting
check_prerequisites(){
  info "Checking system prerequisites..."
  
  # Check Termux environment
  if ! check_privileges; then
    return 1
  fi
  
  # Check available space
  if command -v df >/dev/null 2>&1; then
    local available_mb
    available_mb=$(df "${PREFIX}" 2>/dev/null | tail -1 | awk '{print int($4/1024)}' || echo 0)
    
    case "$available_mb" in
      *[!0-9]*) available_mb=0 ;;
    esac
    
    if [ "$available_mb" -lt 1000 ]; then
      warn "Low disk space: ${available_mb}MB available. Recommended: 1GB+"
      if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
        if ! ask_yes_no "Continue with low disk space?" "n"; then
          err "Installation cancelled due to insufficient space"
          return 1
        fi
      fi
    else
      info "Available space: ${available_mb}MB"
    fi
  fi
  
  # Check network connectivity
  if ! test_connectivity; then
    warn "Network connectivity test failed"
    if ! wait_for_network 5 3; then
      err "Network connection required for installation"
      return 1
    fi
  fi
  
  ok "Prerequisites check completed"
  return 0
}

# Show installation summary
show_completion_summary(){
  draw_phase_header "Installation Summary"
  
  local completed=0 failed=0 skipped=0 pending=0
  local summary_items=()
  
  # Count results and build summary
  for step_name in "${!STEP_STATUS[@]}"; do
    local status="${STEP_STATUS[$step_name]}"
    summary_items+=("$step_name:$status")
    
    case "$status" in
      success) completed=$((completed + 1)) ;;
      failed) failed=$((failed + 1)) ;;
      skipped) skipped=$((skipped + 1)) ;;
      pending) pending=$((pending + 1)) ;;
    esac
  done
  
  # Display summary table if we have items
  if [ "${#summary_items[@]}" -gt 0 ]; then
    show_summary_table summary_items "Installation Results"
  fi
  
  # Overall statistics
  info "Installation Statistics:"
  pecho "${PASTEL_GREEN:-\033[92m}" "  ✓ Completed: $completed steps"
  if [ "$failed" -gt 0 ]; then
    pecho "${PASTEL_RED:-\033[91m}" "  ✗ Failed: $failed steps"
  fi
  if [ "$skipped" -gt 0 ]; then
    pecho "${PASTEL_YELLOW:-\033[93m}" "  - Skipped: $skipped steps"
  fi
  if [ "$pending" -gt 0 ]; then
    pecho "${PASTEL_PURPLE:-\033[95m}" "  ? Pending: $pending steps"
  fi
  
  # Final message
  if [ "$failed" -eq 0 ] && [ "$pending" -eq 0 ]; then
    ok "🎉 Installation completed successfully!"
    info "Your mobile development environment is ready to use."
  else
    warn "Installation completed with issues"
    info "Check the summary above for details"
  fi
  
  # Usage instructions
  echo
  info "Next steps:"
  pecho "${PASTEL_CYAN:-\033[96m}" "  • Run 'termux-x11' to start the desktop environment"
  pecho "${PASTEL_CYAN:-\033[96m}" "  • Use 'proot-distro login ${DISTRO:-ubuntu}' to access the Linux container"
  if [ "${ENABLE_ADB:-1}" = "1" ]; then
    pecho "${PASTEL_CYAN:-\033[96m}" "  • Complete ADB wireless setup in Android Developer Settings"
  fi
  pecho "${PASTEL_CYAN:-\033[96m}" "  • Run 'gh auth login' to authenticate with GitHub"
  
  echo
  ok "Setup completed! Enjoy your mobile development environment."
  return 0
}
