#!/usr/bin/env bash
# colors.sh - Color definitions and visual functions with proper variable initialization
# This module handles all color palettes, visual effects, and terminal display

# Prevent multiple sourcing
if [[ "${CAD_COLORS_LOADED:-}" == "1" ]]; then
    return 0
fi
export CAD_COLORS_LOADED=1

# Color configuration constants - ensure all are properly initialized
export COLOR_SUPPORT_THRESHOLD="${COLOR_SUPPORT_THRESHOLD:-256}"
export TRUE_COLOR_SUPPORT="${TRUE_COLOR_SUPPORT:-}"  # Will be detected
export COLOR_FALLBACK_ENABLED="${COLOR_FALLBACK_ENABLED:-1}"

# Color palette definitions for beautiful terminal output
# Ensure arrays are properly declared and initialized
declare -a PASTEL_HEX
PASTEL_HEX=( 
  "9DF2F2" "FFDFA8" "DCC9FF" "FFC9D9" "C9FFD1" "FBE6A2" 
  "C9E0FF" "FAD3C4" "E0D1FF" "FFE2F1" "D1FFE6" "FFEBC9" 
)

declare -a VIBRANT_HEX
VIBRANT_HEX=( 
  "31D4D4" "FFAA1F" "9B59FF" "FF4F7D" "2EE860" "FFCF26" 
  "4FA6FF" "FF8A4B" "7E4BFF" "FF5FA2" "11DB78" "FFB347" 
)

# Export arrays for use in other modules
export PASTEL_HEX VIBRANT_HEX

# Fallback color constants - ensure all have proper values
export FALLBACK_COLOR="${FALLBACK_COLOR:-\033[38;2;221;160;221m}"  # Pastel purple
export DEFAULT_RESET="${DEFAULT_RESET:-\033[0m}"

# Color validation regex patterns
export HEX_COLOR_REGEX='^[0-9A-Fa-f]{6}$'
export RGB_VALUE_REGEX='^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$'

# Initialize color support detection with comprehensive fallback
init_color_support() {
  local colors=8
  
  # Try tput first
  if command -v tput >/dev/null 2>&1; then
    colors=$(tput colors 2>/dev/null || echo 8)
  fi
  
  # Validate colors is numeric
  case "$colors" in
    *[!0-9]*) colors=8 ;;
    *) 
      if [ "$colors" -lt 8 ]; then colors=8; fi
      if [ "$colors" -gt 16777216 ]; then colors=16777216; fi
      ;;
  esac
  
  # Check environment variables for color support hints
  case "${COLORTERM:-}" in
    truecolor|24bit)
      colors=16777216
      TRUE_COLOR_SUPPORT=1
      ;;
    256color|256)
      if [ "$colors" -lt 256 ]; then colors=256; fi
      ;;
  esac
  
  case "${TERM:-}" in
    *-256color)
      if [ "$colors" -lt 256 ]; then colors=256; fi
      ;;
    *-truecolor|*-24bit)
      colors=16777216
      TRUE_COLOR_SUPPORT=1
      ;;
  esac
  
  # Export detected color support
  export DETECTED_COLOR_SUPPORT="$colors"
  export TRUE_COLOR_SUPPORT="${TRUE_COLOR_SUPPORT:-0}"
  
  # Support high color (256) and true color (24-bit) terminals
  if [ "$colors" -ge "$COLOR_SUPPORT_THRESHOLD" ] || [ -n "${COLORTERM:-}" ]; then
    return 0  # High color support available
  else
    return 1  # Limited color support
  fi
}

