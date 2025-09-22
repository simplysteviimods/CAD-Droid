#!/usr/bin/env bash
###############################################################################
# CAD-Droid ADB Module
# Android Debug Bridge wireless setup, device detection, and debugging tools
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_ADB_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_ADB_LOADED=1

# === ADB Installation and Setup ===

# Install ADB tools if not present
install_adb_tools(){
  if command -v adb >/dev/null 2>&1; then
    debug "ADB already installed"
    return 0
  fi
  
  info "Installing Android Debug Bridge (ADB)..."
  
  # Try different package names depending on distribution
  local packages=("android-tools" "adb")
  local installed=false
  
  for pkg in "${packages[@]}"; do
    # Ensure selected mirror is applied before installing ADB packages
    if command -v ensure_mirror_applied >/dev/null 2>&1; then
      ensure_mirror_applied
    fi
    
    # Use appropriate package manager for installation
    if command -v pkg >/dev/null 2>&1; then
      if run_with_progress "Install $pkg (pkg)" 15 bash -c "
        pkg update -y >/dev/null 2>&1 && 
        pkg install -y $pkg >/dev/null 2>&1
      "; then
        if command -v adb >/dev/null 2>&1; then
          installed=true
          ok "ADB installed successfully via pkg ($pkg)"
          break
        fi
      fi
    fi
    
    # Fallback to apt
    if [ "$installed" = false ]; then
      if run_with_progress "Install $pkg (apt)" 15 bash -c "
        apt update >/dev/null 2>&1 && 
        apt install -y $pkg >/dev/null 2>&1
      "; then
        if command -v adb >/dev/null 2>&1; then
          installed=true
          ok "ADB installed successfully via apt ($pkg)"
          break
        fi
      fi
    fi
  done
  
  if [ "$installed" = false ]; then
    warn "Failed to install ADB tools"
    return 1
  fi
  
  return 0
}

# === Network Detection ===

# Detect device IP address for ADB connection
detect_device_ip(){
  local ip=""
  
  # Try to get Wi-Fi interface IP
  if command -v ip >/dev/null 2>&1; then
    # Try common Wi-Fi interface names
    for iface in wlan0 wlan wlp wlo; do
      ip=$(ip -o -4 addr show "$iface" 2>/dev/null | awk '{print $4}' | head -1 | cut -d'/' -f1)
      if [ -n "$ip" ] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
      fi
    done
  fi
  
  # Fallback to ifconfig if available
  if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
    ip=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
  fi
  
  # Return empty if no IP found
  if [ -z "$ip" ]; then
    ip=""
  fi
  
  echo "$ip"
}

# Scan for open ports on device
scan_device_ports(){
  local ip="$1"
  local start_port="${2:-37000}"
  local end_port="${3:-44999}"
  
  local open_ports=()
  
  # Use nmap if available (most accurate)
  if command -v nmap >/dev/null 2>&1; then
    info "Scanning for ADB ports using nmap..."
    local nmap_result
    nmap_result=$(nmap -p "$start_port-$end_port" "$ip" 2>/dev/null | grep "^[0-9]*/tcp.*open" | awk '{print $1}' | cut -d'/' -f1)
    while IFS= read -r port; do
      if [ -n "$port" ]; then
        open_ports+=("$port")
      fi
    done <<< "$nmap_result"
  # Use ss if available (faster than netstat)
  elif command -v ss >/dev/null 2>&1; then
    info "Scanning for ADB ports using ss..."
    local i="$start_port"
    while [ "$i" -le "$end_port" ]; do
      if ss -ltn 2>/dev/null | grep -q ":$i "; then
        open_ports+=("$i")
      fi
      i=$((i + 1))
      
      # Progress indicator for long scans
      if [ $((i % 1000)) -eq 0 ]; then
        debug "Scanned up to port $i..."
      fi
    done
  # Fallback to basic port testing
  else
    info "Scanning for ADB ports using basic connectivity test..."
    local i="$start_port"
    while [ "$i" -le "$end_port" ] && [ "$i" -lt $((start_port + 1000)) ]; do
      if timeout 1 bash -c "echo >/dev/tcp/$ip/$i" 2>/dev/null; then
        open_ports+=("$i")
      fi
      i=$((i + 1))
    done
  fi
  
  # Return found ports
  printf '%s\n' "${open_ports[@]}"
}

