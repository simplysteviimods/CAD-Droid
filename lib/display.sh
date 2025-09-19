#!/usr/bin/env bash
# display.sh - Display functions with integrated alignment system
# This module handles all visual presentation with unified text alignment and wrapping

# Prevent multiple sourcing
if [[ "${CAD_DISPLAY_LOADED:-}" == "1" ]]; then
    return 0
fi
export CAD_DISPLAY_LOADED=1

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

# Global card index for color cycling - ensure it's always initialized
export CARD_INDEX="${CARD_INDEX:-0}"

# Default alignment settings
export DEFAULT_TERMINAL_WIDTH="${DEFAULT_TERMINAL_WIDTH:-80}"
export DEFAULT_PADDING="${DEFAULT_PADDING:-4}"
export MIN_TERMINAL_WIDTH="${MIN_TERMINAL_WIDTH:-40}"
export MAX_TERMINAL_WIDTH="${MAX_TERMINAL_WIDTH:-200}"

# Alignment constants
readonly ALIGN_LEFT="left"
readonly ALIGN_CENTER="center"
readonly ALIGN_RIGHT="right"

# Get terminal width with robust fallback
get_terminal_width() {
  local width="${DEFAULT_TERMINAL_WIDTH}"
  
  # Try multiple methods to get terminal width
  if command -v tput >/dev/null 2>&1; then
    width=$(tput cols 2>/dev/null || echo "${DEFAULT_TERMINAL_WIDTH}")
  elif [ -n "${COLUMNS:-}" ]; then
    width="${COLUMNS}"
  fi
  
  # Validate and constrain width
  case "$width" in
    *[!0-9]*) width="${DEFAULT_TERMINAL_WIDTH}" ;;
    *) 
      if [ "$width" -lt "${MIN_TERMINAL_WIDTH}" ]; then 
        width="${MIN_TERMINAL_WIDTH}"
      elif [ "$width" -gt "${MAX_TERMINAL_WIDTH}" ]; then 
        width="${MAX_TERMINAL_WIDTH}"
      fi
      ;;
  esac
  
  echo "$width"
}

# Calculate text length without ANSI escape sequences
get_text_length() {
  local text="$1"
  # Remove ANSI escape sequences for accurate length calculation
  local clean_text
  clean_text=$(printf '%s' "$text" | sed 's/\x1b\[[0-9;]*m//g' 2>/dev/null || printf '%s' "$text")
  echo "${#clean_text}"
}

# Core alignment function - handles all alignment types with padding
align_text() {
  local text="${1:-}"
  local alignment="${2:-${ALIGN_CENTER}}"
  local width="${3:-$(get_terminal_width)}"
  local padding="${4:-0}"
  
  [ -z "$text" ] && return 0
  
  # Validate alignment parameter
  case "$alignment" in
    "${ALIGN_LEFT}"|"${ALIGN_CENTER}"|"${ALIGN_RIGHT}") ;;
    *) alignment="${ALIGN_CENTER}" ;;
  esac
  
  # Validate numeric parameters
  case "$width" in
    *[!0-9]*) width="$(get_terminal_width)" ;;
    *) [ "$width" -lt "${MIN_TERMINAL_WIDTH}" ] && width="${MIN_TERMINAL_WIDTH}" ;;
  esac
  
  case "$padding" in
    *[!0-9]*) padding="0" ;;
    *) [ "$padding" -gt "$((width / 2))" ] && padding="$((width / 4))" ;;
  esac
  
  local text_length
  text_length=$(get_text_length "$text")
  local available_width=$((width - padding * 2))
  
  # If text is too long for available width, truncate with ellipsis
  if [ "$text_length" -gt "$available_width" ] && [ "$available_width" -gt 3 ]; then
    local max_text_length=$((available_width - 3))
    text="${text:0:$max_text_length}..."
    text_length=$((max_text_length + 3))
  fi
  
  # Calculate spacing based on alignment
  case "$alignment" in
    "${ALIGN_LEFT}")
      local left_space="$padding"
      ;;
    "${ALIGN_RIGHT}")
      local left_space=$((width - text_length - padding))
      [ "$left_space" -lt 0 ] && left_space="0"
      ;;
    "${ALIGN_CENTER}"|*)
      local center_space=$(((available_width - text_length) / 2))
      [ "$center_space" -lt 0 ] && center_space="0"
      local left_space=$((padding + center_space))
      ;;
  esac
  
  # Output aligned text
  printf "%*s%s\n" "$left_space" "" "$text"
}

