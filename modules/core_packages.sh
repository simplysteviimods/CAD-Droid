#!/usr/bin/env bash
###############################################################################
# CAD-Droid Core Packages Module
# Package installation, APT operations, and system package management
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_CORE_PACKAGES_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_CORE_PACKAGES_LOADED=1

# === Package Installation Functions ===

# Check if a Debian/APT package is installed
dpkg_is_installed() { 
  dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Check if a package is available in repositories
pkg_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

# Install a package only if it's not already installed
apt_install_if_needed(){
  local pkg="$1"
  
  if dpkg_is_installed "$pkg"; then
    debug "$pkg already installed"
    return 0
  fi
  
  if ! pkg_available "$pkg"; then
    warn "Package not available: $pkg"
    return 1
  fi
  
  info "Installing $pkg..."
  
  # Ensure selected mirror is applied before installing
  ensure_mirror_applied
  
  # Try pkg install first (preferred), then fallback to apt install
  # Exit code 100 means package already installed - treat as success
  if command -v pkg >/dev/null 2>&1; then
    pkg install -y "$pkg" >/dev/null 2>&1
    local pkg_result=$?
    if [ $pkg_result -eq 0 ] || [ $pkg_result -eq 100 ]; then
      ok "$pkg installed successfully via pkg"
      return 0
    else
      warn "pkg install failed for $pkg, trying apt install..."
    fi
  fi
  
  # Fallback to apt install - also handle exit code 100
  apt install -y "$pkg" >/dev/null 2>&1
  local apt_result=$?
  if [ $apt_result -eq 0 ] || [ $apt_result -eq 100 ]; then
    ok "$pkg installed successfully via apt"
    return 0
  else
    warn "Failed to install $pkg"
    return 1
  fi
}

# Fix broken APT packages using appropriate Termux commands
apt_fix_broken() {
  info "Fixing broken packages..."
  
  # Ensure selected mirror is applied before fixing packages
  ensure_mirror_applied
  
  run_with_progress "Fix broken packages" 30 bash -c '
    # Try dpkg first
    dpkg --configure -a >/dev/null 2>&1
    
    # Try pkg commands if available
    if command -v pkg >/dev/null 2>&1; then
      pkg install -f -y >/dev/null 2>&1 || true
    fi
    
    # Fallback to apt commands
    apt install -f -y >/dev/null 2>&1 &&
    apt autoremove -y >/dev/null 2>&1
  '
}

# Ensure essential download tools are available
ensure_download_tool(){
  local tool_ready=0
  
  # Check for wget (preferred for APK downloads)
  if ! command -v wget >/dev/null 2>&1; then
    info "Installing wget..."
    if apt_install_if_needed wget; then
      WGET_READY=1
      tool_ready=1
    fi
  else
    WGET_READY=1
    tool_ready=1
  fi
  
  # Check for curl as backup
  if [ "$tool_ready" -eq 0 ]; then
    if ! command -v curl >/dev/null 2>&1; then
      info "Installing curl..."
      if apt_install_if_needed curl; then
        tool_ready=1
      fi
    else
      tool_ready=1
    fi
  fi
  
  if [ "$tool_ready" -eq 0 ]; then
    err "No download tools available"
    return 1
  fi
  
  return 0
}

# === Mirror Management ===

# Ensure the selected mirror is enforced and indexes are up-to-date before any apt operation
# This function addresses the core issue where apt commands could fallback to 
# default or cached mirrors instead of using the user's selected mirror.
# It provides robust mirror enforcement by:
# - Rewriting sources.list with the selected mirror before every apt operation
# - Cleaning up conflicting sources to prevent mirror mixing
# - Updating package indexes to ensure they're current
# - Providing user feedback about which mirror is being used
ensure_mirror_applied(){
  local sources_file="$PREFIX/etc/apt/sources.list"
  
  # Skip if no mirror is selected
  if [ -z "${SELECTED_MIRROR_URL:-}" ]; then
    debug "No selected mirror to enforce, using current configuration"
    return 0
  fi
  
  # Always rewrite sources to ensure selected mirror is used
  debug "Enforcing selected mirror: ${SELECTED_MIRROR_URL}"
  echo "deb ${SELECTED_MIRROR_URL} stable main" > "$sources_file"
  
  # Clean up any conflicting sources to prevent mirror mixing
  sanitize_sources_main_only
  
  # Update package indexes to ensure they're current
  if command -v pkg >/dev/null 2>&1; then
    run_with_progress "Update indexes (pkg)" 15 bash -c 'pkg update -y >/dev/null 2>&1 || true'
  else
    run_with_progress "Update indexes (apt)" 15 bash -c 'apt update >/dev/null 2>&1 || true'
  fi
  
  # Add user-facing info for transparency when mirror name is available (only once)
  if [ "${SELECTED_MIRROR_NAME:-}" ] && [ "${SELECTED_MIRROR_NAME}" != "(current)" ] && [ "${MIRROR_INFO_SHOWN:-0}" != "1" ]; then
    info "Using mirror: ${SELECTED_MIRROR_NAME} for package operations"
    export MIRROR_INFO_SHOWN=1
  fi
  
  return 0
}

# Clean up apt sources to prevent conflicts
sanitize_sources_main_only(){
  local d="$PREFIX/etc/apt/sources.list.d"
  if [ ! -d "$d" ]; then
    return 0
  fi
  
  # Remove non-essential source files (keep only X11 related)
  find "$d" -name "*.list" -type f 2>/dev/null | while read -r f; do
    if ! echo "$f" | grep -qi x11; then
      rm -f "$f" 2>/dev/null || true
    fi
  done
}

# Verify and set package mirror configuration
verify_mirror(){
  local sources_file="$PREFIX/etc/apt/sources.list"
  local url
  
  if [ -f "$sources_file" ]; then
    url=$(awk '/^deb /{print $2; exit}' "$sources_file" 2>/dev/null || true)
  fi
  
  if [ -n "$url" ]; then 
    SELECTED_MIRROR_URL="$url"
    if [ -z "$SELECTED_MIRROR_NAME" ]; then
      SELECTED_MIRROR_NAME="(current)"
    fi
  else
    # Set default mirror if none configured
    echo "deb https://packages.termux.dev/apt/termux-main stable main" > "$sources_file"
    SELECTED_MIRROR_NAME="Default"
    SELECTED_MIRROR_URL="https://packages.termux.dev/apt/termux-main"
  fi
}

# === Core Package Installation ===

# Install core productivity packages
install_core_packages(){
  pecho "$PASTEL_PURPLE" "Installing core productivity packages..."
  
  local essential_packages=(
    "jq"              # JSON processing
    "git"             # Version control
    "curl"            # HTTP client
    "wget"            # Download tool
    "nano"            # Text editor
    "vim"             # Advanced editor
    "tmux"            # Terminal multiplexer
    "python"          # Python language
    "openssh"         # SSH client/server
    "git"             # Version control system
    "gh"              # GitHub CLI
    "pulseaudio"      # Audio system
    "dbus"            # System bus
    "fontconfig"      # Font management
    "ttf-dejavu"      # Fonts
  )
  
  local success_count=0
  local total=${#essential_packages[@]}
  
  for pkg in "${essential_packages[@]}"; do
    if run_with_progress "Install $pkg" 15 apt_install_if_needed "$pkg"; then
      success_count=$((success_count + 1))
    fi
  done
  
  info "Core packages installed: $success_count/$total"
  
  # Update download count
  DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + success_count))
  
  return 0
}

