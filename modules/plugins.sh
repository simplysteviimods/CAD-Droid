#!/usr/bin/env bash
###############################################################################
# CAD-Droid Plugins Module
# Custom plugin loading and execution framework
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_PLUGINS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_PLUGINS_LOADED=1

# Dependencies: constants, utils, logging
if [ -z "${_CAD_CONSTANTS_LOADED:-}" ] || [ -z "${_CAD_UTILS_LOADED:-}" ] || [ -z "${_CAD_LOGGING_LOADED:-}" ]; then
    echo "Error: plugins.sh requires constants.sh, utils.sh, and logging.sh to be loaded first" >&2
    exit 1
fi

# === Plugin System Configuration ===
PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.cad/plugins}"

# Track loaded plugins
declare -a LOADED_PLUGINS=()

# === Plugin Discovery Functions ===

# Initialize plugin system
init_plugin_system(){
    local plugin_dir="${PLUGIN_DIR}"
    
    if [ ! -d "$plugin_dir" ]; then
        if mkdir -p "$plugin_dir" 2>/dev/null; then
            debug "Created plugin directory: $plugin_dir"
            
            # Create example plugin
            create_example_plugin
        else
            debug "Failed to create plugin directory: $plugin_dir"
            return 1
        fi
    fi
    
    return 0
}

# Create an example plugin for reference
create_example_plugin(){
    local example_file="$PLUGIN_DIR/example.sh"
    
    cat > "$example_file" << 'EXAMPLE_PLUGIN_EOF'
#!/usr/bin/env bash
###############################################################################
# Example CAD-Droid Plugin
# This is a template for creating custom plugins
###############################################################################

# Plugin metadata (required)
PLUGIN_NAME="Example Plugin"
PLUGIN_VERSION="1.0.0"
PLUGIN_DESCRIPTION="Example plugin demonstrating the plugin system"
PLUGIN_AUTHOR="CAD-Droid"

# Plugin initialization function (optional)
plugin_init(){
    echo "Example plugin initialized"
    return 0
}

# Plugin main function (required)
plugin_main(){
    echo "Hello from example plugin!"
    echo "Plugin name: $PLUGIN_NAME"
    echo "Plugin version: $PLUGIN_VERSION"
    echo "Arguments: $*"
    return 0
}

# Plugin cleanup function (optional)
plugin_cleanup(){
    echo "Example plugin cleanup"
    return 0
}

# Plugin help function (optional)
plugin_help(){
    cat << 'HELP_EOF'
Example Plugin Help

This plugin demonstrates the CAD-Droid plugin system.

Usage:
  plugin_main [arguments...]

Available functions:
  - plugin_init: Initialize the plugin
  - plugin_main: Main plugin functionality
  - plugin_cleanup: Clean up resources
  - plugin_help: Show this help

Plugin API:
  - Access to all CAD-Droid functions and variables
  - Use pecho/info/warn/err for consistent output
  - Return 0 for success, non-zero for failure
HELP_EOF
}
EXAMPLE_PLUGIN_EOF
    
    chmod +x "$example_file" 2>/dev/null || true
}

