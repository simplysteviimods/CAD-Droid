#!/usr/bin/env bash
# input.sh - Input validation and user interaction functions with proper variable initialization
# This module handles all user input, validation, and interactive prompts

# Prevent multiple sourcing
if [[ "${CAD_INPUT_LOADED:-}" == "1" ]]; then
    return 0
fi
export CAD_INPUT_LOADED=1

# Source required modules
# Use SCRIPT_DIR from main script if available, otherwise determine it
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# If we're in the lib directory, look for modules there
if [[ "$(basename "$SCRIPT_DIR")" == "lib" ]]; then
  source "$SCRIPT_DIR/colors.sh"
  source "$SCRIPT_DIR/utils.sh"
else
  source "$SCRIPT_DIR/lib/colors.sh"
  source "$SCRIPT_DIR/lib/utils.sh"
fi

# Credential storage directory - ensure it's initialized
export CRED_DIR="${CRED_DIR:-${TERMUX_HOME:-$HOME}/.cad-credentials}"

# Input validation constants - ensure they're available with fallbacks
export INPUT_MAX_ATTEMPTS="${INPUT_MAX_ATTEMPTS:-3}"
export INPUT_TIMEOUT="${INPUT_TIMEOUT:-30}"

# User variables with safe defaults - ensure all are initialized
export TERMUX_USERNAME="${TERMUX_USERNAME:-$(get_username)}"
export GIT_USERNAME="${GIT_USERNAME:-}"
export GIT_EMAIL="${GIT_EMAIL:-}"
export UBUNTU_USERNAME="${UBUNTU_USERNAME:-developer}"
export DISTRO="${DISTRO:-ubuntu}"

# Read non-empty input from user with validation
read_nonempty(){
  local prompt="${1:-Enter value}" 
  local var_name="${2:-TEMP_VAR}" 
  local default_val="${3:-}" 
  local validation_type="${4:-username}"
  
  local attempts=0
  local max_attempts="${INPUT_MAX_ATTEMPTS:-3}"
  local validation_regex="${ALLOWED_USERNAME_REGEX:-^[A-Za-z][A-Za-z0-9_-]{0,31}$}"
  
  # Validate function parameters
  if [ -z "$var_name" ]; then
    warn "read_nonempty: variable name required"
    return 1
  fi
  
  # Validate variable name contains only safe characters
  if ! echo "$var_name" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; then
    warn "read_nonempty: invalid variable name format"
    return 1
  fi
  
  # Set validation pattern based on type with proper fallbacks
  case "$validation_type" in
    username) 
      validation_regex="${ALLOWED_USERNAME_REGEX:-^[A-Za-z][A-Za-z0-9_-]{0,31}$}"
      ;;
    email) 
      validation_regex="${ALLOWED_EMAIL_REGEX:-^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$}"
      ;;  
    filename) 
      validation_regex="${ALLOWED_FILENAME_REGEX:-^[A-Za-z0-9._-]{1,64}$}"
      ;;
    hostname)
      validation_regex="${ALLOWED_HOSTNAME_REGEX:-^[A-Za-z0-9.-]{1,253}$}"
      ;;
    *) 
      validation_regex="${ALLOWED_USERNAME_REGEX:-^[A-Za-z][A-Za-z0-9_-]{0,31}$}"
      ;;
  esac
  
  # Auto-fill in non-interactive mode
  if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
    if [ -n "$default_val" ]; then
      export "$var_name"="$default_val"
      info "Using default for $prompt: $default_val"
      return 0
    else
      # Generate a reasonable default based on type
      local auto_default
      case "$validation_type" in
        username) auto_default="caduser" ;;
        email) auto_default="user@example.com" ;;
        filename) auto_default="default.txt" ;;
        hostname) auto_default="localhost" ;;
        *) auto_default="default" ;;
      esac
      export "$var_name"="$auto_default"
      info "Using auto-generated default for $prompt: $auto_default"
      return 0
    fi
  fi
  
  # Interactive input loop
  while [ "$attempts" -lt "$max_attempts" ]; do
    # Show prompt with default if available
    if [ -n "$default_val" ]; then
      pecho "${PASTEL_CYAN:-\033[96m}" "$prompt [$default_val]:"
    else
      pecho "${PASTEL_CYAN:-\033[96m}" "$prompt:"
    fi
    
    # Read user input with timeout if supported
    local input=""
    if command -v read >/dev/null 2>&1 && read -t 1 >/dev/null 2>&1 </dev/null; then
      read -r -t "${INPUT_TIMEOUT:-30}" input 2>/dev/null || input=""
    else
      read -r input 2>/dev/null || input=""
    fi
    
    # Use default if input is empty
    if [ -z "$input" ] && [ -n "$default_val" ]; then
      input="$default_val"
    fi
    
    # Validate input
    if [ -n "$input" ] && validate_input "$input" "$validation_regex" "$prompt" "${MAX_INPUT_LENGTH:-64}"; then
      export "$var_name"="$input"
      return 0
    fi
    
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      warn "Maximum attempts reached for $prompt"
      return 1
    fi
    
    warn "Please try again ($attempts/$max_attempts attempts used)"
  done
  
  return 1
}

