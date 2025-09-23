#!/usr/bin/env bash
###############################################################################
# CAD-Droid: Android Development Environment Setup
#
# This script transforms your Android device into a powerful development 
# workstation using Termux. It sets up a complete Linux desktop environment
# with all the tools you need for serious coding, CAD work, and productivity.
#
# What you'll get:
#  - Full Linux desktop with SSH access for remote work
#  - Multi-monitor support through X11 forwarding  
#  - Remote desktop streaming for working from anywhere
#  - Development tools, editors, and build environments
#  - Secure key-based authentication and encrypted connections
#  - Quick shortcuts and widgets for mobile productivity
#  - Robust error handling that recovers from common issues
#  - Backup and restore functionality to protect your work
#  - Detailed logging so you can see what's happening
#
# The setup process walks you through each step, explaining what's being
# installed and why. You can run it fully automated or interact with each
# phase to customize your environment exactly how you like it.
#
# Environment Variables for Customization:
# Want to speed things up? Set FAST_MODE=1 to show quicker progress estimates
# Prefer plain text? Use NO_GRADIENT=1 to disable the colorful progress bars
# Having display issues? Try FORCE_TRUECOLOR=1 to force 24-bit color support  
# Want slower animations? Adjust SPINNER_DELAY=0.02 (or higher for less jumpiness)
# Need detailed logs? Set RUN_LOG=1 to save everything to setup-session.log
# Debugging problems? Use DEBUG=1 to see what's happening under the hood
# Checking disk space? Set DISK_DEBUG=1 to show usage after each step
# Running unattended? Use NON_INTERACTIVE=1 to auto-answer all prompts
# Skip manual steps? Set AUTO_APK=1 to skip APK installation confirmations
# No GitHub access? Use AUTO_GITHUB=1 to skip SSH key setup interactions
# Don't need remote desktop? Set ENABLE_SUNSHINE=0 to skip streaming setup
# Manual APK handling? Use ENABLE_APK_AUTO=0 to disable automatic downloads  
# Skip shortcuts? Set ENABLE_WIDGETS=0 to skip mobile productivity widgets
# No ADB needed? Use ENABLE_ADB=0 to skip Android Debug Bridge wireless setup
# No backups? Set ENABLE_SNAPSHOTS=0 to disable system snapshot functionality
# Missing Termux:API? Use TERMUX_API_FORCE_SKIP=1 to skip waiting for it
# Control API detection: TERMUX_API_WAIT_MAX=4 attempts, TERMUX_API_WAIT_DELAY=3 seconds each
# APK install timeout: APK_PAUSE_TIMEOUT=45 seconds before auto-continuing
# GitHub timeouts: GITHUB_PROMPT_TIMEOUT_OPEN=30s to open, GITHUB_PROMPT_TIMEOUT_CONFIRM=60s to continue  
# Prefer F-Droid? Set PREFER_FDROID=1 to use F-Droid store over GitHub for APKs (GitHub is default)
# Custom plugins? Put them in PLUGIN_DIR=~/.cad/plugins for automatic loading
#
# Command Line Options:
# Get help: ./setup.sh --help (shows all available options)
# Check what's installed: ./setup.sh --version  
# Run without questions: ./setup.sh --non-interactive (uses defaults for everything)
# Test specific parts: ./setup.sh --only-step <number or name> (run just one step)
# Check your system: ./setup.sh --doctor (diagnose common problems)
# Debug APK issues: ./setup.sh --apk-diagnose (test download connections)  
# Test remote desktop: ./setup.sh --sunshine-test (verify streaming works)
# Backup your setup: ./setup.sh --snapshot-create <name> (save current state)
# Restore from backup: ./setup.sh --snapshot-restore <name> (load saved state)
# List your backups: ./setup.sh --list-snapshots (see what you've saved)
#
###############################################################################

# Check if we're running in Bash shell, if not, restart with Bash
# This ensures compatibility across different shell environments
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

# Set strict error handling modes for robust script execution:
# -e: Exit immediately if any command fails
# -u: Exit if trying to use undefined variables  
# -E: Functions inherit ERR trap
# -o pipefail: Exit if any command in a pipeline fails
set -Eeuo pipefail
# inherit_errexit is available in newer bash; guard it
shopt -s inherit_errexit 2>/dev/null || true

# Set restrictive file permissions (owner read/write only) for security
umask 077

# Define script metadata as read-only constants
readonly SCRIPT_VERSION="CAD-Droid Setup"
readonly SCRIPT_NAME="CAD-Droid Mobile Development Environment"

# Set consistent locale settings for predictable behavior across systems
# This ensures consistent text processing, sorting, and character handling
export LANG=C.UTF-8 LC_ALL=C.UTF-8 LC_CTYPE=C.UTF-8

# Configure Debian package manager for non-interactive mode
# This prevents prompts during package installations
export DEBIAN_FRONTEND=noninteractive

# --- Security and Environment Guards ---
# These checks ensure the script runs in a safe and supported environment

# Check for Windows-style line endings which can break bash scripts
if grep -q $'\r' "$0" 2>/dev/null; then
  printf "Error: CRLF line endings detected. Run: sed -i 's/\\\\r$//' %s\n" "$0" >&2
  exit 1
fi

# Prevent running as root user for security (Termux should never be root)
if [ "$EUID" -eq 0 ]; then 
  echo "Error: Do not run as root" >&2
  exit 1
fi

# Verify we're running inside Termux environment
if [ ! -d "/data/data/com.termux" ]; then
  echo "Error: Must run inside Termux" >&2
  exit 1
fi

# Define critical system paths with fallback defaults and validation
# PREFIX: Termux's equivalent of /usr on standard Linux systems
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
if [ ! -d "$PREFIX" ]; then
  echo "Error: Termux PREFIX directory not found: $PREFIX" >&2
  exit 1
fi

# HOME: User's home directory in Termux
HOME="${HOME:-/data/data/com.termux/files/home}"
if [ ! -d "$HOME" ]; then
  echo "Error: Termux HOME directory not found: $HOME" >&2
  exit 1
fi

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

# Call enhanced TMPDIR setup
ensure_tmpdir || {
  echo "Error: Cannot establish working temporary directory" >&2
  exit 1
}

# Record when script started for duration tracking
START_TIME=$(date +%s 2>/dev/null || echo 0)

# Initialize variables to prevent unbound variable errors
github_opened=false

# Network timeout settings for reliable downloads
CURL_CONNECT="${CURL_CONNECT:-5}"     # Connection timeout in seconds
CURL_MAX_TIME="${CURL_MAX_TIME:-40}"  # Maximum download time in seconds

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

validate_curl_timeouts

# === Core Constants & Palettes (Single Source) ===
# Security constraints for user input validation
MIN_PASSWORD_LENGTH=6      # Minimum characters for secure passwords
MAX_INPUT_LENGTH=64        # Maximum input length to prevent buffer issues

# Regular expression patterns for validating user input
ALLOWED_USERNAME_REGEX='^[A-Za-z][A-Za-z0-9_-]{0,31}$'
ALLOWED_EMAIL_REGEX='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
ALLOWED_FILENAME_REGEX='^[A-Za-z0-9._-]{1,64}$'

# Feature toggle flags - can be overridden by environment variables
# These allow users to enable/disable specific functionality
ENABLE_SNAPSHOTS="${ENABLE_SNAPSHOTS:-1}"    # System backup and restore capability
ENABLE_WIDGETS="${ENABLE_WIDGETS:-1}"        # Desktop productivity shortcuts
ENABLE_ADB="${ENABLE_ADB:-1}"                # Android Debug Bridge wireless setup
SKIP_ADB="${SKIP_ADB:-0}"                    # Skip ADB wireless setup entirely
ENABLE_APK_AUTO="${ENABLE_APK_AUTO:-1}"      # Automatic APK downloading
ENABLE_SUNSHINE="${ENABLE_SUNSHINE:-1}"      # Remote desktop streaming

# Environment timeouts and control variables  
APK_PAUSE_TIMEOUT="${APK_PAUSE_TIMEOUT:-45}"                    # APK installation timeout
GITHUB_PROMPT_TIMEOUT_OPEN="${GITHUB_PROMPT_TIMEOUT_OPEN:-30}" # GitHub browser open timeout  
GITHUB_PROMPT_TIMEOUT_CONFIRM="${GITHUB_PROMPT_TIMEOUT_CONFIRM:-60}" # GitHub setup confirmation timeout
TERMUX_API_FORCE_SKIP="${TERMUX_API_FORCE_SKIP:-0}"           # Force skip Termux:API detection
TERMUX_API_WAIT_MAX="${TERMUX_API_WAIT_MAX:-4}"               # Max API detection attempts
TERMUX_API_WAIT_DELAY="${TERMUX_API_WAIT_DELAY:-3}"           # Delay between API attempts
AUTO_GITHUB="${AUTO_GITHUB:-0}"                               # Skip GitHub setup interaction

# Simple and safe variable validation without arithmetic operations that could fail
# Validate timeout values with robust checking
validate_timeout_vars() {
  # APK_PAUSE_TIMEOUT validation
  case "${APK_PAUSE_TIMEOUT:-}" in
    ''|*[!0-9]*) APK_PAUSE_TIMEOUT=45 ;;
    *)
      # Only do arithmetic if we know it's a number
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

# Apply validation to all timeout variables
validate_timeout_vars

# === Safe Arithmetic & Validation Utilities ===
# These functions ensure all arithmetic operations are validated and safe

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
  if [ "$func_count" -gt 1 ]; then
    echo "ERROR: Detected duplicate function definitions. Script may have been corrupted." >&2
    exit 2
  fi
}

# Call duplication detection
assert_unique_definitions

# Color palette definitions for beautiful terminal output
# Pastel colors for gentle backgrounds
PASTEL_HEX=( "9DF2F2" "FFDFA8" "DCC9FF" "FFC9D9" "C9FFD1" "FBE6A2" "C9E0FF" "FAD3C4" "E0D1FF" "FFE2F1" "D1FFE6" "FFEBC9" )
# Vibrant colors for accents and highlights
VIBRANT_HEX=( "31D4D4" "FFAA1F" "9B59FF" "FF4F7D" "2EE860" "FFCF26" "4FA6FF" "FF8A4B" "7E4BFF" "FF5FA2" "11DB78" "FFB347" )
# Fallback color when palette unavailable
FALLBACK_COLOR='\033[38;2;175;238;238m'

# Initialize color support detection
init_color_support() {
  local colors=8
  if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
    colors=$(tput colors 2>/dev/null || echo 8)
  fi
  
  # Check for color support and terminal capability
  if [ "$colors" -lt 8 ] || [ "${TERM:-}" = "dumb" ]; then
    # Disable colors for limited terminals
    export HAS_COLOR_SUPPORT=0
    return 1
  else
    export HAS_COLOR_SUPPORT=1
    return 0
  fi
}

# Initialize pastel color variables with fallback support
init_pastel_colors() {
  if init_color_support; then
    # Define comprehensive pastel color palette
    export PASTEL_CYAN='\033[38;2;175;238;238m'       # Pale Turquoise #AFEEEE
    export PASTEL_PINK='\033[38;2;255;182;193m'       # Light Pink #FFB6C1
    export PASTEL_GREEN='\033[38;2;144;238;144m'      # Light Green #90EE90
    export PASTEL_YELLOW='\033[38;2;255;255;224m'     # Light Yellow #FFFFE0
    export PASTEL_PURPLE='\033[38;2;221;160;221m'     # Plum #DDA0DD
    export PASTEL_ORANGE='\033[38;2;255;218;185m'     # Peach Puff #FFDAB9
    export PASTEL_BLUE='\033[38;2;173;216;230m'       # Light Blue #ADD8E6
    export PASTEL_RED='\033[38;2;255;192;203m'        # Light Pink (red variant) #FFC0CB
    export RESET='\033[0m'
  else
    # Use basic ANSI colors for limited terminals
    export PASTEL_CYAN='\033[96m'   # Bright cyan
    export PASTEL_PINK='\033[95m'   # Bright magenta
    export PASTEL_GREEN='\033[92m'  # Bright green
    export PASTEL_YELLOW='\033[93m' # Bright yellow
    export PASTEL_PURPLE='\033[35m' # Magenta
    export PASTEL_ORANGE='\033[91m' # Bright red
    export PASTEL_BLUE='\033[94m'   # Bright blue
    export PASTEL_RED='\033[91m'    # Bright red
    export RESET='\033[0m'
  fi
}

# Initialize color theme early
init_pastel_colors

# Unicode Braille characters for animated progress spinners (smoother animation)
# These create a smooth spinning animation effect with less jumpiness
BRAILLE_CHARS=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
# Animation frame delay for spinner (much faster now)
SPINNER_DELAY="${SPINNER_DELAY:-0.02}"

# Validate spinner delay safely without awk injection
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

validate_spinner_delay

# Essential packages required for full productivity environment
# These provide core functionality for development and desktop use
CORE_PACKAGES=( 
  ncurses-utils    # Terminal handling utilities
  jq               # JSON processor for API responses  
  git              # Version control system
  curl             # HTTP client for downloads
  nano             # Simple text editor
  vim              # Advanced text editor
  tmux             # Terminal multiplexer for sessions
  python           # Python programming language
  nodejs           # JavaScript runtime
  openssh          # SSH client/server for secure connections
  pulseaudio       # Audio system
  dbus             # Inter-process communication system
  fontconfig       # Font management system
  ttf-dejavu       # High-quality fonts
  proot-distro     # Linux distribution container system
  termux-api       # Android system integration
)

# Minimum file size for valid APK files (12KB)
# Files smaller than this are likely corrupted or incomplete
MIN_APK_SIZE="${MIN_APK_SIZE:-12288}"

# Validate MIN_APK_SIZE
case "$MIN_APK_SIZE" in
  *[!0-9]*) MIN_APK_SIZE=12288 ;;
  *) [ "$MIN_APK_SIZE" -lt 1024 ] && MIN_APK_SIZE=12288 ;;
esac

# Global state variables - Initialize all variables to prevent undefined variable errors
# These track the current state of the installation process

# Directory paths for storing various types of data
WORK_DIR=""              # Temporary working directory
CRED_DIR=""              # Secure credential storage
STATE_DIR=""             # Persistent state information  
LOG_DIR=""               # Log file storage
SNAP_DIR=""              # System snapshot storage
EVENT_LOG=""             # Event log file path
STATE_JSON=""            # JSON state file path

# User and system configuration
TERMUX_USERNAME=""       # Username for Termux environment
TERMUX_PHONETYPE="unknown"  # Detected phone manufacturer
DISTRO="ubuntu"          # Selected Linux distribution
UBUNTU_USERNAME=""       # Username for Linux container
GIT_USERNAME=""          # Git configuration username
GIT_EMAIL=""             # Git configuration email

# Installation tracking
DOWNLOAD_COUNT=0         # Number of packages processed
TERMUX_API_VERIFIED="no" # Whether Termux:API app is available

# Mirror and network configuration
SELECTED_MIRROR_NAME=""  # Human-readable mirror name
SELECTED_MIRROR_URL=""   # Mirror URL for package downloads

# Tool availability flags
WGET_READY=0            # Whether wget is installed and working
NMAP_READY=0            # Whether nmap is installed and working

# Service health status
SUNSHINE_HEALTH="unknown"  # Remote desktop streaming service status

# Lists for tracking installation status
APK_MISSING=()          # List of APK files that failed to download
LINUX_SSH_PORT=""       # SSH port number for Linux container

# Step execution tracking arrays
STEP_DURATIONS=()       # How long each step took to complete
STEP_STATUS=()          # Success/failure status of each step
STEP_FUNCS=()           # Function name for each step
STEP_NAME=()            # Human-readable name for each step  
STEP_ETA=()             # Estimated time for each step

# Associative arrays for time tracking (Bash 4+ feature)
declare -A STEP_START_TIME STEP_END_TIME

# Progress tracking variables
CURRENT_STEP_INDEX=-1   # Which step is currently executing
PROGRESS_ACCUM=0        # Accumulated progress for percentage calculation
TOTAL_STEPS=0           # Total number of steps in installation
TOTAL_EST=0             # Total estimated time for all steps

# Execution control variables
ONLY_STEP=""            # If set, only run this specific step
NON_INTERACTIVE=0       # Whether to run without user prompts
CARD_INDEX=0            # Current color index for UI cards (initialized to prevent unbound variable)

# Plugin and storage configuration
PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.cad/plugins}"              # Directory for custom plugins
USER_SELECTED_APK_DIR=""                                     # User-selected APK directory via file picker

# --- Color and Visual Functions ---
# These functions create beautiful colored output in the terminal

# Generate RGB color escape sequence for 24-bit color terminals
# Parameters: red (0-255), green (0-255), blue (0-255)
rgb_seq(){ 
  local r="$1" g="$2" b="$3"
  
  # Validate RGB values
  for val in "$r" "$g" "$b"; do
    case "$val" in
      *[!0-9]*) return 1 ;;
      *) [ "$val" -lt 0 ] || [ "$val" -gt 255 ] && return 1 ;;
    esac
  done
  
  printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Convert hexadecimal color code to RGB values
# Parameter: 6-character hex color code (e.g., "FF0000" for red)
# Returns: Three space-separated decimal values (e.g., "255 0 0")
hex_to_rgb(){ 
  local h="${1:-FFFFFF}"  # Default to white if no parameter provided
  
  # Validate hex string format (exactly 6 hex digits)
  if [[ ! "$h" =~ ^[0-9A-Fa-f]{6}$ ]]; then
    printf "128 128 128"  # Return neutral gray for invalid input
    return
  fi
  
  # Extract and convert each color component
  # ${h:0:2} gets first 2 characters, 0x prefix makes it hex
  local r g b
  r=$((0x${h:0:2}))
  g=$((0x${h:2:2}))
  b=$((0x${h:4:2}))
  
  printf "%d %d %d" "$r" "$g" "$b"
}

# Detect if terminal supports 24-bit "true color" mode
# Returns: 0 (success) if supported, 1 (failure) if not supported
supports_truecolor(){
  # Check COLORTERM environment variable for common true color indicators
  case "${COLORTERM:-}" in 
    truecolor|24bit|*TrueColor*|*24bit*) return 0;;
  esac
  
  # Allow manual override via environment variable
  [ "${FORCE_TRUECOLOR:-0}" = "1" ] && return 0
  
  return 1
}

# Create a gradient line across the terminal width with safe arithmetic
# Parameters: start_hex, end_hex, character (default "=")
# This creates beautiful colored separator lines
gradient_line(){
  local start="$1" end="$2" ch="${3:-=}" width
  
  # Get terminal width with proper fallback chain
  width=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
  
  # Validate width is numeric and within reasonable bounds
  case "$width" in
    (*[!0-9]*) width=80;;  # Non-numeric, use default
    (*) 
      if [ "$width" -lt 20 ] 2>/dev/null; then width=20; fi    # Minimum width
      if [ "$width" -gt 200 ] 2>/dev/null; then width=200; fi  # Maximum width
    ;;
  esac
  
  # If gradients disabled or terminal doesn't support true color,
  # fall back to solid color line
  if [ "${NO_GRADIENT:-0}" = "1" ] || ! supports_truecolor; then
    # Convert start color to RGB and use solid color
    local r g b
    read -r r g b <<< "$(hex_to_rgb "$start")"
    local color_seq
    color_seq=$(rgb_seq "$r" "$g" "$b" 2>/dev/null || echo "$FALLBACK_COLOR")
    printf "%b" "$color_seq"
    # Create line of specified character and width
    printf '%*s' "$width" '' | tr ' ' "$ch"
    printf '\033[0m\n'  # Reset color and newline
    return
  fi
  
  # Create true gradient by interpolating between start and end colors
  local r1 g1 b1 r2 g2 b2
  read -r r1 g1 b1 <<< "$(hex_to_rgb "$start")"
  read -r r2 g2 b2 <<< "$(hex_to_rgb "$end")"
  
  # Calculate color interpolation with safe arithmetic
  local pos=0 rr gg bb den
  if [ "$width" -gt 1 ] 2>/dev/null; then
    den=$((width - 1))
  else
    den=1
  fi
  
  # Draw each character with its interpolated color using safe counter
  while [ "$pos" -lt "$width" ] 2>/dev/null; do
    # Linear interpolation formula: start + (end-start) * (pos/total)
    # Safe arithmetic with validation
    if [ "$den" -gt 0 ] 2>/dev/null; then
      rr=$((r1 + (r2 - r1) * pos / den))
      gg=$((g1 + (g2 - g1) * pos / den))
      bb=$((b1 + (b2 - b1) * pos / den))
    else
      rr=$r1; gg=$g1; bb=$b1
    fi
    
    local seq
    seq=$(rgb_seq "$rr" "$gg" "$bb" 2>/dev/null || echo "$FALLBACK_COLOR")
    printf '%b%s' "$seq" "$ch"
    
    # Safe position increment
    if [ "$pos" -lt 1000 ] 2>/dev/null; then
      pos=$((pos + 1))
    else
      break  # Safety break
    fi
  done
  printf '\033[0m\n'  # Reset color and add newline
}

