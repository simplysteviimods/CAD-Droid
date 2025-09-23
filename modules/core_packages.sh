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
safe_apt_operation(){
  local operation="$1"
  shift
  local args="$*"
  local max_attempts=3
  local attempt=1
  
  # Ensure mirror configuration is applied before any operation
  if [ -n "${SELECTED_MIRROR_URL:-}" ]; then
    debug "Ensuring mirror configuration is applied before $operation"
    ensure_mirror_applied
  fi
  
  while [ $attempt -le $max_attempts ]; do
    if [ $attempt -gt 1 ]; then
      debug "Attempt $attempt/$max_attempts for: $operation $args"
      sleep 2  # Brief pause between attempts
    fi
    
    # Initialize APT environment before each attempt
    initialize_apt_environment
    
    case "$operation" in
      "pkg_update")
        if command -v pkg >/dev/null 2>&1; then
          debug "Running: pkg update $args"
          yes | pkg update $args
        else
          debug "pkg command not available"
          return 1
        fi
        ;;
      "apt_update")
        debug "Running: apt update $args"
        yes | apt update $args
        ;;
      "pkg_install")
        if command -v pkg >/dev/null 2>&1; then
          debug "Running: pkg install -y $args"
          pkg install -y $args
        else
          debug "pkg command not available"
          return 1
        fi
        ;;
      "apt_install")
        debug "Running: apt install -y $args"
        yes | apt install -y $args
        ;;
      "pkg_upgrade")
        if command -v pkg >/dev/null 2>&1; then
          debug "Running: pkg upgrade -y $args"
          yes | DEBIAN_FRONTEND=noninteractive pkg upgrade -y $args \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" \
            -o Dpkg::Options::="--force-confnew"
        else
          debug "pkg command not available"
          return 1
        fi
        ;;
      "apt_upgrade")
        debug "Running: apt upgrade -y $args"
        yes | DEBIAN_FRONTEND=noninteractive apt upgrade -y $args \
          -o Dpkg::Options::="--force-confdef" \
          -o Dpkg::Options::="--force-confold" \
          -o Dpkg::Options::="--force-confnew"
        ;;
      *)
        warn "Unknown operation: $operation"
        return 1
        ;;
    esac
    
    local result=$?
    
    # Check if the operation succeeded or if package is already installed/updated
    if [ $result -eq 0 ] || [ $result -eq 100 ]; then
      debug "$operation completed with exit code: $result"
      return $result
    fi
    
    # If it's a lock error, try again
    if [ $result -eq 100 ]; then
      debug "Lock error detected, retrying..."
      attempt=$((attempt + 1))
      continue
    fi
    
    # For other errors, return immediately
    debug "$operation failed with exit code: $result"
    return $result
  done
  
  warn "Operation failed after $max_attempts attempts: $operation $args"
  return 1
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
  
  # Ensure selected mirror is applied before installing
  ensure_mirror_applied
  
  # Try pkg install first (preferred), then fallback to apt install
  # Use safe operation wrapper to handle locks
  if command -v pkg >/dev/null 2>&1; then
    if safe_apt_operation "pkg_install" "$pkg" >/dev/null 2>&1; then
      local pkg_result=$?
      if [ $pkg_result -eq 0 ] || [ $pkg_result -eq 100 ]; then
        ok "$pkg installed successfully via pkg"
        return 0
      else
        warn "pkg install failed for $pkg, trying apt install..."
      fi
    fi
  fi
  
  # Fallback to apt install with safe operation wrapper
  if safe_apt_operation "apt_install" "$pkg" >/dev/null 2>&1; then
    local apt_result=$?  
    if [ $apt_result -eq 0 ] || [ $apt_result -eq 100 ]; then
      ok "$pkg installed successfully via apt"
      return 0
    else
      warn "Failed to install $pkg"
      return 1
    fi
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
  debug "Ensuring mirror is applied, sources file: $sources_file"
  
  # Initialize APT environment first to prevent lock errors
  initialize_apt_environment
  
  # Ensure we have a valid mirror URL - set default if none selected
  if [ -z "${SELECTED_MIRROR_URL:-}" ]; then
    debug "No mirror selected, using default Termux mirror"
    SELECTED_MIRROR_URL="https://packages.termux.dev/apt/termux-main"
    SELECTED_MIRROR_NAME="Default"
  fi
  
  debug "Using mirror URL: $SELECTED_MIRROR_URL"
  
  # Always rewrite sources to ensure selected mirror is used
  debug "Enforcing mirror: ${SELECTED_MIRROR_URL}"
  if ! echo "deb ${SELECTED_MIRROR_URL} stable main" > "$sources_file" 2>/dev/null; then
    warn "Failed to write sources file: $sources_file"
    debug "Sources file write: FAILED"
    return 1
  fi
  
  debug "Sources file updated successfully"
  debug "Current sources content: $(cat "$sources_file" 2>/dev/null || echo 'Could not read')"
  
  # Clean up any conflicting sources to prevent mirror mixing
  sanitize_sources_main_only
  
  # Apply termux-reload-settings to ensure configuration is loaded
  if command -v termux-reload-settings >/dev/null 2>&1; then
    debug "Reloading Termux settings to apply mirror configuration"
    run_with_progress "Apply mirror configuration" 3 termux-reload-settings
    debug "Termux settings reloaded successfully"
  else
    debug "termux-reload-settings not available"
  fi
  
  # Verify sources.list wasn't overwritten
  if [ -f "$sources_file" ]; then
    local current_mirror
    current_mirror=$(awk '/^deb /{print $2; exit}' "$sources_file" 2>/dev/null || true)
    if [ "$current_mirror" != "$SELECTED_MIRROR_URL" ]; then
      warn "Sources.list was overwritten, restoring mirror configuration"
      echo "deb ${SELECTED_MIRROR_URL} stable main" > "$sources_file"
      debug "Mirror configuration restored"
    fi
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

