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

# APK download tracking arrays - persistent across sessions
declare -a DOWNLOADED_APKS=()
declare -a FAILED_APKS=()
declare -a PENDING_APKS=()

# F-Droid API configuration
readonly FDROID_API_BASE="https://f-droid.org/api/v1"
readonly FDROID_REPO_BASE="https://f-droid.org/repo"

# Essential APKs from F-Droid with their package IDs - Only Termux plugins
declare -A ESSENTIAL_APKS=(
  ["Termux:API"]="com.termux.api"
  ["Termux:Boot"]="com.termux.boot"
  ["Termux:Float"]="com.termux.float"
  ["Termux:Styling"]="com.termux.styling"
  ["Termux:Tasker"]="com.termux.tasker"
  ["Termux:Widget"]="com.termux.widget"
  ["Termux:X11"]="com.termux.x11"
  ["Termux:GUI"]="com.termux.gui"
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
      run_with_progress "Request storage access" 8 termux-setup-storage
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
    info "Using external storage for APKs: $selected_dir"
  else
    # Fallback to internal storage
    if mkdir -p "$APK_DOWNLOAD_DIR_FALLBACK" 2>/dev/null; then
      selected_dir="$APK_DOWNLOAD_DIR_FALLBACK"
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
  if ! download_with_spinner "$api_url" "$response_file" "Query F-Droid API"; then
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

# Get latest APK download URL from F-Droid
get_fdroid_apk_url(){
  local package_id="$1"
  local package_info_file
  
  if ! package_info_file=$(query_fdroid_package "$package_id"); then
    return 1
  fi
  
  # Extract latest version APK filename
  local apk_filename
  apk_filename=$(jq -r '.packages[0].apkName // empty' "$package_info_file" 2>/dev/null || echo "")
  
  if [ -z "$apk_filename" ]; then
    warn "No APK filename found for $package_id"
    return 1
  fi
  
  # Construct download URL
  local download_url="$FDROID_REPO_BASE/$apk_filename"
  echo "$download_url"
  return 0
}

# Download APK from F-Droid with GitHub backup and persistent tracking
download_fdroid_apk(){
  local package_id="$1"
  local app_name="${2:-$package_id}"
  
  info "Downloading $app_name..."
  
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
  
  # Try F-Droid first
  local download_url
  if download_url=$(get_fdroid_apk_url "$package_id" 2>/dev/null); then
    if download_with_spinner "$download_url" "$output_file" "Download $app_name (F-Droid)"; then
      # Verify download
      if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        ok "$app_name downloaded successfully from F-Droid"
        # Update tracking arrays
        PENDING_APKS=("${PENDING_APKS[@]/$app_name}")
        DOWNLOADED_APKS+=("$app_name:$output_file")
        save_apk_state
        echo "$output_file"
        return 0
      fi
    fi
  fi
  
  # Fallback to GitHub releases for Termux apps
  warn "F-Droid download failed, trying GitHub backup..."
  local github_url=""
  case "$package_id" in
    "com.termux")
      github_url="https://github.com/termux/termux-app/releases/latest/download/termux-app_universal.apk"
      ;;
    "com.termux.api")
      github_url="https://github.com/termux/termux-api/releases/latest/download/termux-api.apk"
      ;;
    "com.termux.boot")
      github_url="https://github.com/termux/termux-boot/releases/latest/download/termux-boot.apk"
      ;;
    "com.termux.widget")
      github_url="https://github.com/termux/termux-widget/releases/latest/download/termux-widget.apk"
      ;;
    "com.termux.x11")
      github_url="https://github.com/termux/termux-x11/releases/latest/download/termux-x11-universal-1.02.07-0-all.apk"
      ;;
    "com.termux.gui")
      github_url="https://github.com/termux/termux-gui/releases/latest/download/termux-gui.apk"
      ;;
    # Non-Termux APKs don't have GitHub fallbacks, rely on F-Droid
    *)
      err "No GitHub backup available for $app_name (F-Droid only)"
      return 1
      ;;
  esac
  
  if [ -n "$github_url" ]; then
    if download_with_spinner "$github_url" "$output_file" "Download $app_name (GitHub)"; then
      if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        ok "$app_name downloaded successfully from GitHub"
        # Update tracking arrays
        PENDING_APKS=("${PENDING_APKS[@]/$app_name}")
        DOWNLOADED_APKS+=("$app_name:$output_file")
        save_apk_state
        echo "$output_file"
        return 0
      fi
    fi
  fi
  
  err "Failed to download $app_name from both F-Droid and GitHub"
  # Update tracking arrays for failure
  PENDING_APKS=("${PENDING_APKS[@]/$app_name}")
  FAILED_APKS+=("$app_name")
  save_apk_state
  return 1
}

