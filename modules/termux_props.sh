#!/usr/bin/env bash
###############################################################################
# CAD-Droid Termux Properties Module
# Termux configuration, phone detection, API interaction, and system properties
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_TERMUX_PROPS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_TERMUX_PROPS_LOADED=1

# === System Detection ===

# Detect the phone manufacturer for identification
# Sets TERMUX_PHONETYPE global variable
detect_phone(){
  local m="unknown"
  
  # Try to get manufacturer from Android property system
  if command -v getprop >/dev/null 2>&1; then
    m=$(getprop ro.product.manufacturer 2>/dev/null || echo "unknown")
  fi
  
  # Sanitize and normalize the manufacturer name
  TERMUX_PHONETYPE=$(sanitize_string "$(echo "$m" | tr '[:upper:]' '[:lower:]')")
  [ -z "$TERMUX_PHONETYPE" ] && TERMUX_PHONETYPE="unknown"
}

# Generate a random port number for SSH service
# Returns: available port number between 15000-65000
random_port(){
  local p a=0 max_attempts=10
  
  # Try up to max_attempts times to find an available port
  while [ $a -lt $max_attempts ]; do
    # Generate random port (15000-65000 range) safely
    if [ -r /dev/urandom ]; then
      local raw_bytes
      raw_bytes=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ' || echo "32768")
      # Validate the output is numeric
      case "$raw_bytes" in
        *[!0-9]*) raw_bytes="32768" ;;
        '') raw_bytes="32768" ;;
      esac
      p=$((raw_bytes % 50000 + 15000))
    else
      # Fallback using shell's RANDOM or process ID
      local rand_val="${RANDOM:-$$}"
      case "$rand_val" in
        *[!0-9]*) rand_val=12345 ;;
        '') rand_val=12345 ;;
      esac
      p=$((rand_val % 50000 + 15000))
    fi
    
    # Ensure port is in valid range
    if [ "$p" -lt 15000 ] || [ "$p" -gt 65000 ]; then
      p=22222
    fi
    
    # Check if port is already in use
    if command -v ss >/dev/null 2>&1; then
      if ! ss -ltn 2>/dev/null | grep -q ":$p "; then
        echo "$p"
        return 0
      fi
    elif command -v netstat >/dev/null 2>&1; then
      if ! netstat -ln 2>/dev/null | grep -q ":$p "; then
        echo "$p"
        return 0
      fi
    else
      # No port checking available, return the generated port
      echo "$p"
      return 0
    fi
    
    a=$((a+1))
  done
  
  # Fallback port if no random port available
  echo 22222
}

# Test connectivity to GitHub
# Returns: 0 if reachable, 1 if not reachable
probe_github(){ 
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 4 --max-time 6 https://github.com/ -o /dev/null 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=6 --tries=1 https://github.com/ -O /dev/null 2>/dev/null
  else
    return 1
  fi
}

# === Termux:API Detection and Interaction ===

# Detect if Termux:API is available and working
# Returns: 0 if available and functional, 1 if not available or not working
have_termux_api(){
  # Quick check if command exists
  if ! command -v termux-battery-status >/dev/null 2>&1; then
    return 1
  fi
  
  # Test if API actually works by trying to get battery status
  local test_result
  if test_result=$(timeout 5 termux-battery-status 2>/dev/null | head -1); then
    # Check if result contains expected JSON field (percentage)
    if echo "$test_result" | grep -qi '"percentage"'; then
      return 0
    fi
  fi
  
  return 1
}

