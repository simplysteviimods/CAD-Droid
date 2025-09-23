#!/usr/bin/env bash
###############################################################################
# CAD-Droid Widgets Module
# Desktop shortcuts and mobile productivity tools
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_WIDGETS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_WIDGETS_LOADED=1

# Dependencies: constants, utils, logging
if [ -z "${_CAD_CONSTANTS_LOADED:-}" ] || [ -z "${_CAD_UTILS_LOADED:-}" ] || [ -z "${_CAD_LOGGING_LOADED:-}" ]; then
    echo "Error: widgets.sh requires constants.sh, utils.sh, and logging.sh to be loaded first" >&2
    exit 1
fi

# === Widget Configuration ===
WIDGET_DIR="$HOME/.local/share/applications"
DESKTOP_DIR="$HOME/Desktop"

# Helper functions for SSH configuration
get_ssh_port() {
    read_credential "ssh_port" || echo "8022"  # fallback port
}

get_ssh_username() {
    read_credential "ssh_username" || echo "caduser"  # fallback username
}

get_ssh_key_path() {
    echo "$HOME/.ssh/id_ed25519"
}

# === Widget Creation Functions ===

# Initialize widget system
init_widget_system(){
    if [ "$ENABLE_WIDGETS" != "1" ]; then
        debug "Widgets disabled (ENABLE_WIDGETS=0)"
        return 0
    fi
    
    # Create directories
    mkdir -p "$WIDGET_DIR" 2>/dev/null || true
    mkdir -p "$DESKTOP_DIR" 2>/dev/null || true
    
    return 0
}

# Create development shortcuts
create_dev_widgets(){
    if [ "$ENABLE_WIDGETS" != "1" ]; then
        return 0
    fi
    
    pecho "$PASTEL_PURPLE" "Creating development shortcuts..."
    
    # Code Editor shortcut
    create_desktop_entry "code-editor" "Code Editor" "nano %f" "text-editor" \
        "Quick access to nano text editor"
        
    # Termux Widget shortcuts (essential for phantom process killer)
    create_termux_widget_shortcuts
}

# Create essential Termux widget shortcuts
create_termux_widget_shortcuts(){
    info "Setting up Termux widget shortcuts..."
    
    # Create widget shortcuts directory
    local widget_shortcuts="$HOME/.shortcuts"
    mkdir -p "$widget_shortcuts" 2>/dev/null || true
    
    # Phantom Process Killer shortcut (CRITICAL)
    cat > "$widget_shortcuts/phantom-killer" << 'PHANTOM_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Phantom Process Killer - Critical for system stability
echo "Disabling phantom process killer..."
adb shell "settings put global settings_enable_monitor_phantom_procs false"
echo "Phantom process killer disabled!"
echo "Your apps should now run more reliably"
PHANTOM_EOF
    chmod +x "$widget_shortcuts/phantom-killer"
    
    # ADB Connect shortcut
    cat > "$widget_shortcuts/adb-connect" << 'ADB_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# ADB Wireless Connection
echo "Connecting ADB wirelessly..."
adb connect 127.0.0.1:5555
adb devices
echo "ADB connection status shown above"
ADB_EOF
    chmod +x "$widget_shortcuts/adb-connect"
    
    # System Info shortcut
    cat > "$widget_shortcuts/system-info" << 'SYSINFO_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# System Information Display
echo -e "\033[1;36mCAD-Droid System Info\033[0m"
echo "Battery: $(termux-battery-status | jq -r '.percentage')%"
echo "Network: $(termux-wifi-connectioninfo | jq -r '.ssid')"
echo "Storage: $(df -h $HOME | tail -1 | awk '{print $4}') free"
echo "Location: $(termux-location -p gps -r once | jq -r '.latitude, .longitude' | tr '\n' ',' | sed 's/,$//')"
SYSINFO_EOF
    chmod +x "$widget_shortcuts/system-info"
    
    # File Manager shortcut
    cat > "$widget_shortcuts/file-manager" << 'FM_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Quick File Manager
echo "Opening file manager..."
if command -v termux-open >/dev/null 2>&1; then
    termux-open $HOME
else
    ls -la $HOME
fi
FM_EOF
    chmod +x "$widget_shortcuts/file-manager"
    
    # Package Manager shortcut
    cat > "$widget_shortcuts/pkg-update" << 'PKG_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Quick Package Update
echo "Updating packages..."
pkg update -y && pkg upgrade -y
echo "Packages updated successfully!"
PKG_EOF
    chmod +x "$widget_shortcuts/pkg-update"
    
    ok "Termux widget shortcuts created in $widget_shortcuts"
    
    # Provide instructions
    printf "\n${PASTEL_YELLOW}Widget Setup Instructions:${RESET}\n"
    printf "${PASTEL_CYAN}1.${RESET} Add Termux widgets to your home screen\n"
    printf "${PASTEL_CYAN}2.${RESET} ${PASTEL_RED}IMPORTANT:${RESET} ${PASTEL_YELLOW}Add 'phantom-killer' widget for app stability${RESET}\n"
    printf "${PASTEL_CYAN}3.${RESET} Widgets available: phantom-killer, adb-connect, system-info, file-manager, pkg-update\n"
    printf "${PASTEL_CYAN}4.${RESET} Long press home screen → Widgets → Termux:Widget\n\n"
}

