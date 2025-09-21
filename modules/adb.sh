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
  local packages=("android-tools-adb" "android-tools" "adb")
  local installed=false
  
  for pkg in "${packages[@]}"; do
    if run_with_progress "Install $pkg" 15 bash -c "
      apt-get update >/dev/null 2>&1 && 
      apt-get -y install $pkg >/dev/null 2>&1
    "; then
      if command -v adb >/dev/null 2>&1; then
        installed=true
        ok "ADB installed successfully via $pkg"
        break
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
  
  # Last resort - use localhost (for USB debugging)
  if [ -z "$ip" ]; then
    ip="127.0.0.1"
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

# Open Android developer settings
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

# Complete ADB wireless setup process
adb_wireless_helper(){
  if [ "$ENABLE_ADB" != "1" ]; then
    return 0
  fi
  
  info "ADB Wireless Setup with Smart Port Detection"
  
  # Check if we have the required tools
  if [ "$NMAP_READY" != "1" ] && ! command -v ss >/dev/null 2>&1; then
    warn "Neither nmap nor ss available for port scanning"
    return 1
  fi
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    info "This will monitor for new wireless debugging ports."
    info "Please enable 'Wireless debugging' in Android Developer Options."
    pecho "$PASTEL_CYAN" "Press Enter when ready to start monitoring..."
    read -r || true
  fi
  
  # Detect device IP
  local ip
  ip=$(detect_device_ip)
  
  if [ -z "$ip" ] || [ "$ip" = "127.0.0.1" ]; then
    warn "Could not detect Wi-Fi IP address, using localhost"
    ip="127.0.0.1"
  else
    info "Detected device IP: $ip"
  fi
  
  # Get baseline of open ports
  info "Scanning for existing ADB ports (baseline)..."
  local baseline_ports
  baseline_ports=$(scan_device_ports "$ip" 37000 44999)
  
  info "Found ${#baseline_ports[@]} existing ADB ports"
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    info "Now please:"
    info "1. In Android Settings > Developer Options"
    info "2. Tap 'Pair device with pairing code'"
    info "3. Note the pairing code and port shown"
    echo ""
    pecho "$PASTEL_CYAN" "Press Enter when you see the pairing dialog..."
    read -r || true
  fi
  
  # Scan for new ports (pairing port should appear)
  info "Scanning for new pairing port..."
  local new_ports current_ports
  local attempts=0 max_attempts=10
  
  while [ "$attempts" -lt "$max_attempts" ]; do
    current_ports=$(scan_device_ports "$ip" 37000 44999)
    new_ports=$(comm -13 <(printf '%s\n' $baseline_ports | sort) <(printf '%s\n' $current_ports | sort))
    
    if [ -n "$new_ports" ]; then
      info "Found new port(s): $new_ports"
      break
    fi
    
    info "No new ports detected (attempt $((attempts + 1))/$max_attempts)..."
    safe_sleep 3
    attempts=$((attempts + 1))
  done
  
  if [ -z "$new_ports" ]; then
    warn "Could not detect new pairing port"
    info "Please ensure 'Wireless debugging' is enabled and try again"
    return 1
  fi
  
  # Use the first new port for pairing
  local pairing_port
  pairing_port=$(echo "$new_ports" | head -1)
  
  if [ "$NON_INTERACTIVE" != "1" ]; then
    info "Detected pairing port: $pairing_port"
    echo ""
    local pairing_code
    read_nonempty "Enter the 6-digit pairing code shown on your device" pairing_code
    
    # Attempt pairing
    if pair_adb_device "$ip" "$pairing_port" "$pairing_code"; then
      ok "Device paired successfully!"
      
      # Now look for the debugging port
      info "Looking for wireless debugging port..."
      safe_sleep 2
      
      # Scan again for the persistent debugging port
      local final_ports debug_port
      final_ports=$(scan_device_ports "$ip" 37000 44999)
      
      # The debugging port is usually different from the pairing port
      for port in $final_ports; do
        if [ "$port" != "$pairing_port" ]; then
          debug_port="$port"
          break
        fi
      done
      
      if [ -n "$debug_port" ]; then
        info "Found debugging port: $debug_port"
        if connect_adb_device "$ip" "$debug_port"; then
          ok "ADB wireless debugging setup complete!"
          info "You can now use ADB commands wirelessly"
          info "Device address: $ip:$debug_port"
          return 0
        fi
      else
        warn "Could not find persistent debugging port"
      fi
    else
      err "Device pairing failed"
    fi
  else
    info "Non-interactive mode: skipping pairing step"
    info "Manual pairing required with port: $pairing_port"
  fi
  
  info "Please ensure 'Wireless debugging' is enabled and try again"
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
  
  # Single comprehensive prompt with all instructions
  if [ "$NON_INTERACTIVE" != "1" ]; then
    echo ""
    draw_card "Android Debug Bridge (ADB) Wireless Setup" "Optional - Enable wireless debugging for development"
    echo ""
    
    info "What is ADB Wireless Debugging?"
    format_body_text "ADB allows you to connect wirelessly to your device for development and debugging. This is useful for advanced development workflows, file transfers, and device management, but is optional for basic usage."
    echo ""
    
    info "Complete Setup Process:"
    echo ""
    pecho "$PASTEL_YELLOW" "1. Enable Developer Options:"
    info "   • Go to Settings > About phone"
    info "   • Tap 'Build number' 7 times rapidly"
    info "   • Developer options will be enabled"
    echo ""
    pecho "$PASTEL_YELLOW" "2. Enable Wireless Debugging:"
    info "   • Go to Settings > System > Developer Options"
    info "   • Turn ON 'Wireless debugging'"
    info "   • Tap 'Pair device with pairing code'"
    info "   • Note the IP address and port number shown"
    echo ""
    pecho "$PASTEL_YELLOW" "3. Setup will then:"
    info "   • Open Android Settings for you"
    info "   • Monitor for the new debugging port"
    info "   • Show a dialog to enter the pairing code"
    info "   • Automatically pair your device"
    echo ""
    
    if ! ask_yes_no "Set up ADB wireless debugging with these steps?" "y"; then
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
  
  # Open developer settings
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