# === ADB Pairing and Connection ===

# Start ADB server and ensure it's running
start_adb_server(){
  if ! command -v adb >/dev/null 2>&1; then
    err "ADB not installed"
    return 1
  fi
  
  info "Starting ADB server..."
  adb start-server >/dev/null 2>&1 || true
  
  # Wait a moment for server to start
  safe_sleep 2
  
  # Check if server is running
  if ! adb devices >/dev/null 2>&1; then
    warn "ADB server may not be running properly"
    return 1
  fi
  
  return 0
}

# Pair ADB device with pairing code
pair_adb_device(){
  local ip="$1"
  local port="$2"
  local pairing_code="$3"
  
  if [ -z "$ip" ] || [ -z "$port" ] || [ -z "$pairing_code" ]; then
    err "Missing parameters for ADB pairing"
    return 1
  fi
  
  info "Attempting to pair with $ip:$port using code: $pairing_code"
  
  # Attempt pairing with timeout
  local pair_result
  if pair_result=$(timeout 30 adb pair "$ip:$port" 2>&1 <<< "$pairing_code"); then
    if echo "$pair_result" | grep -qi "successfully paired"; then
      ok "ADB pairing successful!"
      return 0
    else
      warn "ADB pairing may have failed: $pair_result"
      return 1
    fi
  else
    err "ADB pairing timed out or failed"
    return 1
  fi
}

# Connect to ADB device
connect_adb_device(){
  local ip="$1"
  local port="$2"
  
  if [ -z "$ip" ] || [ -z "$port" ]; then
    err "Missing parameters for ADB connection"
    return 1
  fi
  
  info "Connecting to ADB device at $ip:$port"
  
  # Attempt connection
  if adb connect "$ip:$port" >/dev/null 2>&1; then
    # Verify connection
    if adb devices 2>/dev/null | grep -q "$ip:$port"; then
      ok "ADB connection established!"
      return 0
    else
      warn "ADB connection failed to verify"
      return 1
    fi
  else
    err "ADB connection failed"
    return 1
  fi
}

# === Android Settings Integration ===

# Open Android developer settings with user guidance
open_developer_settings(){
  local settings_opened=false
  
  info "Opening Android Developer Settings..."
  
  # Method 1: Direct intent to developer settings
  if command -v am >/dev/null 2>&1; then
    if am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS >/dev/null 2>&1; then
      settings_opened=true
      ok "Developer Settings opened"
    fi
  fi
  
  # Method 2: General settings as fallback
  if [ "$settings_opened" = false ] && command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.MAIN -n com.android.settings/.Settings >/dev/null 2>&1; then
      settings_opened=true
      info "Settings opened - navigate to Developer Options"
    fi
  fi
  
  # Method 3: Try Termux API if available
  if [ "$settings_opened" = false ] && command -v termux-open >/dev/null 2>&1; then
    if termux-open --send "android.settings.APPLICATION_DEVELOPMENT_SETTINGS" >/dev/null 2>&1; then
      settings_opened=true
      ok "Developer Settings opened via Termux API"
    fi
  fi
  
  if [ "$settings_opened" = false ]; then
    warn "Unable to open settings automatically"
    info "Please manually navigate to: Settings > System > Developer Options"
    return 1
  fi
  
  return 0
}

# === ADB Wireless Setup Workflow ===

