#!/usr/bin/env bash
###############################################################################
# CAD-Droid XFCE Desktop Module
# XFCE desktop environment setup for both Termux and Ubuntu containers
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_XFCE_DESKTOP_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_XFCE_DESKTOP_LOADED=1

# XFCE Configuration
readonly XFCE_CONFIG_DIR="$HOME/.config/xfce4"
readonly XFCE_THEMES_DIR="$PREFIX/share/themes"
readonly XFCE_ICONS_DIR="$PREFIX/share/icons"

# XFCE packages for Termux
declare -a TERMUX_XFCE_PACKAGES=(
  "xfce4"
  "xfce4-terminal"
  "xfce4-whiskermenu-plugin"
  "xfce4-pulseaudio-plugin"
  "thunar"
  "ristretto"
  "mousepad"
  "xfce4-settings"
  "xfce4-session"
  "xfce4-panel"
  "xfce4-desktop"
  "xfwm4"
  "gtk3"
  "adwaita-icon-theme"
  "gnome-icon-theme"
)

# Optional XFCE enhancement packages
declare -a XFCE_OPTIONAL_PACKAGES=(
  "firefox"
  "libreoffice"
  "gimp"
  "inkscape"
  "vlc"
  "file-manager"
  "geany"
  "galculator"
)