# Initialize pastel color variables with comprehensive fallback support
init_pastel_colors() {
  local color_support=0
  
  # Detect color support
  if init_color_support; then
    color_support=1
  fi
  
  if [ "$color_support" -eq 1 ]; then
    # Define comprehensive pastel color palette with true color support
    export PASTEL_PURPLE="${PASTEL_PURPLE:-\033[38;2;221;160;221m}"     # Plum #DDA0DD
    export PASTEL_PINK="${PASTEL_PINK:-\033[38;2;255;182;193m}"         # Light Pink #FFB6C1
    export PASTEL_MAGENTA="${PASTEL_MAGENTA:-\033[38;2;255;192;203m}"    # Light Pink (magenta variant) #FFC0CB
    export PASTEL_CYAN="${PASTEL_CYAN:-\033[38;2;175;238;238m}"         # Pale Turquoise #AFEEEE
    export PASTEL_GREEN="${PASTEL_GREEN:-\033[38;2;144;238;144m}"        # Light Green #90EE90
    export PASTEL_YELLOW="${PASTEL_YELLOW:-\033[38;2;255;255;224m}"      # Light Yellow #FFFFE0
    export PASTEL_ORANGE="${PASTEL_ORANGE:-\033[38;2;255;218;185m}"      # Peach Puff #FFDAB9
    export PASTEL_BLUE="${PASTEL_BLUE:-\033[38;2;173;216;230m}"         # Light Blue #ADD8E6
    export PASTEL_RED="${PASTEL_RED:-\033[38;2;255;192;203m}"           # Light Pink (red variant) #FFC0CB
    export RESET="${RESET:-$DEFAULT_RESET}"
    
    # Additional vibrant colors for accents
    export VIBRANT_PURPLE="${VIBRANT_PURPLE:-\033[38;2;155;89;255m}"     # Vibrant Purple
    export VIBRANT_PINK="${VIBRANT_PINK:-\033[38;2;255;79;125m}"         # Hot Pink
    export VIBRANT_CYAN="${VIBRANT_CYAN:-\033[38;2;49;212;212m}"         # Bright Cyan
    export VIBRANT_GREEN="${VIBRANT_GREEN:-\033[38;2;46;232;96m}"        # Bright Green
    export VIBRANT_YELLOW="${VIBRANT_YELLOW:-\033[38;2;255;207;38m}"     # Bright Yellow
    export VIBRANT_ORANGE="${VIBRANT_ORANGE:-\033[38;2;255;138;75m}"     # Bright Orange
    export VIBRANT_BLUE="${VIBRANT_BLUE:-\033[38;2;79;166;255m}"         # Bright Blue
    export VIBRANT_RED="${VIBRANT_RED:-\033[38;2;255;95;162m}"           # Bright Pink-Red
    
  else
    # Use basic ANSI colors for limited terminals
    export PASTEL_PURPLE="${PASTEL_PURPLE:-\033[35m}"    # Magenta
    export PASTEL_PINK="${PASTEL_PINK:-\033[95m}"        # Bright magenta
    export PASTEL_MAGENTA="${PASTEL_MAGENTA:-\033[95m}"  # Bright magenta
    export PASTEL_CYAN="${PASTEL_CYAN:-\033[96m}"        # Bright cyan
    export PASTEL_GREEN="${PASTEL_GREEN:-\033[92m}"      # Bright green
    export PASTEL_YELLOW="${PASTEL_YELLOW:-\033[93m}"    # Bright yellow
    export PASTEL_ORANGE="${PASTEL_ORANGE:-\033[91m}"    # Bright red (orange fallback)
    export PASTEL_BLUE="${PASTEL_BLUE:-\033[94m}"        # Bright blue
    export PASTEL_RED="${PASTEL_RED:-\033[31m}"          # Red
    export RESET="${RESET:-$DEFAULT_RESET}"
    
    # Vibrant colors fallback to bright ANSI colors
    export VIBRANT_PURPLE="${VIBRANT_PURPLE:-\033[95m}"   # Bright magenta
    export VIBRANT_PINK="${VIBRANT_PINK:-\033[95m}"       # Bright magenta
    export VIBRANT_CYAN="${VIBRANT_CYAN:-\033[96m}"       # Bright cyan
    export VIBRANT_GREEN="${VIBRANT_GREEN:-\033[92m}"     # Bright green
    export VIBRANT_YELLOW="${VIBRANT_YELLOW:-\033[93m}"   # Bright yellow
    export VIBRANT_ORANGE="${VIBRANT_ORANGE:-\033[91m}"   # Bright red
    export VIBRANT_BLUE="${VIBRANT_BLUE:-\033[94m}"       # Bright blue
    export VIBRANT_RED="${VIBRANT_RED:-\033[91m}"         # Bright red
  fi
  
  # Always ensure RESET is available
  export RESET="${RESET:-$DEFAULT_RESET}"
}