# Complete ADB wireless setup process with simplified manual approach
adb_wireless_helper(){
  if [ "$ENABLE_ADB" != "1" ]; then
    return 0
  fi
  
  # No duplicate dialog - all instructions are now in step_adb
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    pecho "$PASTEL_CYAN" "After enabling wireless debugging, press Enter to continue..."
    read -r || true
  fi
  
  # Get pairing details from user
  local ip pairing_port pairing_code
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    read_nonempty "Enter the IP address shown (e.g., 192.168.1.100)" ip "192.168.1.100"
    read_nonempty "Enter the pairing port (e.g., 37831)" pairing_port "37831"  
    read_nonempty "Enter the 6-digit pairing code" pairing_code "123456"
    
    # Basic validation
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      warn "Invalid IP address format"
      return 1
    fi
    
    if ! [[ "$pairing_port" =~ ^[0-9]+$ ]] || [ "$pairing_port" -lt 1 ] || [ "$pairing_port" -gt 65535 ]; then
      warn "Invalid port number"
      return 1
    fi
    
    if ! [[ "$pairing_code" =~ ^[0-9]{6}$ ]]; then
      warn "Pairing code should be exactly 6 digits"
      return 1  
    fi
    
    # Attempt pairing
    info "Attempting to pair with $ip:$pairing_port..."
    if pair_adb_device "$ip" "$pairing_port" "$pairing_code"; then
      ok "Device paired successfully!"
      
      # Prompt for debugging port
      echo ""
      local debug_port
      read_nonempty "Enter the wireless debugging port (usually different from pairing port)" debug_port "37832"
      
      if connect_adb_device "$ip" "$debug_port"; then
        ok "ADB wireless debugging setup complete!"
        info "Device connected at: $ip:$debug_port"
        return 0
      else
        warn "Failed to connect to debugging port"
      fi
    else
      err "Device pairing failed. Please check the code and try again."
    fi
  else
    info "Non-interactive mode: manual ADB setup required"
    info "Run: adb pair <ip:port> then adb connect <ip:debug_port>"
  fi
  
  return 1
}

# === ADB Step Function ===

# Main ADB setup step
step_adb(){
  # Check if ADB is completely disabled or skipped
  if [ "$ENABLE_ADB" != "1" ] || [ "$SKIP_ADB" = "1" ]; then
    if [ "$SKIP_ADB" = "1" ]; then
      info "ADB wireless setup skipped by user request"
    else
      info "ADB wireless setup disabled"
    fi
    mark_step_status "skipped"
    return 0
  fi
  
  # Single comprehensive prompt with all instructions BEFORE opening settings
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    draw_card "Android Debug Bridge (ADB) Wireless Setup" "CRITICAL - Essential for Linux development stability"
    echo ""
    
    pecho "$PASTEL_YELLOW" "ADB wireless debugging is ESSENTIAL for Linux development on Android!"
    echo ""
    pecho "$PASTEL_CYAN" "Why ADB is critical:"
    info "• Disables Android's Phantom Process Killer that terminates Linux processes"
    info "• Prevents random termination of development tools, servers, and long-running tasks"
    info "• Ensures stable operation of container environments and desktop sessions"
    info "• Required for professional development work on Android devices"
    echo ""
    pecho "$PASTEL_PINK" "Without ADB, Android will randomly kill your Linux processes!"
    echo ""
    
    pecho "$PASTEL_PURPLE" "What you need to do:"
    echo ""
    pecho "$PASTEL_PINK" "1. Split your screen between Settings and Termux"
    pecho "$PASTEL_PINK" "2. In Settings > System > Developer Options"
    pecho "$PASTEL_PINK" "3. Enable 'Wireless debugging'"  
    pecho "$PASTEL_PINK" "4. Tap 'Pair device with pairing code'"
    pecho "$PASTEL_PINK" "5. Note the IP address, port, and 6-digit code shown"
    pecho "$PASTEL_PINK" "6. Return to Termux to enter the pairing information"
    echo ""
    
    if ! ask_yes_no "Ready to open Developer Settings and start ADB setup?" "y"; then
      info "Skipping ADB wireless setup"
      mark_step_status "skipped"
      return 0
    fi
  fi
  
  info "Starting ADB wireless setup process..."
  
  # Install ADB if not present
  if ! install_adb_tools; then
    warn "Failed to install ADB tools"
    mark_step_status "warning"
    return 0
  fi
  
  # Start ADB server
  if ! start_adb_server; then
    warn "Failed to start ADB server"
    mark_step_status "warning"
    return 0
  fi
  
  # Open developer settings once and run the helper (no duplicate prompts)
  if ! open_developer_settings; then
    info "Please manually navigate to Developer Options and enable Wireless debugging"
  fi
  
  # Run the actual ADB helper with enhanced detection
  if adb_wireless_helper; then
    mark_step_status "success"
  else
    mark_step_status "warning"
  fi
}

