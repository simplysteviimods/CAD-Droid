#!/usr/bin/env bash
# setup.sh - Main orchestration script for CAD-Droid mobile development setup
# This script coordinates all modules to create a complete Termux-based development environment

set -euo pipefail

# Script metadata
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="CAD-Droid Mobile Development Setup"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Essential environment setup with proper validation
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export HOME="${HOME:-/data/data/com.termux/files/home}"
export TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

# Validate essential paths exist
if [ ! -d "$PREFIX" ]; then
  echo "Error: Termux PREFIX directory not found: $PREFIX" >&2
  exit 1
fi

if [ ! -d "$HOME" ]; then
  echo "Error: Termux HOME directory not found: $HOME" >&2
  exit 1
fi

# Feature toggles with proper defaults
export ENABLE_SUNSHINE="${ENABLE_SUNSHINE:-1}"
export ENABLE_ADB="${ENABLE_ADB:-1}"
export NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
export AUTO_GITHUB="${AUTO_GITHUB:-0}"
export DEBUG="${DEBUG:-0}"
export SCRIPT_VERSION

# Security and environment guards
if [ "$(id -u 2>/dev/null || echo 1000)" -eq 0 ]; then
  echo "Error: Do not run as root" >&2
  exit 1
fi

if [ ! -d "/data/data/com.termux" ]; then
  echo "Error: Must run inside Termux" >&2
  exit 1
fi

# Create essential directories early
mkdir -p "$TMPDIR" "$HOME/.ssh" "$HOME/.config" "$HOME/.local/bin" 2>/dev/null || {
  echo "Warning: Failed to create some essential directories" >&2
}

# Set secure permissions
chmod 700 "$HOME/.ssh" 2>/dev/null || true

# Source all required modules with comprehensive error handling
source_modules() {
  local modules=(
    "colors"
    "utils" 
    "display"
    "input"
    "system"
    "steps"
  )
  
  local module_errors=0
  
  for module in "${modules[@]}"; do
    local module_path="$SCRIPT_DIR/lib/${module}.sh"
    
    if [ ! -f "$module_path" ]; then
      echo "Error: Required module not found: $module_path" >&2
      echo "Debug: SCRIPT_DIR=$SCRIPT_DIR" >&2
      echo "Debug: Available files in lib/:" >&2
      if [ -d "$SCRIPT_DIR/lib" ]; then
        ls -la "$SCRIPT_DIR/lib/" 2>/dev/null || echo "  lib directory listing failed" >&2
      else
        echo "  lib directory not found" >&2
      fi
      module_errors=$((module_errors + 1))
      continue
    fi
    
    if [ "${DEBUG:-0}" = "1" ]; then
      echo "Debug: Sourcing module: $module_path" >&2
    fi
    
    # Source module with error handling
    if ! source "$module_path"; then
      echo "Error: Failed to source module: $module_path" >&2
      module_errors=$((module_errors + 1))
    fi
  done
  
  if [ "$module_errors" -gt 0 ]; then
    echo "Error: $module_errors module(s) failed to load" >&2
    return 1
  fi
  
  return 0
}

# Initialize the environment with comprehensive validation
initialize() {
  echo "Initializing CAD-Droid setup environment..."
  
  # Source all modules first
  if ! source_modules; then
    echo "Error: Critical modules failed to load" >&2
    exit 1
  fi
  
  # Initialize color system (must be first for display functions)
  if ! initialize_color_module >/dev/null 2>&1; then
    echo "Warning: Color system initialization had issues" >&2
  fi
  
  # Test that essential functions are available
  if ! command -v info >/dev/null 2>&1; then
    echo "Error: Color module functions not available" >&2
    exit 1
  fi
  
  if ! command -v draw_card >/dev/null 2>&1; then
    echo "Error: Display module functions not available" >&2
    exit 1
  fi
  
  # Initialize other modules
  local init_errors=0
  
  if ! initialize_utils >/dev/null 2>&1; then
    warn "Utils module initialization had issues"
    init_errors=$((init_errors + 1))
  fi
  
  if ! initialize_input >/dev/null 2>&1; then
    warn "Input module initialization had issues"
    init_errors=$((init_errors + 1))
  fi
  
  if ! initialize_system_module >/dev/null 2>&1; then
    warn "System module initialization had issues"
    init_errors=$((init_errors + 1))
  fi
  
  # Report initialization status
  if [ "$init_errors" -eq 0 ]; then
    ok "Environment initialization completed successfully"
  else
    warn "Environment initialization completed with $init_errors module warnings"
  fi
  
  # Create additional necessary directories
  local dirs_to_create=(
    "$HOME/.cad-backups"
    "$HOME/.cad-credentials"
    "$HOME/projects"
    "$HOME/scripts"
  )
  
  for dir in "${dirs_to_create[@]}"; do
    mkdir -p "$dir" 2>/dev/null || true
    chmod 700 "$dir" 2>/dev/null || true
  done
  
  return 0
}