# Convert RGB values to ANSI escape sequence with validation
rgb_seq() { 
  local r="${1:-0}" g="${2:-0}" b="${3:-0}"
  
  # Validate RGB values are within 0-255 range
  local vals=("$r" "$g" "$b")
  for val in "${vals[@]}"; do
    # Check if value is numeric
    case "$val" in
      *[!0-9]*) 
        printf "%s" "$FALLBACK_COLOR"
        return 1 
        ;;
      *) 
        if [ "$val" -lt 0 ] || [ "$val" -gt 255 ]; then
          printf "%s" "$FALLBACK_COLOR"
          return 1
        fi
        ;;
    esac
  done
  
  # Return true color sequence if supported, otherwise fallback
  if [ "${TRUE_COLOR_SUPPORT:-0}" = "1" ] || [ "${DETECTED_COLOR_SUPPORT:-8}" -ge 256 ]; then
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
  else
    printf "%s" "$FALLBACK_COLOR"
  fi
}

# Convert hex color to RGB values with comprehensive validation
hex_to_rgb() { 
  local hex="${1:-}"
  
  if [ -z "$hex" ]; then
    echo "0 0 0"
    return 1
  fi
  
  # Remove # prefix if present
  hex="${hex#\#}"
  
  # Validate hex format (exactly 6 characters, hex digits only)
  if ! echo "$hex" | grep -qE "$HEX_COLOR_REGEX"; then
    echo "0 0 0"  # Invalid hex, return black
    return 1
  fi
  
  # Extract RGB components with error handling
  local r g b
  r=$(printf "%d" "0x${hex:0:2}" 2>/dev/null || echo "0")
  g=$(printf "%d" "0x${hex:2:2}" 2>/dev/null || echo "0")  
  b=$(printf "%d" "0x${hex:4:2}" 2>/dev/null || echo "0")
  
  # Validate extracted values
  for val in "$r" "$g" "$b"; do
    case "$val" in
      *[!0-9]*|"") val=0 ;;
      *) 
        if [ "$val" -lt 0 ] || [ "$val" -gt 255 ]; then val=0; fi
        ;;
    esac
  done
  
  echo "$r $g $b"
}

# Check if terminal supports true color with multiple detection methods
supports_truecolor() {
  # Check if already detected
  if [ "${TRUE_COLOR_SUPPORT:-}" = "1" ]; then
    return 0
  fi
  
  # Check common indicators for true color support
  case "${COLORTERM:-}" in
    truecolor|24bit) 
      TRUE_COLOR_SUPPORT=1
      export TRUE_COLOR_SUPPORT
      return 0 
      ;;
  esac
  
  case "${TERM:-}" in
    *-truecolor|*-24bit|xterm-kitty) 
      TRUE_COLOR_SUPPORT=1
      export TRUE_COLOR_SUPPORT
      return 0 
      ;;
    *-256color) 
      # 256 color support, but not necessarily true color
      ;;
  esac
  
  # Check terminal program specific indicators
  if [ -n "${KITTY_WINDOW_ID:-}" ] || [ -n "${ALACRITTY_SOCKET:-}" ]; then
    TRUE_COLOR_SUPPORT=1
    export TRUE_COLOR_SUPPORT
    return 0
  fi
  
  # Default to false if not detected
  TRUE_COLOR_SUPPORT=0
  export TRUE_COLOR_SUPPORT
  return 1
}