# Secure password input with confirmation
secure_password_input(){
  local prompt="${1:-Enter password}" 
  local confirm="${2:-Confirm password}" 
  local var_name="${3:-PASSWORD}"
  
  local pw="" pw2="" tries=0 
  local max_tries="${INPUT_MAX_ATTEMPTS:-3}"
  local min_length="${MIN_PASSWORD_LENGTH:-8}"
  
  # Validate variable name
  if [ -z "$var_name" ] || ! echo "$var_name" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; then
    warn "secure_password_input: invalid variable name"
    return 1
  fi
  
  # Auto-generate password in non-interactive mode
  if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
    pw=$(generate_password 12 2>/dev/null || echo "defaultpass123")
    
    # Save the generated password
    if store_credential "$var_name" "$pw"; then
      info "Generated secure password for $prompt"
      return 0
    else
      warn "Failed to store auto-generated password"
      return 1
    fi
  fi
  
  # Interactive password input
  while [ "$tries" -lt "$max_tries" ]; do
    pecho "${PASTEL_CYAN:-\033[96m}" "$prompt:"
    
    # Read password securely
    if read -rs pw 2>/dev/null; then
      echo  # Add newline after hidden input
    else
      warn "Failed to read password securely"
      tries=$((tries + 1))
      continue
    fi
    
    # Check minimum length
    if [ "${#pw}" -lt "$min_length" ]; then
      warn "Password must be at least $min_length characters"
      tries=$((tries + 1))
      continue
    fi
    
    pecho "${PASTEL_CYAN:-\033[96m}" "$confirm:"
    
    # Read confirmation password
    if read -rs pw2 2>/dev/null; then
      echo  # Add newline after hidden input
    else
      warn "Failed to read password confirmation"
      tries=$((tries + 1))
      continue
    fi
    
    # Check if passwords match
    if [ "$pw" = "$pw2" ]; then
      # Save password securely
      if store_credential "$var_name" "$pw"; then
        ok "Password set successfully"
        # Clear passwords from memory
        pw="" pw2=""
        return 0
      else
        warn "Failed to store password securely"
        pw="" pw2=""
        return 1
      fi
    else
      warn "Passwords do not match"
    fi
    
    # Clear passwords from memory
    pw="" pw2=""
    
    tries=$((tries + 1))
    if [ "$tries" -lt "$max_tries" ]; then
      warn "Please try again ($tries/$max_tries attempts used)"
    fi
  done
  
  warn "Maximum password attempts exceeded"
  return 1
}

# Store credential securely
store_credential(){
  local var_name="${1:-}" password="${2:-}"
  
  if [ -z "$var_name" ] || [ -z "$password" ]; then
    warn "store_credential: variable name and password required"
    return 1
  fi
  
  # Validate variable name
  if ! echo "$var_name" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; then
    warn "store_credential: invalid variable name format"
    return 1
  fi
  
  # Ensure credential directory exists
  mkdir -p "${CRED_DIR}" 2>/dev/null || {
    warn "Failed to create credential directory: ${CRED_DIR}"
    return 1
  }
  
  # Set secure permissions on credential directory
  chmod 700 "${CRED_DIR}" 2>/dev/null || true
  
  # Save password to secure credential file
  local credential_file="${CRED_DIR}/${var_name}_password"
  
  # Set restrictive umask for file creation
  local old_umask
  old_umask=$(umask)
  umask 077
  
  # Write credential file
  if printf "%s" "$password" > "$credential_file" 2>/dev/null; then
    chmod 600 "$credential_file" 2>/dev/null || true
    umask "$old_umask"
    return 0
  else
    umask "$old_umask"
    warn "Failed to write credential file: $credential_file"
    return 1
  fi
}