# Install network tools
install_network_tools(){
  pecho "$PASTEL_PURPLE" "Installing network utilities..."
  
  local network_packages=(
    "iproute2"        # Network configuration
    "net-tools"       # Network utilities
    "dnsutils"        # DNS tools
    "netcat-openbsd"  # Network Swiss Army knife
  )
  
  for pkg in "${network_packages[@]}"; do
    run_with_progress "Install $pkg" 10 apt_install_if_needed "$pkg" || true
  done
  
  return 0
}

# === Specialized Package Operations ===

# Install proot-distro and container support
install_container_support(){
  pecho "$PASTEL_PURPLE" "Installing container support..."
  
  if ! dpkg_is_installed "proot-distro"; then
    if run_with_progress "Install proot-distro" 20 apt_install_if_needed "proot-distro"; then
      ok "Container support installed"
    else
      warn "Failed to install container support"
      return 1
    fi
  else
    debug "Container support already available"
  fi
  
  return 0
}

# Install X11 packages for GUI support
install_x11_packages(){
  pecho "$PASTEL_PURPLE" "Installing X11 GUI support..."
  
  local x11_packages=(
    "x11-repo"        # X11 repository
    "xfce4"           # Desktop environment
    "xfce4-terminal"  # Terminal emulator
    "firefox"         # Web browser
    "tigervnc"        # VNC server
  )
  
  for pkg in "${x11_packages[@]}"; do
    run_with_progress "Install $pkg" 25 apt_install_if_needed "$pkg" || true
  done
  
  return 0
}

# === System Updates ===

# Update package lists using appropriate Termux commands
update_package_lists(){
  info "Updating package lists..."
  
  # Ensure selected mirror is applied before updating
  ensure_mirror_applied
  
  # Try pkg update first (preferred Termux command), then fallback to apt update
  if command -v pkg >/dev/null 2>&1; then
    if run_with_progress "Update package lists (pkg)" 30 bash -c '
      pkg update -y >/dev/null 2>&1
    '; then
      ok "Package lists updated via pkg"
      return 0
    else
      warn "pkg update failed, trying apt update..."
    fi
  fi
  
  # Fallback to apt update
  if run_with_progress "Update package lists (apt)" 30 bash -c '
    apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=10 >/dev/null 2>&1
  '; then
    ok "Package lists updated via apt"
    return 0
  else
    warn "Package list update failed"
    return 1
  fi
}

