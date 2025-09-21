#!/usr/bin/env bash
###############################################################################
# CAD-Droid Diagnostics Module
# Enhanced system diagnostics and testing functionality
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_DIAGNOSTICS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_DIAGNOSTICS_LOADED=1

# Dependencies: constants, utils, logging, termux_props, apk
if [ -z "${_CAD_CONSTANTS_LOADED:-}" ] || [ -z "${_CAD_UTILS_LOADED:-}" ] || [ -z "${_CAD_LOGGING_LOADED:-}" ]; then
    echo "Error: diagnostics.sh requires constants.sh, utils.sh, and logging.sh to be loaded first" >&2
    exit 1
fi

# === Enhanced Diagnostics Functions ===

# Run comprehensive system diagnostics
run_enhanced_diagnostics(){
    pecho "$PASTEL_PURPLE" "CAD-Droid Enhanced System Diagnostics"
    pecho "$PASTEL_PURPLE" "====================================="
    
    echo ""
    
    # System Information
    diagnostic_system_info
    echo ""
    
    # Network Diagnostics
    diagnostic_network_status
    echo ""
    
    # Package Manager Status
    diagnostic_package_status
    echo ""
    
    # Storage Analysis
    diagnostic_storage_analysis
    echo ""
    
    # Development Environment
    diagnostic_dev_environment
    echo ""
    
    # Container Status
    diagnostic_container_status
    echo ""
    
    # Termux Integration
    diagnostic_termux_integration
    echo ""
    
    # Security Status
    diagnostic_security_status
    echo ""
    
    pecho "$PASTEL_GREEN" "Diagnostics complete!"
    return 0
}

