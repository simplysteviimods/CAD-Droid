#!/usr/bin/env bash
###############################################################################
# CAD-Droid Complete Steps Module
# Full implementations for container, XFCE, prefetch, and final configuration
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_COMPLETE_STEPS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_COMPLETE_STEPS_LOADED=1

# Dependencies: constants, utils, logging, core_packages, sunshine, snapshots, widgets
if [ -z "${_CAD_CONSTANTS_LOADED:-}" ] || [ -z "${_CAD_UTILS_LOADED:-}" ] || [ -z "${_CAD_LOGGING_LOADED:-}" ]; then
    echo "Error: complete_steps.sh requires constants.sh, utils.sh, and logging.sh to be loaded first" >&2
    exit 1
fi

# === Container Setup Implementation ===

step_container(){
    pecho "$PASTEL_PURPLE" "Setting up Linux container environment..."
    
    # Ensure proot-distro is available
    if ! dpkg_is_installed "proot-distro"; then
        info "Installing proot-distro for container support..."
        apt_install_if_needed "proot-distro"
    fi
    
    # Distribution selection
    info "Select Linux distribution:"
    local names=("Ubuntu" "Debian" "Arch Linux" "Alpine") i
    
    # Display distribution options with colors
    local __names_len=${#names[@]}
    __names_len=${__names_len:-0}
    local __i=0
    while [ "$__i" -lt "$__names_len" ]; do
        local seq
        seq=$(color_for_index "$__i")
        local display_num
        display_num=$(add_int "$__i" 1)
        printf "%b[%d] %s%b\\n" "$seq" "$display_num" "${names[$__i]}" '\\033[0m'
        __i=$(add_int "$__i" 1) || break
    done
    
    # Get user selection
    local sel
    if [ "$NON_INTERACTIVE" = "1" ]; then
        sel="1"  # Default to Ubuntu
    else
        read_option "Select distribution (1-${#names[@]})" sel 1 ${#names[@]} 1
    fi
    
    # Map selection to distribution name
    local distro_name
    case "$sel" in
        1) distro_name="ubuntu"; DISTRO="ubuntu" ;;
        2) distro_name="debian"; DISTRO="debian" ;;
        3) distro_name="archlinux"; DISTRO="archlinux" ;;
        4) distro_name="alpine"; DISTRO="alpine" ;;
        *) distro_name="ubuntu"; DISTRO="ubuntu" ;;
    esac
    
    info "Selected distribution: $distro_name"
    
    # Install distribution if not already installed
    if ! is_distro_installed "$distro_name"; then
        run_with_progress "Install $distro_name container" 120 \
            proot-distro install "$distro_name"
    else
        ok "$distro_name container already installed"
    fi
    
    # Configure container
    configure_container "$distro_name"
    
    # Install Sunshine if enabled
    if [ "$ENABLE_SUNSHINE" = "1" ] && [ -n "${_CAD_SUNSHINE_LOADED:-}" ]; then
        install_sunshine
        configure_sunshine
    fi
    
    ok "Container setup complete"
    return 0
}

# Configure Linux container
configure_container(){
    local container_name="${1:-ubuntu}"
    
    info "Configuring $container_name container..."
    
    # Create container setup script
    local setup_script="/tmp/container_setup.sh"
    cat > "$setup_script" << CONTAINER_SETUP_EOF
#!/bin/bash
set -e

echo "Configuring $container_name container..."

# Update package lists
apt update

# Install essential packages
apt install -y \\
    sudo \\
    curl \\
    wget \\
    git \\
    nano \\
    vim \\
    htop \\
    neofetch \\
    build-essential \\
    python3 \\
    python3-pip \\
    nodejs \\
    npm

# Create user account
NEW_USER="\${USER:-developer}"
if ! id "\$NEW_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "\$NEW_USER"
    echo "\$NEW_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    echo "Created user: \$NEW_USER"
fi

# Set up development environment
sudo -u "\$NEW_USER" bash << 'USER_SETUP_EOF'
cd ~

# Create development directories
mkdir -p ~/Projects ~/Scripts ~/Downloads

# Set up git (if configured in host)
if [ -n "\${GIT_USERNAME:-}" ] && [ -n "\${GIT_EMAIL:-}" ]; then
    git config --global user.name "\$GIT_USERNAME"
    git config --global user.email "\$GIT_EMAIL"
fi

# Create sample project
if [ ! -d ~/Projects/hello-world ]; then
    mkdir -p ~/Projects/hello-world
    cat > ~/Projects/hello-world/hello.py << 'PYTHON_EOF'
#!/usr/bin/env python3
print("Hello from the CAD-Droid container!")
import sys
print(f"Python version: {sys.version}")
PYTHON_EOF
    chmod +x ~/Projects/hello-world/hello.py
fi

echo "User environment configured"
USER_SETUP_EOF

echo "Container configuration complete!"
CONTAINER_SETUP_EOF
    
    chmod +x "$setup_script"
    
    # Run setup in container
    run_with_progress "Configure container environment" 60 \
        proot-distro login "$container_name" -- bash < "$setup_script"
    
    # Clean up
    rm -f "$setup_script" 2>/dev/null || true
    
    # Create host launcher scripts
    create_container_launchers "$container_name"
    
    ok "$container_name container configured"
    return 0
}

