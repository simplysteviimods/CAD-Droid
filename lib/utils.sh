#!/usr/bin/env bash
# utils.sh - Core utilities, safe arithmetic, and validation functions
# This module provides essential utility functions used throughout the setup

# Set strict error handling modes for robust script execution
set -Eeuo pipefail
# inherit_errexit is available in newer bash; guard it
shopt -s inherit_errexit 2>/dev/null || true

# Prevent multiple sourcing
if [[ "${CAD_UTILS_LOADED:-}" == "1" ]]; then
    return 0
fi
export CAD_UTILS_LOADED=1

# Source required modules
# Use SCRIPT_DIR from main script if available, otherwise determine it
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# If we're in the lib directory, look for modules there
if [[ "$(basename "$SCRIPT_DIR")" == "lib" ]]; then
  source "$SCRIPT_DIR/colors.sh"
else
  source "$SCRIPT_DIR/lib/colors.sh"
fi

# Security constraints for user input validation
MIN_PASSWORD_LENGTH=${MIN_PASSWORD_LENGTH:-6}      # Minimum characters for secure passwords
MAX_INPUT_LENGTH=${MAX_INPUT_LENGTH:-64}        # Maximum input length to prevent buffer issues

# Regular expression patterns for validating user input
export ALLOWED_USERNAME_REGEX='^[A-Za-z][A-Za-z0-9_-]{0,31}$'
export ALLOWED_EMAIL_REGEX='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
export ALLOWED_FILENAME_REGEX='^[A-Za-z0-9._-]{1,64}$'

# Core package list for installation
export CORE_PACKAGES=(
  "curl"
  "wget" 
  "git"
  "nano"
  "openssh"
  "termux-exec"
  "proot-distro"
  "x11-repo"
  "unstable-repo"
)

# Safe arithmetic operations with validation
safe_calc(){
  local expression="$1"
  local result
  
  # Remove spaces and validate characters
  expression=$(echo "$expression" | tr -d ' ')
  
  # Only allow numbers, basic operators, and parentheses
  if echo "$expression" | grep -qE '[^0-9+\-*/().]'; then
    echo "0"  # Return 0 for invalid expressions
    return 1
  fi
  
  # Prevent division by zero and other dangerous operations
  if echo "$expression" | grep -qE '(/0|^0*$)'; then
    echo "0"
    return 1
  fi
  
  # Use bc for calculation if available, otherwise basic arithmetic
  if command -v bc >/dev/null 2>&1; then
    result=$(echo "scale=0; $expression" | bc 2>/dev/null)
  else
    # Fallback to shell arithmetic for simple expressions
    case "$expression" in
      *[+-*/]*) result=$((expression)) 2>/dev/null ;;  # Remove unnecessary backslash
      *) result="$expression" ;;
    esac
  fi
  
  # Validate result is numeric
  case "$result" in
    *[!0-9-]*) 
      echo "0"  # Return 0 on any arithmetic failure
      return 1
      ;;
    *)
      echo "$result"
      return 0
      ;;
  esac
}

# Safe addition with overflow protection
add_int(){
  local a="${1:-0}" b="${2:-0}"
  
  # Validate inputs are integers
  case "$a" in *[!0-9-]*) a=0 ;; esac
  case "$b" in *[!0-9-]*) b=0 ;; esac
  
  local result=$((a + b))
  
  # Check for reasonable bounds (prevent overflow)
  if [ "$result" -gt 2147483647 ] || [ "$result" -lt -2147483648 ]; then
    echo "0"
    return 1
  fi
  
  echo "$result"
}

# Safe subtraction
sub_int(){
  local a="${1:-0}" b="${2:-0}"
  
  # Validate inputs are integers  
  case "$a" in *[!0-9-]*) a=0 ;; esac
  case "$b" in *[!0-9-]*) b=0 ;; esac
  
  echo "$((a - b))"
}

# Check if value is a non-negative integer
is_nonneg_int(){
  local val="$1"
  case "$val" in
    ''|*[!0-9]*) return 1 ;;  # Empty or non-numeric
    *) 
      # Additional check for leading zeros and range
      if [ "$val" -ge 0 ] 2>/dev/null && [ "$val" -le 2147483647 ] 2>/dev/null; then
        return 0
      else
        return 1
      fi
      ;;
  esac
}

