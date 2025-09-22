#!/usr/bin/env bash
###############################################################################
# CAD-Droid Mirror Configuration Module
# Repository mirror selection, validation, and index management
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_MIRROR_CONFIG_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_MIRROR_CONFIG_LOADED=1

# Mirror Configuration Arrays
declare -a TERMUX_MIRRORS=(
  "https://packages.termux.dev/apt/termux-main"
  "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"  
  "https://grimler.se/termux/apt/termux-main"
  "https://mirror.sahilister.in/termux/apt/termux-main"
  "https://termux.librehat.com/apt/termux-main"
)

declare -a X11_MIRRORS=(
  "https://packages.termux.dev/apt/termux-x11"
  "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-x11"
  "https://grimler.se/termux/apt/termux-x11"
  "https://mirror.sahilister.in/termux/apt/termux-x11"
  "https://termux.librehat.com/apt/termux-x11"
)

# Mirror names corresponding to URLs for user-friendly display
declare -a TERMUX_MIRROR_NAMES=(
  "Official Termux (Global)"
  "Tsinghua University (China)"  
  "Grimler (Europe)"
  "Sahilister (India)"
  "LibreHat (Asia-Pacific)"
)

declare -a X11_MIRROR_NAMES=(
  "Official Termux X11 (Global)"
  "Tsinghua University X11 (China)"
  "Grimler X11 (Europe)"  
  "Sahilister X11 (India)"
  "LibreHat X11 (Asia-Pacific)"
)

# Mirror test function with spinner integration
test_mirror_speed(){
  local mirror_url="$1"
  local test_timeout="${2:-8}"
  
  if [ -z "$mirror_url" ]; then
    return 1
  fi
  
  # Extract hostname for display
  local hostname
  hostname=$(echo "$mirror_url" | sed 's|https\?://||' | cut -d'/' -f1)
  
  # Test connection with timeout
  local start_time end_time response_time
  start_time=$(date +%s%3N 2>/dev/null || date +%s)
  
  if timeout "$test_timeout" curl -sf --connect-timeout 3 --max-time "$test_timeout" \
     -H "User-Agent: Termux-Setup/1.0" \
     -o /dev/null "$mirror_url/Packages" >/dev/null 2>&1; then
    end_time=$(date +%s%3N 2>/dev/null || date +%s)
    response_time=$((end_time - start_time))
    echo "$response_time"
    return 0
  else
    return 1
  fi
}

# Select fastest working mirror with progress indication
select_fastest_mirror(){
  local mirror_type="${1:-main}"
  local -n mirror_array_ref
  
  case "$mirror_type" in
    "main"|"termux") mirror_array_ref=TERMUX_MIRRORS ;;
    "x11") mirror_array_ref=X11_MIRRORS ;;
    *)
      err "Unknown mirror type: $mirror_type"
      return 1
      ;;
  esac
  
  info "Testing $mirror_type repository mirrors..."
  
  local best_mirror=""
  local best_time=999999
  local working_mirrors=0
  
  for mirror in "${mirror_array_ref[@]}"; do
    local hostname
    hostname=$(echo "$mirror" | sed 's|https\?://||' | cut -d'/' -f1)
    
    # Show progress with spinner
    run_with_progress "Test $hostname" 12 bash -c "
      if response_time=\$(test_mirror_speed '$mirror' 8); then
        echo \"RESULT:\$response_time\" >&2
        exit 0
      else
        echo \"FAILED\" >&2
        exit 1
      fi
    " 2>&1 | {
      while IFS= read -r line; do
        if [[ "$line" == RESULT:* ]]; then
          local response_time="${line#RESULT:}"
          if [ "$response_time" -lt "$best_time" ] 2>/dev/null; then
            best_time="$response_time"
            best_mirror="$mirror"
          fi
          working_mirrors=$((working_mirrors + 1))
          ok "$hostname: ${response_time}ms"
        elif [[ "$line" == "FAILED" ]]; then
          warn "$hostname: Connection failed"
        fi
      done
    }
  done
  
  if [ -z "$best_mirror" ]; then
    err "No working mirrors found for $mirror_type"
    return 1
  fi
  
  local best_hostname
  best_hostname=$(echo "$best_mirror" | sed 's|https\?://||' | cut -d'/' -f1)
  ok "Selected fastest mirror: $best_hostname (${best_time}ms)"
  
  echo "$best_mirror"
  return 0
}

