#!/usr/bin/env bash
###############################################################################
# CAD-Droid Spinners Module
# Progress indicators and visual feedback for all operations
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_SPINNERS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_SPINNERS_LOADED=1

# Spinner configuration
readonly SPINNER_DELAY="${SPINNER_DELAY:-0.08}"
readonly SPINNER_PID_FILE="$TMPDIR/.cad_spinner_pid"

# Pastel-colored spinner frames using the setup's color scheme
readonly SPINNER_FRAMES=(
  "${PASTEL_CYAN}●${RESET}○○○"
  "${PASTEL_PINK}○●${RESET}○○"  
  "${PASTEL_LAVENDER}○○●${RESET}○"
  "${PASTEL_GREEN}○○○●${RESET}"
  "${PASTEL_LAVENDER}○○●${RESET}○"
  "${PASTEL_PINK}○●${RESET}○○"
)

# Progress tracking
CURRENT_STEP_COUNT=0
TOTAL_STEPS=15

# Initialize spinner system
init_spinner_system(){
  # Ensure spinner PID file directory exists
  mkdir -p "$(dirname "$SPINNER_PID_FILE")" 2>/dev/null || true
  
  # Clean up any existing spinner processes
  cleanup_spinner
  
  # Set up signal handlers for clean spinner termination
  trap cleanup_spinner EXIT INT TERM
}

# Clean up spinner processes
cleanup_spinner(){
  if [ -f "$SPINNER_PID_FILE" ]; then
    local spinner_pid
    spinner_pid=$(cat "$SPINNER_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$spinner_pid" ] && kill -0 "$spinner_pid" 2>/dev/null; then
      kill "$spinner_pid" 2>/dev/null || true
      wait "$spinner_pid" 2>/dev/null || true
    fi
    rm -f "$SPINNER_PID_FILE" 2>/dev/null || true
  fi
  
  # Clear any remaining spinner display
  printf "\r\033[2K" >&2
}

# Background spinner function
run_spinner(){
  local message="$1"
  local max_length="${2:-40}"
  
  # Truncate message if too long
  if [ ${#message} -gt "$max_length" ]; then
    message="${message:0:$((max_length-3))}..."
  fi
  
  local frame_count=${#SPINNER_FRAMES[@]}
  local frame_index=0
  
  while true; do
    local current_frame="${SPINNER_FRAMES[$frame_index]}"
    printf "\r${current_frame} ${PASTEL_CYAN}%s${RESET}" "$message" >&2
    
    frame_index=$(( (frame_index + 1) % frame_count ))
    sleep "$SPINNER_DELAY"
  done
}

# Start spinner with message
start_spinner(){
  local message="${1:-Working...}"
  
  cleanup_spinner
  run_spinner "$message" &
  echo $! > "$SPINNER_PID_FILE"
}

# Stop spinner and show result
stop_spinner(){
  local result="${1:-done}"
  local message="${2:-}"
  
  cleanup_spinner
  
  case "$result" in
    "success"|"ok"|"done")
      printf "\r${PASTEL_GREEN}✓${RESET} %s\n" "${message:-Complete}" >&2
      ;;
    "warn"|"warning")
      printf "\r${PASTEL_YELLOW}⚠${RESET} %s\n" "${message:-Warning}" >&2
      ;;
    "error"|"fail"|"failed")
      printf "\r${PASTEL_RED}✗${RESET} %s\n" "${message:-Failed}" >&2
      ;;
    *)
      printf "\r${PASTEL_CYAN}●${RESET} %s\n" "${message:-$result}" >&2
      ;;
  esac
}

