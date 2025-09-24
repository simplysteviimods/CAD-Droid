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

# Regional Mirror Configuration - Following Termux best practices
# Groups mirrors by region for better user experience and auto-detection

# Official mirrors (always preferred and tested first)
declare -a OFFICIAL_MIRRORS=(
  "https://packages.termux.dev/apt/termux-main"
  "https://packages-cf.termux.dev/apt/termux-main"
)

declare -a OFFICIAL_MIRROR_NAMES=(
  "Official Termux (Global CDN)"
  "Official Termux (Cloudflare CDN)"
)

# Regional mirror groups based on Termux community recommendations
declare -A REGIONAL_MIRRORS=(
  # Asia-Pacific region
  ["asia-pacific-urls"]="https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main|https://mirror.bfsu.edu.cn/termux/apt/termux-main|https://mirror.sahilister.in/termux/apt/termux-main"
  ["asia-pacific-names"]="Tsinghua University (China)|BFSU Mirror (China)|Sahilister (India)"
  
  # Europe region  
  ["europe-urls"]="https://grimler.se/termux/apt/termux-main|https://fau.mirror.termux.dev/apt/termux-main"
  ["europe-names"]="Grimler (Sweden)|FAU (Germany)"
  
  # Americas region
  ["americas-urls"]="https://termux.mentality.rip/termux/apt/termux-main"
  ["americas-names"]="Mentality (North America)"
)

# X11 repository mirrors (parallel structure)
declare -a OFFICIAL_X11_MIRRORS=(
  "https://packages.termux.dev/apt/termux-x11"
  "https://packages-cf.termux.dev/apt/termux-x11"
)

declare -A REGIONAL_X11_MIRRORS=(
  ["asia-pacific-urls"]="https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-x11|https://mirror.bfsu.edu.cn/termux/apt/termux-x11|https://mirror.sahilister.in/termux/apt/termux-x11"
  ["europe-urls"]="https://grimler.se/termux/apt/termux-x11|https://fau.mirror.termux.dev/apt/termux-x11"
  ["americas-urls"]="https://termux.mentality.rip/termux/apt/termux-x11"
)