# Calculate midpoint color between two hex colors
# Parameters: start_hex, end_hex
# Returns: RGB escape sequence for the middle color
mid_color_seq(){
  # Convert both colors to RGB
  local r1 g1 b1 r2 g2 b2
  read -r r1 g1 b1 <<< "$(hex_to_rgb "$1")"
  read -r r2 g2 b2 <<< "$(hex_to_rgb "$2")"
  
  # Return RGB sequence for average of the two colors
  rgb_seq $(((r1+r2)/2)) $(((g1+g2)/2)) $(((b1+b2)/2)) 2>/dev/null || echo "$FALLBACK_COLOR"
}

# Get color from palette based on index (with wraparound)
# Parameter: index number
# Returns: RGB escape sequence for the selected color
color_for_index(){
  local i="${1:-0}"
  local size=${#PASTEL_HEX[@]}  # Size of color palette array
  
  # Handle empty palette - critical safety check
  if [ "$size" -eq 0 ]; then
    printf '%s' "$FALLBACK_COLOR"
    return
  fi
  
  # Ensure index is numeric (default to 0 for non-numeric input)
  case "$i" in
    (*[!0-9-]*) i=0;;  # Include negative sign in validation
    (*) 
      # Handle negative numbers
      if [ "$i" -lt 0 ]; then
        i=0
      fi
    ;;
  esac
  
  # Use modulo operator to wrap around palette (with zero division protection)
  local idx=0
  if [ "$size" -gt 0 ]; then
    idx=$((i % size))
  fi
  
  local hex="${PASTEL_HEX[$idx]:-9DF2F2}"  # Get color with fallback
  
  # Convert hex to RGB and return escape sequence
  local r g b
  read -r r g b <<< "$(hex_to_rgb "$hex")"
  rgb_seq "$r" "$g" "$b" 2>/dev/null || echo "$FALLBACK_COLOR"
}

# Get terminal width for consistent display calculations
get_terminal_width() {
  local width
  if command -v tput >/dev/null 2>&1; then
    width=$(tput cols 2>/dev/null) || width=80
  else
    width="${COLUMNS:-80}"
  fi
  
  # Ensure reasonable bounds
  if [ "$width" -lt 40 ] || [ "$width" -gt 200 ]; then
    width=80
  fi
  
  echo "$width"
}

# Simple text centering without wrapping
center_text() {
  local text="$1"
  local width
  width=$(get_terminal_width)
  
  # Strip ANSI sequences for length calculation
  local clean_text
  clean_text=$(echo "$text" | sed 's/\x1b\[[0-9;]*m//g')
  local text_len=${#clean_text}
  
  # If text is too long, just return it as-is
  if [ "$text_len" -ge "$width" ]; then
    echo "$text"
    return
  fi
  
  # Calculate padding and center the text
  local padding=$(( (width - text_len) / 2 ))
  printf "%*s%s\n" "$padding" "" "$text"
}

# NEW: Word-based text wrapping for body text
wrap_text_words() {
  local text="$1"
  local max_width="${2:-72}"
  
  # Validate max_width
  case "$max_width" in
    *[!0-9]*) max_width=72 ;;
    *) 
      if [ "$max_width" -lt 20 ]; then max_width=72; fi
      if [ "$max_width" -gt 200 ]; then max_width=200; fi
      ;;
  esac
  
  # Split text into words
  local words line_length current_line
  line_length=0
  current_line=""
  
  # Process each word
  for word in $text; do
    local word_length=${#word}
    
    # Check if adding this word would exceed the line length
    if [ "$line_length" -eq 0 ]; then
      # First word on line
      current_line="$word"
      line_length="$word_length"
    elif [ $((line_length + 1 + word_length)) -le "$max_width" ]; then
      # Word fits on current line
      current_line="$current_line $word"
      line_length=$((line_length + 1 + word_length))
    else
      # Word doesn't fit, output current line and start new one
      echo "$current_line"
      current_line="$word"
      line_length="$word_length"
    fi
  done
  
  # Output the last line if it has content
  if [ -n "$current_line" ]; then
    echo "$current_line"
  fi
}

# NEW: Format body text with word wrapping
format_body_text() {
  local text="$1"
  local width
  width=$(get_terminal_width)
  local wrap_width=$((width - 8))  # Leave margin for readability
  
  wrap_text_words "$text" "$wrap_width"
}

# NEW: Completely rewritten card display system
# Draw a decorative card with title and subtitle
draw_card(){
  local title="${1:-}" subtitle="${2:-}"
  
  # Safe CARD_INDEX validation and increment
  local current_index="${CARD_INDEX:-0}"
  case "$current_index" in
    *[!0-9-]*) current_index=0 ;;
    *) 
      if [ "$current_index" -lt 0 ] 2>/dev/null; then
        current_index=0
      fi
      ;;
  esac
  
  # Select colors from palette using current card index
  local size=${#PASTEL_HEX[@]}
  if [ "$size" -le 0 ]; then
    echo "Error: Color palette is empty" >&2
    return 1
  fi
  
  local idx=0
  if [ "$size" -gt 0 ] 2>/dev/null && [ "$current_index" -ge 0 ] 2>/dev/null; then
    idx=$((current_index % size))
  fi
  
  local start="${PASTEL_HEX[$idx]:-9DF2F2}"
  local end="${VIBRANT_HEX[$idx]:-31D4D4}"
  local mid
  mid=$(mid_color_seq "$start" "$end")
  
  # Safe increment of CARD_INDEX
  if [ "$current_index" -lt 1000 ] 2>/dev/null; then
    CARD_INDEX=$((current_index + 1))
  else
    CARD_INDEX=0
  fi
  
  # Draw top border
  gradient_line "$start" "$end" "="
  
  # Display title if provided (no wrapping, just center)
  if [ -n "$title" ]; then
    printf "%b%s%b\n" "$mid" "$(center_text "$title")" '\033[0m'
  fi
  
  # Display subtitle if provided (no wrapping, just center)
  if [ -n "$subtitle" ]; then
    printf "%b%s%b\n" "$mid" "$(center_text "$subtitle")" '\033[0m'
  fi
  
  # Draw bottom border
  gradient_line "$start" "$end" "="
  echo  # Add spacing after card
}

# NEW: Completely rewritten phase header system - exactly like intro cards
# Draw a phase header for major installation steps
draw_phase_header(){
  local text="${1:-}"
  
  # Safe CARD_INDEX validation and increment
  local current_index="${CARD_INDEX:-0}"
  case "$current_index" in
    *[!0-9-]*) current_index=0 ;;
    *) 
      if [ "$current_index" -lt 0 ] 2>/dev/null; then
        current_index=0
      fi
      ;;
  esac
  
  # Select colors for this phase
  local size=${#PASTEL_HEX[@]}
  if [ "$size" -le 0 ]; then
    echo "Error: Color palette is empty" >&2
    return 1
  fi
  
  local idx=0
  if [ "$size" -gt 0 ] 2>/dev/null && [ "$current_index" -ge 0 ] 2>/dev/null; then
    idx=$((current_index % size))
  fi
  
  local start="${PASTEL_HEX[$idx]:-9DF2F2}"
  local end="${VIBRANT_HEX[$idx]:-31D4D4}"
  local mid
  mid=$(mid_color_seq "$start" "$end")
  
  # Safe increment of CARD_INDEX
  if [ "$current_index" -lt 1000 ] 2>/dev/null; then
    CARD_INDEX=$((current_index + 1))
  else
    CARD_INDEX=0
  fi
  
  # Draw top border
  gradient_line "$start" "$end" "="
  
  # Handle multi-line text by centering each line separately (like intro cards handle title/subtitle)
  if [ -n "$text" ]; then
    while IFS= read -r line; do
      if [ -n "$line" ]; then
        printf "%b%s%b\n" "$mid" "$(center_text "$line")" '\033[0m'
      fi
    done <<< "$text"
  fi
  
  # Draw bottom border
  gradient_line "$start" "$end" "="
  echo
}

# --- Logging and Output Functions ---
# These functions provide consistent, colorful output with logging

# Print colored text with automatic color reset
# Parameters: color_escape_sequence, text_to_print
pecho(){ 
  local c="${1:-$FALLBACK_COLOR}"
  shift
  printf "%b%s%b\n" "$c" "$*" '\033[0m'
}

# Print informational message in cyan (title cards never wrap, body text wraps appropriately)
info(){ 
  local message="$*"
  # Simple approach: wrap if message is very long (over 100 chars) and not a title/header
  if [ "${#message}" -gt 100 ] && [[ ! "$message" =~ ^(Phase|Step|Installing|Configuring|Setting) ]]; then
    while IFS= read -r line; do
      pecho '\033[38;2;175;238;238m' "$line"
    done < <(format_body_text "$message")
  else
    pecho '\033[38;2;175;238;238m' "$message"
  fi
  log_event info "${CURRENT_STEP_INDEX:-unknown}" info "$*"
}

# Print warning message in yellow (same logic as info)
warn(){ 
  local message="$*"
  if [ "${#message}" -gt 100 ] && [[ ! "$message" =~ ^(Phase|Step|Installing|Configuring|Setting) ]]; then
    while IFS= read -r line; do
      pecho '\033[38;2;255;255;224m' "$line"
    done < <(format_body_text "$message")
  else
    pecho '\033[38;2;255;255;224m' "$message"
  fi
  log_event warn "${CURRENT_STEP_INDEX:-unknown}" warn "$*"
}

# Print success message in green (same logic as info)
ok(){ 
  local message="$*"
  if [ "${#message}" -gt 100 ] && [[ ! "$message" =~ ^(Phase|Step|Installing|Configuring|Setting) ]]; then
    while IFS= read -r line; do
      pecho '\033[38;2;152;251;152m' "$line"
    done < <(format_body_text "$message")
  else
    pecho '\033[38;2;152;251;152m' "$message"
  fi
  log_event success "${CURRENT_STEP_INDEX:-unknown}" success "$*"
}

# Print error message in pink/red (same logic as info)
err(){ 
  local message="$*"
  if [ "${#message}" -gt 100 ] && [[ ! "$message" =~ ^(Phase|Step|Installing|Configuring|Setting) ]]; then
    while IFS= read -r line; do
      pecho '\033[38;2;255;192;203m' "$line"
    done < <(format_body_text "$message")
  else
    pecho '\033[38;2;255;192;203m' "$message"
  fi
  log_event error "${CURRENT_STEP_INDEX:-unknown}" error "$*"
}

# Print debug message in purple (only if DEBUG=1)
debug(){ 
  [ "${DEBUG:-0}" = "1" ] && pecho '\033[38;2;221;160;221m' "[DEBUG] $*"
}

# Write structured log entry to JSON event log
# Parameters: action, phase, status, detail, duration
log_event(){
  local ts action phase status detail dur
  
  # Generate ISO 8601 timestamp
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "unknown")
  
  # Extract parameters with defaults
  action="${1:-unknown}"
  phase="${2:-null}"
  status="${3:-unknown}"
  detail="${4:-}"
  dur="${5:-}"
  
  # Escape double quotes in strings to prevent JSON corruption
  action=$(printf "%s" "$action" | sed 's/"/\\"/g')
  detail=$(printf "%s" "$detail" | sed 's/"/\\"/g')
  
  # Only write log if EVENT_LOG path is set and writable
  if [ -n "${EVENT_LOG:-}" ]; then
    if printf '{"ts":"%s","phase":%s,"action":"%s","status":"%s","detail":"%s","duration":"%s"}\n' \
      "$ts" "$phase" "$action" "$status" "$detail" "$dur" >> "$EVENT_LOG" 2>/dev/null; then
      return 0
    fi
  fi
  
  return 0  # Don't fail if logging fails
}

# Sleep with fallback for systems without GNU sleep
# Parameter: sleep duration in seconds (default 0.5)
safe_sleep(){ 
  local duration="${1:-0.5}"
  
  # Validate duration
  case "$duration" in
    *[!0-9.]*) duration="0.5" ;;
  esac
  
  if ! sleep "$duration" 2>/dev/null; then
    if command -v busybox >/dev/null 2>&1; then
      busybox sleep "$duration" 2>/dev/null || return 0
    fi
  fi
}

# --- Progress Tracking and Step Management ---

# Safely calculate percentage avoiding division by zero
# Parameters: numerator, denominator  
# Returns: percentage (0-100)
safe_progress_div(){ 
  local numerator="${1:-0}" denominator="${2:-1}"
  
  # Validate both inputs are numeric
  case "$numerator" in *[!0-9-]*) numerator=0 ;; esac
  case "$denominator" in *[!0-9-]*) denominator=1 ;; esac
  
  # Ensure positive values
  if [ "$numerator" -lt 0 ] 2>/dev/null; then
    numerator=0
  fi
  if [ "$denominator" -lt 1 ] 2>/dev/null; then
    denominator=1
  fi
  
  # Safe division with validation
  if [ "$denominator" -eq 0 ]; then
    echo 0
  else
    local result=0
    if [ "$numerator" -gt 0 ] && [ "$denominator" -gt 0 ] 2>/dev/null; then
      result=$((numerator * 100 / denominator))
      # Cap at 100%
      if [ "$result" -gt 100 ] 2>/dev/null; then
        result=100
      fi
    fi
    echo "$result"
  fi
}

# Execute a command with animated progress display using safe arithmetic
# Parameters: description, estimated_time_seconds, command, [command_args...]
# Shows a spinner with progress percentage while command runs
run_with_progress(){
  local message="${1:-Running command}"
  shift
  local est="${1:-40}"
  shift
  
  # Validate estimated time
  case "$est" in
    *[!0-9]*) est=20 ;;
    *) 
      if [ "$est" -lt 5 ] 2>/dev/null; then est=20; fi
      if [ "$est" -gt 3600 ] 2>/dev/null; then est=3600; fi
      ;;
  esac
  
  # Create temporary file for command output
  local logf
  if logf="$(mktemp -p "$TMPDIR" log.XXXX 2>/dev/null)"; then
    :  # Success
  elif logf="$(mktemp 2>/dev/null)"; then
    :  # Fallback success
  else
    # Final fallback
    logf="/tmp/cad_log_$$"
    touch "$logf" 2>/dev/null || return 1
  fi
  
  # Log the start of this command
  log_event cmd_start "${CURRENT_STEP_INDEX:-unknown}" start "$message"
  
  # Start the command in background and capture its process ID
  ( "$@" >"$logf" 2>&1 ) & 
  local pid=$!
  
  # Progress animation loop
  local start_ts
  start_ts=$(date +%s 2>/dev/null || echo 0)
  local frame=0 cols
  cols=$(get_terminal_width)
  local delay="${SPINNER_DELAY:-0.02}"
  
  # Continue animation while command is running
  while kill -0 "$pid" 2>/dev/null; do
    local now elapsed pct
    now=$(date +%s 2>/dev/null || echo "$start_ts")
    
    # Safe elapsed time calculation
    if [ "$now" -ge "$start_ts" ] 2>/dev/null; then
      elapsed=$((now - start_ts))
    else
      elapsed=0
    fi
    
    # Calculate progress percentage with safe arithmetic
    if [ "$elapsed" -le "$est" ] 2>/dev/null; then 
      # Normal progress: 0-90% during estimated time
      if [ "$est" -gt 0 ] 2>/dev/null; then
        pct=$((elapsed * 90 / est))
      else
        pct=0
      fi
    else 
      # Overtime progress: slowly approach 100%
      local over tail add
      if [ "$elapsed" -gt "$est" ] 2>/dev/null; then
        over=$((elapsed - est))
      else
        over=0
      fi
      
      if [ "$est" -gt 3 ] 2>/dev/null; then
        tail=$((est / 3))
      else
        tail=5
      fi
      
      if [ "$tail" -lt 5 ] 2>/dev/null; then tail=5; fi
      
      if [ "$tail" -gt 0 ] 2>/dev/null; then
        add=$((over * 10 / tail))
      else
        add=0
      fi
      
      if [ "$add" -gt 10 ] 2>/dev/null; then add=10; fi
      pct=$((90 + add))
    fi
    
    if [ "$pct" -gt 99 ] 2>/dev/null; then pct=99; fi  # Never show 100% while running
    
    # Get current spinner character with bounds checking
    local spinner_count=${#BRAILLE_CHARS[@]} sym_idx sym
    if [ "$spinner_count" -gt 0 ] 2>/dev/null; then
      sym_idx=$((frame % spinner_count))
      sym="${BRAILLE_CHARS[$sym_idx]:-*}"
    else
      sym="*"
    fi
    
    # Display progress line with spinner, message, and percentage
    local display_width
    if [ "$cols" -gt 14 ] 2>/dev/null; then
      display_width=$((cols - 14))
    else
      display_width=40
    fi
    
    printf "\r\033[38;2;175;238;238m%s\033[0m \033[38;2;175;238;238m%-*.*s\033[0m \033[38;2;173;216;230m(%3d%%)\033[0m" \
      "$sym" "$display_width" "$display_width" "$message" "$pct"
    
    # Safe frame increment
    if [ "$frame" -lt 10000 ] 2>/dev/null; then
      frame=$((frame + 1))
    else
      frame=0  # Reset to prevent overflow
    fi
    
    safe_sleep "$delay"
  done
  
  # Wait for command to complete and get exit code
  local rc=0
  wait "$pid" || rc=$?
  
  local end_ts dur
  end_ts=$(date +%s 2>/dev/null || echo "$start_ts")
  if [ "$end_ts" -ge "$start_ts" ] 2>/dev/null; then
    dur=$((end_ts - start_ts))
  else
    dur=0
  fi
  
  # Clear the progress line
  printf "\r%*s\r" "$cols" ""
  
  # Report final result
  if [ "$rc" -eq 0 ]; then 
    ok "[OK] $message"
    log_event cmd_done "${CURRENT_STEP_INDEX:-unknown}" ok "$message" "$dur"
  else 
    warn "[FAIL] $message (exit $rc)"
    # Show last few lines of output for debugging
    if [ -f "$logf" ]; then
      tail -n 12 "$logf" 2>/dev/null | sed 's/^/  > /' || true
    fi
    log_event cmd_done "${CURRENT_STEP_INDEX:-unknown}" fail "$message" "$dur"
  fi
  
  # Clean up temporary log file
  rm -f "$logf" 2>/dev/null || true
  return $rc
}

# Run command with progress but don't fail the script if it fails
# Same parameters as run_with_progress
soft_step(){ 
  run_with_progress "$@" || true
}