# Discover available plugins
discover_plugins(){
    local plugin_dir="${PLUGIN_DIR}"
    local plugins=()
    
    if [ ! -d "$plugin_dir" ]; then
        debug "Plugin directory not found: $plugin_dir"
        return 1
    fi
    
    # Find all .sh files in plugin directory
    for plugin_file in "$plugin_dir"/*.sh; do
        if [ -f "$plugin_file" ] && [ -r "$plugin_file" ]; then
            local plugin_name
            plugin_name=$(basename "$plugin_file" .sh)
            plugins+=("$plugin_name")
        fi
    done
    
    if [ ${#plugins[@]} -eq 0 ]; then
        debug "No plugins found in $plugin_dir"
        return 1
    fi
    
    printf '%s\n' "${plugins[@]}"
    return 0
}

# Validate plugin file
validate_plugin(){
    local plugin_file="${1:-}"
    
    if [ -z "$plugin_file" ] || [ ! -f "$plugin_file" ]; then
        return 1
    fi
    
    # Check if file is readable
    if [ ! -r "$plugin_file" ]; then
        debug "Plugin file not readable: $plugin_file"
        return 1
    fi
    
    # Check for required functions using bash -n (syntax check)
    if ! bash -n "$plugin_file" 2>/dev/null; then
        debug "Plugin has syntax errors: $plugin_file"
        return 1
    fi
    
    # Check for required plugin_main function
    if ! grep -q "^plugin_main()" "$plugin_file" 2>/dev/null; then
        debug "Plugin missing plugin_main function: $plugin_file"
        return 1
    fi
    
    return 0
}

# === Plugin Loading Functions ===

# Load a plugin by name
load_plugin(){
    local plugin_name="${1:-}"
    
    if [ -z "$plugin_name" ]; then
        warn "Plugin name required"
        return 1
    fi
    
    local plugin_file="$PLUGIN_DIR/${plugin_name}.sh"
    
    if [ ! -f "$plugin_file" ]; then
        warn "Plugin not found: $plugin_name"
        return 1
    fi
    
    # Validate plugin
    if ! validate_plugin "$plugin_file"; then
        warn "Invalid plugin: $plugin_name"
        return 1
    fi
    
    # Check if already loaded
    local loaded_plugin
    for loaded_plugin in "${LOADED_PLUGINS[@]}"; do
        if [ "$loaded_plugin" = "$plugin_name" ]; then
            debug "Plugin already loaded: $plugin_name"
            return 0
        fi
    done
    
    debug "Loading plugin: $plugin_name"
    
    # Source the plugin file
    if source "$plugin_file" 2>/dev/null; then
        LOADED_PLUGINS+=("$plugin_name")
        
        # Call plugin initialization if available
        if declare -f plugin_init >/dev/null 2>&1; then
            plugin_init || warn "Plugin initialization failed: $plugin_name"
        fi
        
        debug "Plugin loaded successfully: $plugin_name"
        return 0
    else
        warn "Failed to load plugin: $plugin_name"
        return 1
    fi
}

# Load all available plugins
load_all_plugins(){
    local plugins
    plugins=$(discover_plugins)
    
    if [ -z "$plugins" ]; then
        debug "No plugins to load"
        return 0
    fi
    
    local loaded_count=0
    local failed_count=0
    
    while IFS= read -r plugin_name; do
        if [ -n "$plugin_name" ]; then
            if load_plugin "$plugin_name"; then
                loaded_count=$((loaded_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
        fi
    done <<< "$plugins"
    
    if [ "$loaded_count" -gt 0 ]; then
        debug "Loaded $loaded_count plugins"
    fi
    
    if [ "$failed_count" -gt 0 ]; then
        warn "Failed to load $failed_count plugins"
    fi
    
    return 0
}

# === Plugin Execution Functions ===

# Execute a plugin
execute_plugin(){
    local plugin_name="${1:-}"
    shift
    
    if [ -z "$plugin_name" ]; then
        warn "Plugin name required"
        return 1
    fi
    
    # Check if plugin is loaded
    local loaded_plugin found=0
    for loaded_plugin in "${LOADED_PLUGINS[@]}"; do
        if [ "$loaded_plugin" = "$plugin_name" ]; then
            found=1
            break
        fi
    done
    
    if [ "$found" -eq 0 ]; then
        # Try to load the plugin
        if ! load_plugin "$plugin_name"; then
            warn "Plugin not available: $plugin_name"
            return 1
        fi
    fi
    
    # Execute plugin main function
    if declare -f plugin_main >/dev/null 2>&1; then
        debug "Executing plugin: $plugin_name"
        plugin_main "$@"
        local result=$?
        
        if [ "$result" -eq 0 ]; then
            debug "Plugin executed successfully: $plugin_name"
        else
            warn "Plugin execution failed: $plugin_name (exit code: $result)"
        fi
        
        return $result
    else
        warn "Plugin has no main function: $plugin_name"
        return 1
    fi
}

# Show plugin information
show_plugin_info(){
    local plugin_name="${1:-}"
    
    if [ -z "$plugin_name" ]; then
        warn "Plugin name required"
        return 1
    fi
    
    local plugin_file="$PLUGIN_DIR/${plugin_name}.sh"
    
    if [ ! -f "$plugin_file" ]; then
        warn "Plugin not found: $plugin_name"
        return 1
    fi
    
    pecho "$PASTEL_PURPLE" "Plugin Information: $plugin_name"
    
    # Extract metadata
    local name version description author
    name=$(grep "^PLUGIN_NAME=" "$plugin_file" 2>/dev/null | cut -d'"' -f2)
    version=$(grep "^PLUGIN_VERSION=" "$plugin_file" 2>/dev/null | cut -d'"' -f2)
    description=$(grep "^PLUGIN_DESCRIPTION=" "$plugin_file" 2>/dev/null | cut -d'"' -f2)
    author=$(grep "^PLUGIN_AUTHOR=" "$plugin_file" 2>/dev/null | cut -d'"' -f2)
    
    [ -n "$name" ] && info "Name: $name"
    [ -n "$version" ] && info "Version: $version"
    [ -n "$description" ] && info "Description: $description"
    [ -n "$author" ] && info "Author: $author"
    
    # Check available functions
    info "Available functions:"
    declare -f -F | grep "^declare -f plugin_" | while read -r _ _ func; do
        pecho "$PASTEL_CYAN" "  • $func"
    done
    
    return 0
}

# List all available plugins
list_plugins(){
    init_plugin_system
    
    local plugins
    plugins=$(discover_plugins)
    
    pecho "$PASTEL_PURPLE" "Available plugins:"
    
    if [ -z "$plugins" ]; then
        info "No plugins found in $PLUGIN_DIR"
        info "Create .sh files in the plugin directory to add custom functionality"
        return 0
    fi
    
    while IFS= read -r plugin_name; do
        if [ -n "$plugin_name" ]; then
            local plugin_file="$PLUGIN_DIR/${plugin_name}.sh"
            local status="INVALID"
            
            # Check if plugin is valid
            if validate_plugin "$plugin_file"; then
                status="VALID"
                
                # Check if loaded
                local loaded_plugin
                for loaded_plugin in "${LOADED_PLUGINS[@]}"; do
                    if [ "$loaded_plugin" = "$plugin_name" ]; then
                        status="LOADED"  # Loaded status
                        break
                    fi
                done
            fi
            
            # Get plugin description
            local description
            description=$(grep "^PLUGIN_DESCRIPTION=" "$plugin_file" 2>/dev/null | cut -d'"' -f2)
            
            if [ -n "$description" ]; then
                pecho "$PASTEL_CYAN" "  $status $plugin_name - $description"
            else
                pecho "$PASTEL_CYAN" "  $status $plugin_name"
            fi
        fi
    done <<< "$plugins"
    
    pecho "$PASTEL_GREEN" ""
    pecho "$PASTEL_GREEN" "Legend: VALID=Valid  LOADED=Loaded  INVALID=Invalid"
    
    return 0
}

# === Plugin Management Functions ===

# Unload all plugins
unload_all_plugins(){
    local plugin_name
    for plugin_name in "${LOADED_PLUGINS[@]}"; do
        # Call cleanup function if available
        if declare -f plugin_cleanup >/dev/null 2>&1; then
            plugin_cleanup || debug "Plugin cleanup failed: $plugin_name"
        fi
        
        debug "Unloaded plugin: $plugin_name"
    done
    
    LOADED_PLUGINS=()
    return 0
}

# Show plugin help
show_plugin_help(){
    local plugin_name="${1:-}"
    
    if [ -z "$plugin_name" ]; then
        pecho "$PASTEL_PURPLE" "CAD-Droid Plugin System Help"
        echo ""
        echo "Available commands:"
        echo "  list-plugins          List all available plugins"
        echo "  load-plugin <name>    Load a specific plugin"
        echo "  execute-plugin <name> Execute a plugin"
        echo "  plugin-info <name>    Show plugin information"
        echo "  plugin-help <name>    Show plugin-specific help"
        echo ""
        echo "Plugin directory: $PLUGIN_DIR"
        return 0
    fi
    
    # Load plugin if not already loaded
    if ! load_plugin "$plugin_name"; then
        return 1
    fi
    
    # Call plugin help function if available
    if declare -f plugin_help >/dev/null 2>&1; then
        plugin_help
    else
        show_plugin_info "$plugin_name"
    fi
    
    return 0
}