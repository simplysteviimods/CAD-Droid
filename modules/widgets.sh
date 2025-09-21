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
    
    # Git Status shortcut
    create_desktop_entry "git-status" "Git Status" "bash -c 'cd ~/; git status; read -p \"Press Enter to continue...\"'" "git" \
        "Check git repository status"
    
    # Terminal shortcut
    create_desktop_entry "terminal" "Terminal" "bash" "terminal" \
        "Open terminal session"
    
    # File Manager shortcut
    create_desktop_entry "files" "Files" "bash -c 'ls -la ~/; read -p \"Press Enter to continue...\"'" "folder" \
        "Browse home directory"
    
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

# === Widget Management Functions ===

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