#!/usr/bin/env bash
###############################################################################
# CAD-Droid Snapshots Module
# System backup and restore functionality
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_SNAPSHOTS_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_SNAPSHOTS_LOADED=1

# Dependencies: constants, utils, logging
if [ -z "${_CAD_CONSTANTS_LOADED:-}" ] || [ -z "${_CAD_UTILS_LOADED:-}" ] || [ -z "${_CAD_LOGGING_LOADED:-}" ]; then
    echo "Error: snapshots.sh requires constants.sh, utils.sh, and logging.sh to be loaded first" >&2
    exit 1
fi

# === Snapshot Configuration ===
SNAPSHOT_DIR="${SNAP_DIR:-$HOME/.cad/snapshots}"

# === Snapshot Management Functions ===

# Initialize snapshot directory structure
init_snapshot_system(){
    local snapshot_dir="${SNAPSHOT_DIR}"
    
    if [ ! -d "$snapshot_dir" ]; then
        if mkdir -p "$snapshot_dir" 2>/dev/null; then
            debug "Created snapshot directory: $snapshot_dir"
        else
            warn "Failed to create snapshot directory: $snapshot_dir"
            return 1
        fi
    fi
    
    return 0
}

# Create a system snapshot
# Parameters: snapshot_name
create_snapshot(){
    local name="${1:-}"
    
    if [ -z "$name" ]; then
        err "Snapshot name required"
        return 1
    fi
    
    # Validate snapshot name
    if ! validate_filename "$name"; then
        err "Invalid snapshot name: $name"
        return 1
    fi
    
    init_snapshot_system || return 1
    
    local snapshot_file="$SNAPSHOT_DIR/${name}.tar.gz"
    local temp_dir="/tmp/cad_snapshot_$$"
    
    pecho "$PASTEL_PURPLE" "Creating snapshot: $name"
    
    # Create temporary directory for snapshot data
    if ! mkdir -p "$temp_dir"; then
        err "Failed to create temporary directory"
        return 1
    fi
    
    # Collect system state
    info "Gathering system state..."
    
    # Save package lists
    if command -v dpkg >/dev/null 2>&1; then
        dpkg -l > "$temp_dir/packages.txt" 2>/dev/null || true
    fi
    
    # Save Termux configuration
    if [ -f "$HOME/.termux/termux.properties" ]; then
        cp "$HOME/.termux/termux.properties" "$temp_dir/" 2>/dev/null || true
    fi
    
    # Save bash configuration
    if [ -f "$HOME/.bashrc" ]; then
        cp "$HOME/.bashrc" "$temp_dir/" 2>/dev/null || true
    fi
    
    # Save git configuration
    if [ -f "$HOME/.gitconfig" ]; then
        cp "$HOME/.gitconfig" "$temp_dir/" 2>/dev/null || true
    fi
    
    # Save nano configuration
    if [ -f "$HOME/.nanorc" ]; then
        cp "$HOME/.nanorc" "$temp_dir/" 2>/dev/null || true
    fi
    
    # Save CAD state
    if [ -f "${STATE_JSON:-$HOME/.cad-droid-state.json}" ]; then
        cp "${STATE_JSON:-$HOME/.cad-droid-state.json}" "$temp_dir/cad-state.json" 2>/dev/null || true
    fi
    
    # Create metadata
    cat > "$temp_dir/metadata.json" << METADATA_EOF
{
  "name": "$name",
  "created": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')",
  "hostname": "$(hostname 2>/dev/null || echo 'unknown')",
  "termux_version": "$(termux-info 2>/dev/null | head -1 || echo 'unknown')",
  "script_version": "${SCRIPT_VERSION:-unknown}"
}
METADATA_EOF
    
    # Create compressed archive
    info "Creating archive..."
    if tar -czf "$snapshot_file" -C "$temp_dir" . 2>/dev/null; then
        ok "Snapshot created: $snapshot_file"
        pecho "$PASTEL_GREEN" "Snapshot '$name' saved successfully"
    else
        err "Failed to create snapshot archive"
        rm -rf "$temp_dir" 2>/dev/null || true
        return 1
    fi
    
    # Clean up
    rm -rf "$temp_dir" 2>/dev/null || true
    return 0
}

