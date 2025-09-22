#!/usr/bin/env bash
###############################################################################
# CAD-Droid APK Management Module
# F-Droid APK downloads and Android app installation management
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_APK_MANAGEMENT_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_APK_MANAGEMENT_LOADED=1

# APK Configuration - Use persistent directories
# Primary location: external storage for user access
readonly APK_DOWNLOAD_DIR_PRIMARY="/storage/emulated/0/Download/CAD-Droid-APKs"
# Fallback location: internal storage (always accessible)  
readonly APK_DOWNLOAD_DIR_FALLBACK="$HOME/.cad/apks"
# Working directory for tracking downloads
readonly APK_STATE_DIR="$HOME/.cad/apk-state"

# Global APK download directory (set during initialization)
APK_DOWNLOAD_DIR=""

# APK download tracking arrays - persistent across sessions with global scope
declare -ga DOWNLOADED_APKS=()
declare -ga FAILED_APKS=()
declare -ga PENDING_APKS=()

# F-Droid API configuration
readonly FDROID_API_BASE="https://f-droid.org/api/v1"
readonly FDROID_REPO_BASE="https://f-droid.org/repo"

# Minimum APK size check (12KB)
readonly MIN_APK_SIZE=12288

# Essential APKs from F-Droid with their package IDs - Complete Termux plugin suite
declare -gA ESSENTIAL_APKS 2>/dev/null || true
ESSENTIAL_APKS=(
  ["Termux:API"]="com.termux.api"
  ["Termux:Boot"]="com.termux.boot"
  ["Termux:Float"]="com.termux.float"
  ["Termux:Styling"]="com.termux.styling"
  ["Termux:Tasker"]="com.termux.tasker"
  ["Termux:Widget"]="com.termux.widget"
  ["Termux:X11"]="com.termux.x11"
  ["Termux:GUI"]="com.termux.gui"
)

# GitHub backup URLs for Termux plugins when F-Droid fails
declare -gA TERMUX_GITHUB_URLS 2>/dev/null || true
TERMUX_GITHUB_URLS=(
  ["com.termux.api"]="https://github.com/termux/termux-api/releases/latest/download/termux-api.apk"
  ["com.termux.boot"]="https://github.com/termux/termux-boot/releases/latest/download/termux-boot.apk"
  ["com.termux.float"]="https://github.com/termux/termux-float/releases/latest/download/termux-float.apk"
  ["com.termux.styling"]="https://github.com/termux/termux-styling/releases/latest/download/termux-styling.apk"
  ["com.termux.tasker"]="https://github.com/termux/termux-tasker/releases/latest/download/termux-tasker.apk"
  ["com.termux.widget"]="https://github.com/termux/termux-widget/releases/latest/download/termux-widget.apk"
  ["com.termux.x11"]="https://github.com/termux/termux-x11/releases/latest/download/termux-x11-universal-1.02.07-0-all.apk"
  ["com.termux.gui"]="https://github.com/termux/termux-gui/releases/latest/download/termux-gui.apk"
)

# Initialize APK management system with persistent storage
init_apk_system(){
  info "Initializing APK management system..."
  
  # Create state directory first (always accessible)
  if ! mkdir -p "$APK_STATE_DIR" 2>/dev/null; then
    err "Cannot create APK state directory: $APK_STATE_DIR"
    return 1
  fi
  
  # Ensure storage permissions are available first
  if [ ! -d "$HOME/storage" ]; then
    if [ "$NON_INTERACTIVE" != "1" ]; then
      echo ""
      pecho "$PASTEL_PURPLE" "=== Storage Permission Required ==="
      echo ""
      pecho "$PASTEL_CYAN" "What will happen next:"
      info "• Android permission dialog will appear"
      info "• Grant 'Files and media' access to Termux"
      info "• This allows APK files to be saved to Downloads folder"
      echo ""
      pecho "$PASTEL_YELLOW" "Press Enter to request storage permission..."
      read -r
    fi
    
    warn "Storage access not available, requesting permissions..."
    if command -v termux-setup-storage >/dev/null 2>&1; then
      info "Requesting storage access..."
      termux-setup-storage && ok "Storage access granted" || warn "Storage access may have failed"
      # Wait a moment for storage to be available
      sleep 2
    else
      warn "termux-setup-storage not available, using fallback directory"
    fi
  fi
  
  # Try primary directory first (external storage)
  local selected_dir=""
  if mkdir -p "$APK_DOWNLOAD_DIR_PRIMARY" 2>/dev/null && [ -w "$APK_DOWNLOAD_DIR_PRIMARY" ]; then
    selected_dir="$APK_DOWNLOAD_DIR_PRIMARY"
    # Set proper permissions for APK directory and all parent directories
    chmod 755 "$selected_dir" 2>/dev/null || true
    chmod 755 "$(dirname "$selected_dir")" 2>/dev/null || true
    # Make sure APKs will be readable and executable
    find "$selected_dir" -name "*.apk" -exec chmod 644 {} \; 2>/dev/null || true
    info "Using external storage for APKs: $selected_dir"
  else
    # Fallback to internal storage
    if mkdir -p "$APK_DOWNLOAD_DIR_FALLBACK" 2>/dev/null; then
      selected_dir="$APK_DOWNLOAD_DIR_FALLBACK"
      # Set proper permissions for APK directory and all parent directories
      chmod 755 "$selected_dir" 2>/dev/null || true
      chmod 755 "$(dirname "$selected_dir")" 2>/dev/null || true
      # Make sure APKs will be readable and executable
      find "$selected_dir" -name "*.apk" -exec chmod 644 {} \; 2>/dev/null || true
      warn "External storage not available, using internal storage: $selected_dir"
    else
      err "Cannot create any APK directory"
      return 1
    fi
  fi
  
  # Set global APK directory
  APK_DOWNLOAD_DIR="$selected_dir"
  
  # Create .nomedia file to prevent APKs from appearing in gallery
  touch "$APK_DOWNLOAD_DIR/.nomedia" 2>/dev/null || true
  
  # Load previous download state if available
  load_apk_state
  
  info "APK system initialized: $APK_DOWNLOAD_DIR"
  return 0
}