# Install XFCE base packages for Termux
install_termux_xfce(){
  info "Installing XFCE desktop environment in Termux..."
  
  # Update repositories first
  if ! run_with_progress "Update package lists" 15 bash -c 'apt-get update >/dev/null 2>&1'; then
    warn "Package list update had issues, continuing anyway"
  fi
  
  # Install core XFCE packages
  local installed_count=0
  local failed_packages=()
  
  for package in "${TERMUX_XFCE_PACKAGES[@]}"; do
    if run_with_progress "Install $package" 30 apt_install_if_needed "$package"; then
      installed_count=$((installed_count + 1))
    else
      failed_packages+=("$package")
    fi
  done
  
  # Report installation results
  local total_packages=${#TERMUX_XFCE_PACKAGES[@]}
  if [ "$installed_count" -eq "$total_packages" ]; then
    ok "All XFCE packages installed successfully ($installed_count/$total_packages)"
  else
    warn "XFCE installation: $installed_count/$total_packages packages successful"
    if [ ${#failed_packages[@]} -gt 0 ]; then
      warn "Failed packages: ${failed_packages[*]}"
    fi
  fi
  
  return 0
}

# Create XFCE configuration with pastel theme
configure_xfce_theme(){
  info "Configuring XFCE with pastel theme..."
  
  # Create XFCE config directory
  run_with_progress "Setup XFCE config" 5 bash -c "
    mkdir -p '$XFCE_CONFIG_DIR'/{xfwm4,xfce4-panel,xfce4-desktop,xfce4-session} &&
    chmod -R 755 '$XFCE_CONFIG_DIR'
  "
  
  # Configure XFCE window manager theme
  local xfwm4_config="$XFCE_CONFIG_DIR/xfwm4/xfwm4rc"
  cat > "$xfwm4_config" << 'XFWM4_CONFIG_EOF'
[General]
theme=Default-hdpi
button_layout=O|SHMC
button_offset=0
button_spacing=0
click_to_focus=true
focus_delay=250
focus_new=true
raise_delay=250
raise_on_click=true
raise_on_focus=false
repeat_urgent_blink=false
snap_to_border=true
snap_to_windows=false
snap_width=10
title_alignment=center
title_font=Sans Bold 9
title_shadow=false
urgent_blink=false
use_compositing=true
zoom_desktop=true
XFWM4_CONFIG_EOF

  # Configure XFCE panel with pastel colors
  local panel_config="$XFCE_CONFIG_DIR/xfce4-panel/panel-1.xml"
  cat > "$panel_config" << 'PANEL_CONFIG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="28"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
      </property>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-rgba" type="array">
        <value type="double" value="0.8"/>
        <value type="double" value="0.9"/>
        <value type="double" value="1.0"/>
        <value type="double" value="0.9"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="tasklist"/>
    <property name="plugin-3" type="string" value="separator"/>
    <property name="plugin-4" type="string" value="systray"/>
    <property name="plugin-5" type="string" value="clock"/>
  </property>
</channel>
PANEL_CONFIG_EOF

  # Configure XFCE desktop with pastel wallpaper
  local desktop_config="$XFCE_CONFIG_DIR/xfce4-desktop/desktop.xml"
  cat > "$desktop_config" << 'DESKTOP_CONFIG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="2"/>
          <property name="color1" type="array">
            <value type="double" value="0.8"/>
            <value type="double" value="0.9"/>
            <value type="double" value="1.0"/>
            <value type="double" value="1.0"/>
          </property>
          <property name="color2" type="array">
            <value type="double" value="1.0"/>
            <value type="double" value="0.8"/>
            <value type="double" value="0.9"/>
            <value type="double" value="1.0"/>
          </property>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
DESKTOP_CONFIG_EOF

  # Configure XFCE terminal with pastel colors
  local terminal_config="$HOME/.config/xfce4/terminal/terminalrc"
  mkdir -p "$(dirname "$terminal_config")" 2>/dev/null
  cat > "$terminal_config" << 'TERMINAL_CONFIG_EOF'
[Configuration]
BackgroundMode=TERMINAL_BACKGROUND_TRANSPARENT
BackgroundDarkness=0.900000
ColorForeground=#DCC9FF
ColorBackground=#0d1117
ColorCursor=#FFC9D9
ColorPalette=#484f58;#FFC9D9;#C9FFD1;#FFDFA8;#C9E0FF;#DCC9FF;#9DF2F2;#b1bac4;#6e7681;#FFC9D9;#C9FFD1;#FFDFA8;#C9E0FF;#DCC9FF;#9DF2F2;#ffffff
FontName=Monospace 10
ScrollingBar=TERMINAL_SCROLLBAR_RIGHT
TERMINAL_CONFIG_EOF

  ok "XFCE theme configured with pastel colors"
}

# Install XFCE optional packages
install_xfce_applications(){
  info "Installing XFCE applications..."
  
  local installed_count=0
  local skipped_count=0
  
  for package in "${XFCE_OPTIONAL_PACKAGES[@]}"; do
    if apt_install_with_spinner "$package"; then
      installed_count=$((installed_count + 1))
    else
      skipped_count=$((skipped_count + 1))
    fi
  done
  
  ok "XFCE applications: $installed_count installed, $skipped_count skipped"
}

# Create XFCE startup scripts
create_xfce_scripts(){
  info "Creating XFCE startup scripts..."
  
  local scripts_dir="$HOME/.cad/scripts"
  run_with_progress "Setup script directory" 3 bash -c "
    mkdir -p '$scripts_dir' &&
    chmod 755 '$scripts_dir'
  "
  
  # Create XFCE startup script for Termux
  local xfce_termux_script="$scripts_dir/start-xfce-termux.sh"
  cat > "$xfce_termux_script" << 'XFCE_TERMUX_SCRIPT_EOF'
#!/usr/bin/env bash
# Start XFCE desktop environment in Termux

# Set up display
export DISPLAY=:1
export PULSE_SERVER=tcp:127.0.0.1:4713

# Kill any existing X11 processes
pkill -f com.termux.x11 2>/dev/null || true
pkill -f Xvfb 2>/dev/null || true
sleep 2

# Start Termux:X11 if available
if command -v termux-x11 >/dev/null 2>&1; then
  echo "Starting Termux:X11 server..."
  termux-x11 :1 -ac -extension MIT-SHM &
  sleep 3
else
  echo "Warning: Termux:X11 not found, using Xvfb"
  Xvfb :1 -screen 0 1920x1080x24 &
  sleep 2
fi

# Start PulseAudio if available
if command -v pulseaudio >/dev/null 2>&1; then
  echo "Starting PulseAudio server..."
  pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 2>/dev/null &
fi

# Start XFCE desktop
echo "Starting XFCE desktop environment..."
export XDG_RUNTIME_DIR="$TMPDIR"
export XDG_CONFIG_HOME="$HOME/.config"

# Start XFCE session
startxfce4 &

# Launch Termux:X11 app if available
if command -v am >/dev/null 2>&1; then
  sleep 5
  echo "Launching Termux:X11 app..."
  am start -n com.termux.x11/.MainActivity 2>/dev/null || true
fi

echo "XFCE desktop started on display :1"
echo "Use 'pkill -f xfce' to stop the desktop"
XFCE_TERMUX_SCRIPT_EOF

  chmod +x "$xfce_termux_script"
  
  # Create XFCE startup script for container
  local xfce_container_script="$scripts_dir/start-xfce-container.sh"
  cat > "$xfce_container_script" << 'XFCE_CONTAINER_SCRIPT_EOF'
#!/usr/bin/env bash
# Start XFCE desktop environment in Ubuntu container via SSH

# Configuration
CONTAINER_IP="127.0.0.1"
SSH_PORT="2222"
SSH_KEY="$HOME/.ssh/id_ed25519"

# Check if container is running
if ! nc -z "$CONTAINER_IP" "$SSH_PORT" 2>/dev/null; then
  echo "Error: Ubuntu container not accessible on $CONTAINER_IP:$SSH_PORT"
  echo "Please start the container first"
  exit 1
fi

# Set up X11 forwarding
export DISPLAY=:1

# Connect to container and start XFCE
echo "Connecting to Ubuntu container..."
ssh -i "$SSH_KEY" -X -p "$SSH_PORT" \
    -o ConnectTimeout=10 \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    caduser@"$CONTAINER_IP" \
    'export DISPLAY=:1; startxfce4' &

echo "XFCE desktop started in container"
XFCE_CONTAINER_SCRIPT_EOF

  chmod +x "$xfce_container_script"
  
  ok "XFCE startup scripts created"
}

# Main XFCE installation function
install_xfce_desktop(){
  info "Installing XFCE desktop environment..."
  
  # Install XFCE packages
  if ! install_termux_xfce; then
    err "Failed to install XFCE packages"
    return 1
  fi
  
  # Configure XFCE theme
  configure_xfce_theme
  
  # Install optional applications
  install_xfce_applications
  
  # Create startup scripts
  create_xfce_scripts
  
  # Verify installation
  if command -v startxfce4 >/dev/null 2>&1; then
    ok "XFCE desktop environment installed successfully"
    
    # Show usage instructions
    printf "\n${PASTEL_PINK}XFCE Desktop Usage:${RESET}\n"
    printf "${PASTEL_CYAN}Start in Termux:${RESET} ~/.cad/scripts/start-xfce-termux.sh\n"
    printf "${PASTEL_CYAN}Start in Container:${RESET} ~/.cad/scripts/start-xfce-container.sh\n"
    printf "${PASTEL_CYAN}Stop Desktop:${RESET} pkill -f xfce\n\n"
    
    return 0
  else
    err "XFCE installation verification failed"
    return 1
  fi
}

# Export functions for use by other modules
export -f install_termux_xfce
export -f configure_xfce_theme
export -f install_xfce_applications
export -f create_xfce_scripts
export -f install_xfce_desktop