# Update repository indexes with retry logic
update_repository_indexes(){
  info "Updating package repository indexes..."
  
  local max_attempts=3
  local attempt=1
  
  while [ "$attempt" -le "$max_attempts" ]; do
    if [ "$attempt" -gt 1 ]; then
      warn "Attempt $attempt of $max_attempts..."
    fi
    
    if run_with_progress "Update package lists" 25 bash -c '
      apt-get update >/dev/null 2>&1 || [ $? -eq 100 ]
    '; then
      ok "Package indexes updated successfully"
      return 0
    else
      warn "Update attempt $attempt failed"
      attempt=$((attempt + 1))
      
      if [ "$attempt" -le "$max_attempts" ]; then
        # Clean cache and retry
        run_with_progress "Clean package cache" 8 bash -c '
          apt-get clean >/dev/null 2>&1 || true
          rm -rf "$PREFIX/var/lib/apt/lists"/* 2>/dev/null || true
        '
        sleep 2
      fi
    fi
  done
  
  err "Failed to update package indexes after $max_attempts attempts"
  return 1
}

# Configure main Termux repository
configure_main_repository(){
  info "Configuring main Termux repository..."
  
  local best_main_mirror
  if ! best_main_mirror=$(select_fastest_mirror "main"); then
    err "Failed to find working main repository mirror"
    return 1
  fi
  
  local sources_file="$PREFIX/etc/apt/sources.list"
  
  # Backup existing sources
  if [ -f "$sources_file" ]; then
    run_with_progress "Backup current sources" 3 cp "$sources_file" "$sources_file.backup"
  fi
  
  # Write new main repository configuration
  run_with_progress "Configure main repository" 5 bash -c "
    mkdir -p '$PREFIX/etc/apt' &&
    echo 'deb $best_main_mirror stable main' > '$sources_file'
  "
  
  if ! update_repository_indexes; then
    warn "Restoring original sources list"
    if [ -f "$sources_file.backup" ]; then
      cp "$sources_file.backup" "$sources_file" 2>/dev/null || true
    fi
    return 1
  fi
  
  return 0
}

# Configure X11 repository
configure_x11_repository(){
  info "Configuring X11 repository..."
  
  local best_x11_mirror
  if ! best_x11_mirror=$(select_fastest_mirror "x11"); then
    warn "Failed to find working X11 repository mirror, skipping X11 repo"
    return 0
  fi
  
  local x11_sources_dir="$PREFIX/etc/apt/sources.list.d"
  local x11_sources_file="$x11_sources_dir/x11.list"
  
  # Create sources.list.d directory
  run_with_progress "Setup X11 repository" 8 bash -c "
    mkdir -p '$x11_sources_dir' &&
    echo 'deb $best_x11_mirror x11 main' > '$x11_sources_file'
  "
  
  # Add X11 repository key
  if ! run_with_progress "Install X11 repository key" 15 bash -c '
    pkg install -y x11-repo >/dev/null 2>&1 || [ $? -eq 100 ]
  '; then
    warn "Failed to install X11 repository key"
    rm -f "$x11_sources_file" 2>/dev/null || true
    return 1
  fi
  
  if ! update_repository_indexes; then
    warn "Failed to update after X11 repo addition"
    rm -f "$x11_sources_file" 2>/dev/null || true
    return 1
  fi
  
  ok "X11 repository configured successfully"
  return 0
}

# Clean up broken repository configurations
cleanup_broken_repositories(){
  info "Cleaning up broken repository configurations..."
  
  local sources_dir="$PREFIX/etc/apt/sources.list.d"
  
  if [ ! -d "$sources_dir" ]; then
    return 0
  fi
  
  # Test each repository file
  find "$sources_dir" -name "*.list" -type f 2>/dev/null | while read -r repo_file; do
    local repo_name
    repo_name=$(basename "$repo_file" .list)
    
    # Extract repository URL
    local repo_url
    repo_url=$(awk '/^deb/ {print $2; exit}' "$repo_file" 2>/dev/null || echo "")
    
    if [ -n "$repo_url" ]; then
      # Test if repository is accessible
      if ! timeout 8 curl -sf --connect-timeout 3 \
           -H "User-Agent: Termux-Setup/1.0" \
           -o /dev/null "$repo_url/Packages" >/dev/null 2>&1; then
        warn "Removing broken repository: $repo_name"
        rm -f "$repo_file" 2>/dev/null || true
      fi
    fi
  done
  
  # Update indexes after cleanup
  update_repository_indexes || true
}

# Main mirror configuration function
configure_repositories(){
  info "Configuring package repositories..."
  
  # Clean up any broken repositories first
  cleanup_broken_repositories
  
  # Configure main repository
  if ! configure_main_repository; then
    err "Failed to configure main repository"
    return 1
  fi
  
  # Configure X11 repository
  configure_x11_repository || warn "X11 repository configuration had issues"
  
  # Final index update to ensure everything is current
  if ! update_repository_indexes; then
    err "Final repository index update failed"
    return 1
  fi
  
  ok "Repository configuration completed successfully"
  return 0
}

# Export functions for use by other modules
export -f test_mirror_speed
export -f select_fastest_mirror
export -f update_repository_indexes
export -f configure_repositories
