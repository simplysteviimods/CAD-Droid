#!/usr/bin/env bash
###############################################################################
# CAD-Droid: Android Development Environment Setup
# Main orchestrator script - sources modular components
#
# This script transforms your Android device into a powerful development 
# workstation using Termux. It sets up a complete Linux desktop environment
# with all the tools you need for serious coding, CAD work, and productivity.
###############################################################################

# Check if we're running in Bash shell, if not, restart with Bash
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

# Set strict error handling modes for robust script execution
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Set restrictive file permissions (owner read/write only) for security
umask 077

# Set consistent locale settings for predictable behavior
export LANG=C.UTF-8 LC_ALL=C.UTF-8 LC_CTYPE=C.UTF-8
export DEBIAN_FRONTEND=noninteractive

# === Security and Environment Guards ===

# Check for Windows-style line endings which can break bash scripts
if grep -q $'\r' "$0" 2>/dev/null; then
  printf "Error: CRLF line endings detected. Run: sed -i 's/\\\\r$//' %s\n" "$0" >&2
  exit 1
fi

# Prevent running as root user for security (Termux should never be root)
if [ "$EUID" -eq 0 ]; then 
  echo "Error: Do not run as root" >&2
  exit 1
fi

# Verify we're running inside Termux environment
if [ ! -d "/data/data/com.termux" ]; then
  echo "Error: Must run inside Termux" >&2
  exit 1
fi

# Verify critical paths exist
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"

if [ ! -d "$PREFIX" ]; then
  echo "Error: Termux PREFIX directory not found: $PREFIX" >&2
  exit 1
fi

if [ ! -d "$HOME" ]; then
  echo "Error: Termux HOME directory not found: $HOME" >&2
  exit 1
fi

# === Module Loading System ===

# Determine script directory for module loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Verify modules directory exists
if [ ! -d "$MODULES_DIR" ]; then
  echo "Error: Modules directory not found: $MODULES_DIR" >&2
  echo "Please ensure all CAD-Droid files are properly extracted" >&2
  exit 1
fi

# Load modules in dependency order
load_module() {
  local module="$1"
  local module_path="$MODULES_DIR/${module}.sh"
  
  if [ ! -f "$module_path" ]; then
    echo "Error: Module not found: $module_path" >&2
    exit 1
  fi
  
  # Source the module
  # shellcheck source=/dev/null
  source "$module_path"
}

# Load all modules in correct order
echo "Loading CAD-Droid modules..."

# 1. Foundation layer (order matters)
load_module "constants"
load_module "utils"

# 2. Core functionality (depends on foundation)
load_module "logging" 
load_module "color"
load_module "spinner"

# Initialize color support immediately after color module is loaded
init_pastel_colors

# 3. Specialized modules (can be loaded in any order)
load_module "termux_props"
load_module "apk"
load_module "adb"
load_module "core_packages"
load_module "nano"

pecho "$PASTEL_PINK" "✓ All modules loaded successfully"

# === Post-Module Initialization ===

# Apply all validations after modules are loaded
validate_curl_timeouts
validate_timeout_vars  
validate_spinner_delay
validate_apk_size

# Set up environment
ensure_tmpdir || {
  echo "Error: Cannot establish working temporary directory" >&2
  exit 1
}

# Call duplication detection after all modules loaded
assert_unique_definitions

# === Step Registration ===

