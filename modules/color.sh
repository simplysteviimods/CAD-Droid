#!/usr/bin/env bash
###############################################################################
# CAD-Droid Color Module
# Color handling, terminal detection, gradient creation, and visual functions
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_COLOR_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_COLOR_LOADED=1

# === Color Support Detection ===

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

# === Color Functions ===

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
  local r g b
  r=$((0x${h:0:2}))
  g=$((0x${h:2:2}))
  b=$((0x${h:4:2}))
  
  printf "%d %d %d" "$r" "$g" "$b"
}

# Detect if terminal supports 24-bit "true color" mode
supports_truecolor(){
  # Check COLORTERM environment variable for common true color indicators
  case "${COLORTERM:-}" in 
    truecolor|24bit|*TrueColor*|*24bit*) return 0;;
  esac
  
  # Allow manual override via environment variable
  [ "${FORCE_TRUECOLOR:-0}" = "1" ] && return 0
  
  return 1
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

# === Terminal Display Functions ===

# Get terminal width for consistent display calculations
get_terminal_width() {
  local width=80  # Safe default
  
  # Try multiple methods to get terminal width
  if command -v stty >/dev/null 2>&1; then
    width=$(stty size 2>/dev/null | cut -d' ' -f2) || width=80
  fi
  
  # Fallback to environment variable
  if [ "$width" -le 0 ] 2>/dev/null; then
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

# Word-based text wrapping for body text
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

# Format body text with word wrapping
format_body_text() {
  local text="$1"
  local width
  width=$(get_terminal_width)
  local wrap_width=$((width - 8))  # Leave margin for readability
  
  wrap_text_words "$text" "$wrap_width"
}

# === Gradient and Visual Effects ===

# Create a gradient line across the terminal width with safe arithmetic
# Parameters: start_hex, end_hex, character (default "=")
# This creates beautiful colored separator lines
gradient_line(){
  local start="$1" end="$2" ch="${3:-=}" width
  
  # Get terminal width with proper fallback chain
  width=$(get_terminal_width)
  
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

# === Card and Header Display ===

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
  
  # Split text into first line and second line (same as draw_card title/subtitle)
  if [ -n "$text" ]; then
    local first_line second_line
    first_line=$(echo "$text" | head -1)
    second_line=$(echo "$text" | tail -n +2 | head -1)
    
    # Display first line (like title)
    if [ -n "$first_line" ]; then
      printf "%b%s%b\n" "$mid" "$(center_text "$first_line")" '\033[0m'
    fi
    
    # Display second line (like subtitle)
    if [ -n "$second_line" ]; then
      printf "%b%s%b\n" "$mid" "$(center_text "$second_line")" '\033[0m'
    fi
  fi
  
  # Draw bottom border
  gradient_line "$start" "$end" "="
  echo
}