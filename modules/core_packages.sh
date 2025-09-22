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

# Install a package only if it's not already installed - treating exit code 100 as success
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
  # Exit code 100 means already installed - treat as success
  if run_with_progress "Install $pkg" 18 bash -c "apt-get -y install $pkg >/dev/null 2>&1 || [ \$? -eq 100 ]"; then
    ok "$pkg installed successfully"
    return 0
  else
    warn "Failed to install $pkg"
    return 1
  fi
}

# Fix broken APT packages
apt_fix_broken() {
  info "Fixing broken packages..."
  run_with_progress "Fix broken packages" 30 bash -c '
    apt-get -y -f install >/dev/null 2>&1 &&
    dpkg --configure -a >/dev/null 2>&1 &&
    apt-get -y autoremove >/dev/null 2>&1
  '
}

# Ensure essential download tools are available
ensure_download_tool(){
  local tool_ready=0
  
  # Check for wget (preferred for APK downloads)
  if ! command -v wget >/dev/null 2>&1; then
    info "Installing wget..."
    if run_with_progress "Install wget" 15 bash -c "apt-get update >/dev/null 2>&1 && apt-get -y install wget >/dev/null 2>&1 || [ \$? -eq 100 ]"; then
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
      if run_with_progress "Install curl" 15 bash -c "apt-get -y install curl >/dev/null 2>&1 || [ \$? -eq 100 ]"; then
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

# Update package indexes with retry logic
update_indexes_with_retry(){
  local max_attempts=3
  local attempt=1
  
  while [ "$attempt" -le "$max_attempts" ]; do
    info "Updating package indexes (attempt $attempt/$max_attempts)..."
    
    if run_with_progress "Update package lists" 25 bash -c 'apt-get update >/dev/null 2>&1 || [ $? -eq 100 ]'; then
      ok "Package indexes updated successfully"
      return 0
    else
      warn "Update attempt $attempt failed"
      
      if [ "$attempt" -lt "$max_attempts" ]; then
        # Clean cache and try again
        run_with_progress "Clean package cache" 8 bash -c 'apt-get clean >/dev/null 2>&1 || true'
        sleep 2
      fi
      
      attempt=$((attempt + 1))
    fi
  done
  
  err "Failed to update package indexes after $max_attempts attempts"
  return 1
}

# Install core system packages
install_core_packages(){
  info "Installing core system packages..."
  
  local core_packages=(
    "coreutils"
    "findutils" 
    "sed"
    "gawk"
    "grep"
    "termux-tools"
    "proot"
    "util-linux"
    "jq"
    "git"
    "curl"
    "wget"
    "nano"
    "vim"
    "openssh"
  )
  
  local installed_count=0
  local failed_packages=()
  
  for package in "${core_packages[@]}"; do
    if apt_install_if_needed "$package"; then
      installed_count=$((installed_count + 1))
    else
      failed_packages+=("$package")
    fi
  done
  
  # Report results
  local total_packages=${#core_packages[@]}
  if [ "$installed_count" -eq "$total_packages" ]; then
    ok "All core packages installed successfully ($installed_count/$total_packages)"
  else
    warn "Core package installation: $installed_count/$total_packages successful"
    if [ ${#failed_packages[@]} -gt 0 ]; then
      warn "Failed packages: ${failed_packages[*]}"
    fi
  fi
  
  return 0
}

# Export functions for use by other modules
export -f dpkg_is_installed
export -f pkg_available
export -f apt_install_if_needed
export -f apt_fix_broken
export -f ensure_download_tool
export -f update_indexes_with_retry
export -f install_core_packages