# Create desktop entry helper function
create_desktop_entry(){
    local entry_name="$1"
    local display_name="$2" 
    local exec_command="$3"
    local icon="$4"
    local comment="$5"
    
    local desktop_file="$WIDGET_DIR/${entry_name}.desktop"
    
    cat > "$desktop_file" << DESKTOP_EOF
[Desktop Entry]
Version=1.0
Name=${display_name}
Comment=${comment}
Exec=${exec_command}
Icon=${icon}
Terminal=false
Type=Application
Categories=Development;
DESKTOP_EOF

    chmod +x "$desktop_file" 2>/dev/null || true
}

# Create development shortcuts
create_dev_widgets(){
    if [ "$ENABLE_WIDGETS" != "1" ]; then
        return 0
    fi
    
    pecho "$PASTEL_PURPLE" "Creating development shortcuts..."
    
    # Code Editor shortcut
    create_desktop_entry "code-editor" "Code Editor" "nano %f" "text-editor" \
        "Quick access to nano text editor"
        
    # Git Status shortcut
    create_desktop_entry "git-status" "Git Status" "bash -c 'cd ~/; git status; read -p \"Press Enter to continue...\"'" "git" \
        "Check git repository status"
    
    # Terminal shortcut
    create_desktop_entry "terminal" "Terminal" "bash" "terminal" \
        "Open terminal session"
    
    # File Manager shortcut
    create_desktop_entry "files" "Files" "bash -c 'ls -la ~/; read -p \"Press Enter to continue...\"'" "folder" \
        "Browse home directory"
    
    # Termux Widget shortcuts (essential for phantom process killer)
    create_termux_widget_shortcuts
    
    ok "Development shortcuts created"
    return 0
}

# Create productivity widgets
create_productivity_widgets(){
    if [ "$ENABLE_WIDGETS" != "1" ]; then
        return 0
    fi
    
    pecho "$PASTEL_PURPLE" "Creating productivity widgets..."
    
    # System Information widget
    create_desktop_entry "system-info" "System Info" \
        "bash -c 'echo \"System Information:\"; uname -a; echo; df -h; echo; free -h; read -p \"Press Enter to continue...\"'" \
        "system-monitor" "Display system information"
    
    # Network Information widget
    create_desktop_entry "network-info" "Network Info" \
        "bash -c 'echo \"Network Information:\"; ip addr show; echo; ss -tulpn; read -p \"Press Enter to continue...\"'" \
        "network-wired" "Display network information"
    
    # Package Manager widget
    create_desktop_entry "package-manager" "Package Manager" \
        "bash -c 'echo \"Package Manager:\"; echo \"1) Update packages: apt update && apt upgrade\"; echo \"2) Search packages: apt search <query>\"; echo \"3) Install package: apt install <package>\"; read -p \"Press Enter to continue...\"'" \
        "package" "Package management shortcuts"
    
    # Log Viewer widget
    create_desktop_entry "log-viewer" "Log Viewer" \
        "bash -c 'echo \"Recent logs:\"; journalctl --user -n 50; read -p \"Press Enter to continue...\"'" \
        "document-text" "View system logs"
    
    ok "Productivity widgets created"
    return 0
}

