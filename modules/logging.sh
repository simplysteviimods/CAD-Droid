#!/usr/bin/env bash
###############################################################################
# CAD-Droid Logging Module
# Logging functions, output formatting, and progress display
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_LOGGING_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_LOGGING_LOADED=1

# === Core Logging Functions ===

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

# === Structured Logging ===

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
  
  # Build JSON entry
  local json_entry
  json_entry=$(cat <<JSON_LOG_EOF
{
  "timestamp": "$ts",
  "action": "$action",
  "phase": $phase,
  "status": "$status",
  "detail": "$detail"
JSON_LOG_EOF
)
  
  # Add duration if provided
  if [ -n "$dur" ]; then
    json_entry="${json_entry}, \"duration\": $dur"
  fi
  
  json_entry="${json_entry}}"
  
  # Write to event log if available
  if [ -n "${EVENT_LOG:-}" ] && [ -f "${EVENT_LOG:-}" ]; then
    printf "%s\n" "$json_entry" >> "$EVENT_LOG" 2>/dev/null || true
  fi
  
  # Also log to session file if RUN_LOG is enabled
  if [ "${RUN_LOG:-0}" = "1" ]; then
    local session_log="${HOME:-/tmp}/setup-session.log"
    printf "%s [%s] %s: %s\n" "$ts" "$status" "$action" "$detail" >> "$session_log" 2>/dev/null || true
  fi
}

# === Progress Display Functions ===

# Safe division for progress calculations
safe_progress_div() {
  local num="${1:-0}" den="${2:-1}"
  
  # Validate inputs are numeric
  case "$num" in *[!0-9]*) num=0;; esac
  case "$den" in *[!0-9]*) den=1;; esac
  
  # Prevent division by zero
  if [ "$den" -eq 0 ]; then
    den=1
  fi
  
  # Perform safe calculation
  if [ "$num" -le "$den" ]; then
    # Normal case: num/den * 100
    echo $(( num * 100 / den ))
  else
    # Clamp to 100% if somehow exceeded
    echo 100
  fi
}

# Run a command with animated progress display and proper logging
# Parameters: description, estimated_time_seconds, command...
run_with_progress(){
  local desc="$1" est="$2"
  shift 2
  
  # Validate estimated time is numeric and reasonable
  case "$est" in
    (*[!0-9]*) est=30;;   # Non-numeric, use default
    (*) 
      if [ "$est" -lt 1 ] 2>/dev/null; then est=30; fi    # Minimum time
      if [ "$est" -gt 600 ] 2>/dev/null; then est=600; fi # Maximum time (10 min)
    ;;
  esac
  
  # Ensure TMPDIR is set and exists
  local tmpdir="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
  if [ ! -d "$tmpdir" ]; then
    mkdir -p "$tmpdir" 2>/dev/null || {
      tmpdir="/tmp"
      mkdir -p "$tmpdir" 2>/dev/null || tmpdir="/dev/null"
    }
  fi
  
  local logf="$tmpdir/cmd_$$.log"
  local start_time=$(date +%s)
  
  # Start background process
  "$@" > "$logf" 2>&1 &
  local pid=$!
  
  # Progress animation variables with safe initialization
  local elapsed=0 frame=0 pct=0
  local delay="${SPINNER_DELAY:-0.08}"
  
  # Show progress while command runs
  while kill -0 "$pid" 2>/dev/null; do
    # Calculate elapsed time safely
    local current_time
    current_time=$(date +%s 2>/dev/null || echo "$start_time")
    elapsed=$((current_time - start_time))
    
    # Calculate percentage with more accurate time-based calculation
    if [ "$elapsed" -le "$est" ] 2>/dev/null; then
      # Linear progress for time within estimate
      pct=$(safe_progress_div "$elapsed" "$est")
    else
      # Beyond estimate - use logarithmic slowdown for more realistic feel
      local over=$((elapsed - est))
      local extra_time=$((est / 4))  # Allow 25% extra time to reach 95%
      
      if [ "$over" -le "$extra_time" ] 2>/dev/null; then
        # Progress from 90% to 95% over the extra time
        local base_pct=90
        local extra_pct=$(safe_progress_div "$over" "$extra_time")
        local bonus_pct=$((extra_pct * 5 / 100))  # Max 5% bonus (90% -> 95%)
        pct=$((base_pct + bonus_pct))
      else
        # After extra time, slowly approach 99% but never reach 100%
        local remaining_time=$((elapsed - est - extra_time))
        if [ "$remaining_time" -lt 60 ] 2>/dev/null; then
          pct=95
        elif [ "$remaining_time" -lt 120 ] 2>/dev/null; then
          pct=97
        else
          pct=98
        fi
      fi
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
    local display_width cols
    cols=$(get_terminal_width)
    if [ "$cols" -gt 14 ] 2>/dev/null; then
      display_width=$((cols - 14))
    else
      display_width=40
    fi
    
    # Clear the entire line more aggressively to prevent ghosting
    printf "\r\033[2K"  # Clear entire line and return to beginning
    printf "\033[38;2;175;238;238m%s\033[0m \033[38;2;175;238;238m%-*.*s\033[0m \033[38;2;173;216;230m(%3d%%)\033[0m" \
      "$sym" "$display_width" "$display_width" "$desc" "$pct"
    
    # Flush output to ensure immediate display
    printf "" > /dev/tty 2>/dev/null || true
    
    # Safe frame increment
    if [ "$frame" -lt 10000 ] 2>/dev/null; then
      frame=$((frame + 1))
    else
      frame=0  # Reset to prevent overflow
    fi
    
    safe_sleep "$delay"
  done
  
  # Wait for process to complete and capture exit code
  wait "$pid"
  local rc=$?
  
  # Calculate final duration
  local end_time
  end_time=$(date +%s 2>/dev/null || echo "$start_time")
  local dur=$((end_time - start_time))
  
  # Clear progress line and show final result
  printf "\r\033[2K"  # Clear line completely
  
  local message
  if [ $rc -eq 0 ]; then
    message="OK $desc"
    pecho '\033[38;2;152;251;152m' "$message"
    log_event cmd_done "${CURRENT_STEP_INDEX:-unknown}" success "$desc" "$dur"
  else
    message="FAILED $desc (failed)"
    pecho '\033[38;2;255;192;203m' "$message"
    log_event cmd_done "${CURRENT_STEP_INDEX:-unknown}" fail "$message" "$dur"
  fi
  
  # Clean up temporary log file
  rm -f "$logf" 2>/dev/null || true
  return $rc
}

