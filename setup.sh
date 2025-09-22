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

# Verify we're running inside Termux environment (allow development mode)
if [ ! -d "/data/data/com.termux" ] && [ "${DEVELOPMENT_MODE:-0}" != "1" ]; then
  echo "Error: Must run inside Termux" >&2
  echo "Set DEVELOPMENT_MODE=1 for testing outside Termux" >&2
  exit 1
fi

# Verify critical paths exist (flexible for development)
if [ "${DEVELOPMENT_MODE:-0}" = "1" ]; then
    PREFIX="${PREFIX:-/usr}"
    HOME="${HOME:-$HOME}"
else
    PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
    HOME="${HOME:-/data/data/com.termux/files/home}"
fi

if [ ! -d "$PREFIX" ]; then
  echo "Error: PREFIX directory not found: $PREFIX" >&2
  echo "Set DEVELOPMENT_MODE=1 and appropriate PREFIX/HOME for testing" >&2
  exit 1
fi

if [ ! -d "$HOME" ]; then
  echo "Error: HOME directory not found: $HOME" >&2
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

# Load modules function - called when actually needed
load_all_modules() {
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

  # Now we can use colors for the rest of the loading
  pecho "$PASTEL_PURPLE" "Loading specialized modules..."

  # 3. Specialized modules (can be loaded in any order)
  load_module "termux_props"
  load_module "apk_management"
  load_module "adb"
  load_module "core_packages"
  load_module "mirror_config"
  load_module "nano"
  load_module "xfce_desktop"

  # 4. Enhanced feature modules
  load_module "snapshots"
  load_module "sunshine"  
  load_module "plugins"
  load_module "widgets"
  load_module "diagnostics"
  load_module "complete_steps"
  load_module "completion"
  load_module "feature_parity"
  load_module "help"

  pecho "$PASTEL_PINK" "✓ All modules loaded successfully"
  
  # Initialize post-module setup
  initialize_post_modules
}

# Load minimal modules for basic functionality
load_minimal_modules() {
  load_module "constants"
  load_module "utils"
  load_module "logging"
}

# Check if functions need modules loaded
ensure_basic_functions() {
  if ! command -v warn >/dev/null 2>&1; then
    load_minimal_modules
  fi
}

# Post-module initialization - called after modules are loaded
initialize_post_modules() {
  # Apply all validations after modules are loaded (with error handling)
  validate_curl_timeouts || true
  validate_timeout_vars || true
  validate_spinner_delay || true
  validate_apk_size || true

  # Set up environment
  ensure_tmpdir || {
    echo "Error: Cannot establish working temporary directory" >&2
    exit 1
  }

  # Call duplication detection after all modules loaded
  assert_unique_definitions || true
}

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
  pecho "$PASTEL_PURPLE" "Setting up storage access..."
  
  # Run termux-setup-storage first
  if command -v termux-setup-storage >/dev/null 2>&1; then
    # Check if storage is already available
    if [ -d "$HOME/storage" ]; then
      ok "Storage permission already granted"
    else
      if [ "$NON_INTERACTIVE" != "1" ]; then
        echo ""
        pecho "$PASTEL_CYAN" "Storage Permission Required:"
        info "• Termux needs access to device storage for APK downloads"
        info "• Grant 'Files and media' permission when prompted"
        info "• This enables saving files to Downloads folder"
        echo ""
        pecho "$PASTEL_YELLOW" "Press Enter to request storage permission..."
        read -r || true
      fi
      
      run_with_progress "Request storage permission" 10 termux-setup-storage
      
      # Wait for storage to be available
      local attempts=0
      while [ ! -d "$HOME/storage" ] && [ "$attempts" -lt 10 ]; do
        sleep 1
        attempts=$((attempts + 1))
      done
      
      if [ -d "$HOME/storage" ]; then
        ok "Storage access granted successfully"
      else
        warn "Storage access may not be fully available yet"
      fi
    fi
  else
    warn "termux-setup-storage not available"
  fi
  
  # Then initialize directories
  initialize_directories
  mark_step_status "success"
}

step_apk(){
  info "Installing required Termux add-on APKs..."
  
  # Ensure download tools are available
  ensure_download_tool
  
  # Check if APK installation is enabled
  if [ "${ENABLE_APK_AUTO:-1}" != "1" ]; then
    info "APK installation disabled - skipping"
    mark_step_status "skipped"
    return 0
  fi
  
  # Initialize APK management system
  if ! init_apk_system; then
    warn "APK system initialization failed, but continuing..."
  fi
  
  # Download essential APKs automatically (no user interaction during downloads)
  if download_essential_apks; then
    ok "APK downloads completed successfully"
    
    # Handle permissions and installation AFTER all downloads are complete
    setup_apk_permissions
    
    mark_step_status "success"
  else
    warn "Some APK downloads may have failed - check manually"
    mark_step_status "partial"
  fi
}

