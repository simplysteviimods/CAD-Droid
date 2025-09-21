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
  
  # Check maximum length first
  if [ ${#input} -gt $MAX_INPUT_LENGTH ]; then
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
  local prompt="$1"
  local var_name="$2" 
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
  local prompt="$1" var_name="$2" min_val="$3" max_val="$4" default_val="$5"
  
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
    case "$var_name" in
      sel) sel="$default_val" ;;
      *) warn "Unknown variable for read_option: $var_name" ;;
    esac
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
      case "$var_name" in
        sel) sel="$input" ;;
        *) warn "Unknown variable for read_option: $var_name" ;;
      esac
      return 0
    fi
    
    warn "Please enter a number between $min_val and $max_val"
    attempts=$(add_int "$attempts" 1)
  done
  
  # Fallback after max attempts
  case "$var_name" in
    sel) sel="$default_val" ;;
    *) warn "Using default for $var_name: $default_val" ;;
  esac
  return 1
}

# Check if a proot-distro Linux distribution is installed
# Parameter: distro_name
# Returns: 0 if installed, 1 if not installed
is_distro_installed(){ 
  local distro="$1"
  [ -n "$distro" ] && [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$distro" ]
}

# Read non-empty input with validation
# Parameters: prompt, variable_name, default_value
read_nonempty() {
  local prompt="$1" var_name="$2" default_val="$3"
  
  if [ "$NON_INTERACTIVE" = "1" ]; then
    case "$var_name" in
      TERMUX_USERNAME) TERMUX_USERNAME="${default_val:-user}" ;;
      GIT_USERNAME) GIT_USERNAME="${default_val:-user}" ;;
      GIT_EMAIL) GIT_EMAIL="${default_val:-user@example.com}" ;;
      UBUNTU_USERNAME) UBUNTU_USERNAME="${default_val:-user}" ;;
      *) warn "Unknown variable for read_nonempty: $var_name" ;;
    esac
    return 0
  fi
  
  local attempts=0 max_attempts=3
  while [ "$attempts" -lt "$max_attempts" ]; do
    pecho "$PASTEL_CYAN" "$prompt [$default_val]:"
    
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
    *) warn "Using default for $var_name: ${default_val}" ;;
  esac
  return 1
}

# Ask yes/no question with timeout support
ask_yes_no() {
  local prompt="$1" default="${2:-n}"
  
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
  local prompt1="$1" prompt2="$2" var_name="$3"
  
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
    printf "\\n"
    
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
    printf "\\n"
    
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
  local question="$1"
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