# Restore from a system snapshot
# Parameters: snapshot_name
restore_snapshot(){
    local name="${1:-}"
    
    if [ -z "$name" ]; then
        err "Snapshot name required"
        return 1
    fi
    
    local snapshot_file="$SNAPSHOT_DIR/${name}.tar.gz"
    
    if [ ! -f "$snapshot_file" ]; then
        err "Snapshot not found: $name"
        return 1
    fi
    
    pecho "$PASTEL_PURPLE" "Restoring snapshot: $name"
    
    local temp_dir="/tmp/cad_restore_$$"
    
    # Create temporary directory
    if ! mkdir -p "$temp_dir"; then
        err "Failed to create temporary directory"
        return 1
    fi
    
    # Extract snapshot
    info "Extracting snapshot..."
    if ! tar -xzf "$snapshot_file" -C "$temp_dir" 2>/dev/null; then
        err "Failed to extract snapshot"
        rm -rf "$temp_dir" 2>/dev/null || true
        return 1
    fi
    
    # Restore configurations
    info "Restoring configurations..."
    
    # Restore Termux properties
    if [ -f "$temp_dir/termux.properties" ]; then
        mkdir -p "$HOME/.termux" 2>/dev/null || true
        cp "$temp_dir/termux.properties" "$HOME/.termux/" 2>/dev/null || true
        info "Restored Termux properties"
    fi
    
    # Restore bash configuration
    if [ -f "$temp_dir/.bashrc" ]; then
        cp "$temp_dir/.bashrc" "$HOME/" 2>/dev/null || true
        info "Restored bash configuration"
    fi
    
    # Restore git configuration
    if [ -f "$temp_dir/.gitconfig" ]; then
        cp "$temp_dir/.gitconfig" "$HOME/" 2>/dev/null || true
        info "Restored git configuration"
    fi
    
    # Restore nano configuration
    if [ -f "$temp_dir/.nanorc" ]; then
        cp "$temp_dir/.nanorc" "$HOME/" 2>/dev/null || true
        info "Restored nano configuration"
    fi
    
    # Restore CAD state
    if [ -f "$temp_dir/cad-state.json" ]; then
        cp "$temp_dir/cad-state.json" "${STATE_JSON:-$HOME/.cad-droid-state.json}" 2>/dev/null || true
        info "Restored CAD state"
    fi
    
    ok "Snapshot '$name' restored successfully"
    pecho "$PASTEL_GREEN" "Please restart Termux to apply all changes"
    
    # Clean up
    rm -rf "$temp_dir" 2>/dev/null || true
    return 0
}

# List available snapshots
list_snapshots(){
    init_snapshot_system || return 1
    
    local snapshot_dir="${SNAPSHOT_DIR}"
    
    pecho "$PASTEL_PURPLE" "Available snapshots:"
    
    if [ ! -d "$snapshot_dir" ] || [ -z "$(ls -A "$snapshot_dir"/*.tar.gz 2>/dev/null)" ]; then
        info "No snapshots found"
        return 0
    fi
    
    local count=0
    for snapshot in "$snapshot_dir"/*.tar.gz; do
        if [ -f "$snapshot" ]; then
            local basename_snapshot
            basename_snapshot=$(basename "$snapshot" .tar.gz)
            local size
            size=$(stat -c%s "$snapshot" 2>/dev/null | awk '{printf "%.1fMB", $1/1024/1024}' 2>/dev/null || echo "unknown")
            local date
            date=$(stat -c%y "$snapshot" 2>/dev/null | cut -d' ' -f1 2>/dev/null || echo "unknown")
            
            pecho "$PASTEL_CYAN" "  • $basename_snapshot ($size, $date)"
            count=$((count + 1))
        fi
    done
    
    if [ "$count" -eq 0 ]; then
        info "No snapshots found"
    else
        pecho "$PASTEL_GREEN" "Total: $count snapshots"
    fi
    
    return 0
}

# Delete a snapshot
# Parameters: snapshot_name
delete_snapshot(){
    local name="${1:-}"
    
    if [ -z "$name" ]; then
        err "Snapshot name required"
        return 1
    fi
    
    local snapshot_file="$SNAPSHOT_DIR/${name}.tar.gz"
    
    if [ ! -f "$snapshot_file" ]; then
        err "Snapshot not found: $name"
        return 1
    fi
    
    if [ "$NON_INTERACTIVE" != "1" ]; then
        pecho "$PASTEL_PURPLE" "Delete snapshot '$name'? [y/N]"
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
    
    if rm "$snapshot_file" 2>/dev/null; then
        ok "Snapshot '$name' deleted"
    else
        err "Failed to delete snapshot: $name"
        return 1
    fi
    
    return 0
}

# Get snapshot information
# Parameters: snapshot_name
snapshot_info(){
    local name="${1:-}"
    
    if [ -z "$name" ]; then
        err "Snapshot name required"
        return 1
    fi
    
    local snapshot_file="$SNAPSHOT_DIR/${name}.tar.gz"
    
    if [ ! -f "$snapshot_file" ]; then
        err "Snapshot not found: $name"
        return 1
    fi
    
    pecho "$PASTEL_PURPLE" "Snapshot information: $name"
    
    local temp_dir="/tmp/cad_info_$$"
    mkdir -p "$temp_dir" 2>/dev/null || return 1
    
    # Extract metadata
    if tar -xzf "$snapshot_file" -C "$temp_dir" metadata.json 2>/dev/null; then
        if [ -f "$temp_dir/metadata.json" ] && command -v jq >/dev/null 2>&1; then
            jq -r '. | to_entries[] | "  \(.key): \(.value)"' "$temp_dir/metadata.json" 2>/dev/null || \
            cat "$temp_dir/metadata.json"
        fi
    fi
    
    local size
    size=$(stat -c%s "$snapshot_file" 2>/dev/null | awk '{printf "%.1fMB", $1/1024/1024}' 2>/dev/null || echo "unknown")
    info "Size: $size"
    
    rm -rf "$temp_dir" 2>/dev/null || true
    return 0
}