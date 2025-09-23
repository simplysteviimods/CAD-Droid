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

# Global APK download directory (set during initialization)
APK_DOWNLOAD_DIR=""

# Minimum APK size check (12KB)
readonly MIN_APK_SIZE=12288

# === Core Download Functions (Based on Working Reference) ===

# Wrapper for wget with consistent timeout settings
wget_get(){
  if ! command -v wget >/dev/null 2>&1; then
    return 1
  fi
  
  wget -q --timeout="${CURL_MAX_TIME:-40}" --tries=2 "$@"
}

# Simple HTTP fetch using wget only (based on working reference)
http_fetch(){
  local url="$1" output="$2"
  
  if [ -z "$url" ] || [ -z "$output" ]; then
    return 1
  fi
  
  # Ensure output directory exists
  mkdir -p "$(dirname "$output")" 2>/dev/null || true
  
  # Try wget only for APK downloads (no curl fallback due to 404 errors)
  if wget_get -O "$output" "$url"; then
    return 0
  else
    return 1
  fi
}

# Ensure minimum file size for APK validation
ensure_min_size(){
  local f="$1"
  local min_size="${MIN_APK_SIZE:-12288}"  # 12KB minimum
  
  if [ ! -f "$f" ]; then
    return 1
  fi
  
  local sz
  sz=$(wc -c < "$f" 2>/dev/null || echo "0")
  
  if [ "$sz" -lt "$min_size" ]; then
    warn "File too small: $(basename "$f") ($sz bytes, minimum $min_size)"
    rm -f "$f" 2>/dev/null || true
    return 1
  fi
  
  return 0
}

# Fetch APK from F-Droid using their API
fetch_fdroid_api(){
  local pkg="$1"
  local out="$2" 
  local api="https://f-droid.org/api/v1/packages/$pkg"
  
  if [ -z "$pkg" ] || [ -z "$out" ]; then
    return 1
  fi
  
  local tmp="${TMPDIR:-/tmp}/fdroid_${pkg}.json"
  
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
  local html_file="${TMPDIR:-/tmp}/fdroid_page_${pkg}.html"
  
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
  if http_fetch "https://f-droid.org$rel" "$out"; then
    ensure_min_size "$out"
  else
    return 1
  fi
}

# Fetch APK from GitHub releases
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
  local data_file="${TMPDIR:-/tmp}/github_${repo//\//_}.json"
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

# Enhanced Termux add-on fetch (based on working reference)
fetch_termux_addon(){
  local name="$1" pkg="$2" repo="$3" patt="$4" outdir="$5"
  local prefer="${PREFER_FDROID:-0}" success=0
  
  if [ -z "$name" ] || [ -z "$pkg" ] || [ -z "$outdir" ]; then
    return 1
  fi
  
  # Ensure output directory exists with proper permissions
  if ! mkdir -p "$outdir" 2>/dev/null; then
    return 1
  fi
  
  # Set proper permissions for the directory and parent directories
  chmod 755 "$outdir" 2>/dev/null || true
  chmod 755 "$(dirname "$outdir")" 2>/dev/null || true
  
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
  
  # Ensure downloaded APK has proper permissions
  if [ $success -eq 1 ]; then
    find "$outdir" -name "*.apk" -newer /tmp -exec chmod 644 {} \; 2>/dev/null || true
  fi
  
  return $((1 - success))
}

# === Directory Management (Simplified) ===