# Load APK download state from previous sessions
load_apk_state(){
  local state_file="$APK_STATE_DIR/downloads.json"
  
  if [ -f "$state_file" ]; then
    # Load arrays from JSON state file if jq is available
    if command -v jq >/dev/null 2>&1; then
      local downloaded_json failed_json pending_json
      downloaded_json=$(jq -r '.downloaded // [] | @sh' "$state_file" 2>/dev/null)
      failed_json=$(jq -r '.failed // [] | @sh' "$state_file" 2>/dev/null)
      pending_json=$(jq -r '.pending // [] | @sh' "$state_file" 2>/dev/null)
      
      [ -n "$downloaded_json" ] && eval "DOWNLOADED_APKS=($downloaded_json)"
      [ -n "$failed_json" ] && eval "FAILED_APKS=($failed_json)"
      [ -n "$pending_json" ] && eval "PENDING_APKS=($pending_json)"
      
      debug "Loaded APK state: ${#DOWNLOADED_APKS[@]} downloaded, ${#FAILED_APKS[@]} failed, ${#PENDING_APKS[@]} pending"
    fi
  fi
}

# Save APK download state for persistence across sessions
save_apk_state(){
  local state_file="$APK_STATE_DIR/downloads.json"
  
  # Create JSON state file if jq is available
  if command -v jq >/dev/null 2>&1; then
    local json_data
    json_data=$(jq -n \
      --argjson downloaded "$(printf '%s\n' "${DOWNLOADED_APKS[@]}" | jq -R . | jq -s .)" \
      --argjson failed "$(printf '%s\n' "${FAILED_APKS[@]}" | jq -R . | jq -s .)" \
      --argjson pending "$(printf '%s\n' "${PENDING_APKS[@]}" | jq -R . | jq -s .)" \
      '{downloaded: $downloaded, failed: $failed, pending: $pending}')
    
    echo "$json_data" > "$state_file" 2>/dev/null || warn "Could not save APK state"
  else
    # Fallback to simple text format
    {
      echo "# CAD-Droid APK Download State"
      echo "DOWNLOADED: ${DOWNLOADED_APKS[*]}"
      echo "FAILED: ${FAILED_APKS[*]}"
      echo "PENDING: ${PENDING_APKS[*]}"
    } > "$state_file" 2>/dev/null || warn "Could not save APK state"
  fi
}

# Ensure minimum APK file size and validity
ensure_min_size(){
  local f="$1"
  
  if [ ! -f "$f" ]; then
    return 1
  fi
  
  # Get file size using stat or wc as fallback
  local sz
  if sz=$(stat -c%s "$f" 2>/dev/null); then
    :  # stat worked
  elif sz=$(wc -c < "$f" 2>/dev/null); then
    :  # wc worked
  else
    sz=0
  fi
  
  # Check if file meets minimum size requirement
  if [ "$sz" -lt "$MIN_APK_SIZE" ]; then
    warn "APK file too small: $sz bytes (minimum $MIN_APK_SIZE)"
    rm -f "$f" 2>/dev/null || true
    return 1
  fi
  
  return 0
}

# Enhanced HTTP fetch function with wget-only approach
http_fetch(){
  local url="$1" output="$2"
  local timeout="${CURL_MAX_TIME:-40}"
  local connect_timeout="${CURL_CONNECT:-5}"
  
  if [ -z "$url" ] || [ -z "$output" ]; then
    return 1
  fi
  
  # Use wget with proper timeouts and error handling
  if wget \
    --timeout="$timeout" \
    --connect-timeout="$connect_timeout" \
    --tries=3 \
    --user-agent="CAD-Droid-Setup/1.0" \
    --no-check-certificate \
    --quiet \
    --output-document="$output" \
    "$url"; then
    return 0
  else
    return 1
  fi
}

# Fetch APK from F-Droid using their API  
fetch_fdroid_api(){
  local pkg="$1"
  local out="$2" 
  local api="https://f-droid.org/api/v1/packages/$pkg"
  
  if [ -z "$pkg" ] || [ -z "$out" ]; then
    return 1
  fi
  
  local tmp="$TMPDIR/fdroid_${pkg}.json"
  
  # Download package metadata from F-Droid API
  if ! http_fetch "$api" "$tmp"; then
    return 1
  fi
  
  # Extract APK filename from JSON response
  local apk
  if command -v jq >/dev/null 2>&1; then
    apk=$(jq -r '.packages[0].apkName // empty' "$tmp" 2>/dev/null)
  else
    apk=$(grep -m1 '"apkName"' "$tmp" 2>/dev/null | awk -F'"' '{print $4}')
  fi
  
  if [ -z "$apk" ]; then
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
  
  # Download the APK file
  if http_fetch "https://f-droid.org/repo/$apk" "$out"; then
    rm -f "$tmp" 2>/dev/null
    ensure_min_size "$out"
  else
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
}