# Register a new installation step
# Parameters: step_name, function_name, estimated_time_seconds
cad_register_step(){ 
  STEP_NAME+=("${1:-}")
  STEP_FUNCS+=("${2:-}")
  local eta="${3:-30}"
  
  # Validate eta is numeric
  case "$eta" in
    *[!0-9]*) eta=30 ;;
    *) [ "$eta" -lt 1 ] && eta=30 ;;
  esac
  
  STEP_ETA+=("$eta")
}

# Recalculate total steps and estimated time with safe arithmetic
# Call this after registering all steps
recompute_totals(){ 
  TOTAL_STEPS=${#STEP_NAME[@]}
  TOTAL_EST=0
  
  # Validate TOTAL_STEPS is reasonable
  case "$TOTAL_STEPS" in
    *[!0-9]*) TOTAL_STEPS=0 ;;
    *) 
      if [ "$TOTAL_STEPS" -lt 0 ] 2>/dev/null; then
        TOTAL_STEPS=0
      elif [ "$TOTAL_STEPS" -gt 100 ] 2>/dev/null; then
        TOTAL_STEPS=100  # Cap at reasonable maximum
      fi
      ;;
  esac
  
  # Sum up all step ETAs with safe arithmetic
  # Safe array iteration using bounds-checked index-based loop
  local __step_eta_len=${#STEP_ETA[@]}
  __step_eta_len=${__step_eta_len:-0}
  local __i=0
  while [ "$__i" -lt "$__step_eta_len" ]; do
    local eta_value="${STEP_ETA[$__i]:-30}"
    
    # Validate each ETA value
    case "$eta_value" in
      *[!0-9]*) eta_value=30 ;;  # Default fallback
      *) 
        if [ "$eta_value" -lt 1 ] 2>/dev/null; then
          eta_value=30
        elif [ "$eta_value" -gt 3600 ] 2>/dev/null; then
          eta_value=3600  # Cap at 1 hour per step
        fi
        ;;
    esac
    
    # Safe addition using validated arithmetic
    if is_nonneg_int "${TOTAL_EST:-0}" && is_nonneg_int "$eta_value"; then
      TOTAL_EST=$(add_int "${TOTAL_EST:-0}" "$eta_value")
    fi
    
    __i=$(add_int "$__i" 1) || break
  done
  
  # Ensure TOTAL_EST is reasonable
  if [ "${TOTAL_EST:-0}" -lt 1 ] 2>/dev/null; then
    TOTAL_EST=300  # 5 minute minimum
  elif [ "$TOTAL_EST" -gt 36000 ] 2>/dev/null; then
    TOTAL_EST=36000  # 10 hour maximum
  fi
}

# Begin execution of a step with safe arithmetic
# Sets up timing, displays header, logs start
start_step(){
  # CURRENT_STEP_INDEX is already set by the caller, no need to increment here
  
  local start_time
  start_time=$(date +%s 2>/dev/null || echo 0)
  STEP_START_TIME[$CURRENT_STEP_INDEX]="$start_time"
  
  # Calculate progress percentage based on accumulated time with safe arithmetic
  local pct
  pct=$(safe_progress_div "$PROGRESS_ACCUM" "$TOTAL_EST")
  
  local step_name="${STEP_NAME[$CURRENT_STEP_INDEX]:-Unknown Step}"
  local step_number=1
  local total_steps="${TOTAL_STEPS:-1}"
  
  # Safe arithmetic for step numbers
  if [ "$CURRENT_STEP_INDEX" -ge 0 ] 2>/dev/null; then
    step_number=$(add_int "${CURRENT_STEP_INDEX:-0}" 1)
  fi
  
  local txt
  txt=$(printf 'Phase %d / %d  (%d%%)\n%s' "$step_number" "$total_steps" "$pct" "$step_name")
  
  # Display the phase header
  draw_phase_header "$txt"
  log_event step_start "$CURRENT_STEP_INDEX" start "$step_name"
  
  # Show disk usage if debugging is enabled
  if [ "${DISK_DEBUG:-0}" = "1" ] && command -v df >/dev/null 2>&1; then
    df -h "$PREFIX" 2>/dev/null | tail -1 | awk '{print "[DISK] "$0}' || true
  fi
}

# Complete execution of a step with safe arithmetic
# Records timing, updates progress, logs completion
end_step(){
  local current_index="${CURRENT_STEP_INDEX:-0}"
  
  # Validate step index is numeric and in range
  case "$current_index" in
    *[!0-9-]*) return 1 ;;  # Not numeric
    *) 
      if [ "$current_index" -lt 0 ] 2>/dev/null; then
        return 1
      fi
      ;;
  esac
  
  # Record end time and calculate duration with safe arithmetic
  local end_time start_time duration
  end_time=$(date +%s 2>/dev/null || echo 0)
  start_time="${STEP_START_TIME[$current_index]:-0}"
  
  # Safe duration calculation using validated arithmetic
  if is_nonneg_int "$end_time" && is_nonneg_int "$start_time" && [ "$end_time" -ge "$start_time" ]; then
    duration=$(sub_int "$end_time" "$start_time")
  else
    duration=0
  fi
  
  STEP_END_TIME[$current_index]="$end_time"
  STEP_DURATIONS[$current_index]="$duration"
  
  # Update accumulated progress for percentage calculation with safe arithmetic
  local eta="${STEP_ETA[$current_index]:-30}"
  case "$eta" in *[!0-9]*) eta=30 ;; esac
  
  if [ "${PROGRESS_ACCUM:-0}" -ge 0 ] 2>/dev/null && [ "$eta" -ge 0 ] 2>/dev/null; then
    PROGRESS_ACCUM=$((PROGRESS_ACCUM + eta))
  fi
  
  # Log step completion
  local step_name="${STEP_NAME[$current_index]:-Unknown}"
  local status="${STEP_STATUS[$current_index]:-unknown}"
  log_event step_end "$current_index" "$status" "$step_name" "$duration"
}

# Mark the current step's status with safe array access
# Parameter: status_string
mark_step_status(){ 
  local status="${1:-unknown}" current_idx="${CURRENT_STEP_INDEX:-0}"
  
  # Validate current index is numeric and reasonable
  case "$current_idx" in
    *[!0-9-]*) return 1 ;;  # Not numeric, abort
    *) 
      if [ "$current_idx" -ge 0 ] 2>/dev/null && [ "$current_idx" -lt 1000 ] 2>/dev/null; then
        STEP_STATUS[$current_idx]="$status"
      fi
      ;;
  esac
}

# --- Input Validation and User Interaction ---

# Validate user input against a regular expression pattern
# Parameters: input_string, regex_pattern, field_description
# Returns: 0 (success) if valid, 1 (failure) if invalid
validate_input(){ 
  local input="$1" pattern="$2" label="$3"
  
  # Check for empty input
  if [ -z "$input" ]; then
    warn "$label empty"
    return 1
  fi
  
  # Check input length
  if [ "${#input}" -gt "$MAX_INPUT_LENGTH" ]; then
    warn "$label too long (max $MAX_INPUT_LENGTH chars)"
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

# Read non-empty input from user with validation
# Parameters: prompt_text, variable_name, default_value (optional), validation_type (optional)
# validation_type can be: "username" (default), "email", "filename"
read_nonempty(){
  local prompt="${1:-Enter value}" var_name="${2:-TEMP_VAR}" def="${3:-}" validation_type="${4:-username}"
  local attempts=0 max_attempts=3
  local validation_regex
  
  # Validate function parameters
  if [ -z "$var_name" ]; then
    warn "read_nonempty: variable name required"
    return 1
  fi
  
  # Validate variable name contains only safe characters
  case "$var_name" in
    *[!a-zA-Z0-9_]*) 
      warn "Invalid variable name: $var_name"
      return 1
      ;;
  esac
  
  # Select appropriate validation regex based on type
  case "$validation_type" in
    email) validation_regex="$ALLOWED_EMAIL_REGEX" ;;
    filename) validation_regex="$ALLOWED_FILENAME_REGEX" ;;
    username|*) validation_regex="$ALLOWED_USERNAME_REGEX" ;;
  esac
  
  while [ "$attempts" -lt "$max_attempts" ]; do
    pecho "$PASTEL_CYAN" "$prompt:"
    local v=""
    
    # Handle read with timeout for non-interactive mode
    if [ "$NON_INTERACTIVE" = "1" ] && [ -n "$def" ]; then
      v="$def"
      printf "%s\n" "$def"
    else
      IFS= read -r v || v=""
    fi
    
    if [ -z "$v" ] && [ -n "$def" ]; then
      # Use default value if provided and input is empty - direct assignment by variable name
      if [ "$NON_INTERACTIVE" != "1" ]; then
        printf "%s\n" "$def"
      fi
      # Direct assignment for known variable names to avoid eval
      case "$var_name" in
        TERMUX_USERNAME) TERMUX_USERNAME="$def" ;;
        GIT_USERNAME) GIT_USERNAME="$def" ;;
        GIT_EMAIL) GIT_EMAIL="$def" ;;
        UBUNTU_USERNAME) UBUNTU_USERNAME="$def" ;;
        *) 
          warn "Unknown variable for assignment: $var_name"
          return 1
          ;;
      esac
      return 0
    elif [ -n "$v" ]; then
      # Validate the input based on type
      if validate_input "$v" "$validation_regex" "Input"; then
        # Direct assignment for known variable names
        case "$var_name" in
          TERMUX_USERNAME) TERMUX_USERNAME="$v" ;;
          GIT_USERNAME) GIT_USERNAME="$v" ;;
          GIT_EMAIL) GIT_EMAIL="$v" ;;
          UBUNTU_USERNAME) UBUNTU_USERNAME="$v" ;;
          *) 
            warn "Unknown variable for assignment: $var_name"
            return 1
            ;;
        esac
        return 0
      fi
    else
      warn "Value cannot be empty"
    fi
    
    attempts=$(add_int "$attempts" 1)
  done
  
  # Use default if all attempts failed - direct assignment
  if [ -n "$def" ]; then
    case "$var_name" in
      TERMUX_USERNAME) TERMUX_USERNAME="$def" ;;
      GIT_USERNAME) GIT_USERNAME="$def" ;;
      GIT_EMAIL) GIT_EMAIL="$def" ;;
      UBUNTU_USERNAME) UBUNTU_USERNAME="$def" ;;
      *) 
        warn "Unknown variable for fallback assignment: $var_name"
        return 1
        ;;
    esac
    return 0
  fi
  
  return 1
}

# Securely read password input with confirmation
# Parameters: prompt_text, confirm_prompt_text, variable_name
# Stores password in secure credential file
secure_password_input(){
  local prompt="$1" confirm="$2" var="$3" pw pw2 tries=0 max_tries=3
  
  # Auto-generate password in non-interactive mode
  if [ "$NON_INTERACTIVE" = "1" ]; then
    # Generate a random password using available entropy sources
    if command -v openssl >/dev/null 2>&1; then
      pw=$(openssl rand -base64 12 2>/dev/null | tr -d '\n' | head -c 12)
    elif [ -r /dev/urandom ]; then
      pw=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12 2>/dev/null || echo "defaultpass123")
    else
      pw="defaultpass123"
    fi
    
    # Ensure minimum length
    [ "${#pw}" -lt "$MIN_PASSWORD_LENGTH" ] && pw="${pw}abc123"
  else
    # Interactive password input
    while [ "$tries" -lt "$max_tries" ]; do
      tries=$(add_int "${tries:-0}" 1)
      
      # Read password (hidden input)
      pecho "$PASTEL_CYAN" "$prompt:"
      read -rs pw || pw=""
      echo
      
      # Check minimum length
      if [ "${#pw}" -lt "$MIN_PASSWORD_LENGTH" ]; then
        warn "Password too short (minimum $MIN_PASSWORD_LENGTH characters)"
        pw=""
        continue
      fi
      
      # Read confirmation (hidden input)
      pecho "$PASTEL_CYAN" "$confirm:"
      read -rs pw2 || pw2=""
      echo
      
      # Check if passwords match
      if [ "$pw" = "$pw2" ]; then
        break
      fi
      
      warn "Passwords do not match (attempt $tries/$max_tries)"
      pw=""
      pw2=""
    done
  fi
  
  if [ -z "$pw" ]; then
    return 1
  fi
  
  # Ensure credential directory exists
  mkdir -p "$CRED_DIR" 2>/dev/null || return 1
  
  # Save password to secure credential file
  local cf="$CRED_DIR/${var}_password"
  umask 077  # Ensure restrictive permissions
  if printf "%s" "$pw" > "$cf" 2>/dev/null; then
    chmod 600 "$cf" 2>/dev/null || true
  else
    return 1
  fi
  
  # Clear password variables from memory
  pw=""
  pw2=""
  return 0
}

# Wrapper function for password input (for backwards compatibility)
read_password_confirm(){ 
  secure_password_input "$1" "$2" "$3"
}

# Return appropriate estimated time based on FAST_MODE setting
# Parameters: normal_time, fast_time
ETA(){ 
  local normal="${1:-30}" fast="${2:-10}"
  
  # Validate inputs are numeric
  case "$normal" in *[!0-9]*) normal=30 ;; esac
  case "$fast" in *[!0-9]*) fast=10 ;; esac
  
  [ "${FAST_MODE:-0}" = "1" ] && echo "$fast" || echo "$normal"
}

# Read a stored credential from secure storage
# Parameter: credential_name
# Returns: credential value or empty string
read_credential(){ 
  local name="$1"
  [ -z "$name" ] && return 1
  
  local f="$CRED_DIR/${name}_password"
  if [ -f "$f" ] && [ -r "$f" ]; then
    cat "$f" 2>/dev/null || true
  fi
}

# Remove potentially dangerous characters from strings
# Parameter: input_string
# Returns: sanitized string with only alphanumeric, period, underscore, dash
sanitize_string(){ 
  printf "%s" "${1:-}" | tr -cd '[:alnum:]._-'
}

# Ask user a yes/no question with default answer using safe attempt counting
# Parameters: question, default_answer(y/n)
# Returns: 0 for yes, 1 for no
ask_yes_no(){
  local question="$1" default="${2:-n}" answer
  
  # Auto-answer in non-interactive mode
  if [ "$NON_INTERACTIVE" = "1" ]; then
    case "$default" in
      y|Y|yes|YES) return 0 ;;
      *) return 1 ;;
    esac
  fi
  
  # Interactive prompt with safe attempt counting
  local attempts=0 max_attempts=3
  while [ "$attempts" -lt "$max_attempts" ] 2>/dev/null; do
    if [ "$default" = "y" ]; then
      printf "%s [Y/n]: " "$question"
    else
      printf "%s [y/N]: " "$question"
    fi
    
    read -r answer
    answer="${answer:-$default}"
    
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) 
        warn "Please answer y or n"
        # Safe increment using validated arithmetic
        if is_nonneg_int "$attempts" && [ "$attempts" -lt 10 ]; then
          attempts=$(add_int "$attempts" 1)
        else
          attempts="$max_attempts"  # Force exit
        fi
        
        # Check if this was the last attempt
        if [ "$attempts" -ge "$max_attempts" ] 2>/dev/null; then
          warn "Using default: $default"
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

# --- System Detection and Configuration ---

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

# --- Termux:API Detection and Interaction ---

# Wait for Termux:API app to be available with safe arithmetic
# Returns: 0 if available, 1 if not available after timeout
wait_for_termux_api(){
  if [ "${TERMUX_API_FORCE_SKIP:-0}" = "1" ]; then
    TERMUX_API_VERIFIED="skipped"
    return 0
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
  
  TERMUX_API_VERIFIED="no"
  warn "Termux:API unavailable."
  return 1
}

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

# Show countdown prompt with auto-continue option using safe arithmetic
# Parameters: prompt_text, timeout_seconds, auto_continue_message
# Returns: 0 if user pressed Enter, 1 if timed out
countdown_prompt(){
  local prompt="$1" timeout="$2" auto_msg="$3"
  
  # Validate timeout is numeric
  case "$timeout" in
    *[!0-9]*) timeout=10 ;;
    *) 
      if [ "$timeout" -lt 1 ] 2>/dev/null; then timeout=10; fi
      if [ "$timeout" -gt 300 ] 2>/dev/null; then timeout=300; fi
      ;;
  esac
  
  echo -e "$prompt"
  
  local remaining="$timeout"
  while [ "$remaining" -gt 0 ] 2>/dev/null; do
    printf "\rContinuing in %2ds (Enter to proceed) " "$remaining"
    
    # Wait 1 second or until user presses Enter
    if read -r -t 1 2>/dev/null; then 
      echo
      return 0
    fi
    
    # Safe decrement
    if [ "$remaining" -gt 1 ] 2>/dev/null; then
      remaining=$(sub_int "${remaining:-0}" 1)
    else
      remaining=0
    fi
  done
  
  echo
  info "$auto_msg"
  return 1
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

# --- File Management and APK Handling ---

# NEW: Use Termux file picker to select APK directory with improved UX
select_apk_directory(){
  # Set default location first
  local default_location="/storage/emulated/0/Download/CAD-Droid-APKs"
  USER_SELECTED_APK_DIR="$default_location"
  
  info "APK File Location Setup"
  echo ""
  format_body_text "Your APK files will be downloaded to a folder for easy installation. You can choose a custom location or use the default Downloads folder."
  echo ""
  info "Default location: $default_location"
  echo ""
  
  # Check if termux-storage-get is available
  if ! command -v termux-storage-get >/dev/null 2>&1; then
    warn "Termux file picker not available, using default location"
    mkdir -p "$USER_SELECTED_APK_DIR" 2>/dev/null || true
    return 0
  fi
  
  # Ask user if they want to choose a custom location
  if [ "$NON_INTERACTIVE" != "1" ]; then
    if ask_yes_no "Use default location?" "y"; then
      info "Using default location: $USER_SELECTED_APK_DIR"
      mkdir -p "$USER_SELECTED_APK_DIR" 2>/dev/null || true
      return 0
    fi
    
    echo ""
    info "File Picker Instructions:"
    format_body_text "The Android file picker will open. Navigate to where you want to save APK files, then tap any file in that folder (the file itself doesn't matter - we just need to know which folder you want)."
    echo ""
    pecho "$PASTEL_CYAN" "Press Enter when ready to open the file picker..."
    read -r || true
    
    # Use termux-storage-get to let user pick a file (to determine directory)
    local temp_file="$TMPDIR/selected_path.txt"
    
    info "Opening file picker..."
    if termux-storage-get "$temp_file" 2>/dev/null; then
      # The user selected a file, extract the directory and clean any null bytes
      local selected_path
      if [ -f "$temp_file" ]; then
        # Clean null bytes and read the path
        selected_path=$(tr -d '\0' < "$temp_file" 2>/dev/null | head -1)
        rm -f "$temp_file" 2>/dev/null
        
        if [ -n "$selected_path" ] && [ "$selected_path" != "null" ]; then
          # Get the directory part of the selected path and add our subfolder
          USER_SELECTED_APK_DIR="$(dirname "$selected_path")/CAD-Droid-APKs"
          info "Selected location: $USER_SELECTED_APK_DIR"
        else
          warn "Invalid selection, using default location"
          USER_SELECTED_APK_DIR="$default_location"
        fi
      else
        warn "No file created by picker, using default location"
        USER_SELECTED_APK_DIR="$default_location"
      fi
    else
      warn "File picker cancelled or failed, using default location"
      USER_SELECTED_APK_DIR="$default_location"
    fi
  else
    # Non-interactive mode - use default
    USER_SELECTED_APK_DIR="$default_location"
  fi
  
  # Ensure the directory exists and is writable
  if ! mkdir -p "$USER_SELECTED_APK_DIR" 2>/dev/null; then
    warn "Cannot create selected directory, falling back to default"
    USER_SELECTED_APK_DIR="$default_location"
    mkdir -p "$USER_SELECTED_APK_DIR" 2>/dev/null || {
      warn "Cannot create any directory, APK downloads may fail"
      return 1
    }
  fi
  
  ok "APK files will be saved to: $USER_SELECTED_APK_DIR"
  return 0
}

