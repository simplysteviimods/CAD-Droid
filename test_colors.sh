#!/usr/bin/env bash
# Test script for CAD-Droid color enhancements

# Create mock Termux environment
PREFIX="/tmp/test_prefix"
HOME="/tmp/test_home"
mkdir -p "$PREFIX/tmp" "$HOME"
export PREFIX HOME TMPDIR="$PREFIX/tmp"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Mock functions to prevent errors
command() {
    if [ "$1" = "-v" ] && [ "$2" = "warn" ]; then
        return 0
    fi
    return 1
}

# Load modules
echo "Testing enhanced color system..."
for module in constants utils logging color; do
    echo "Loading $module..."
    source "$MODULES_DIR/${module}.sh" 2>/dev/null || echo "Error loading $module"
done

echo "Testing color initialization..."
init_pastel_colors 2>/dev/null || echo "Color init failed"

echo ""
echo "=== Enhanced User Interface Colors ==="

echo ""
echo "Section Headers (PASTEL_PURPLE):"
pecho "$PASTEL_PURPLE" "Installing core productivity packages..."
pecho "$PASTEL_PURPLE" "APK File Location Setup"
pecho "$PASTEL_PURPLE" "Setting up a nice text editor for you..."

echo ""
echo "Instructions and Options (PASTEL_PURPLE):"
pecho "$PASTEL_PURPLE" "Options:"
pecho "$PASTEL_PURPLE" "INSTRUCTIONS:"
pecho "$PASTEL_PURPLE" "Nano features enabled:"

echo ""
echo "Loading Messages (PASTEL_PURPLE → PASTEL_PINK):"
pecho "$PASTEL_PURPLE" "Loading specialized modules..."
pecho "$PASTEL_PINK" "✓ All modules loaded successfully"

echo ""
echo "Status Messages (preserved cyan/green):"
info "  1. Use default location (recommended)"
info "  2. Press Enter to open folder (view only)."
ok "Nano editor configured successfully"
warn "This is a warning message (preserved yellow)"

echo ""
echo "Interactive Elements:"
pecho "$PASTEL_CYAN" "Press Enter to open folder..."
pecho "$PASTEL_GREEN" "  2. Install *.apk add-ons."

echo ""
echo "=== Color Enhancement Complete ==="
echo "User-facing text now uses warm pastel colors while preserving"
echo "functional status indicators (cyan info, green success, yellow warnings)"