# Word wrapping with integrated alignment
wrap_and_align() {
  local text="${1:-}"
  local alignment="${2:-${ALIGN_CENTER}}"
  local width="${3:-$(get_terminal_width)}"
  local padding="${4:-${DEFAULT_PADDING}}"
  
  [ -z "$text" ] && return 0
  
  # Validate parameters
  case "$alignment" in
    "${ALIGN_LEFT}"|"${ALIGN_CENTER}"|"${ALIGN_RIGHT}") ;;
    *) alignment="${ALIGN_CENTER}" ;;
  esac
  
  case "$width" in
    *[!0-9]*) width="$(get_terminal_width)" ;;
  esac
  
  case "$padding" in
    *[!0-9]*) padding="${DEFAULT_PADDING}" ;;
  esac
  
  local wrap_width=$((width - padding * 2))
  
  # Ensure minimum wrap width
  if [ "$wrap_width" -lt 20 ]; then
    wrap_width=20
    padding=$(((width - wrap_width) / 2))
  fi
  
  # Process text expansion (handle escape sequences like \n)
  local expanded_text
  expanded_text=$(printf '%b' "$text" 2>/dev/null || printf '%s' "$text")
  
  # Split into lines and process each line
  printf '%s\n' "$expanded_text" | while IFS= read -r line || [ -n "$line" ]; do
    # Wrap line if needed using fold
    if command -v fold >/dev/null 2>&1; then
      printf '%s\n' "$line" | fold -w "$wrap_width" -s | while IFS= read -r wrapped_line; do
        align_text "$wrapped_line" "$alignment" "$width" "$padding"
      done
    else
      # Fallback: simple word wrapping
      local words current_line=""
      read -ra words <<< "$line"
      
      for word in "${words[@]}"; do
        local test_line
        if [ -z "$current_line" ]; then
          test_line="$word"
        else
          test_line="$current_line $word"
        fi
        
        local test_length
        test_length=$(get_text_length "$test_line")
        
        if [ "$test_length" -le "$wrap_width" ]; then
          current_line="$test_line"
        else
          # Output current line and start new one
          [ -n "$current_line" ] && align_text "$current_line" "$alignment" "$width" "$padding"
          current_line="$word"
        fi
      done
      
      # Output final line
      [ -n "$current_line" ] && align_text "$current_line" "$alignment" "$width" "$padding"
    fi
  done
}

# Enhanced card drawing with integrated alignment system
draw_card() {
  local title="${1:-}" subtitle="${2:-}"
  
  # Safely increment card index with bounds checking
  local current_index="${CARD_INDEX:-0}"
  case "$current_index" in
    *[!0-9-]*) current_index=0 ;;
    *) 
      [ "$current_index" -lt 0 ] && current_index=0
      [ "$current_index" -gt 1000 ] && current_index=0
      ;;
  esac
  
  # Ensure color arrays are available
  local palette_size="${#PASTEL_HEX[@]:-0}"
  if [ "$palette_size" -eq 0 ]; then
    warn "Color palette not initialized"
    return 1
  fi
  
  # Select colors with safe array access
  local color_idx=$((current_index % palette_size))
  local start_color="${PASTEL_HEX[$color_idx]:-9DF2F2}"
  local end_color="${VIBRANT_HEX[$color_idx]:-31D4D4}"
  local mid_color
  mid_color=$(mid_color_seq "$start_color" "$end_color" 2>/dev/null || echo "${FALLBACK_COLOR:-\033[38;2;221;160;221m}")
  
  # Safe increment with overflow protection
  CARD_INDEX=$(((current_index + 1) % 1000))
  
  local width
  width=$(get_terminal_width)
  
  # Draw top border
  gradient_line "$start_color" "$end_color" "="
  
  # Process title with integrated alignment
  if [ -n "$title" ]; then
    printf "%b" "$mid_color"
    wrap_and_align "$title" "${ALIGN_CENTER}" "$width" 4
    printf "%b" '\033[0m'
  fi
  
  # Process subtitle with integrated alignment
  if [ -n "$subtitle" ]; then
    printf "%b" "$mid_color"
    wrap_and_align "$subtitle" "${ALIGN_CENTER}" "$width" 4
    printf "%b" '\033[0m'
  fi
  
  # Draw bottom border
  gradient_line "$start_color" "$end_color" "="
  echo
}

# Enhanced phase header with integrated alignment
draw_phase_header() {
  local text="${1:-}"
  
  [ -z "$text" ] && return 0
  
  # Safely increment card index
  local current_index="${CARD_INDEX:-0}"
  case "$current_index" in
    *[!0-9-]*) current_index=0 ;;
    *) 
      [ "$current_index" -lt 0 ] && current_index=0
      [ "$current_index" -gt 1000 ] && current_index=0
      ;;
  esac
  
  # Ensure color arrays are available
  local palette_size="${#PASTEL_HEX[@]:-0}"
  if [ "$palette_size" -eq 0 ]; then
    warn "Color palette not initialized"
    return 1
  fi
  
  # Select colors with safe array access
  local color_idx=$((current_index % palette_size))
  local start_color="${PASTEL_HEX[$color_idx]:-9DF2F2}"
  local end_color="${VIBRANT_HEX[$color_idx]:-31D4D4}"
  local mid_color
  mid_color=$(mid_color_seq "$start_color" "$end_color" 2>/dev/null || echo "${FALLBACK_COLOR:-\033[38;2;221;160;221m}")
  
  # Safe increment
  CARD_INDEX=$(((current_index + 1) % 1000))
  
  local width
  width=$(get_terminal_width)
  
  # Draw top border
  gradient_line "$start_color" "$end_color" "="
  
  # Process text with integrated alignment
  printf "%b" "$mid_color"
  wrap_and_align "$text" "${ALIGN_CENTER}" "$width" 4
  printf "%b" '\033[0m'
  
  # Draw bottom border
  gradient_line "$start_color" "$end_color" "="
  echo
}