# Open file manager to specified directory using multiple fallback methods
# Parameter: target_directory
open_file_manager(){
  local target="$1"
  
  # Validate and create target directory
  if [ -z "$target" ]; then
    warn "No target directory specified"
    return 1
  fi
  
  if ! mkdir -p "$target" 2>/dev/null; then
    warn "Cannot create directory: $target"
    return 1
  fi
  
  info "APK directory: $target"
  echo "INSTRUCTIONS:"
  echo "  1. Press Enter to open folder (view only)."
  pecho "$PASTEL_GREEN" "  2. Install *.apk add-ons."
  echo "  3. Return & continue."
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    pecho "$PASTEL_CYAN" "Press Enter to open folder..."
    read -r || true
  fi
  
  local opened=0
  
  # Method 1: Termux wiki approach - exact command without modifications
  if [ $opened -eq 0 ] && command -v am >/dev/null 2>&1; then
    # Use exact Termux wiki command without any path modifications
    if am start -a android.intent.action.VIEW -d "content://com.android.externalstorage.documents/root/primary" >/dev/null 2>&1; then
      opened=1
    fi
  fi
  
  # Method 2: Android intent with VIEW action (fallback)
  if [ $opened -eq 0 ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "file://$target" >/dev/null 2>&1; then
      opened=1
    fi
  fi
  
  # Method 3: termux-open with directory
  if [ $opened -eq 0 ] && command -v termux-open >/dev/null 2>&1; then
    if termux-open "$target" 2>/dev/null; then
      opened=1
    fi
  fi
  
  # Method 4: termux-open-url with file URI
  if [ $opened -eq 0 ] && command -v termux-open-url >/dev/null 2>&1; then
    if termux-open-url "file://$target" >/dev/null 2>&1; then
      opened=1
    fi
  fi
  
  # Method 5: Desktop fallback (if running in desktop environment)
  if [ $opened -eq 0 ] && command -v xdg-open >/dev/null 2>&1; then
    if xdg-open "$target" >/dev/null 2>&1; then
      opened=1
    fi
  fi
  
  # If all methods failed, show manual instruction
  if [ $opened -eq 0 ]; then
    warn "Automatic open failed. Manually browse to: $target"
  fi
}

# --- APK Download Helper Functions ---

# Verify APK file meets minimum size requirements
# Parameter: file_path
# Returns: 0 if valid size, 1 if too small or missing
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
  
  # Verify it's a valid APK by checking ZIP signature (PK header)
  if ! head -c 4 "$f" 2>/dev/null | grep -q "PK"; then
    warn "Invalid APK file: missing ZIP signature"
    rm -f "$f" 2>/dev/null || true
    return 1
  fi
  
  # Additional validation for Android APK structure (less strict)
  if command -v unzip >/dev/null 2>&1; then
    if ! unzip -qq -t "$f" >/dev/null 2>&1; then
      warn "APK file appears to be corrupted"
      rm -f "$f" 2>/dev/null || true
      return 1
    fi
    
    # Check for required APK components (more lenient check)
    local manifest_check
    manifest_check=$(unzip -l "$f" 2>/dev/null | grep -i "manifest\|META-INF" | head -1)
    if [ -z "$manifest_check" ]; then
      warn "APK file missing required components, but continuing anyway"
    fi
  fi
  
  info "APK verified: $(basename "$f") (${sz} bytes)"
  return 0
}

# Wrapper for curl with consistent timeout settings
curl_get(){ 
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi
  
  curl -fsSL --connect-timeout "$CURL_CONNECT" --max-time "$CURL_MAX_TIME" "$@"
}

# Wrapper for wget with consistent timeout settings
wget_get(){
  if ! command -v wget >/dev/null 2>&1; then
    return 1
  fi
  
  wget -q --timeout="$CURL_MAX_TIME" --tries=2 "$@"
}

# Generic HTTP fetch with fallbacks
http_fetch(){
  local url="$1" output="$2"
  
  if [ -z "$url" ] || [ -z "$output" ]; then
    return 1
  fi
  
  # Try wget only for APK downloads (no curl fallback due to 404 errors)
  if wget_get -O "$output" "$url"; then
    return 0
  else
    return 1
  fi
}

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

# NEW: Enhanced GitHub release fetch that preserves original filenames
# Parameters: repository_path, filename_pattern, output_directory, app_name
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

# NEW: Enhanced Termux add-on fetch that preserves original APK names and prioritizes GitHub
# Parameters: addon_name, package_id, github_repo, filename_pattern, output_directory
# Returns: 0 if successful, 1 if failed
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

# --- Remote Desktop (Sunshine) Helper Functions ---

# Bash function block for finding Sunshine Debian packages
# This gets embedded into the container setup script
SUNSHINE_FUNCTION_BLOCK=$(cat <<'SUNSHINE_EOF'
find_sunshine_deb(){
  local arch="$1" api="https://api.github.com/repos/LizardByte/Sunshine/releases/latest" url=""
  
  # Validate architecture parameter
  case "$arch" in
    arm64|amd64|armhf) ;;
    *) return 1 ;;
  esac
  
  # Try with jq first for reliable JSON parsing
  if command -v jq >/dev/null 2>&1; then
    url=$(curl -fsSL --connect-timeout 8 --max-time 30 "$api" 2>/dev/null | \
          jq -r --arg a "$arch" ".assets[]? | select(.name|endswith(\"${a}.deb\")) | .browser_download_url" 2>/dev/null | \
          head -1)
  fi
  
  # Fallback to grep if jq is missing or failed
  if [ -z "$url" ] || [ "$url" = "null" ]; then
    url=$(curl -fsSL --connect-timeout 8 --max-time 30 "$api" 2>/dev/null | \
          grep -Eo "https://[^\" ]+${arch}\\.deb" 2>/dev/null | \
          head -1)
  fi
  
  # Output URL or empty string if not found
  echo "${url:-}"
}
SUNSHINE_EOF
)

# Verify the health status of Sunshine remote desktop service
# Sets SUNSHINE_HEALTH global variable
verify_sunshine_health(){
  if [ "$ENABLE_SUNSHINE" != "1" ]; then
    SUNSHINE_HEALTH="disabled"
    return 0
  fi
  
  local root="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
  if [ ! -d "$root" ]; then
    SUNSHINE_HEALTH="no-rootfs"
    return 0
  fi
  
  # Check if Sunshine is installed and get version
  local out
  out=$(timeout 10 proot-distro login "$DISTRO" -- bash -lc 'command -v sunshine >/dev/null 2>&1 && sunshine --version 2>/dev/null | head -1 || echo __NO__' 2>/dev/null || echo "__NO__")
  
  if echo "$out" | grep -q "__NO__"; then 
    SUNSHINE_HEALTH="missing"
  elif [ -n "$out" ]; then 
    SUNSHINE_HEALTH="ok: $out"
  else 
    SUNSHINE_HEALTH="unknown"
  fi
}

# --- NEW: Enhanced Android Debug Bridge (ADB) Wireless Helper ---

# Get current open ports on localhost
get_localhost_ports(){
  local ports=()
  if command -v nmap >/dev/null 2>&1; then
    # Use nmap to scan for open ports on localhost
    local nmap_output
    nmap_output=$(nmap -Pn -T4 -p 1000-65535 localhost 2>/dev/null | grep "^[0-9]" | grep "open" | awk '{print $1}' | cut -d'/' -f1)
    if [ -n "$nmap_output" ]; then
      while IFS= read -r port; do
        ports+=("$port")
      done <<< "$nmap_output"
    fi
  elif command -v ss >/dev/null 2>&1; then
    # Fallback to ss if nmap is not available
    local ss_output
    ss_output=$(ss -tlnH 2>/dev/null | awk '{print $4}' | grep "127.0.0.1\|localhost\|::" | cut -d':' -f2)
    if [ -n "$ss_output" ]; then
      while IFS= read -r port; do
        [ -n "$port" ] && ports+=("$port")
      done <<< "$ss_output"
    fi
  fi
  
  printf '%s\n' "${ports[@]}"
}

# Monitor for new ports appearing on localhost
# Parameters: timeout_seconds, scan_interval_seconds
# Returns: new port number if found, empty if timeout
monitor_for_new_port(){
  local timeout="${1:-60}" interval="${2:-2}"
  local initial_ports new_ports
  
  # Get initial port list
  mapfile -t initial_ports < <(get_localhost_ports | sort -n)
  info "Monitoring for new ADB wireless debugging ports..."
  info "Initial ports: ${initial_ports[*]}"
  
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    safe_sleep "$interval"
    elapsed=$((elapsed + interval))
    
    # Get current port list
    mapfile -t new_ports < <(get_localhost_ports | sort -n)
    
    # Find new ports by comparing arrays
    local port
    for port in "${new_ports[@]}"; do
      local found=0
      local initial_port
      for initial_port in "${initial_ports[@]}"; do
        if [ "$port" = "$initial_port" ]; then
          found=1
          break
        fi
      done
      
      # If port wasn't in initial list, it's new
      if [ "$found" -eq 0 ]; then
        # Verify it's likely an ADB port (typically in ranges 5555, 37000-45000)
        if [ "$port" -eq 5555 ] || ([ "$port" -ge 37000 ] && [ "$port" -le 45000 ]); then
          echo "$port"
          return 0
        fi
      fi
    done
    
    # Show progress every 10 seconds
    if [ $((elapsed % 10)) -eq 0 ]; then
      info "Still monitoring... (${elapsed}s/${timeout}s)"
    fi
  done
  
  return 1
}

# Show Termux GUI dialog for pairing code input
# Parameters: host, port
# Returns: 0 if pairing successful, 1 if failed
show_pairing_dialog(){
  local host="$1" port="$2"
  
  if [ -z "$host" ] || [ -z "$port" ]; then
    return 1
  fi
  
  # Check if termux-dialog is available
  if ! command -v termux-dialog >/dev/null 2>&1; then
    warn "Termux:GUI dialog not available"
    return 1
  fi
  
  info "Showing pairing code dialog..."
  
  # Show dialog asking for pairing code
  local result
  result=$(termux-dialog text -i "ADB Pairing Code" -t "Enter the pairing code for $host:$port" 2>/dev/null)
  
  if [ $? -eq 0 ] && [ -n "$result" ]; then
    # Extract the text from JSON response
    local code
    if command -v jq >/dev/null 2>&1; then
      code=$(echo "$result" | jq -r '.text // empty' 2>/dev/null)
    else
      # Fallback parsing
      code=$(echo "$result" | grep -o '"text":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [ -n "$code" ]; then
      info "Attempting to pair with code: $code"
      
      # Verify ADB is installed
      if ! command -v adb >/dev/null 2>&1; then
        warn "adb not installed."
        return 1
      fi
      
      # Attempt to pair with the device
      if adb pair "$host:$port" "$code" >/dev/null 2>&1; then
        ok "ADB pairing successful with $host:$port"
        return 0
      else
        warn "ADB pairing failed"
        return 1
      fi
    fi
  fi
  
  warn "No pairing code provided or dialog cancelled"
  return 1
}

# NEW: Enhanced ADB wireless setup with smart port detection
adb_wireless_helper(){
  if [ "$ENABLE_ADB" != "1" ]; then
    return 0
  fi
  
  info "ADB Wireless Setup with Smart Port Detection"
  
  # Check if we have the required tools
  if [ "$NMAP_READY" != "1" ] && ! command -v ss >/dev/null 2>&1; then
    warn "Neither nmap nor ss available for port scanning"
    return 1
  fi
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    info "This will monitor for new wireless debugging ports."
    info "Please enable 'Wireless debugging' in Android Developer Options."
    pecho "$PASTEL_CYAN" "Press Enter when ready to start monitoring..."
    read -r || true
  fi
  
  # Try to detect Wi-Fi IP address
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip -o -4 addr show wlan0 2>/dev/null | awk '{print $4}' | head -1 | cut -d'/' -f1)
    if [ -z "$ip" ]; then
      ip=$(ip -o -4 addr show wlan 2>/dev/null | awk '{print $4}' | head -1 | cut -d'/' -f1)
    fi
  fi
  
  if [ -z "$ip" ]; then
    # Fallback to localhost
    ip="127.0.0.1"
    info "Using localhost IP for ADB connection"
  else
    info "Detected Wi-Fi IP: $ip"
  fi
  
  # Monitor for new ports (60 second timeout, check every 2 seconds)
  local new_port
  new_port=$(monitor_for_new_port 60 2)
  
  if [ -n "$new_port" ]; then
    ok "Detected new ADB port: $new_port"
    
    # Show pairing dialog if Termux:GUI is available
    if command -v termux-dialog >/dev/null 2>&1; then
      if show_pairing_dialog "$ip" "$new_port"; then
        return 0
      fi
    else
      # Fallback to manual input
      local code=""
      if [ "$NON_INTERACTIVE" != "1" ]; then
        pecho "$PASTEL_CYAN" "Enter pairing code for $ip:$new_port:"
        read -r code
        
        if [ -n "$code" ]; then
          if command -v adb >/dev/null 2>&1; then
            if adb pair "$ip:$new_port" "$code" >/dev/null 2>&1; then
              ok "ADB pairing successful"
              return 0
            else
              warn "ADB pairing failed"
            fi
          else
            warn "adb command not available"
          fi
        fi
      fi
    fi
  else
    warn "No new ADB ports detected within timeout period"
    info "Please ensure 'Wireless debugging' is enabled and try again"
  fi
  
  return 1
}

# --- Container and SSH Configuration ---

# Check if a proot-distro Linux distribution is installed
# Parameter: distro_name
# Returns: 0 if installed, 1 if not installed
is_distro_installed(){ 
  local distro="$1"
  [ -n "$distro" ] && [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$distro" ]
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
    input="${input:-$default_val}"
    
    # Validate input is numeric
    case "$input" in
      *[!0-9-]*) 
        warn "Please enter a number between $min_val and $max_val"
        ;;
      *) 
        # Check range with safe arithmetic
        if [ "$input" -ge "$min_val" ] 2>/dev/null && [ "$input" -le "$max_val" ] 2>/dev/null; then
          case "$var_name" in
            sel) sel="$input" ;;
            *) warn "Unknown variable for assignment: $var_name" ;;
          esac
          return 0
        else
          warn "Please enter a number between $min_val and $max_val"
        fi
        ;;
    esac
    
    # Safe increment using validated arithmetic
    if is_nonneg_int "$attempts" && [ "$attempts" -lt 10 ]; then
      attempts=$(add_int "$attempts" 1)
    else
      attempts="$max_attempts"  # Force exit
    fi
    
    # Use default if max attempts reached
    if [ "$attempts" -ge "$max_attempts" ] 2>/dev/null; then
      warn "Using default: $default_val"
      case "$var_name" in
        sel) sel="$default_val" ;;
        *) warn "Unknown variable for default assignment: $var_name" ;;
      esac
      return 0
    fi
  done
  
  return 1
}

# Verify health of all installed services
# Sets various *_HEALTH global variables  
verify_all_health(){
  verify_sunshine_health
  # Add other health checks as needed
  info "Health verification completed"
}

# Save completion state to JSON file with completely safe operations
save_completion_state(){
  local json_file="${STATE_JSON:-$HOME/.cad-droid-state.json}"
  local successful=0
  
  # Safe calculation using our wrapper
  successful=$(count_successful_steps)
  
  # Validate all variables before using
  local version="${SCRIPT_VERSION:-unknown}"
  local completion_time distro api_verified total_steps
  
  completion_time=$(date -Iseconds 2>/dev/null || date)
  distro="${DISTRO:-unknown}"
  api_verified="${TERMUX_API_VERIFIED:-no}"
  total_steps="${TOTAL_STEPS:-0}"
  
  # Validate numeric values
  case "$successful" in *[!0-9]*) successful=0 ;; esac
  case "$total_steps" in *[!0-9]*) total_steps=0 ;; esac
  
  local json
  json=$(cat <<JSON_STATE_EOF
{
  "version": "$version",
  "completion_time": "$completion_time",
  "distro": "$distro",
  "termux_api_verified": "$api_verified",
  "total_steps": $total_steps,
  "successful_steps": $successful
}
JSON_STATE_EOF
)
  
  if echo "$json" > "$json_file" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Count number of successful steps with safe arithmetic
count_successful_steps(){
  local count=0
  local status_value
  
  # Safely iterate through status array
  local total_steps=${#STEP_STATUS[@]}
  local step_index=0
  
  while [ "$step_index" -lt "$total_steps" ] 2>/dev/null; do
    status_value="${STEP_STATUS[$step_index]:-}"
    
    if [ "$status_value" = "success" ]; then
      # Safe increment
      if [ "$count" -lt 1000 ] 2>/dev/null; then
        count=$(add_int "${count:-0}" 1)
      fi
    fi
    
    # Safe increment of loop counter using validated arithmetic
    if is_nonneg_int "${step_index:-0}" && [ "$step_index" -lt 1000 ]; then
      step_index=$(add_int "$step_index" 1)
    else
      break  # Safety break to prevent infinite loops
    fi
  done
  
  echo "$count"
}

# Show completion summary with statistics using safe array operations
show_completion_summary(){
  local successful=0 failed=0 total_steps="${TOTAL_STEPS:-0}"
  
  # Safe calculation of successful steps
  successful=$(count_successful_steps)
  
  # Validate successful count is numeric
  case "$successful" in
    *[!0-9]*) successful=0 ;;
    *) 
      if [ "$successful" -lt 0 ] 2>/dev/null; then
        successful=0
      fi
      ;;
  esac
  
  # Safe calculation of failed steps using validated arithmetic
  if is_nonneg_int "$total_steps" && is_nonneg_int "$successful" && [ "$total_steps" -ge "$successful" ]; then
    failed=$(sub_int "$total_steps" "$successful")
  else
    failed=0
  fi
  
  draw_card "Setup Complete!" "Successfully completed $successful/$total_steps steps"
  
  if [ "$failed" -gt 0 ] 2>/dev/null; then
    warn "$failed steps had issues - check logs for details"
  fi
}

# Show final completion message
show_final_completion(){
  echo
  draw_phase_header "*** CAD-Droid Setup Complete! ***"
  echo
  info "Your secure Android development environment is ready!"
  info "Check the logs for any warnings or additional setup steps."
  echo
}