# System information diagnostics
diagnostic_system_info(){
    pecho "$PASTEL_CYAN" "System Information:"
    
    # Basic system info
    info "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
    info "Kernel: $(uname -r 2>/dev/null || echo 'unknown')"
    info "Architecture: $(uname -m 2>/dev/null || echo 'unknown')"
    
    # Termux info
    if command -v termux-info >/dev/null 2>&1; then
        local termux_version
        termux_version=$(termux-info 2>/dev/null | head -1 | cut -d' ' -f2 2>/dev/null || echo 'unknown')
        info "Termux version: $termux_version"
    fi
    
    # Android version (if available)
    if command -v getprop >/dev/null 2>&1; then
        local android_version
        android_version=$(getprop ro.build.version.release 2>/dev/null || echo 'unknown')
        info "Android version: $android_version"
    fi
    
    # Uptime
    if [ -f /proc/uptime ]; then
        local uptime_seconds uptime_readable
        uptime_seconds=$(cut -d' ' -f1 /proc/uptime | cut -d'.' -f1)
        uptime_readable=$(printf '%dd %dh %dm' $((uptime_seconds/86400)) $((uptime_seconds%86400/3600)) $((uptime_seconds%3600/60)))
        info "Uptime: $uptime_readable"
    fi
    
    # CPU info
    if [ -f /proc/cpuinfo ]; then
        local cpu_count
        cpu_count=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo '1')
        info "CPU cores: $cpu_count"
    fi
    
    # Memory info
    if [ -f /proc/meminfo ]; then
        local total_mem available_mem
        total_mem=$(awk '/MemTotal/ {printf "%.1fGB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 'unknown')
        available_mem=$(awk '/MemAvailable/ {printf "%.1fGB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 'unknown')
        info "Memory: $available_mem / $total_mem available"
    fi
}

# Network diagnostics
diagnostic_network_status(){
    pecho "$PASTEL_CYAN" "Network Status:"
    
    # Interface status
    if command -v ip >/dev/null 2>&1; then
        local interfaces
        interfaces=$(ip -4 addr show | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1' | wc -l)
        info "Active network interfaces: $interfaces"
        
        # Show primary IP
        local primary_ip
        primary_ip=$(ip -4 addr show | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1' | head -1)
        if [ -n "$primary_ip" ]; then
            info "Primary IP address: $primary_ip"
        fi
    fi
    
    # DNS resolution test
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        ok "Internet connectivity: Working"
    else
        warn "Internet connectivity: Failed"
    fi
    
    # Package repository connectivity
    if ping -c 1 -W 2 packages.termux.dev >/dev/null 2>&1; then
        ok "Termux repository: Reachable"
    else
        warn "Termux repository: Not reachable"
    fi
    
    # HTTP client tools
    local http_tools=0
    command -v curl >/dev/null 2>&1 && http_tools=$((http_tools + 1)) && info "curl: Available"
    command -v wget >/dev/null 2>&1 && http_tools=$((http_tools + 1)) && info "wget: Available"
    
    if [ "$http_tools" -eq 0 ]; then
        warn "No HTTP clients available"
    fi
}

# Package manager diagnostics
diagnostic_package_status(){
    pecho "$PASTEL_CYAN" "Package Manager Status:"
    
    # Check apt/dpkg
    if command -v apt >/dev/null 2>&1; then
        ok "APT package manager: Available"
        
        # Count installed packages
        if command -v dpkg >/dev/null 2>&1; then
            local pkg_count
            pkg_count=$(dpkg -l | grep "^ii" | wc -l 2>/dev/null || echo '0')
            info "Installed packages: $pkg_count"
        fi
        
        # Check for updates
        local updates_available
        updates_available=$(apt list --upgradable 2>/dev/null | wc -l 2>/dev/null || echo '0')
        if [ "$updates_available" -gt 1 ]; then
            info "Updates available: $((updates_available - 1))"
        else
            info "System up to date"
        fi
    else
        warn "APT package manager: Not available"
    fi
    
    # Repository status
    if [ -f "$PREFIX/etc/apt/sources.list" ]; then
        local repo_count
        repo_count=$(grep -c "^deb" "$PREFIX/etc/apt/sources.list" 2>/dev/null || echo '0')
        info "Configured repositories: $repo_count"
    fi
    
    # Mirror status
    if [ -n "${SELECTED_MIRROR_NAME:-}" ]; then
        info "Active mirror: ${SELECTED_MIRROR_NAME}"
    fi
}

# Storage diagnostics
diagnostic_storage_analysis(){
    pecho "$PASTEL_CYAN" "Storage Analysis:"
    
    # Disk usage
    local home_usage prefix_usage tmp_usage
    home_usage=$(du -sh "$HOME" 2>/dev/null | cut -f1 || echo 'unknown')
    prefix_usage=$(du -sh "$PREFIX" 2>/dev/null | cut -f1 || echo 'unknown')
    tmp_usage=$(du -sh "/tmp" 2>/dev/null | cut -f1 || echo 'unknown')
    
    info "Home directory: $home_usage"
    info "Termux prefix: $prefix_usage" 
    info "Temporary files: $tmp_usage"
    
    # Available space
    if command -v df >/dev/null 2>&1; then
        local available_space
        available_space=$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo 'unknown')
        info "Available space: $available_space"
        
        # Warn if low on space
        local available_mb
        available_mb=$(df "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo '0')
        if [ "$available_mb" -lt 500000 ]; then  # Less than ~500MB
            warn "Low disk space warning"
        fi
    fi
    
    # Large directories
    pecho "$PASTEL_CYAN" "Largest directories:"
    du -sh "$HOME"/* 2>/dev/null | sort -hr | head -5 | while read -r size dir; do
        info "  $size $(basename "$dir")"
    done
}

# Development environment diagnostics
diagnostic_dev_environment(){
    pecho "$PASTEL_CYAN" "Development Environment:"
    
    # Core development tools
    local dev_tools=("git" "python" "nano" "vim" "curl" "wget" "jq")
    local available_tools=0
    
    for tool in "${dev_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version
            case "$tool" in
                git) version=$(git --version 2>/dev/null | cut -d' ' -f3) ;;
                python) version=$(python --version 2>&1 | cut -d' ' -f2) ;;
                *) version="available" ;;
            esac
            info "$tool: $version"
            available_tools=$((available_tools + 1))
        else
            warn "$tool: Not installed"
        fi
    done
    
    info "Development tools: $available_tools/${#dev_tools[@]} available"
    
    # Git configuration
    if command -v git >/dev/null 2>&1; then
        local git_user git_email
        git_user=$(git config --global user.name 2>/dev/null || echo 'not set')
        git_email=$(git config --global user.email 2>/dev/null || echo 'not set')
        info "Git user: $git_user <$git_email>"
    fi
    
    # SSH keys
    if [ -d "$HOME/.ssh" ]; then
        local key_count
        key_count=$(ls -1 "$HOME/.ssh/"*.pub 2>/dev/null | wc -l || echo '0')
        info "SSH keys: $key_count"
    else
        info "SSH keys: None"
    fi
}

# Container diagnostics
diagnostic_container_status(){
    pecho "$PASTEL_CYAN" "Container Status:"
    
    if ! command -v proot-distro >/dev/null 2>&1; then
        warn "proot-distro: Not installed"
        return 0
    fi
    
    ok "proot-distro: Available"
    
    # List installed distributions
    local installed_distros
    installed_distros=$(proot-distro list 2>/dev/null | grep -c "installed" || echo '0')
    info "Installed distributions: $installed_distros"
    
    # Check specific distribution
    if [ -n "${DISTRO:-}" ]; then
        if proot-distro list 2>/dev/null | grep -q "${DISTRO}.*installed"; then
            ok "Distribution '$DISTRO': Installed"
        else
            warn "Distribution '$DISTRO': Not installed"
        fi
    fi
    
    # Container storage usage
    local container_dir="$PREFIX/var/lib/proot-distro/installed-rootfs"
    if [ -d "$container_dir" ]; then
        local container_usage
        container_usage=$(du -sh "$container_dir" 2>/dev/null | cut -f1 || echo 'unknown')
        info "Container storage: $container_usage"
    fi
}

# Termux integration diagnostics
diagnostic_termux_integration(){
    pecho "$PASTEL_CYAN" "Termux Integration:"
    
    # Termux:API detection  
    if [ "${TERMUX_API_VERIFIED:-no}" = "yes" ]; then
        ok "Termux:API detected"
    else
        info "Termux:API not detected (optional)"
    fi
    
    # Termux properties
    if [ -f "$HOME/.termux/termux.properties" ]; then
        ok "Termux properties: Configured"
        local extra_keys
        extra_keys=$(grep -c "extra-keys" "$HOME/.termux/termux.properties" 2>/dev/null || echo '0')
        info "Extra keys: $extra_keys configurations"
    else
        warn "Termux properties: Not configured"
    fi
    
    # Shell configuration
    if [ -f "$HOME/.bashrc" ]; then
        ok "Bash configuration: Available"
        local alias_count
        alias_count=$(grep -c "^alias" "$HOME/.bashrc" 2>/dev/null || echo '0')
        info "Shell aliases: $alias_count"
    else
        warn "Bash configuration: Default"
    fi
    
    # Phone detection
    if [ -n "${TERMUX_PHONETYPE:-}" ] && [ "${TERMUX_PHONETYPE}" != "unknown" ]; then
        info "Phone type: ${TERMUX_PHONETYPE}"
    fi
}

# Security status diagnostics  
diagnostic_security_status(){
    pecho "$PASTEL_CYAN" "Security Status:"
    
    # File permissions
    local secure_dirs=("$HOME/.ssh" "$HOME/.gnupg" "$WORK_DIR/credentials")
    for dir in "${secure_dirs[@]}"; do
        if [ -d "$dir" ]; then
            local perms
            perms=$(stat -c '%a' "$dir" 2>/dev/null || echo 'unknown')
            if [ "$perms" = "700" ]; then
                ok "$(basename "$dir"): Secure (700)"
            else
                warn "$(basename "$dir"): Permissions $perms"
            fi
        fi
    done
    
    # SSH agent
    if [ -n "${SSH_AGENT_PID:-}" ]; then
        ok "SSH agent: Running"
    else
        info "SSH agent: Not running"
    fi
    
    # GPG status
    if command -v gpg >/dev/null 2>&1; then
        local key_count
        key_count=$(gpg --list-keys 2>/dev/null | grep -c "^pub" || echo '0')
        info "GPG keys: $key_count"
    else
        info "GPG: Not available"
    fi
}

# === APK Diagnostics Functions ===

# Test APK download connections
test_apk_connections(){
    pecho "$PASTEL_PURPLE" "Testing APK download connections..."
    echo ""
    
    # Test F-Droid API
    pecho "$PASTEL_CYAN" "F-Droid Repository Test:"
    local fdroid_api="https://f-droid.org/api/v1/packages/com.termux.api"
    
    if wget_get "$fdroid_api" "/tmp/fdroid_test.json"; then
        ok "F-Droid API: Accessible"
        if command -v jq >/dev/null 2>&1 && [ -f "/tmp/fdroid_test.json" ]; then
            local app_name
            app_name=$(jq -r '.name // "Unknown"' "/tmp/fdroid_test.json" 2>/dev/null)
            info "Sample app: $app_name"
        fi
        rm -f "/tmp/fdroid_test.json" 2>/dev/null || true
    else
        warn "F-Droid API: Not accessible"
    fi
    
    echo ""
    
    # Test GitHub API
    pecho "$PASTEL_CYAN" "GitHub Repository Test:"
    local github_api="https://api.github.com/repos/termux/termux-api/releases/latest"
    
    if wget_get "$github_api" "/tmp/github_test.json"; then
        ok "GitHub API: Accessible"
        if command -v jq >/dev/null 2>&1 && [ -f "/tmp/github_test.json" ]; then
            local release_name asset_count
            release_name=$(jq -r '.name // "Unknown"' "/tmp/github_test.json" 2>/dev/null)
            asset_count=$(jq -r '.assets | length' "/tmp/github_test.json" 2>/dev/null || echo '0')
            info "Latest release: $release_name"
            info "Available assets: $asset_count"
        fi
        rm -f "/tmp/github_test.json" 2>/dev/null || true
    else
        warn "GitHub API: Not accessible"
    fi
    
    echo ""
    
    # Test download capability
    pecho "$PASTEL_CYAN" "Download Tools Test:"
    
    if command -v wget >/dev/null 2>&1; then
        ok "wget: Available"
        local wget_version
        wget_version=$(wget --version 2>/dev/null | head -1 | cut -d' ' -f3)
        info "Version: $wget_version"
    else
        warn "wget: Not available"
    fi
    
    if command -v curl >/dev/null 2>&1; then
        ok "curl: Available" 
        local curl_version
        curl_version=$(curl --version 2>/dev/null | head -1 | cut -d' ' -f2)
        info "Version: $curl_version"
    else
        warn "curl: Not available"
    fi
    
    echo ""
    
    # Test APK download directory
    pecho "$PASTEL_CYAN" "APK Storage Test:"
    local apk_dir="${USER_SELECTED_APK_DIR:-$HOME/Downloads}"
    
    if [ -d "$apk_dir" ]; then
        ok "APK directory: $apk_dir"
        local apk_count
        apk_count=$(ls -1 "$apk_dir"/*.apk 2>/dev/null | wc -l || echo '0')
        info "APK files: $apk_count"
        
        # Check write permissions
        if [ -w "$apk_dir" ]; then
            ok "Directory writable: Yes"
        else
            warn "Directory writable: No"
        fi
    else
        warn "APK directory: Not found"
    fi
    
    pecho "$PASTEL_GREEN" "APK connection test complete"
    return 0
}

# === System Health Check ===

# Run quick health check
health_check(){
    pecho "$PASTEL_PURPLE" "CAD-Droid System Health Check"
    echo ""
    
    local issues=0
    local warnings=0
    
    # Critical checks
    pecho "$PASTEL_CYAN" "Critical Systems:"
    
    if ! command -v apt >/dev/null 2>&1; then
        warn "Package manager not available"
        issues=$((issues + 1))
    else
        ok "Package manager: Working"
    fi
    
    if ! ping -c 1 -W 2 packages.termux.dev >/dev/null 2>&1; then
        warn "Repository not reachable"
        issues=$((issues + 1))
    else
        ok "Repository access: Working"
    fi
    
    # Storage check
    local available_mb
    available_mb=$(df "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo '1000000')
    if [ "$available_mb" -lt 100000 ]; then  # Less than ~100MB
        warn "Low disk space: $(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
        warnings=$((warnings + 1))
    else
        ok "Disk space: Sufficient"
    fi
    
    echo ""
    
    # Summary
    if [ "$issues" -eq 0 ] && [ "$warnings" -eq 0 ]; then
        pecho "$PASTEL_GREEN" "System health: All systems operational - OK"
    elif [ "$issues" -eq 0 ]; then
        pecho "$PASTEL_CYAN" "System health: Minor warnings ($warnings) - WARNING"
    else
        pecho "$PASTEL_PURPLE" "System health: Issues detected ($issues issues, $warnings warnings) - FAILED"
    fi
    
    return 0
}