# Initialize steps if not already done
initialize_steps(){
  # Clear existing arrays
  STEP_NAME=()
  STEP_FUNCS=()
  STEP_ETA=()
  
  # Register all installation steps
  cad_register_step "Storage Setup" "step_storage" 15
  cad_register_step "Mirror Selection" "step_mirror" 20  
  cad_register_step "System Bootstrap" "step_bootstrap" 35
  cad_register_step "X11 Repository" "step_x11repo" 25
  cad_register_step "APT Configuration" "step_aptni" 15
  cad_register_step "System Update" "step_systemup" 45
  cad_register_step "Network Tools" "step_nettools" 30
  cad_register_step "Core Installation" "step_coreinst" 90
  cad_register_step "APK Installation" "step_apk" 30
  cad_register_step "User Configuration" "step_usercfg" 10
  cad_register_step "Package Prefetch" "step_prefetch" 60
  cad_register_step "ADB Wireless Setup" "step_adb" 20
  cad_register_step "XFCE Desktop" "step_xfce" 75
  cad_register_step "Container Setup" "step_container" 120
  cad_register_step "Final Configuration" "step_final" 25
  
  # Calculate totals
  recompute_totals
}

# === Missing Step Implementations ===
# These step functions were not yet modularized - add minimal implementations

step_storage(){
  initialize_directories
  mark_step_status "success"
}

step_apk(){
  if [ "$ENABLE_APK_AUTO" = "1" ]; then
    select_apk_directory
    setup_apk_directory || true
  else
    info "APK installation disabled"
  fi
  mark_step_status "success"
}

step_usercfg(){
  info "Configuring user environment..."
  detect_phone
  configure_termux_properties || true
  mark_step_status "success"
}

step_prefetch(){
  info "Prefetching packages for offline use..."
  run_with_progress "Download package lists" 30 bash -c 'apt-get update >/dev/null 2>&1' || true
  run_with_progress "Download core packages" 30 bash -c 'apt-get -d install "${CORE_PACKAGES[@]}" >/dev/null 2>&1' || true
  mark_step_status "success"  
}

step_xfce(){
  info "Installing XFCE desktop environment..."
  install_x11_packages || true
  mark_step_status "success"
}

step_container(){
  info "Setting up Linux container..."
  install_container_support || true
  mark_step_status "success"
}

step_final(){
  info "Finalizing configuration..."
  configure_nano_editor || true
  set_nano_as_default || true
  mark_step_status "success"
}

initialize_directories(){
  # Create work directories
  WORK_DIR="$HOME/.cad"
  CRED_DIR="$WORK_DIR/credentials"
  STATE_DIR="$WORK_DIR/state"
  LOG_DIR="$WORK_DIR/logs"
  SNAP_DIR="$WORK_DIR/snapshots"
  EVENT_LOG="$LOG_DIR/events.json"
  STATE_JSON="$STATE_DIR/state.json"
  
  for dir in "$WORK_DIR" "$CRED_DIR" "$STATE_DIR" "$LOG_DIR" "$SNAP_DIR"; do
    if ! mkdir -p "$dir" 2>/dev/null; then
      warn "Could not create directory: $dir"
    fi
  done
  
  # Create initial log files
  touch "$EVENT_LOG" 2>/dev/null || true
  touch "$STATE_JSON" 2>/dev/null || true
}

# === Single Step Execution ===

run_single_step(){
  local identifier="$1"
  initialize_steps
  
  local step_index
  step_index=$(find_step_index "$identifier")
  
  if [ "$step_index" -ge 0 ]; then
    local step_name="${STEP_NAME[$step_index]}"
    info "Running single step: $step_name"
    
    if execute_step "$step_index"; then
      ok "Step completed successfully: $step_name"
      return 0
    else
      err "Step failed: $step_name"
      return 1
    fi
  else
    err "Step not found: $identifier"
    return 1
  fi
}

# === Help and Diagnostics ===

show_help(){
  cat << 'HELP_EOF'
CAD-Droid Mobile Development Setup - Help

USAGE:
  ./setup.sh [OPTIONS]

OPTIONS:
  --help                    Show this help message  
  --version                 Show script information
  --non-interactive         Run without asking questions
  --only-step <N|name>      Run just one specific step
  --doctor                  Check your system for problems

ENVIRONMENT VARIABLES:
  NON_INTERACTIVE=1         Answer yes to everything automatically
  AUTO_GITHUB=1             Skip GitHub SSH key setup  
  ENABLE_SUNSHINE=0         Don't install remote desktop streaming
  SKIP_ADB=1                Skip ADB wireless debugging setup
  DEBUG=1                   Show extra details about what's happening
  
HELP_EOF
}

