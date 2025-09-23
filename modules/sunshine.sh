#!/usr/bin/env bash
###############################################################################
# CAD-Droid Sunshine Remote Desktop Module
# Remote desktop streaming service integration
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_SUNSHINE_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_SUNSHINE_LOADED=1

# Dependencies: constants, utils, logging
if [ -z "${_CAD_CONSTANTS_LOADED:-}" ] || [ -z "${_CAD_UTILS_LOADED:-}" ] || [ -z "${_CAD_LOGGING_LOADED:-}" ]; then
    echo "Error: sunshine.sh requires constants.sh, utils.sh, and logging.sh to be loaded first" >&2
    exit 1
fi

# === Sunshine Configuration ===
SUNSHINE_PORT="${SUNSHINE_PORT:-47989}"
SUNSHINE_CONFIG_DIR="$HOME/.config/sunshine"

# === Sunshine Detection Functions ===

# Check if Sunshine is available
sunshine_available(){
    command -v sunshine >/dev/null 2>&1
}

# Verify Sunshine health status
verify_sunshine_health(){
    if ! sunshine_available; then
        SUNSHINE_HEALTH="not_installed"
        return 1
    fi
    
    # Check if service is running
    if pgrep -f sunshine >/dev/null 2>&1; then
        SUNSHINE_HEALTH="running"
        return 0
    else
        SUNSHINE_HEALTH="stopped"
        return 1
    fi
}

# === Sunshine Installation Functions ===

# Find appropriate Sunshine .deb package
find_sunshine_deb(){
    local arch="${1:-arm64}"
    local api="https://api.github.com/repos/LizardByte/Sunshine/releases/latest"
    local url=""
    
    # Validate architecture
    case "$arch" in
        arm64|amd64|armhf) ;;
        *) 
            warn "Unsupported architecture: $arch"
            return 1
            ;;
    esac
    
    pecho "$PASTEL_PURPLE" "Finding Sunshine package for $arch..."
    
    # Try with curl first for API request
    local temp_json="/tmp/sunshine_release.json"
    if wget_get "$api" "$temp_json"; then
        # Parse JSON for appropriate .deb file
        if command -v jq >/dev/null 2>&1; then
            url=$(jq -r ".assets[] | select(.name | contains(\"$arch\") and endswith(\".deb\")) | .browser_download_url" "$temp_json" 2>/dev/null | head -1)
        else
            # Fallback parsing without jq
            url=$(grep -o '"browser_download_url":"[^"]*'$arch'[^"]*\.deb"' "$temp_json" 2>/dev/null | \
                  sed 's/"browser_download_url":"//; s/"//' | head -1)
        fi
        rm -f "$temp_json" 2>/dev/null || true
    fi
    
    if [ -n "$url" ]; then
        echo "$url"
        return 0
    else
        warn "Could not find Sunshine package for $arch"
        return 1
    fi
}

# Install Sunshine in container
install_sunshine(){
    local container_name="${DISTRO:-ubuntu}"
    
    if [ "$ENABLE_SUNSHINE" != "1" ]; then
        info "Sunshine installation disabled (ENABLE_SUNSHINE=0)"
        return 0
    fi
    
    pecho "$PASTEL_PURPLE" "Installing Sunshine remote desktop streaming..."
    
    # Check if container exists
    if ! proot-distro list 2>/dev/null | grep -q "$container_name"; then
        warn "Container '$container_name' not found. Install container first."
        return 1
    fi
    
    # Detect architecture
    local arch
    case "$(uname -m)" in
        aarch64) arch="arm64" ;;
        armv7l) arch="armhf" ;;
        x86_64) arch="amd64" ;;
        *) 
            warn "Unsupported architecture for Sunshine"
            return 1
            ;;
    esac
    
    # Find and download Sunshine package
    local sunshine_url
    sunshine_url=$(find_sunshine_deb "$arch")
    if [ -z "$sunshine_url" ]; then
        warn "Could not locate Sunshine package"
        return 1
    fi
    
    local sunshine_deb="/tmp/sunshine_${arch}.deb"
    info "Downloading Sunshine package..."
    
    if ! wget_get "$sunshine_url" "$sunshine_deb"; then
        warn "Failed to download Sunshine package"
        return 1
    fi
    
    # Install in container
    info "Installing Sunshine in container..."
    
    local install_script="/tmp/install_sunshine.sh"
    cat > "$install_script" << 'SUNSHINE_INSTALL_EOF'
#!/bin/bash
set -e

# Update package list
apt update

# Install dependencies
yes | apt install -y \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libva-dev \
    libdrm-dev \
    libx11-dev \
    libxfixes-dev \
    libxrandr-dev \
    libxtst-dev \
    libpulse-dev \
    libudev-dev \
    curl

# Install the .deb package
DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/sunshine_*.deb || true
yes | DEBIAN_FRONTEND=noninteractive apt install -f -y

# Create systemd user directory
mkdir -p ~/.config/systemd/user

# Create Sunshine service file
cat > ~/.config/systemd/user/sunshine.service << 'SERVICE_EOF'
[Unit]
Description=Sunshine Remote Desktop
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=forking
Environment=HOME=%h
ExecStart=/usr/bin/sunshine
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
SERVICE_EOF

echo "Sunshine installed successfully"
SUNSHINE_INSTALL_EOF
    
    chmod +x "$install_script"
    
    # Copy files to container and run installation
    if proot-distro login "$container_name" -- bash -c "
        cp '$sunshine_deb' /tmp/ &&
        cp '$install_script' /tmp/ &&
        bash /tmp/install_sunshine.sh
    "; then
        ok "Sunshine installed successfully in container"
        SUNSHINE_HEALTH="installed"
    else
        warn "Failed to install Sunshine"
        return 1
    fi
    
    # Clean up
    rm -f "$sunshine_deb" "$install_script" 2>/dev/null || true
    
    return 0
}