# Create container shortcuts
create_container_widgets(){
    if [ "$ENABLE_WIDGETS" != "1" ]; then
        return 0
    fi
    
    local container_name="${DISTRO:-ubuntu}"
    
    pecho "$PASTEL_PURPLE" "Creating container shortcuts..."
    
    # Container Login shortcut
    create_desktop_entry "container-login" "Container Login" \
        "proot-distro login $container_name" "computer" \
        "Login to Linux container"
    
    # Container Shell shortcut
    create_desktop_entry "container-shell" "Container Shell" \
        "proot-distro login $container_name -- bash" "terminal" \
        "Open shell in Linux container"
    
    # Container Desktop shortcut (if XFCE is installed)
    create_desktop_entry "container-desktop" "Container Desktop" \
        "bash -c 'echo \"Starting desktop environment...\"; proot-distro login $container_name -- startxfce4'" \
        "desktop" "Start container desktop environment"
    
    ok "Container shortcuts created"
    return 0
}

# Create development environment widgets
create_devenv_widgets(){
    if [ "$ENABLE_WIDGETS" != "1" ]; then
        return 0
    fi
    
    pecho "$PASTEL_PURPLE" "Creating development environment shortcuts..."
    
    # Python Development shortcut
    create_desktop_entry "python-dev" "Python Dev" \
        "bash -c 'echo \"Python Development Environment\"; echo \"Python version: $(python --version 2>/dev/null || echo Not installed)\"; echo \"Pip version: $(pip --version 2>/dev/null || echo Not installed)\"; echo \"Virtual environments: $(ls -la ~/.virtualenvs 2>/dev/null || echo None)\"; read -p \"Press Enter to continue...\"'" \
        "python" "Python development environment"
    
    # Git Development shortcut
    create_desktop_entry "git-dev" "Git Dev" \
        "bash -c 'echo \"Git Development Environment\"; echo \"Git version: $(git --version 2>/dev/null || echo Not installed)\"; echo \"Current directory: $(pwd)\"; echo \"Git status:\"; git status 2>/dev/null || echo \"Not a git repository\"; read -p \"Press Enter to continue...\"'" \
        "git" "Git development environment"
    
    # Node.js Development shortcut (if available)
    if command -v node >/dev/null 2>&1; then
        create_desktop_entry "nodejs-dev" "Node.js Dev" \
            "bash -c 'echo \"Node.js Development Environment\"; echo \"Node version: $(node --version 2>/dev/null || echo Not installed)\"; echo \"NPM version: $(npm --version 2>/dev/null || echo Not installed)\"; echo \"Global packages:\"; npm list -g --depth=0 2>/dev/null || echo None; read -p \"Press Enter to continue...\"'" \
            "nodejs" "Node.js development environment"
    fi
    
    ok "Development environment shortcuts created"
    return 0
}

# Create utility desktop entry file
# Parameters: filename, name, command, icon, description
create_desktop_entry(){
    local filename="${1:-}"
    local name="${2:-}"
    local command="${3:-}"
    local icon="${4:-application-x-executable}"
    local description="${5:-}"
    
    if [ -z "$filename" ] || [ -z "$name" ] || [ -z "$command" ]; then
        warn "Missing required parameters for desktop entry"
        return 1
    fi
    
    local desktop_file="$WIDGET_DIR/${filename}.desktop"
    
    cat > "$desktop_file" << DESKTOP_ENTRY_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$description
Exec=$command
Icon=$icon
Terminal=true
Categories=Development;Utility;
StartupNotify=false
DESKTOP_ENTRY_EOF
    
    chmod +x "$desktop_file" 2>/dev/null || true
    
    # Also create symlink on desktop if desktop directory exists
    if [ -d "$DESKTOP_DIR" ]; then
        ln -sf "$desktop_file" "$DESKTOP_DIR/${filename}.desktop" 2>/dev/null || true
    fi
    
    debug "Created desktop entry: $filename"
    return 0
}