# Select APK directory (based on working reference)
select_apk_directory(){
  # Set default location first
  local default_location="/storage/emulated/0/Download/CAD-Droid-APKs"
  APK_DOWNLOAD_DIR="$default_location"
  
  info "APK File Location Setup"
  echo ""
  info "Default location: $default_location"
  echo ""
  
  # Ask user if they want to use default location
  if [ "$NON_INTERACTIVE" != "1" ]; then
    if ask_yes_no "Use default location?" "y"; then
      info "Using default location: $APK_DOWNLOAD_DIR"
      mkdir -p "$APK_DOWNLOAD_DIR" 2>/dev/null || true
      return 0
    fi
  fi
  
  # Try to create the directory
  if ! mkdir -p "$APK_DOWNLOAD_DIR" 2>/dev/null; then
    # Fallback to internal storage
    APK_DOWNLOAD_DIR="$APK_DOWNLOAD_DIR_FALLBACK"
    warn "Using fallback location: $APK_DOWNLOAD_DIR"
    mkdir -p "$APK_DOWNLOAD_DIR" 2>/dev/null || {
      err "Cannot create APK directory"
      return 1
    }
  fi
  
  # Set proper permissions
  chmod 755 "$APK_DOWNLOAD_DIR" 2>/dev/null || true
  chmod 755 "$(dirname "$APK_DOWNLOAD_DIR")" 2>/dev/null || true
  
  return 0
}

# === Main APK Step Function (Enhanced) ===

# Main APK management step (based on working reference)
step_apk(){
  info "Installing required Termux add-on APKs..."
  
  # Check if APK installation is enabled
  if [ "${ENABLE_APK_AUTO:-1}" != "1" ]; then
    info "APK installation disabled - skipping"
    mark_step_status "skipped"
    return 0
  fi
  
  # Let user select APK directory
  if ! select_apk_directory; then
    warn "APK directory setup failed"
    mark_step_status "warning"  
    return 0
  fi
  
  local failed=0
  
  # Install Termux:API (required for GitHub setup and other features)
  if download_apk_with_spinner "Termux:API" "com.termux.api" "termux/termux-api" ".*api.*\.apk" "$APK_DOWNLOAD_DIR"; then
    ok "Termux:API downloaded successfully"
  else
    failed=$((failed + 1))
    warn "Failed to download Termux:API"
  fi
  
  # Install Termux:X11 (required for GUI apps)
  if download_apk_with_spinner "Termux:X11" "com.termux.x11" "termux/termux-x11" ".*x11.*\.apk" "$APK_DOWNLOAD_DIR"; then
    ok "Termux:X11 downloaded successfully"
  else
    failed=$((failed + 1))
    warn "Failed to download Termux:X11"
  fi
  
  # Install Termux:GUI (additional GUI support)
  if download_apk_with_spinner "Termux:GUI" "com.termux.gui" "termux/termux-gui" ".*gui.*\.apk" "$APK_DOWNLOAD_DIR"; then
    ok "Termux:GUI downloaded successfully"
  else
    failed=$((failed + 1))
    warn "Failed to download Termux:GUI"
  fi
  
  # Install Termux:Float (floating window support)
  if download_apk_with_spinner "Termux:Float" "com.termux.float" "termux/termux-float" ".*float.*\.apk" "$APK_DOWNLOAD_DIR"; then
    ok "Termux:Float downloaded successfully"
  else
    failed=$((failed + 1))
    warn "Failed to download Termux:Float"
  fi
  
  # Show results
  if [ "$failed" -eq 0 ]; then
    ok "All APKs downloaded successfully to: $APK_DOWNLOAD_DIR"
    mark_step_status "success"
  else
    warn "$failed APK(s) failed to download"
    mark_step_status "warning"
  fi
  
  # Enhanced installation instructions and file manager opening
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    echo ""
    pecho "$PASTEL_PINK" "=== APK Installation Guide ==="
    echo ""
    pecho "$PASTEL_YELLOW" "What you need to do:"
    pecho "$PASTEL_CYAN" "+= Open Android Settings → Security → Unknown Sources"
    pecho "$PASTEL_CYAN" "+= Or: Settings → Apps → File Manager → Install Unknown Apps"  
    pecho "$PASTEL_CYAN" "+= Enable installation from your file manager"
    echo ""
    pecho "$PASTEL_YELLOW" "APKs are located at:"
    pecho "$PASTEL_CYAN" "+= $APK_DOWNLOAD_DIR"
    echo ""
    pecho "$PASTEL_YELLOW" "Installation steps:"
    pecho "$PASTEL_CYAN" "+= Allow ALL permissions when prompted"
    pecho "$PASTEL_CYAN" "+= Enable 'Display over other apps' for widgets"
    pecho "$PASTEL_CYAN" "+= Enable notification access if requested"
    echo ""
    pecho "$PASTEL_YELLOW" "Press Enter to open file manager..."
    read -r || true
    
    # Open file manager with enhanced logic
    open_apk_directory
  else
    info "Non-interactive mode: APK directory will open automatically"
    # Try to open file manager even in non-interactive mode
    open_apk_directory >/dev/null 2>&1 || true
  fi
  
  return 0
}

