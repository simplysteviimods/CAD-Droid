#!/usr/bin/env bash
###############################################################################
# CAD-Droid Colors Library
# Color definitions and terminal color support detection
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_COLORS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_COLORS_LOADED=1

# === Color Support Detection ===

# Initialize color support detection
init_color_support() {
  local colors=8
  if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
    colors=$(tput colors 2>/dev/null || echo 8)
  fi
  
  # Check for color support and terminal capability
  if [ "$colors" -lt 8 ] || [ "${TERM:-}" = "dumb" ]; then
    export HAS_COLOR_SUPPORT=0
    return 1
  else
    export HAS_COLOR_SUPPORT=1
    return 0
  fi
}

# === Pastel Color Palette ===

# Pastel color definitions - the heart of CAD-Droid's visual theme
declare -a PASTEL_HEX
PASTEL_HEX=( 
  "AFEEEE"  # Pastel Cyan
  "FFC9D9"  # Pastel Pink  
  "DCC9FF"  # Pastel Lavender
  "C9FFD1"  # Pastel Green
  "FFEBAA"  # Pastel Yellow
  "FFD1AA"  # Pastel Peach
  "C9E0FF"  # Pastel Blue
  "E6C9FF"  # Pastel Purple
  "FFAAC9"  # Pastel Rose
  "D1FFE6"  # Pastel Mint
  "FFEBC9"  # Pastel Cream
  "F0C9FF"  # Pastel Violet
)

# Vibrant accent colors for highlights
declare -a VIBRANT_HEX
VIBRANT_HEX=( 
  "40E0D0"  # Turquoise
  "FF69B4"  # Hot Pink
  "9370DB"  # Medium Purple  
  "32CD32"  # Lime Green
  "FFD700"  # Gold
  "FF6347"  # Tomato
  "4169E1"  # Royal Blue
  "DA70D6"  # Orchid
  "FF1493"  # Deep Pink
  "00FA9A"  # Medium Spring Green
  "FFA500"  # Orange
  "8A2BE2"  # Blue Violet
)

# === Color Variable Definitions ===

# Initialize color variables with fallback support
init_color_variables() {
  if init_color_support; then
    # Primary pastel colors
    export PASTEL_CYAN='\033[38;2;175;238;238m'    # AFEEEE
    export PASTEL_PINK='\033[38;2;255;201;217m'    # FFC9D9  
    export PASTEL_LAVENDER='\033[38;2;220;201;255m' # DCC9FF
    export PASTEL_GREEN='\033[38;2;201;255;209m'   # C9FFD1
    export PASTEL_YELLOW='\033[38;2;255;235;170m'  # FFEBAA
    export PASTEL_PEACH='\033[38;2;255;209;170m'   # FFD1AA
    export PASTEL_BLUE='\033[38;2;201;224;255m'    # C9E0FF
    export PASTEL_PURPLE='\033[38;2;230;201;255m'  # E6C9FF
    export PASTEL_ROSE='\033[38;2;255;170;201m'    # FFAAC9
    export PASTEL_MINT='\033[38;2;209;255;230m'    # D1FFE6
    export PASTEL_CREAM='\033[38;2;255;235;201m'   # FFEBC9
    export PASTEL_VIOLET='\033[38;2;240;201;255m'  # F0C9FF
    
    # Vibrant accent colors
    export VIBRANT_CYAN='\033[38;2;64;224;208m'    # 40E0D0
    export VIBRANT_PINK='\033[38;2;255;105;180m'   # FF69B4
    export VIBRANT_PURPLE='\033[38;2;147;112;219m' # 9370DB
    export VIBRANT_GREEN='\033[38;2;50;205;50m'    # 32CD32
    export VIBRANT_YELLOW='\033[38;2;255;215;0m'   # FFD700
    export VIBRANT_RED='\033[38;2;255;99;71m'      # FF6347
    
    # Standard colors with pastel tint
    export RESET='\033[0m'
    export BOLD='\033[1m'
    export DIM='\033[2m'
    export UNDERLINE='\033[4m'
    
    # Background colors for highlights
    export BG_PASTEL_CYAN='\033[48;2;175;238;238m'
    export BG_PASTEL_PINK='\033[48;2;255;201;217m'
    export BG_PASTEL_LAVENDER='\033[48;2;220;201;255m'
    
    # Gradient transition colors
    export GRADIENT_START="$PASTEL_CYAN"
    export GRADIENT_MID="$PASTEL_LAVENDER" 
    export GRADIENT_END="$PASTEL_PINK"
    
  else
    # Fallback for terminals without color support
    export PASTEL_CYAN=''
    export PASTEL_PINK=''
    export PASTEL_LAVENDER=''
    export PASTEL_GREEN=''
    export PASTEL_YELLOW=''
    export PASTEL_PEACH=''
    export PASTEL_BLUE=''
    export PASTEL_PURPLE=''
    export PASTEL_ROSE=''
    export PASTEL_MINT=''
    export PASTEL_CREAM=''
    export PASTEL_VIOLET=''
    
    export VIBRANT_CYAN=''
    export VIBRANT_PINK=''
    export VIBRANT_PURPLE=''
    export VIBRANT_GREEN=''
    export VIBRANT_YELLOW=''
    export VIBRANT_RED=''
    
    export RESET=''
    export BOLD=''
    export DIM=''
    export UNDERLINE=''
    
    export BG_PASTEL_CYAN=''
    export BG_PASTEL_PINK=''
    export BG_PASTEL_LAVENDER=''
    
    export GRADIENT_START=''
    export GRADIENT_MID=''
    export GRADIENT_END=''
  fi
}