# Wait for Termux:API app to be available with safe arithmetic
# Returns: 0 if available, 1 if not available after timeout
wait_for_termux_api(){
  if [ "${TERMUX_API_FORCE_SKIP:-0}" = "1" ]; then
    TERMUX_API_VERIFIED="skipped"
    return 0
  fi
  
  # Ask user if they want Termux:API (make it optional)
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    pecho "$PASTEL_PURPLE" "Termux:API Installation (Optional)"
    echo ""
    pecho "$PASTEL_CYAN" "Termux:API provides useful functions to access:"
    info "• GPS location and sensors"
    info "• Camera and flashlight control"
    info "• WiFi info and network details"
    info "• Phone calls and SMS features"
    info "• System notifications and clipboard"
    info "• Battery status and device info"
    echo ""
    pecho "$PASTEL_YELLOW" "Termux:API is useful for development tasks but not required for basic setup."
    echo ""
    
    if ask_yes_no "Do you want to install Termux:API?" "y"; then
      info "Checking for Termux:API installation..."
    else
      info "Skipping Termux:API installation"
      TERMUX_API_VERIFIED="skipped_by_user"
      return 0
    fi
  fi
  
  local max_attempts="${TERMUX_API_WAIT_MAX:-4}" 
  local delay_seconds="${TERMUX_API_WAIT_DELAY:-3}"
  local current_attempt=1  # Initialize counter safely
  
  # Validate max_attempts is numeric
  case "$max_attempts" in *[!0-9]*) max_attempts=4 ;; esac
  case "$delay_seconds" in *[!0-9]*) delay_seconds=3 ;; esac
  
  # Try multiple times to detect Termux:API
  while [ "$current_attempt" -le "$max_attempts" ] 2>/dev/null; do
    # Test if termux-battery-status command works (indicates API is available)
    if command -v termux-battery-status >/dev/null 2>&1; then
      local test_result
      test_result=$(timeout 5 termux-battery-status 2>/dev/null | head -1 || echo "")
      if echo "$test_result" | grep -qi '"percentage"'; then
        TERMUX_API_VERIFIED="yes"
        return 0
      fi
    fi
    
    # Wait between attempts (except on last attempt)
    if [ "$current_attempt" -lt "$max_attempts" ] 2>/dev/null; then
      info "Termux:API not found (attempt $current_attempt/$max_attempts). Enter to retry or wait ${delay_seconds}s."
      if [ "$NON_INTERACTIVE" != "1" ]; then
        read -r -t "$delay_seconds" || true
      else
        safe_sleep "$delay_seconds"
      fi
    fi
    
    # Safe counter increment
    if [ "$current_attempt" -lt 1000 ] 2>/dev/null; then
      current_attempt=$(add_int "${current_attempt:-0}" 1)
    else
      break  # Safety break to prevent infinite loops
    fi
  done
  
  # Final check - if still not found, offer to skip
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    warn "Termux:API not detected after $max_attempts attempts"
    if ask_yes_no "Continue without Termux:API?" "y"; then
      info "Continuing setup without Termux:API"
      TERMUX_API_VERIFIED="skipped_after_attempts"
      return 0
    fi
  fi
  
  TERMUX_API_VERIFIED="no"
  debug "Termux:API unavailable after ${max_attempts} attempts"
  return 1
}

# Configure bash prompt theme in ~/.bashrc
configure_bash_prompt(){
  local bashrc="$HOME/.bashrc"
  
  # Check if prompt is already configured
  if grep -q "# CAD-Droid prompt theme" "$bashrc" 2>/dev/null; then
    debug "Bash prompt theme already configured"
    return 0
  fi
  
  info "Configuring pink username and purple input theme..."
  
  # Persist current TERMUX_USERNAME/PHONETYPE to environment
  if ! grep -q '^export TERMUX_USERNAME=' "$bashrc" 2>/dev/null; then
    printf "export TERMUX_USERNAME=%q\n" "${TERMUX_USERNAME:-}" >> "$bashrc"
  fi
  if ! grep -q '^export TERMUX_PHONETYPE=' "$bashrc" 2>/dev/null; then
    printf "export TERMUX_PHONETYPE=%q\n" "${TERMUX_PHONETYPE:-}" >> "$bashrc"
  fi

  # Add prompt configuration to ~/.bashrc
  cat >> "$bashrc" << 'BASH_PROMPT_EOF'

# CAD-Droid prompt theme
# Pastel pink username, pastel purple typed text
# Username uses TERMUX_USERNAME if set, otherwise \u@\h
cad_reset='\[\e[0m\]'
cad_pastel_pink='\[\e[38;5;217m\]'    # Pastel pink for username
cad_pastel_cyan='\[\e[38;5;159m\]'    # Pastel cyan for path
cad_pastel_purple='\[\e[38;5;183m\]'  # Pastel purple for input text

# Compose display name from TERMUX_USERNAME or fallback to \u@\h
if [ -n "${TERMUX_USERNAME:-}" ]; then
  cad_name="${TERMUX_USERNAME}"
else
  cad_name='\u@\h'
fi

# Prompt: <pastel_pink>name</pastel_pink>:<pastel_cyan>cwd</pastel_cyan> and leave pastel purple color active for typed text
PS1="${cad_pastel_pink}\${cad_name}${cad_reset}:${cad_pastel_cyan}\w${cad_reset} ${cad_pastel_purple}"

# Reset color after each command so output returns to normal
PROMPT_COMMAND="echo -ne '\033[0m'"
BASH_PROMPT_EOF
  
  # Set proper permissions
  chmod 644 "$bashrc" 2>/dev/null || true
  
  ok "Bash prompt theme configured in ~/.bashrc"
}