# Validate that a string is a positive integer
is_positive_int(){
  local val="$1"
  case "$val" in
    ''|0|*[!0-9]*) return 1 ;;  # Empty, zero, or non-numeric
    *) 
      if [ "$val" -gt 0 ] 2>/dev/null && [ "$val" -le 2147483647 ] 2>/dev/null; then
        return 0
      else
        return 1  
      fi
      ;;
  esac
}

# Remove potentially dangerous characters from strings
sanitize_string(){ 
  printf "%s" "${1:-}" | tr -cd '[:alnum:]._-'
}

# Validate input against pattern with length limit
validate_input(){
  local input="$1" pattern="$2" label="${3:-Input}" max_length="${4:-$MAX_INPUT_LENGTH}"
  
  # Check length first
  if [ "${#input}" -eq 0 ]; then
    warn "$label cannot be empty"
    return 1
  fi
  
  if [ "${#input}" -gt "$max_length" ]; then
    warn "$label too long (max $max_length chars)"
    return 1
  fi
  
  # Check against regex pattern
  if echo "$input" | grep -Eq "$pattern" 2>/dev/null; then
    return 0
  else
    warn "$label invalid format"
    return 1
  fi
}

# Check if a package is installed using dpkg
dpkg_is_installed(){
  local pkg="$1"
  [ -n "$pkg" ] && dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
}

# Test network connectivity to a host
test_connectivity(){
  # shellcheck disable=SC2120 # Parameters are optional with defaults
  local host="${1:-8.8.8.8}" timeout="${2:-5}"
  
  # Validate timeout
  case "$timeout" in
    *[!0-9]*) timeout=5 ;;
    *) 
      if [ "$timeout" -lt 1 ] || [ "$timeout" -gt 30 ]; then
        timeout=5
      fi
      ;;
  esac
  
  # Try multiple methods to test connectivity
  if command -v nc >/dev/null 2>&1; then
    nc -z -w"$timeout" "$host" 53 >/dev/null 2>&1
  elif command -v timeout >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
    timeout "$timeout" bash -c "</dev/tcp/$host/53" >/dev/null 2>&1
  elif command -v ping >/dev/null 2>&1; then
    ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1
  else
    return 1  # No connectivity test method available
  fi
}

# Wait for network connectivity with retry logic
wait_for_network(){
  local max_attempts="${1:-10}" delay="${2:-2}"
  local attempts=0
  
  info "Waiting for network connectivity..."
  
  while [ "$attempts" -lt "$max_attempts" ]; do
    # shellcheck disable=SC2119 # Function can be called without arguments (uses defaults)
    if test_connectivity; then
      ok "Network connectivity established"
      return 0
    fi
    
    attempts=$((attempts + 1))
    if [ "$attempts" -lt "$max_attempts" ]; then
      info "Attempt $attempts/$max_attempts failed, retrying in ${delay}s..."
      sleep "$delay" 2>/dev/null || sleep 2
    fi
  done
  
  warn "Network connectivity could not be established after $max_attempts attempts"
  return 1
}

# Download a file with retry logic and progress indication
download_file(){
  local url="$1" output="$2" max_retries="${3:-3}"
  local retry=0
  
  if [ -z "$url" ] || [ -z "$output" ]; then
    err "download_file: URL and output path required"
    return 1
  fi
  
  # Create output directory if needed
  local output_dir
  output_dir=$(dirname "$output")
  mkdir -p "$output_dir" 2>/dev/null || return 1
  
  while [ "$retry" -lt "$max_retries" ]; do
    info "Downloading $(basename "$output") (attempt $((retry + 1))/$max_retries)"
    
    # Try wget first, then curl
    if command -v wget >/dev/null 2>&1; then
      if wget --progress=bar:force -O "$output" "$url" 2>/dev/null; then
        ok "Download completed: $(basename "$output")"
        return 0
      fi
    elif command -v curl >/dev/null 2>&1; then
      if curl -fsSL -o "$output" "$url" 2>/dev/null; then
        ok "Download completed: $(basename "$output")"
        return 0
      fi
    else
      err "Neither wget nor curl available for downloads"
      return 1
    fi
    
    retry=$((retry + 1))
    if [ "$retry" -lt "$max_retries" ]; then
      warn "Download failed, retrying in 3 seconds..."
      sleep 3
    fi
  done
  
  err "Failed to download $(basename "$output") after $max_retries attempts"
  return 1
}