# === Color Utility Functions ===

# Convert hex color to RGB values
hex_to_rgb() {
  local hex="$1"
  # Remove # if present
  hex="${hex#\#}"
  
  # Extract RGB components
  local r=$((16#${hex:0:2}))
  local g=$((16#${hex:2:2}))
  local b=$((16#${hex:4:2}))
  
  echo "$r $g $b"
}

# Create ANSI color code from hex
hex_to_ansi() {
  local hex="$1"
  local rgb
  rgb=$(hex_to_rgb "$hex")
  echo "\033[38;2;${rgb// /;}m"
}

# Create background ANSI color code from hex
hex_to_ansi_bg() {
  local hex="$1"
  local rgb
  rgb=$(hex_to_rgb "$hex")
  echo "\033[48;2;${rgb// /;}m"
}

# Get random pastel color
get_random_pastel() {
  local count=${#PASTEL_HEX[@]}
  local index=$((RANDOM % count))
  hex_to_ansi "${PASTEL_HEX[$index]}"
}

# Get random vibrant color
get_random_vibrant() {
  local count=${#VIBRANT_HEX[@]}
  local index=$((RANDOM % count))
  hex_to_ansi "${VIBRANT_HEX[$index]}"
}

# Cycle through pastel colors for varied display
get_cycled_pastel() {
  local cycle_index="${1:-0}"
  local count=${#PASTEL_HEX[@]}
  local index=$((cycle_index % count))
  hex_to_ansi "${PASTEL_HEX[$index]}"
}

# === Color Testing and Validation ===

# Test if terminal supports true color (24-bit)
test_truecolor_support() {
  local test_color='\033[38;2;255;100;0m'
  local reset='\033[0m'
  
  # This is a simple heuristic - more advanced detection possible
  if [ "${COLORTERM:-}" = "truecolor" ] || [ "${COLORTERM:-}" = "24bit" ]; then
    return 0
  elif [ -n "${TERM_PROGRAM:-}" ] && [[ "${TERM_PROGRAM}" =~ (iTerm|Terminal|Hyper) ]]; then
    return 0
  else
    # Conservative fallback
    return 1
  fi
}

# Display color palette for testing
show_color_palette() {
  if [ "$HAS_COLOR_SUPPORT" != "1" ]; then
    echo "Color support not available"
    return 1
  fi
  
  echo -e "\n${BOLD}CAD-Droid Pastel Color Palette:${RESET}\n"
  
  local i=0
  for hex in "${PASTEL_HEX[@]}"; do
    local color
    color=$(hex_to_ansi "$hex")
    printf "%s●%s " "$color" "$RESET"
    i=$((i + 1))
    if [ $((i % 6)) -eq 0 ]; then
      echo
    fi
  done
  
  echo -e "\n\n${BOLD}Vibrant Accent Colors:${RESET}\n"
  
  i=0
  for hex in "${VIBRANT_HEX[@]}"; do
    local color
    color=$(hex_to_ansi "$hex")
    printf "%s●%s " "$color" "$RESET"
    i=$((i + 1))
    if [ $((i % 6)) -eq 0 ]; then
      echo
    fi
  done
  
  echo -e "\n"
}

# === Initialization ===

# Initialize color system on module load
init_color_variables

# Export arrays for use by other modules
export PASTEL_HEX
export VIBRANT_HEX

# Export functions
export -f init_color_support
export -f init_color_variables
export -f hex_to_rgb
export -f hex_to_ansi
export -f hex_to_ansi_bg
export -f get_random_pastel
export -f get_random_vibrant
export -f get_cycled_pastel
export -f test_truecolor_support
export -f show_color_pale