# Configure nano editor with pastel colors
configure_nano_colors(){
  local nanorc="$HOME/.nanorc"
  
  # Check if nano color configuration is already present
  if grep -q "# CAD-Droid nano theme" "$nanorc" 2>/dev/null; then
    debug "Nano color theme already configured"
    return 0
  fi
  
  info "Configuring nano editor with pastel colors..."
  
  # Add nano color configuration
  cat >> "$nanorc" << 'NANO_CONFIG_EOF'

# CAD-Droid nano theme
# Pastel colors for better readability
set titlecolor brightwhite,lightmagenta
set statuscolor brightwhite,lightcyan
set selectedcolor brightwhite,lightblue
set stripecolor yellow
set numbercolor lightcyan
set keycolor lightcyan
set functioncolor lightgreen

# Syntax highlighting with pastel colors
include "/data/data/com.termux/files/usr/share/nano/*.nanorc"

# Enhanced editor behavior
set tabsize 2
set autoindent
set smooth
set mouse
set linenumbers
set constantshow
NANO_CONFIG_EOF
  
  # Set proper permissions
  chmod 644 "$nanorc" 2>/dev/null || true
  
  ok "Nano editor configured with pastel colors"
}

# === Termux Configuration ===

# Configure comprehensive Termux properties with enhanced features
configure_termux_properties(){
  local termux_dir="$HOME/.termux"
  
  # Create .termux directory if it doesn't exist
  if ! mkdir -p "$termux_dir" 2>/dev/null; then
    warn "Cannot create .termux directory"
    mark_step_status "warning"
    return 0
  fi
  
  # Set proper permissions
  chmod 700 "$termux_dir" 2>/dev/null || true
  
  local prop="$termux_dir/termux.properties"
  
  info "Configuring enhanced Termux properties with extra keys..."
  
  # Create comprehensive termux.properties with error handling
  if cat > "$prop" << TERMUX_PROPERTIES_EOF
# Enhanced Termux Properties Configuration
# Generated by CAD-Droid Mobile Development Setup
# User: ${TERMUX_USERNAME:-unknown}
# Git: ${GIT_USERNAME:-}${GIT_EMAIL:+ <$GIT_EMAIL>}
# Configuration date: $(date 2>/dev/null || echo "unknown")

# ===== BASIC SETTINGS =====
# Enable external app access (required for APKs)
allow-external-apps = true

# ===== EXTRA KEYS CONFIGURATION =====
# Enhanced extra keys row with power-user shortcuts
# Layout: ESC | / | - | HOME | UP | END | PGUP
#         TAB | CTRL | ALT | LEFT | DOWN | RIGHT | PGDN
extra-keys = [[ \
  {key: ESC, popup: {macro: "CTRL f d", display: "tmux exit"}}, \
  {key: "/", popup: "?"}, \
  {key: "-", popup: "_"}, \
  {key: HOME, popup: {macro: "CTRL a", display: "line start"}}, \
  {key: UP, popup: {macro: "CTRL p", display: "prev cmd"}}, \
  {key: END, popup: {macro: "CTRL e", display: "line end"}}, \
  {key: PGUP, popup: {macro: "CTRL u", display: "del line"}} \
], [ \
  {key: TAB, popup: {macro: "CTRL i", display: "tab"}}, \
  {key: CTRL, popup: {macro: "CTRL SHIFT c CTRL SHIFT v", display: "copy/paste"}}, \
  {key: ALT, popup: {macro: "ALT b ALT f", display: "word nav"}}, \
  {key: LEFT, popup: {macro: "CTRL b", display: "char left"}}, \
  {key: DOWN, popup: {macro: "CTRL n", display: "next cmd"}}, \
  {key: RIGHT, popup: {macro: "CTRL f", display: "char right"}}, \
  {key: PGDN, popup: {macro: "CTRL k", display: "del to end"}} \
]]

# ===== KEYBOARD SHORTCUTS =====
# Volume keys as additional input methods
use-black-ui = true
hide-soft-keyboard-on-startup = false

# ===== BELL AND NOTIFICATIONS =====
# Disable terminal bell
bell-character = ignore

# ===== ADVANCED TERMINAL SETTINGS =====
# Enforce UTF-8 encoding
enforce-char-based-input = true
# Enable full hardware keyboard support
use-fullscreen = false
use-fullscreen-workaround = false

# ===== DEVELOPMENT-FRIENDLY OPTIONS =====
# Terminal transcript (scrollback) settings
terminal-transcript-rows = 10000

# ===== POWER USER FEATURES =====
# Enable bracketed paste mode for better clipboard handling
bracketed-paste-mode = true
# Handle terminal resize properly
handle-resize = true
TERMUX_PROPERTIES_EOF
  then
    # Set proper file permissions (readable by owner only)
    chmod 600 "$prop" 2>/dev/null || true
    
    info "termux.properties created successfully"
    info "Pink username: ${TERMUX_USERNAME:-user}"
    info "Phone type: ${TERMUX_PHONETYPE:-unknown}"
  else
    warn "Failed to create termux.properties file"
    mark_step_status "success"
    return 0
  fi

  info "Extra keys configuration complete. Keys available:"
  info "  Row 1: ESC, /, -, HOME, UP, END, PGUP"
  info "  Row 2: TAB, CTRL, ALT, LEFT, DOWN, RIGHT, PGDN"
  info "  Long-press keys for additional shortcuts"
  
  # Reload Termux settings to apply changes with better error handling
  run_with_progress "Reload termux settings (enhanced)" 8 bash -c '
    if command -v termux-reload-settings >/dev/null 2>&1; then
      # Force reload settings and wait a moment
      termux-reload-settings && sleep 2
      echo "Termux settings reloaded successfully"
      echo "New terminal prompt and extra keys will be active"
    else
      echo "termux-reload-settings not available"
      echo "Please restart Termux to apply the new prompt colors and extra keys"
      exit 0
    fi
  '
  
  mark_step_status "success"
}