# Show welcome screen with enhanced information
show_welcome() {
  clear
  draw_card "$SCRIPT_NAME v$SCRIPT_VERSION" "Complete mobile development environment setup for Termux"
  
  info "This setup will install and configure:"
  pecho "$PASTEL_GREEN" "  • Essential development tools (git, curl, openssh, nano)"
  pecho "$PASTEL_GREEN" "  • XFCE desktop environment with X11 support"
  pecho "$PASTEL_GREEN" "  • Linux container with full Ubuntu development environment"
  pecho "$PASTEL_GREEN" "  • Enhanced terminal configuration with color themes"
  pecho "$PASTEL_GREEN" "  • Git and SSH key setup for development workflow"
  if [ "${ENABLE_ADB:-1}" = "1" ]; then
    pecho "$PASTEL_GREEN" "  • ADB wireless debugging configuration"
  fi
  if [ "${ENABLE_SUNSHINE:-1}" = "1" ]; then
    pecho "$PASTEL_GREEN" "  • Remote desktop streaming capabilities"
  fi
  pecho "$PASTEL_GREEN" "  • Mobile-optimized keyboard shortcuts and navigation"
  echo
  
  # Show system information
  info "System Information:"
  get_system_info | while IFS= read -r line; do
    if [ -n "$line" ]; then
      pecho "$PASTEL_CYAN" "  $line"
    fi
  done
  echo
  
  # Show feature status
  info "Feature Configuration:"
  pecho "$PASTEL_CYAN" "  • ADB Setup: ${ENABLE_ADB:-1}"
  pecho "$PASTEL_CYAN" "  • Remote Desktop: ${ENABLE_SUNSHINE:-1}"
  pecho "$PASTEL_CYAN" "  • Non-Interactive Mode: ${NON_INTERACTIVE:-0}"
  pecho "$PASTEL_CYAN" "  • Auto GitHub Setup: ${AUTO_GITHUB:-0}"
  pecho "$PASTEL_CYAN" "  • Debug Mode: ${DEBUG:-0}"
  echo
  
  if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
    pecho "$PASTEL_CYAN" "Press Enter to continue or Ctrl+C to cancel"
    read -r
  else
    info "Running in non-interactive mode - starting automatically"
    sleep 2
  fi
}

# Parse command line arguments with comprehensive validation
parse_arguments() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        show_help
        exit 0
        ;;
      --version|-v)
        echo "$SCRIPT_NAME v$SCRIPT_VERSION"
        exit 0
        ;;
      --non-interactive)
        export NON_INTERACTIVE=1
        ;;
      --auto-github)
        export AUTO_GITHUB=1
        ;;
      --disable-sunshine)
        export ENABLE_SUNSHINE=0
        ;;
      --disable-adb)
        export ENABLE_ADB=0
        ;;
      --debug)
        export DEBUG=1
        set -x
        ;;
      --test-colors)
        # Initialize modules first
        if source_modules && initialize_color_module; then
          test_colors
        else
          echo "Error: Could not initialize color system for testing" >&2
          exit 1
        fi
        exit 0
        ;;
      --self-test)
        run_self_tests
        exit $?
        ;;
      --system-info)
        # Initialize modules for system info
        if source_modules; then
          echo "=== CAD-Droid System Information ==="
          get_system_info
          echo
          if command -v get_device_info >/dev/null 2>&1; then
            get_device_info
          fi
          echo "=================================="
        else
          echo "Error: Could not initialize modules for system info" >&2
          exit 1
        fi
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
    shift
  done
}