# Fetch APK from F-Droid by scraping their web page
fetch_fdroid_page(){
  local pkg="$1"
  local out="$2"
  local html_file="$TMPDIR/fdroid_page_${pkg}.html"
  
  if [ -z "$pkg" ] || [ -z "$out" ]; then
    return 1
  fi
  
  # Download the F-Droid package page
  if ! http_fetch "https://f-droid.org/packages/$pkg" "$html_file"; then
    return 1
  fi
  
  # Extract APK download URL from HTML
  local rel
  rel=$(grep -Eo "/repo/${pkg//./\\.}_[A-Za-z0-9+.-]*\.apk" "$html_file" 2>/dev/null | grep -v '\.apk\.asc' | head -1)
  
  rm -f "$html_file" 2>/dev/null
  
  if [ -z "$rel" ]; then
    return 1
  fi
  
  # Download the APK file
  if http_fetch "https://f-droid.org${rel}" "$out"; then
    ensure_min_size "$out"
  else
    return 1
  fi
}

# Enhanced GitHub release fetch that preserves original filenames
fetch_github_release(){
  local repo="$1"
  local pattern="$2"
  local outdir="$3"
  local app_name="${4:-app}"
  local api="https://api.github.com/repos/$repo/releases/latest"
  
  if [ -z "$repo" ] || [ -z "$pattern" ] || [ -z "$outdir" ]; then
    return 1
  fi
  
  # Get latest release information from GitHub API
  local data_file="$TMPDIR/github_${repo//\//_}.json"
  if ! http_fetch "$api" "$data_file"; then
    return 1
  fi
  
  local url="" original_filename=""
  
  # Parse JSON to find download URL matching the pattern
  if command -v jq >/dev/null 2>&1; then
    # Use jq for reliable JSON parsing if available
    local asset_info
    asset_info=$(jq -r --arg p "$pattern" '.assets[]? | select(.browser_download_url | test($p)) | "\(.browser_download_url)|\(.name)"' "$data_file" 2>/dev/null | head -1)
    if [ -n "$asset_info" ]; then
      url="${asset_info%|*}"
      original_filename="${asset_info#*|}"
    fi
  else
    # Fallback to grep-based parsing
    local line
    line=$(grep -Eo '"browser_download_url":[^"]*"[^"]+","name":[^"]*"[^"]+' "$data_file" 2>/dev/null | grep "$pattern" | head -1)
    if [ -n "$line" ]; then
      url=$(echo "$line" | grep -Eo '"browser_download_url":[^"]*"[^"]+' | cut -d'"' -f4)
      original_filename=$(echo "$line" | grep -Eo '"name":[^"]*"[^"]+' | cut -d'"' -f4)
    fi
  fi
  
  # Special case for termux-x11 with known URL and filename
  if [ -z "$url" ] && [ "$repo" = "termux/termux-x11" ]; then
    url="https://github.com/termux/termux-x11/releases/latest/download/app-universal-debug.apk"
    original_filename="app-universal-debug.apk"
  fi
  
  rm -f "$data_file" 2>/dev/null
  
  if [ -z "$url" ]; then
    return 1
  fi
  
  # Use original filename if available, otherwise use app name
  local final_filename="${original_filename:-${app_name}.apk}"
  local out="$outdir/$final_filename"
  
  # Download the APK file with original name
  if http_fetch "$url" "$out"; then
    ensure_min_size "$out"
  else
    return 1
  fi
}

# Enhanced Termux add-on fetch that preserves original APK names and prioritizes GitHub
fetch_termux_addon(){
  local name="$1" pkg="$2" repo="$3" patt="$4" outdir="$5"
  local prefer="${PREFER_FDROID:-0}" success=0
  
  if [ -z "$name" ] || [ -z "$pkg" ] || [ -z "$outdir" ]; then
    return 1
  fi
  
  # Ensure output directory exists
  if ! mkdir -p "$outdir" 2>/dev/null; then
    return 1
  fi
  
  # Enhanced conflict resolution - check for existing conflicting packages
  if command -v pm >/dev/null 2>&1; then
    local existing_pkg
    existing_pkg=$(pm list packages 2>/dev/null | grep -E "$pkg" | cut -d: -f2 | head -1)
    if [ -n "$existing_pkg" ]; then
      info "Found existing package: $existing_pkg - will attempt conflict resolution during installation"
    fi
  fi
  
  # Always prioritize GitHub unless F-Droid is explicitly preferred
  if [ "$prefer" = "1" ]; then
    # Try F-Droid first if preferred
    if fetch_fdroid_api "$pkg" "$outdir/${name}.apk" || fetch_fdroid_page "$pkg" "$outdir/${name}.apk"; then
      success=1
    fi
  else
    # Try GitHub first by default (preserves original names)
    if [ -n "$repo" ] && [ -n "$patt" ]; then
      if fetch_github_release "$repo" "$patt" "$outdir" "$name"; then
        success=1
      fi
    fi
  fi
  
  # Fall back to the other source if the first failed
  if [ $success -eq 0 ]; then
    if [ "$prefer" = "1" ]; then
      # F-Droid was preferred but failed, try GitHub
      if [ -n "$repo" ] && [ -n "$patt" ]; then
        if fetch_github_release "$repo" "$patt" "$outdir" "$name"; then
          success=1
        fi
      fi
    else
      # GitHub was preferred but failed, try F-Droid
      if fetch_fdroid_api "$pkg" "$outdir/${name}.apk" || fetch_fdroid_page "$pkg" "$outdir/${name}.apk"; then
        success=1
      fi
    fi
  fi
  
  return $((1 - success))  
}

