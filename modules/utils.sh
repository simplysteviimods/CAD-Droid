#!/usr/bin/env bash
###############################################################################
# CAD-Droid Utilities Module
# Safe arithmetic, validation, input handling, and utility functions
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_UTILS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_UTILS_LOADED=1

# === Safe Arithmetic & Validation Utilities ===

# Safe calculation function - validates expressions and handles errors
safe_calc() {
  local expr="$1"
  
  # Simple safety checks - reject clearly dangerous patterns
  case "$expr" in
    *[\;\&\|\`\$]*) return 1 ;;  # Dangerous shell characters
    *[a-zA-Z]*) return 1 ;;      # No letters allowed
    "") return 1 ;;              # Empty expression
  esac
  
  # Attempt calculation with error handling
  local result
  if result=$(( expr )) 2>/dev/null; then
    echo "$result"
    return 0
  else
    echo "0"  # Return 0 on any arithmetic failure
    return 1
  fi
}

# Check if value is non-negative integer
is_nonneg_int() {
  local val="$1"
  [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 0 ] 2>/dev/null
}

# Clamp integer between min and max values
clamp_int() {
  local val="$1" min="$2" max="$3"
  if ! is_nonneg_int "$val"; then val="$min"; fi
  if [ "$val" -lt "$min" ]; then val="$min"; fi
  if [ "$val" -gt "$max" ]; then val="$max"; fi
  echo "$val"
}

# Safe integer addition
add_int() {
  local a="$1" b="$2"
  if is_nonneg_int "$a" && is_nonneg_int "$b"; then
    safe_calc "$a + $b"
  else
    echo "0"
    return 1
  fi
}

# Calculate percentage of a value
percent_of() {
  local value="$1" percent="$2"
  if is_nonneg_int "$value" && is_nonneg_int "$percent"; then
    safe_calc "$value * $percent / 100"
  else
    echo "0"
    return 1
  fi
}

# Safe integer subtraction
sub_int() {
  local a="$1" b="$2"
  if is_nonneg_int "$a" && is_nonneg_int "$b"; then
    safe_calc "$a - $b"
  else
    echo "0"
    return 1
  fi
}

# Safely increment a variable
inc_var() {
  local var_name="$1"
  local current="${!var_name:-0}"
  if is_nonneg_int "$current"; then
    local new_val
    new_val=$(add_int "$current" 1)
    eval "$var_name=$new_val"
  else
    eval "$var_name=1"
  fi
}

# Validate array bounds before access
validate_array_access() {
  local array_name="$1" index="$2"
  local array_length_var="${array_name}[@]"
  local array_length="${#!array_length_var[@]}"
  is_nonneg_int "$index" && [ "$index" -lt "$array_length" ]
}

# Safe array iteration wrapper
iterate_array() {
  local array_name="$1" callback_func="$2"
  local array_length_var="${array_name}[@]"
  local array_ref="$array_name"
  eval "local array_length=\${#${array_name}[@]}"
  
  if ! is_nonneg_int "$array_length"; then
    return 1
  fi
  
  local i=0
  while [ "$i" -lt "$array_length" ]; do
    eval "local element=\"\${${array_name}[$i]}\""
    if declare -f "$callback_func" >/dev/null; then
      "$callback_func" "$element" "$i" || true
    fi
    i=$(add_int "$i" 1) || break
  done
}

# Duplication detection guard
assert_unique_definitions() {
  local func_count
  func_count=$(grep -c '^safe_calc()' "$0" 2>/dev/null || echo "1")
  if [ "$func_count" -gt 1 ] 2>/dev/null; then
    echo "ERROR: Detected duplicate function definitions. Script may have been corrupted." >&2
    exit 2
  fi
}

# === Validation Functions ===

# Validate curl timeout values are numeric before use
validate_curl_timeouts() {
  # CURL_CONNECT validation
  case "${CURL_CONNECT:-}" in
    ''|*[!0-9]*) CURL_CONNECT=5 ;;
    *) 
      if [ "$CURL_CONNECT" -lt 1 ] 2>/dev/null; then
        CURL_CONNECT=5
      elif [ "$CURL_CONNECT" -gt 60 ] 2>/dev/null; then
        CURL_CONNECT=60
      fi
      ;;
  esac

  # CURL_MAX_TIME validation  
  case "${CURL_MAX_TIME:-}" in
    ''|*[!0-9]*) CURL_MAX_TIME=40 ;;
    *)
      if [ "$CURL_MAX_TIME" -lt 10 ] 2>/dev/null; then
        CURL_MAX_TIME=40
      elif [ "$CURL_MAX_TIME" -gt 300 ] 2>/dev/null; then
        CURL_MAX_TIME=300
      fi
      ;;
  esac
}

# Validate timeout values with robust checking
validate_timeout_vars() {
  # APK_PAUSE_TIMEOUT validation
  case "${APK_PAUSE_TIMEOUT:-}" in
    ''|*[!0-9]*) APK_PAUSE_TIMEOUT=45 ;;
    *)
      if [ "${#APK_PAUSE_TIMEOUT}" -gt 0 ] && [ "$APK_PAUSE_TIMEOUT" -ge 1 ] 2>/dev/null; then
        : # Value is valid, keep it
      else
        APK_PAUSE_TIMEOUT=45
      fi
      ;;
  esac
  
  # GITHUB_PROMPT_TIMEOUT_OPEN validation
  case "${GITHUB_PROMPT_TIMEOUT_OPEN:-}" in
    ''|*[!0-9]*) GITHUB_PROMPT_TIMEOUT_OPEN=30 ;;
    *)
      if [ "${#GITHUB_PROMPT_TIMEOUT_OPEN}" -gt 0 ] && [ "$GITHUB_PROMPT_TIMEOUT_OPEN" -ge 1 ] 2>/dev/null; then
        : # Value is valid, keep it
      else
        GITHUB_PROMPT_TIMEOUT_OPEN=30
      fi
      ;;
  esac
  
  # GITHUB_PROMPT_TIMEOUT_CONFIRM validation
  case "${GITHUB_PROMPT_TIMEOUT_CONFIRM:-}" in
    ''|*[!0-9]*) GITHUB_PROMPT_TIMEOUT_CONFIRM=60 ;;
    *)
      if [ "${#GITHUB_PROMPT_TIMEOUT_CONFIRM}" -gt 0 ] && [ "$GITHUB_PROMPT_TIMEOUT_CONFIRM" -ge 1 ] 2>/dev/null; then
        : # Value is valid, keep it
      else
        GITHUB_PROMPT_TIMEOUT_CONFIRM=60
      fi
      ;;
  esac
  
  # TERMUX_API_WAIT_MAX validation
  case "${TERMUX_API_WAIT_MAX:-}" in
    ''|*[!0-9]*) TERMUX_API_WAIT_MAX=4 ;;
    *)
      if [ "${#TERMUX_API_WAIT_MAX}" -gt 0 ] && [ "$TERMUX_API_WAIT_MAX" -ge 1 ] 2>/dev/null; then
        : # Value is valid, keep it
      else
        TERMUX_API_WAIT_MAX=4
      fi
      ;;
  esac
  
  # TERMUX_API_WAIT_DELAY validation
  case "${TERMUX_API_WAIT_DELAY:-}" in
    ''|*[!0-9]*) TERMUX_API_WAIT_DELAY=3 ;;
    *)
      if [ "${#TERMUX_API_WAIT_DELAY}" -gt 0 ] && [ "$TERMUX_API_WAIT_DELAY" -ge 1 ] 2>/dev/null; then
        : # Value is valid, keep it
      else
        TERMUX_API_WAIT_DELAY=3
      fi
      ;;
  esac
}

# Validate spinner delay safely
validate_spinner_delay() {
  local delay_val="${SPINNER_DELAY:-0.02}"
  
  # Remove any potentially dangerous characters
  delay_val=$(echo "$delay_val" | tr -cd '0-9.')
  
  # Check if it's a valid decimal number
  case "$delay_val" in
    ''|*[!0-9.]*|.*.*.*|.) 
      SPINNER_DELAY="0.02"
      ;;
    *.*)
      # Simple range check without awk
      local int_part="${delay_val%.*}"
      local dec_part="${delay_val#*.}"
      if [ "${int_part:-0}" -eq 0 ] && [ "${#dec_part}" -le 2 ] && [ "${dec_part:-1}" -ge 1 ] && [ "${dec_part:-100}" -le 99 ]; then
        SPINNER_DELAY="$delay_val"
      else
        SPINNER_DELAY="0.02"
      fi
      ;;
    *)
      # Integer value
      if [ "$delay_val" -ge 1 ] 2>/dev/null; then
        SPINNER_DELAY="1.0"
      else
        SPINNER_DELAY="0.02"
      fi
      ;;
  esac
}

# Validate MIN_APK_SIZE
validate_apk_size() {
  case "$MIN_APK_SIZE" in
    *[!0-9]*) MIN_APK_SIZE=12288 ;;
    *) [ "$MIN_APK_SIZE" -lt 1024 ] && MIN_APK_SIZE=12288 ;;
  esac
}

# === Input Validation and User Interaction ===

# Validate user input with pattern matching
# Parameters: input_string, validation_type
validate_input() {
  local input="$1"
  local type="$2"
  local max_len="${MAX_INPUT_LENGTH:-256}"
  
  # Check maximum length first
  if [ ${#input} -gt "$max_len" ]; then
    return 1
  fi
  
  case "$type" in
    username)
      [[ "$input" =~ $ALLOWED_USERNAME_REGEX ]]
      ;;
    email)
      [[ "$input" =~ $ALLOWED_EMAIL_REGEX ]]
      ;;
    filename)
      [[ "$input" =~ $ALLOWED_FILENAME_REGEX ]]
      ;;
    nonempty)
      [ -n "$input" ]
      ;;
    port)
      [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 65535 ]
      ;;
    *)
      return 1
      ;;
  esac
}

# Read non-empty input with validation
# Parameters: prompt, variable_name, validation_type, default_value
read_nonempty() {
  local prompt="${1:-}"
  local var_name="${2:-}" 
  local validation_type="${3:-nonempty}"
  local default_val="${4:-}"
  
  local input
  while true; do
    if [ "$NON_INTERACTIVE" = "1" ] && [ -n "$default_val" ]; then
      eval "$var_name='$default_val'"
      return 0
    fi
    
    printf "%s" "$prompt"
    if [ -n "$default_val" ]; then
      printf " [%s]" "$default_val"
    fi
    printf ": "
    
    if ! read -r input; then
      return 1
    fi
    
    # Use default if empty input
    if [ -z "$input" ] && [ -n "$default_val" ]; then
      input="$default_val"
    fi
    
    # Validate input
    if validate_input "$input" "$validation_type"; then
      eval "$var_name='$input'"
      return 0
    else
      printf "Invalid input. Please try again.\n"
    fi
  done
}

# Sanitize string for safe use in filenames and variables
sanitize_string() {
  local str="$1"
  # Remove dangerous characters and limit length
  echo "$str" | sed 's/[^a-zA-Z0-9._-]//g' | cut -c1-32
}

# Read user option with validation using safe arithmetic and bounds checking
# Parameters: prompt, variable_name, min_value, max_value, default_value
read_option(){
  local prompt="${1:-}" var_name="${2:-}" min_val="${3:-1}" max_val="${4:-10}" default_val="${5:-}"
  
  # Fallback default_val to min_val if empty
  if [ -z "$default_val" ]; then
    default_val="$min_val"
  fi
  
  # Validate all numeric parameters
  case "$min_val" in *[!0-9-]*) min_val=1 ;; esac
  case "$max_val" in *[!0-9-]*) max_val=10 ;; esac
  case "$default_val" in *[!0-9-]*) default_val="$min_val" ;; esac
  
  # Ensure min/max relationship is logical
  if [ "$min_val" -gt "$max_val" ] 2>/dev/null; then
    local temp="$min_val"
    min_val="$max_val"
    max_val="$temp"
  fi
  
  if [ "$NON_INTERACTIVE" = "1" ]; then
    eval "$var_name='$default_val'"
    return 0
  fi
  
  local attempts=0 max_attempts=3
  while [ "$attempts" -lt "$max_attempts" ] 2>/dev/null; do
    pecho "$PASTEL_CYAN" "$prompt [$default_val]:"
    
    local input
    read -r input
    
    # Use default if empty
    if [ -z "$input" ]; then
      input="$default_val"
    fi
    
    # Validate numeric input with safe arithmetic
    if is_nonneg_int "$input" && [ "$input" -ge "$min_val" ] 2>/dev/null && [ "$input" -le "$max_val" ] 2>/dev/null; then
      # Set variable in calling scope using eval for dynamic assignment
      eval "$var_name='$input'"
      return 0
    fi
    
    warn "Please enter a number between $min_val and $max_val"
    attempts=$(add_int "$attempts" 1)
  done
  
  # Fallback after max attempts
  eval "$var_name='$default_val'"
  return 1
}

# Check if a proot-distro Linux distribution is installed
# Parameter: distro_name
# Returns: 0 if installed, 1 if not installed
is_distro_installed(){ 
  local distro="$1"
  [ -n "$distro" ] && [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$distro" ]
}

# Read non-empty input with validation (nounset-safe 3-arg variant)
# Parameters: prompt, variable_name, default_value
read_nonempty() {
  local prompt="${1:-}" var_name="${2:-}" default_val="${3:-}"
  
  if [ "$NON_INTERACTIVE" = "1" ]; then
    case "$var_name" in
      TERMUX_USERNAME) TERMUX_USERNAME="${default_val:-user}" ;;
      GIT_USERNAME) GIT_USERNAME="${default_val:-user}" ;;
      GIT_EMAIL) GIT_EMAIL="${default_val:-user@example.com}" ;;
      UBUNTU_USERNAME) UBUNTU_USERNAME="${default_val:-user}" ;;
      ip) ip="${default_val:-192.168.1.100}" ;;
      pairing_port) pairing_port="${default_val:-37831}" ;;
      pairing_code) pairing_code="${default_val:-123456}" ;;
      debug_port) debug_port="${default_val:-37832}" ;;
      *) warn "Unknown variable for read_nonempty: $var_name" ;;
    esac
    return 0
  fi
  
  local attempts=0 max_attempts=3
  while [ "$attempts" -lt "$max_attempts" ]; do
    pecho "$PASTEL_CYAN" "$prompt [${default_val:-}]:"
    
    local input
    read -r input
    
    # Use default if empty
    if [ -z "$input" ]; then
      input="$default_val"
    fi
    
    # Validate non-empty
    if [ -n "$input" ]; then
      case "$var_name" in
        TERMUX_USERNAME) TERMUX_USERNAME="$input" ;;
        GIT_USERNAME) GIT_USERNAME="$input" ;;
        GIT_EMAIL) GIT_EMAIL="$input" ;;
        UBUNTU_USERNAME) UBUNTU_USERNAME="$input" ;;
        ip) ip="$input" ;;
        pairing_port) pairing_port="$input" ;;
        pairing_code) pairing_code="$input" ;;
        debug_port) debug_port="$input" ;;
        *) warn "Unknown variable for read_nonempty: $var_name" ;;
      esac
      return 0
    fi
    
    warn "Input cannot be empty"
    attempts=$(add_int "$attempts" 1)
  done
  
  # Fallback after max attempts
  case "$var_name" in
    TERMUX_USERNAME) TERMUX_USERNAME="${default_val:-user}" ;;
    GIT_USERNAME) GIT_USERNAME="${default_val:-user}" ;;
    GIT_EMAIL) GIT_EMAIL="${default_val:-user@example.com}" ;;
    UBUNTU_USERNAME) UBUNTU_USERNAME="${default_val:-user}" ;;
    ip) ip="${default_val:-192.168.1.100}" ;;
    pairing_port) pairing_port="${default_val:-37831}" ;;
    pairing_code) pairing_code="${default_val:-123456}" ;;
    debug_port) debug_port="${default_val:-37832}" ;;
    *) warn "Using default for $var_name: ${default_val}" ;;
  esac
  return 1
}

# Ask yes/no question with timeout support
ask_yes_no() {
  local prompt="${1:-}" default="${2:-n}"
  
  if [ "$NON_INTERACTIVE" = "1" ]; then
    case "$default" in
      y|Y|yes|YES) return 0 ;;
      *) return 1 ;;
    esac
  fi
  
  local response
  pecho "$PASTEL_CYAN" "$prompt [y/N]: "
  read -r response
  
  # Use default if empty
  if [ -z "$response" ]; then
    response="$default"
  fi
  
  case "$response" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Read password with confirmation
read_password_confirm() {
  local prompt1="${1:-Enter password}" prompt2="${2:-Confirm password}" var_name="${3:-}"
  
  if [ "$NON_INTERACTIVE" = "1" ]; then
    # Generate a simple password in non-interactive mode
    local default_pass="cad$(date +%s | tail -c 4)"
    case "$var_name" in
      linux_user) store_credential "$var_name" "$default_pass" ;;
      linux_root) store_credential "$var_name" "$default_pass" ;;
    esac
    return 0
  fi
  
  local attempts=0 max_attempts=3
  while [ "$attempts" -lt "$max_attempts" ]; do
    local password confirm_password
    
    printf "%s: " "$prompt1"
    if ! read -rs password; then
      return 1
    fi
    printf "\n"
    
    # Check minimum length
    if [ "${#password}" -lt 6 ]; then
      warn "Password too short (minimum 6 characters)"
      attempts=$(add_int "$attempts" 1)
      continue
    fi
    
    printf "%s: " "$prompt2" 
    if ! read -rs confirm_password; then
      return 1
    fi
    printf "\n"
    
    if [ "$password" = "$confirm_password" ]; then
      store_credential "$var_name" "$password"
      return 0
    else
      warn "Passwords do not match. Please try again."
    fi
    
    attempts=$(add_int "$attempts" 1)
  done
  
  return 1
}

# Store credential securely
store_credential() {
  local name="$1" value="$2"
  local cred_file="$CRED_DIR/$name.cred"
  
  # Ensure credentials directory exists
  mkdir -p "$CRED_DIR" 2>/dev/null || return 1
  chmod 700 "$CRED_DIR" 2>/dev/null || return 1
  
  # Store credential with restricted permissions
  if echo "$value" > "$cred_file" 2>/dev/null; then
    chmod 600 "$cred_file" 2>/dev/null || true
    return 0
  else
    return 1
  fi
}

# Read stored credential
read_credential() {
  local name="$1"
  local cred_file="$CRED_DIR/$name.cred"
  
  if [ -f "$cred_file" ]; then
    cat "$cred_file" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# Generate random port number
random_port() {
  # Generate port in range 8000-9999
  local port=$(( (RANDOM % 2000) + 8000 ))
  echo "$port"
}

# Ask yes/no question with validation
ask_yes_no() {
  local question="${1:-}"
  local default="${2:-}"
  
  if [ "$NON_INTERACTIVE" = "1" ]; then
    case "$default" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) return 0 ;; # Default to yes in non-interactive mode
    esac
  fi
  
  local prompt="$question"
  case "$default" in
    y|Y|yes|YES) prompt="$prompt [Y/n]" ;;
    n|N|no|NO) prompt="$prompt [y/N]" ;;
    *) prompt="$prompt [y/n]" ;;
  esac
  
  local response
  while true; do
    printf "%s: " "$prompt"
    if ! read -r response; then
      return 1
    fi
    
    # Use default if empty response
    if [ -z "$response" ] && [ -n "$default" ]; then
      response="$default"
    fi
    
    case "$response" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf "Please answer yes or no.\n" ;;
    esac
  done
}

# === Environment Setup Functions ===

# Enhanced TMPDIR creation with comprehensive error handling
ensure_tmpdir() {
  # Validate TMPDIR is set and not empty
  if [ -z "${TMPDIR:-}" ]; then
    TMPDIR="$PREFIX/tmp"
  fi
  
  # Create TMPDIR with proper error handling
  if ! mkdir -p "$TMPDIR" 2>/dev/null; then
    # Try alternative locations if primary fails
    for alt_tmp in "/tmp" "$HOME/tmp" "$HOME/.tmp"; do
      if mkdir -p "$alt_tmp" 2>/dev/null; then
        TMPDIR="$alt_tmp"
        warn "Using alternative TMPDIR: $TMPDIR"
        return 0
      fi
    done
    
    err "Cannot create any temporary directory"
    return 1
  fi
  
  # Verify TMPDIR is writable
  local test_file="$TMPDIR/.cad_write_test_$$"
  if ! touch "$test_file" 2>/dev/null; then
    err "TMPDIR not writable: $TMPDIR"
    return 1
  fi
  rm -f "$test_file" 2>/dev/null
  
  return 0
}

# Safe sleep function that validates duration
safe_sleep() {
  local duration="${1:-0.1}"
  
  # Validate duration is a positive number
  if ! [[ "$duration" =~ ^[0-9]*\.?[0-9]+$ ]] || [ "${duration%.*}" -gt 10 ]; then
    duration="0.1"  # Default safe value
  fi
  
  sleep "$duration" 2>/dev/null || true
}

# === Library Detection and Installation ===

# Detect and install missing runtime libraries
# This function addresses CANNOT LINK EXECUTABLE errors for missing libraries
detect_install_missing_libs() {
  info "Checking for missing runtime libraries..."
  
  local libs_needed=()
  local test_output
  
  # Test a common binary to detect missing libraries
  test_output=$( (date >/dev/null) 2>&1 || true )
  
  # Check for libpcre2-8.so issues
  if echo "$test_output" | grep -qi 'libpcre2-8.so'; then
    libs_needed+=("pcre2")
    warn "Detected missing libpcre2-8.so library"
  fi
  
  # Check for libandroid-selinux.so dependency on libpcre2-8.so (specific xfce4 error)
  if echo "$test_output" | grep -qi 'libandroid-selinux.so.*libpcre2-8.so'; then
    if ! [[ " ${libs_needed[*]} " =~ " pcre2 " ]]; then
      libs_needed+=("pcre2")
      warn "Detected libpcre2-8.so dependency issue for libandroid-selinux.so"
    fi
  fi
  
  # Check for libgmp.so issues
  if echo "$test_output" | grep -qi 'libgmp.so'; then
    libs_needed+=("libgmp")
    warn "Detected missing libgmp.so library"
  fi
  
  # Proactive detection using ldd if available
  if command -v ldd >/dev/null 2>&1; then
    local ldd_output
    ldd_output=$(ldd /bin/date 2>&1 || true)
    
    # Check for missing libpcre2
    if echo "$ldd_output" | grep -qi "libpcre2.*not found"; then
      if ! [[ " ${libs_needed[*]} " =~ " pcre2 " ]]; then
        libs_needed+=("pcre2")
        warn "Proactive detection: libpcre2 missing"
      fi
    fi
    
    # Check for missing libgmp
    if echo "$ldd_output" | grep -qi "libgmp.*not found"; then
      if ! [[ " ${libs_needed[*]} " =~ " libgmp " ]]; then
        libs_needed+=("libgmp")
        warn "Proactive detection: libgmp missing"
      fi
    fi
  fi
  
  # Install missing libraries
  if [ ${#libs_needed[@]} -gt 0 ]; then
    # Ensure mirrors are up-to-date before installation
    if command -v ensure_mirror_applied >/dev/null 2>&1; then
      ensure_mirror_applied
    fi
    
    for lib in "${libs_needed[@]}"; do
      install_runtime_library "$lib"
    done
  else
    ok "All runtime libraries are available"
  fi
}

# Install a specific runtime library
install_runtime_library() {
  local lib="$1"
  
  case "$lib" in
    "pcre2")
      run_with_progress "Install libpcre2 (apt)" 15 bash -c 'apt install -y libpcre2-8-0 pcre2-utils >/dev/null 2>&1 || [ $? -eq 100 ]'
      ;;
    "libgmp")
      run_with_progress "Install libgmp (apt)" 15 bash -c 'apt install -y libgmp10 libgmpxx4ldbl >/dev/null 2>&1 || [ $? -eq 100 ]'
      ;;
    *)
      warn "Unknown library: $lib"
      return 1
      ;;
  esac
  
  # Verify installation
  local verify_output
  verify_output=$( (date >/dev/null) 2>&1 || true )
  if echo "$verify_output" | grep -qi "$lib"; then
    warn "Library $lib may still be missing after installation"
    return 1
  else
    ok "Library $lib installed successfully"
    return 0
  fi
}

# === Shell Configuration ===

# Configure bash prompt with pastel theming
configure_pastel_shell_prompt() {
  info "Setting up pastel shell prompt..."
  
  # Create .bashrc with pastel prompt
  cat >> "$HOME/.bashrc" << 'BASHRC_EOF'

# === CAD-Droid Pastel Shell Configuration ===

# Pastel color definitions
PASTEL_PINK='\[\033[38;2;221;160;221m\]'
PASTEL_PURPLE='\[\033[38;5;183m\]'
PASTEL_CYAN='\[\033[38;5;159m\]'
PASTEL_GREEN='\[\033[38;5;158m\]'
PASTEL_YELLOW='\[\033[38;5;229m\]'
PASTEL_LAVENDER='\[\033[38;5;189m\]'
RESET='\[\033[0m\]'

# Get username (prefer installer-set username)
if [ -n "${TERMUX_USERNAME:-}" ]; then
  DISPLAY_USER="$TERMUX_USERNAME"
elif [ -n "${USER:-}" ]; then
  DISPLAY_USER="$USER"
else
  DISPLAY_USER="cad-user"
fi

# Pastel-themed prompt: pink username, cyan directory, purple input
export PS1="${PASTEL_PINK}${DISPLAY_USER}${RESET} ${PASTEL_CYAN}\w${RESET} ${PASTEL_PURPLE}$ ${RESET}"

# Make user input appear in pastel purple
bind 'set colored-completion-prefix on'
bind 'set completion-ignore-case on'
bind 'set show-all-if-ambiguous on'
bind 'set colored-stats on'

# Set terminal colors for better visibility and pastel user input
export LS_COLORS='di=38;5;159:fi=38;5;255:ln=38;5;213:pi=38;5;229:so=38;5;183:bd=38;5;189:cd=38;5;189:or=38;5;196:ex=38;5;158'

# Configure readline for pastel user input
bind 'set colored-completion-prefix on'
bind 'set completion-ignore-case on'
bind 'set show-all-if-ambiguous on'
bind 'set colored-stats on'
bind 'set bell-style none'

# Make sure user input appears in pastel purple
export PS1="${PASTEL_PINK}${DISPLAY_USER}${RESET} ${PASTEL_CYAN}\w${RESET} ${PASTEL_PURPLE}$ ${RESET}"

# Configure input line editing colors for pastel cursor
printf '\e]12;#DCC9FF\a'

# Aliases with color support
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'

# CAD-Droid specific aliases
alias cad-status='echo -e "${PASTEL_GREEN}CAD-Droid Environment Active${RESET}"'
alias cad-help='echo -e "${PASTEL_CYAN}CAD-Droid Commands:${RESET}\n  cad-status  - Show environment status\n  cad-update  - Update system packages\n  cad-backup  - Create system backup"'
alias cad-update='pkg update && pkg upgrade'

BASHRC_EOF

  # Source the new configuration
  if [ -n "$BASH_VERSION" ]; then
    source "$HOME/.bashrc" 2>/dev/null || true
  fi
  
  # Reload Termux settings to apply new configuration
  if command -v termux-reload-settings >/dev/null 2>&1; then
    run_with_progress "Reload Termux settings" 3 termux-reload-settings
  fi
  
  ok "Pastel shell prompt configured"
}

# Configure termux.properties with pastel theme
configure_termux_properties_pastel() {
  info "Configuring Termux properties with pastel theme..."
  
  local termux_props="$HOME/.termux/termux.properties"
  mkdir -p "$HOME/.termux"
  
  # Backup existing properties
  if [ -f "$termux_props" ]; then
    cp "$termux_props" "$termux_props.backup.$(date +%s)" 2>/dev/null || true
  fi
  
  # Create pastel-themed termux.properties
  cat > "$termux_props" << 'TERMUX_PROPS_EOF'
# === CAD-Droid Pastel Termux Configuration ===

# === APPEARANCE ===
# Use a pleasant pastel color scheme with better contrast
use-black-ui=true
default-working-directory=/data/data/com.termux/files/home

# === COLORS ===
# Custom color scheme for pastel theming
color-scheme=one-dark

# === KEYBOARD ===
# Enhanced extra keys row with useful shortcuts including on-screen keyboard toggle
extra-keys = [[ \
 {key: 'ESC', popup: {macro: 'CTRL f d', display: 'tmux exit'}}, \
 {key: 'CTRL', popup: {macro: 'CTRL f CTRL n', display: 'new window'}}, \
 'ALT', \
 {key: '/', popup: '\\'}, \
 {key: 'HOME', popup: 'END'}, \
 {key: 'UP', popup: 'PGUP'}, \
 {key: 'DOWN', popup: 'PGDN'}, \
 {key: 'KEYBOARD', popup: {macro: 'CTRL a CTRL a', display: 'toggle keyboard'}} \
], [ \
 'TAB', \
 {key: 'CTRL', popup: {macro: 'CTRL f c', display: 'kill process'}}, \
 'ALT', \
 {key: '-', popup: '|'}, \
 'LEFT', \
 'RIGHT', \
 {key: '.', popup: {macro: '. . LEFT', display: '..'}}, \
 {key: 'KEYBOARD', popup: {macro: 'CTRL SHIFT SPACE', display: 'on-screen keyboard'}}, \
 {key: 'ENTER', popup: {macro: 'CTRL f z', display: 'suspend'}} \
]]

# === BELL ===
# Disable annoying terminal bell
bell-character=ignore

# === CURSOR ===
# Use a visible cursor style
terminal-cursor-style=block
terminal-cursor-blink-rate=500

# === SCROLLBACK ===
# Keep more history
terminal-transcript-rows=10000

# === HARDWARE ===
# Handle volume keys appropriately
volume-keys=volume

# === BEHAVIOR ===
# Handle back button
back-key=escape
# Handle special keys
enforce-char-based-input=true
# Handle fullscreen
fullscreen=false

TERMUX_PROPS_EOF

  ok "Termux properties configured with pastel theme"
  
  # Reload Termux settings to apply changes
  if command -v termux-reload-settings >/dev/null 2>&1; then
    run_with_progress "Reload Termux settings" 3 termux-reload-settings
    info "Restart Termux to apply new keyboard and theme settings"
  else
    info "Restart Termux to apply new keyboard and theme settings"
  fi
}

# === Final Completion ===

# Final completion with reboot prompt
cad_droid_completion(){
  printf "\n${PASTEL_PINK}CAD-Droid Setup Complete!${RESET}\n"
  printf "${PASTEL_YELLOW}========================================${RESET}\n\n"
  
  printf "${PASTEL_GREEN}Installation Summary:${RESET}\n"
  printf "${PASTEL_CYAN}+= ${RESET} Critical bug fixes applied\n"
  printf "${PASTEL_CYAN}+= ${RESET} Pastel theme configured\n"  
  printf "${PASTEL_CYAN}+= ${RESET} APK management system ready\n"
  printf "${PASTEL_CYAN}+= ${RESET} ADB wireless setup completed\n"
  printf "${PASTEL_CYAN}+= ${RESET} Phantom process killer disabled\n"
  printf "${PASTEL_CYAN}+= ${RESET} Widget shortcuts created\n"
  printf "${PASTEL_CYAN}+= ${RESET} Container support installed\n"
  printf "${PASTEL_CYAN}+= ${RESET} XFCE desktop environment ready\n\n"
  
  printf "${PASTEL_YELLOW}Quick Start Guide:${RESET}\n"
  printf "${PASTEL_CYAN}1.${RESET} Add Termux widgets to home screen (especially phantom-killer)\n"
  printf "${PASTEL_CYAN}2.${RESET} Start XFCE desktop: ~/.cad/scripts/start-xfce-termux.sh\n" 
  printf "${PASTEL_CYAN}3.${RESET} Access Ubuntu container: proot-distro login ubuntu\n"
  printf "${PASTEL_CYAN}4.${RESET} Check system status: cad-status\n\n"
  
  printf "${PASTEL_RED}Reboot Recommended${RESET}\n"
  printf "A reboot will ensure all configuration changes take effect,\n"
  printf "especially the new keyboard layout and theme settings.\n\n"
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    printf "${PASTEL_PINK}Press Enter to reboot Termux now...${RESET} "
    read -r || true
    
    printf "\n${PASTEL_YELLOW}Rebooting Termux...${RESET}\n"
    sleep 2
    
    # Kill current Termux process to trigger restart
    am force-stop com.termux 2>/dev/null || killall -9 com.termux 2>/dev/null || exit 0
  else
    printf "${PASTEL_YELLOW}Non-interactive mode: Skipping reboot${RESET}\n"
    printf "Please restart Termux manually to apply all changes.\n"
  fi
}

# === Git and SSH Configuration ===

# Configure git with user settings
configure_git_settings(){
  info "Configuring Git settings..."
  
  # Check if git is installed
  if ! command -v git >/dev/null 2>&1; then
    warn "Git not installed, installing first..."
    if ! apt_install_if_needed git; then
      err "Failed to install git"
      return 1
    fi
  fi
  
  # Verify git is now available
  if ! command -v git >/dev/null 2>&1; then
    err "Git still not available after installation"
    return 1
  fi
  
  # Set up basic git configuration if not already set
  if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
    local git_username="${GIT_USERNAME:-CAD-Droid User}"
    run_with_progress "Set Git username" 5 git config --global user.name "$git_username"
  fi
  
  if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
    local git_email="${GIT_EMAIL:-cad-droid@termux.local}"
    run_with_progress "Set Git email" 5 git config --global user.email "$git_email"
  fi
  
  # Set up git to use main branch by default
  run_with_progress "Configure Git defaults" 5 bash -c '
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global core.autocrlf input
  '
  
  ok "Git configuration completed"
}

# Set up SSH keys for secure connections
setup_ssh_keys(){
  info "Setting up SSH keys..."
  
  local ssh_dir="$HOME/.ssh"
  local ssh_key="$ssh_dir/id_ed25519"
  
  # Create SSH directory if it doesn't exist
  mkdir -p "$ssh_dir" 2>/dev/null || true
  chmod 700 "$ssh_dir" 2>/dev/null || true
  
  # Check if SSH key already exists
  if [ -f "$ssh_key" ]; then
    warn "SSH key already exists at $ssh_key"
    if [ "$NON_INTERACTIVE" != "1" ]; then
      printf "${PASTEL_PINK}Overwrite existing SSH key? (y/N):${RESET} "
      local response
      read -r response || response="n"
      case "${response,,}" in
        y|yes)
          info "Overwriting existing SSH key..."
          rm -f "$ssh_key" "$ssh_key.pub" 2>/dev/null || true
          ;;
        *)
          ok "Using existing SSH key"
          return 0
          ;;
      esac
    else
      ok "Using existing SSH key (non-interactive mode)"
      return 0
    fi
  fi
  
  # Generate SSH key
  local ssh_email="${GIT_EMAIL:-cad-droid@termux.local}"
  if run_with_progress "Generate SSH key" 10 bash -c "
    ssh-keygen -t ed25519 -C '$ssh_email' -f '$ssh_key' -N '' >/dev/null 2>&1
  "; then
    chmod 600 "$ssh_key" 2>/dev/null || true
    chmod 644 "${ssh_key}.pub" 2>/dev/null || true
    ok "SSH key pair generated successfully"
    
    # Show public key for user
    printf "\n${PASTEL_YELLOW}Your SSH public key:${RESET}\n"
    printf "${PASTEL_CYAN}"
    cat "${ssh_key}.pub" 2>/dev/null || echo "Error reading public key"
    printf "${RESET}\n\n"
    printf "${PASTEL_LAVENDER}Add this key to GitHub/GitLab under Settings → SSH Keys${RESET}\n\n"
  else
    warn "Failed to generate SSH key"
    return 1
  fi
  
  return 0
}

# === Installation Management ===

# Installation flag to track CAD-Droid installation attempts
readonly INSTALL_FLAG_FILE="$HOME/.cad/cad_droid_installed"
readonly INSTALL_COMPLETE_FLAG="$HOME/.cad/install_complete"

# Set installation flag at the beginning of install
set_install_flag(){
  info "Setting permanent installation flag..."
  mkdir -p "$(dirname "$INSTALL_FLAG_FILE")" 2>/dev/null || true
  echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$INSTALL_FLAG_FILE"
  export CAD_DROID_INSTALLING=1
}

# Mark installation as complete and update permanent flag
clear_install_flag(){
  # Update the permanent install flag with completion date
  echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$INSTALL_COMPLETE_FLAG"
  echo "Installation completed: $(date '+%Y-%m-%d %H:%M:%S')" >> "$INSTALL_FLAG_FILE"
  # Keep CAD_DROID_INSTALLING for current session but don't unset globally
}

# Check for previous CAD-Droid installation
check_previous_install(){
  info "Checking for previous CAD-Droid installation..."
  
  # Check for permanent installation flag
  if [ -f "$INSTALL_FLAG_FILE" ]; then
    local flag_content
    flag_content=$(cat "$INSTALL_FLAG_FILE" 2>/dev/null || echo "")
    
    # Check if this is a completed installation (contains "Installation completed")
    if echo "$flag_content" | grep -q "Installation completed"; then
      local install_date completion_date
      install_date=$(echo "$flag_content" | head -1)
      completion_date=$(echo "$flag_content" | grep "Installation completed" | head -1 | cut -d':' -f2- | sed 's/^ *//')
      
      warn "Previous CAD-Droid installation detected (completed: $completion_date)"
      
      if [ "$NON_INTERACTIVE" != "1" ]; then
        printf "\n${PASTEL_YELLOW}Previous CAD-Droid installation found!${RESET}\n"
        printf "${PASTEL_CYAN}Installation was completed on: $completion_date${RESET}\n\n"
        
        # Enhanced cleanup options
        printf "${PASTEL_PURPLE}Choose cleanup option:${RESET}\n"
        printf "${PASTEL_CYAN}  1) Conservative clean (remove main installation files only)${RESET}\n"
        printf "${PASTEL_CYAN}  2) Deep clean (remove everything that would be installed/downloaded)${RESET}\n"
        printf "${PASTEL_CYAN}  3) No cleaning (continue with existing files)${RESET}\n"
        printf "${PASTEL_PINK}Select option [1-3]:${RESET} "
        
        local cleanup_choice
        read -r cleanup_choice || cleanup_choice="3"
        
        case "$cleanup_choice" in
          1)
            printf "\n${PASTEL_YELLOW}Conservative cleanup will remove main CAD-Droid files but preserve system configurations.${RESET}\n"
            printf "${PASTEL_PINK}Proceed with conservative cleanup? (y/N):${RESET} "
            local confirm
            read -r confirm || confirm="n"
            case "${confirm,,}" in
              y|yes)
                cleanup_previous_install "conservative"
                info "Conservative cleanup completed - continuing with fresh installation"
                ;;
              *)
                info "Cleanup cancelled - continuing with existing files"
                ;;
            esac
            ;;
          2)
            printf "\n${PASTEL_YELLOW}Deep cleanup will remove ALL files that would be installed or downloaded by CAD-Droid.${RESET}\n"
            printf "${PASTEL_CYAN}This includes proot-distro containers, apt caches, downloaded packages, and system configurations.${RESET}\n"
            printf "${PASTEL_PINK}Proceed with deep cleanup? (y/N):${RESET} "
            local confirm
            read -r confirm || confirm="n"
            case "${confirm,,}" in
              y|yes)
                cleanup_previous_install "deep"
                info "Deep cleanup completed - continuing with fresh installation"
                ;;
              *)
                info "Cleanup cancelled - continuing with existing files"
                ;;
            esac
            ;;
          3|*)
            info "No cleanup selected - continuing with existing files"
            ;;
        esac
      else
        warn "Previous installation found - continuing anyway (non-interactive mode)"
      fi
    else
      # This is an incomplete installation (no completion marker)
      local flag_date
      flag_date=$(echo "$flag_content" | head -1)
      warn "Incomplete installation attempt detected (started: $flag_date)"
      
      if [ "$NON_INTERACTIVE" != "1" ]; then
        # Single confirmation prompt for incomplete installation cleanup
        printf "\n${PASTEL_YELLOW}Incomplete installation detected!${RESET}\n"
        printf "${PASTEL_CYAN}This may indicate a previous installation was interrupted.${RESET}\n"
        printf "${PASTEL_PINK}Remove previous installation files and start fresh? (y/N):${RESET} "
        local response
        read -r response || response="n"
        case "${response,,}" in
          y|yes)
            cleanup_previous_install "conservative"
            info "Previous installation cleaned up - continuing with fresh installation"
            ;;
          *)
            info "Continuing with existing installation state"
            ;;
        esac
      else
        warn "Incomplete installation found - continuing anyway (non-interactive mode)"
      fi
    fi
  fi
  
  # If no install flag found, check for other markers
  # Enhanced detection of installation markers
  local install_markers=(
    "$HOME/.cad"
    "$HOME/.shortcuts/phantom-killer"
    "$HOME/.shortcuts/adb-connect" 
    "$HOME/.shortcuts/system-info"
    "$HOME/.shortcuts/file-manager"
    "$HOME/.shortcuts/Linux Desktop"
    "$HOME/.shortcuts/Linux Sunshine"
    "$HOME/.termux/boot/disable-phantom-killer.sh"
    "$PREFIX/etc/motd"
    "$HOME/.bashrc_cad_completion"
    "$HOME/.local/bin/cad-droid"
    "$HOME/.config/xfce4"
    "$HOME/.proot-distro"
  )
  
  # Also check for APK installer files
  local apk_markers=(
    "/storage/emulated/0/Download/CAD-Droid-APKs"
    "$HOME/.cad/apks"
    "$HOME/.cad/apk-state"
  )
  
  local found_markers=()
  local found_apk_files=()
  local found=false
  local apk_files_found=false
  
  for marker in "${install_markers[@]}"; do
    if [ -e "$marker" ]; then
      found_markers+=("$marker")
      found=true
    fi
  done
  
  for apk_marker in "${apk_markers[@]}"; do
    if [ -e "$apk_marker" ]; then
      found_apk_files+=("$apk_marker")
      apk_files_found=true
      found=true
    fi
  done
  
  if [ "$found" = true ]; then
    printf "\n${PASTEL_YELLOW}Previous CAD-Droid installation detected!${RESET}\n\n"
    
    if [ ${#found_markers[@]} -gt 0 ]; then
      printf "${PASTEL_CYAN}Found installation files:${RESET}\n"
      for marker in "${found_markers[@]}"; do
        printf "${PASTEL_LAVENDER}  - %s${RESET}\n" "$marker"
      done
    fi
    
    if [ ${#found_apk_files[@]} -gt 0 ]; then
      printf "\n${PASTEL_CYAN}Found APK installer files:${RESET}\n"
      for apk_file in "${found_apk_files[@]}"; do
        local apk_count=""
        if [ -d "$apk_file" ]; then
          apk_count=$(find "$apk_file" -name "*.apk" -type f 2>/dev/null | wc -l)
          if [ "$apk_count" -gt 0 ]; then
            apk_count=" ($apk_count APK files)"
          else
            apk_count=""
          fi
        fi
        printf "${PASTEL_LAVENDER}  - %s${apk_count}${RESET}\n" "$apk_file"
      done
    fi
    
    printf "\n"
    
    if [ "$NON_INTERACTIVE" != "1" ]; then
      printf "${PASTEL_PINK}Would you like to clean up ALL previous installation files?${RESET}\n"
      printf "${PASTEL_YELLOW}This will remove CAD-Droid configurations, APKs, containers, and shortcuts.${RESET}\n"
      printf "\n${PASTEL_PINK}   Delete all previous CAD-Droid files? (y/N):${RESET} "
      local cleanup_response
      read -r cleanup_response || cleanup_response="n"
      case "${cleanup_response,,}" in
        y|yes)
          # Single confirmation prompt
          printf "\n${PASTEL_PINK}Are you absolutely sure? (y/N):${RESET} "
          local final_confirm
          read -r final_confirm || final_confirm="n"
          case "${final_confirm,,}" in
            y|yes)
              cleanup_previous_install
              ;;
            *)
              info "Cleanup cancelled - continuing with fresh installation alongside existing files"
              ;;
          esac
          ;;
        *)
          info "Continuing with fresh installation alongside existing files"
          ;;
      esac
    else
      warn "Previous installation found - continuing anyway (non-interactive mode)"
    fi
  else
    ok "No previous installation detected"
  fi
}

# Clean up previous CAD-Droid installation files
cleanup_previous_install(){
  local cleanup_type="${1:-conservative}"
  
  if [ "$cleanup_type" = "conservative" ]; then
    info "Performing conservative cleanup of previous installation..."
  else
    info "Performing deep cleanup of previous installation..."
  fi
  
  # Temporarily disable exit on error for cleanup operations
  set +e
  
  # Conservative cleanup items (main CAD-Droid files)
  local conservative_cleanup_items=(
    "$HOME/.cad"
    "$HOME/.shortcuts"
    "$HOME/.termux/boot/disable-phantom-killer.sh"
    "$HOME/.termux/boot/phantom-killer.log"
    "$PREFIX/etc/motd"
    "$HOME/.bashrc_cad_completion"
    "$HOME/.local/bin/cad-droid"
    "/storage/emulated/0/Download/CAD-Droid-APKs"
  )
  
  # Deep cleanup items (everything that would be installed/downloaded)
  local deep_cleanup_items=(
    "$HOME/.config/xfce4"
    "$HOME/.proot-distro"
    "$PREFIX/var/lib/proot-distro"
    "$PREFIX/var/lib/apt/lists"
    "$PREFIX/var/cache/apt"
    "$PREFIX/tmp"
    "$HOME/.cache"
    "$PREFIX/var/lib/dpkg"
    "$PREFIX/share/applications"
    "$PREFIX/share/pixmaps"
    "$PREFIX/etc/pulse"
    "$PREFIX/lib/pulse*"
    "$PREFIX/bin/pulseaudio"
    "$PREFIX/bin/startxfce4"
    "$PREFIX/bin/xfce4*"
    "$PREFIX/share/xfce4"
    "$PREFIX/etc/xdg/xfce4"
  )
  
  local cleanup_items=()
  
  # Select cleanup items based on type
  if [ "$cleanup_type" = "deep" ]; then
    cleanup_items=("${conservative_cleanup_items[@]}" "${deep_cleanup_items[@]}")
  else
    cleanup_items=("${conservative_cleanup_items[@]}")
  fi
  
  local cleaned_count=0
  local total_size=0
  
  # Clean up configuration files only in deep mode
  if [ "$cleanup_type" = "deep" ]; then
    local config_files=(
      "$HOME/.bashrc"
      "$HOME/.termux/termux.properties" 
      "$HOME/.termux/colors.properties"
      "$HOME/.termux/font.ttf"
      "$HOME/.nanorc"
      "$PREFIX/etc/nanorc"
    )
    
    for config_file in "${config_files[@]}"; do
      if [ -f "$config_file" ]; then
        local config_size
        config_size=$(du -sb "$config_file" 2>/dev/null | cut -f1) || config_size=0
        total_size=$((total_size + config_size))
        if rm -f "$config_file" 2>/dev/null; then
          cleaned_count=$((cleaned_count + 1))
          debug "Removed config file: $config_file"
        else
          warn "Failed to remove config file: $config_file"
        fi
      fi
    done
  fi
  
  # Clean up main installation files
  for item in "${cleanup_items[@]}"; do
    if [ -e "$item" ]; then
      local size
      size=$(du -sb "$item" 2>/dev/null | cut -f1) || size=0
      total_size=$((total_size + size))
      if rm -rf "$item" 2>/dev/null; then
        cleaned_count=$((cleaned_count + 1))
        debug "Removed: $item"
      else
        warn "Failed to remove: $item"
      fi
    fi
  done
  
  # Deep cleanup: Remove installed packages that would be installed by CAD-Droid
  if [ "$cleanup_type" = "deep" ]; then
    info "Removing packages that would be installed by CAD-Droid..."
    
    # List of packages typically installed by CAD-Droid
    local cad_packages=(
      "proot-distro"
      "xfce4"
      "tigervnc"
      "pulseaudio"
      "git"
      "wget"
      "curl"
      "nano"
      "termux-api"
      "python"
      "nodejs"
      "openssh"
      "rsync"
    )
    
    for pkg in "${cad_packages[@]}"; do
      if pkg list-installed 2>/dev/null | grep -q "^${pkg}/"; then
        if pkg uninstall -y "$pkg" 2>/dev/null; then
          debug "Uninstalled package: $pkg"
          cleaned_count=$((cleaned_count + 1))
        else
          debug "Failed to uninstall package: $pkg"
        fi
      fi
    done
    
    # Clean apt caches and update indexes
    if apt-get clean 2>/dev/null; then
      debug "Cleaned apt cache"
    fi
    
    if apt-get update >/dev/null 2>&1; then
      debug "Updated package indexes after cleanup"
    fi
    
    # Deep cleanup: Remove proot-distro containers and data
    info "Removing proot-distro containers and data..."
    if command -v proot-distro >/dev/null 2>&1; then
      # List and remove all installed distributions
      local installed_distros
      installed_distros=$(proot-distro list --installed 2>/dev/null | grep -E '^[a-z]+$' || true)
      if [ -n "$installed_distros" ]; then
        while IFS= read -r distro; do
          if [ -n "$distro" ]; then
            info "Removing proot-distro container: $distro"
            if proot-distro remove "$distro" --force 2>/dev/null; then
              debug "Removed proot-distro container: $distro"
              cleaned_count=$((cleaned_count + 1))
            else
              warn "Failed to remove proot-distro container: $distro"
            fi
          fi
        done <<< "$installed_distros"
      fi
    fi
  fi
  
  # Clean up APK installer files and cache if the function exists
  if command -v cleanup_apk_installer_files >/dev/null 2>&1; then
    cleanup_apk_installer_files || true
  else
    # Fallback APK cleanup if the dedicated function isn't available
    local apk_cleanup_items=(
      "/storage/emulated/0/Download/CAD-Droid-APKs"
      "$HOME/.cad/apks"
      "$HOME/.cad/apk-state"
    )
    
    for apk_item in "${apk_cleanup_items[@]}"; do
      if [ -e "$apk_item" ]; then
        local apk_size
        apk_size=$(du -sb "$apk_item" 2>/dev/null | cut -f1) || apk_size=0
        total_size=$((total_size + apk_size))
        if rm -rf "$apk_item" 2>/dev/null; then
          cleaned_count=$((cleaned_count + 1))
          debug "Removed APK files: $apk_item"
        else
          warn "Failed to remove APK files: $apk_item"
        fi
      fi
    done
  fi
  
  # Clean up any remaining cache files in temp directories
  local temp_patterns=("$TMPDIR/cad*" "$TMPDIR/*apk*" "$TMPDIR/fdroid*")
  for temp_pattern in "${temp_patterns[@]}"; do
    for temp_file in $temp_pattern; do
      if [ -e "$temp_file" ] 2>/dev/null; then
        local temp_size
        temp_size=$(du -sb "$temp_file" 2>/dev/null | cut -f1) || temp_size=0
        total_size=$((total_size + temp_size))
        if rm -rf "$temp_file" 2>/dev/null; then
          cleaned_count=$((cleaned_count + 1))
          debug "Removed cache: $temp_file"
        fi
      fi
    done
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
  
  if [ "$cleanup_type" = "deep" ]; then
    ok "Deep cleanup completed - removed $cleaned_count items ($size_display)"
  else
    ok "Conservative cleanup completed - removed $cleaned_count items ($size_display)"
  fi
  
  # Re-enable exit on error
  set -e
}

# Text wrapping function that breaks on word boundaries
wrap_text() {
  local text="$1"
  local width="${2:-80}"
  
  # Simple word wrapping - split on spaces and rebuild lines
  local words line_length current_line=""
  
  # Convert text to array of words
  words=$(echo "$text" | tr ' ' '\n')
  
  while IFS= read -r word; do
    if [ -z "$word" ]; then
      continue
    fi
    
    # Calculate length if we add this word
    local test_line
    if [ -z "$current_line" ]; then
      test_line="$word"
    else
      test_line="$current_line $word"
    fi
    
    # Check if adding this word would exceed width
    if [ "${#test_line}" -le "$width" ]; then
      current_line="$test_line"
    else
      # Print current line and start new one
      [ -n "$current_line" ] && echo "$current_line"
      current_line="$word"
    fi
  done <<< "$words"
  
  # Print final line if not empty
  [ -n "$current_line" ] && echo "$current_line"
}
