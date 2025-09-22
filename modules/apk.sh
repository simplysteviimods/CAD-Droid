#!/usr/bin/env bash
###############################################################################
# CAD-Droid APK Module
# APK download, F-Droid API interaction, GitHub releases, and file management
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_APK_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_APK_LOADED=1

# === File Size and Validation ===

# Ensure APK file meets minimum size requirements
# Parameters: file_path
# Returns: 0 if valid, 1 if invalid or too small
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

# === HTTP Download Functions ===

# Download helper using wget (optimized for APK downloads)
wget_get(){
  local timeout="${CURL_MAX_TIME:-40}"
  local connect_timeout="${CURL_CONNECT:-5}"
  
  # Use wget with proper timeouts and error handling
  wget \
    --timeout="$timeout" \
    --connect-timeout="$connect_timeout" \
    --tries=3 \
    --user-agent="CAD-Droid-Setup/1.0" \
    --no-check-certificate \
    --progress=dot:mega \
    "$@" 2>/dev/null
}

# HTTP fetch function optimized for APK downloads
# Guarantees overwrite by removing existing file first
# Parameters: url, output_file
# Returns: 0 if successful, 1 if failed
http_fetch(){
  local url="$1" output="$2"
  
  if [ -z "$url" ] || [ -z "$output" ]; then
    return 1
  fi

  # Force overwrite behavior: ensure directory exists and remove any existing file
  mkdir -p "$(dirname "$output")" 2>/dev/null || true
  [ -e "$output" ] && rm -f -- "$output" 2>/dev/null || true
  
  # Try wget only for APK downloads (no curl fallback due to 404 errors)
  if wget_get -O "$output" "$url"; then
    return 0
  else
    return 1
  fi
}

# === F-Droid API Functions ===