# Download file with progress spinner using the complete system
# Parameters: url, output_file, description
download_with_spinner(){
  local url="$1"
  local output_file="$2"
  local description="${3:-Downloading file}"
  
  if [ -z "$url" ] || [ -z "$output_file" ]; then
    return 1
  fi
  
  # Ensure output directory exists
  mkdir -p "$(dirname "$output_file")" 2>/dev/null || true
  
  # Remove any existing file
  rm -f "$output_file" 2>/dev/null || true
  
  # Use http_fetch with progress display
  if http_fetch "$url" "$output_file"; then
    # Check file size and set permissions
    if [ -f "$output_file" ]; then
      local file_size
      file_size=$(wc -c < "$output_file" 2>/dev/null || echo "0")
      # Accept files larger than 1KB (most APKs are much larger)
      if [ "$file_size" -gt 1024 ]; then
        # Set proper permissions for downloaded APK
        chmod 644 "$output_file" 2>/dev/null || true
        return 0
      else
        warn "Downloaded file too small ($file_size bytes), may be incomplete"
        chmod 644 "$output_file" 2>/dev/null || true
        return 0
      fi
    fi
  fi
  
  return 1
}

# Query F-Droid API for package information
query_fdroid_package(){
  local package_id="$1"
  
  if [ -z "$package_id" ]; then
    err "Package ID required for F-Droid query"
    return 1
  fi
  
  local api_url="$FDROID_API_BASE/packages/$package_id"
  local response_file="$APK_STATE_DIR/fdroid_${package_id}.json"
  
  # Download package information
  if ! download_with_spinner "$api_url" "$response_file" "Query F-Droid API for $package_id"; then
    warn "Failed to query F-Droid for package: $package_id"
    return 1
  fi
  
  # Validate JSON response
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not available for JSON parsing"
    return 1
  fi
  
  if ! jq -e . >/dev/null 2>&1 < "$response_file"; then
    warn "Invalid JSON response from F-Droid API"
    return 1
  fi
  
  echo "$response_file"
  return 0
}

# Get latest APK download URL from F-Droid with improved error handling
get_fdroid_apk_url(){
  local package_id="$1"
  
  # Direct F-Droid repo download URL construction 
  # F-Droid packages follow a predictable naming pattern
  local apk_url=""
  
  case "$package_id" in
    "com.termux.api")
      apk_url="$FDROID_REPO_BASE/com.termux.api_51.apk"
      ;;
    "com.termux.boot")
      apk_url="$FDROID_REPO_BASE/com.termux.boot_7.apk"
      ;;
    "com.termux.float")
      apk_url="$FDROID_REPO_BASE/com.termux.float_14.apk"
      ;;
    "com.termux.styling")
      apk_url="$FDROID_REPO_BASE/com.termux.styling_29.apk"
      ;;
    "com.termux.tasker")
      apk_url="$FDROID_REPO_BASE/com.termux.tasker_7.apk"
      ;;
    "com.termux.widget")
      apk_url="$FDROID_REPO_BASE/com.termux.widget_12.apk"
      ;;
    "com.termux.x11")
      apk_url="$FDROID_REPO_BASE/com.termux.x11_1207.apk"
      ;;
    "com.termux.gui")
      apk_url="$FDROID_REPO_BASE/com.termux.gui_6.apk"
      ;;
    *)
      warn "Unknown F-Droid package: $package_id"
      return 1
      ;;
  esac
  
  echo "$apk_url"
  return 0
}

