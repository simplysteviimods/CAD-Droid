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

# APK Configuration
readonly APK_DOWNLOAD_DIR="$HOME/storage/downloads/cad-droid-apks"
readonly APK_TEMP_DIR="$TMPDIR/apk_downloads"

# F-Droid API configuration
readonly FDROID_API_BASE="https://f-droid.org/api/v1"
readonly FDROID_REPO_BASE="https://f-droid.org/repo"

# Essential APKs from F-Droid with their package IDs
declare -A ESSENTIAL_APKS=(
  ["Termux"]="com.termux"
  ["Termux:API"]="com.termux.api"
  ["Termux:Boot"]="com.termux.boot"
  ["Termux:Float"]="com.termux.float"
  ["Termux:Styling"]="com.termux.styling"
  ["Termux:Tasker"]="com.termux.tasker"
  ["Termux:Widget"]="com.termux.widget"
  ["Termux:X11"]="com.termux.x11"
)

# Initialize APK management system
init_apk_system(){
  info "Initializing APK management system..."
  
  # Create download directories
  run_with_progress "Setup APK directories" 5 bash -c "
    mkdir -p '$APK_DOWNLOAD_DIR' &&
    mkdir -p '$APK_TEMP_DIR' &&
    chmod 755 '$APK_DOWNLOAD_DIR' '$APK_TEMP_DIR'
  "
  
  # Ensure storage access is available
  if [ ! -d "$HOME/storage/downloads" ]; then
    warn "Storage access not available, requesting permissions..."
    if command -v termux-setup-storage >/dev/null 2>&1; then
      run_with_progress "Request storage access" 8 termux-setup-storage
    fi
  fi
  
  ok "APK management system initialized"
}

# Query F-Droid API for package information
query_fdroid_package(){
  local package_id="$1"
  
  if [ -z "$package_id" ]; then
    err "Package ID required for F-Droid query"
    return 1
  fi
  
  local api_url="$FDROID_API_BASE/packages/$package_id"
  local response_file="$APK_TEMP_DIR/fdroid_${package_id}.json"
  
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

# Download APK from F-Droid
download_fdroid_apk(){
  local package_id="$1"
  local app_name="${2:-$package_id}"
  
  info "Downloading $app_name from F-Droid..."
  
  # Get download URL
  local download_url
  if ! download_url=$(get_fdroid_apk_url "$package_id"); then
    err "Failed to get download URL for $package_id"
    return 1
  fi
  
  # Extract APK filename
  local apk_filename
  apk_filename=$(basename "$download_url")
  local output_file="$APK_DOWNLOAD_DIR/$apk_filename"
  
  # Check if already downloaded
  if [ -f "$output_file" ]; then
    ok "$app_name APK already downloaded"
    echo "$output_file"
    return 0
  fi
  
  # Download the APK
  if download_with_spinner "$download_url" "$output_file" "Download $app_name"; then
    # Verify download
    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
      ok "$app_name downloaded successfully"
      echo "$output_file"
      return 0
    else
      err "Downloaded APK file is empty or corrupted"
      rm -f "$output_file" 2>/dev/null || true
      return 1
    fi
  else
    err "Failed to download $app_name APK"
    return 1
  fi
}

# Download all essential APKs before user interaction
download_essential_apks(){
  info "Pre-downloading essential APKs from F-Droid..."
  
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

# Verify APK installation permissions
check_apk_permissions(){
  info "Checking APK installation permissions..."
  
  # Check if we can request install permissions
  if command -v termux-api-start >/dev/null 2>&1; then
    run_with_progress "Check install permissions" 5 bash -c '
      # This will show if we have permission to install APKs
      am start -a android.settings.MANAGE_UNKNOWN_APP_SOURCES >/dev/null 2>&1 || true
    '
  fi
  
  # Provide installation instructions
  printf "\n${PASTEL_PINK}APK Installation Instructions:${RESET}\n"
  printf "${PASTEL_CYAN}1.${RESET} Enable 'Install unknown apps' for your file manager\n"
  printf "${PASTEL_CYAN}2.${RESET} Navigate to: %s\n" "$APK_DOWNLOAD_DIR"
  printf "${PASTEL_CYAN}3.${RESET} Install APKs in this order:\n"
  
  local install_order=(
    "Termux:API"
    "Termux:Boot" 
    "Termux:Widget"
    "Termux:X11"
    "Termux:Float"
    "Termux:Styling"
    "Termux:Tasker"
  )
  
  for app in "${install_order[@]}"; do
    printf "   ${PASTEL_LAVENDER}•${RESET} %s\n" "$app"
  done
  
  printf "\n${PASTEL_YELLOW}Important:${RESET} Grant all requested permissions during installation\n\n"
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
  
  # Wait for user confirmation
  printf "\n${PASTEL_PINK}Press Enter after installing all APKs...${RESET} "
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    read -r || true
  else
    printf "(auto-continue)\n"
    sleep 2
  fi
  
  ok "APK management process completed"
  return 0
}

# Cleanup function for APK temporary files
cleanup_apk_temp(){
  if [ -d "$APK_TEMP_DIR" ]; then
    run_with_progress "Clean APK temp files" 3 rm -rf "$APK_TEMP_DIR"
  fi
}

# Set up cleanup on script exit
trap cleanup_apk_temp EXIT

# Export functions for use by other modules
export -f init_apk_system
export -f download_fdroid_apk
export -f download_essential_apks
export -f open_apk_directory
export -f manage_