# Create container launcher scripts
create_container_launchers(){
    local container_name="${1:-ubuntu}"
    
    info "Creating container launcher scripts..."
    
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    
    # Container login launcher
    cat > "$HOME/.local/bin/container" << CONTAINER_LAUNCHER_EOF
#!/bin/bash
# Container Launcher - Quick access to Linux container

echo "CAD-Droid Container Launcher"
echo "==========================="
echo "Container: $container_name"
echo ""

if [ "\$1" = "desktop" ]; then
    echo "Starting desktop environment..."
    proot-distro login $container_name -- startxfce4 2>/dev/null || \\
    echo "Desktop environment not available. Install with: apt install xfce4"
elif [ "\$1" = "dev" ]; then
    echo "Starting development environment..."
    proot-distro login $container_name -- bash -c "cd ~/Projects && bash"
else
    echo "Entering container shell..."
    proot-distro login $container_name
fi
CONTAINER_LAUNCHER_EOF
    
    chmod +x "$HOME/.local/bin/container" 2>/dev/null || true
    
    # Development environment launcher
    cat > "$HOME/.local/bin/devenv" << DEV_LAUNCHER_EOF
#!/bin/bash
# Development Environment Launcher

echo "CAD-Droid Development Environment"
echo "================================"
echo ""
echo "Available commands:"
echo "  python   - Python development"
echo "  node     - Node.js development"
echo "  git      - Git operations"
echo "  build    - Build tools"
echo ""

proot-distro login $container_name -- bash -c "cd ~/Projects && exec bash"
DEV_LAUNCHER_EOF
    
    chmod +x "$HOME/.local/bin/devenv" 2>/dev/null || true
    
    info "Launcher scripts created in ~/.local/bin/"
    return 0
}

# === XFCE Desktop Implementation ===