# Show comprehensive help information
show_help() {
  cat << 'HELP_EOF'
CAD-Droid Mobile Development Setup - Help

USAGE:
  ./setup.sh [OPTIONS]

DESCRIPTION:
  Complete mobile development environment setup for Termux on Android devices.
  Installs essential development tools, desktop environment, Linux containers,
  and mobile-optimized configurations.

OPTIONS:
  --help, -h              Show this help message and exit
  --version, -v           Show script version and exit
  --non-interactive       Run without user prompts (automated mode)
  --auto-github          Skip GitHub setup prompts
  --disable-sunshine     Skip remote desktop setup
  --disable-adb          Skip ADB wireless debugging setup
  --debug                Enable verbose debug output
  --test-colors          Test color system and display palette
  --system-info          Display detailed system information
  --self-test            Run internal tests and exit

ENVIRONMENT VARIABLES:
  NON_INTERACTIVE=1      Skip all user interaction prompts
  AUTO_GITHUB=1          Skip GitHub setup interaction
  ENABLE_SUNSHINE=0      Disable remote desktop features
  ENABLE_ADB=0           Disable ADB debugging setup
  DEBUG=1                Show detailed debug information
  
EXAMPLES:
  ./setup.sh                     # Interactive setup with all features
  ./setup.sh --non-interactive   # Automated setup with defaults
  ./setup.sh --disable-sunshine  # Setup without remote desktop
  ./setup.sh --debug            # Setup with verbose output
  ./setup.sh --test-colors      # Test color system only
  ./setup.sh --system-info      # Show system information only
  
FEATURES:
  • XFCE Desktop Environment with X11 support
  • Ubuntu Linux container with development tools
  • Enhanced terminal with custom color themes
  • Git/SSH configuration for development workflow
  • Mobile-optimized keyboard shortcuts
  • Optional ADB wireless debugging setup
  • Optional remote desktop streaming
  
REQUIREMENTS:
  • Android device with Termux installed
  • Internet connection for package downloads
  • Sufficient storage space (recommended: 2GB+)
  • Android 7.0+ for full feature compatibility

For more information and troubleshooting, visit the project repository.
HELP_EOF
}

# Main execution flow with comprehensive error handling
main() {
  local main_errors=0
  
  # Parse command line arguments first
  parse_arguments "$@"
  
  # Initialize environment and modules
  if ! initialize; then
    echo "Error: Environment initialization failed" >&2
    exit 1
  fi
  
  # Check prerequisites
  if ! check_prerequisites; then
    err "Prerequisites check failed"
    main_errors=$((main_errors + 1))
  fi
  
  # Show welcome screen
  show_welcome
  
  # Register all installation steps
  if ! register_installation_steps; then
    err "Failed to register installation steps"
    exit 1
  fi
  
  # Execute the installation process
  if ! execute_installation_steps; then
    warn "Installation process completed with some failures"
    main_errors=$((main_errors + 1))
  fi
  
  # Show completion summary
  show_completion_summary
  
  # Final status
  if [ "$main_errors" -eq 0 ]; then
    ok "CAD-Droid setup completed successfully!"
    exit 0
  else
    warn "CAD-Droid setup completed with $main_errors issues"
    exit 1
  fi
}

