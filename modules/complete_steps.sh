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
        run_with_progress "Install proot-distro (apt)" 30 bash -c 'DEBIAN_FRONTEND=noninteractive apt install -y proot-distro >/dev/null 2>&1 || [ $? -eq 100 ]'
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
        printf "%b[%d] %s%b\n" "$seq" "$display_num" "${names[$__i]}" '\033[0m'
        __i=$(add_int "$__i" 1) || break
    done
    
    # Get user selection  
    local sel=""
    if [ "$NON_INTERACTIVE" = "1" ]; then
        sel="1"  # Default to Ubuntu
    else
        read_option "Select distribution [1-4]" sel 1 4 1
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
    debug "Container install path: $PREFIX/var/lib/proot-distro/installed-rootfs/$distro_name"
    
    # Install distribution if not already installed
    if ! is_distro_installed "$distro_name"; then
        info "Installing $distro_name container (this may take several minutes)..."
        debug "Running: proot-distro install $distro_name"
        local install_log="${TMPDIR:-$PREFIX/tmp}/proot-install-$$.log"
        if run_with_progress "Install $distro_name container" 120 \
            bash -c "DEBIAN_FRONTEND=noninteractive proot-distro install '$distro_name' 2>&1 | tee '$install_log'"; then
            local exit_code=$?
            if [ $exit_code -eq 0 ] || [ $exit_code -eq 100 ]; then
                ok "$distro_name container installed successfully"
                debug "Container installation completed (exit code: $exit_code)"
                rm -f "$install_log" 2>/dev/null || true
            else
                warn "$distro_name container installation may have had issues"
                debug "Container installation exit code: $exit_code"
                if [ -f "$install_log" ]; then
                    debug "Installation log contents:"
                    debug "$(cat "$install_log" 2>/dev/null | tail -20)"
                    rm -f "$install_log" 2>/dev/null || true
                fi
            fi
        else
            local exit_code=$?
            if [ $exit_code -eq 100 ]; then
                ok "$distro_name container installed successfully (already installed)"
                debug "Container installation completed (exit code: 100 - already installed)"
                rm -f "$install_log" 2>/dev/null || true
            else
                warn "$distro_name container installation may have had issues"
                debug "Container installation exit code: $exit_code"
                if [ -f "$install_log" ]; then
                    debug "Installation log contents:"
                    debug "$(cat "$install_log" 2>/dev/null | tail -20)"
                    rm -f "$install_log" 2>/dev/null || true
                fi
            fi
        fi
    else
        ok "$distro_name container already installed"
        debug "Container found at: $PREFIX/var/lib/proot-distro/installed-rootfs/$distro_name"
    fi
    
    # Verify installation
    debug "Verifying container installation..."
    if is_distro_installed "$distro_name"; then
        debug "Container verification: SUCCESS - $distro_name is properly installed"
    else
        warn "Container verification: FAILED - $distro_name installation may be incomplete"
    fi
    
    # Configure Linux environment with user accounts and SSH
    debug "Starting Linux environment configuration for: $distro_name"
    if configure_linux_env "$distro_name"; then
        debug "Linux environment configuration: SUCCESS"
        mark_step_status "success"
    else
        debug "Linux environment configuration: FAILED (exit code: $?)"
        mark_step_status "warning"
        warn "Container configuration had issues but container is available"
        debug "Container is still available for manual configuration"
    fi
}