# Simple region detection based on timezone and locale
detect_user_region(){
  local detected_region="global"
  
  # Try timezone-based detection first
  if [ -n "${TZ:-}" ]; then
    case "$TZ" in
      Asia/*|*/Shanghai|*/Beijing|*/Tokyo|*/Mumbai|*/Kolkata|*/Singapore)
        detected_region="asia-pacific" ;;
      Europe/*|*/London|*/Berlin|*/Stockholm|*/Amsterdam)
        detected_region="europe" ;;
      America/*|US/*|Canada/*)
        detected_region="americas" ;;
    esac
  fi
  
  # Fallback to locale detection if timezone didn't help
  if [ "$detected_region" = "global" ] && [ -n "${LANG:-}" ]; then
    case "$LANG" in
      zh_*|ja_*|ko_*|hi_*|*_CN|*_JP|*_KR|*_IN)
        detected_region="asia-pacific" ;;
      *_DE|*_SE|*_GB|*_FR|*_ES|*_IT|*_NL|*_FI|*_NO|*_DK)
        detected_region="europe" ;;
      en_US|en_CA|es_*|pt_BR|fr_CA)
        detected_region="americas" ;;
    esac
  fi
  
  echo "$detected_region"
}

# Get suggested mirrors for a region
get_regional_mirrors(){
  local region="$1"
  local repo_type="${2:-main}"
  local -a suggested_urls=()
  local -a suggested_names=()
  
  # Always include official mirrors first
  if [ "$repo_type" = "x11" ]; then
    suggested_urls+=("${OFFICIAL_X11_MIRRORS[@]}")
  else
    suggested_urls+=("${OFFICIAL_MIRRORS[@]}")
    suggested_names+=("${OFFICIAL_MIRROR_NAMES[@]}")
  fi
  
  # Add regional mirrors if available - only for valid regions
  if [ "$region" != "global" ]; then
    local urls_key="${region}-urls"
    local names_key="${region}-names"
    
    if [ "$repo_type" = "x11" ]; then
      if [ -n "${REGIONAL_X11_MIRRORS[$urls_key]:-}" ]; then
        IFS='|' read -ra regional_urls <<< "${REGIONAL_X11_MIRRORS[$urls_key]}"
        suggested_urls+=("${regional_urls[@]}")
      fi
    else
      if [ -n "${REGIONAL_MIRRORS[$urls_key]:-}" ] && [ -n "${REGIONAL_MIRRORS[$names_key]:-}" ]; then
        IFS='|' read -ra regional_urls <<< "${REGIONAL_MIRRORS[$urls_key]}"
        IFS='|' read -ra regional_names <<< "${REGIONAL_MIRRORS[$names_key]}"
        suggested_urls+=("${regional_urls[@]}")
        suggested_names+=("${regional_names[@]}")
      fi
    fi
  fi
  
  # Return as space-separated values for easy parsing
  printf "%s\n" "${suggested_urls[@]}"
}

# Get mirror names for display
get_regional_mirror_names(){
  local region="$1" 
  local repo_type="${2:-main}"
  local -a suggested_names=()
  
  # Always include official mirror names first
  suggested_names+=("${OFFICIAL_MIRROR_NAMES[@]}")
  
  # Add regional mirror names if available (only for main repo and valid regions)
  if [ "$repo_type" != "x11" ] && [ "$region" != "global" ]; then
    local names_key="${region}-names"
    if [ -n "${REGIONAL_MIRRORS[$names_key]:-}" ]; then
      IFS='|' read -ra regional_names <<< "${REGIONAL_MIRRORS[$names_key]}"
      suggested_names+=("${regional_names[@]}")
    fi
  fi
  
  printf "%s\n" "${suggested_names[@]}"
}

# Mirror test function with spinner integration  
test_mirror_speed(){
  local mirror_url="$1"
  local test_timeout="${2:-8}"
  
  # Test reachability and response time
  local start_time end_time response_time
  start_time=$(date +%s%3N)
  
  if curl --max-time "$test_timeout" --connect-timeout 3 --fail --silent --head "$mirror_url" >/dev/null 2>&1; then
    end_time=$(date +%s%3N)
    response_time=$((end_time - start_time))
    echo "$response_time"
    return 0
  else
    return 1
  fi
}

# Select fastest working mirror with regional preference
select_fastest_mirror(){
  local mirror_type="${1:-main}"
  local user_region
  user_region=$(detect_user_region)
  
  info "Detected region: $user_region"
  info "Selecting optimal $mirror_type repository mirror..."
  
  # Get suggested mirrors for the user's region
  local -a suggested_mirrors
  mapfile -t suggested_mirrors < <(get_regional_mirrors "$user_region" "$mirror_type")
  
  if [ ${#suggested_mirrors[@]} -eq 0 ]; then
    warn "No mirrors available for region $user_region, using global defaults"
    if [ "$mirror_type" = "x11" ]; then
      suggested_mirrors=("${OFFICIAL_X11_MIRRORS[@]}")
    else
      suggested_mirrors=("${OFFICIAL_MIRRORS[@]}")
    fi
  fi
  
  local best_mirror=""
  local best_time=999999
  local working_mirrors=0
  
  for mirror in "${suggested_mirrors[@]}"; do
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
  ok "Selected optimal mirror: $best_hostname (${best_time}ms)"
  
  echo "$best_mirror"
  return 0
  
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
      apt update >/dev/null 2>&1 || [ $? -eq 100 ]
    '; then
      ok "Package indexes updated successfully"
      return 0
    else
      warn "Update attempt $attempt failed"
      attempt=$((attempt + 1))
      
      if [ "$attempt" -le "$max_attempts" ]; then
        # Clean cache and retry
        run_with_progress "Clean package cache" 8 bash -c '
          apt clean >/dev/null 2>&1 || true
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
    yes | apt install -y x11-repo >/dev/null 2>&1 || [ $? -eq 100 ]
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

# Clean previous mirror configuration files to ensure clean state
wipe_previous_mirror_config(){
  info "Cleaning previous mirror configuration files..."
  
  # Files and directories to clean for fresh mirror configuration
  local mirror_config_files=(
    "$PREFIX/etc/apt/sources.list"
    "$PREFIX/etc/apt/sources.list.d"
    "$PREFIX/var/lib/apt/lists"
    "$PREFIX/var/cache/apt/archives"
  )
  
  local cleaned_count=0
  
  # Remove existing sources.list to ensure clean slate
  if [ -f "$PREFIX/etc/apt/sources.list" ]; then
    if cp "$PREFIX/etc/apt/sources.list" "$PREFIX/etc/apt/sources.list.backup.$(date +%s)" 2>/dev/null; then
      debug "Backed up existing sources.list"
    fi
    if rm -f "$PREFIX/etc/apt/sources.list" 2>/dev/null; then
      cleaned_count=$((cleaned_count + 1))
      debug "Removed old sources.list"
    fi
  fi
  
  # Clean sources.list.d directory
  if [ -d "$PREFIX/etc/apt/sources.list.d" ]; then
    if rm -rf "$PREFIX/etc/apt/sources.list.d"/* 2>/dev/null; then
      cleaned_count=$((cleaned_count + 1))
      debug "Cleaned sources.list.d directory"
    fi
  fi
  
  # Clean package lists to force fresh download
  if [ -d "$PREFIX/var/lib/apt/lists" ]; then
    if rm -rf "$PREFIX/var/lib/apt/lists"/* 2>/dev/null; then
      cleaned_count=$((cleaned_count + 1))
      debug "Cleaned package lists"
    fi
  fi
  
  # Ensure directories exist
  mkdir -p "$PREFIX/etc/apt/sources.list.d" 2>/dev/null || true
  mkdir -p "$PREFIX/var/lib/apt/lists" 2>/dev/null || true
  mkdir -p "$PREFIX/var/cache/apt/archives" 2>/dev/null || true
  
  debug "Mirror configuration files cleaned ($cleaned_count items)"
}

# Main mirror configuration function
configure_repositories(){
  info "Configuring package repositories..."
  
  # Wipe previous mirror configuration for clean setup
  wipe_previous_mirror_config
  
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
export -f wipe_previous_mirror_config