# === ADB Utility Functions ===

# Test ADB connection
test_adb_connection(){
  if ! command -v adb >/dev/null 2>&1; then
    err "ADB not installed"
    return 1
  fi
  
  local devices
  devices=$(adb devices 2>/dev/null | grep -c "device$" || echo "0")
  
  if [ "$devices" -gt 0 ]; then
    ok "ADB: $devices device(s) connected"
    
    # Show device information
    adb devices -l 2>/dev/null | grep "device$" | while read -r line; do
      local device_id
      device_id=$(echo "$line" | awk '{print $1}')
      info "  Device: $device_id"
    done
    
    return 0
  else
    warn "ADB: No devices connected"
    return 1
  fi
}

# Disconnect all ADB devices
disconnect_adb(){
  if command -v adb >/dev/null 2>&1; then
    info "Disconnecting ADB devices..."
    adb disconnect >/dev/null 2>&1 || true
    adb kill-server >/dev/null 2>&1 || true
    ok "ADB disconnected"
  fi
}

# === Critical System Configuration ===

# Disable phantom process killer (CRITICAL for app stability)
disable_phantom_process_killer(){
  printf "\n${PASTEL_RED}CRITICAL SYSTEM CONFIGURATION${RESET}\n"
  printf "${PASTEL_YELLOW}═══════════════════════════════════════${RESET}\n\n"
  
  printf "${PASTEL_CYAN}What is the Phantom Process Killer?${RESET}\n"
  printf "Android's phantom process killer terminates background processes\n"
  printf "to save battery, but this breaks many useful apps and services.\n\n"
  
  printf "${PASTEL_RED}Why disable it?${RESET}\n"
  printf "${PASTEL_CYAN}├─${RESET} Prevents apps from being randomly terminated\n"
  printf "${PASTEL_CYAN}├─${RESET} Allows background services to run reliably\n"
  printf "${PASTEL_CYAN}├─${RESET} Enables better multitasking and automation\n"
  printf "${PASTEL_CYAN}└─${RESET} Essential for development and power user workflows\n\n"
  
  # Test ADB connection first
  if ! test_adb_connection >/dev/null 2>&1; then
    printf "${PASTEL_RED}WARNING: ADB not connected!${RESET}\n"
    printf "Please complete ADB wireless setup first.\n\n"
    return 1
  fi
  
  printf "${PASTEL_GREEN}✓${RESET} ADB connection verified\n"
  printf "${PASTEL_YELLOW}Disabling phantom process killer...${RESET}\n"
  
  # Execute the critical command
  if adb shell "settings put global settings_enable_monitor_phantom_procs false" 2>/dev/null; then
    printf "${PASTEL_GREEN}SUCCESS!${RESET} Phantom process killer disabled\n"
    printf "${PASTEL_CYAN}Your apps will now run more reliably in the background.${RESET}\n\n"
    
    # Verify the setting
    local current_setting
    current_setting=$(adb shell "settings get global settings_enable_monitor_phantom_procs" 2>/dev/null | tr -d '\r\n')
    if [ "$current_setting" = "false" ] || [ "$current_setting" = "null" ]; then
  printf "${PASTEL_GREEN}Setting verified: phantom process killer is OFF\n"
      return 0
    else
      printf "${PASTEL_YELLOW}WARNING:${RESET} Setting verification: current value is '$current_setting'\n"
      return 0
    fi
  else
    printf "${PASTEL_RED}FAILED${RESET} to disable phantom process killer\n"
    printf "This may be due to insufficient ADB permissions.\n"
    printf "Try: Settings → Developer Options → Disable 'Remove background activities'\n\n"
    return 1
  fi
}