# Upgrade all packages using appropriate Termux commands
upgrade_packages(){
  info "Upgrading packages..."
  
  # Ensure selected mirror is applied before upgrading
  ensure_mirror_applied
  
  # Try pkg upgrade first (preferred Termux command), then fallback to apt upgrade
  if command -v pkg >/dev/null 2>&1; then
    if run_with_progress "Upgrade packages (pkg)" 60 bash -c '
      pkg upgrade -y >/dev/null 2>&1
    '; then
      ok "Packages upgraded successfully via pkg"
      return 0
    else
      warn "pkg upgrade failed, trying apt upgrade..."
    fi
  fi
  
  # Fallback to apt upgrade
  if run_with_progress "Upgrade packages (apt)" 60 bash -c '
    apt upgrade -y >/dev/null 2>&1
  '; then
    ok "Packages upgraded successfully via apt"
    return 0
  else
    warn "Package upgrade had issues"
    return 1
  fi
}

# === Step Functions ===

# Step: Mirror selection for faster downloads
step_mirror(){
  pecho "$PASTEL_PURPLE" "Choose Termux mirror:"
  
  # Available mirrors with geographic distribution
  local urls=(
    "https://packages.termux.dev/apt/termux-main"
    "https://packages-cf.termux.dev/apt/termux-main"
    "https://fau.mirror.termux.dev/apt/termux-main"
    "https://mirror.bfsu.edu.cn/termux/apt/termux-main"
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
    "https://grimler.se/termux/termux-main"
    "https://termux.mentality.rip/termux/apt/termux-main"
  )
  
  local names=(
    "Default"
    "Cloudflare (US Anycast)"
    "FAU (DE)"
    "BFSU (CN)"
    "Tsinghua (CN)"
    "Grimler (SE)"
    "Mentality (UK)"
  )
  
  # Display mirror options with colors
  local i
  for i in "${!names[@]}"; do 
    local seq
    seq=$(color_for_index "$i")
    printf "%b[%d] %s%b\n" "$seq" "$i" "${names[$i]}" '\033[0m'
  done
  
  local idx=""
  if [ "$NON_INTERACTIVE" = "1" ]; then
    idx=0
  else
    local max_index
    max_index=$(sub_int "${#names[@]}" 1)
    printf "%bMirror (0-%s default 0): %b" "$PASTEL_PINK" "$max_index" '\033[0m'
    read -r idx
  fi
  
  # Validate selection
  case "$idx" in
    *[!0-9]*) idx=0 ;;
    *) [ "$idx" -ge "${#urls[@]}" ] && idx=0 ;;
  esac
  
  SELECTED_MIRROR_NAME="${names[$idx]}"
  SELECTED_MIRROR_URL="${urls[$idx]}"
  
  # Write mirror configuration
  run_with_progress "Write mirror config" 5 bash -c "echo 'deb ${SELECTED_MIRROR_URL} stable main' > '$PREFIX/etc/apt/sources.list'"
  
  # Reload settings and clean up sources
  soft_step "Reload termux settings (post-mirror)" 5 bash -c 'command -v termux-reload-settings >/dev/null 2>&1 && termux-reload-settings || exit 0'
  sanitize_sources_main_only
  verify_mirror
  
  # Test the mirror and automatically fallback if needed
  if run_with_progress "Test mirror connection" 18 bash -c 'apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=10 >/dev/null 2>&1'; then
    ok "Mirror connection successful: ${SELECTED_MIRROR_NAME}"
  else
    warn "Selected mirror failed, trying alternatives..."
    
    # Iterate through official mirrors first, then others
    local fallback_attempted=false
    local max_attempts=3
    local attempt=0
    
    for i in "${!urls[@]}"; do
      # Skip the already tried mirror
      if [ "$i" -eq "$idx" ]; then
        continue
      fi
      
      # Limit attempts to prevent hanging
      if [ "$attempt" -ge "$max_attempts" ]; then
        break
      fi
      
      local test_url="${urls[$i]}"
      local test_name="${names[$i]}"
      
      info "Trying ${test_name}..."
      
      # Update selected mirror variables for fallback testing
      SELECTED_MIRROR_NAME="$test_name"
      SELECTED_MIRROR_URL="$test_url"
      
      # Apply the fallback mirror and test
      ensure_mirror_applied
      
      if run_with_progress "Test ${test_name}" 18 bash -c 'apt-get update -o Acquire::Retries=2 -o Acquire::http::Timeout=8 >/dev/null 2>&1'; then
        ok "Mirror connection successful: ${test_name}"
        fallback_attempted=true
        break
      else
        warn "${test_name} also failed"
      fi
      
      attempt=$((attempt + 1))
    done
    
    # If all mirrors failed, inform user but continue
    if [ "$fallback_attempted" = false ]; then
      warn "All tested mirrors failed, continuing with best effort"
      # Force update attempt with selected mirror enforced
      ensure_mirror_applied
      run_with_progress "Force apt index update" 25 bash -c 'apt-get clean && apt-get update --fix-missing >/dev/null 2>&1 || true'
    fi
  fi
  
  mark_step_status "success"
}