# Read a stored credential from secure storage
read_credential(){
  local name="${1:-}"
  
  if [ -z "$name" ]; then
    warn "read_credential: credential name required"
    return 1
  fi
  
  # Validate credential name
  if ! echo "$name" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; then
    warn "read_credential: invalid credential name format"
    return 1
  fi
  
  local credential_file="${CRED_DIR}/${name}_password"
  
  if [ -f "$credential_file" ] && [ -r "$credential_file" ]; then
    cat "$credential_file" 2>/dev/null || true
  else
    return 1
  fi
}

# Ask user a yes/no question with default answer
ask_yes_no(){
  local question="${1:-Continue?}" 
  local default="${2:-n}" 
  local answer=""
  local attempts=0 
  local max_attempts="${INPUT_MAX_ATTEMPTS:-3}"
  
  # Normalize default
  case "$default" in
    y|Y|yes|YES|1) default="y" ;;
    *) default="n" ;;
  esac
  
  # Auto-answer in non-interactive mode
  if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
    case "$default" in
      y|Y|yes|YES) 
        info "Auto-answering yes to: $question"
        return 0 
        ;;
      *) 
        info "Auto-answering no to: $question"
        return 1 
        ;;
    esac
  fi
  
  # Interactive prompt with safe attempt counting
  while [ "$attempts" -lt "$max_attempts" ]; do
    if [ "$default" = "y" ]; then
      printf "%s [Y/n]: " "$question"
    else
      printf "%s [y/N]: " "$question"
    fi
    
    # Read answer with timeout if supported
    if command -v read >/dev/null 2>&1 && read -t 1 >/dev/null 2>&1 </dev/null; then
      read -r -t "${INPUT_TIMEOUT:-30}" answer 2>/dev/null || answer=""
    else
      read -r answer 2>/dev/null || answer=""
    fi
    
    # Use default if no answer provided
    if [ -z "$answer" ]; then
      answer="$default"
    fi
    
    case "$answer" in
      y|Y|yes|YES|1) return 0 ;;
      n|N|no|NO|0) return 1 ;;
      *) 
        warn "Please answer y or n"
        attempts=$((attempts + 1))
        if [ "$attempts" -ge "$max_attempts" ]; then
          warn "Using default answer: $default"
          case "$default" in
            y|Y|yes|YES) return 0 ;;
            *) return 1 ;;
          esac
        fi
        ;;
    esac
  done
  
  return 1
}

# Show countdown prompt with auto-continue option
countdown_prompt(){
  local prompt="${1:-Continuing in}" 
  local timeout="${2:-10}" 
  local auto_msg="${3:-Auto-continuing...}"
  
  # Validate timeout is numeric and within reasonable bounds
  case "$timeout" in
    *[!0-9]*) timeout=10 ;;
    *) 
      if [ "$timeout" -lt 1 ]; then timeout=10; fi
      if [ "$timeout" -gt 300 ]; then timeout=300; fi
      ;;
  esac
  
  pecho "${PASTEL_CYAN:-\033[96m}" "$prompt"
  
  local remaining="$timeout"
  while [ "$remaining" -gt 0 ]; do
    printf "\rContinuing in %2ds (Enter to proceed immediately) " "$remaining"
    
    # Wait 1 second or until user presses Enter
    if read -r -t 1 2>/dev/null; then 
      echo
      return 0
    fi
    
    remaining=$((remaining - 1))
  done
  
  echo
  if [ -n "$auto_msg" ]; then
    info "$auto_msg"
  fi
  return 1
}