# Enhanced ADB setup with phantom process killer emphasis
setup_adb_with_phantom_killer(){
  printf "\n${PASTEL_PINK}═══ ADB SETUP - CRITICAL FOR SYSTEM STABILITY ═══${RESET}\n\n"
  
  printf "${PASTEL_RED}IMPORTANT:${RESET} ${PASTEL_YELLOW}ADB setup is essential for disabling the phantom process killer!${RESET}\n"
  printf "Without this step, your apps may be randomly terminated by Android.\n\n"
  
  # Run normal ADB setup
  if ! setup_adb_wireless; then
    printf "${PASTEL_RED}WARNING: ADB setup failed or incomplete${RESET}\n"
    printf "You can retry this later, but phantom process killer will remain active.\n"
    return 1
  fi
  
  # Now disable phantom process killer
  printf "\n${PASTEL_YELLOW}Now for the critical step...${RESET}\n"
  sleep 2
  
  disable_phantom_process_killer
}

# === Termux:Boot Integration ===

# Set up automatic phantom process killer disable via Termux:Boot
setup_termux_boot_phantom_killer(){
  info "Setting up automatic phantom process killer disable via Termux:Boot..."
  
  # Create boot directory
  local boot_dir="$HOME/.termux/boot"
  mkdir -p "$boot_dir" 2>/dev/null || true
  
  # Create boot script for phantom process killer
  local boot_script="$boot_dir/disable-phantom-killer.sh"
  cat > "$boot_script" << 'BOOT_SCRIPT_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot script to disable phantom process killer on device boot
# This ensures the phantom process killer is always disabled

# Wait a bit for system to be ready
sleep 30

# Check if ADB is available
if command -v adb >/dev/null 2>&1; then
    # Try to disable phantom process killer
    if adb shell "settings put global settings_enable_monitor_phantom_procs false" 2>/dev/null; then
        echo "$(date): Phantom process killer disabled via boot script" >> ~/.termux/boot/phantom-killer.log
    else
        echo "$(date): Failed to disable phantom process killer - ADB not ready" >> ~/.termux/boot/phantom-killer.log
    fi
else
    echo "$(date): ADB not available for phantom process killer disable" >> ~/.termux/boot/phantom-killer.log
fi
BOOT_SCRIPT_EOF

  chmod +x "$boot_script"
  ok "Termux:Boot phantom process killer disable script created"
  
  # Also add fallback to widget shortcuts
  add_phantom_killer_fallback_to_widgets
}

# Add phantom process killer fallback to existing widget shortcuts
add_phantom_killer_fallback_to_widgets(){
  info "Adding phantom process killer fallback to widget shortcuts..."
  
  local widget_shortcuts="$HOME/.shortcuts"
  
  # Update all existing widgets to include phantom killer disable as fallback
  for widget in "$widget_shortcuts"/*; do
    if [ -f "$widget" ] && [ "$(basename "$widget")" != "phantom-killer" ]; then
      # Add phantom killer disable to the beginning of each widget
      local temp_file=$(mktemp)
      {
        echo "#!/data/data/com.termux/files/usr/bin/bash"
        echo "# Auto-disable phantom process killer when using widgets"
        echo "if command -v adb >/dev/null 2>&1 && adb devices 2>/dev/null | grep -q device; then"
        echo "  adb shell 'settings put global settings_enable_monitor_phantom_procs false' 2>/dev/null || true"
        echo "fi"
        echo ""
        tail -n +2 "$widget"  # Skip the first shebang line
      } > "$temp_file"
      
      mv "$temp_file" "$widget"
      chmod +x "$widget"
    fi
  done
  
  ok "Phantom process killer fallback added to all widgets"
}