# Create a backup of a file with timestamp
backup_file(){
  local file="$1" backup_dir="${2:-$HOME/.cad-backups}"
  
  if [ ! -f "$file" ]; then
    warn "Cannot backup $file - file does not exist"
    return 1
  fi
  
  # Create backup directory
  mkdir -p "$backup_dir" 2>/dev/null || return 1
  
  # Generate backup filename with timestamp
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S' 2>/dev/null || echo "backup")
  local basename
  basename=$(basename "$file")
  local backup_file="$backup_dir/${basename}.${timestamp}.bak"
  
  # Copy file to backup location
  if cp "$file" "$backup_file" 2>/dev/null; then
    info "Backup created: $backup_file"
    return 0
  else
    warn "Failed to create backup of $file"
    return 1
  fi
}

# Clean up old backup files (keep last N backups)
cleanup_backups(){
  local backup_dir="${1:-$HOME/.cad-backups}" keep="${2:-5}"
  
  if [ ! -d "$backup_dir" ]; then
    return 0  # Nothing to clean up
  fi
  
  # Validate keep parameter
  case "$keep" in
    *[!0-9]*) keep=5 ;;
    *) if [ "$keep" -lt 1 ]; then keep=1; fi ;;
  esac
  
  # Find and remove old backup files
  find "$backup_dir" -name "*.bak" -type f -printf '%T@ %p\n' 2>/dev/null | \
    sort -nr | \
    tail -n +$((keep + 1)) | \
    cut -d' ' -f2- | \
    while IFS= read -r old_backup; do
      rm -f "$old_backup" 2>/dev/null && info "Removed old backup: $(basename "$old_backup")"
    done
}

# Generate a secure random password
generate_password(){
  local length="${1:-12}" 
  
  # Validate length
  case "$length" in
    *[!0-9]*) length=12 ;;
    *) 
      if [ "$length" -lt 6 ]; then length=6; fi
      if [ "$length" -gt 64 ]; then length=64; fi
      ;;
  esac
  
  # Try multiple methods to generate password
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 "$((length * 3 / 4))" 2>/dev/null | tr -d '\n' | head -c "$length"
  elif [ -r /dev/urandom ]; then
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length" 2>/dev/null
  else
    # Fallback: simple password
    echo "SecurePass$(date +%s | tail -c 4)!"
  fi
}

# Check if script is running with appropriate privileges
check_privileges(){
  # Check if running as root (should not be)
  if [ "$(id -u)" -eq 0 ]; then
    err "This script should not be run as root for security reasons"
    return 1
  fi
  
  # Check if running in Termux environment
  if [ ! -d "/data/data/com.termux" ]; then
    err "This script must be run inside Termux"
    return 1
  fi
  
  return 0
}

# Get system information for diagnostics
get_system_info(){
  local info=""
  
  # Architecture
  if command -v uname >/dev/null 2>&1; then
    info="$info\nArchitecture: $(uname -m)"
    info="$info\nKernel: $(uname -r)"
  fi
  
  # Android version if available
  if [ -r /system/build.prop ]; then
    local android_version
    android_version=$(grep "ro.build.version.release" /system/build.prop 2>/dev/null | cut -d'=' -f2)
    if [ -n "$android_version" ]; then
      info="$info\nAndroid: $android_version"
    fi
  fi
  
  # Available storage
  if command -v df >/dev/null 2>&1; then
    local storage
    storage=$(df -h "$PREFIX" 2>/dev/null | tail -1 | awk '{print $4}')
    if [ -n "$storage" ]; then
      info="$info\nAvailable storage: $storage"
    fi
  fi
  
  # Memory information
  if [ -r /proc/meminfo ]; then
    local memory
    memory=$(grep "MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024) " MB"}')
    if [ -n "$memory" ]; then
      info="$info\nAvailable memory: $memory"
    fi
  fi
  
  printf "%b\n" "$info"
}

# Check if a proot-distro distribution is installed
is_distro_installed(){ 
  local distro="$1"
  [ -n "$distro" ] && [ -d "${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/installed-rootfs/$distro" ]
}