# Enhanced run_with_progress that ensures spinner is always shown
run_with_progress(){
  local message="$1"
  local estimated_seconds="${2:-10}"
  local command="$3"
  
  if [ -z "$command" ]; then
    err "run_with_progress: No command provided"
    return 1
  fi
  
  # Show step progress if tracking is enabled
  if [ "$TOTAL_STEPS" -gt 0 ] && [ "$CURRENT_STEP_COUNT" -ge 0 ]; then
    CURRENT_STEP_COUNT=$((CURRENT_STEP_COUNT + 1))
    local progress_msg="[$CURRENT_STEP_COUNT/$TOTAL_STEPS] $message"
  else
    local progress_msg="$message"
  fi
  
  # Always start spinner for visual feedback
  start_spinner "$progress_msg"
  
  # Create temporary files for command output
  local stdout_file="$TMPDIR/.cmd_stdout_$$"
  local stderr_file="$TMPDIR/.cmd_stderr_$$"
  local exit_code_file="$TMPDIR/.cmd_exit_$$"
  
  # Run command in background with output capture
  (
    eval "$command" >"$stdout_file" 2>"$stderr_file"
    echo $? > "$exit_code_file"
  ) &
  local cmd_pid=$!
  
  # Wait for command with timeout
  local elapsed=0
  local timeout_seconds=$((estimated_seconds * 3))  # 3x estimate as timeout
  
  while kill -0 "$cmd_pid" 2>/dev/null; do
    sleep 0.5
    elapsed=$((elapsed + 1))
    
    # Check for timeout (in half-second increments)
    if [ "$elapsed" -gt $((timeout_seconds * 2)) ]; then
      kill "$cmd_pid" 2>/dev/null || true
      wait "$cmd_pid" 2>/dev/null || true
      stop_spinner "error" "Timeout after ${timeout_seconds}s"
      
      # Clean up temp files
      rm -f "$stdout_file" "$stderr_file" "$exit_code_file" 2>/dev/null || true
      return 124  # Standard timeout exit code
    fi
  done
  
  # Wait for command to fully complete
  wait "$cmd_pid" 2>/dev/null || true
  
  # Get exit code
  local exit_code=1
  if [ -f "$exit_code_file" ]; then
    exit_code=$(cat "$exit_code_file" 2>/dev/null || echo 1)
  fi
  
  # Treat exit code 100 as success (package already installed)
  if [ "$exit_code" -eq 100 ]; then
    exit_code=0
  fi
  
  # Show result
  if [ "$exit_code" -eq 0 ]; then
    stop_spinner "success" "$message"
  else
    stop_spinner "error" "$message (exit $exit_code)"
    
    # Show error output if available and in debug mode
    if [ "${DEBUG:-0}" = "1" ] && [ -f "$stderr_file" ]; then
      local error_output
      error_output=$(tail -n 3 "$stderr_file" 2>/dev/null || echo "")
      if [ -n "$error_output" ]; then
        debug "Command error output: $error_output"
      fi
    fi
  fi
  
  # Clean up temp files
  rm -f "$stdout_file" "$stderr_file" "$exit_code_file" 2>/dev/null || true
  
  return "$exit_code"
}

# Simple progress indicator for file operations
show_file_progress(){
  local operation="$1"
  local filename="$2"
  
  start_spinner "$operation: $(basename "$filename")"
}

# Progress indicator for network operations
show_network_progress(){
  local operation="$1"
  local url="$2"
  
  local hostname
  hostname=$(echo "$url" | sed 's|https\?://||' | cut -d'/' -f1)
  start_spinner "$operation: $hostname"
}

# Step counter functions for overall progress tracking
reset_step_counter(){
  CURRENT_STEP_COUNT=0
  TOTAL_STEPS="${1:-15}"
}

increment_step_counter(){
  CURRENT_STEP_COUNT=$((CURRENT_STEP_COUNT + 1))
}

get_step_progress(){
  if [ "$TOTAL_STEPS" -gt 0 ]; then
    echo "[$CURRENT_STEP_COUNT/$TOTAL_STEPS]"
  else
    echo "[$CURRENT_STEP_COUNT]"
  fi
}

# Package installation with spinner and proper exit code handling
apt_install_with_spinner(){
  local package="$1"
  local action="${2:-install}"
  
  if [ -z "$package" ]; then
    err "apt_install_with_spinner: Package name required"
    return 1
  fi
  
  # Check if already installed first
  if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
    stop_spinner "success" "$package (already installed)"
    return 0
  fi
  
  # Install with progress indication
  if run_with_progress "$action $package" 20 "apt-get -y $action $package >/dev/null 2>&1 || [ \$? -eq 100 ]"; then
    return 0
  else
    return 1
  fi
}

# File download with progress spinner
download_with_spinner(){
  local url="$1"
  local output_file="$2"
  local description="${3:-Download}"
  
  if [ -z "$url" ] || [ -z "$output_file" ]; then
    err "download_with_spinner: URL and output file required"
    return 1
  fi
  
  # Extract filename for display
  local filename
  filename=$(basename "$output_file")
  
  # Show network progress
  show_network_progress "$description" "$url"
  
  # Download with timeout and retry
  local max_attempts=3
  local attempt=1
  
  while [ "$attempt" -le "$max_attempts" ]; do
    if timeout 120 curl -fsSL --connect-timeout 10 --max-time 120 \
       -H "User-Agent: CAD-Droid-Setup/1.0" \
       -o "$output_file" "$url" >/dev/null 2>&1; then
      stop_spinner "success" "Downloaded $filename"
      return 0
    else
      if [ "$attempt" -lt "$max_attempts" ]; then
        stop_spinner "warn" "Retry $attempt/$max_attempts: $filename"
        sleep 2
        show_network_progress "$description (retry $((attempt + 1)))" "$url"
      fi
      attempt=$((attempt + 1))
    fi
  done
  
  stop_spinner "error" "Failed to download $filename"
  return 1
}

# Initialize the spinner system when module loads
init_spinner_system

# Export functions for use by other modules
export -f start_spinner
export -f stop_spinner
export -f run_with_progress
export -f show_file_progress
export -f show_network_progress
export -f apt_install_with_spinner
export -f download_with_spinner
export -f reset_step_counter
export -f increment_step_counter
export -f get_step_progress