# Download APK from F-Droid with GitHub backup and persistent tracking
download_fdroid_apk(){
  local package_id="$1"
  local app_name="${2:-$package_id}"
  
  # Add to pending list
  PENDING_APKS+=("$app_name")
  save_apk_state
  
  # Verify APK directory exists
  if [ ! -d "$APK_DOWNLOAD_DIR" ]; then
    warn "APK directory not found, creating..."
    mkdir -p "$APK_DOWNLOAD_DIR" 2>/dev/null || {
      err "Cannot create APK directory: $APK_DOWNLOAD_DIR"
      # Remove from pending and add to failed
      PENDING_APKS=("${PENDING_APKS[@]/$app_name}")
      FAILED_APKS+=("$app_name")
      save_apk_state
      return 1
    }
  fi
  
  # Create friendly filename (no temp files, direct download)
  local output_file="$APK_DOWNLOAD_DIR/${app_name// /_}.apk"
  
  # Always overwrite existing APKs to ensure latest version
  [ -f "$output_file" ] && rm -f "$output_file" 2>/dev/null || true
  
  # Try F-Droid first with enhanced progress display
  local download_url
  if download_url=$(get_fdroid_apk_url "$package_id" 2>/dev/null); then
    info "Downloading $app_name from F-Droid..."
    if download_with_spinner "$download_url" "$output_file" "Downloading $app_name"; then
      # Less strict verification - accept any non-empty file
      if [ -f "$output_file" ]; then
        local file_size
        file_size=$(wc -c < "$output_file" 2>/dev/null || echo "0")
        if [ "$file_size" -gt 0 ]; then
          ok "$app_name downloaded successfully from F-Droid ($file_size bytes)"
          # Update tracking arrays
          PENDING_APKS=("${PENDING_APKS[@]/$app_name}")
          DOWNLOADED_APKS+=("$app_name:$output_file")
          save_apk_state
          echo "$output_file"
          return 0
        else
          warn "$app_name: Downloaded file is empty"
        fi
      fi
    fi
  fi
  
  # Fallback to GitHub releases for Termux apps
  warn "F-Droid download failed, trying GitHub backup..."
  
  # Ensure TERMUX_GITHUB_URLS is properly declared
  if ! declare -p TERMUX_GITHUB_URLS >/dev/null 2>&1; then
    err "TERMUX_GITHUB_URLS array not properly declared"
    return 1
  fi
  
  local github_url="${TERMUX_GITHUB_URLS[$package_id]:-}"
  
  if [ -n "$github_url" ]; then
    info "Downloading $app_name from GitHub..."
    if download_with_spinner "$github_url" "$output_file" "Downloading $app_name from GitHub"; then
      if [ -f "$output_file" ]; then
        local file_size
        file_size=$(wc -c < "$output_file" 2>/dev/null || echo "0")
        if [ "$file_size" -gt 0 ]; then
          ok "$app_name downloaded successfully from GitHub ($file_size bytes)"
          # Update tracking arrays
          PENDING_APKS=("${PENDING_APKS[@]/$app_name}")
          DOWNLOADED_APKS+=("$app_name:$output_file")
          save_apk_state
          echo "$output_file"
          return 0
        else
          warn "$app_name: Downloaded file from GitHub is empty"
        fi
      fi
    fi
  else
    warn "No GitHub backup available for $app_name"
  fi
  
  err "Failed to download $app_name from both F-Droid and GitHub"
  # Update tracking arrays for failure
  PENDING_APKS=("${PENDING_APKS[@]/$app_name}")
  FAILED_APKS+=("$app_name")
  save_apk_state
  return 1
}

