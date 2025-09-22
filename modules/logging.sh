#!/usr/bin/env bash
###############################################################################
# CAD-Droid Logging Library
# Logging functions and output formatting for consistent messaging
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_LOGGING_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_LOGGING_LOADED=1

# === Logging Configuration ===

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Current log level (can be overridden by environment)
CURRENT_LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Log file location (if logging to file is enabled)
LOG_FILE="${RUN_LOG:+$HOME/cad-droid-setup.log}"

# === Terminal Utilities ===

# Get terminal width with fallback
get_terminal_width() {
  local width=80
  
  if command -v tput >/dev/null 2>&1; then
    width=$(tput cols 2>/dev/null || echo 80)
  elif [ -n "${COLUMNS:-}" ]; then
    width="$COLUMNS"
  fi
  
  # Validate and constrain width
  case "$width" in
    *[!0-9]*) width=80 ;;
    *) 
      [ "$width" -lt 40 ] && width=40
      [ "$width" -gt 200 ] && width=200
      ;;
  esac
  
  echo "$width"
}

# Strip ANSI escape sequences for length calculation
strip_ansi() {
  local text="$1"
  echo "$text" | sed 's/\x1b\[[0-9;]*m//g'
}

# Get actual text length without ANSI codes
get_text_length() {
  local text="$1"
  local clean_text
  clean_text=$(strip_ansi "$text")
  echo "${#clean_text}"
}

# === Core Logging Functions ===

# Write to log file if enabled
write_to_log() {
  local level="$1"
  local message="$2"
  
  if [ -n "$LOG_FILE" ]; then
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local clean_message
    clean_message=$(strip_ansi "$message")
    echo "[$timestamp] [$level] $clean_message" >> "$LOG_FILE"
  fi
}

# Debug messages (only shown when DEBUG=1)
debug() {
  [ "$CURRENT_LOG_LEVEL" -gt "$LOG_LEVEL_DEBUG" ] && return 0
  [ "${DEBUG:-0}" != "1" ] && return 0
  
  local message="$*"
  write_to_log "DEBUG" "$message"
  printf "${DIM}${PASTEL_CYAN}[DEBUG]${RESET}${DIM} %s${RESET}\n" "$message" >&2
}

# Informational messages
info() {
  [ "$CURRENT_LOG_LEVEL" -gt "$LOG_LEVEL_INFO" ] && return 0
  
  local message="$*"
  write_to_log "INFO" "$message"
  printf "${PASTEL_CYAN}ℹ${RESET} %s\n" "$message" >&2
}

# Warning messages  
warn() {
  [ "$CURRENT_LOG_LEVEL" -gt "$LOG_LEVEL_WARN" ] && return 0
  
  local message="$*"
  write_to_log "WARN" "$message"
  printf "${PASTEL_YELLOW}⚠${RESET} %s\n" "$message" >&2
}

# Error messages
err() {
  local message="$*"
  write_to_log "ERROR" "$message"
  printf "${VIBRANT_RED}✗${RESET} %s\n" "$message" >&2
}

# Success messages
ok() {
  local message="$*"
  write_to_log "SUCCESS" "$message"
  printf "${PASTEL_GREEN}✓${RESET} %s\n" "$message" >&2
}

# === Enhanced Logging Functions ===

# Info with icon
info_icon() {
  local icon="$1"
  shift
  local message="$*"
  write_to_log "INFO" "$icon $message"
  printf "${PASTEL_CYAN}%s${RESET} %s\n" "$icon" "$message" >&2
}

# Highlighted info messages
highlight() {
  local message="$*"
  write_to_log "HIGHLIGHT" "$message"
  printf "${BG_PASTEL_LAVENDER}${BOLD} %s ${RESET}\n" "$message" >&2
}

# Step messages with numbering
step() {
  local step_num="$1"
  shift
  local message="$*"
  write_to_log "STEP" "Step $step_num: $message"
  printf "${PASTEL_PINK}[${BOLD}%s${RESET}${PASTEL_PINK}]${RESET} %s\n" "$step_num" "$message" >&2
}

# Section headers
section() {
  local title="$*"
  local width
  width=$(get_terminal_width)
  local border_char="─"
  
  write_to_log "SECTION" "$title"
  
  # Create border
  local border=""
  local i=0
  while [ $i -lt "$width" ]; do
    border="${border}${border_char}"
    i=$((i + 1))
  done
  
  printf "\n${PASTEL_LAVENDER}%s${RESET}\n" "$border" >&2
  printf "${BOLD}${PASTEL_PINK}%s${RESET}\n" "$title" >&2
  printf "${PASTEL_LAVENDER}%s${RESET}\n\n" "$border" >&2
}