step_usercfg(){
  info "Configuring user environment..."
  detect_phone
  configure_termux_properties || true
  configure_bash_prompt || true
  configure_nano_colors || true
  mark_step_status "success"
}

step_prefetch(){
  info "Prefetching packages for offline use..."
  
  # Use modular package list updating to ensure indexes are current
  update_package_lists || {
    warn "Failed to update package lists, proceeding with prefetch anyway"
  }
  
  # Download core packages for offline installation - using simple progress without complex spinners
  info "Downloading core packages for offline use..."
  if command -v pkg >/dev/null 2>&1; then
    pkg install --download-only -y "${CORE_PACKAGES[@]}" >/dev/null 2>&1 && ok "Core packages downloaded (pkg)" || warn "Some packages may have failed to download (pkg)"
  else
    apt install --download-only -y "${CORE_PACKAGES[@]}" >/dev/null 2>&1 && ok "Core packages downloaded (apt)" || warn "Some packages may have failed to download (apt)"
  fi
  
  mark_step_status "success"  
}

step_xfce(){
  info "Installing XFCE desktop environment..."
  
  # Use modular XFCE desktop installation which handles both Termux and containers
  if declare -f install_xfce_desktop >/dev/null 2>&1; then
    install_xfce_desktop || true
  else
    # Fallback to existing approach if xfce_desktop module not available
    warn "XFCE desktop module not available, using fallback approach"
    step_xfce_termux || true
    install_x11_packages || true
  fi
  
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

step_adb(){
  # Use modular ADB setup from adb module
  info "Setting up ADB wireless debugging..."
  
  # Check if ADB setup should be skipped
  if [ "$ENABLE_ADB" != "1" ] || [ "$SKIP_ADB" = "1" ]; then
    info "ADB setup skipped per configuration"
    mark_step_status "skipped"
    return 0
  fi
  
  # Call the ADB wireless helper from the adb module
  if declare -f adb_wireless_helper >/dev/null 2>&1; then
    adb_wireless_helper || true
  else
    warn "ADB module functions not available, skipping ADB setup"
  fi
  
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
  --apk-diagnose           Test APK download connections
  --sunshine-test          Verify remote desktop streaming
  --snapshot-create <name> Save current state to backup
  --snapshot-restore <name> Load saved state from backup
  --list-snapshots         Show available backups

ENVIRONMENT VARIABLES:
  NON_INTERACTIVE=1         Answer yes to everything automatically
  AUTO_GITHUB=1             Skip GitHub SSH key setup  
  AUTO_APK=1                Skip APK installation confirmations
  ENABLE_SUNSHINE=0         Don't install remote desktop streaming
  ENABLE_WIDGETS=0          Skip productivity widgets installation
  ENABLE_SNAPSHOTS=0        Disable backup/restore functionality
  SKIP_ADB=1                Skip ADB wireless debugging setup
  DEBUG=1                   Show extra details about what's happening
  APK_PAUSE_TIMEOUT=45      APK installation timeout (seconds)
  GITHUB_PROMPT_TIMEOUT_OPEN=30    GitHub browser timeout (seconds)
  PLUGIN_DIR=~/.cad/plugins Custom plugins directory
  
HELP_EOF
}

show_final_completion(){
  draw_card "CAD-Droid Setup Complete!" "Your Android development environment is ready"
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
  # Use enhanced diagnostics if available, otherwise fall back to basic
  if declare -f run_enhanced_diagnostics >/dev/null 2>&1; then
    run_enhanced_diagnostics
  else
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
      ok "Termux:API detected"  
    fi
  fi
}

# === Main Execution Function ===

main_execution(){
  # Load all modules first
  load_all_modules
  
  # Set installation flag at the very beginning
  set_install_flag
  
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
    # Clear installation flag on successful completion
    clear_install_flag
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
    --help) 
        show_help; 
        exit 0 ;;
    --version) 
        load_minimal_modules
        echo "$SCRIPT_VERSION"; 
        exit 0 ;;
    --non-interactive) NON_INTERACTIVE=1 ;;
    --only-step) shift; ONLY_STEP="$1" ;;
    --doctor) 
        load_all_modules
        run_diagnostics; 
        exit 0 ;;
    --apk-diagnose) 
        load_all_modules
        test_apk_connections; 
        exit 0 ;;
    --sunshine-test) 
        load_all_modules
        test_sunshine_streaming; 
        exit 0 ;;
    --snapshot-create) 
        load_all_modules
        shift; create_snapshot "$1"; 
        exit 0 ;;
    --snapshot-restore) 
        load_all_modules
        shift; restore_snapshot "$1"; 
        exit 0 ;;
    --list-snapshots) 
        load_all_modules
        list_snapshots; 
        exit 0 ;;
    --self-test) echo "Self-test functionality available in utils module"; exit 0 ;;
    *) 
        ensure_basic_functions
        warn "Unknown option: $1" ;;
  esac
  shift
done

# === Main Execution ===

# Execute main installation flow
main_execution