show_final_completion(){
  draw_card "🎉 CAD-Droid Setup Complete! 🎉" "Your Android development environment is ready"
  pecho "$PASTEL_PURPLE" "Key features now available:"
  info "  • Full Linux desktop with XFCE"
  info "  • Development tools and editors" 
  info "  • Package management with APT"
  info "  • SSH access and Git integration"
  if [ "$ENABLE_ADB" = "1" ]; then
    info "  • ADB wireless debugging"
  fi
  echo ""
  pecho "$PASTEL_PURPLE" "Next steps:"
  info "  • Restart Termux to see new prompt colors"
  info "  • Use 'nano filename' to edit files"
  info "  • Check ~/.bashrc for environment settings"
}

run_diagnostics(){
  pecho "$PASTEL_PURPLE" "=== CAD-Droid System Diagnostics ==="
  
  # Check environment
  validate_termux_environment || true
  
  # Check critical tools
  local tools=("pkg" "apt-get" "git" "curl" "wget" "nano")
  for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$tool: Available"
    else
      warn "$tool: Not found"
    fi
  done
  
  # Check disk space
  check_disk_space "$HOME" 500 || true
  
  # Test network connectivity
  if probe_github; then
    ok "GitHub connectivity: Working"
  else
    warn "GitHub connectivity: Failed"
  fi
  
  # Test Termux API
  if have_termux_api; then
    ok "Termux:API: Available"  
  else
    warn "Termux:API: Not available"
  fi
}

# === Main Execution Function ===

main_execution(){
  # Early Termux:API detection for better UX fallbacks
  if have_termux_api 2>/dev/null; then
    TERMUX_API_VERIFIED="yes"
  fi
  
  # Initialize all required arrays and variables
  STEP_DURATIONS=()
  STEP_STATUS=() 
  STEP_FUNCS=()
  STEP_NAME=()
  STEP_ETA=()
  
  # Check if only running specific step
  if [ -n "${ONLY_STEP:-}" ]; then
    run_single_step "$ONLY_STEP"
    return $?
  fi
  
  # Initialize steps
  initialize_steps
  
  # Display welcome message
  draw_card "CAD-Droid Ultimate Setup v${SCRIPT_VERSION}" "Comprehensive Android Development Environment"
  
  # Execute all registered steps
  if execute_all_steps; then
    show_final_completion
    return 0
  else
    err "Installation completed with errors"
    return 1
  fi
}

# === Error Handling ===

error_handler() {
    local exit_code=$?
    local line_number=$1
    if command -v err >/dev/null 2>&1; then
        err "Script interrupted at line $line_number (exit code: $exit_code)"
    else
        echo "Error: Script interrupted at line $line_number (exit code: $exit_code)" >&2
    fi
    exit $exit_code
}

# Set up error handling
trap 'error_handler $LINENO' ERR

# === Command Line Argument Parsing ===

# Check if running in non-interactive mode
if [ "${NON_INTERACTIVE:-0}" = "1" ] || [ "$#" -gt 0 ] && [[ "$*" == *"--non-interactive"* ]]; then
  NON_INTERACTIVE=1
fi

# Parse command line arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --help) show_help; exit 0 ;;
    --version) echo "$SCRIPT_VERSION"; exit 0 ;;
    --non-interactive) NON_INTERACTIVE=1 ;;
    --only-step) shift; ONLY_STEP="$1" ;;
    --doctor) run_diagnostics; exit 0 ;;
    --self-test) echo "Self-test functionality available in utils module"; exit 0 ;;
    *) warn "Unknown option: $1" ;;
  esac
  shift
done

# === Main Execution ===

# Execute main installation flow
main_execution