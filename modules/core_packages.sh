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

# Initialize Termux APT environment to prevent lock errors
initialize_apt_environment(){
  debug "Initializing Termux APT environment"
  
  # Create necessary dpkg directories to prevent lock errors
  local dpkg_dirs=(
    "$PREFIX/var/lib/dpkg"
    "$PREFIX/var/lib/dpkg/info"
    "$PREFIX/var/lib/dpkg/updates" 
    "$PREFIX/var/lib/apt/lists"
    "$PREFIX/var/cache/apt/archives"
    "$PREFIX/var/cache/apt/archives/partial"
    "$PREFIX/etc/apt"
    "$PREFIX/etc/apt/sources.list.d"
  )
  
  for dir in "${dpkg_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
      mkdir -p "$dir" 2>/dev/null || {
        warn "Failed to create directory: $dir"
        continue
      }
      debug "Created directory: $dir"
    fi
  done
  
  # Initialize dpkg status file if it doesn't exist
  local dpkg_status="$PREFIX/var/lib/dpkg/status"
  if [ ! -f "$dpkg_status" ]; then
    touch "$dpkg_status" 2>/dev/null || warn "Failed to create dpkg status file"
    debug "Created dpkg status file: $dpkg_status"
  fi
  
  # Create available file if it doesn't exist
  local dpkg_available="$PREFIX/var/lib/dpkg/available"
  if [ ! -f "$dpkg_available" ]; then
    touch "$dpkg_available" 2>/dev/null || warn "Failed to create dpkg available file"
    debug "Created dpkg available file: $dpkg_available"
  fi
  
  # Remove any stale lock files that might cause issues
  local lock_files=(
    "$PREFIX/var/lib/dpkg/lock"
    "$PREFIX/var/lib/dpkg/lock-frontend"
    "$PREFIX/var/cache/apt/archives/lock"
  )
  
  for lock_file in "${lock_files[@]}"; do
    if [ -f "$lock_file" ]; then
      # Check if the lock is actually in use by checking for running apt/dpkg processes
      if ! pgrep -f "apt|dpkg" >/dev/null 2>&1; then
        rm -f "$lock_file" 2>/dev/null && debug "Removed stale lock file: $lock_file"
      fi
    fi
  done
  
  debug "APT environment initialization completed"
}

# Safely run apt/pkg commands with lock handling and retry logic
# Simple package installation using default Termux methods
simple_pkg_install(){
  local pkg="$1"
  
  # Try pkg first (preferred Termux method)
  if command -v pkg >/dev/null 2>&1; then
    debug "Installing $pkg using pkg"
    if pkg install -y "$pkg" 2>/dev/null; then
      return 0
    fi
  fi
  
  # Fallback to apt
  debug "Installing $pkg using apt"
  if yes | apt install -y "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  
  return 1
}

# Simple package update using default Termux methods
simple_pkg_update(){
  # Try pkg first (preferred Termux method)
  if command -v pkg >/dev/null 2>&1; then
    debug "Updating package lists using pkg"
    if pkg update 2>/dev/null; then
      return 0
    fi
  fi
  
  # Fallback to apt
  debug "Updating package lists using apt"
  if yes | apt update >/dev/null 2>&1; then
    return 0
  fi
  
  return 1
}

# Simple package upgrade using default Termux methods
simple_pkg_upgrade(){
  # Try pkg first (preferred Termux method)
  if command -v pkg >/dev/null 2>&1; then
    debug "Upgrading packages using pkg"
    if yes | pkg upgrade -y 2>/dev/null; then
      return 0
    fi
  fi
  
  # Fallback to apt
  debug "Upgrading packages using apt"
  if yes | DEBIAN_FRONTEND=noninteractive apt upgrade -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      -o Dpkg::Options::="--force-confnew" >/dev/null 2>&1; then
    return 0
  fi
  
  return 1
}