# Create Linux desktop shortcuts using tmux and SSH
create_linux_desktop_shortcuts(){
    info "Creating Linux desktop shortcuts..."
    
    # Create shortcuts directory
    local widget_shortcuts="$HOME/.shortcuts"
    mkdir -p "$widget_shortcuts" 2>/dev/null || true
    
    # Linux Desktop shortcut (portrait mode, X11 focus)
    cat > "$widget_shortcuts/Linux Desktop" << 'LINUX_DESKTOP_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Linux Desktop - X11 XFCE Desktop Environment with SSH Key Authentication

# Simple credential reader function
read_credential() {
    local name="$1"
    local cred_file="$HOME/.cad/credentials/$name.cred"
    if [ -f "$cred_file" ]; then
        cat "$cred_file" 2>/dev/null
    else
        return 1
    fi
}

# Get SSH configuration from stored credentials
SSH_PORT=$(read_credential "ssh_port" 2>/dev/null || echo "8022")
SSH_USERNAME=$(read_credential "ssh_username" 2>/dev/null || echo "caduser")
SSH_KEY="$HOME/.ssh/id_ed25519"

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo "SSH key not found at $SSH_KEY"
    echo "Please run the full CAD-Droid setup first"
    exit 1
fi

echo "Starting Linux Desktop..."
echo "SSH Port: $SSH_PORT"
echo "Username: $SSH_USERNAME"

# Start Termux:X11
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity

# Create new tmux session for container setup
tmux new -s rootlog -d

# Send commands to tmux session to setup SSH daemon
tmux send-keys "proot-distro login ubuntu --shared-tmp --fix-low-ports" enter
tmux send-keys "sudo service ssh start && sudo /usr/sbin/sshd -D -p $SSH_PORT & echo 'SSH daemon started' && tmux wait -S ssh_ready" enter

# Wait for SSH daemon to be ready
tmux wait ssh_ready

# Connect to the container via SSH with X11 forwarding and start XFCE
ssh -tt -X -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no "$SSH_USERNAME@localhost" 'termux-x11 :0 -xstartup "dbus-launch --exit-with-session xfce4-session"'

# Clean up tmux session when done
tmux kill-session -t rootlog 2>/dev/null || true
LINUX_DESKTOP_EOF
    chmod +x "$widget_shortcuts/Linux Desktop"
    
    # Linux Sunshine shortcut (landscape mode, includes Sunshine for remote access)
    cat > "$widget_shortcuts/Linux Sunshine" << 'LINUX_SUNSHINE_EOF'
#!/data/data/com.termux/files/usr/bin/bash  
# Linux Sunshine - X11 Desktop with Remote Streaming and SSH Key Authentication

# Force landscape orientation for better streaming experience
am start -a android.intent.action.MAIN -c android.intent.category.HOME

# Simple credential reader function
read_credential() {
    local name="$1"
    local cred_file="$HOME/.cad/credentials/$name.cred"
    if [ -f "$cred_file" ]; then
        cat "$cred_file" 2>/dev/null
    else
        return 1
    fi
}

# Get SSH configuration from stored credentials
SSH_PORT=$(read_credential "ssh_port" 2>/dev/null || echo "8022")
SSH_USERNAME=$(read_credential "ssh_username" 2>/dev/null || echo "caduser")
SSH_KEY="$HOME/.ssh/id_ed25519"

# Check if SSH key exists  
if [ ! -f "$SSH_KEY" ]; then
    echo "SSH key not found at $SSH_KEY"
    echo "Please run the full CAD-Droid setup first"
    exit 1
fi

echo "Starting Linux Sunshine Desktop..."
echo "SSH Port: $SSH_PORT"
echo "Username: $SSH_USERNAME"

# Start Termux:X11
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity

# Create new tmux session for container setup
tmux new -s sunshine_session -d

# Setup SSH daemon and Sunshine in the container
tmux send-keys "proot-distro login ubuntu --shared-tmp --fix-low-ports" enter
tmux send-keys "sudo service ssh start && sudo /usr/sbin/sshd -D -p $SSH_PORT & echo 'SSH daemon started'" enter
tmux send-keys "sudo systemctl start sunshine || sudo sunshine --service & echo 'Sunshine started'" enter
tmux send-keys "echo 'Services ready' && tmux wait -S services_ready" enter

# Wait for services to be ready
tmux wait services_ready

# Connect with X11 forwarding and start XFCE with Sunshine
ssh -tt -X -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no "$SSH_USERNAME@localhost" '
export DISPLAY=:0
sunshine --config-dir ~/.config/sunshine &
termux-x11 :0 -xstartup "dbus-launch --exit-with-session xfce4-session"
'

# Clean up tmux session when done
tmux kill-session -t sunshine_session 2>/dev/null || true
LINUX_SUNSHINE_EOF
    chmod +x "$widget_shortcuts/Linux Sunshine"
    
    ok "Linux desktop shortcuts created: 'Linux Desktop' and 'Linux Sunshine'"
}

