#!/usr/bin/env bash
###############################################################################
# CAD-Droid Constants Module
# Global constants, configuration variables, and environment setup
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_CONSTANTS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_CONSTANTS_LOADED=1

# Define script metadata as read-only constants
readonly SCRIPT_VERSION="CAD-Droid Setup"
readonly SCRIPT_NAME="CAD-Droid Mobile Development Environment"

# === Critical System Paths ===
# PREFIX: Termux's equivalent of /usr on standard Linux systems
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
# HOME: User's home directory in Termux
HOME="${HOME:-/data/data/com.termux/files/home}"

# Network timeout settings for reliable downloads
CURL_CONNECT="${CURL_CONNECT:-5}"     # Connection timeout in seconds
CURL_MAX_TIME="${CURL_MAX_TIME:-40}"  # Maximum download time in seconds

# Record when script started for duration tracking
START_TIME=$(date +%s 2>/dev/null || echo 0)

# Initialize variables to prevent unbound variable errors
github_opened=false

# === Core Constants & Palettes ===
# Security constraints for user input validation
MIN_PASSWORD_LENGTH=6      # Minimum characters for secure passwords
MAX_INPUT_LENGTH=64        # Maximum input length to prevent buffer issues

# Regular expression patterns for validating user input
ALLOWED_USERNAME_REGEX='^[A-Za-z][A-Za-z0-9_-]{0,31}$'
ALLOWED_EMAIL_REGEX='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
ALLOWED_FILENAME_REGEX='^[A-Za-z0-9._-]{1,64}$'

# Feature toggle flags - can be overridden by environment variables
ENABLE_SNAPSHOTS="${ENABLE_SNAPSHOTS:-1}"    # System backup and restore capability
ENABLE_WIDGETS="${ENABLE_WIDGETS:-1}"        # Desktop productivity shortcuts
ENABLE_ADB="${ENABLE_ADB:-1}"                # Android Debug Bridge wireless setup
SKIP_ADB="${SKIP_ADB:-0}"                    # Skip ADB wireless setup entirely
ENABLE_APK_AUTO="${ENABLE_APK_AUTO:-1}"      # Automatic APK downloading
ENABLE_SUNSHINE="${ENABLE_SUNSHINE:-1}"      # Remote desktop streaming
PREFER_FDROID="${PREFER_FDROID:-1}"          # Prefer F-Droid over GitHub by default

# Enhanced environment variables for advanced configuration
AUTO_GITHUB="${AUTO_GITHUB:-0}"              # Skip GitHub SSH key setup interactions
AUTO_APK="${AUTO_APK:-0}"                    # Skip APK installation confirmations
TERMUX_API_FORCE_SKIP="${TERMUX_API_FORCE_SKIP:-0}"  # Force skip Termux:API detection
TERMUX_API_WAIT_MAX="${TERMUX_API_WAIT_MAX:-4}"       # Maximum API detection attempts
TERMUX_API_WAIT_DELAY="${TERMUX_API_WAIT_DELAY:-3}"   # Delay between API detection attempts

# Timeout settings for various operations
APK_PAUSE_TIMEOUT="${APK_PAUSE_TIMEOUT:-45}"          # APK installation timeout in seconds
GITHUB_PROMPT_TIMEOUT_OPEN="${GITHUB_PROMPT_TIMEOUT_OPEN:-30}"    # GitHub browser open timeout
GITHUB_PROMPT_TIMEOUT_CONFIRM="${GITHUB_PROMPT_TIMEOUT_CONFIRM:-60}" # GitHub confirmation timeout

# Environment timeouts and control variables  
APK_PAUSE_TIMEOUT="${APK_PAUSE_TIMEOUT:-45}"                    # APK installation timeout
GITHUB_PROMPT_TIMEOUT_OPEN="${GITHUB_PROMPT_TIMEOUT_OPEN:-30}" # GitHub browser open timeout  
GITHUB_PROMPT_TIMEOUT_CONFIRM="${GITHUB_PROMPT_TIMEOUT_CONFIRM:-60}" # GitHub setup confirmation timeout
TERMUX_API_FORCE_SKIP="${TERMUX_API_FORCE_SKIP:-0}"           # Force skip Termux:API detection
TERMUX_API_WAIT_MAX="${TERMUX_API_WAIT_MAX:-4}"               # Max API detection attempts
TERMUX_API_WAIT_DELAY="${TERMUX_API_WAIT_DELAY:-3}"           # Delay between API attempts
AUTO_GITHUB="${AUTO_GITHUB:-0}"                               # Skip GitHub setup interaction

# Color palette definitions for beautiful terminal output
# Pastel colors for gentle backgrounds
PASTEL_HEX=( "9DF2F2" "FFDFA8" "DCC9FF" "FFC9D9" "C9FFD1" "FBE6A2" "C9E0FF" "FAD3C4" "E0D1FF" "FFE2F1" "D1FFE6" "FFEBC9" )
# Vibrant colors for accents and highlights
VIBRANT_HEX=( "31D4D4" "FFAA1F" "9B59FF" "FF4F7D" "2EE860" "FFCF26" "4FA6FF" "FF8A4B" "7E4BFF" "FF5FA2" "11DB78" "FFB347" )
# Fallback color when palette unavailable
FALLBACK_COLOR='\033[38;2;175;238;238m'

# Unicode Braille characters for animated progress spinners
BRAILLE_CHARS=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
# Animation frame delay for spinner
SPINNER_DELAY="${SPINNER_DELAY:-0.02}"

# Essential packages required for full productivity environment
CORE_PACKAGES=( 
  jq               # JSON processor for API responses  
  git              # Version control system
  curl             # HTTP client for downloads
  nano             # Simple text editor
  vim              # Advanced text editor
  tmux             # Terminal multiplexer for sessions
  python           # Python programming language
  openssh          # SSH client/server for secure connections
  pulseaudio       # Audio system
  dbus             # Inter-process communication system
  fontconfig       # Font management system
  ttf-dejavu       # High-quality fonts
  proot-distro     # Linux distribution container system
  termux-api       # Android system integration
)

# Minimum file size for valid APK files (12KB)
MIN_APK_SIZE="${MIN_APK_SIZE:-12288}"

# === Global State Variables ===
# Initialize all variables to prevent undefined variable errors

# Directory paths for storing various types of data
WORK_DIR=""              # Temporary working directory
CRED_DIR=""              # Secure credential storage
STATE_DIR=""             # Persistent state information  
LOG_DIR=""               # Log file storage
SNAP_DIR=""              # System snapshot storage
EVENT_LOG=""             # Event log file path
STATE_JSON=""            # JSON state file path

# User and system configuration
TERMUX_USERNAME=""           # Username for Termux environment
TERMUX_PHONETYPE="unknown"   # Detected phone manufacturer
DISTRO="ubuntu"              # Selected Linux distribution
UBUNTU_USERNAME=""           # Username for Linux container  
GIT_USERNAME=""              # Git configuration username
GIT_EMAIL=""                 # Git configuration email

# Installation tracking
DOWNLOAD_COUNT=0         # Number of packages processed
TERMUX_API_VERIFIED="no" # Whether Termux:API app is available

# Tool availability flags
WGET_READY=0            # Whether wget is installed and working

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
CARD_INDEX=0            # Current color index for UI cards

# Plugin and storage configuration
PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.cad/plugins}"              # Directory for custom plugins
USER_SELECTED_APK_DIR=""                                     # User-selected APK directory via file picker