# Simple progress display with just spinner (no timeout or percentages)
simple_run_with_progress(){
  local desc="$1"
  shift
  
  local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  local frame=0
  
  # Start background process
  "$@" &
  local pid=$!
  
  # Show spinner while command runs
  while kill -0 "$pid" 2>/dev/null; do
    local char_index=$((frame % ${#spinner_chars}))
    local spinner_char="${spinner_chars:$char_index:1}"
    
    printf "\r\033[38;2;175;238;238m%s\033[0m %s" "$spinner_char" "$desc"
    
    frame=$((frame + 1))
    sleep 0.1
  done
  
  # Wait for process to complete
  wait "$pid"
  local rc=$?
  
  # Clear line and show result
  printf "\r\033[2K"
  if [ $rc -eq 0 ] || [ $rc -eq 100 ]; then
    printf "\033[38;2;152;251;152mOK\033[0m %s\n" "$desc"
  else
    printf "\033[38;2;255;192;203mFAILED\033[0m %s\n" "$desc"
  fi
  
  return $rc
}

# Check if a Debian/APT package is installed
dpkg_is_installed() { 
  dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Check if a package is available in repositories
pkg_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

# Install a package only if it's not already installed
# Get estimated installation time for a package based on known patterns
get_package_install_time(){
  local pkg="$1"
  
  # Large packages that typically take longer
  case "$pkg" in
    "proot-distro"|"ubuntu"|"debian"|"archlinux") echo "45" ;;
    "xfce4"|"firefox"|"chromium"|"libreoffice") echo "40" ;;
    "gcc"|"g++"|"build-essential"|"python3-dev") echo "35" ;;
    "nodejs"|"python3"|"golang"|"rust") echo "30" ;;
    "git"|"wget"|"curl"|"nano"|"vim") echo "15" ;;
    *) echo "25" ;;  # Default for unknown packages
  esac
}

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
  
  # Use simple installation method
  if simple_pkg_install "$pkg"; then
    ok "$pkg installed successfully"
    return 0
  else
    warn "Failed to install $pkg"
    return 1
  fi
}

# Fix broken APT packages using appropriate Termux commands
apt_fix_broken() {
  info "Fixing broken packages..."
  
  run_with_progress "Fix broken packages" 30 bash -c '
    # Try dpkg first
    dpkg --configure -a >/dev/null 2>&1
    
    # Try pkg commands if available
    if command -v pkg >/dev/null 2>&1; then
      pkg install -f -y >/dev/null 2>&1 || true
    fi
    
    # Fallback to apt commands
    yes | apt install -f -y >/dev/null 2>&1 &&
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
# Note: Mirror selection is now handled by termux-change-repo in step_mirror()
# Custom mirror configuration functions have been removed in favor of the official tool
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
    "gh"              # GitHub CLI
    "pulseaudio"      # Audio system
    "dbus"            # System bus
    "fontconfig"      # Font management
    "ttf-dejavu"      # Fonts
  )
  
  local success_count=0
  local total=${#essential_packages[@]}
  
  for pkg in "${essential_packages[@]}"; do
    if simple_run_with_progress "Install $pkg" apt_install_if_needed "$pkg"; then
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
    simple_run_with_progress "Install $pkg" apt_install_if_needed "$pkg" || true
  done
  
  return 0
}

# === Specialized Package Operations ===

# Install proot-distro and container support
install_container_support(){
  pecho "$PASTEL_PURPLE" "Installing container support..."
  
  if ! dpkg_is_installed "proot-distro"; then
    if simple_run_with_progress "Install proot-distro" apt_install_if_needed "proot-distro"; then
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
    simple_run_with_progress "Install $pkg" apt_install_if_needed "$pkg" || true
  done
  
  return 0
}

# === System Updates ===

# Update package lists using appropriate Termux commands
update_package_lists(){
  if [ "${PACKAGES_UPDATED:-0}" = "1" ]; then
    debug "Package lists already updated this session, skipping"
    return 0  # Already updated this session
  fi
  
  info "Updating package lists..."
  
  # Use simple update method (repositories are already configured by termux-change-repo)
  if simple_pkg_update; then
    ok "Package lists updated successfully"
    export PACKAGES_UPDATED=1
    debug "Package list update: SUCCESS"
    return 0
  else
    warn "Package list update failed"
    debug "Package list update: FAILED"
    return 1
  fi
}

# Upgrade all packages using appropriate Termux commands
upgrade_packages(){
  info "Upgrading packages..."
  
  # Try to update package lists first, but continue with upgrade even if it fails
  update_package_lists || {
    warn "Failed to update package lists before upgrade, but continuing with upgrade attempt"
    debug "Package list update: FAILED (exit code: $?)"
  }
  
  # Proactively install essential libraries before upgrading to prevent CANNOT LINK EXECUTABLE errors
  debug "Installing essential libraries before package upgrade"
  if command -v detect_install_missing_libs >/dev/null 2>&1; then
    detect_install_missing_libs || true
  fi
  
  # Also directly install essential packages to ensure availability
  local essential_libs=("libpcre2-8-0" "pcre2-utils" "openssl" "libssl3" "libcrypto3")
  for lib in "${essential_libs[@]}"; do
    if ! dpkg -l | grep -q "$lib" 2>/dev/null; then
      info "Installing $lib to prevent upgrade errors..."
      simple_run_with_progress "Install $lib" simple_pkg_install "$lib" || true
    fi
  done
  
  # Use simple upgrade method with spinner
  if simple_run_with_progress "Upgrading packages" simple_pkg_upgrade; then
    ok "Packages upgraded successfully"
    return 0
  else
    warn "Package upgrade failed"
    return 1
  fi
}