# Create a gradient line with specified colors and character
gradient_line() {
  local start_hex="${1:-9DF2F2}" end_hex="${2:-31D4D4}" char="${3:-=}"
  
  # Validate hex colors
  if ! echo "$start_hex" | grep -qE "$HEX_COLOR_REGEX"; then
    start_hex="9DF2F2"  # Default pastel cyan
  fi
  
  if ! echo "$end_hex" | grep -qE "$HEX_COLOR_REGEX"; then
    end_hex="31D4D4"    # Default vibrant cyan
  fi
  
  # Get terminal width with proper fallback
  local width
  if command -v tput >/dev/null 2>&1; then
    width=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
  else
    width="${COLUMNS:-80}"
  fi
  
  # Validate and constrain width
  case "$width" in
    *[!0-9]*) width=80 ;;
    *) 
      if [ "$width" -lt 20 ]; then width=80; fi
      if [ "$width" -gt 200 ]; then width=200; fi
      ;;
  esac
  
  # Get RGB values for start and end colors
  local start_rgb end_rgb
  start_rgb=$(hex_to_rgb "$start_hex")
  end_rgb=$(hex_to_rgb "$end_hex")
  
  read -r sr sg sb <<< "$start_rgb"
  read -r er eg eb <<< "$end_rgb"
  
  # Create gradient if terminal supports it and width is reasonable
  if supports_truecolor && [ "$width" -gt 10 ]; then
    local i=0
    while [ "$i" -lt "$width" ]; do
      # Calculate color interpolation with safe arithmetic
      local progress=0
      if [ "$width" -gt 0 ]; then
        progress=$((i * 100 / width))
      fi
      
      local r=$(( sr + (er - sr) * progress / 100 ))
      local g=$(( sg + (eg - sg) * progress / 100 ))
      local b=$(( sb + (eb - sb) * progress / 100 ))
      
      # Ensure RGB values are in valid range
      [ "$r" -lt 0 ] && r=0; [ "$r" -gt 255 ] && r=255
      [ "$g" -lt 0 ] && g=0; [ "$g" -gt 255 ] && g=255
      [ "$b" -lt 0 ] && b=0; [ "$b" -gt 255 ] && b=255
      
      local color_seq
      color_seq=$(rgb_seq "$r" "$g" "$b" 2>/dev/null || printf "%s" "$FALLBACK_COLOR")
      printf "%b%s" "$color_seq" "$char"
      
      i=$((i + 1))
    done
    printf "%b\n" "$RESET"
  else
    # Fallback: simple colored line using start color
    local color_seq
    color_seq=$(rgb_seq "$sr" "$sg" "$sb" 2>/dev/null || printf "%s" "$FALLBACK_COLOR")
    printf "%b" "$color_seq"
    printf "%*s" "$width" "" | tr ' ' "$char"
    printf "%b\n" "$RESET"
  fi
}

# Generate a color sequence for middle of gradient with validation
mid_color_seq() {
  local start_hex="${1:-9DF2F2}" end_hex="${2:-31D4D4}"
  
  # Validate inputs
  if ! echo "$start_hex" | grep -qE "$HEX_COLOR_REGEX"; then
    start_hex="9DF2F2"
  fi
  
  if ! echo "$end_hex" | grep -qE "$HEX_COLOR_REGEX"; then
    end_hex="31D4D4"
  fi
  
  local start_rgb end_rgb
  start_rgb=$(hex_to_rgb "$start_hex")
  end_rgb=$(hex_to_rgb "$end_hex")
  
  read -r sr sg sb <<< "$start_rgb"
  read -r er eg eb <<< "$end_rgb"
  
  # Calculate middle color with safe arithmetic
  local mr=$(( (sr + er) / 2 ))
  local mg=$(( (sg + eg) / 2 ))
  local mb=$(( (sb + eb) / 2 ))
  
  # Ensure values are in valid range
  [ "$mr" -lt 0 ] && mr=0; [ "$mr" -gt 255 ] && mr=255
  [ "$mg" -lt 0 ] && mg=0; [ "$mg" -gt 255 ] && mg=255
  [ "$mb" -lt 0 ] && mb=0; [ "$mb" -gt 255 ] && mb=255
  
  rgb_seq "$mr" "$mg" "$mb" 2>/dev/null || printf "%s" "$FALLBACK_COLOR"
}

# Get color for specific index from palette with comprehensive bounds checking
color_for_index() {
  local index="${1:-0}" 
  local palette_size="${2:-${#PASTEL_HEX[@]}}"
  
  # Validate index is numeric
  case "$index" in
    *[!0-9]*) index=0 ;;
  esac
  
  # Ensure we have a palette to work with
  if [ "$palette_size" -le 0 ]; then
    printf "%s" "$FALLBACK_COLOR"
    return 1
  fi
  
  # Calculate index within bounds with safe modulo
  local safe_index=$((index % palette_size))
  local hex_color="${PASTEL_HEX[$safe_index]:-9DF2F2}"
  
  # Validate hex color from array
  if ! echo "$hex_color" | grep -qE "$HEX_COLOR_REGEX"; then
    hex_color="9DF2F2"  # Fallback to default
  fi
  
  # Convert to RGB and then to escape sequence
  local rgb
  rgb=$(hex_to_rgb "$hex_color")
  read -r r g b <<< "$rgb"
  
  rgb_seq "$r" "$g" "$b" 2>/dev/null || printf "%s" "$FALLBACK_COLOR"
}