# Run comprehensive internal self-tests
run_self_tests() {
  echo "=== CAD-Droid Self-Test Suite ==="
  local tests_passed=0
  local tests_failed=0
  
  # Initialize modules for testing
  if ! source_modules; then
    echo "FAIL: Could not load modules for testing"
    return 1
  fi
  
  # Test 1: Safe arithmetic operations
  echo -n "Testing safe_calc arithmetic functions... "
  if [ "$(safe_calc "2 + 3" 2>/dev/null || echo 0)" = "5" ] && \
     [ "$(safe_calc "10 - 4" 2>/dev/null || echo 0)" = "6" ] && \
     [ "$(safe_calc "3 * 4" 2>/dev/null || echo 0)" = "12" ]; then
    echo "PASS"
    tests_passed=$((tests_passed + 1))
  else
    echo "FAIL"
    tests_failed=$((tests_failed + 1))
  fi
  
  # Test 2: Input validation
  echo -n "Testing input validation functions... "
  if validate_input "test123" "$ALLOWED_USERNAME_REGEX" "username" 2>/dev/null && \
     validate_input "user@example.com" "$ALLOWED_EMAIL_REGEX" "email" 2>/dev/null; then
    echo "PASS"
    tests_passed=$((tests_passed + 1))
  else
    echo "FAIL"
    tests_failed=$((tests_failed + 1))
  fi
  
  # Test 3: Color system
  echo -n "Testing color system functions... "
  if [ -n "$(hex_to_rgb "FF0000" 2>/dev/null)" ] && \
     [ -n "${PASTEL_HEX[0]:-}" ] && \
     [ -n "${VIBRANT_HEX[0]:-}" ]; then
    echo "PASS"
    tests_passed=$((tests_passed + 1))
  else
    echo "FAIL"
    tests_failed=$((tests_failed + 1))
  fi
  
  # Test 4: File operations
  echo -n "Testing file operation functions... "
  local test_file="/tmp/cad_test_$$"
  if echo "test" > "$test_file" 2>/dev/null && \
     backup_file "$test_file" >/dev/null 2>&1; then
    rm -f "$test_file" 2>/dev/null
    echo "PASS"
    tests_passed=$((tests_passed + 1))
  else
    rm -f "$test_file" 2>/dev/null
    echo "FAIL"
    tests_failed=$((tests_failed + 1))
  fi
  
  # Test 5: System detection
  echo -n "Testing system detection functions... "
  if [ -n "$(detect_os 2>/dev/null)" ] && \
     [ -n "$(detect_primary_storage 2>/dev/null)" ]; then
    echo "PASS"
    tests_passed=$((tests_passed + 1))
  else
    echo "FAIL"
    tests_failed=$((tests_failed + 1))
  fi
  
  # Test 6: Text alignment system
  echo -n "Testing text alignment system... "
  if command -v align_text >/dev/null 2>&1 && \
     [ -n "$(align_text "test" "center" 80 4 2>/dev/null)" ]; then
    echo "PASS"
    tests_passed=$((tests_passed + 1))
  else
    echo "FAIL"
    tests_failed=$((tests_failed + 1))
  fi
  
  # Report results
  echo
  echo "=== Test Results ==="
  echo "Tests passed: $tests_passed"
  echo "Tests failed: $tests_failed"
  echo "Total tests:  $((tests_passed + tests_failed))"
  
  if [ "$tests_failed" -eq 0 ]; then
    echo "✅ All tests passed!"
    return 0
  else
    echo "❌ Some tests failed!"
    return 1
  fi
}

# Enhanced error handler with context information
error_handler() {
  local line_no="$1"
  local exit_code="${2:-1}"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "🚨 CAD-Droid Setup Error" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "Script failed at line $line_no with exit code $exit_code" >&2
  echo >&2
  echo "Debug Information:" >&2
  echo "  • Script: $(basename "${BASH_SOURCE[1]:-$0}")" >&2
  echo "  • Line: $line_no" >&2
  echo "  • Exit Code: $exit_code" >&2
  echo "  • Working Directory: $(pwd)" >&2
  echo "  • User: $(whoami 2>/dev/null || echo 'unknown')" >&2
  echo >&2
  echo "For help and troubleshooting:" >&2
  echo "  • Run: $0 --help" >&2
  echo "  • Run: $0 --system-info" >&2
  echo "  • Run: $0 --self-test" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  
  exit "$exit_code"
}

# Set up comprehensive error handling
trap 'error_handler $LINENO $?' ERR

# Cleanup function for graceful shutdown
cleanup() {
  local exit_code=$?
  
  # Clean up temporary files
  if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
    find "$TMPDIR" -name "cad_*" -type f -mmin +60 -delete 2>/dev/null || true
  fi
  
  # Show cursor (in case it was hidden)
  printf '\033[?25h' 2>/dev/null || true
  
  # Reset terminal colors
  printf '\033[0m' 2>/dev/null || true
  
  exit $exit_code
}

# Set up cleanup on exit
trap cleanup EXIT INT TERM

# Execute main function with all arguments
main "$@"