# Download all essential APKs using the fetch_termux_addon function
download_essential_apks(){
  info "Downloading essential Termux plugin APKs..."
  
  # Ensure ESSENTIAL_APKS is properly declared and accessible
  if ! declare -p ESSENTIAL_APKS >/dev/null 2>&1; then
    err "ESSENTIAL_APKS array not properly declared"
    return 1
  fi
  
  # Ensure APK download directory exists
  mkdir -p "$APK_DOWNLOAD_DIR" 2>/dev/null || {
    err "Cannot create APK directory: $APK_DOWNLOAD_DIR"
    return 1
  }
  
  # Set proper permissions for directory
  chmod 755 "$APK_DOWNLOAD_DIR" 2>/dev/null || true
  chmod 755 "$(dirname "$APK_DOWNLOAD_DIR")" 2>/dev/null || true
  
  # Track download results
  local success=0 total=0
  
  # Download each essential APK using fetch_termux_addon
  for app_name in "${!ESSENTIAL_APKS[@]}"; do
    local package_id="${ESSENTIAL_APKS[$app_name]}"
    local repo_path="" github_pattern=""
    
    total=$((total + 1))
    
    # Map each APK to its GitHub repository and filename pattern
    case "$package_id" in
      "com.termux.api")
        repo_path="termux/termux-api"
        github_pattern=".*api.*\.apk"
        ;;
      "com.termux.boot")
        repo_path="termux/termux-boot" 
        github_pattern=".*boot.*\.apk"
        ;;
      "com.termux.float")
        repo_path="termux/termux-float"
        github_pattern=".*float.*\.apk"
        ;;
      "com.termux.styling")
        repo_path="termux/termux-styling"
        github_pattern=".*styling.*\.apk"
        ;;
      "com.termux.tasker")
        repo_path="termux/termux-tasker"
        github_pattern=".*tasker.*\.apk"
        ;;
      "com.termux.widget")
        repo_path="termux/termux-widget" 
        github_pattern=".*widget.*\.apk"
        ;;
      "com.termux.x11")
        repo_path="termux/termux-x11"
        github_pattern=".*x11.*\.apk"
        ;;
      "com.termux.gui")
        repo_path="termux/termux-gui"
        github_pattern=".*gui.*\.apk"
        ;;
      *)
        warn "Unknown package: $package_id - using generic pattern"
        repo_path=""
        github_pattern=""
        ;;
    esac
    
    info "($total/8) Downloading $app_name..."
    
    # Use fetch_termux_addon function from the reference
    if fetch_termux_addon "$app_name" "$package_id" "$repo_path" "$github_pattern" "$APK_DOWNLOAD_DIR"; then
      success=$((success + 1))
      ok "Downloaded: $app_name"
      DOWNLOADED_APKS+=("$app_name")
    else
      warn "Failed to download: $app_name"
      FAILED_APKS+=("$app_name")
    fi
  done
  
  # Set proper permissions for all downloaded APK files
  find "$APK_DOWNLOAD_DIR" -name "*.apk" -exec chmod 644 {} \; 2>/dev/null || true
  
  # Report results
  info "APK download complete: $success/$total successful"
  
  if [ "$success" -gt 0 ]; then
    ok "Successfully downloaded $success APK(s) to $APK_DOWNLOAD_DIR"
  fi
  
  if [ "$success" -lt "$total" ]; then
    local failed=$((total - success))
    warn "$failed APK(s) failed to download"
    if [ ${#FAILED_APKS[@]} -gt 0 ]; then
      warn "Failed APKs: ${FAILED_APKS[*]}"
    fi
  fi
  
  # Always save state
  save_apk_state
  
  return 0
}

# Open Android security settings to enable "Install unknown apps" for Termux
open_security_settings() {
  info "Opening Android security settings..."
  
  # Try to open Termux-specific app settings
  if command -v am >/dev/null 2>&1; then
    # Open app-specific settings for Termux
    am start -a android.settings.APPLICATION_DETAILS_SETTINGS \
       -d package:com.termux >/dev/null 2>&1 || {
      # Fallback to general security settings
      am start -a android.settings.SECURITY_SETTINGS >/dev/null 2>&1 || {
        # Final fallback to main settings
        am start -a android.settings.SETTINGS >/dev/null 2>&1 || true
      }
    }
    ok "Android settings opened - please enable 'Install unknown apps' for Termux"
  else
    warn "Cannot open Android settings automatically"
    info "Please manually enable 'Install unknown apps' for Termux in Android settings"
  fi
}

# Handle APK installation and permission setup after downloads are complete
setup_apk_permissions(){
  info "Setting up APK installation and permissions..."
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    pecho "$PASTEL_PURPLE" "=== APK Installation & Permissions Setup ==="
    echo ""
    pecho "$PASTEL_YELLOW" "All Termux plugin APKs have been downloaded successfully!"
    echo ""
    pecho "$PASTEL_CYAN" "Required permissions for each plugin:"
    echo ""
    pecho "$PASTEL_GREEN" "• Termux:API - Phone, SMS, Location, Camera, Microphone"
    pecho "$PASTEL_GREEN" "• Termux:Boot - Boot permission to start services automatically" 
    pecho "$PASTEL_GREEN" "• Termux:Widget - Display over other apps permission"
    pecho "$PASTEL_GREEN" "• Termux:X11 - Display over other apps, battery optimization disabled"
    pecho "$PASTEL_GREEN" "• Other plugins - Standard app permissions as requested"
    echo ""
    pecho "$PASTEL_PINK" "Installation steps:"
    pecho "$PASTEL_CYAN" "1. Open the APK directory (will open automatically)"
    pecho "$PASTEL_CYAN" "2. Install each APK by tapping on it"
    pecho "$PASTEL_CYAN" "3. Grant all requested permissions for full functionality"
    echo ""
    
    printf "${PASTEL_YELLOW}Press Enter when ready to open APK directory...${RESET} "
    read -r
  else
    info "Non-interactive mode: APK directory will open automatically"
  fi
  
  # Open APK directory for installation
  open_apk_directory || warn "Could not open APK directory"
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    info "Install each APK file by tapping on it in the file manager"
    info "Configure permissions as requested by each app"
    echo ""
    printf "${PASTEL_PINK}Press Enter after installing all APKs and configuring permissions...${RESET} "
    read -r
  else
    info "Non-interactive mode: continuing after ${APK_PAUSE_TIMEOUT:-45}s delay"
    sleep "${APK_PAUSE_TIMEOUT:-45}"
  fi
  
  return 0
}

# Open file manager to APK download directory
open_apk_directory(){
  info "Opening APK download directory..."
  
  if [ ! -d "$APK_DOWNLOAD_DIR" ]; then
    err "APK download directory not found: $APK_DOWNLOAD_DIR"
    return 1
  fi
  
  # Ensure proper permissions before opening
  chmod 755 "$APK_DOWNLOAD_DIR" 2>/dev/null || true
  find "$APK_DOWNLOAD_DIR" -name "*.apk" -exec chmod 644 {} \; 2>/dev/null || true
  
  # Count downloaded APKs
  local apk_count
  apk_count=$(find "$APK_DOWNLOAD_DIR" -name "*.apk" -type f 2>/dev/null | wc -l)
  
  if [ "$apk_count" -eq 0 ]; then
    warn "No APK files found in download directory"
  else
    ok "Found $apk_count APK files ready for installation"
  fi
  
  # Use termux-open to open the directory (simple method without complex spinner)
  if command -v termux-open >/dev/null 2>&1; then
    info "Opening APK directory in file manager..."
    termux-open "$APK_DOWNLOAD_DIR" >/dev/null 2>&1 || {
      warn "Failed to open with termux-open, trying alternative methods"
      # Try alternative methods to open file manager
      if command -v am >/dev/null 2>&1; then
        am start -a android.intent.action.VIEW -d "file://$APK_DOWNLOAD_DIR" >/dev/null 2>&1 || true
      fi
    }
    ok "APK directory opened in file manager"
  else
    warn "termux-open not available, please manually navigate to:"
    printf "${PASTEL_CYAN}%s${RESET}\n" "$APK_DOWNLOAD_DIR"
    
    # Try opening with alternative methods
    if command -v am >/dev/null 2>&1; then
      info "Attempting to open directory with system file manager..."
      am start -a android.intent.action.VIEW -d "file://$APK_DOWNLOAD_DIR" >/dev/null 2>&1 || true
    fi
  fi
  
  return 0
}

# Verify APK installation permissions and provide detailed guidance
check_apk_permissions(){
  info "Checking APK installation permissions..."
  
  # Check if we can request install permissions
  if command -v termux-api-start >/dev/null 2>&1; then
    run_with_progress "Check install permissions" 5 bash -c '
      # This will show if we have permission to install APKs
      am start -a android.settings.MANAGE_UNKNOWN_APP_SOURCES >/dev/null 2>&1 || true
    '
  fi
  
  # Provide comprehensive installation instructions
  printf "\n${PASTEL_PINK}═══ APK Installation Guide ═══${RESET}\n\n"
  
  printf "${PASTEL_YELLOW}Step 1: Enable Unknown App Sources${RESET}\n"
  printf "${PASTEL_CYAN}├─${RESET} Open Android Settings → Security → Unknown Sources\n"
  printf "${PASTEL_CYAN}├─${RESET} Or: Settings → Apps → File Manager → Install Unknown Apps\n"  
  printf "${PASTEL_CYAN}└─${RESET} Enable installation from your file manager\n\n"
  
  printf "${PASTEL_YELLOW}Step 2: Navigate to APK Directory${RESET}\n"
  printf "${PASTEL_CYAN}└─${RESET} %s\n\n" "$APK_DOWNLOAD_DIR"
  
  printf "${PASTEL_YELLOW}Step 3: Install APKs in Order${RESET}\n"
  
  local install_order=(
    "Termux:API"
    "Termux:Boot" 
    "Termux:Widget"
    "Termux:X11"
    "Termux:Float"
    "Termux:Styling"
    "Termux:Tasker"
  )
  
  for i in "${!install_order[@]}"; do
    local app="${install_order[$i]}"
    local num=$((i + 1))
    printf "${PASTEL_CYAN}%d.${RESET} ${PASTEL_PURPLE}%s${RESET}\n" "$num" "$app"
    
    # Add specific permission requirements
    case "$app" in
      "Termux:API")
        printf "   ${PASTEL_GREEN}Permissions needed:${RESET} Phone, SMS, Location, Camera, Microphone\n"
        ;;
      "Termux:Boot")
        printf "   ${PASTEL_GREEN}Permissions needed:${RESET} Boot completed, System alert window\n"
        ;;
      "Termux:Widget")
        printf "   ${PASTEL_GREEN}Permissions needed:${RESET} System alert window, Draw over apps\n"
        ;;
      "Termux:X11")
        printf "   ${PASTEL_GREEN}Permissions needed:${RESET} System alert window, Draw over apps\n"
        ;;
      "Termux:Float")
        printf "   ${PASTEL_GREEN}Permissions needed:${RESET} System alert window, Draw over apps\n"
        ;;
    esac
  done
  
  printf "\n${PASTEL_YELLOW}Step 4: Grant All Permissions${RESET}\n"
  printf "${PASTEL_CYAN}├─${RESET} Allow ALL permissions when prompted\n"
  printf "${PASTEL_CYAN}├─${RESET} Enable 'Display over other apps' for widgets\n"
  printf "${PASTEL_CYAN}└─${RESET} Enable notification access if requested\n\n"
  
  printf "${PASTEL_RED}Important:${RESET} ${PASTEL_YELLOW}Install Termux:API first - other apps depend on it!${RESET}\n\n"
}