# Helper function for colored echo with newline (used throughout the setup)
pecho() { 
  local color="${1:-$FALLBACK_COLOR}"
  shift
  
  # Validate color parameter
  if [ -z "$color" ]; then
    color="$FALLBACK_COLOR"
  fi
  
  printf "%b%s%b\n" "$color" "$*" "${RESET:-$DEFAULT_RESET}"
}

# Print informational message in pastel purple with fallback
info() { 
  pecho "${PASTEL_PURPLE:-\033[38;2;221;160;221m}" "$*"
}

# Print warning message in pastel pink with fallback
warn() { 
  pecho "${PASTEL_PINK:-\033[38;2;255;182;193m}" "$*"
}

# Print success message in pastel magenta with fallback
ok() { 
  pecho "${PASTEL_MAGENTA:-\033[38;2;255;192;203m}" "$*"
}

# Print error message in bright pink with fallback
err() { 
  pecho "${VIBRANT_PINK:-\033[38;2;255;105;180m}" "$*" >&2
}

# Test color functionality and display color palette
test_colors() {
  echo "=== CAD-Droid Color System Test ==="
  
  info "Color Support Detected: ${DETECTED_COLOR_SUPPORT:-unknown} colors"
  info "True Color Support: ${TRUE_COLOR_SUPPORT:-unknown}"
  
  echo
  info "Pastel Color Palette:"
  pecho "$PASTEL_PURPLE" "  Purple - Information messages"
  pecho "$PASTEL_PINK" "    Pink - Warning messages"  
  pecho "$PASTEL_MAGENTA" " Magenta - Success messages"
  pecho "$PASTEL_CYAN" "    Cyan - Input prompts"
  pecho "$PASTEL_GREEN" "   Green - Positive feedback"
  pecho "$PASTEL_YELLOW" "  Yellow - Neutral information"
  pecho "$PASTEL_BLUE" "    Blue - Secondary information"
  pecho "$PASTEL_ORANGE" "  Orange - Highlights"
  
  echo
  info "Vibrant Color Palette:"
  pecho "$VIBRANT_PURPLE" "  Purple - Accent text"
  pecho "$VIBRANT_PINK" "    Pink - Error messages"
  pecho "$VIBRANT_CYAN" "    Cyan - Bright highlights"
  pecho "$VIBRANT_GREEN" "   Green - Strong positive"
  pecho "$VIBRANT_YELLOW" "  Yellow - Attention"
  pecho "$VIBRANT_ORANGE" "  Orange - Warning accent"
  pecho "$VIBRANT_BLUE" "    Blue - Links/references"
  pecho "$VIBRANT_RED" "     Red - Critical alerts"
  
  echo
  info "Gradient Line Test:"
  gradient_line "9DF2F2" "31D4D4" "="
  gradient_line "DCC9FF" "9B59FF" "-"
  gradient_line "FFC9D9" "FF4F7D" "~"
  
  echo
  ok "Color system test completed!"
}

# Initialize color module
initialize_color_module() {
  # Ensure palette arrays are initialized
  if [ "${#PASTEL_HEX[@]}" -eq 0 ]; then
    warn "Pastel color palette not initialized properly"
    return 1
  fi
  
  if [ "${#VIBRANT_HEX[@]}" -eq 0 ]; then
    warn "Vibrant color palette not initialized properly"
    return 1
  fi
  
  # Initialize color support detection
  if ! init_color_support >/dev/null 2>&1; then
    warn "Color support detection failed, using fallbacks"
  fi
  
  # Initialize color variables
  if ! init_pastel_colors; then
    warn "Color initialization had issues"
    return 1
  fi
  
  return 0
}

# Initialize colors when this module is sourced
initialize_color_module || warn "Color module initialization completed with warnings"