# Download APK with spinner animation
download_apk_with_spinner(){
  local name="$1" pkg="$2" repo="$3" patt="$4" outdir="$5"
  
  if [ -z "$name" ] || [ -z "$pkg" ] || [ -z "$outdir" ]; then
    return 1
  fi
  
  # Show spinner while downloading
  printf "Downloading %s... " "$name"
  
  # Start download in background
  fetch_termux_addon "$name" "$pkg" "$repo" "$patt" "$outdir" &
  local pid=$!
  
  # Simple spinner animation
  local frame=0
  local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  
  while kill -0 "$pid" 2>/dev/null; do
    local char_index=$((frame % 10))
    local spinner_char="${spinner_chars:$char_index:1}"
    printf "\r\033[38;2;175;238;238m%s\033[0m Downloading %s..." "$spinner_char" "$name"
    frame=$((frame + 1))
    sleep 0.1
  done
  
  # Wait for download to complete and get result
  wait "$pid"
  local result=$?
  
  # Clear spinner line
  printf "\r\033[2K"
  
  return $result
}

# Open file manager to APK download directory (enhanced)
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
  
  # Try multiple methods to open file manager
  local opened=0
  
  # Method 1: Use recommended Android intent for external storage (primary method)
  if [ $opened -eq 0 ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "content://com.android.externalstorage.documents/root/primary" >/dev/null 2>&1; then
      opened=1
      ok "File manager opened to external storage"
    fi
  fi
  
  # Method 2: Direct file manager intent with directory
  if [ $opened -eq 0 ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "file://$APK_DOWNLOAD_DIR" >/dev/null 2>&1; then
      opened=1
      ok "APK directory opened in file manager"
    fi
  fi
  
  # Method 3: Use content provider for specific CAD-Droid directory
  if [ $opened -eq 0 ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "content://com.android.externalstorage.documents/root/primary/Download/CAD-Droid-APKs" >/dev/null 2>&1; then
      opened=1
      ok "APK directory opened via content provider"
    fi
  fi
  
  # Method 4: Fallback to termux-open
  if [ $opened -eq 0 ] && command -v termux-open >/dev/null 2>&1; then
    if termux-open "$APK_DOWNLOAD_DIR" >/dev/null 2>&1; then
      opened=1
      ok "APK directory opened with termux-open"
    fi
  fi
  
  # Method 4: Last resort - general Downloads folder
  if [ $opened -eq 0 ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "content://com.android.externalstorage.documents/root/primary/Download" >/dev/null 2>&1; then
      opened=1
      info "Downloads folder opened - navigate to CAD-Droid-APKs"
    fi
  fi
  
  if [ $opened -eq 0 ]; then
    warn "Could not open file manager automatically"
    info "Please manually open: $APK_DOWNLOAD_DIR"
  fi
  
  # If interactive, wait for user to complete installation
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    echo ""
    info "Install each APK file by tapping on it in the file manager"
    info "Configure permissions as requested by each app"
    echo ""
    printf "${PASTEL_PINK}Press Enter after installing all APKs and configuring permissions...${RESET} "
    read -r || true
  else
    info "Non-interactive mode: continuing after ${APK_PAUSE_TIMEOUT:-45}s delay"
    sleep "${APK_PAUSE_TIMEOUT:-45}"
  fi
  
  return 0
}

# Export functions for use in other modules
export -f step_apk fetch_termux_addon http_fetch wget_get download_apk_with_spinner open_apk_directory