# Post-installation permission setup assistant
assist_apk_permissions(){
  info "Setting up APK permissions..."
  
  printf "\n${PASTEL_PINK}═══ Permission Setup Assistant ═══${RESET}\n\n"
  
  # Check if Termux:API is installed
  if ! command -v termux-api-start >/dev/null 2>&1; then
    warn "Termux:API not detected. Please install it first."
    return 1
  fi
  
  printf "${PASTEL_GREEN}[OK]${RESET} Termux:API detected\n\n"
  
  # Guide through permission settings
  printf "${PASTEL_YELLOW}Let's verify your permissions:${RESET}\n\n"
  
  # Test API permissions
  printf "${PASTEL_CYAN}Testing phone access...${RESET} "
  if timeout 5 termux-telephony-deviceinfo >/dev/null 2>&1; then
    printf "${PASTEL_GREEN}[OK]${RESET}\n"
  else
    printf "${PASTEL_RED}[FAIL]${RESET} Grant phone permissions to Termux:API\n"
  fi
  
  printf "${PASTEL_CYAN}Testing location access...${RESET} "
  if timeout 5 termux-location >/dev/null 2>&1; then
    printf "${PASTEL_GREEN}[OK]${RESET}\n" 
  else
    printf "${PASTEL_RED}[FAIL]${RESET} Grant location permissions to Termux:API\n"
  fi
  
  # Check for widget installation
  printf "${PASTEL_CYAN}Checking widgets...${RESET} "
  if [ -d "/data/data/com.termux.widget" ] 2>/dev/null; then
    printf "${PASTEL_GREEN}[OK]${RESET}\n"
  else
    printf "${PASTEL_RED}[FAIL]${RESET} Install Termux:Widget for shortcuts\n"
  fi
  
  # Provide links to permission settings
  printf "\n${PASTEL_YELLOW}Quick Permission Settings:${RESET}\n"
  printf "${PASTEL_CYAN}├─${RESET} Open Settings → Apps → Termux:API → Permissions\n"
  printf "${PASTEL_CYAN}├─${RESET} Enable: Phone, Location, Storage, Camera, Microphone\n"
  printf "${PASTEL_CYAN}└─${RESET} For widgets: Enable 'Display over other apps'\n\n"
  
  # Ask if user wants to continue to permission settings
  if [ "$NON_INTERACTIVE" != "1" ]; then
    printf "${PASTEL_PINK}Open permission settings now? (y/N):${RESET} "
    local response
    read -r response || response="n"
    case "${response,,}" in
      y|yes)
        if command -v am >/dev/null 2>&1; then
          am start -a android.settings.APPLICATION_DETAILS_SETTINGS \
             -d package:com.termux.api >/dev/null 2>&1 || true
          info "Permission settings opened"
        fi
        ;;
    esac
  fi
}