step_xfce(){
    pecho "$PASTEL_PURPLE" "Setting up XFCE desktop environment..."
    
    local container_name="${DISTRO:-ubuntu}"
    
    # Check if container exists
    if ! is_distro_installed "$container_name"; then
        warn "Container '$container_name' not found. Install container first."
        return 1
    fi
    
    # Install XFCE in container
    local xfce_script="/tmp/xfce_install.sh"
    cat > "$xfce_script" << XFCE_INSTALL_EOF
#!/bin/bash
set -e

echo "Installing XFCE desktop environment..."

# Update package lists
apt update

# Install XFCE and essential desktop components
DEBIAN_FRONTEND=noninteractive apt install -y \\
    xfce4 \\
    xfce4-goodies \\
    firefox-esr \\
    file-manager \\
    mousepad \\
    ristretto \\
    xfce4-terminal \\
    xfce4-taskmanager \\
    xfce4-screenshooter \\
    thunar \\
    pulseaudio \\
    pavucontrol

# Install additional useful applications
DEBIAN_FRONTEND=noninteractive apt install -y \\
    libreoffice \\
    gimp \\
    vlc \\
    chromium \\
    code \\
    gedit

# Configure XFCE for user
NEW_USER="\${USER:-developer}"
sudo -u "\$NEW_USER" bash << 'XFCE_CONFIG_EOF'
cd ~

# Create XFCE config directories
mkdir -p ~/.config/xfce4

# Create desktop shortcuts
mkdir -p ~/Desktop

# Firefox shortcut
cat > ~/Desktop/firefox.desktop << 'FIREFOX_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Firefox
Comment=Web Browser
Exec=firefox-esr
Icon=firefox
Terminal=false
Categories=Network;WebBrowser;
FIREFOX_EOF

# Terminal shortcut
cat > ~/Desktop/terminal.desktop << 'TERMINAL_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Terminal
Comment=Terminal Emulator
Exec=xfce4-terminal
Icon=terminal
Terminal=false
Categories=System;TerminalEmulator;
TERMINAL_EOF

# File Manager shortcut
cat > ~/Desktop/files.desktop << 'FILES_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Files
Comment=File Manager
Exec=thunar
Icon=folder
Terminal=false
Categories=System;FileManager;
FILES_EOF

chmod +x ~/Desktop/*.desktop

echo "XFCE desktop configured for user: \$NEW_USER"
XFCE_CONFIG_EOF

echo "XFCE installation complete!"
XFCE_INSTALL_EOF
    
    chmod +x "$xfce_script"
    
    # Run XFCE installation
    run_with_progress "Install XFCE desktop environment" 300 \
        proot-distro login "$container_name" -- bash < "$xfce_script"
    
    # Clean up
    rm -f "$xfce_script" 2>/dev/null || true
    
    # Create desktop launcher
    create_desktop_launcher "$container_name"
    
    ok "XFCE desktop environment installed"
    return 0
}

# Create desktop launcher
create_desktop_launcher(){
    local container_name="${1:-ubuntu}"
    
    info "Creating desktop launcher..."
    
    cat > "$HOME/.local/bin/desktop" << DESKTOP_LAUNCHER_EOF
#!/bin/bash
# Desktop Environment Launcher

echo "Starting CAD-Droid Desktop Environment..."
echo "========================================"
echo ""
echo "Container: $container_name"
echo "Desktop: XFCE4"
echo ""

# Check if X11 is available
if [ -z "\${DISPLAY:-}" ]; then
    echo "Warning: DISPLAY not set. You may need to:"
    echo "  1. Install Termux:X11 app"
    echo "  2. Start X11 server: termux-x11 :0"
    echo "  3. Set DISPLAY: export DISPLAY=:0"
    echo ""
fi

echo "Starting desktop environment..."
proot-distro login $container_name -- startxfce4
DESKTOP_LAUNCHER_EOF
    
    chmod +x "$HOME/.local/bin/desktop" 2>/dev/null || true
    
    pecho "$PASTEL_GREEN" "Desktop launcher created: desktop"
    info "Start with: desktop"
    return 0
}

# === Package Prefetch Implementation ===

step_prefetch(){
    pecho "$PASTEL_PURPLE" "Prefetching commonly used packages..."
    
    # Define packages to prefetch (download but don't necessarily install)
    local prefetch_packages=(
        # Development tools
        "build-essential" "cmake" "make" "gcc" "g++"
        # Languages
        "python3-dev" "nodejs" "openjdk-11-jdk" "golang"
        # Libraries
        "libssl-dev" "libcurl4-openssl-dev" "libxml2-dev" "libffi-dev"
        # Utilities
        "tree" "htop" "ncdu" "tmux" "screen"
        # Network tools
        "nmap" "wireshark-common" "tcpdump"
        # Media
        "ffmpeg" "imagemagick" "gimp"
        # Text processing
        "pandoc" "texlive-base"
    )
    
    local container_name="${DISTRO:-ubuntu}"
    
    if ! is_distro_installed "$container_name"; then
        info "Container not available - skipping prefetch"
        return 0
    fi
    
    # Create prefetch script
    local prefetch_script="/tmp/prefetch_packages.sh"
    cat > "$prefetch_script" << PREFETCH_EOF
#!/bin/bash

echo "Prefetching packages..."

# Update package lists
apt update

# Download packages without installing
echo "Downloading package archives..."
apt install --download-only -y ${prefetch_packages[*]} 2>/dev/null || {
    echo "Some packages may not be available in this distribution"
}

# Show cache status
echo ""
echo "Package cache status:"
du -sh /var/cache/apt/archives/ 2>/dev/null || echo "Cache information not available"

# Count cached packages
CACHED_COUNT=\$(ls -1 /var/cache/apt/archives/*.deb 2>/dev/null | wc -l || echo 0)
echo "Cached packages: \$CACHED_COUNT"

echo "Package prefetch complete"
PREFETCH_EOF
    
    chmod +x "$prefetch_script"
    
    # Run prefetch in container
    run_with_progress "Download common packages" 180 \
        proot-distro login "$container_name" -- bash < "$prefetch_script"
    
    # Clean up
    rm -f "$prefetch_script" 2>/dev/null || true
    
    ok "Package prefetch complete"
    return 0
}

# === Final Configuration Implementation ===

step_final(){
    pecho "$PASTEL_PURPLE" "Applying final configuration..."
    
    # Install widgets if enabled
    if [ "$ENABLE_WIDGETS" = "1" ] && [ -n "${_CAD_WIDGETS_LOADED:-}" ]; then
        info "Installing productivity widgets..."
        install_widgets
    fi
    
    # Configure bash prompt
    if [ -n "${_CAD_TERMUX_PROPS_LOADED:-}" ] && declare -f configure_bash_prompt >/dev/null 2>&1; then
        configure_bash_prompt
    fi
    
    # Create system launchers
    create_system_launchers
    
    # Generate completion summary
    create_completion_summary
    
    # Save completion state
    if [ -n "${_CAD_SNAPSHOTS_LOADED:-}" ] && declare -f save_completion_state >/dev/null 2>&1; then
        save_completion_state
    fi
    
    # Write metrics JSON
    write_metrics_json
    
    # Show final information
    show_final_information
    
    ok "Final configuration complete"
    return 0
}

# Create system launcher scripts
create_system_launchers(){
    info "Creating system launcher scripts..."
    
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    
    # CAD-Droid manager script
    cat > "$HOME/.local/bin/cad-droid" << CAD_MANAGER_EOF
#!/bin/bash
# CAD-Droid System Manager

case "\$1" in
    "container"|"c")
        container "\${@:2}"
        ;;
    "desktop"|"d")
        desktop
        ;;
    "devenv"|"dev")
        devenv
        ;;
    "widgets"|"w")
        widgets
        ;;
    "health"|"h")
        cd "$PWD" && bash setup.sh --doctor
        ;;
    "update"|"u")
        echo "Updating system packages..."
        apt update && apt upgrade
        ;;
    "info"|"i")
        echo "CAD-Droid Mobile Development Environment"
        echo "======================================="
        echo ""
        echo "Installed components:"
        [ -d "$HOME/.local/bin" ] && echo "  ✓ System launchers"
        [ -f "$HOME/.bashrc" ] && echo "  ✓ Bash configuration"
        [ -f "$HOME/.termux/termux.properties" ] && echo "  ✓ Termux properties"
        [ -d "$HOME/.local/share/applications" ] && echo "  ✓ Productivity widgets"
        command -v proot-distro >/dev/null && echo "  ✓ Linux container"
        echo ""
        echo "Available commands:"
        echo "  container, c    - Access Linux container"
        echo "  desktop, d      - Start desktop environment"  
        echo "  devenv, dev     - Development environment"
        echo "  widgets, w      - Show productivity widgets"
        echo "  health, h       - System health check"
        echo "  update, u       - Update packages"
        echo "  info, i         - Show this information"
        ;;
    *)
        echo "CAD-Droid Mobile Development Environment"
        echo "Usage: cad-droid <command>"
        echo ""
        echo "Commands:"
        echo "  container (c)   Access Linux container"
        echo "  desktop (d)     Start desktop environment"
        echo "  devenv (dev)    Development environment"  
        echo "  widgets (w)     Productivity widgets"
        echo "  health (h)      System health check"
        echo "  update (u)      Update system packages"
        echo "  info (i)        System information"
        echo ""
        echo "For detailed help: cad-droid info"
        ;;
esac
CAD_MANAGER_EOF
    
    chmod +x "$HOME/.local/bin/cad-droid" 2>/dev/null || true
    
    info "Created system manager: cad-droid"
    return 0
}

# Create completion summary
create_completion_summary(){
    local summary_file="$HOME/.cad-droid-summary.txt"
    
    cat > "$summary_file" << SUMMARY_EOF
CAD-Droid Mobile Development Environment - Installation Summary
=============================================================

Installation completed: $(date)

Installed Components:
--------------------
✓ Modular setup system with 10+ specialized modules
✓ Package management with intelligent mirror fallback
✓ Enhanced color interface with pastel themes
✓ Linux container environment (${DISTRO:-ubuntu})
✓ Development tools and editors
✓ Network utilities and diagnostics
✓ APK management with friendly naming
✓ ADB wireless debugging setup
$([ "$ENABLE_WIDGETS" = "1" ] && echo "✓ Productivity widgets and shortcuts")
$([ "$ENABLE_SUNSHINE" = "1" ] && echo "✓ Sunshine remote desktop streaming")
$([ "$ENABLE_SNAPSHOTS" = "1" ] && echo "✓ System backup and restore")

Quick Start:
-----------
• Run 'cad-droid' for system management
• Run 'container' to access Linux environment  
• Run 'desktop' to start GUI desktop
• Run 'devenv' for development environment
• Run 'widgets' to see productivity shortcuts

System Information:
------------------
• Termux Username: ${TERMUX_USERNAME:-user}
• Phone Type: ${TERMUX_PHONETYPE:-unknown}
• Git User: ${GIT_USERNAME:-not set}
• Container: ${DISTRO:-ubuntu}
• Packages Processed: ${DOWNLOAD_COUNT:-0}

For help and troubleshooting:
• Run './setup.sh --doctor' for diagnostics
• Run './setup.sh --help' for options  
• Check ~/.cad/logs/ for detailed logs

Enjoy your mobile development environment!
SUMMARY_EOF
    
    info "Installation summary saved: $summary_file"
    return 0
}

# Show final information to user
show_final_information(){
    echo ""
    pecho "$PASTEL_PURPLE" "🎉 CAD-Droid Installation Complete! 🎉"
    echo ""
    pecho "$PASTEL_GREEN" "Your mobile development environment is ready!"
    echo ""
    pecho "$PASTEL_CYAN" "Quick commands to get started:"
    echo "  • cad-droid        System manager"
    echo "  • container        Linux container"
    echo "  • desktop          GUI desktop"
    echo "  • devenv           Development environment"
    
    if [ "$ENABLE_WIDGETS" = "1" ]; then
        echo "  • widgets          Productivity shortcuts"
    fi
    
    echo ""
    pecho "$PASTEL_PURPLE" "For help: ./setup.sh --doctor or cad-droid info"
    echo ""
    
    # Show connection information if relevant
    if [ -n "${primary_ip:-}" ]; then
        pecho "$PASTEL_CYAN" "Device IP: $primary_ip"
    fi
    
    if [ "$ENABLE_SUNSHINE" = "1" ] && [ -n "${_CAD_SUNSHINE_LOADED:-}" ]; then
        pecho "$PASTEL_CYAN" "Remote desktop: Connect with Moonlight client"
    fi
    
    echo ""
    return 0
}

# Write installation metrics to JSON
write_metrics_json(){
    local json_file="setup-summary.json"
    
    # Create comprehensive metrics
    local json
    json=$(cat << METRICS_JSON_EOF
{
  "installation_date": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')",
  "script_version": "${SCRIPT_VERSION:-unknown}",
  "hostname": "$(hostname 2>/dev/null || echo 'unknown')",
  "termux_username": "${TERMUX_USERNAME//\"/\\\"}",
  "git_username": "${GIT_USERNAME//\"/\\\"}",
  "git_email": "${GIT_EMAIL//\"/\\\"}",
  "phone_type": "${TERMUX_PHONETYPE//\"/\\\"}",
  "selected_distro": "${DISTRO//\"/\\\"}",
  "selected_mirror_name": "${SELECTED_MIRROR_NAME//\"/\\\"}",
  "selected_mirror_url": "${SELECTED_MIRROR_URL//\"/\\\"}",
  "termux_api_verified": "${TERMUX_API_VERIFIED//\"/\\\"}",
  "user_selected_apk_dir": "${USER_SELECTED_APK_DIR//\"/\\\"}",
  "core_packages_processed": ${DOWNLOAD_COUNT:-0},
  "features_enabled": {
    "widgets": $([ "$ENABLE_WIDGETS" = "1" ] && echo "true" || echo "false"),
    "sunshine": $([ "$ENABLE_SUNSHINE" = "1" ] && echo "true" || echo "false"),
    "snapshots": $([ "$ENABLE_SNAPSHOTS" = "1" ] && echo "true" || echo "false"),
    "adb": $([ "$ENABLE_ADB" = "1" ] && echo "true" || echo "false")
  },
  "missing_apks": [
METRICS_JSON_EOF
)
    
    # Add missing APKs array
    local i
    for i in "${!APK_MISSING[@]}"; do
        json="${json}\"${APK_MISSING[$i]//\"/\\\"}\""
        if [ "$i" -lt $(( ${#APK_MISSING[@]}-1 )) ]; then
            json="${json},"
        fi
    done
    
    json="${json}],\"steps\":["
    
    # Add step information
    for i in "${!STEP_NAME[@]}"; do
        local step_json
        step_json=$(printf '{"index":%d,"name":"%s","duration_sec":%d,"status":"%s"}' \
            "$((i+1))" "${STEP_NAME[$i]//\"/\\\"}" "${STEP_DURATIONS[$i]:-0}" "${STEP_STATUS[$i]:-unknown}")
        json="${json}${step_json}"
        if [ "$i" -lt $(( ${#STEP_NAME[@]}-1 )) ]; then
            json="${json},"
        fi
    done
    
    json="${json}]}"
    
    # Write metrics file
    if printf "%s\\n" "$json" > "$json_file" 2>/dev/null; then
        ok "Metrics written: $json_file"
        return 0
    else
        warn "Failed to write metrics file"
        return 1
    fi
}