# Run single step by name or index
# Parameter: step_identifier (name substring or index)
run_single_step(){
  local identifier="$1" i
  
  if [ -z "$identifier" ]; then
    err "Step identifier required"
    return 1
  fi
  
  # Initialize if needed
  if [ ${#STEP_NAME[@]} -eq 0 ]; then
    initialize_steps
  fi
  
  # Try to find step by index first
  if [[ "$identifier" =~ ^[0-9]+$ ]] && [ "$identifier" -gt 0 ] && [ "$identifier" -le "${TOTAL_STEPS:-0}" ]; then
    if is_nonneg_int "$identifier"; then
      i=$(sub_int "$identifier" 1)
    else
      i=0
    fi
    local step_name="${STEP_NAME[$i]:-Unknown Step}"
    local step_display
    step_display=$(add_int "$i" 1)
    info "Running step $step_display: $step_name"
    
    local func="${STEP_FUNCS[$i]:-}"
    if [ -n "$func" ] && declare -f "$func" >/dev/null 2>&1; then
      "$func"
      return $?
    else
      err "Step function '$func' not found"
      # Debug: Show detailed information about the lookup failure
      err "Debug info for missing function '$func':"
      err "- Total registered steps: ${#STEP_NAME[@]}"
      err "- Current step index: $i"
      err "- Step name: ${STEP_NAME[$i]:-UNDEFINED}"
      err "- Function name in array: ${STEP_FUNCS[$i]:-UNDEFINED}"
      # Debug: List all available functions starting with step_
      err "Available step functions:"
      declare -F | grep "step_" | head -10 || err "No step functions found"
      return 1
    fi
  fi
  
  # Try to find step by name substring using safe index-based iteration
  local __step_name_len=${#STEP_NAME[@]}
  __step_name_len=${__step_name_len:-0}
  local __i=0
  while [ "$__i" -lt "$__step_name_len" ]; do
    if [[ "${STEP_NAME[$__i]:-}" == *"$identifier"* ]]; then
      local step_name="${STEP_NAME[$__i]}"
      local step_num
      step_num=$(add_int "$__i" 1)
      info "Running step $step_num: $step_name"
      
      local func="${STEP_FUNCS[$__i]:-}"
      if [ -n "$func" ] && declare -f "$func" >/dev/null 2>&1; then
        "$func"
        return $?
      else
        err "Step function '$func' not found"
        # Debug: Show detailed information about the lookup failure  
        err "Debug info for missing function '$func':"
        err "- Total registered steps: ${#STEP_NAME[@]}"
        err "- Current step index: $__i"
        err "- Step name: ${STEP_NAME[$__i]:-UNDEFINED}"
        err "- Function name in array: ${STEP_FUNCS[$__i]:-UNDEFINED}"
        # Debug: List all available functions starting with step_
        err "Available step functions:"
        declare -F | grep "step_" | head -10 || err "No step functions found"
        return 1
      fi
    fi
    __i=$(add_int "$__i" 1) || break
  done
  
  err "Step not found: $identifier"
  return 1
}

# Initialize steps if not already done
initialize_steps(){
  # Clear existing arrays
  STEP_NAME=()
  STEP_FUNCS=()
  STEP_ETA=()
  
  # Register all installation steps
  cad_register_step "Storage Setup" "step_storage" 15
  cad_register_step "Mirror Selection" "step_mirror" 20  
  cad_register_step "System Bootstrap" "step_bootstrap" 35
  cad_register_step "X11 Repository" "step_x11repo" 25
  cad_register_step "APT Configuration" "step_aptni" 15
  cad_register_step "System Update" "step_systemup" 45
  cad_register_step "Network Tools" "step_nettools" 30
  cad_register_step "APK Installation" "step_apk" 30
  cad_register_step "User Configuration" "step_usercfg" 10
  cad_register_step "ADB Wireless Setup" "step_adb" 20
  cad_register_step "Package Prefetch" "step_prefetch" 60
  cad_register_step "Core Installation" "step_coreinst" 90
  cad_register_step "XFCE Desktop" "step_xfce" 75
  cad_register_step "Container Setup" "step_container" 120
  cad_register_step "Final Configuration" "step_final" 25
  
  # Calculate totals
  recompute_totals
}

# Show help information
show_help(){
  cat << 'HELP_EOF'
CAD-Droid Mobile Development Setup - Help

USAGE:
  ./setup.sh [OPTIONS]

OPTIONS:
  --help                    Show this help message  
  --version                 Show script information
  --non-interactive         Run without asking questions
  --only-step <N|name>      Run just one specific step
  --doctor                  Check your system for problems

ENVIRONMENT VARIABLES:
  NON_INTERACTIVE=1         Answer yes to everything automatically
  AUTO_GITHUB=1             Skip GitHub SSH key setup  
  ENABLE_SUNSHINE=0         Don't install remote desktop streaming
  SKIP_ADB=1                Skip ADB wireless debugging setup
  DEBUG=1                   Show extra details about what's happening
  
Want more options? Check the comments at the top of this script.
HELP_EOF
}

# Run system diagnostics
run_diagnostics(){
  draw_phase_header "System Diagnostics"
  
  # Termux version
  if command -v termux-info >/dev/null 2>&1; then
    info "Termux version: $(termux-info | head -1 2>/dev/null || echo 'Unknown')"
  else
    info "Termux version: Unknown"
  fi
  
  # Android version
  if command -v getprop >/dev/null 2>&1; then
    info "Android version: $(getprop ro.build.version.release 2>/dev/null || echo 'Unknown')"
  else
    info "Android version: Unknown"
  fi
  
  # Architecture
  info "Architecture: $(uname -m 2>/dev/null || echo 'Unknown')"
  
  # Available storage
  if command -v df >/dev/null 2>&1; then
    local storage
    storage=$(df -h "$PREFIX" 2>/dev/null | tail -1 | awk '{print $4}' || echo 'Unknown')
    info "Available storage: $storage"
  else
    info "Available storage: Unknown"
  fi
  
  # Termux:API status
  if have_termux_api; then
    info "Termux:API: Available and functional"
  else
    warn "Termux:API: Not available or not functional"
  fi
  
  info "Diagnostics complete"
}

# Configure Linux container environment with users, SSH, and Sunshine
# This is the main container setup function
configure_linux_env(){
  # Generate SSH port
  LINUX_SSH_PORT=$(random_port)
  
  # Get user configuration
  read_nonempty "Linux username" UBUNTU_USERNAME "caduser"
  
  if ! read_password_confirm "Password for $UBUNTU_USERNAME (hidden)" "Confirm password" "linux_user"; then
    err "User password setup failed"
    return 1
  fi
  
  if ! read_password_confirm "Root password (hidden)" "Confirm password" "linux_root"; then
    err "Root password setup failed"
    return 1
  fi

  # Generate SSH key for container access
  local ssh_dir="$HOME/.ssh"
  mkdir -p "$ssh_dir" 2>/dev/null || {
    err "Cannot create SSH directory"
    return 1
  }
  chmod 700 "$ssh_dir" 2>/dev/null
  
  local ssh_key="$ssh_dir/id_ed25519"
  if [ ! -f "$ssh_key" ]; then
    run_with_progress "Generate container key" 8 bash -c "
      umask 077
      ssh-keygen -t ed25519 -f '$ssh_key' -N '' -C 'container-access' >/dev/null 2>&1 || exit 1
    "
  fi
  
  # Read the SSH public key
  local pubkey
  if [ -f "${ssh_key}.pub" ]; then
    pubkey=$(cat "${ssh_key}.pub" 2>/dev/null || echo "")
  else
    err "SSH key generation failed"
    return 1
  fi
  
  # Retrieve stored passwords
  local user_pass root_pass
  user_pass=$(read_credential "linux_user" || echo "")
  root_pass=$(read_credential "linux_root" || echo "")
  
  if [ -z "$user_pass" ]; then
    err "User credential retrieval failed"
    return 1
  fi
  
  if [ -z "$root_pass" ]; then
    err "Root credential retrieval failed"
    return 1
  fi

  # Detect system architecture for package selection
  local arch='arm64'
  case "$(uname -m)" in
    aarch64|arm64) arch='arm64';;
    x86_64|amd64) arch='amd64';;
    armv7l) arch='armhf';;
  esac

  # Create container configuration script
  # This script will run inside the container to set everything up
  local script
  script=$(cat <<'CONTAINER_SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

# Configuration variables (will be replaced by actual values)
NEW_USER="__NEWUSER__"
USER_PASS="__USER_PASS__"
ROOT_PASS="__ROOT_PASS__"
SSH_PUBLIC_KEY="__PUBKEY__"
SSH_PORT="__SSH_PORT__"
ARCH_HINT="__ARCH__"
ENABLE_SUN="__ENABLE_SUNSHINE__"

# Include Sunshine detection function
__SUNFUNCS__

# Detect Linux distribution
detect_os(){ 
  local id="unknown"
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    id="${ID:-unknown}"
  fi
  echo "$id"
}

# Install packages for Debian-based systems (Ubuntu, Debian)
pkg_install_debian(){
  export DEBIAN_FRONTEND=noninteractive
  # Update package lists
  apt-get update >/dev/null 2>&1 || true
  # Upgrade existing packages
  apt-get -y upgrade >/dev/null 2>&1 || true
  # Install essential packages for productivity environment
  apt-get -y install sudo openssh-server wget curl jq nano dbus-x11 ffmpeg ca-certificates >/dev/null 2>&1 || true
}

# Install packages for Arch Linux
pkg_install_arch(){
  # Update system and packages
  pacman -Syu --noconfirm >/dev/null 2>&1 || true
  # Install essential packages
  pacman -S --noconfirm sudo openssh wget curl jq nano ffmpeg dbus >/dev/null 2>&1 || true
}

# Install packages for Alpine Linux
pkg_install_alpine(){
  # Update package index
  apk update >/dev/null 2>&1 || true
  # Install essential packages
  apk add sudo openssh wget curl jq nano ffmpeg dbus >/dev/null 2>&1 || true
}

# Install Sunshine remote desktop streaming service
install_sunshine(){
  [ "$ENABLE_SUN" = "1" ] || return 0
  local os="$1"
  
  case "$os" in
    debian|ubuntu)
      # Download and install Sunshine .deb package
      local url
      url=$(find_sunshine_deb "$ARCH_HINT")
      if [ -n "$url" ]; then
        if curl -fsSL --connect-timeout 8 --max-time 90 -o /tmp/sunshine.deb "$url"; then
          if dpkg -i /tmp/sunshine.deb >/dev/null 2>&1 || apt-get -y -f install >/dev/null 2>&1; then
            rm -f /tmp/sunshine.deb
          fi
        fi
      fi
      ;;
    arch) 
      # Install from Arch repositories
      pacman -S --noconfirm sunshine >/dev/null 2>&1 || true 
      ;;
    alpine) 
      echo "Sunshine unsupported on Alpine." 
      ;;
  esac
  
  # Create Sunshine startup script if installed
  if command -v sunshine >/dev/null 2>&1; then
    cat > /usr/local/bin/start_sunshine.sh <<'SUNSHINE_SCRIPT_EOF'
#!/usr/bin/env bash
sunshine >/var/log/sunshine.log 2>&1 &
echo "Sunshine started."
SUNSHINE_SCRIPT_EOF
    chmod +x /usr/local/bin/start_sunshine.sh
  fi
}

# Create user account and configure permissions
create_user(){
  # Set root password
  echo "root:$ROOT_PASS" | chpasswd
  
  # Create user if doesn't exist
  if ! id -u "$NEW_USER" >/dev/null 2>&1; then
    case "$(detect_os)" in
      alpine) adduser -D "$NEW_USER" ;;
      *) useradd -m -s /bin/bash "$NEW_USER" 2>/dev/null || adduser "$NEW_USER" ;;
    esac
  fi
  
  # Set user password
  echo "$NEW_USER:$USER_PASS" | chpasswd
  
  # Grant sudo privileges to user (use literal string to avoid shell expansion)
  echo '$NEW_USER ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  
  # Set up SSH key authentication
  local home="/home/$NEW_USER" sshd="$home/.ssh"
  mkdir -p "$sshd"
  echo "$SSH_PUBLIC_KEY" > "$sshd/authorized_keys"
  chmod 700 "$sshd"
  chmod 600 "$sshd/authorized_keys"
  chown -R "$NEW_USER:$NEW_USER" "$sshd" 2>/dev/null || true
}

# Configure SSH daemon with security hardening
harden_sshd(){
  local cfg="/etc/ssh/sshd_config"
  
  # Remove existing port configuration
  sed -i '/^Port /d' "$cfg"
  echo "Port $SSH_PORT" >> "$cfg"
  
  # Security configurations
  local lines=(
    "PasswordAuthentication no"        # Only allow key-based auth
    "PermitRootLogin no"              # Disable root login
    "PubkeyAuthentication yes"        # Enable SSH key auth
    "AllowUsers $NEW_USER"            # Only allow our user
    "ClientAliveInterval 120"         # Keep connections alive
    "ClientAliveCountMax 2"           # Max missed keepalives
  )
  
  # Apply each configuration line
  for ln in "${lines[@]}"; do
    local key="${ln%% *}"
    if grep -q "^$key" "$cfg"; then
      sed -i "s/^$key.*/$ln/" "$cfg"
    else
      echo "$ln" >> "$cfg"
    fi
  done
  
  # Start SSH daemon
  /usr/sbin/sshd || /usr/sbin/sshd -D & 
}

# Install launcher script for host desktop environment
install_host_launcher(){
  cat > /usr/local/bin/launch_host_desktop.sh <<'HOST_DESKTOP_SCRIPT_EOF'
#!/usr/bin/env bash
# Launch desktop in portrait mode for productivity
export DISPLAY=:0

# Termux installation prefix
TP="/data/data/com.termux/files/usr"

# Start X11 server in portrait mode if not running
if ! pgrep -f termux-x11 >/dev/null 2>&1; then 
  "$TP/bin/termux-x11" :0 -geometry 1080x1920 >/dev/null 2>&1 & 
  sleep 2
fi

# Start XFCE desktop session if not running
if ! pgrep -f xfce4-session >/dev/null 2>&1; then 
  DISPLAY=:0 "$TP/bin/xfce4-session" >/dev/null 2>&1 & 
  sleep 2
fi

# Start D-Bus session for inter-process communication
dbus-daemon --session --fork >/dev/null 2>&1 || true

echo "Desktop environment active (Portrait Mode)."
HOST_DESKTOP_SCRIPT_EOF
  chmod +x /usr/local/bin/launch_host_desktop.sh

  # Also create landscape version for Sunshine streaming
  cat > /usr/local/bin/launch_sunshine_desktop.sh <<'LANDSCAPE_DESKTOP_SCRIPT_EOF'
#!/usr/bin/env bash
# Launch desktop in landscape mode for remote streaming
export DISPLAY=:0

# Termux installation prefix  
TP="/data/data/com.termux/files/usr"

# Stop existing X11 server
pkill -f termux-x11 2>/dev/null || true
sleep 1

# Start X11 server in landscape mode for streaming
"$TP/bin/termux-x11" :0 -geometry 1920x1080 >/dev/null 2>&1 &
sleep 3

# Configure display resolution
export DISPLAY=:0
xrandr --output default --mode 1920x1080 2>/dev/null || true

# Start XFCE desktop session if not running
if ! pgrep -f xfce4-session >/dev/null 2>&1; then 
  DISPLAY=:0 "$TP/bin/xfce4-session" >/dev/null 2>&1 & 
  sleep 3
fi

# Start D-Bus session
dbus-daemon --session --fork >/dev/null 2>&1 || true

echo "Desktop environment active (Landscape Mode for Streaming)."
LANDSCAPE_DESKTOP_SCRIPT_EOF
  chmod +x /usr/local/bin/launch_sunshine_desktop.sh
}

# Main setup function that coordinates all configuration
main(){
  local os
  os=$(detect_os)
  
  # Install packages based on detected OS
  case "$os" in
    debian|ubuntu) pkg_install_debian ;;
    arch) pkg_install_arch ;;
    alpine) pkg_install_alpine ;;
    *) echo "Unknown OS $os" ;;
  esac
  
  # Set up Sunshine remote desktop service
  install_sunshine "$os"
  
  # Create and configure user account
  create_user
  
  # Configure and start SSH daemon
  harden_sshd
  
  # Install desktop launcher scripts
  install_host_launcher
  
  # Save configuration for later reference
  echo "$SSH_PORT" > /root/port.txt
  echo "$NEW_USER" > /root/username.txt
}

# Execute main setup function
main
CONTAINER_SCRIPT_EOF
)

  # Replace placeholders in the script with actual values
  script="${script/__SUNFUNCS__/$SUNSHINE_FUNCTION_BLOCK}"
  script="${script//__NEWUSER__/${UBUNTU_USERNAME//\"/\\\"}}"
  script="${script//__USER_PASS__/${user_pass//\"/\\\"}}"
  script="${script//__ROOT_PASS__/${root_pass//\"/\\\"}}"
  script="${script//__PUBKEY__/${pubkey//\"/\\\"}}"
  script="${script//__SSH_PORT__/$LINUX_SSH_PORT}"
  script="${script//__ARCH__/$arch}"
  script="${script//__ENABLE_SUNSHINE__/$ENABLE_SUNSHINE}"

  # Execute the container configuration script
  if run_with_progress "Configure container + Sunshine" 185 bash -c "
    proot-distro login '$DISTRO' --shared-tmp --fix-low-ports -- bash -lc \"
      cat > /root/autocfg.sh << 'EOF_SCRIPT'
$script
EOF_SCRIPT
      chmod +x /root/autocfg.sh
      bash /root/autocfg.sh 2>&1 | grep -Ev '^(Selecting previously|Preparing|Unpacking|Setting up|Processing triggers|Get:|Fetched|Reading|Building)'
    \"
  "; then
    ok "Container configuration successful"
  else
    err "Container configuration failed"
    return 1
  fi

  # Configure SSH client on Termux side
  local ssh_config="$HOME/.ssh/config"
  mkdir -p "$HOME/.ssh" 2>/dev/null
  
  if ! grep -q "Host cad-container" "$ssh_config" 2>/dev/null; then
    cat >> "$ssh_config" <<SSH_CONFIG_EOF
Host cad-container
  HostName localhost
  Port $LINUX_SSH_PORT
  User $UBUNTU_USERNAME
  StrictHostKeyChecking accept-new
  ServerAliveInterval 120
  ServerAliveCountMax 2
SSH_CONFIG_EOF
  fi
}

# Ensure SSH daemon is running in container
ensure_container_sshd(){
  local root="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO" pf="$root/root/port.txt"
  
  if [ ! -f "$pf" ]; then
    return 0
  fi
  
  # Get SSH port from saved configuration
  local p
  p=$(cat "$pf" 2>/dev/null || echo "$LINUX_SSH_PORT")
  
  # Check if SSH is already listening on the port
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | grep -q ":$p "; then
      return 0
    fi
  fi
  
  # Start SSH daemon if not running
  proot-distro login "$DISTRO" -- bash -lc '/usr/sbin/sshd || /usr/sbin/sshd -D & sleep 1' 2>/dev/null || true
}

# --- Productivity Widget Creation ---