# Verify and set package mirror configuration with comprehensive testing
verify_mirror(){
  local sources_file="$PREFIX/etc/apt/sources.list"
  
  # Initialize APT environment first to prevent lock errors  
  initialize_apt_environment
  
  # Ensure we have a valid mirror selection (should be set by step_mirror)
  if [ -z "${SELECTED_MIRROR_URL:-}" ]; then
    debug "No mirror selected, reading from sources.list or using default"
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
      mkdir -p "$PREFIX/etc/apt" 2>/dev/null || true
      echo "deb https://packages.termux.dev/apt/termux-main stable main" > "$sources_file"
      SELECTED_MIRROR_NAME="Default"
      SELECTED_MIRROR_URL="https://packages.termux.dev/apt/termux-main"
    fi
  else
    # Mirror already selected, ensure it's written to sources.list
    debug "Using already selected mirror: $SELECTED_MIRROR_URL"
    mkdir -p "$PREFIX/etc/apt" 2>/dev/null || true
    if ! echo "deb ${SELECTED_MIRROR_URL} stable main" > "$sources_file" 2>/dev/null; then
      warn "Failed to write selected mirror to sources file"
      return 1
    fi
    debug "Mirror written to sources.list: $(cat "$sources_file" 2>/dev/null || echo 'failed to read')"
  fi
  
  # Reload settings after writing sources.list
  if command -v termux-reload-settings >/dev/null 2>&1; then
    termux-reload-settings >/dev/null 2>&1 || true
    debug "Termux settings reloaded"
  fi
  
  # Test mirror functionality with package list update (no curl dependency)
  info "Verifying mirror configuration..."
  debug "Testing mirror: $SELECTED_MIRROR_URL"
  
  local temp_dir="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
  mkdir -p "$temp_dir" 2>/dev/null || true
  local update_log="$temp_dir/mirror-test-$$"
  
  # Use pkg update as the primary method (official Termux way)
  if command -v pkg >/dev/null 2>&1; then
    debug "Using pkg update for mirror verification"
    if safe_apt_operation "pkg_update" >"$update_log" 2>&1; then
      ok "Mirror verification successful: ${SELECTED_MIRROR_NAME}"
      debug "Mirror verification: SUCCESS"
      rm -f "$update_log" 2>/dev/null || true
    else
      info "Mirror verification completed (configuration saved): ${SELECTED_MIRROR_NAME}"
      debug "Mirror verification: PARTIAL (mirror configured but update had issues)"
      if [ -f "$update_log" ]; then
        debug "Update log: $(tail -5 "$update_log" 2>/dev/null || echo 'no log content')"
      else
        debug "Update log: could not create temporary file"
      fi
      rm -f "$update_log" 2>/dev/null || true
    fi
  else
    # Fallback to apt update if pkg is not available
    debug "Using apt update for mirror verification (pkg not available)"
    if safe_apt_operation "apt_update" >"$update_log" 2>&1; then
      ok "Mirror verification successful: ${SELECTED_MIRROR_NAME}"
      debug "Mirror verification: SUCCESS"
      rm -f "$update_log" 2>/dev/null || true
    else
      info "Mirror verification completed (configuration saved): ${SELECTED_MIRROR_NAME}"
      debug "Mirror verification: PARTIAL (mirror configured but update had issues)"
      if [ -f "$update_log" ]; then
        debug "Update log: $(tail -5 "$update_log" 2>/dev/null || echo 'no log content')"
      else
        debug "Update log: could not create temporary file"
      fi
      rm -f "$update_log" 2>/dev/null || true
    fi
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
    "gh"              # GitHub CLI
    "pulseaudio"      # Audio system
    "dbus"            # System bus
    "fontconfig"      # Font management
    "ttf-dejavu"      # Fonts
  )
  
  local success_count=0
  local total=${#essential_packages[@]}
  
  for pkg in "${essential_packages[@]}"; do
    local install_time
    install_time=$(get_package_install_time "$pkg")
    if run_with_progress "Install $pkg" "$install_time" apt_install_if_needed "$pkg"; then
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
    run_with_progress "Install $pkg" 20 apt_install_if_needed "$pkg" || true
  done
  
  return 0
}