# Install all widget categories
install_widgets(){
    if [ "$ENABLE_WIDGETS" != "1" ]; then
        info "Widgets disabled (ENABLE_WIDGETS=0)"
        return 0
    fi
    
    pecho "$PASTEL_PURPLE" "Installing productivity widgets and shortcuts..."
    
    init_widget_system
    
    # Create different categories of widgets
    create_dev_widgets
    create_productivity_widgets
    create_container_widgets
    create_devenv_widgets
    create_linux_desktop_shortcuts
    
    # Create widget index
    create_widget_index
    
    pecho "$PASTEL_GREEN" "Widget installation complete!"
    info "Widgets installed in: $WIDGET_DIR"
    if [ -d "$DESKTOP_DIR" ]; then
        info "Desktop shortcuts in: $DESKTOP_DIR"
    fi
    
    return 0
}

# Create widget index/launcher
create_widget_index(){
    local index_file="$HOME/.local/bin/widgets"
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    
    cat > "$index_file" << 'WIDGET_INDEX_EOF'
#!/bin/bash
# CAD-Droid Widget Launcher

echo "CAD-Droid Productivity Widgets"
echo "=============================="
echo ""
echo "Available shortcuts:"

# List available desktop files
if [ -d "$HOME/.local/share/applications" ]; then
    for desktop in "$HOME/.local/share/applications"/*.desktop; do
        if [ -f "$desktop" ]; then
            name=$(grep "^Name=" "$desktop" | cut -d'=' -f2)
            comment=$(grep "^Comment=" "$desktop" | cut -d'=' -f2)
            echo "  • $name - $comment"
        fi
    done
fi

echo ""
echo "To launch a widget, use your application launcher or file manager."
echo "Desktop shortcuts are available in ~/Desktop/"
WIDGET_INDEX_EOF
    
    chmod +x "$index_file" 2>/dev/null || true
}

# List installed widgets
list_widgets(){
    if [ ! -d "$WIDGET_DIR" ]; then
        info "No widgets installed"
        return 0
    fi
    
    pecho "$PASTEL_PURPLE" "Installed widgets:"
    
    local count=0
    for desktop_file in "$WIDGET_DIR"/*.desktop; do
        if [ -f "$desktop_file" ]; then
            local name comment
            name=$(grep "^Name=" "$desktop_file" 2>/dev/null | cut -d'=' -f2)
            comment=$(grep "^Comment=" "$desktop_file" 2>/dev/null | cut -d'=' -f2)
            
            if [ -n "$name" ]; then
                if [ -n "$comment" ]; then
                    pecho "$PASTEL_CYAN" "  • $name - $comment"
                else
                    pecho "$PASTEL_CYAN" "  • $name"
                fi
                count=$((count + 1))
            fi
        fi
    done
    
    if [ "$count" -eq 0 ]; then
        info "No widgets found"
    else
        pecho "$PASTEL_GREEN" "Total: $count widgets"
    fi
    
    return 0
}

# Remove all widgets
remove_widgets(){
    if [ "$NON_INTERACTIVE" != "1" ]; then
        pecho "$PASTEL_PURPLE" "Remove all productivity widgets? [y/N]"
        local confirm
        read -r confirm || confirm="n"
        case "$confirm" in
            [Yy]*) ;;
            *) 
                info "Cancelled"
                return 0
                ;;
        esac
    fi
    
    local removed=0
    
    # Remove desktop entries
    if [ -d "$WIDGET_DIR" ]; then
        for desktop_file in "$WIDGET_DIR"/*.desktop; do
            if [ -f "$desktop_file" ]; then
                local basename_file
                basename_file=$(basename "$desktop_file")
                # Only remove CAD-Droid created entries (avoid system ones)
                if grep -q "Categories=Development;Utility;" "$desktop_file" 2>/dev/null; then
                    rm "$desktop_file" 2>/dev/null && removed=$((removed + 1))
                fi
            fi
        done
    fi
    
    # Remove desktop shortcuts
    if [ -d "$DESKTOP_DIR" ]; then
        for desktop_file in "$DESKTOP_DIR"/*.desktop; do
            if [ -L "$desktop_file" ]; then  # Only remove symlinks
                rm "$desktop_file" 2>/dev/null || true
            fi
        done
    fi
    
    # Remove widget launcher
    rm -f "$HOME/.local/bin/widgets" 2>/dev/null || true
    
    if [ "$removed" -gt 0 ]; then
        ok "Removed $removed widgets"
    else
        info "No widgets to remove"
    fi
    
    return 0
}

# === Mobile Productivity Functions ===

# Create mobile-optimized shortcuts
create_mobile_shortcuts(){
    if [ "$ENABLE_WIDGETS" != "1" ]; then
        return 0
    fi
    
    pecho "$PASTEL_PURPLE" "Creating mobile-optimized shortcuts..."
    
    # Quick Commands shortcut
    create_desktop_entry "quick-commands" "Quick Commands" \
        "bash -c 'echo \"Quick Commands:\"; echo \"1. System update: pkg update && pkg upgrade\"; echo \"2. Clean cache: apt autoclean\"; echo \"3. Check space: df -h\"; echo \"4. Process list: ps aux\"; echo \"5. Network status: ip addr\"; read -p \"Enter command number (1-5): \" cmd; case \$cmd in 1) if command -v ensure_mirror_applied >/dev/null 2>&1; then ensure_mirror_applied; fi; if command -v pkg >/dev/null 2>&1; then pkg update -y && pkg upgrade -y; else apt update && apt upgrade -y; fi;; 2) if command -v pkg >/dev/null 2>&1; then pkg autoclean; else apt autoclean; fi;; 3) df -h;; 4) ps aux;; 5) ip addr;; *) echo \"Invalid choice\";; esac; read -p \"Press Enter to continue...\"'" \
        "preferences-system" "Quick system commands"
    
    # Development Tools shortcut
    create_desktop_entry "dev-tools" "Dev Tools" \
        "bash -c 'echo \"Development Tools:\"; echo \"1. Git status: git status\"; echo \"2. Git log: git log --oneline -10\"; echo \"3. Python version: python --version\"; echo \"4. Check ports: ss -tulpn\"; echo \"5. Disk usage: du -sh ~/\"; read -p \"Enter choice (1-5): \" choice; case \$choice in 1) git status;; 2) git log --oneline -10;; 3) python --version;; 4) ss -tulpn;; 5) du -sh ~/;; *) echo \"Invalid choice\";; esac; read -p \"Press Enter to continue...\"'" \
        "applications-development" "Development tool shortcuts"
    
    # System Monitor shortcut  
    create_desktop_entry "system-monitor" "System Monitor" \
        "bash -c 'while true; do clear; echo \"System Monitor - $(date)\"; echo \"===================\"; echo; echo \"CPU Usage:\"; cat /proc/loadavg; echo; echo \"Memory Usage:\"; free -h; echo; echo \"Disk Usage:\"; df -h /; echo; echo \"Top Processes:\"; ps aux --sort=-%cpu | head -5; echo; read -t 5 -p \"Press Enter to refresh (auto-refresh in 5s)...\" || true; done'" \
        "system-monitor" "Real-time system monitoring"
    
    ok "Mobile shortcuts created"
    return 0
}

# Show widget usage tips
show_widget_tips(){
    pecho "$PASTEL_PURPLE" "CAD-Droid Widget Usage Tips:"
    echo ""
    pecho "$PASTEL_CYAN" "Desktop Integration:"
    info "  • Widgets appear in your application launcher"
    info "  • Desktop shortcuts available in ~/Desktop/"  
    info "  • Use file manager to browse and launch"
    echo ""
    pecho "$PASTEL_CYAN" "Mobile Optimization:"
    info "  • Touch-friendly command interfaces"
    info "  • Quick access to common tasks"
    info "  • Simplified navigation menus"
    echo ""
    pecho "$PASTEL_CYAN" "Customization:"
    info "  • Edit .desktop files in ~/.local/share/applications/"
    info "  • Modify commands and descriptions"
    info "  • Add custom icons and categories"
    echo ""
    pecho "$PASTEL_GREEN" "Run 'widgets' command to see all available shortcuts"
    
    return 0
}