# Legacy compatibility functions using new alignment system
simple_center() {
  local text="${1:-}" width="${2:-$(get_terminal_width)}"
  align_text "$text" "${ALIGN_CENTER}" "$width" 2
}

center_line() {
  local text="${1:-}"
  align_text "$text" "${ALIGN_CENTER}"
}

# Backward compatibility for wrap functions
wrap_text() {
  local text="${1:-}" width="${2:-$(get_terminal_width)}"
  wrap_and_align "$text" "${ALIGN_CENTER}" "$width" 4
}

simple_wrap() {
  local text="${1:-}" width="${2:-$(get_terminal_width)}"
  wrap_and_align "$text" "${ALIGN_CENTER}" "$width" 3
}

# Progress spinner with consistent alignment
show_spinner() {
  local pid="${1:-}" msg="${2:-Working...}" delay="${3:-0.1}"
  
  # Validate delay
  case "$delay" in
    *[!0-9.]*) delay="0.1" ;;
    *) 
      if command -v awk >/dev/null 2>&1; then
        if ! awk "BEGIN{exit($delay>=0.05&&$delay<=5)}" 2>/dev/null; then
          delay="0.1"
        fi
      fi
      ;;
  esac
  
  # Spinner characters
  local chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local i=0
  
  # Hide cursor
  printf '\033[?25l'
  
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r'
    align_text "${PASTEL_CYAN:-\033[96m}${chars[i]} ${msg}${RESET:-\033[0m}" "${ALIGN_LEFT}" "$(get_terminal_width)" 2
    i=$(((i + 1) % ${#chars[@]}))
    sleep "$delay" 2>/dev/null || sleep 1
  done
  
  # Clean up
  printf '\r%*s\r' "$(get_terminal_width)" ""
  printf '\033[?25h'  # Show cursor
}

# Progress bar with consistent alignment
show_progress_bar() {
  local current="${1:-0}" total="${2:-100}" width="${3:-40}" label="${4:-Progress}"
  
  # Validate inputs with defaults
  case "$current" in *[!0-9]*) current=0 ;; esac
  case "$total" in *[!0-9]*) total=100 ;; esac
  case "$width" in *[!0-9]*) width=40 ;; esac
  
  # Prevent division by zero
  [ "$total" -eq 0 ] && total=1
  
  # Calculate progress
  local percentage=$((current * 100 / total))
  local filled=$((current * width / total))
  
  # Constrain values
  [ "$percentage" -gt 100 ] && percentage=100
  [ "$filled" -gt "$width" ] && filled="$width"
  
  # Build progress bar
  local bar=""
  local i=0
  while [ "$i" -lt "$filled" ]; do
    bar="${bar}█"
    i=$((i + 1))
  done
  while [ "$i" -lt "$width" ]; do
    bar="${bar}░"
    i=$((i + 1))
  done
  
  local progress_text="$label: ${PASTEL_GREEN:-\033[92m}[$bar]${RESET:-\033[0m} $percentage%"
  printf "\r"
  align_text "$progress_text" "${ALIGN_LEFT}" "$(get_terminal_width)" 2
}

# Summary table with consistent alignment
show_summary_table() {
  local -n items_ref="$1"
  local title="${2:-Summary}"
  
  if [ "${#items_ref[@]}" -eq 0 ]; then
    info "No items to display in summary"
    return
  fi
  
  draw_phase_header "$title"
  
  # Find longest item name for alignment
  local max_length=0
  for item in "${items_ref[@]}"; do
    local name="${item%%:*}"
    local name_length
    name_length=$(get_text_length "$name")
    [ "$name_length" -gt "$max_length" ] && max_length="$name_length"
  done
  
  # Display items with consistent alignment
  for item in "${items_ref[@]}"; do
    local name="${item%%:*}"
    local status="${item#*:}"
    local status_icon status_text status_color
    
    case "$status" in
      success|ok|completed)
        status_icon="✓"
        status_text="Completed"
        status_color="${PASTEL_GREEN:-\033[92m}"
        ;;
      failed|error)
        status_icon="✗"
        status_text="Failed"
        status_color="${PASTEL_RED:-\033[91m}"
        ;;
      skipped)
        status_icon="-"
        status_text="Skipped"
        status_color="${PASTEL_YELLOW:-\033[93m}"
        ;;
      *)
        status_icon="?"
        status_text="$status"
        status_color="${PASTEL_PURPLE:-\033[95m}"
        ;;
    esac
    
    local item_line
    item_line=$(printf "  %s%-*s%s %s%s %s%s" \
      "${PASTEL_CYAN:-\033[96m}" "$max_length" "$name" "${RESET:-\033[0m}" \
      "$status_color" "$status_icon" "$status_text" "${RESET:-\033[0m}")
    
    echo "$item_line"
  done
  
  echo
}
