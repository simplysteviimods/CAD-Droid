#!/usr/bin/env bash
# Test script for CAD-Droid modules

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
echo "Testing module loading..."
for module in constants utils logging color; do
    echo "Loading $module..."
    source "$MODULES_DIR/${module}.sh" 2>/dev/null || echo "Error loading $module"
done

echo "Testing color initialization..."
init_pastel_colors 2>/dev/null || echo "Color init failed"

echo "Testing pecho with PASTEL_PINK:"
pecho "$PASTEL_PINK" "This should be pink text"

echo "Testing info function:"
info "This is an info message"

echo "Testing warn function:" 
warn "This is a warning message"

echo "Testing ok function:"
ok "This is a success message"

echo "Module test complete!"