# Download all essential APKs after user confirms permissions
download_essential_apks(){
  info "Preparing to download essential Termux plugin APKs..."
  
  # Show permission prompt before downloading
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    pecho "$PASTEL_PURPLE" "=== Termux Plugin Permissions Required ==="
    echo ""
    pecho "$PASTEL_YELLOW" "The following Termux plugins will be downloaded and require specific permissions:"
    echo ""
    pecho "$PASTEL_CYAN" "• Termux:API - Phone, SMS, Location, Camera, Microphone permissions"
    pecho "$PASTEL_CYAN" "• Termux:Boot - Boot permission to start services automatically"
    pecho "$PASTEL_CYAN" "• Termux:Widget - Display over other apps permission"
    pecho "$PASTEL_CYAN" "• Other plugins - Standard app permissions"
    echo ""
    pecho "$PASTEL_PINK" "After downloading, you'll need to:"
    pecho "$PASTEL_GREEN" "1. Install each APK manually from the file manager"
    pecho "$PASTEL_GREEN" "2. Grant the requested permissions for full functionality"
    echo ""
    pecho "$PASTEL_CYAN" "What will happen next:"
    info "• Android App Settings will open"
    info "• You can review app permissions there if needed"
    info "• APK downloads will begin automatically"
    echo ""
    printf "${PASTEL_YELLOW}Press Enter to open permission settings and continue with download...${RESET} "
    read -r
    
    # Open Android app permission settings
    if command -v am >/dev/null 2>&1; then
      info "Opening Android App Settings..."
      am start -a android.settings.APPLICATION_SETTINGS >/dev/null 2>&1 || true
      sleep 2  # Give user time to see the settings opened
    fi
  fi
  
  info "Downloading essential Termux plugin APKs..."
  
  local download_count=0
  local success_count=0
  local failed_apks=()
  
  for app_name in "${!ESSENTIAL_APKS[@]}"; do
    local package_id="${ESSENTIAL_APKS[$app_name]}"
    download_count=$((download_count + 1))
    
    if download_fdroid_apk "$package_id" "$app_name" >/dev/null; then
      success_count=$((success_count + 1))
    else
      failed_apks+=("$app_name")
    fi
  done
  
  # Report results
  if [ "$success_count" -eq "$download_count" ]; then
    ok "All $download_count essential APKs downloaded successfully"
  else
    local failed_count=$((download_count - success_count))
    warn "$success_count/$download_count APKs downloaded successfully"
    
    if [ ${#failed_apks[@]} -gt 0 ]; then
      warn "Failed downloads: ${failed_apks[*]}"
    fi
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
  
  # Count downloaded APKs
  local apk_count
  apk_count=$(find "$APK_DOWNLOAD_DIR" -name "*.apk" -type f 2>/dev/null | wc -l)
  
  if [ "$apk_count" -eq 0 ]; then
    warn "No APK files found in download directory"
  else
    ok "Found $apk_count APK files ready for installation"
  fi
  
  # Use termux-open to open the directory
  if command -v termux-open >/dev/null 2>&1; then
    run_with_progress "Open APK directory" 3 termux-open "$APK_DOWNLOAD_DIR"
    ok "APK directory opened in file manager"
  else
    warn "termux-open not available, please manually navigate to:"
    printf "${PASTEL_CYAN}%s${RESET}\n" "$APK_DOWNLOAD_DIR"
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
  
  printf "${PASTEL_GREEN}✓${RESET} Termux:API detected\n\n"
  
  # Guide through permission settings
  printf "${PASTEL_YELLOW}Let's verify your permissions:${RESET}\n\n"
  
  # Test API permissions
  printf "${PASTEL_CYAN}Testing phone access...${RESET} "
  if timeout 5 termux-telephony-deviceinfo >/dev/null 2>&1; then
    printf "${PASTEL_GREEN}✓${RESET}\n"
  else
    printf "${PASTEL_RED}✗${RESET} Grant phone permissions to Termux:API\n"
  fi
  
  printf "${PASTEL_CYAN}Testing location access...${RESET} "
  if timeout 5 termux-location >/dev/null 2>&1; then
    printf "${PASTEL_GREEN}✓${RESET}\n" 
  else
    printf "${PASTEL_RED}✗${RESET} Grant location permissions to Termux:API\n"
  fi
  
  # Check for widget installation
  printf "${PASTEL_CYAN}Checking widgets...${RESET} "
  if [ -d "/data/data/com.termux.widget" ] 2>/dev/null; then
    printf "${PASTEL_GREEN}✓${RESET}\n"
  else
    printf "${PASTEL_RED}✗${RESET} Install Termux:Widget for shortcuts\n"
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
  
  # Download all essential APKs first (before user interaction)
  download_essential_apks
  
  # Show installation instructions
  check_apk_permissions
  
  # Ask user if they want to proceed with installation
  printf "${PASTEL_PINK}Ready to install APKs. Continue? (y/N):${RESET} "
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    local response
    read -r response || response="n"
    case "${response,,}" in
      y|yes) ;;
      *)
        info "APK installation skipped by user"
        return 0
        ;;
    esac
  else
    printf "y (auto)\n"
  fi
  
  # Open APK directory for user installation
  open_apk_directory
  
  # Wait for user to install APKs
  printf "\n${PASTEL_PINK}Press Enter after installing all APKs...${RESET} "
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    read -r || true
  else
    printf "(auto-continue)\n"
    sleep 2
  fi
  
  # Run post-installation permission assistant
  assist_apk_permissions
  
  ok "APK management process completed"
  return 0
}

# Cleanup function for APK temporary files
cleanup_apk_temp(){
  if [ -d "$APK_STATE_DIR" ]; then
    # Only clean up F-Droid API response files, not the state files
    find "$APK_STATE_DIR" -name "fdroid_*.json" -type f -delete 2>/dev/null || true
  fi
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