# === Termux Environment Validation ===

# Verify Termux environment is properly set up
validate_termux_environment(){
  local errors=0
  
  # Check critical paths
  if [ ! -d "$PREFIX" ]; then
    err "Termux PREFIX directory not found: $PREFIX"
    errors=$((errors + 1))
  fi
  
  if [ ! -d "$HOME" ]; then
    err "Termux HOME directory not found: $HOME"
    errors=$((errors + 1))
  fi
  
  # Check if we're running inside Termux
  if [ ! -d "/data/data/com.termux" ]; then
    err "Must run inside Termux environment"
    errors=$((errors + 1))
  fi
  
  # Check for package manager
  if ! command -v pkg >/dev/null 2>&1 && ! command -v apt >/dev/null 2>&1; then
    err "Package manager not available"
    errors=$((errors + 1))
  fi
  
  # Check TMPDIR
  if [ ! -w "${TMPDIR:-}" ]; then
    err "TMPDIR is not writable: ${TMPDIR:-}"
    errors=$((errors + 1))
  fi
  
  if [ "$errors" -gt 0 ]; then
    err "Termux environment validation failed with $errors errors"
    return 1
  else
    debug "Termux environment validation passed"
    return 0
  fi
}

# === User Input and Configuration ===

# Read user credentials with proper validation and timeout handling
read_credential() {
  local prompt="${1:-}"
  local var_name="${2:-}"
  local validation_type="${3:-nonempty}"
  local is_password="${4:-false}"
  
  # Validate required parameters
  if [ -z "$prompt" ] || [ -z "$var_name" ]; then
    err "read_credential requires prompt and variable name parameters"
    return 1
  fi
  
  if [ "$is_password" = "true" ]; then
    secure_password_input "$prompt" "$var_name"
  else
    read_nonempty "$prompt" "$var_name" "$validation_type"
  fi
}