# Progress messages
progress() {
  local current="$1"
  local total="$2"
  local message="$3"
  
  local percentage=0
  if [ "$total" -gt 0 ] 2>/dev/null; then
    percentage=$(( (current * 100) / total ))
  fi
  
  write_to_log "PROGRESS" "($current/$total - ${percentage}%) $message"
  printf "${PASTEL_CYAN}[${BOLD}%s${RESET}${PASTEL_CYAN}/${BOLD}%s${RESET}${PASTEL_CYAN}]${RESET} %s ${DIM}(${percentage}%%)${RESET}\n" \
    "$current" "$total" "$message" >&2
}

# === Message Formatting ===

# Center text in terminal
center_text() {
  local text="$1"
  local width="${2:-$(get_terminal_width)}"
  
  local text_length
  text_length=$(get_text_length "$text")
  
  if [ "$text_length" -ge "$width" ]; then
    echo "$text"
    return
  fi
  
  local padding=$(( (width - text_length) / 2 ))
  printf "%*s%s\n" "$padding" "" "$text"
}

# Create a box around text
text_box() {
  local text="$*"
  local width
  width=$(get_terminal_width)
  local max_text_width=$((width - 4))  # Account for box borders
  
  # Split text into lines if too long
  local lines=()
  while [ ${#text} -gt "$max_text_width" ]; do
    local line="${text:0:$max_text_width}"
    local last_space="${line%% *}"
    if [ "$last_space" != "$line" ]; then
      # Break at last word boundary
      line="${text%% ${text#* * * * * * * * * *}}"
      text="${text#$line }"
    else
      # Force break if no spaces
      text="${text:$max_text_width}"
    fi
    lines+=("$line")
  done
  [ -n "$text" ] && lines+=("$text")
  
  # Draw box
  local border_top="┌"
  local border_bottom="└"
  local border_side="│"
  local border_char="─"
  
  local i=0
  while [ $i -lt $((max_text_width + 2)) ]; do
    border_top="${border_top}${border_char}"
    border_bottom="${border_bottom}${border_char}"
    i=$((i + 1))
  done
  border_top="${border_top}┐"
  border_bottom="${border_bottom}┘"
  
  printf "${PASTEL_LAVENDER}%s${RESET}\n" "$border_top" >&2
  
  for line in "${lines[@]}"; do
    local line_length
    line_length=$(get_text_length "$line")
    local padding=$((max_text_width - line_length))
    printf "${PASTEL_LAVENDER}%s${RESET} %s%*s ${PASTEL_LAVENDER}%s${RESET}\n" \
      "$border_side" "$line" "$padding" "" "$border_side" >&2
  done
  
  printf "${PASTEL_LAVENDER}%s${RESET}\n" "$border_bottom" >&2
}

# === Log Level Management ===

# Set log level
set_log_level() {
  local level="$1"
  case "$level" in
    "debug"|"DEBUG"|"0") CURRENT_LOG_LEVEL="$LOG_LEVEL_DEBUG" ;;
    "info"|"INFO"|"1") CURRENT_LOG_LEVEL="$LOG_LEVEL_INFO" ;;
    "warn"|"WARN"|"warning"|"WARNING"|"2") CURRENT_LOG_LEVEL="$LOG_LEVEL_WARN" ;;
    "error"|"ERROR"|"err"|"ERR"|"3") CURRENT_LOG_LEVEL="$LOG_LEVEL_ERROR" ;;
    *) 
      warn "Invalid log level: $level. Using INFO."
      CURRENT_LOG_LEVEL="$LOG_LEVEL_INFO"
      ;;
  esac
}

# Get current log level name
get_log_level() {
  case "$CURRENT_LOG_LEVEL" in
    "$LOG_LEVEL_DEBUG") echo "DEBUG" ;;
    "$LOG_LEVEL_INFO") echo "INFO" ;;
    "$LOG_LEVEL_WARN") echo "WARN" ;;
    "$LOG_LEVEL_ERROR") echo "ERROR" ;;
    *) echo "UNKNOWN" ;;
  esac
}

# === Initialization ===

# Initialize logging system
init_logging() {
  # Set log level from environment if provided
  if [ -n "${LOG_LEVEL:-}" ]; then
    set_log_level "$LOG_LEVEL"
  fi
  
  # Create log file if logging is enabled
  if [ -n "$LOG_FILE" ]; then
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir" 2>/dev/null || true
    
    # Write session header
    {
      echo ""
      echo "========================================"
      echo "CAD-Droid Setup Session Started"
      echo "Date: $(date)"
      echo "Log Level: $(get_log_level)"
      echo "========================================"
    } >> "$LOG_FILE"
  fi
}

# Initialize on module load
init_logging

# Export functions for use by other modules
export -f debug info warn err ok
export -f info_icon highlight step section progress
export -f center_text text_box
export -f get_terminal_width strip_ansi get_text_length
export -f set_log_level get_log_level
export -f write_to_log

# Export log level constants
export LOG_LEVEL_DEBUG LOG_LEVEL_INFO LOG_LEVEL_WARN LOG_LEVEL_ERROR