# === Step Functions ===

# Step: Mirror selection using termux-change-repo
step_mirror(){
  pecho "$PASTEL_PURPLE" "Configuring Termux repository mirror:"
  
  # Use the official termux-change-repo command for mirror selection
  if command -v termux-change-repo >/dev/null 2>&1; then
    info "Using termux-change-repo for optimal mirror selection..."
    
    if [ "$NON_INTERACTIVE" = "1" ]; then
      # In non-interactive mode, let termux-change-repo auto-select
      run_with_progress "Auto-selecting fastest mirror" 15 termux-change-repo
    else
      # Interactive mode - let user choose via termux-change-repo interface
      pecho "$PASTEL_CYAN" "The official Termux mirror selection tool will now start."
      info "• Choose your preferred mirror or let it auto-select"
      info "• This will configure both main and X11 repositories"
      echo ""
      termux-change-repo
    fi
    
    if [ $? -eq 0 ]; then
      ok "Repository mirror configured successfully"
      return 0
    else
      warn "Mirror configuration failed, continuing with defaults"
      return 1
    fi
  else
    warn "termux-change-repo not available, using default repository configuration"
    return 1
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
  # Repository configuration is already handled by termux-change-repo in step_mirror
  
  # Use apt directly as pkg is not reliable for x11-repo
  simple_run_with_progress "Add X11 repository" bash -c 'yes | apt install -y x11-repo >/dev/null 2>&1' || true
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
  debug "Starting system update (step 6)..."
  debug "Packages updated flag: ${PACKAGES_UPDATED:-0}"
  
  # Package repositories are already configured by termux-change-repo in step_mirror
  
  if update_package_lists; then
    debug "Package list update: SUCCESS"
  else
    warn "Package list update failed, but continuing with upgrade"
    debug "Package list update: FAILED (exit code: $?)"
  fi
  
  # Always attempt upgrade regardless of update success/failure
  upgrade_packages || {
    warn "Package upgrade failed but continuing"
    debug "Package upgrade: FAILED (exit code: $?)"
  }
  
  debug "System update step completed"
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
  
  # Repository configuration is already handled by termux-change-repo in step_mirror
  
  # Install X11 repo if not already installed
  if ! dpkg_is_installed "x11-repo"; then
    simple_run_with_progress "Add X11 repository" bash -c 'yes | apt install -y x11-repo >/dev/null 2>&1' || true
    
    # Update indexes after adding X11 repo
    debug "Updating package indexes after X11 repo installation"
    update_package_lists || true
  fi
  
  # Proactively install critical libraries that commonly cause XFCE installation failures
  info "Installing critical runtime libraries..."
  
  # Install libpcre2 and related libraries (fixes "cut" command issues)
  simple_run_with_progress "Install libpcre2 libraries" simple_pkg_install "libpcre2-8-0" || true
  simple_run_with_progress "Install pcre2-utils" simple_pkg_install "pcre2-utils" || true
  simple_run_with_progress "Install libpcre2-8" simple_pkg_install "libpcre2-8" || true
  
  # Install OpenSSL libraries (fixes libcrypto.so.3 issues)
  simple_run_with_progress "Install openssl" simple_pkg_install "openssl" || true
  simple_run_with_progress "Install libssl3" simple_pkg_install "libssl3" || true
  simple_run_with_progress "Install libcrypto3" simple_pkg_install "libcrypto3" || true
  simple_run_with_progress "Install openssl-tool" simple_pkg_install "openssl-tool" || true
  
  # Install essential system libraries
  simple_run_with_progress "Install libandroid-selinux" simple_pkg_install "libandroid-selinux" || true
  simple_run_with_progress "Install libandroid-support" simple_pkg_install "libandroid-support" || true
  
  # Install development tools that might be missing
  simple_run_with_progress "Install coreutils" simple_pkg_install "coreutils" || true
  simple_run_with_progress "Install binutils" simple_pkg_install "binutils" || true
  
  # Detect and install any remaining missing runtime libraries
  if command -v detect_install_missing_libs >/dev/null 2>&1; then
    detect_install_missing_libs || true
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
    if simple_run_with_progress "Install $pkg" apt_install_if_needed "$pkg"; then
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
    simple_run_with_progress "Install $pkg" apt_install_if_needed "$pkg" || true
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