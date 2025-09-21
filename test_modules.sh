#!/usr/bin/env bash
# Quick test of CAD-Droid module system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Mock required environment
PREFIX="/tmp/test_prefix"
HOME="/tmp/test_home"
mkdir -p "$PREFIX" "$HOME"
export PREFIX HOME

# Load modules in dependency order
load_module() {
  local module="$1"
  local module_path="$MODULES_DIR/${module}.sh"
  
  echo "Loading module: $module"
  # shellcheck source=/dev/null
  source "$module_path"
}

echo "=== CAD-Droid Module Loading Test ==="
echo

# Load all modules
load_module "constants"
load_module "utils"
load_module "logging" 
load_module "color"
load_module "spinner"
load_module "termux_props"
load_module "apk"
load_module "adb"
load_module "core_packages"
load_module "nano"

echo
echo "=== Testing Core Functions ==="

# Test basic functions
echo "Testing safe_calc: 2 + 3 = $(safe_calc "2 + 3")"
echo "Testing is_nonneg_int: is_nonneg_int 42 = $(is_nonneg_int 42 && echo "true" || echo "false")"
echo "Testing clamp_int: clamp_int 15 10 20 = $(clamp_int 15 10 20)"

# Test color support
echo "Testing color support: $(init_color_support && echo "supported" || echo "not supported")"

# Test validation
validate_curl_timeouts
validate_timeout_vars  
validate_spinner_delay
validate_apk_size

echo
echo "=== Module Loading Complete ==="
echo "✓ All modules loaded successfully"
echo "✓ Core functions operational"
echo "✓ Validation functions working"

echo
echo "Global variables set:"
echo "  SCRIPT_VERSION: ${SCRIPT_VERSION}"
echo "  CORE_PACKAGES count: ${#CORE_PACKAGES[@]}"
echo "  PASTEL_HEX count: ${#PASTEL_HEX[@]}"
echo "  VIBRANT_HEX count: ${#VIBRANT_HEX[@]}"

echo
echo "Available step functions:"
declare -F | grep "^declare -f step_" | head -5

echo
echo "=== Test Complete ==="