# Run command with progress but don't fail the script if it fails
soft_step(){ 
  run_with_progress "$@" || true
}

# === Time and Duration Formatting ===

# Format duration in seconds to human-readable format
format_duration() {
  local seconds="${1:-0}"
  
  # Validate input is numeric
  case "$seconds" in
    *[!0-9]*) seconds=0 ;;
  esac
  
  if [ "$seconds" -lt 60 ]; then
    printf "%ds" "$seconds"
  elif [ "$seconds" -lt 3600 ]; then
    local mins=$((seconds / 60))
    local secs=$((seconds % 60))
    printf "%dm %ds" "$mins" "$secs"
  else
    local hours=$((seconds / 3600))
    local mins=$(((seconds % 3600) / 60))
    printf "%dh %dm" "$hours" "$mins"
  fi
}

# Calculate ETA (estimated time of arrival) for remaining work
ETA() {
  local completed="${1:-0}" total="${2:-1}" elapsed="${3:-0}"
  
  # Validate all inputs are numeric
  case "$completed" in *[!0-9]*) completed=0 ;; esac
  case "$total" in *[!0-9]*) total=1 ;; esac
  case "$elapsed" in *[!0-9]*) elapsed=0 ;; esac
  
  # Avoid division by zero
  if [ "$completed" -eq 0 ] || [ "$total" -eq 0 ]; then
    echo "Unknown"
    return
  fi
  
  # Calculate remaining time
  local remaining_work=$((total - completed))
  if [ "$remaining_work" -le 0 ]; then
    echo "Complete"
    return
  fi
  
  # Calculate estimated remaining seconds
  local rate_per_unit=$((elapsed / completed))
  local eta_seconds=$((remaining_work * rate_per_unit))
  
  format_duration "$eta_seconds"
}

# === File Size and Disk Space ===

# Format bytes into human-readable format
format_bytes() {
  local bytes="${1:-0}"
  
  # Validate input is numeric
  case "$bytes" in
    *[!0-9]*) bytes=0 ;;
  esac
  
  if [ "$bytes" -lt 1024 ]; then
    printf "%d B" "$bytes"
  elif [ "$bytes" -lt 1048576 ]; then
    printf "%.1f KB" "$(( bytes * 10 / 1024 )).$(( (bytes * 10 / 1024) % 10 ))"
  elif [ "$bytes" -lt 1073741824 ]; then
    local mb=$((bytes / 1048576))
    printf "%d MB" "$mb"
  else
    local gb=$((bytes / 1073741824))
    printf "%d GB" "$gb"
  fi
}

# Check disk space and warn if low
check_disk_space() {
  local path="${1:-$HOME}"
  local min_free_mb="${2:-100}"
  
  if command -v df >/dev/null 2>&1; then
    local available_kb
    available_kb=$(df "$path" 2>/dev/null | awk 'NR==2 {print $4}' 2>/dev/null || echo "0")
    local available_mb=$((available_kb / 1024))
    
    if [ "$available_mb" -lt "$min_free_mb" ] 2>/dev/null; then
      warn "Low disk space: $(format_bytes $((available_mb * 1024 * 1024))) available in $path"
      return 1
    else
      debug "Disk space OK: $(format_bytes $((available_mb * 1024 * 1024))) available in $path"
      return 0
    fi
  else
    warn "Cannot check disk space - df command not available"
    return 1
  fi
}