# Secure password input with confirmation (SAFE: defaults prevent unbound errors)
secure_password_input() {
  local prompt="${1:-Enter password}"
  local var_name="${2:-CAD_PASSWORD}"
  local password confirm_password

  : "${MIN_PASSWORD_LENGTH:=8}"
  
  while true; do
    if [ "$NON_INTERACTIVE" = "1" ]; then
      # In non-interactive mode, generate a random password
      password=$(head -c 12 /dev/urandom | base64 | tr -d '/+' | head -c 16)
      eval "$var_name='\$password'"
      info "Generated password for $var_name (non-interactive mode)"
      return 0
    fi
    
    printf "%s: " "$prompt"
    if ! read -rs password; then
      return 1
    fi
    printf "\n"
    
    # Validate minimum length
    if [ ${#password} -lt "$MIN_PASSWORD_LENGTH" ] 2>/dev/null; then
      warn "Password must be at least $MIN_PASSWORD_LENGTH characters long"
      continue
    fi
    
    printf "Confirm password: "
    if ! read -rs confirm_password; then
      return 1
    fi
    printf "\n"
    
    if [ "$password" = "$confirm_password" ]; then
      eval "$var_name='\$password'"
      return 0
    else
      warn "Passwords do not match. Please try again."
    fi
  done
}

# === Termux-specific File Operations ===

# Open file manager to display directory with user guidance
open_file_manager(){
  local target="${1:-/storage/emulated/0/Download}"
  local show_prompt="${2:-true}"
  
  # Validate directory exists
  if [ ! -d "$target" ]; then
    if ! mkdir -p "$target" 2>/dev/null; then
      warn "Cannot create directory: $target"
      return 1
    fi
  fi
  
  # Show user guidance unless suppressed
  if [ "$show_prompt" = "true" ] && [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    pecho "$PASTEL_PURPLE" "=== Opening File Manager ==="
    echo ""
    pecho "$PASTEL_CYAN" "What will happen next:"
    info "• Android file manager will open"
    info "• Navigate to the displayed folder location"
    info "• You can browse and manage files there"
    echo ""
    info "Target folder: $target"
    echo ""
    pecho "$PASTEL_YELLOW" "Press Enter to open file manager..."
    read -r
  fi
  
  local opened=0
  
  # Method 1: Direct Android intent with file path (primary method)
  if [ $opened -eq 0 ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "file://$target" >/dev/null 2>&1; then
      opened=1
    fi
  fi
  
  # Method 2: Generic external storage content URI (fallback)
  if [ $opened -eq 0 ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "content://com.android.externalstorage.documents/root/primary" >/dev/null 2>&1; then
      opened=1
    fi
  fi
  
  # Method 3: Termux-open fallback (final fallback)
  if [ $opened -eq 0 ] && command -v termux-open >/dev/null 2>&1; then
    if termux-open "$target" >/dev/null 2>&1; then
      opened=1
    fi
  fi
  
  if [ $opened -eq 1 ]; then
    info "File manager opened"
    return 0
  else
    warn "Could not open file manager automatically"
    info "Please manually navigate to: $target"
    return 1
  fi
}

# User configuration step - configure username and git settings
step_usercfg(){ 
  detect_phone
  read_nonempty "Enter Termux username" TERMUX_USERNAME "user"
  TERMUX_USERNAME="${TERMUX_USERNAME}@${TERMUX_PHONETYPE}"
  
  # Confirm username
  if [ "$NON_INTERACTIVE" != "1" ]; then
    if ! ask_yes_no "Confirm username: $TERMUX_USERNAME" "y"; then
      read_nonempty "Enter Termux username" TERMUX_USERNAME "user"
      TERMUX_USERNAME="${TERMUX_USERNAME}@${TERMUX_PHONETYPE}"
    fi
  fi

  # Persist username and phonetype for new shells
  if ! grep -q '^export TERMUX_USERNAME=' "$HOME/.bashrc" 2>/dev/null; then
    printf "export TERMUX_USERNAME=%q\n" "$TERMUX_USERNAME" >> "$HOME/.bashrc"
  else
    # Update existing export (sed in-place safe)
    sed -i "s/^export TERMUX_USERNAME=.*/export TERMUX_USERNAME=$(printf "%q" "$TERMUX_USERNAME")/" "$HOME/.bashrc" 2>/dev/null || true
  fi
  if ! grep -q '^export TERMUX_PHONETYPE=' "$HOME/.bashrc" 2>/dev/null; then
    printf "export TERMUX_PHONETYPE=%q\n" "$TERMUX_PHONETYPE" >> "$HOME/.bashrc"
  fi
  
  ok "User: $TERMUX_USERNAME"
  
  # Git configuration with confirmation
  configure_git_with_timeout
  mark_step_status "success"
}

# Configure git with timeout and error handling
configure_git_with_timeout() {
  pecho "$PASTEL_PURPLE" "Configuring Git for version control..."
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    if ask_yes_no "Do you want to configure Git and GitHub?" "y"; then
      configure_git_interactive
      
      # Ask about SSH key generation
      echo ""
      if ask_yes_no "Generate SSH key for GitHub?" "y"; then
        generate_github_ssh_key
      fi
    else
      info "Skipping Git configuration"
      # Set minimal git config
      if command -v git >/dev/null 2>&1; then
        git config --global user.name "user" 2>/dev/null || true
        git config --global user.email "user@example.com" 2>/dev/null || true
        git config --global init.defaultBranch main 2>/dev/null || true
        git config --global pull.rebase false 2>/dev/null || true
      fi
      return 0
    fi
  else
    configure_git_interactive
  fi
}

# Interactive Git configuration
configure_git_interactive() {
  while true; do
    # Get git username
    read_nonempty "Enter Git username" GIT_USERNAME "${TERMUX_USERNAME%%@*}"
    
    # Get git email with validation
    read_nonempty "Enter Git email" GIT_EMAIL "user@example.com"
    
    # Validate email format
    if ! echo "$GIT_EMAIL" | grep -qE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; then
      warn "Invalid email format, using default"
      GIT_EMAIL="user@example.com"
    fi

    # Confirmation prompt
    if [ "$NON_INTERACTIVE" != "1" ]; then
      echo "Git will be configured as: $GIT_USERNAME <$GIT_EMAIL>"
      if ask_yes_no "Proceed with these Git settings?" "y"; then
        break
      else
        info "Re-enter Git details..."
      fi
    else
      break
    fi
  done
  
  # Configure git
  if command -v git >/dev/null 2>&1; then
    git config --global user.name "$GIT_USERNAME" 2>/dev/null || warn "Failed to set git username"
    git config --global user.email "$GIT_EMAIL" 2>/dev/null || warn "Failed to set git email"
    git config --global init.defaultBranch main 2>/dev/null || true
    git config --global pull.rebase false 2>/dev/null || true
    ok "Git configured: $GIT_USERNAME <$GIT_EMAIL>"
  else
    warn "Git not available for configuration"
  fi
}

# Generate SSH key for GitHub
generate_github_ssh_key() {
  pecho "$PASTEL_PURPLE" "Generating SSH key for GitHub..."
  
  local ssh_dir="$HOME/.ssh"
  local key_file="$ssh_dir/id_rsa"
  
  # Create SSH directory
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  
  # Check if key already exists
  if [ -f "$key_file" ]; then
    if [ "$NON_INTERACTIVE" != "1" ]; then
      if ask_yes_no "SSH key already exists. Overwrite?" "n"; then
        rm -f "$key_file" "$key_file.pub"
      else
        info "Using existing SSH key"
        cat "$key_file.pub" 2>/dev/null || warn "Could not read existing key"
        return 0
      fi
    else
      info "SSH key already exists"
      return 0
    fi
  fi
  
  # Generate SSH key with GitHub email
  info "Generating SSH key with email: $GIT_EMAIL"
  ssh-keygen -t rsa -b 4096 -C "$GIT_EMAIL" -f "$key_file" -N "" >/dev/null 2>&1
  
  if [ -f "$key_file.pub" ]; then
    ok "SSH key generated successfully"
    
    # Display the public key
    echo ""
    pecho "$PASTEL_CYAN" "Your SSH public key (copy this to GitHub):"
    echo ""
    cat "$key_file.pub"
    echo ""
    
    if [ "$NON_INTERACTIVE" != "1" ]; then
      pecho "$PASTEL_YELLOW" "Instructions:"
      info "1. Copy the SSH key above"
      info "2. Press Enter to open GitHub SSH settings"
      info "3. Click 'New SSH key' and paste the key"
      info "4. Give it a title (e.g., 'Termux Key')"
      info "5. Click 'Add SSH key'"
      echo ""
      pecho "$PASTEL_GREEN" "Press Enter to open GitHub SSH settings..."
      read -r || true
      
      # Open GitHub SSH settings
      if command -v termux-open-url >/dev/null 2>&1; then
        termux-open-url "https://github.com/settings/ssh/new"
      elif command -v am >/dev/null 2>&1; then
        am start -a android.intent.action.VIEW -d "https://github.com/settings/ssh/new" >/dev/null 2>&1 || true
      fi
      
      echo ""
      pecho "$PASTEL_CYAN" "Press Enter when you've added the SSH key to GitHub..."
      read -r || true
    fi
  else
    err "Failed to generate SSH key"
    return 1
  fi
}