# Configure Linux container
configure_container(){
    local container_name="${1:-ubuntu}"
    
    info "Configuring $container_name container..."
    
    # Create container setup script (robust temp path)
    local tmp_base="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
    mkdir -p "$tmp_base" 2>/dev/null || true
    local setup_script
    setup_script="$(mktemp "$tmp_base/container_setup.XXXXXX.sh" 2>/dev/null || echo "$tmp_base/container_setup.sh")"

    cat > "$setup_script" << CONTAINER_SETUP_EOF
#!/bin/bash
set -e

echo "Configuring $container_name container..."

# Update package lists
if command -v apt >/dev/null 2>&1; then
  apt update
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update
fi

# Install essential packages (Debian/Ubuntu)
if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y \\
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
    npm || true
fi

# Create user account
NEW_USER="\${USER:-developer}"
if ! id "\$NEW_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "\$NEW_USER" || true
    echo "\$NEW_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers || true
    echo "Created user: \$NEW_USER"
fi

# Set up development environment
sudo -u "\$NEW_USER" bash << 'USER_SETUP_EOF'
cd ~

# Create development directories
mkdir -p ~/Projects ~/Scripts ~/Downloads

# Set up git (if configured in host)
if [ -n "\${GIT_USERNAME:-}" ] && [ -n "\${GIT_EMAIL:-}" ]; then
    git config --global user.name "\$GIT_USERNAME" || true
    git config --global user.email "\$GIT_EMAIL" || true
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
    
    chmod +x "$setup_script" 2>/dev/null || true
    
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
    pecho "$PASTEL_PURPLE" "Setting up XFCE desktop environment for Termux..."
    
    # Install XFCE directly in Termux environment, not in a container
    info "Installing XFCE desktop packages for Termux..."
    
    # Essential XFCE packages for Termux
    local xfce_packages=(
        "xfce4"
        "xfce4-terminal" 
        "xfce4-panel"
        "xfce4-session"
        "xfce4-settings"
        "xfce4-whiskermenu-plugin"
        "xfce4-taskmanager"
        "tigervnc"
        "firefox"
        "pulseaudio"
    )
    
    # Install packages with progress
    for pkg in "${xfce_packages[@]}"; do
        run_with_progress "Install $pkg" 35 bash -c "
            pkg install -y $pkg >/dev/null 2>&1 || apt install -y $pkg >/dev/null 2>&1
        "
    done
    
    # Create XFCE startup script for Termux
    local xfce_script="$HOME/.cad/scripts/start-xfce-termux.sh"
    mkdir -p "$(dirname "$xfce_script")" 2>/dev/null || true
    
    cat > "$xfce_script" << 'XFCE_SCRIPT_EOF'
#!/bin/bash
# XFCE Desktop Environment for Termux

# Set up display
export DISPLAY=:1
export PULSE_RUNTIME_PATH=$PREFIX/var/run/pulse

# Start VNC server if not running
if ! pgrep -f "Xvnc.*:1" >/dev/null; then
    echo "Starting VNC server..."
    vncserver :1 -geometry 1920x1080 -depth 24 >/dev/null 2>&1
fi

# Start PulseAudio if not running
if ! pgrep -f pulseaudio >/dev/null; then
    echo "Starting PulseAudio..."
    pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1
fi

# Start XFCE session
echo "Starting XFCE desktop..."
DISPLAY=:1 xfce4-session >/dev/null 2>&1 &

echo "XFCE desktop started on display :1"
echo "Connect with VNC viewer to localhost:5901"
XFCE_SCRIPT_EOF
    
    chmod +x "$xfce_script" 2>/dev/null || true
    
    # Create desktop launcher
    local desktop_launcher="$HOME/.local/bin/desktop"
    mkdir -p "$(dirname "$desktop_launcher")" 2>/dev/null || true
    
    cat > "$desktop_launcher" << 'DESKTOP_LAUNCHER_EOF'
#!/bin/bash
# Desktop launcher for XFCE
exec ~/.cad/scripts/start-xfce-termux.sh "$@"
DESKTOP_LAUNCHER_EOF
    
    chmod +x "$desktop_launcher" 2>/dev/null || true
    
    ok "XFCE desktop environment installed for Termux"
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
    
    # Step 1: Clean package cache
    run_with_progress "Clean package cache in container" 15 \
        proot-distro login "$container_name" -- bash -c "
            apt-get clean >/dev/null 2>&1 || true
            rm -f /var/cache/apt/archives/*.deb 2>/dev/null || true
        "
    
    # Step 2: Update package lists
    run_with_progress "Update package lists" 30 \
        proot-distro login "$container_name" -- bash -c "
            apt-get update >/dev/null 2>&1
        "
    
    # Step 3: Download packages in batches with individual progress
    local batch_size=5
    local batch_num=1
    local total_batches=$(( (${#prefetch_packages[@]} + batch_size - 1) / batch_size ))
    
    info "Downloading $total_batches batches of development packages..."
    
    for ((i=0; i<${#prefetch_packages[@]}; i+=batch_size)); do
        local batch=("${prefetch_packages[@]:i:batch_size}")
        local batch_list="${batch[*]}"
        
        run_with_progress "Download batch $batch_num/$total_batches: ${batch_list// /, }" 25 \
            proot-distro login "$container_name" -- bash -c "
                apt-get -o Acquire::http::No-Cache=true \\
                    --download-only --fix-missing -y \\
                    install $batch_list >/dev/null 2>&1 || true
            "
        
        batch_num=$((batch_num + 1))
    done
    
    # Step 4: Report final cache status
    run_with_progress "Check downloaded package cache" 10 \
        proot-distro login "$container_name" -- bash -c "
            CACHED_COUNT=\$(ls -1 /var/cache/apt/archives/*.deb 2>/dev/null | wc -l || echo 0)
            echo \"Cached packages: \$CACHED_COUNT\"
        "
    
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
        # Ensure selected mirror is applied before updating system packages
        if command -v ensure_mirror_applied >/dev/null 2>&1; then
            ensure_mirror_applied
        fi
        # Use appropriate Termux package manager
        if command -v pkg >/dev/null 2>&1; then
            pkg update -y && pkg upgrade -y
        else
            apt update && apt upgrade -y
        fi
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
    pecho "$PASTEL_PURPLE" "CAD-Droid Installation Complete!"
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
    if printf "%s\n" "$json" > "$json_file" 2>/dev/null; then
        ok "Metrics written: $json_file"
        return 0
    else
        warn "Failed to write metrics file"
        return 1
    fi
}

# Configure Linux container environment with SSH access
configure_linux_env() {
    local distro="$1"
    debug "Starting Linux environment configuration for distribution: $distro"
    
    # Generate SSH port
    local ssh_port
    ssh_port=$(random_port)
    debug "Generated SSH port: $ssh_port"
    
    # Store SSH port for later use by shortcuts
    store_credential "ssh_port" "$ssh_port"
    
    # Get user configuration with confirmation loop
    while true; do
        read_nonempty "Linux username" UBUNTU_USERNAME "caduser"
        
        if [ "$NON_INTERACTIVE" = "1" ]; then
            break
        fi
        
        if ask_yes_no "Confirm Linux username: $UBUNTU_USERNAME" "y"; then
            break
        fi
        
        info "Please enter the username again"
    done
    
    # Store SSH username for later use by shortcuts
    store_credential "ssh_username" "$UBUNTU_USERNAME"
    
    if ! read_password_confirm "Password for $UBUNTU_USERNAME (hidden)" "Confirm password" "linux_user"; then
        warn "User password setup failed, using default"
        store_credential "linux_user" "cadpass123"
    fi
    
    if ! read_password_confirm "Root password (hidden)" "Confirm password" "linux_root"; then
        warn "Root password setup failed, using default"  
        store_credential "linux_root" "rootpass123"
    fi

    # Generate SSH key for container access
    local ssh_dir="$HOME/.ssh"
    if ! mkdir -p "$ssh_dir" 2>/dev/null; then
        warn "Cannot create SSH directory"
        return 1
    fi
    chmod 700 "$ssh_dir" 2>/dev/null || true
    
    local ssh_key="$ssh_dir/id_ed25519"
    if [ ! -f "$ssh_key" ]; then
        run_with_progress "Generate container SSH key" 8 bash -c "
            umask 077
            ssh-keygen -t ed25519 -f '$ssh_key' -N '' -C 'container-access' >/dev/null 2>&1 || exit 1
        "
    fi
    
    # Read the SSH public key
    local pubkey
    if [ -f "${ssh_key}.pub" ]; then
        pubkey=$(cat "${ssh_key}.pub" 2>/dev/null || echo "")
    else
        warn "SSH key generation failed"
        return 1
    fi
    
    # Retrieve stored passwords
    local user_pass root_pass
    user_pass=$(read_credential "linux_user" || echo "cadpass123")
    root_pass=$(read_credential "linux_root" || echo "rootpass123")
    
    # Configure the container
    info "Setting up user accounts and SSH access..."
    if run_with_progress "Configure container environment" 30 bash -c "
        proot-distro login '$distro' --shared-tmp -- bash -c \\\"
            # Update package manager
            if command -v apt-get >/dev/null 2>&1; then
                export DEBIAN_FRONTEND=noninteractive
                apt-get update >/dev/null 2>&1 || true
                apt-get install -y sudo openssh-server >/dev/null 2>&1 || true
            elif command -v pacman >/dev/null 2>&1; then
                pacman -Sy --noconfirm sudo openssh >/dev/null 2>&1 || true
            elif command -v apk >/dev/null 2>&1; then
                apk update >/dev/null 2>&1 && apk add sudo openssh >/dev/null 2>&1 || true
            fi
            
            # Create user account
            if ! id '$UBUNTU_USERNAME' >/dev/null 2>&1; then
                useradd -m -s /bin/bash '$UBUNTU_USERNAME' >/dev/null 2>&1 || true
                echo '$UBUNTU_USERNAME:$user_pass' | chpasswd >/dev/null 2>&1 || true
            fi
            
            # Add user to sudo group
            usermod -aG sudo '$UBUNTU_USERNAME' >/dev/null 2>&1 || true
            
            # Set root password
            echo 'root:$root_pass' | chpasswd >/dev/null 2>&1 || true
            
            # Setup SSH directory for user
            mkdir -p /home/'$UBUNTU_USERNAME'/.ssh >/dev/null 2>&1 || true
            echo '$pubkey' > /home/'$UBUNTU_USERNAME'/.ssh/authorized_keys 2>/dev/null || true
            chown -R '$UBUNTU_USERNAME':'$UBUNTU_USERNAME' /home/'$UBUNTU_USERNAME'/.ssh >/dev/null 2>&1 || true
            chmod 700 /home/'$UBUNTU_USERNAME'/.ssh >/dev/null 2>&1 || true
            chmod 600 /home/'$UBUNTU_USERNAME'/.ssh/authorized_keys >/dev/null 2>&1 || true
            
            # Configure SSH daemon with custom port
            mkdir -p /etc/ssh >/dev/null 2>&1 || true
            sed -i 's/#Port 22/Port $ssh_port/' /etc/ssh/sshd_config 2>/dev/null || echo 'Port $ssh_port' >> /etc/ssh/sshd_config
            sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
            sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null || echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
        \\\"
    "; then
        ok "Container environment configured successfully"
    else
        warn "Container configuration completed with some warnings"
    fi
    # Create convenience launcher
    local launcher="$PREFIX/bin/container"
    cat > "$launcher" << LAUNCHER_EOF
#!/bin/bash
# Container access launcher - connects to $distro environment
# Usage: container [command]
if [ \$# -eq 0 ]; then
    echo "Entering $distro container as $UBUNTU_USERNAME..."
    proot-distro login '$distro' --user '$UBUNTU_USERNAME' --
else
    proot-distro login '$distro' --user '$UBUNTU_USERNAME' -- "\$@"
fi
LAUNCHER_EOF
    chmod +x "$launcher" 2>/dev/null || true
    
    ok "Linux container setup completed"
    info "Access container with: container"
    info "SSH key available at: $ssh_key"
    info "Container user: $UBUNTU_USERNAME"
    
    debug "Linux environment configuration completed successfully"
    debug "Container: $distro, User: $UBUNTU_USERNAME, SSH Port: $ssh_port"
    
    return 0
}