# Create helpful desktop shortcuts for productivity workflows
create_widget_shortcuts(){
  if [ "$ENABLE_WIDGETS" != "1" ]; then
    return 0
  fi
  
  local shortcuts_dir="$HOME/.shortcuts"
  mkdir -p "$shortcuts_dir" 2>/dev/null || return 1

  # Create Linux Desktop shortcut (Portrait Mode for Productivity)
  cat > "$shortcuts_dir/Linux Desktop.sh" <<'DESKTOP_WIDGET_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
echo "Starting Linux Desktop (Portrait Mode)..."

# Start X11 server in portrait orientation for productive vertical screen space
if ! pgrep -f termux-x11 >/dev/null 2>&1; then 
  termux-x11 :0 -geometry 1080x1920 >/dev/null 2>&1 & 
  sleep 2
fi

# Start XFCE desktop environment optimized for portrait productivity
if ! pgrep -f xfce4-session >/dev/null 2>&1; then 
  DISPLAY=:0 xfce4-session >/dev/null 2>&1 & 
  sleep 2
fi

echo "Desktop started in Portrait Mode for optimal productivity."
DESKTOP_WIDGET_EOF

  # Create Professional Workspace shortcut (Landscape Mode for Presentations/Streaming)
  cat > "$shortcuts_dir/Professional Workspace.sh" <<'WORKSPACE_WIDGET_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
echo "Starting Professional Workspace (Landscape Mode)..."

# Stop existing X11 server to change orientation
pkill -f termux-x11 2>/dev/null || true
sleep 1

# Start X11 server in landscape mode for presentations and streaming
DISPLAY=:0 termux-x11 :0 -geometry 1920x1080 >/dev/null 2>&1 &
sleep 3

# Configure display resolution for professional use
export DISPLAY=:0
xrandr --output default --mode 1920x1080 2>/dev/null || true

# Start XFCE desktop optimized for presentations
if ! pgrep -f xfce4-session >/dev/null 2>&1; then 
  DISPLAY=:0 xfce4-session >/dev/null 2>&1 & 
  sleep 3
fi

pecho "$PASTEL_GREEN" "Professional Workspace Ready (Landscape Mode for presentations and streaming)!"
WORKSPACE_WIDGET_EOF

  # Create Linux Terminal shortcut
  cat > "$shortcuts_dir/Linux Terminal.sh" <<'TERMINAL_WIDGET_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
echo "Connecting to Linux container..."

# Try to connect to available Linux distributions
proot-distro login ubuntu || proot-distro login debian || proot-distro login archlinux || proot-distro login alpine
TERMINAL_WIDGET_EOF

  # Create System Status shortcut
  cat > "$shortcuts_dir/System Status.sh" <<'STATUS_WIDGET_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
echo "CAD-Droid Productivity System Status"
echo "===================================="

PREFIX="/data/data/com.termux/files/usr"

# Check X11 desktop status
if pgrep -f termux-x11 >/dev/null 2>&1; then 
  pecho "$PASTEL_GREEN" "✓ Termux-X11: Running"
else 
  echo "✗ Termux-X11: Not running"
fi

# Check XFCE desktop status
if pgrep -f xfce4-session >/dev/null 2>&1; then 
  pecho "$PASTEL_GREEN" "✓ XFCE Desktop: Running"
else 
  echo "✗ XFCE Desktop: Not running"
fi

echo ""
echo "Linux Containers:"

# Check status of each possible Linux distribution
for d in ubuntu debian archlinux alpine; do
  if [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$d" ]; then
    pecho "$PASTEL_GREEN" "✓ $d: Installed"
    
    # Check SSH status if configured
    if [ -f "$PREFIX/var/lib/proot-distro/installed-rootfs/$d/root/port.txt" ]; then
      p=$(cat "$PREFIX/var/lib/proot-distro/installed-rootfs/$d/root/port.txt")
      if ss -ltn 2>/dev/null | grep -q ":$p "; then 
        echo "  ✓ SSH: Listening on port $p"
      else 
        echo "  ✗ SSH: Not listening"
      fi
    fi
  fi
done

# Check Sunshine remote desktop status
if pgrep -f sunshine >/dev/null 2>&1; then 
  pecho "$PASTEL_GREEN" "✓ Sunshine: Running"
else 
  echo "✗ Sunshine: Not running"
fi

echo ""

# Display storage usage information
df -h "$PREFIX" 2>/dev/null | tail -1 | awk '{print "Termux Storage: "$3"/"$2" ("$5" used)"}'

# Show shared storage if available
[ -d "$HOME/storage/shared" ] && df -h "$HOME/storage/shared" 2>/dev/null | tail -1 | awk '{print "Shared Storage: "$3"/"$2" ("$5" used)"}'
STATUS_WIDGET_EOF

  # Make all shortcuts executable
  chmod +x "$shortcuts_dir"/*.sh 2>/dev/null || true
  ok "Productivity widget shortcuts created"
}

# --- System Snapshot Functions ---

# Get path to container root filesystem
container_rootfs(){ 
  echo "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
}

# Create a compressed snapshot of the container
# Parameter: snapshot_name
create_snapshot(){
  if [ "$ENABLE_SNAPSHOTS" != "1" ]; then
    warn "Snapshots disabled"
    return 0
  fi
  
  local name="$1"
  if [ -z "$name" ]; then
    err "Snapshot name required"
    return 1
  fi
  
  # Validate snapshot name
  if ! validate_input "$name" "$ALLOWED_FILENAME_REGEX" "Snapshot name"; then
    return 1
  fi
  
  local root
  root=$(container_rootfs)
  if [ ! -d "$root" ]; then
    err "Container rootfs not found"
    return 1
  fi
  
  local outdir="$SNAP_DIR/$DISTRO"
  if ! mkdir -p "$outdir" 2>/dev/null; then
    err "Cannot create snapshot directory"
    return 1
  fi
  
  local out="$outdir/${name}.tar.gz"
  if [ -f "$out" ]; then
    warn "Snapshot already exists: $out"
    return 1
  fi
  
  info "Creating snapshot: $out"
  
  # Create compressed snapshot using pigz if available for faster compression
  if (cd "$root" && { 
    if command -v pigz >/dev/null 2>&1; then 
      tar -cf - . | pigz -9 > "$out"
    else 
      tar -czf "$out" .
    fi
  }); then
    ok "Snapshot created successfully"
    return 0
  else
    err "Snapshot creation failed"
    rm -f "$out" 2>/dev/null
    return 1
  fi
}

# List all available snapshots
list_snapshots(){
  if [ "$ENABLE_SNAPSHOTS" != "1" ]; then
    warn "Snapshots disabled"
    return 0
  fi
  
  local dir="$SNAP_DIR/$DISTRO"
  if [ ! -d "$dir" ]; then
    warn "No snapshot directory found"
    return 0
  fi
  
  local files
  files=$(find "$dir" -name "*.tar.gz" -type f 2>/dev/null | sort)
  if [ -z "$files" ]; then
    warn "No snapshots found"
    return 0
  fi
  
  echo "Available snapshots:"
  echo "$files" | while read -r file; do
    local basename
    basename=$(basename "$file" .tar.gz)
    local size
    size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
    printf "  %s (%s)\n" "$basename" "${size:-unknown}"
  done
}

# Restore container from a snapshot
# Parameter: snapshot_name  
restore_snapshot(){
  if [ "$ENABLE_SNAPSHOTS" != "1" ]; then
    warn "Snapshots disabled"
    return 0
  fi
  
  local name="$1" 
  if [ -z "$name" ]; then
    err "Snapshot name required"
    return 1
  fi
  
  local root
  root=$(container_rootfs)
  local in="$SNAP_DIR/$DISTRO/${name}.tar.gz"
  
  if [ ! -f "$in" ]; then
    err "Snapshot not found: $in"
    return 1
  fi
  
  info "Restoring snapshot: $in"
  
  # Remove existing container and restore from snapshot
  rm -rf "$root" 2>/dev/null || {
    err "Cannot remove existing container"
    return 1
  }
  
  if ! mkdir -p "$root" 2>/dev/null; then
    err "Cannot create container directory"
    return 1
  fi
  
  if command -v pigz >/dev/null 2>&1; then 
    if pigz -dc "$in" | tar -C "$root" -xf -; then
      ok "Snapshot restored successfully"
      return 0
    fi
  else 
    if tar -C "$root" -xzf "$in"; then
      ok "Snapshot restored successfully"
      return 0
    fi
  fi
  
  err "Snapshot restore failed"
  return 1
}

# --- Metrics and Summary Generation ---

# Write installation metrics to JSON file for analysis
write_metrics_json(){
  local json_file="setup-summary.json"
  
  local json
  json=$(cat <<METRICS_JSON_EOF
{
  "termux_user": "${TERMUX_USERNAME//\"/\\\"}",
  "mirror_name": "${SELECTED_MIRROR_NAME//\"/\\\"}",
  "mirror_url": "${SELECTED_MIRROR_URL//\"/\\\"}",
  "distro": "${DISTRO//\"/\\\"}",
  "ssh_port": "${LINUX_SSH_PORT//\"/\\\"}",
  "sunshine_health": "${SUNSHINE_HEALTH//\"/\\\"}",
  "termux_api_verified": "${TERMUX_API_VERIFIED//\"/\\\"}",
  "user_selected_apk_dir": "${USER_SELECTED_APK_DIR//\"/\\\"}",
  "core_packages_processed": $DOWNLOAD_COUNT,
  "missing_apks": [
METRICS_JSON_EOF
)
  
  # Add missing APKs array
  local i
  for i in "${!APK_MISSING[@]}"; do
    json="${json}\"${APK_MISSING[$i]//\"/\\\"}\""
    if [ "$i" -lt $(( ${#APK_MISSING[@]}-1 )) ]; then
      json="${json},"
    fi
  done
  
  json="${json}],\"steps\":["
  
  # Add step information
  for i in "${!STEP_NAME[@]}"; do
    local step_json
    step_json=$(printf '{"index":%d,"name":"%s","duration_sec":%d,"status":"%s"}' \
      "$((i+1))" "${STEP_NAME[$i]//\"/\\\"}" "${STEP_DURATIONS[$i]:-0}" "${STEP_STATUS[$i]:-unknown}")
    json="${json}${step_json}"
    if [ "$i" -lt $(( ${#STEP_NAME[@]}-1 )) ]; then
      json="${json},"
    fi
  done
  
  json="${json}]}"
  
  # Write metrics file
  if printf "%s\n" "$json" > "$json_file" 2>/dev/null; then
    ok "Metrics written: $json_file"
    return 0
  else
    warn "Failed to write metrics file"
    return 1
  fi
}

# --- Installation Step Functions ---
# Each of these functions performs a specific part of the setup process

# Initialize directory structure and credentials storage
initialize_directories(){
  # Create work directories
  WORK_DIR="$HOME/.cad"
  CRED_DIR="$WORK_DIR/credentials"
  STATE_DIR="$WORK_DIR/state"
  LOG_DIR="$WORK_DIR/logs"
  SNAP_DIR="$WORK_DIR/snapshots"
  
  # Create all directories
  for dir in "$WORK_DIR" "$CRED_DIR" "$STATE_DIR" "$LOG_DIR" "$SNAP_DIR"; do
    if ! mkdir -p "$dir" 2>/dev/null; then
      err "Cannot create directory: $dir"
      return 1
    fi
    chmod 700 "$dir" 2>/dev/null
  done
  
  # Set up log files
  EVENT_LOG="$LOG_DIR/setup-events.json"
  STATE_JSON="$STATE_DIR/completion-state.json"
  
  return 0
}

# ===== UTILITY FUNCTIONS USED BY STEPS =====

# Check if package is installed
dpkg_is_installed(){ 
  dpkg -s "$1" >/dev/null 2>&1
}

# Check if package is available for installation
pkg_available(){ 
  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}' | grep -vq none
}

# Install package if needed and available
apt_install_if_needed(){
  local p="$1"
  
  # Update package lists first
  run_with_progress "Update package lists" 3 bash -c "apt-get update >/dev/null 2>&1"
  
  # Skip if already installed
  if dpkg_is_installed "$p"; then
    return 0
  fi
  
  # Skip if not available
  if ! pkg_available "$p"; then
    warn "$p unavailable"
    return 0
  fi
  
  # Install the package - treat exit code 100 as success (already installed)
  run_with_progress "Install $p" 18 bash -c "apt-get -y install $p >/dev/null 2>&1 || [ \$? -eq 100 ]"
}

# Ensure wget/curl is available for downloads
ensure_download_tool(){
  # Check if we have curl or wget
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi
  
  if command -v wget >/dev/null 2>&1; then
    return 0
  fi
  
  # Install wget if neither is available
  run_with_progress "Install wget for downloads" 10 bash -c "apt-get update >/dev/null 2>&1 && apt-get -y install wget >/dev/null 2>&1 || [ \$? -eq 100 ]"
}

# Step 1: Configure storage access and permissions
step_storage(){
  # Initialize directories first
  if ! initialize_directories; then
    err "Directory initialization failed"
    return 1
  fi
  
  # Request Android storage permissions if not already granted
  if [ ! -d "$HOME/storage/shared" ]; then
    soft_step "Request storage permission" 10 bash -c 'command -v termux-setup-storage >/dev/null 2>&1 && termux-setup-storage || exit 0'
  fi
  
  # Configure enhanced Termux properties
  local termux_dir="$HOME/.termux"
  mkdir -p "$termux_dir" 2>/dev/null || true
  local prop="$termux_dir/termux.properties"
  
  info "Configuring enhanced Termux properties with extra keys..."
  
  # Create comprehensive termux.properties
  cat > "$prop" << TERMUX_PROPERTIES_EOF
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

  info "Extra keys configuration complete. Keys available:"
  info "  Row 1: ESC, /, -, HOME, UP, END, PGUP"
  info "  Row 2: TAB, CTRL, ALT, LEFT, DOWN, RIGHT, PGDN"
  info "  Long-press keys for additional shortcuts"
  
  # Reload Termux settings to apply changes
  soft_step "Reload termux settings (enhanced)" 5 bash -c '
    if command -v termux-reload-settings >/dev/null 2>&1; then
      termux-reload-settings
      echo "Termux settings reloaded successfully"
    else
      echo "termux-reload-settings not available - please restart Termux to apply changes"
      exit 0
    fi
  '
  
  mark_step_status "success"
}

# Clean up apt sources to prevent conflicts
sanitize_sources_main_only(){
  local d="$PREFIX/etc/apt/sources.list.d"
  if [ ! -d "$d" ]; then
    return 0
  fi
  
  # Remove non-essential source files (keep only X11 related)
  find "$d" -name "*.list" -type f 2>/dev/null | while read -r f; do
    if ! echo "$f" | grep -qi x11; then
      rm -f "$f" 2>/dev/null || true
    fi
  done
}

# Verify and set package mirror configuration
verify_mirror(){
  local sources_file="$PREFIX/etc/apt/sources.list"
  local url
  
  if [ -f "$sources_file" ]; then
    url=$(awk '/^deb /{print $2; exit}' "$sources_file" 2>/dev/null || true)
  fi
  
  if [ -n "$url" ]; then 
    SELECTED_MIRROR_URL="$url"
    if [ -z "$SELECTED_MIRROR_NAME" ]; then
      SELECTED_MIRROR_NAME="(current)"
    fi
  else
    # Set default mirror if none configured
    echo "deb https://packages.termux.dev/apt/termux-main stable main" > "$sources_file"
    SELECTED_MIRROR_NAME="Default"
    SELECTED_MIRROR_URL="https://packages.termux.dev/apt/termux-main"
  fi
}

# Step 2: Mirror selection for faster downloads
step_mirror(){
  info "Choose Termux mirror:"
  
  # Available mirrors with geographic distribution
  local urls=(
    "https://packages.termux.dev/apt/termux-main"
    "https://packages-cf.termux.dev/apt/termux-main"
    "https://fau.mirror.termux.dev/apt/termux-main"
    "https://mirror.bfsu.edu.cn/termux/apt/termux-main"
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
    "https://grimler.se/termux/termux-main"
    "https://termux.mentality.rip/termux/apt/termux-main"
  )
  
  local names=(
    "Default"
    "Cloudflare (US Anycast)"
    "FAU (DE)"
    "BFSU (CN)"
    "Tsinghua (CN)"
    "Grimler (SE)"
    "Mentality (UK)"
  )
  
  # Display mirror options with colors
  local i
  for i in "${!names[@]}"; do 
    local seq
    seq=$(color_for_index "$i")
    printf "%b[%d] %s%b\n" "$seq" "$i" "${names[$i]}" '\033[0m'
  done
  
  local idx=""
  if [ "$NON_INTERACTIVE" = "1" ]; then
    idx=0
  else
    local max_index
    max_index=$(sub_int "${#names[@]}" 1)
    printf "%bMirror (0-%s default 0): %b" "$FALLBACK_COLOR" "$max_index" '\033[0m'
    read -r idx
  fi
  
  # Validate selection
  case "$idx" in
    *[!0-9]*) idx=0 ;;
    *) [ "$idx" -ge "${#urls[@]}" ] && idx=0 ;;
  esac
  
  SELECTED_MIRROR_NAME="${names[$idx]}"
  SELECTED_MIRROR_URL="${urls[$idx]}"
  
  # Write mirror configuration
  run_with_progress "Write mirror config" 5 bash -c "echo 'deb ${SELECTED_MIRROR_URL} stable main' > '$PREFIX/etc/apt/sources.list'"
  
  # Reload settings and clean up sources
  soft_step "Reload termux settings (post-mirror)" 5 bash -c 'command -v termux-reload-settings >/dev/null 2>&1 && termux-reload-settings || exit 0'
  sanitize_sources_main_only
  verify_mirror
  
  # Test the mirror with better error handling
  if run_with_progress "Test mirror connection" 18 bash -c 'apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=10 >/dev/null 2>&1'; then
    ok "Mirror connection successful"
  else
    warn "Mirror connection failed, but continuing..."
    # Force update of package lists
    run_with_progress "Force apt index update" 25 bash -c 'apt-get clean && apt-get update --fix-missing >/dev/null 2>&1 || true'
  fi
  
  mark_step_status "success"
}

# Repair common runtime library issues
repair_runtime_libs(){ 
  local e
  e=$( (date >/dev/null) 2>&1 || true )
  if echo "$e" | grep -qi 'libpcre2-8.so'; then
    run_with_progress "Repair libpcre2" 12 bash -c 'apt-get -y install pcre2 >/dev/null 2>&1 || true'
  fi
}

# Wait for network connectivity with safe arithmetic
network_ready_wait(){ 
  local attempts=3  # Initialize attempts counter safely
  
  while [ "$attempts" -gt 0 ] 2>/dev/null; do
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
      return 0
    fi
    
    # Safe arithmetic decrement using validated helpers
    if is_nonneg_int "$attempts" && [ "$attempts" -gt 1 ]; then
      attempts=$(sub_int "$attempts" 1)
    else
      attempts=0
    fi
    safe_sleep 1
  done
  return 0
}

# Ensure jq JSON processor is available
ensure_jq(){ 
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  run_with_progress "Install jq" 12 bash -c 'apt-get update >/dev/null 2>&1 || true; apt-get -y install jq >/dev/null 2>&1 || true'
}

# Step 3: Bootstrap essential system components
step_bootstrap(){ 
  repair_runtime_libs
  network_ready_wait
  run_with_progress "Baseline apt update" 18 bash -c 'apt-get update >/dev/null 2>&1 || true'
  run_with_progress "Install baseline utils" 28 bash -c 'DEBIAN_FRONTEND=noninteractive apt-get -y -qq install coreutils termux-exec findutils procps grep sed gawk busybox curl jq >/dev/null 2>&1 || true'
  ensure_jq
  mark_step_status "success"
}

# Step 4: Enable X11 repository for desktop packages with safe retry logic
step_x11repo(){ 
  local commands=("apt-get update || true" "apt-get -y install x11-repo || [ \$? -eq 100 ] || false" "apt-get update || true") 
  local labels=("Update apt lists" "Install x11-repo" "Refresh lists") 
  local cmd_index=0
  local max_attempts=3
  
  # Process each command with retry logic
  while [ "$cmd_index" -lt "${#commands[@]}" ] 2>/dev/null; do
    local current_command="${commands[$cmd_index]:-}"
    local current_label="${labels[$cmd_index]:-Command}"
    local attempt=1
    local success=0
    
    # Try each command multiple times for reliability
    while [ "$attempt" -le "$max_attempts" ] 2>/dev/null && [ "$success" -eq 0 ]; do
      if run_with_progress "$current_label" 24 bash -c "$current_command >/dev/null 2>&1"; then
        success=1
        break
      else
        # Only sleep between failed attempts, not after success
        if [ "$attempt" -lt "$max_attempts" ] 2>/dev/null; then
          safe_sleep 1
        fi
        
        # Safe increment using validated arithmetic
        if is_nonneg_int "${attempt:-0}" && [ "$attempt" -lt 10 ]; then
          attempt=$(add_int "$attempt" 1)
        else
          break  # Safety break
        fi
      fi
    done
    
    # Move to next command - safe increment using validated arithmetic
    if is_nonneg_int "${cmd_index:-0}" && [ "$cmd_index" -lt 10 ]; then
      cmd_index=$(add_int "$cmd_index" 1)
    else
      break  # Safety break
    fi
  done
  
  mark_step_status "success"
}

# Step 5: Configure apt for non-interactive operation
step_aptni(){ 
  local d="$PREFIX/etc/apt/apt.conf.d"
  mkdir -p "$d" 2>/dev/null || return 1
  
  # Create configuration file for automated installations
  run_with_progress "Apply apt NI config" 4 bash -c "cat > '$d/99cad-noninteractive' <<'APT_CONFIG_EOF'
APT::Get::Assume-Yes \"true\";
APT::Color \"0\";
Acquire::Retries \"4\";
Dpkg::Progress-Fancy \"0\";
Dpkg::Options { \"--force-confdef\"; \"--force-confold\"; }
APT_CONFIG_EOF
"
  mark_step_status "success"
}

# Step 6: System update and maintenance
step_systemup(){ 
  if run_with_progress "System apt update" 28 bash -c 'apt-get update >/dev/null 2>&1 || true'; then
    :
  else
    apt_fix_broken
  fi
  
  if run_with_progress "System apt upgrade" 75 bash -c 'apt-get -y upgrade >/dev/null 2>&1 || true'; then
    :
  else
    apt_fix_broken
  fi
  
  run_with_progress "Verify termux-exec" 6 bash -c 'dpkg -s termux-exec >/dev/null 2>&1 || apt-get -y install termux-exec >/dev/null 2>&1 || true'
  mark_step_status "success"
}

# Step 7: Install network tools with safe array iteration
step_nettools(){
  local tools=("wget" "nmap")
  local tools_count=${#tools[@]} tool_index=0
  
  # Safe iteration through tools array
  while [ "$tool_index" -lt "$tools_count" ] 2>/dev/null; do
    local current_tool="${tools[$tool_index]:-}"
    
    if [ -n "$current_tool" ]; then
      run_with_progress "Install $current_tool" 18 bash -c "apt-get -y install $current_tool >/dev/null 2>&1 || true"
      
      if command -v "$current_tool" >/dev/null 2>&1; then
        case "$current_tool" in
          wget) WGET_READY=1 ;;
          nmap) NMAP_READY=1 ;;
        esac
      fi
    fi
    
    # Safe increment using validated arithmetic
    if is_nonneg_int "${tool_index:-0}" && [ "$tool_index" -lt 100 ]; then
      tool_index=$(add_int "$tool_index" 1)
    else
      break  # Safety break
    fi
  done
  
  mark_step_status "success"
}

# NEW: Step 8: Enhanced APK Installation with file picker and preserving original names
step_apk(){
  info "Installing required Termux add-on APKs..."
  
  # Ensure download tools are available
  ensure_download_tool
  
  # Check if APK installation is enabled
  if [ "${ENABLE_APK_AUTO:-1}" != "1" ]; then
    info "APK installation disabled - skipping"
    mark_step_status "skipped"
    return 0
  fi
  
  # Let user select APK directory using file picker
  select_apk_directory
  
  local failed=0
  
  # Install Termux:API (required for GitHub setup and other features)
  if ! fetch_termux_addon "Termux-API" "com.termux.api" "termux/termux-api" ".*api.*\.apk" "$USER_SELECTED_APK_DIR"; then
    APK_MISSING+=("Termux:API")
    failed=$(add_int "${failed:-0}" 1)
  fi
  
  # Install Termux:X11 (required for GUI apps)
  if ! fetch_termux_addon "Termux-X11" "com.termux.x11" "termux/termux-x11" ".*x11.*\.apk" "$USER_SELECTED_APK_DIR"; then
    APK_MISSING+=("Termux:X11") 
    failed=$(add_int "${failed:-0}" 1)
  fi
  
  # Install Termux:GUI (additional GUI support)
  if ! fetch_termux_addon "Termux-GUI" "com.termux.gui" "termux/termux-gui" ".*gui.*\.apk" "$USER_SELECTED_APK_DIR"; then
    APK_MISSING+=("Termux:GUI")
    failed=$(add_int "${failed:-0}" 1)
  fi
  
  # Show results and instructions
  if [ "$failed" -eq 0 ]; then
    ok "All APKs downloaded successfully to: $USER_SELECTED_APK_DIR"
  else
    warn "$failed APK(s) failed to download"
    if [ ${#APK_MISSING[@]} -gt 0 ]; then
      warn "Missing APKs will need manual installation:"
      for missing in "${APK_MISSING[@]}"; do
        warn "  - $missing"
      done
    fi
  fi
  
  # Always open APK directory for installation after downloads
  info "Opening APK directory for installation..."
  open_file_manager "$USER_SELECTED_APK_DIR" || warn "Could not open APK directory"
  
  # Pause for manual installation unless in non-interactive mode
  if [ "$NON_INTERACTIVE" != "1" ]; then
    info "Please install the APK files manually by tapping on each .apk file, then press Enter to continue..."
    read -r || true
  else
    info "Non-interactive mode: continuing after ${APK_PAUSE_TIMEOUT:-45}s delay for APK installation"
    safe_sleep "${APK_PAUSE_TIMEOUT:-45}"
  fi
  
  # Wait for Termux:API to become available
  wait_for_termux_api || warn "Termux:API setup may be incomplete"
  
  mark_step_status "success"
}

# Step 9: User configuration and device detection
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
  
  ok "User: $TERMUX_USERNAME"
  
  # Git configuration with timeout handling
  configure_git_with_timeout
  mark_step_status "success"
}

# Step 10: Enhanced ADB Wireless Setup with skip option
step_adb(){
  # Check if ADB is completely disabled or skipped
  if [ "$ENABLE_ADB" != "1" ] || [ "$SKIP_ADB" = "1" ]; then
    if [ "$SKIP_ADB" = "1" ]; then
      info "ADB wireless setup skipped by user request"
    else
      info "ADB wireless setup disabled"
    fi
    mark_step_status "skipped"
    return 0
  fi
  
  # Ask user if they want to skip ADB setup (unless in non-interactive mode)
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    info "Android Debug Bridge (ADB) Wireless Setup"
    format_body_text "ADB allows you to connect wirelessly to your device for development and debugging. This is useful for advanced development workflows but is optional for basic usage."
    echo ""
    
    if ! ask_yes_no "Set up ADB wireless debugging?" "y"; then
      info "Skipping ADB wireless setup"
      mark_step_status "skipped"
      return 0
    fi
  fi
  
  info "Setting up Android Debug Bridge (ADB) wireless connection..."
  echo ""
  format_body_text "This allows you to connect wirelessly to your device for development. You'll need to enable Developer Options and Wireless Debugging on your Android device."
  echo ""
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    pecho "$PASTEL_CYAN" "Press Enter to open Android Developer Settings..."
    read -r || true
  fi
  
  # Try to open developer settings using multiple methods
  local settings_opened=false
  info "Opening Android Developer Settings..."
  
  # Method 1: Direct intent to developer settings
  if command -v am >/dev/null 2>&1; then
    if am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS >/dev/null 2>&1; then
      settings_opened=true
    fi
  fi
  
  # Method 2: General settings as fallback
  if [ "$settings_opened" = false ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.MAIN -n com.android.settings/.Settings >/dev/null 2>&1; then
      settings_opened=true
    fi
  fi
  
  # Method 3: Termux API notification if available
  if have_termux_api; then
    termux-notification --title "CAD-Droid Setup" --content "Enable Developer Options > Wireless Debugging in Android Settings" 2>/dev/null || true
  fi
  
  if [ "$settings_opened" = true ]; then
    info "Android Settings opened"
  else
    info "Unable to open settings automatically"
  fi
  
  echo ""
  info "Follow these steps in Android Settings:"
  info "1. Go to Settings > About phone"
  info "2. Tap 'Build number' 7 times to enable Developer Options"
  info "3. Go back to Settings > System > Developer Options"
  info "4. Enable 'Wireless debugging'"
  info "5. Tap 'Pair device with pairing code'"
  
  # Now run the actual ADB helper with enhanced detection
  adb_wireless_helper
  mark_step_status "success"
}

# Step 11: Pre-download core packages for faster installation
step_prefetch(){
  local need=() p
  
  # Identify packages that need to be installed
  for p in "${CORE_PACKAGES[@]}"; do 
    if ! dpkg_is_installed "$p"; then
      need+=("$p")
    fi
  done
  
  if [ "${#need[@]}" -eq 0 ]; then
    info "All core packages already downloaded - skipping prefetch"
    mark_step_status "success"
    return 0
  fi
  
  # Download packages without installing
  run_with_progress "Download core packages" 28 bash -c "apt-get -y install --download-only ${need[*]} >/dev/null 2>&1 || true"
  mark_step_status "success"
}

# Step 12: Install core productivity packages with safe array iteration and arithmetic
step_coreinst(){
  # Check if all core packages are already installed
  local missing_count=0
  local pkg
  for pkg in "${CORE_PACKAGES[@]}"; do
    if [ -n "$pkg" ] && ! dpkg_is_installed "$pkg"; then
      missing_count=$((missing_count + 1))
    fi
  done
  
  if [ "$missing_count" -eq 0 ]; then
    info "All core packages already installed - skipping installation"
    mark_step_status "success"
    return 0
  fi
  
  local packages_count=${#CORE_PACKAGES[@]} pkg_index=0
  
  # Safe iteration through CORE_PACKAGES array
  while [ "$pkg_index" -lt "$packages_count" ] 2>/dev/null; do
    local current_package="${CORE_PACKAGES[$pkg_index]:-}"
    
    if [ -n "$current_package" ]; then
      apt_install_if_needed "$current_package"
      
      # Safe arithmetic increment for DOWNLOAD_COUNT
      local current_count="${DOWNLOAD_COUNT:-0}"
      case "$current_count" in
        *[!0-9]*) current_count=0 ;;  # Reset if not numeric
      esac
      
      if is_nonneg_int "$current_count" && [ "$current_count" -lt 10000 ]; then
        DOWNLOAD_COUNT=$(add_int "$current_count" 1)
      fi
    fi
    
    # Safe increment for loop counter using validated arithmetic
    if is_nonneg_int "${pkg_index:-0}" && [ "$pkg_index" -lt 1000 ]; then
      pkg_index=$(add_int "$pkg_index" 1)
    else
      break  # Safety break
    fi
  done
  
  mark_step_status "success"
}

# Step 13: Install XFCE desktop environment
step_xfce(){
  if dpkg_is_installed xfce4; then
    info "XFCE desktop environment already installed - skipping installation"
    mark_step_status "success"
    return 0
  fi
  
  # Try installing full XFCE meta-package first
  if run_with_progress "Install xfce4 meta" 55 bash -c 'apt-get -y install xfce4 >/dev/null 2>&1'; then
    mark_step_status "success"
  else
    # Fall back to individual components
    run_with_progress "Install xfce4 parts" 50 bash -c 'apt-get -y install xfce4-session xfce4-panel xfce4-terminal xfce4-settings thunar >/dev/null 2>&1 || true'
    mark_step_status "success"
  fi
}

# Step 14: Linux container setup with user accounts and services
step_container(){
  # Ensure proot-distro is available
  if ! dpkg_is_installed "proot-distro"; then
    info "Installing proot-distro for container support..."
    apt_install_if_needed "proot-distro"
  fi
  
  info "Select Linux distro:"
  local names=("Ubuntu" "Debian" "Arch Linux" "Alpine") i
  
  # Display distribution options with colors using safe array iteration
  local __names_len=${#names[@]}
  __names_len=${__names_len:-0}
  local __i=0
  while [ "$__i" -lt "$__names_len" ]; do
    local seq
    seq=$(color_for_index "$__i")
    local display_num
    display_num=$(add_int "$__i" 1)
    printf "%b[%d] %s%b\n" "$seq" "$display_num" "${names[$__i]}" '\033[0m'
    __i=$(add_int "$__i" 1) || break
  done
  
  # Get user selection
  local sel
  read_option "Select distribution [1-4]" sel 1 4 1
  case "$sel" in
    1) DISTRO="ubuntu" ;;
    2) DISTRO="debian" ;;
    3) DISTRO="arch" ;;
    4) DISTRO="alpine" ;;
    *) DISTRO="ubuntu" ;;
  esac
  
  info "Selected: $DISTRO"
  
  # Install the selected distribution if not already present
  if ! is_distro_installed "$DISTRO"; then
    run_with_progress "Install $DISTRO container" 45 bash -c "proot-distro install $DISTRO >/dev/null 2>&1 || true"
  fi
  
  # Configure Linux environment if distribution is available
  if is_distro_installed "$DISTRO"; then
    if configure_linux_env; then
      mark_step_status "success"
    else
      mark_step_status "failed"
      warn "Container configuration failed"
    fi
  else
    mark_step_status "failed"
    warn "Failed to install $DISTRO distribution"
  fi
}

# Step 15: Finalize installation and generate completion report
step_final(){
  # Create widget shortcuts
  create_widget_shortcuts
  
  # Configure Bash environment
  configure_bash_environment
  
  # Configure Nano editor
  configure_nano_editor
  
  # Verify all services and generate health report
  verify_all_health
  
  # Write metrics JSON
  write_metrics_json
  
  # Create completion state file
  save_completion_state
  
  mark_step_status "success"
}

# Fix common apt/dpkg issues (moved here to be accessible by step functions)
apt_fix_broken(){ 
  run_with_progress "dpkg configure -a" 14 bash -c 'dpkg --configure -a >/dev/null 2>&1 || true'
  run_with_progress "apt -f install" 14 bash -c 'apt-get -y -f install >/dev/null 2>&1 || true'
  run_with_progress "apt clean" 5 bash -c 'apt-get clean >/dev/null 2>&1 || true'
}

# Configure Git and optionally set up GitHub SSH keys with timeout handling
configure_git_with_timeout(){
  # Git basic configuration - fix parameter order for read_nonempty calls
  read_nonempty "Git username" GIT_USERNAME "${TERMUX_USERNAME%@*}" "username"
  read_nonempty "Git email" GIT_EMAIL "${TERMUX_USERNAME%@*}@example.com" "email"
  
  # Confirm Git settings if interactive
  if [ "$NON_INTERACTIVE" != "1" ]; then
    if ! ask_yes_no "Confirm Git username: $GIT_USERNAME" "y"; then
      read_nonempty "Git username" GIT_USERNAME "${TERMUX_USERNAME%@*}" "username"
    fi
    if ! ask_yes_no "Confirm Git email: $GIT_EMAIL" "y"; then
      read_nonempty "Git email" GIT_EMAIL "${TERMUX_USERNAME%@*}@example.com" "email"
    fi
  fi
  
  # Configure Git globally
  run_with_progress "Configure git user" 5 bash -c "git config --global user.name \"$GIT_USERNAME\" 2>/dev/null || true"
  run_with_progress "Configure git email" 5 bash -c "git config --global user.email \"$GIT_EMAIL\" 2>/dev/null || true"
  
  # Skip GitHub setup if AUTO_GITHUB=1 or NON_INTERACTIVE=1
  if [ "$AUTO_GITHUB" = "1" ] || [ "$NON_INTERACTIVE" = "1" ]; then
    info "Skipping GitHub SSH key setup (auto mode)"
    # Still generate SSH key for container access
    generate_ssh_key_if_needed
    return 0
  fi
  
  # Offer GitHub SSH key setup (independent of Termux:API status)
  if ask_yes_no "Set up GitHub SSH key?" "n"; then
    setup_github_ssh_key_with_timeout
  else
    # Generate SSH key anyway for container access
    generate_ssh_key_if_needed
  fi
}

# Generate SSH key if needed (enhanced with dual keys for Git and container access)
generate_ssh_key_if_needed(){
  local git_ssh_key="$HOME/.ssh/id_ed25519_git"
  local container_ssh_key="$HOME/.ssh/id_ed25519_container"
  
  # Ensure .ssh directory exists with proper permissions
  mkdir -p "$HOME/.ssh" 2>/dev/null || true
  chmod 700 "$HOME/.ssh" 2>/dev/null || true
  
  # Ensure openssh is available for SSH key generation
  if ! dpkg_is_installed "openssh"; then
    run_with_progress "Install openssh" 8 bash -c "apt-get update >/dev/null 2>&1 && apt-get -y install openssh >/dev/null 2>&1 || [ \$? -eq 100 ]"
  fi
  
  # Generate Git SSH key if it doesn't exist
  if [ ! -f "$git_ssh_key" ]; then
    info "Generating SSH key for Git operations..."
    local git_comment="${GIT_EMAIL:-user@termux-device}"
    run_with_progress "Generate Git SSH key" 8 bash -c "ssh-keygen -t ed25519 -f \"$git_ssh_key\" -N \"\" -C \"$git_comment\" >/dev/null 2>&1"
  fi
  
  # Generate container SSH key if it doesn't exist
  if [ ! -f "$container_ssh_key" ]; then
    info "Generating SSH key for container access..."
    local container_comment="container-access@${HOSTNAME:-termux}"
    run_with_progress "Generate container SSH key" 8 bash -c "ssh-keygen -t ed25519 -f \"$container_ssh_key\" -N \"\" -C \"$container_comment\" >/dev/null 2>&1"
  fi
  
  # Set proper permissions
  chmod 600 "$git_ssh_key" "$container_ssh_key" 2>/dev/null || true
  chmod 644 "$git_ssh_key.pub" "$container_ssh_key.pub" 2>/dev/null || true
}

# Set up GitHub SSH key with improved Enter-based flow
setup_github_ssh_key_with_timeout(){
  local git_ssh_key="$HOME/.ssh/id_ed25519_git"
  local pub_key_path="$git_ssh_key.pub"
  
  # Ensure SSH keys are generated first
  generate_ssh_key_if_needed
  
  # Check if public key exists
  if [ ! -f "$pub_key_path" ]; then
    warn "SSH public key not found: $pub_key_path"
    return 1
  fi
  
  # Display instructions with proper color rendering
  info "GitHub SSH Key Setup Process:"
  echo ""
  pecho "$PASTEL_CYAN" "1. Your SSH public key will be displayed below"
  pecho "$PASTEL_CYAN" "2. Press Enter to open GitHub SSH settings page"
  pecho "$PASTEL_CYAN" "3. Add the key to your GitHub account"
  pecho "$PASTEL_CYAN" "4. Press Enter again to confirm completion"
  echo ""
  
  # Step 1: Display the public key
  pecho '\033[38;2;255;182;193m' "Press Enter to view your SSH public key..."
  if [ "$NON_INTERACTIVE" != "1" ]; then
    read -r || true
  else
    echo "[AUTO]"
  fi
  
    echo ""
  echo "=== Your SSH Public Key ==="
  cat "$pub_key_path"
  echo "=== End of SSH Key ==="
  echo ""
  
  # Step 2: Show instructions first, then open GitHub settings
  echo ""
  info "Next steps for GitHub SSH key setup:"
  info "1. We'll open GitHub's SSH key settings page for you"
  info "2. Click 'New SSH key' on the GitHub page"  
  info "3. Give it a title (like 'CAD-Droid Mobile Setup')"
  info "4. Copy and paste the SSH key shown above"
  info "5. Click 'Add SSH key' to save it"
  echo ""
  
  pecho '\033[38;2;255;182;193m' "Press Enter to open GitHub SSH settings..."
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    read -r || true
  else
    echo "[AUTO]"
  fi
  
  # Always try to open GitHub SSH settings page
  local github_opened=false
  info "Opening GitHub SSH settings..."
  
  # Copy to clipboard if termux-api is available
  if have_termux_api; then
    info "Copying SSH key to clipboard..."
    termux-clipboard-set < "$pub_key_path" 2>/dev/null || true
  fi
  
  # Try multiple methods to open GitHub (not just termux-api)
  # Method 1: termux-open-url (works with or without Termux:API)
  if command -v termux-open-url >/dev/null 2>&1; then
    if termux-open-url "https://github.com/settings/keys" 2>/dev/null; then
      github_opened=true
    fi
  fi
  
  # Method 2: Android am command with VIEW action
  if [ "$github_opened" = false ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "https://github.com/settings/keys" >/dev/null 2>&1; then
      github_opened=true
    fi
  fi
  
  # Method 3: Desktop environment fallback
  if [ "$github_opened" = false ] && command -v xdg-open >/dev/null 2>&1; then
    if xdg-open "https://github.com/settings/keys" >/dev/null 2>&1; then
      github_opened=true
    fi
  fi
  
  if [ "$github_opened" = true ]; then
    info "GitHub SSH settings page opened in your browser"
  else
    info "Unable to open browser automatically"
    info "Please manually navigate to: https://github.com/settings/keys"
  fi
  
  echo ""
  
  # Step 3: Wait for user confirmation
  if [ "$NON_INTERACTIVE" != "1" ]; then
    pecho '\033[38;2;255;182;193m' "Press Enter when you've added the key to GitHub..."
    read -r || true
    ok "GitHub SSH key setup completed!"
    
    # Configure Git authentication if GitHub CLI is available
    if command -v gh >/dev/null 2>&1; then
      info "Configuring GitHub CLI authentication..."
      # Test if already authenticated
      if ! gh auth status >/dev/null 2>&1; then
        info "To complete GitHub integration, run: gh auth login"
        info "This will allow you to use 'gh' commands for GitHub operations"
      else
        ok "GitHub CLI already authenticated"
      fi
    fi
  else
    info "Non-interactive mode: GitHub setup instructions provided"
  fi
}

# Configure Bash environment with useful settings
configure_bash_environment(){
  info "Setting up your custom Bash environment..."
  
  # Create a personalized .bashrc with all the good stuff
  cat > "$HOME/.bashrc" << 'BASH_CONFIG_EOF'
# Personal Bash configuration for your CAD-Droid setup
# This gives you a much nicer command-line experience
#
# Safety features to prevent common mistakes
set -o noclobber    # Don't accidentally overwrite files
set -o pipefail     # Catch errors in command pipelines
shopt -s extglob    # Enable powerful pattern matching
shopt -s checkwinsize  # Keep terminal size updated
set +H              # Turn off history expansion (avoids ! issues)

# Make your command history much more useful
HISTSIZE=50000      # Remember lots of commands
HISTFILESIZE=100000  # Save even more to disk
HISTCONTROL=ignoreboth:erasedups  # Skip duplicates and commands starting with space
HISTIGNORE="ls:ps:history:exit:clear"  # Don't save these boring commands
shopt -s histappend  # Add to history instead of overwriting
shopt -s cmdhist     # Keep multi-line commands together

# Pretty colors that are easy on the eyes
# Only use colors if your terminal can handle them
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  # Soft, pleasant color palette
  PASTEL_CYAN='\033[38;2;175;238;238m'
  PASTEL_PINK='\033[38;2;255;182;193m' 
  PASTEL_GREEN='\033[38;2;144;238;144m'
  PASTEL_YELLOW='\033[38;2;255;255;224m'
  PASTEL_PURPLE='\033[38;2;221;160;221m'
  PASTEL_BLUE='\033[38;2;173;216;230m'
  PASTEL_ORANGE='\033[38;2;255;218;185m'
  RESET='\033[0m'
  
  # A colorful but readable command prompt with orange text input
  if [ -n "${PS1-}" ]; then
    PS1="\[${PASTEL_CYAN}\]\u\[${RESET}\]@\[${PASTEL_PINK}\]\h\[${RESET}\]:\[${PASTEL_BLUE}\]\w\[${RESET}\]\[${PASTEL_GREEN}\]\$\[${RESET}\] \[${PASTEL_ORANGE}\]"
    # Reset color after each command
    PROMPT_COMMAND="echo -ne '${RESET}'"
  fi
else
  # Simple prompt for basic terminals
  if [ -n "${PS1-}" ]; then
    PS1='\u@\h:\w\$ '
  fi
fi

# Handy shortcuts that save tons of typing
# Better file listing options
alias ll='ls -alF --color=auto'    # Long list with file types
alias la='ls -A --color=auto'      # Show hidden files
alias l='ls -CF --color=auto'      # Compact list with file types  
alias lla='ls -la --color=auto'    # Long list including hidden
alias ls='ls --color=auto'         # Always use colors

# Git shortcuts for faster version control
alias gs='git status'        # Quick status check
alias ga='git add'          # Stage files
alias gaa='git add .'       # Stage everything
alias gco='git checkout'    # Switch branches
alias gcb='git checkout -b' # Create new branch
alias gcm='git commit -m'   # Commit with message
alias gp='git push'         # Push changes
alias gpl='git pull'        # Pull updates
alias gd='git diff'         # See what changed
alias gl='git log --oneline' # Compact log view

# Docker shortcuts (if you use Docker)
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias di='docker images'

# Package management aliases
alias apt-search='apt search'
alias apt-show='apt show'
alias pkg='pkg'

# Safety aliases with confirmation
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias chmod='chmod --preserve-root'
alias chown='chown --preserve-root'

# Enhanced grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Navigation shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'

# Utility aliases
alias h='history'
alias c='clear'
alias path='echo -e ${PATH//:/\\n}'
alias now='date +"%T"'
alias nowtime=now
alias nowdate='date +"%d-%m-%Y"'

# Process and system aliases
alias psg='ps aux | grep -v grep | grep -i -E'
alias ports='netstat -tulanp'
alias meminfo='free -m -l -t'
alias psmem='ps auxf | sort -nr -k 4'
alias pscpu='ps auxf | sort -nr -k 3'

# Text editing shortcuts
alias n='nano'
alias v='vim'

# ===== ENVIRONMENT VARIABLES =====
export EDITOR=nano
export VISUAL=nano
export PAGER=less
export LESS='-R -M --shift 5'

# Add useful paths
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# ===== PROGRAMMABLE COMPLETION =====
if [ -f /data/data/com.termux/files/usr/etc/bash_completion ] && ! shopt -oq posix; then
    . /data/data/com.termux/files/usr/etc/bash_completion
fi

# ===== READLINE BINDINGS =====
# Enhanced text editing shortcuts
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
# Ctrl+L to clear screen
bind -x '"\C-l": clear'
# Ctrl+U to kill whole line
bind '"\C-u": kill-whole-line'

# ===== CUSTOM FUNCTIONS =====
# Quick directory creation and navigation
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract various archive types
extract() {
    if [ -f "$1" ] ; then
        case $1 in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar e "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Find and kill process by name
killps() {
    local pid
    pid=$(ps aux | grep "$1" | grep -v grep | awk '{print $2}')
    if [ -n "$pid" ]; then
        kill -9 "$pid"
        echo "Killed process $1 (PID: $pid)"
    else
        echo "No process found matching: $1"
    fi
}

# Welcome message when you open a new terminal
if [ -n "${PS1-}" ]; then
    echo -e "\033[38;2;175;238;238mWelcome to your mobile development environment!\033[0m"
    echo -e "\033[38;2;255;182;193mType 'alias' to see your shortcuts\033[0m"
fi

# Don't interfere with script terminal width detection
unset COLUMNS LINES
BASH_CONFIG_EOF

  # Add personalized configuration with actual username and aliases
  cat >> "$HOME/.bashrc" << PERSONAL_CONFIG_EOF

# ===== PERSONAL CONFIGURATION =====
# Your CAD-Droid setup details
export CAD_TERMUX_USER="${TERMUX_USERNAME:-user}"
export CAD_GIT_USER="${GIT_USERNAME:-}"
export CAD_GIT_EMAIL="${GIT_EMAIL:-}"

# Personalized aliases based on your setup
alias whoami_cad='echo "Termux User: \$CAD_TERMUX_USER, Git: \$CAD_GIT_USER <\$CAD_GIT_EMAIL>"'
alias my_setup='echo "CAD-Droid Mobile Development Environment for \$CAD_TERMUX_USER"'

# Username color customization function
change_username_color() {
  local color="\${1:-cyan}"
  local bashrc="\$HOME/.bashrc"
  case "\$color" in
    cyan) local new_color='\\\033[38;2;175;238;238m' ;;
    pink) local new_color='\\\033[38;2;255;182;193m' ;;  
    green) local new_color='\\\033[38;2;144;238;144m' ;;
    yellow) local new_color='\\\033[38;2;255;255;224m' ;;
    purple) local new_color='\\\033[38;2;221;160;221m' ;;
    blue) local new_color='\\\033[38;2;173;216;230m' ;;
    *) echo "Available colors: cyan, pink, green, yellow, purple, blue"; return 1 ;;
  esac
  
  # Update the PS1 color in .bashrc
  if command -v sed >/dev/null 2>&1; then
    sed -i "s/PASTEL_CYAN\]/\$new_color\]/g" "\$bashrc" 2>/dev/null
    echo "Username color changed to \$color. Restart terminal to see changes."
  else
    echo "sed not available, cannot change color automatically"
  fi
}

# Quick alias for changing username color
alias set_user_color='change_username_color'
PERSONAL_CONFIG_EOF

  ok "Your personalized Bash environment is ready"
}

# Configure Nano editor with useful settings
configure_nano_editor(){
  info "Setting up a nice text editor for you..."
  
  # Make Nano much more pleasant to use
  cat > "$HOME/.nanorc" << 'NANO_CONFIG_EOF'
# Your personal Nano editor configuration
# This makes editing files much more enjoyable
#
# Load all the built-in syntax highlighting
include "/data/data/com.termux/files/usr/share/nano/*.nanorc"

# Interface improvements that make editing easier
set titlebar        # Show the filename at the top
set statusbar       # Show helpful info at the bottom  
set linenumbers     # Show line numbers on the left
set softwrap        # Wrap long lines nicely
set softwrap
# Show cursor position constantly
set constantshow
# Enable smooth scrolling
set smooth

# ===== EDITING BEHAVIOR =====
# Set tab size to 2 spaces (common for development)
set tabsize 2
# Convert tabs to spaces
set tabstospaces
# Enable auto-indentation
set autoindent
# Enable smart home key
set smarthome
# Use cut-to-end-of-line by default
set cutfromcursor

# ===== MOUSE AND INPUT =====
# Enable mouse support for selections and positioning
set mouse
# Enable multi-file buffer editing
set multibuffer

# ===== SEARCH SETTINGS =====
# Case-sensitive search by default
set casesensitive
# Enable regular expression search
set regexp

# ===== FILE HANDLING =====
# Create backup files
set backup
# Store backups in dedicated directory
set backupdir "~/.nano/backups"
# Automatically save on exit
set tempfile

# ===== PASTEL COLOR THEME =====
# Main interface colors (pastel cyan theme)
set titlecolor white,cyan
set statuscolor white,green
set numbercolor cyan,black
set keycolor white,blue

# Text colors (enhanced readability)
set functioncolor magenta
set stringscolor yellow
set commentcolor brightblack

# Advanced color customization (if supported)
# These work with newer versions of nano
set selectedcolor white,magenta
set errorcolor white,red
set spotlightcolor black,yellow

# ===== ADDITIONAL FEATURES =====
# Show whitespace characters
set whitespace "»·"
# Enable word wrapping at word boundaries  
set wordchars "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
# Enable undo functionality
set undo
NANO_CONFIG_EOF

  # Create backup directory for nano
  mkdir -p "$HOME/.nano/backups" 2>/dev/null || true
  
  ok "Enhanced Nano editor with pastel theme configured"
}

# Main execution function with completely safe array operations
main_execution(){
  # Early Termux:API detection for better UX fallbacks
  if have_termux_api 2>/dev/null; then
    TERMUX_API_VERIFIED="yes"
  fi
  
  # Initialize all required arrays and variables
  STEP_DURATIONS=()
  STEP_STATUS=() 
  STEP_FUNCS=()
  STEP_NAME=()
  STEP_ETA=()
  
  # Check if only running specific step
  if [ -n "$ONLY_STEP" ]; then
    run_single_step "$ONLY_STEP"
    return $?
  fi
  
  # Initialize steps
  initialize_steps
  
  # Display welcome message
  draw_card "CAD-Droid Ultimate Setup v${SCRIPT_VERSION}" "Comprehensive Android Development Environment"
  
  # Execute all registered steps using safe counter-based iteration
  local current_step=0 total_steps="${TOTAL_STEPS:-0}"
  
  # Validate total_steps is numeric and reasonable
  case "$total_steps" in
    *[!0-9]*) total_steps=0 ;;
    *) 
      if [ "$total_steps" -lt 0 ] 2>/dev/null; then
        total_steps=0
      elif [ "$total_steps" -gt 50 ] 2>/dev/null; then
        total_steps=50  # Cap at reasonable maximum
      fi
      ;;
  esac
  
  while [ "$current_step" -lt "$total_steps" ] 2>/dev/null; do
    CURRENT_STEP_INDEX="$current_step"
    
    # Start the step
    start_step
    
    # Execute the step function with bounds checking
    local func="${STEP_FUNCS[$current_step]:-}"
    local step_name="${STEP_NAME[$current_step]:-Unknown}"
    
    if [ -n "$func" ] && declare -f "$func" >/dev/null 2>&1; then
      if "$func"; then
        # Check if status was already set by the function
        if [ -z "${STEP_STATUS[$current_step]:-}" ]; then
          STEP_STATUS[$current_step]="success"
        fi
      else
        warn "Step $((current_step + 1)) failed: $step_name"
        STEP_STATUS[$current_step]="failed"
      fi
    else
      warn "Step function $func not found"
      # Debug: Show detailed information about the lookup failure
      warn "Debug info for missing function '$func':"
      warn "- Total registered steps: ${#STEP_NAME[@]}"
      warn "- Current step index: $current_step"  
      warn "- Step name: ${STEP_NAME[$current_step]:-UNDEFINED}"
      warn "- Function name in array: ${STEP_FUNCS[$current_step]:-UNDEFINED}"
      # Debug: List all available functions starting with step_
      warn "Available step functions:"
      declare -F | grep "step_" | head -10 || warn "No step functions found"
      STEP_STATUS[$current_step]="missing"
    fi
    
    # Complete the step
    end_step
    
    # Safe step increment using validated arithmetic
    if is_nonneg_int "$current_step" && [ "$current_step" -lt 1000 ]; then
      current_step=$(add_int "$current_step" 1)
    else
      break  # Safety break to prevent infinite loops
    fi
  done
  
  # Show final completion message
  show_completion_summary
  show_final_completion
}

# Error handling for the main script
error_handler() {
    local exit_code=$?
    local line_number=$1
    if command -v err >/dev/null 2>&1; then
        err "Script interrupted at line $line_number (exit code: $exit_code)"
    else
        echo "Error: Script interrupted at line $line_number (exit code: $exit_code)" >&2
    fi
    exit $exit_code
}

# Set up error handling
trap 'error_handler $LINENO' ERR

# === Self-Test Functionality ===
# Lightweight test harness for validating core utilities
run_self_tests() {
  echo "=== CAD-Droid Self-Test Suite ==="
  local tests_passed=0
  local tests_failed=0
  
  # Test safe_calc function
  echo -n "Testing safe_calc basic arithmetic... "
  if [ "$(safe_calc "2 + 3")" = "5" ] && [ "$(safe_calc "10 - 4")" = "6" ]; then
    echo "PASS"
    ((tests_passed++))
  else
    echo "FAIL"
    ((tests_failed++))
  fi
  
  # Test safe_calc input validation
  echo -n "Testing safe_calc input validation... "
  if safe_calc "rm -rf /" >/dev/null 2>&1; then
    echo "FAIL (unsafe input accepted)"
    ((tests_failed++))
  else
    echo "PASS"
    ((tests_passed++))
  fi
  
  # Test is_nonneg_int function
  echo -n "Testing is_nonneg_int validation... "
  if is_nonneg_int "42" && is_nonneg_int "0" && ! is_nonneg_int "-5" && ! is_nonneg_int "abc"; then
    echo "PASS"
    ((tests_passed++))
  else
    echo "FAIL"
    ((tests_failed++))
  fi
  
  # Test clamp_int function
  echo -n "Testing clamp_int boundaries... "
  if [ "$(clamp_int "15" "10" "20")" = "15" ] && [ "$(clamp_int "5" "10" "20")" = "10" ] && [ "$(clamp_int "25" "10" "20")" = "20" ]; then
    echo "PASS"
    ((tests_passed++))
  else
    echo "FAIL"
    ((tests_failed++))
  fi
  
  # Test regex patterns
  echo -n "Testing regex patterns... "
  local test_passed=true
  if [[ ! "validuser123" =~ $ALLOWED_USERNAME_REGEX ]] || [[ "123invalid" =~ $ALLOWED_USERNAME_REGEX ]]; then
    test_passed=false
  fi
  if [[ ! "user@example.com" =~ $ALLOWED_EMAIL_REGEX ]] || [[ "invalid-email" =~ $ALLOWED_EMAIL_REGEX ]]; then
    test_passed=false
  fi
  if [[ ! "file.txt" =~ $ALLOWED_FILENAME_REGEX ]] || [[ "invalid/file" =~ $ALLOWED_FILENAME_REGEX ]]; then
    test_passed=false
  fi
  
  if $test_passed; then
    echo "PASS"
    ((tests_passed++))
  else
    echo "FAIL"
    ((tests_failed++))
  fi
  
  # Test array iteration safety
  echo -n "Testing safe array iteration... "
  TEST_ARRAY=("item1" "item2" "item3")
  local iteration_count=0
  test_callback() { ((iteration_count++)); }
  iterate_array TEST_ARRAY test_callback
  if [ "$iteration_count" = "3" ]; then
    echo "PASS"
    ((tests_passed++))
  else
    echo "FAIL"
    ((tests_failed++))
  fi
  
  echo
  echo "=== Self-Test Results ==="
  echo "Tests passed: $tests_passed"
  echo "Tests failed: $tests_failed"
  
  if [ "$tests_failed" -eq 0 ]; then
    echo "All tests passed! ✓"
    return 0
  else
    echo "Some tests failed! ✗"
    return 1
  fi
}

# Check if running in non-interactive mode
if [ "${NON_INTERACTIVE:-0}" = "1" ] || [ "$#" -gt 0 ] && [[ "$*" == *"--non-interactive"* ]]; then
  NON_INTERACTIVE=1
fi

# Parse command line arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --help) show_help; exit 0 ;;
    --version) echo "$SCRIPT_VERSION"; exit 0 ;;
    --non-interactive) NON_INTERACTIVE=1 ;;
    --only-step) shift; ONLY_STEP="$1" ;;
    --doctor) run_diagnostics; exit 0 ;;
    --self-test) run_self_tests; exit $? ;;
    --snapshot-create) shift; create_snapshot "$1"; exit $? ;;
    --snapshot-restore) shift; restore_snapshot "$1"; exit $? ;;
    --list-snapshots) list_snapshots; exit 0 ;;
    *) ;;
  esac
  shift
done

# Verify critical step functions are defined before execution
verify_step_functions() {
  local missing_funcs=()
  local test_funcs=("step_x11repo" "step_aptni" "step_systemup" "step_nettools")
  
  for func in "${test_funcs[@]}"; do
    if ! declare -f "$func" >/dev/null 2>&1; then
      missing_funcs+=("$func")
    fi
  done
  
  if [ ${#missing_funcs[@]} -gt 0 ]; then
    echo "WARNING: Missing step functions detected: ${missing_funcs[*]}" >&2
    echo "Available step functions:" >&2
    declare -F | grep "^declare -f step_" | head -10 >&2 || echo "No step functions found" >&2
  fi
}

# Execute main installation flow
verify_step_functions
main_execution "$@"
      