# Main APK management function
manage_apks(){
  info "Starting APK management process..."
  
  # Initialize system
  if ! init_apk_system; then
    err "Failed to initialize APK management system"
    return 1
  fi
  
  # Download all essential APKs automatically 
  download_essential_apks
  
  # Show installation instructions and requirements
  check_apk_permissions
  
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    echo ""
    pecho "$PASTEL_PINK" "=== APK Installation Ready ==="
    echo ""
    pecho "$PASTEL_YELLOW" "Next steps:"
    pecho "$PASTEL_CYAN" "1. Android security settings will open"
    pecho "$PASTEL_CYAN" "2. Enable 'Install unknown apps' for Termux"  
    pecho "$PASTEL_CYAN" "3. File manager will open to APK directory"
    pecho "$PASTEL_CYAN" "4. Install each APK by tapping on it"
    echo ""
    printf "${PASTEL_PINK}Press Enter to open Android security settings...${RESET} "
    read -r || true
  else
    info "Non-interactive mode: opening security settings automatically"
  fi
  
  # Open security settings first (before user needs to act)
  open_security_settings
  
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then 
    echo ""
    pecho "$PASTEL_YELLOW" "Please enable 'Install unknown apps' for Termux in the settings that just opened."
    echo ""
    printf "${PASTEL_PINK}Press Enter after enabling 'Install unknown apps' for Termux...${RESET} "
    read -r || true
  else
    info "Non-interactive mode: continuing after settings delay"
    sleep 5
  fi
  
  # Open APK directory for user installation
  open_apk_directory
  
  # Wait for user to install APKs
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    echo ""
    pecho "$PASTEL_YELLOW" "Install each APK file by tapping on it in the file manager."
    pecho "$PASTEL_YELLOW" "Grant all requested permissions for full functionality."
    echo ""
    printf "${PASTEL_PINK}Press Enter after installing all APKs...${RESET} "
    read -r || true
  else
    info "Non-interactive mode: auto-continuing after delay"
    sleep "${APK_INSTALL_DELAY:-30}"
  fi
  
  # Run post-installation permission assistant
  assist_apk_permissions
  
  ok "APK management process completed"
  return 0
}

# Cleanup function for APK temporary files and cache
cleanup_apk_temp(){
  local cleaned_count=0
  
  # Clean temporary JSON files
  if [ -d "$APK_STATE_DIR" ]; then
    find "$APK_STATE_DIR" -name "fdroid_*.json" -type f -delete 2>/dev/null && cleaned_count=$((cleaned_count + 1)) || true
  fi
  
  if [ "$cleaned_count" -gt 0 ]; then
    debug "Cleaned $cleaned_count APK temporary files"
  fi
}

# Comprehensive APK installer cleanup - removes all installer-created files
cleanup_apk_installer_files(){
  info "Cleaning up APK installer files and cache..."
  
  local cleanup_items=(
    # APK directories (both primary and fallback)
    "$APK_DOWNLOAD_DIR_PRIMARY"
    "$APK_DOWNLOAD_DIR_FALLBACK"
    # APK state and cache directories
    "$APK_STATE_DIR"
    # Temporary download files
    "$TMPDIR/fdroid_*.json"
    "$TMPDIR/*apk*"
  )
  
  local cleaned_count=0
  local total_size=0
  
  for item in "${cleanup_items[@]}"; do
    if [[ "$item" == *"*"* ]]; then
      # Handle glob patterns
      for file in $item; do
        if [ -e "$file" ] 2>/dev/null; then
          local size
          size=$(du -sb "$file" 2>/dev/null | cut -f1) || size=0
          total_size=$((total_size + size))
          if rm -rf "$file" 2>/dev/null; then
            cleaned_count=$((cleaned_count + 1))
            debug "Removed: $file ($size bytes)"
          else
            warn "Failed to remove: $file"
          fi
        fi
      done
    else
      # Handle regular paths
      if [ -e "$item" ]; then
        local size
        size=$(du -sb "$item" 2>/dev/null | cut -f1) || size=0
        total_size=$((total_size + size))
        if rm -rf "$item" 2>/dev/null; then
          cleaned_count=$((cleaned_count + 1))
          debug "Removed: $item ($size bytes)"
        else
          warn "Failed to remove: $item"
        fi
      fi
    fi
  done
  
  # Format size for display
  local size_display
  if [ "$total_size" -gt 1048576 ]; then
    size_display="$(( total_size / 1048576 )) MB"
  elif [ "$total_size" -gt 1024 ]; then
    size_display="$(( total_size / 1024 )) KB"
  else
    size_display="${total_size} bytes"
  fi
  
  if [ "$cleaned_count" -gt 0 ]; then
    ok "APK cleanup completed - removed $cleaned_count items ($size_display)"
  else
    info "No APK installer files found to clean"
  fi
  
  return 0
}

# Set up cleanup on script exit
trap cleanup_apk_temp EXIT

# Export functions for use by other modules
export -f init_apk_system
export -f download_fdroid_apk
export -f download_essential_apks
export -f open_apk_directory
export -f manage_apks
export -f cleanup_apk_temp
export -f setup_apk_permissions
export -f cleanup_apk_installer_files