# Step: System bootstrap and essential tools
step_bootstrap(){
  update_package_lists || true
  ensure_download_tool
  mark_step_status "success"
}

# Step: Add X11 repository
step_x11repo(){
  # Ensure selected mirror is applied before installing X11 repo
  ensure_mirror_applied
  
  # Try pkg first, then apt as fallback
  if command -v pkg >/dev/null 2>&1; then
    if run_with_progress "Add X11 repository (pkg)" 15 bash -c 'pkg install -y x11-repo >/dev/null 2>&1'; then
      mark_step_status "success"
      return 0
    fi
  fi
  
  # Fallback to apt
  run_with_progress "Add X11 repository (apt)" 15 bash -c 'apt install -y x11-repo >/dev/null 2>&1 || true'
  mark_step_status "success"
}

# Step: Configure APT for non-interactive use
step_aptni(){
  run_with_progress "Configure APT" 10 bash -c '
    echo "APT::Get::Assume-Yes \"true\";" > $PREFIX/etc/apt/apt.conf.d/90-noninteractive
    echo "APT::Get::Fix-Broken \"true\";" >> $PREFIX/etc/apt/apt.conf.d/90-noninteractive
  '
  mark_step_status "success"
}

# Step: System update
step_systemup(){
  if update_package_lists; then
    upgrade_packages || true
  fi
  mark_step_status "success"
}

# Step: Install network tools
step_nettools(){
  install_network_tools
  mark_step_status "success"
}

# Step: Install core packages
step_coreinst(){
  install_core_packages
  apt_fix_broken || true
  mark_step_status "success"
}

# Step: Install XFCE Desktop Environment for Termux
step_xfce_termux(){
  info "Installing XFCE desktop environment for Termux..."
  
  # Ensure X11 repository is available first
  ensure_mirror_applied
  
  # Install X11 repo if not already installed
  if ! dpkg_is_installed "x11-repo"; then
    if command -v pkg >/dev/null 2>&1; then
      run_with_progress "Add X11 repository (pkg)" 15 bash -c 'pkg install -y x11-repo >/dev/null 2>&1 || [ $? -eq 100 ]'
    else
      run_with_progress "Add X11 repository (apt)" 15 bash -c 'apt install -y x11-repo >/dev/null 2>&1 || [ $? -eq 100 ]'
    fi
    
    # Update indexes after adding X11 repo
    ensure_mirror_applied
  fi
  
  # XFCE desktop components for Termux
  local xfce_packages=(
    "xfce4"
    "xfce4-terminal" 
    "xfce4-panel"
    "xfce4-session"
    "xfce4-settings"
    "xfce4-appfinder"
    "thunar"
    "xfce4-power-manager"
    "xfce4-screenshooter"
    "ristretto"
    "mousepad"
  )
  
  info "Installing XFCE components..."
  local success_count=0
  local total=${#xfce_packages[@]}
  
  for pkg in "${xfce_packages[@]}"; do
    if run_with_progress "Install $pkg" 20 apt_install_if_needed "$pkg"; then
      success_count=$((success_count + 1))
    fi
  done
  
  info "XFCE packages installed: $success_count/$total"
  
  # Install additional desktop utilities
  local desktop_utils=(
    "pulseaudio"
    "dbus"
    "fontconfig"
    "ttf-dejavu"
    "firefox"
  )
  
  info "Installing desktop utilities..."
  for pkg in "${desktop_utils[@]}"; do
    run_with_progress "Install $pkg" 15 apt_install_if_needed "$pkg" || true
  done
  
  # Configure XFCE for Termux
  info "Configuring XFCE desktop..."
  run_with_progress "Configure XFCE" 10 bash -c '
    # Create desktop directories
    mkdir -p "$HOME/Desktop" "$HOME/.config/xfce4" >/dev/null 2>&1 || true
    
    # Set up basic XFCE configuration
    if [ ! -f "$HOME/.config/xfce4/xfconf" ]; then
      mkdir -p "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml" >/dev/null 2>&1 || true
    fi
  ' || true
  
  ok "XFCE desktop environment installed for Termux"
  info "XFCE will be available in both Termux and Ubuntu containers"
  
  mark_step_status "success"
}