# === Specialized Package Operations ===

# Install proot-distro and container support
install_container_support(){
  pecho "$PASTEL_PURPLE" "Installing container support..."
  
  if ! dpkg_is_installed "proot-distro"; then
    if run_with_progress "Install proot-distro" 30 apt_install_if_needed "proot-distro"; then
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
    run_with_progress "Install $pkg" 35 apt_install_if_needed "$pkg" || true
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
  debug "Using mirror: ${SELECTED_MIRROR_URL:-default}"
  
  # Ensure selected mirror is applied and sources file is written before updating
  ensure_mirror_applied
  
  # Check if sources file exists and is readable
  local sources_file="$PREFIX/etc/apt/sources.list"
  if [ ! -f "$sources_file" ]; then
    warn "Sources file missing: $sources_file"
    debug "Creating minimal sources file"
    echo "deb ${SELECTED_MIRROR_URL:-https://packages.termux.dev/apt/termux-main} stable main" > "$sources_file"
  fi
  
  debug "Sources file content:"
  debug "$(cat "$sources_file" 2>/dev/null || echo 'Could not read sources file')"
  
  # Simple approach - try pkg first, then apt
  if command -v pkg >/dev/null 2>&1; then
    info "Updating with pkg..."
    debug "Running: pkg update -y"
    local pkg_log="${TMPDIR:-$PREFIX/tmp}/pkg-update-$$.log"
    if safe_apt_operation "pkg_update" "-y" 2>&1 | tee "$pkg_log" >/dev/null; then
      ok "Package lists updated via pkg"
      export PACKAGES_UPDATED=1
      debug "pkg update: SUCCESS"
      rm -f "$pkg_log" 2>/dev/null || true
      return 0
    else
      warn "pkg update failed, trying apt..."
      debug "pkg update: FAILED"
      if [ -f "$pkg_log" ]; then
        debug "pkg update error log:"
        debug "$(cat "$pkg_log" 2>/dev/null | tail -10)"
        rm -f "$pkg_log" 2>/dev/null || true
      fi
    fi
  fi
  
  # Fallback to apt update
  info "Updating with apt..."
  debug "Running: apt update"
  local apt_log="${TMPDIR:-$PREFIX/tmp}/apt-update-$$.log"
  if safe_apt_operation "apt_update" 2>&1 | tee "$apt_log" >/dev/null; then
    ok "Package lists updated via apt"
    export PACKAGES_UPDATED=1
    debug "apt update: SUCCESS"
    rm -f "$apt_log" 2>/dev/null || true
    return 0
  else
    warn "Package list update failed"
    debug "apt update: FAILED"
    if [ -f "$apt_log" ]; then
      debug "apt update error log:"
      debug "$(cat "$apt_log" 2>/dev/null | tail -10)"
      rm -f "$apt_log" 2>/dev/null || true
    fi
    return 1
  fi
}