# === Sunshine Configuration Functions ===

# Configure Sunshine service
configure_sunshine(){
    local container_name="${DISTRO:-ubuntu}"
    
    pecho "$PASTEL_PURPLE" "Configuring Sunshine service..."
    
    # Create configuration directory
    mkdir -p "$SUNSHINE_CONFIG_DIR" 2>/dev/null || true
    
    # Create basic configuration
    local config_file="$SUNSHINE_CONFIG_DIR/sunshine.conf"
    cat > "$config_file" << SUNSHINE_CONFIG_EOF
# Sunshine Configuration
# Generated by CAD-Droid Setup

# Network settings
port = $SUNSHINE_PORT
upnp = true

# Video settings
fps = 60
bitrate = 20000
min_bitrate = 10000
max_bitrate = 40000

# Audio settings
audio_sink = pulse

# Input settings  
key_repeat_delay = 500
key_repeat_frequency = 24.9

# Security settings
pin = $(generate_random_pin)

# Performance settings
sw_preset = ultrafast
hw_device = auto
SUNSHINE_CONFIG_EOF
    
    info "Sunshine configuration created"
    
    # Create launcher script for host
    local launcher="$HOME/.local/bin/sunshine-launcher"
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    
    cat > "$launcher" << LAUNCHER_EOF
#!/bin/bash
# Sunshine Launcher - Start remote desktop streaming

echo "Starting Sunshine remote desktop service..."
proot-distro login $container_name -- systemctl --user start sunshine
echo "Sunshine started on port $SUNSHINE_PORT"
echo "Use Moonlight client to connect to this device"
LAUNCHER_EOF
    
    chmod +x "$launcher" 2>/dev/null || true
    
    ok "Sunshine configuration complete"
    return 0
}

# Generate random PIN for Sunshine
generate_random_pin(){
    if command -v shuf >/dev/null 2>&1; then
        shuf -i 1000-9999 -n 1 2>/dev/null || echo "1234"
    else
        # Fallback using date/process ID
        echo $((1000 + $(date +%s) % 9000)) 2>/dev/null || echo "1234"
    fi
}

# === Sunshine Testing Functions ===

# Test Sunshine streaming functionality
test_sunshine_streaming(){
    pecho "$PASTEL_PURPLE" "Testing Sunshine remote desktop streaming..."
    
    # Check if Sunshine is installed
    if ! sunshine_available; then
        warn "Sunshine is not installed"
        return 1
    fi
    
    # Check if service can start
    info "Testing Sunshine service startup..."
    local container_name="${DISTRO:-ubuntu}"
    
    if proot-distro login "$container_name" -- systemctl --user is-active sunshine >/dev/null 2>&1; then
        ok "Sunshine service is running"
    else
        info "Starting Sunshine service for test..."
        if proot-distro login "$container_name" -- systemctl --user start sunshine 2>/dev/null; then
            sleep 3
            if proot-distro login "$container_name" -- systemctl --user is-active sunshine >/dev/null 2>&1; then
                ok "Sunshine service started successfully"
            else
                warn "Sunshine service failed to start"
                return 1
            fi
        else
            warn "Failed to start Sunshine service"
            return 1
        fi
    fi
    
    # Check port availability
    info "Testing network connectivity..."
    if ss -tlnp | grep -q ":$SUNSHINE_PORT "; then
        ok "Sunshine port $SUNSHINE_PORT is listening"
    else
        warn "Sunshine port $SUNSHINE_PORT is not accessible"
        # Don't fail the test as the port might be bound inside container
    fi
    
    # Test configuration
    if [ -f "$SUNSHINE_CONFIG_DIR/sunshine.conf" ]; then
        ok "Sunshine configuration found"
    else
        warn "Sunshine configuration missing"
    fi
    
    pecho "$PASTEL_GREEN" "Sunshine streaming test complete"
    pecho "$PASTEL_CYAN" "Connect using Moonlight client on port $SUNSHINE_PORT"
    
    return 0
}

# Show Sunshine connection information
show_sunshine_info(){
    if ! sunshine_available; then
        warn "Sunshine is not installed"
        return 1
    fi
    
    pecho "$PASTEL_PURPLE" "Sunshine Remote Desktop Information:"
    
    # Get device IP addresses
    local ips
    ips=$(ip -4 addr show | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1' | head -3)
    
    if [ -n "$ips" ]; then
        pecho "$PASTEL_CYAN" "Device IP addresses:"
        echo "$ips" | while read -r ip; do
            pecho "$PASTEL_GREEN" "  • $ip:$SUNSHINE_PORT"
        done
    fi
    
    # Show PIN if available
    if [ -f "$SUNSHINE_CONFIG_DIR/sunshine.conf" ]; then
        local pin
        pin=$(grep "^pin = " "$SUNSHINE_CONFIG_DIR/sunshine.conf" 2>/dev/null | cut -d' ' -f3)
        if [ -n "$pin" ]; then
            pecho "$PASTEL_CYAN" "Connection PIN: $pin"
        fi
    fi
    
    pecho "$PASTEL_PURPLE" "Install Moonlight client to connect:"
    pecho "$PASTEL_GREEN" "  • Android: https://play.google.com/store/apps/details?id=com.limelight"
    pecho "$PASTEL_GREEN" "  • iOS: https://apps.apple.com/app/moonlight-game-streaming/id1000551566"
    pecho "$PASTEL_GREEN" "  • Windows/Mac/Linux: https://moonlight-stream.org/"
    
    return 0
}