# Fetch APK from F-Droid using their API
# Parameters: package_name, output_file
# Returns: 0 if successful, 1 if failed
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
# Parameters: package_name, output_file
# Returns: 0 if successful, 1 if failed
fetch_fdroid_page(){
  local pkg="$1"
  local out="$2"
  local html_file="$TMPDIR/fdroid_page_${pkg}.html"
  local page="https://f-droid.org/packages/$pkg/"
  
  if [ -z "$pkg" ] || [ -z "$out" ]; then
    return 1
  fi
  
  # Download F-Droid package page
  if ! http_fetch "$page" "$html_file"; then
    return 1
  fi
  
  # Extract APK download link from HTML
  local apk_link
  apk_link=$(grep -o 'href="[^"]*\.apk"' "$html_file" 2>/dev/null | head -1 | sed 's/href="//;s/"//')
  
  if [ -z "$apk_link" ]; then
    rm -f "$html_file" 2>/dev/null
    return 1
  fi
  
  # Make absolute URL if relative
  if [[ "$apk_link" == /* ]]; then
    apk_link="https://f-droid.org$apk_link"
  elif [[ "$apk_link" != http* ]]; then
    apk_link="https://f-droid.org/repo/$apk_link"
  fi
  
  # Download the APK
  if http_fetch "$apk_link" "$out"; then
    rm -f "$html_file" 2>/dev/null
    ensure_min_size "$out"
  else
    rm -f "$html_file" 2>/dev/null
    return 1
  fi
}

# === GitHub Releases Functions ===

# Get friendly name for common Termux addon APKs
get_friendly_apk_name(){
  local package_name="$1"
  local app_name="$2"
  
  # Map common Termux addons to friendly names
  case "$package_name" in
    "com.termux.api") echo "Termux API.apk" ;;
    "com.termux.x11") echo "Termux X11.apk" ;;
    "com.termux.gui") echo "Termux GUI.apk" ;;
    "com.termux.widget") echo "Termux Widget.apk" ;;
    *) echo "${app_name}.apk" ;;
  esac
}

# Fetch APK from GitHub releases with friendly naming
# Parameters: repo, pattern, output_directory, app_name
# Returns: 0 if successful, 1 if failed
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
    line=$(grep -m1 '"browser_download_url"' "$data_file" | grep "$pattern" 2>/dev/null || true)
    if [ -n "$line" ]; then
      url=$(echo "$line" | awk -F'"' '{print $4}')
      # Try to extract filename from URL
      original_filename=$(basename "$url" 2>/dev/null || echo "${app_name}.apk")
    fi
  fi
  
  if [ -z "$url" ]; then
    rm -f "$data_file" 2>/dev/null
    return 1
  fi
  
  # Use friendly naming for Termux addons
  local friendly_name
  friendly_name=$(get_friendly_apk_name "$app_name" "$app_name")
  
  # Download to temporary file first, then rename to friendly name
  local temp_file="$outdir/.tmp_${app_name}_$$.apk"
  local final_file="$outdir/$friendly_name"
  
  # Download the APK to temp file
  if http_fetch "$url" "$temp_file"; then
    rm -f "$data_file" 2>/dev/null
    
    # Verify file size
    if ensure_min_size "$temp_file"; then
      # Move to final location with friendly name; force overwrite
      rm -f "$final_file" 2>/dev/null || true
      if mv -f "$temp_file" "$final_file" 2>/dev/null; then
        ok "Downloaded: $friendly_name"
      else
        warn "Failed to rename to friendly name"
        rm -f "$temp_file" 2>/dev/null
        return 1
      fi
    else
      rm -f "$temp_file" 2>/dev/null
      return 1
    fi
  else
    rm -f "$data_file" 2>/dev/null
    return 1
  fi
}

# === APK Directory Management ===

# Use Termux file picker to select APK directory with improved UX and fallback
select_apk_directory(){
  # Set default location first
  local default_location="/storage/emulated/0/Download/CAD-Droid-APKs"
  USER_SELECTED_APK_DIR="$default_location"
  
  pecho "$PASTEL_PURPLE" "APK File Location Setup"
  echo ""
  format_body_text "Your APK files will be downloaded to a folder for easy installation. You can choose a custom location or use the default Downloads folder."
  echo ""
  info "Default location: $default_location"
  echo ""
  
  # Quick check for termux-storage-get availability
  local has_file_picker=false
  if command -v termux-storage-get >/dev/null 2>&1; then
    has_file_picker=true
  fi
  
  # If no file picker available, use default and continue
  if [ "$has_file_picker" = false ]; then
    info "File picker not available - using default location"
    return 0
  fi
  
  # Interactive file picker option
  if [ "$NON_INTERACTIVE" = "1" ]; then
    info "Using default location (non-interactive mode)"
    return 0
  fi
  
  # Offer choice between default and custom location
  pecho "$PASTEL_PURPLE" "Options:"
  info "  1. Use default location (recommended)"
  info "  2. Choose custom location with file picker"
  echo ""
  
  local choice=1
  if ! read_option "Select option" choice 1 2 1; then
    info "Using default location"
    return 0
  fi
  
  if [ "$choice" = "2" ]; then
    info "Opening file picker... Please select a folder for APK downloads."
    
    # Try to get directory using termux-storage-get
    local selected_dir
    if selected_dir=$(termux-storage-get 2>/dev/null | head -1); then
      if [ -n "$selected_dir" ] && [ -d "$(dirname "$selected_dir")" ]; then
        USER_SELECTED_APK_DIR="$(dirname "$selected_dir")/CAD-Droid-APKs"
        info "Selected custom location: $USER_SELECTED_APK_DIR"
      else
        warn "Invalid selection, using default location"
      fi
    else
      warn "File picker failed, using default location"
    fi
  fi
  
  return 0
}

# Create APK directory with proper permissions and display instructions
setup_apk_directory(){
  local target="${USER_SELECTED_APK_DIR:-/storage/emulated/0/Download/CAD-Droid-APKs}"
  
  # Create directory
  if ! mkdir -p "$target" 2>/dev/null; then
    warn "Cannot create directory: $target"
    return 1
  fi
  
  info "APK directory: $target"
  pecho "$PASTEL_PURPLE" "INSTRUCTIONS:"
  info "  1. Press Enter to open folder (view only)."
  pecho "$PASTEL_GREEN" "  2. Install *.apk add-ons."
  info "  3. Return & continue."
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    pecho "$PASTEL_CYAN" "Next step: File manager will open to show APK location"
    info "You can install APKs by tapping them from the file manager"
    echo ""
    pecho "$PASTEL_YELLOW" "Press Enter to open folder..."
    read -r || true
  fi
  
  # Try to open file manager with enhanced prompts
  if open_file_manager "$target" "false"; then  # Don't show duplicate prompt
    info "File manager opened successfully"
  else
    info "Please manually navigate to: $target"
  fi
  
  return 0
}

# === High-level APK Download Functions ===

# Download APK with intelligent source selection and friendly naming
# Parameters: package_name, display_name, fdroid_pkg, github_repo, github_pattern, output_directory
download_apk(){
  local name="$1"
  local display_name="$2"
  local pkg="$3"
  local repo="$4"
  local patt="$5"
  local outdir="$6"
  
  local success=0
  local prefer="${PREFER_FDROID:-1}"
  
  # Get friendly filename
  local friendly_name
  friendly_name=$(get_friendly_apk_name "$pkg" "$name")
  local target_file="$outdir/$friendly_name"
  
  # Try preferred source first
  if [ "$prefer" = "1" ]; then
    # F-Droid preferred (default) - download to temp then rename
    local temp_fdroid="$outdir/.tmp_fdroid_${name}_$$.apk"
    if fetch_fdroid_api "$pkg" "$temp_fdroid" || fetch_fdroid_page "$pkg" "$temp_fdroid"; then
      # Force overwrite destination
      rm -f "$target_file" 2>/dev/null || true
      if mv -f "$temp_fdroid" "$target_file" 2>/dev/null; then
        success=1
      else
        rm -f "$temp_fdroid" 2>/dev/null
      fi
    fi
  else
    # GitHub preferred
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
      local temp_fdroid="$outdir/.tmp_fdroid_${name}_$$.apk"
      if fetch_fdroid_api "$pkg" "$temp_fdroid" || fetch_fdroid_page "$pkg" "$temp_fdroid"; then
        rm -f "$target_file" 2>/dev/null || true
        if mv -f "$temp_fdroid" "$target_file" 2>/dev/null; then
          success=1
        else
          rm -f "$temp_fdroid" 2>/dev/null
        fi
      fi
    fi
  fi
  
  return $((1 - success))
}

# Fetch specific Termux addon APK with intelligent fallback
# Parameters: display_name, package_name, github_repo, github_pattern, output_directory  
fetch_termux_addon(){
  local name="$1" pkg="$2" repo="$3" patt="$4" outdir="$5"
  local prefer="${PREFER_FDROID:-1}" success=0
  
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
  
  # Prioritize F-Droid by default (prefer=1)
  if [ "$prefer" = "1" ]; then
    # Try F-Droid first (preferred)
    if fetch_fdroid_api "$pkg" "$outdir/${name}.apk" || fetch_fdroid_page "$pkg" "$outdir/${name}.apk"; then
      success=1
    fi
  else
    # Try GitHub first (preserves original names)
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

# Batch download multiple APKs
# Parameters: output_directory, apk_list_array_name
batch_download_apks(){
  local outdir="$1"
  local list_var="$2"
  local success_count=0 fail_count=0
  
  # Create output directory
  if ! mkdir -p "$outdir" 2>/dev/null; then
    err "Cannot create APK directory: $outdir"
    return 1
  fi
  
  # Get array reference
  eval "local apk_list=(\"\${${list_var}[@]}\")"
  local total=${#apk_list[@]}
  
  if [ "$total" -eq 0 ]; then
    warn "No APKs to download"
    return 0
  fi
  
  pecho "$PASTEL_PURPLE" "Starting batch download of $total APKs to: $outdir"
  
  local i=0
  while [ "$i" -lt "$total" ]; do
    local apk_spec="${apk_list[$i]}"
    
    # Parse APK specification (format: "name|display|fdroid_pkg|github_repo|github_pattern")
    IFS='|' read -r name display_name pkg repo patt <<< "$apk_spec"
    
    if [ -n "$name" ]; then
      info "Downloading ($((i+1))/$total): ${display_name:-$name}"
      
      if run_with_progress "Download ${display_name:-$name}" 30 \
         download_apk "$name" "$display_name" "$pkg" "$repo" "$patt" "$outdir"; then
        success_count=$((success_count + 1))
        ok "Downloaded: ${display_name:-$name}"
      else
        fail_count=$((fail_count + 1))
        warn "Failed to download: ${display_name:-$name}"
        APK_MISSING+=("$name")
      fi
    fi
    
    i=$((i + 1))
  done
  
  # Report summary
  info "Batch download complete:"
  info "  ✓ Successful: $success_count"
  if [ "$fail_count" -gt 0 ]; then
    warn "  ✗ Failed: $fail_count"
  fi
  
  DOWNLOAD_COUNT="$success_count"
  
  # Return success if at least some APKs downloaded
  [ "$success_count" -gt 0 ]
}

# === APK Verification ===

# Verify APK file integrity and basic structure
verify_apk(){
  local apk_file="$1"
  
  # Check file exists and has minimum size
  if ! ensure_min_size "$apk_file"; then
    return 1
  fi
  
  # Basic APK structure check (ZIP magic bytes)
  if command -v file >/dev/null 2>&1; then
    local file_type
    file_type=$(file "$apk_file" 2>/dev/null || echo "")
    if ! echo "$file_type" | grep -qi "zip\|archive"; then
      warn "APK file may be corrupted: $apk_file"
      return 1
    fi
  fi
  
  # Check for Android manifest (if unzip available)
  if command -v unzip >/dev/null 2>&1; then
    if ! unzip -l "$apk_file" 2>/dev/null | grep -q AndroidManifest.xml; then
      warn "APK file missing AndroidManifest.xml: $apk_file"
      return 1
    fi
  fi
  
  return 0
}

# Verify all APK files in directory
verify_apk_directory(){
  local apk_dir="$1"
  local verified=0 failed=0
  
  if [ ! -d "$apk_dir" ]; then
    warn "APK directory does not exist: $apk_dir"
    return 1
  fi
  
  info "Verifying APK files in: $apk_dir"
  
  # Check each APK file
  find "$apk_dir" -name "*.apk" -type f 2>/dev/null | while read -r apk_file; do
    local basename
    basename=$(basename "$apk_file")
    
    if verify_apk "$apk_file"; then
      debug "✓ Valid APK: $basename"
      verified=$((verified + 1))
    else
      warn "✗ Invalid APK: $basename"
      failed=$((failed + 1))
    fi
  done
  
  info "APK verification complete: $verified valid, $failed failed"
  return 0
}