# Upgrade all packages using appropriate Termux commands
upgrade_packages(){
  info "Upgrading packages..."
  
  # Ensure selected mirror is applied and sources file is written before upgrading
  ensure_mirror_applied
  
  # Always update package lists first
  update_package_lists || {
    warn "Failed to update package lists before upgrade"
    return 1
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
      run_with_progress "Install $lib (apt)" 15 bash -c "yes | DEBIAN_FRONTEND=noninteractive apt install -y '$lib' >/dev/null 2>&1 || [ \$? -eq 100 ]" || true
    fi
  done
  
  # Upgrade with spinners and non-interactive flags using safe operations
  if command -v pkg >/dev/null 2>&1; then
    if run_with_progress "Upgrading packages with pkg" 45 bash -c 'safe_apt_operation "pkg_upgrade" >/dev/null 2>&1'; then
      ok "Packages upgraded successfully via pkg"
      return 0
    else
      warn "pkg upgrade failed, trying apt..."
    fi
  fi
  
  # Fallback to apt upgrade with safe operations
  if run_with_progress "Upgrading packages with apt" 45 bash -c 'safe_apt_operation "apt_upgrade" >/dev/null 2>&1'; then
    ok "Packages upgraded successfully via apt"
    return 0
  else
    warn "Package upgrade failed"
    return 1
  fi
}

# === Step Functions ===

# Step: Mirror selection for faster downloads
step_mirror(){
  pecho "$PASTEL_PURPLE" "Choose Termux mirror:"
  
  # Use static reliable mirror list (no auto-detection)
  local -a urls names
  urls=(
    "https://packages.termux.dev/apt/termux-main"
    "https://packages-cf.termux.dev/apt/termux-main"
    "https://fau.mirror.termux.dev/apt/termux-main"
    "https://mirror.bfsu.edu.cn/termux/apt/termux-main"
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
    "https://grimler.se/termux/termux-main"
    "https://termux.mentality.rip/termux/apt/termux-main"
  )
  names=(
    "Official Termux (Global CDN) ★"
    "Official Termux (Cloudflare CDN) ★"
    "FAU (Germany)"
    "BFSU (China)"
    "Tsinghua (China)"
    "Grimler (Sweden)"
    "Mentality (North America)"
  )

  # Ensure we have at least one mirror
  if [ ${#urls[@]} -eq 0 ] || [ ${#names[@]} -eq 0 ]; then
    err "No mirrors available"
    return 1
  fi

  # Show recommendation
  echo ""
  pecho "$PASTEL_GREEN" "Recommended: Official mirrors (marked with ★) are usually fastest and most reliable"
  echo ""
  
  # Display mirror options with colors  
  local i
  for i in "${!names[@]}"; do 
    local seq
    seq=$(color_for_index "$i")
    # Display mirrors with consistent formatting (★ already in name)
    printf "%b[%d] %s%b\n" "$seq" "$i" "${names[$i]}" '\033[0m'
  done
  
  # Auto-select option
  echo ""
  pecho "$PASTEL_CYAN" "Selection Options:"
  info "  • Press Enter for auto-selection (tests speed and selects fastest)"
  local max_idx=$((${#names[@]} - 1))
  if [ "$max_idx" -gt 0 ]; then
    info "  • Type a number (0 to $max_idx) for manual selection"
  fi
  
  local idx=""
  if [ "$NON_INTERACTIVE" = "1" ]; then
    # Auto-select in non-interactive mode
    idx="auto"
  else
    printf "%bMirror selection (0-$max_idx or Enter for auto): %b" "$PASTEL_PINK" '\033[0m'
    read -r idx
  fi
  
  # Handle auto-selection
  if [ -z "$idx" ] || [ "$idx" = "auto" ]; then
    info "Auto-selecting fastest mirror..."
    if command -v select_fastest_mirror >/dev/null 2>&1; then
      local best_mirror
      if best_mirror=$(select_fastest_mirror "main"); then
        SELECTED_MIRROR_URL="$best_mirror"
        # Find the corresponding name
        local j
        for j in "${!urls[@]}"; do
          if [ "${urls[$j]}" = "$best_mirror" ]; then
            SELECTED_MIRROR_NAME="${names[$j]}"
            break
          fi
        done
        [ -z "$SELECTED_MIRROR_NAME" ] && SELECTED_MIRROR_NAME="Auto-selected"
      else
        warn "Auto-selection failed, using default mirror"
        idx=0
      fi
    else
      warn "Auto-selection not available, using default mirror"
      idx=0
    fi
  fi
  
  # Manual selection fallback
  if [ -n "$idx" ] && [ "$idx" != "auto" ]; then
    # Validate selection
    case "$idx" in
      *[!0-9]*) idx=0 ;;
      *) [ "$idx" -ge "${#urls[@]}" ] && idx=0 ;;
    esac
    
    # Ensure we have valid arrays and index
    if [ ${#names[@]} -gt 0 ] && [ ${#urls[@]} -gt 0 ] && [ "$idx" -lt "${#names[@]}" ]; then
      SELECTED_MIRROR_NAME="${names[$idx]}"
      SELECTED_MIRROR_URL="${urls[$idx]}"
    else
      warn "Invalid selection, using first available mirror"
      SELECTED_MIRROR_NAME="${names[0]}"
      SELECTED_MIRROR_URL="${urls[0]}"
    fi
  fi
  
  # Ensure we have a valid mirror selection
  if [ -z "${SELECTED_MIRROR_URL:-}" ]; then
    # Fallback to first mirror if nothing selected
    SELECTED_MIRROR_NAME="${names[0]}"
    SELECTED_MIRROR_URL="${urls[0]}"
    debug "No mirror selected, using first available: $SELECTED_MIRROR_NAME"
  fi
  
  # Clean up sources and verify mirror (verify_mirror will handle sources.list writing)
  sanitize_sources_main_only
  verify_mirror
  
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
  # Mirror should already be configured in step_mirror, only ensure if not available
  if [ ! -f "$PREFIX/etc/apt/sources.list" ]; then
    debug "Sources file missing, applying mirror configuration"
    ensure_mirror_applied
  fi
  
  # Use apt directly as pkg is not reliable for x11-repo
  run_with_progress "Add X11 repository (apt)" 15 bash -c 'yes | apt install -y x11-repo >/dev/null 2>&1 || true'
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
  debug "Current mirror: ${SELECTED_MIRROR_URL:-not set}"
  debug "Packages updated flag: ${PACKAGES_UPDATED:-0}"
  
  # Mirror should already be configured in step_mirror, only ensure if not set
  if [ -z "${SELECTED_MIRROR_URL:-}" ] || [ ! -f "$PREFIX/etc/apt/sources.list" ]; then
    debug "Mirror not configured, applying mirror configuration"
    ensure_mirror_applied
  else
    debug "Using existing mirror configuration: ${SELECTED_MIRROR_NAME:-unknown}"
  fi
  
  if update_package_lists; then
    debug "Package list update: SUCCESS"
    upgrade_packages || {
      warn "Package upgrade failed but continuing"
      debug "Package upgrade: FAILED (exit code: $?)"
    }
  else
    warn "Package list update failed"
    debug "Package list update: FAILED (exit code: $?)"
  fi
  
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
  
  # Mirror should already be configured, only ensure if sources.list doesn't exist
  if [ ! -f "$PREFIX/etc/apt/sources.list" ]; then
    debug "Sources file missing, applying mirror configuration"
    ensure_mirror_applied
  fi
  
  # Install X11 repo if not already installed
  if ! dpkg_is_installed "x11-repo"; then
    run_with_progress "Add X11 repository (apt)" 15 bash -c 'yes | apt install -y x11-repo >/dev/null 2>&1 || [ $? -eq 100 ]'
    
    # Update indexes after adding X11 repo - don't need ensure_mirror_applied
    debug "Updating package indexes after X11 repo installation"
    update_package_lists || true
  fi
  
  # Proactively install critical libraries that commonly cause XFCE installation failures
  info "Installing critical runtime libraries..."
  
  # Install libpcre2 and related libraries (fixes "cut" command issues)
  run_with_progress "Install libpcre2 libraries" 20 bash -c 'yes | apt install -y libpcre2-8-0 pcre2-utils libpcre2-8 >/dev/null 2>&1 || [ $? -eq 100 ]'
  
  # Install OpenSSL libraries (fixes libcrypto.so.3 issues)
  run_with_progress "Install OpenSSL libraries" 20 bash -c 'yes | apt install -y openssl libssl3 libcrypto3 openssl-tool >/dev/null 2>&1 || [ $? -eq 100 ]'
  
  # Install essential system libraries
  run_with_progress "Install core system libraries" 20 bash -c 'yes | apt install -y libandroid-selinux libandroid-support >/dev/null 2>&1 || [ $? -eq 100 ]'
  
  # Install development tools that might be missing
  run_with_progress "Install build essentials" 15 bash -c 'yes | apt install -y coreutils binutils >/dev/null 2>&1 || [ $? -eq 100 ]'
  
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
    local install_time
    install_time=$(get_package_install_time "$pkg")
    if run_with_progress "Install $pkg" "$install_time" apt_install_if_needed "$pkg"; then
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
    run_with_progress "Install $pkg" 25 apt_install_if_needed "$pkg" || true
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