# Present multiple choice options to user
read_option(){
  local prompt="${1:-Select an option}"
  shift
  local options=("$@")
  local choice=""
  local attempts=0
  local max_attempts="${INPUT_MAX_ATTEMPTS:-3}"
  
  if [ "${#options[@]}" -eq 0 ]; then
    warn "read_option: no options provided"
    return 1
  fi
  
  # Auto-select first option in non-interactive mode
  if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
    info "Auto-selecting: ${options[0]}"
    echo "0"
    return 0
  fi
  
  # Display options
  pecho "${PASTEL_CYAN:-\033[96m}" "$prompt"
  local i=0
  for option in "${options[@]}"; do
    pecho "${PASTEL_GREEN:-\033[92m}" "  $i) $option"
    i=$((i + 1))
  done
  
  # Get user choice
  while [ "$attempts" -lt "$max_attempts" ]; do
    pecho "${PASTEL_CYAN:-\033[96m}" "Select option [0-$((${#options[@]} - 1))]:"
    
    # Read choice with timeout if supported
    if command -v read >/dev/null 2>&1 && read -t 1 >/dev/null 2>&1 </dev/null; then
      read -r -t "${INPUT_TIMEOUT:-30}" choice 2>/dev/null || choice=""
    else
      read -r choice 2>/dev/null || choice=""
    fi
    
    # Validate choice is numeric and within range
    case "$choice" in
      *[!0-9]*) 
        warn "Please enter a number"
        ;;
      *)
        if [ "$choice" -ge 0 ] && [ "$choice" -lt "${#options[@]}" ]; then
          echo "$choice"
          return 0
        else
          warn "Please enter a number between 0 and $((${#options[@]} - 1))"
        fi
        ;;
    esac
    
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      warn "Maximum attempts reached, using default option 0"
      echo "0"
      return 0
    fi
  done
  
  return 1
}

# Wait for user confirmation with custom message
wait_for_confirmation(){
  local message="${1:-Press Enter to continue}"
  
  if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
    info "$message (auto-continuing)"
    return 0
  fi
  
  pecho "${PASTEL_CYAN:-\033[96m}" "$message"
  
  # Read with timeout if supported
  if command -v read >/dev/null 2>&1 && read -t 1 >/dev/null 2>&1 </dev/null; then
    read -r -t "${INPUT_TIMEOUT:-30}" 2>/dev/null || true
  else
    read -r 2>/dev/null || true
  fi
}

# Get system username with fallback and sanitization
get_username(){
  local username=""
  
  # Try multiple methods to get username
  if command -v whoami >/dev/null 2>&1; then
    username=$(whoami 2>/dev/null || echo "")
  fi
  
  if [ -z "$username" ] && [ -n "${USER:-}" ]; then
    username="$USER"
  fi
  
  if [ -z "$username" ] && [ -n "${USERNAME:-}" ]; then
    username="$USERNAME"
  fi
  
  if [ -z "$username" ] && [ -n "${LOGNAME:-}" ]; then
    username="$LOGNAME"
  fi
  
  # Fallback to default
  if [ -z "$username" ]; then
    username="termux"
  fi
  
  # Sanitize username
  username=$(sanitize_username "$username")
  
  # Ensure we have a valid username that's not root
  if [ -z "$username" ] || [ "$username" = "root" ]; then
    username="termux"
  fi
  
  echo "$username"
}

# Initialize user environment variables with proper validation
initialize_user_vars(){
  # Set username if not already set, using safe fallback
  if [ -z "${TERMUX_USERNAME:-}" ]; then
    export TERMUX_USERNAME
    TERMUX_USERNAME=$(get_username)
  fi
  
  # Validate and sanitize username
  if [ -n "${TERMUX_USERNAME:-}" ]; then
    TERMUX_USERNAME=$(sanitize_username "$TERMUX_USERNAME")
    if [ -z "$TERMUX_USERNAME" ]; then
      TERMUX_USERNAME="termux"
    fi
    export TERMUX_USERNAME
  fi
  
  # Initialize Git variables if not set
  export GIT_USERNAME="${GIT_USERNAME:-}"
  export GIT_EMAIL="${GIT_EMAIL:-}"
  
  # Initialize system variables with validation
  export UBUNTU_USERNAME="${UBUNTU_USERNAME:-developer}"
  export DISTRO="${DISTRO:-ubuntu}"
  
  # Validate and sanitize UBUNTU_USERNAME
  if [ -n "${UBUNTU_USERNAME:-}" ]; then
    UBUNTU_USERNAME=$(sanitize_username "$UBUNTU_USERNAME")
    if [ -z "$UBUNTU_USERNAME" ]; then
      UBUNTU_USERNAME="developer"
    fi
    export UBUNTU_USERNAME
  fi
  
  return 0
}

# Initialize input module
initialize_input(){
  # Create credential directory with secure permissions
  mkdir -p "${CRED_DIR}" 2>/dev/null || true
  chmod 700 "${CRED_DIR}" 2>/dev/null || true
  
  # Initialize user variables
  initialize_user_vars
  
  # Validate critical variables are set
  if [ -z "${TERMUX_USERNAME:-}" ]; then
    warn "Failed to determine username"
    return 1
  fi
  
  return 0
}

# Call initialization when module is sourced
initialize_input || warn "Input module initialization had issues"
