#!/usr/bin/env bash
###############################################################################
# CAD-Droid Nano Editor Module
# Nano text editor configuration and setup
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_NANO_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_NANO_LOADED=1

# === Nano Configuration ===

# Configure nano editor with enhanced settings
configure_nano_editor(){
  pecho "$PASTEL_PURPLE" "Setting up a nice text editor for you..."
  
  # Make Nano much more pleasant to use
  cat > "$HOME/.nanorc" << 'NANO_CONFIG_EOF'
# Your personal Nano editor configuration
# This makes editing files much more enjoyable
#
# Load all the built-in syntax highlighting
include "/data/data/com.termux/files/usr/share/nano/*.nanorc"

# Interface improvements that make editing easier
set titlebar        # Show the filename at the top
set statusbar       # Show helpful info at the bottom  
set linenumbers     # Show line numbers on the left
set softwrap        # Wrap long lines nicely
# Show cursor position constantly
set constantshow
# Enable smooth scrolling
set smooth

# ===== EDITING BEHAVIOR =====
# Set tab size to 2 spaces (common for development)
set tabsize 2
# Convert tabs to spaces
set tabstospaces
# Enable auto-indentation
set autoindent
# Enable smart home key
set smarthome
# Use cut-to-end-of-line by default
set cutfromcursor

# ===== MOUSE AND INPUT =====
# Enable mouse support for selections and positioning
set mouse
# Enable multi-file buffer editing
set multibuffer

# ===== SEARCH SETTINGS =====
# Case-sensitive search by default
set casesensitive
# Enable regular expression search
set regexp

# ===== FILE HANDLING =====
# Create backup files
set backup
# Store backups in dedicated directory
set backupdir "~/.nano_backups"

# ===== HELPFUL FEATURES =====
# Highlight trailing whitespace
set trimblanks
# Use bold text for better visibility
set boldtext
# Enable word wrapping indicator
set indicator
# Automatically add newline at end of file
set finalnewline

# ===== SYNTAX HIGHLIGHTING CUSTOMIZATION =====
# Pastel color scheme for syntax highlighting

# Set title bar color to pastel pink
set titlecolor pink,white
# Set status bar to pastel cyan
set statuscolor cyan,white
# Set key combo color to pastel lavender
set keycolor magenta,white
# Set function color to pastel green
set functioncolor green,white
# Set number color to pastel yellow
set numbercolor yellow,black
# Set selected text color to pastel purple
set selectedcolor white,magenta
# Set stripe color for line numbers
set stripecolor yellow,black

# Enhanced syntax highlighting patterns
syntax "config" "\.(conf|config|cfg|ini)$"
color brightcyan "^[[:space:]]*[^=]*="
color yellow "=.*$"
color green "^[[:space:]]*#.*$"
color brightred "^[[:space:]]*\[.*\]$"

syntax "shell" "\.sh$"
header "^#!.*/(ba|da|a|k|pdk|z)?sh[-0-9_]*"
color green "^[[:space:]]*#.*$"
color yellow "\$\{[^}]*\}"
color yellow "\$[A-Za-z0-9_!@#$*?-]+"
color brightblue "^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*\("
color brightcyan "^[[:space:]]*(case|do|done|elif|else|esac|fi|for|function|if|in|select|then|until|while)"
color brightmagenta "^[[:space:]]*(break|continue|declare|echo|eval|exec|exit|export|getopts|hash|pwd|readonly|return|shift|test|times|trap|umask|unset)"

# ===== KEY BINDINGS =====
# More familiar shortcuts
bind ^Q exit all           # Ctrl+Q to quit
bind ^S writeout all       # Ctrl+S to save
bind ^O insert all         # Ctrl+O to open file
bind ^F whereis all        # Ctrl+F to search
bind ^G findnext all       # Ctrl+G to find next
bind ^R replace all        # Ctrl+R to replace
bind ^Z suspend main       # Ctrl+Z to suspend
bind ^X cut all           # Ctrl+X to cut
bind ^C copy all          # Ctrl+C to copy  
bind ^V uncut all         # Ctrl+V to paste
bind ^A mark all          # Ctrl+A to select all
bind ^L refresh all       # Ctrl+L to refresh screen

# Movement shortcuts
bind ^B pageup all        # Ctrl+B for page up
bind ^N pagedown all      # Ctrl+N for page down
bind ^P prevpage all      # Ctrl+P for previous page
bind ^E nextpage all      # Ctrl+E for next page

# ===== ADDITIONAL FEATURES =====
# Show whitespace characters
set whitespace "··"
# Enable undo/redo functionality
set historylog
# Set history log location
set historylog

# ===== TERMINAL COMPATIBILITY =====
# Fix common terminal issues
set zap
# Gentle color support
set titlecolor brightmagenta
set statuscolor brightcyan
set errorcolor brightwhite,red
set selectedcolor brightwhite
set numbercolor cyan
set keycolor brightcyan
set functioncolor yellow

NANO_CONFIG_EOF

  # Create backup directory for nano
  mkdir -p "$HOME/.nano_backups" 2>/dev/null || true
  
  # Set proper permissions
  chmod 644 "$HOME/.nanorc" 2>/dev/null || true
  chmod 755 "$HOME/.nano_backups" 2>/dev/null || true
  
  # Test nano configuration
  if nano --version >/dev/null 2>&1; then
    ok "Nano editor configured successfully"
    pecho "$PASTEL_PURPLE" "Nano features enabled:"
    info "  • Syntax highlighting for many languages"
    info "  • Line numbers and status bar"
    info "  • Mouse support for selections"
    info "  • Auto-backup in ~/.nano_backups/"
    info "  • Familiar keyboard shortcuts (Ctrl+S to save, Ctrl+Q to quit)"
    info "  • Smart indentation and tab handling"
  else
    warn "Nano may not be installed properly"
  fi
}

# === Nano Utility Functions ===

# Install nano if not present
install_nano(){
  if command -v nano >/dev/null 2>&1; then
    debug "Nano already installed"
    return 0
  fi
  
  info "Installing nano text editor..."
  
  # Ensure selected mirror is applied before installing nano
  if command -v ensure_mirror_applied >/dev/null 2>&1; then
    ensure_mirror_applied
  fi
  
  if command -v pkg >/dev/null 2>&1; then
    if run_with_progress "Install nano (pkg)" 10 bash -c 'pkg install -y nano >/dev/null 2>&1 || [ $? -eq 100 ]'; then
      ok "Nano installed successfully via pkg"
      return 0
    fi
  fi
  
  # Fallback to apt - also handle exit code 100
  if run_with_progress "Install nano (apt)" 10 bash -c 'yes | apt install -y nano >/dev/null 2>&1 || [ $? -eq 100 ]'; then
    ok "Nano installed successfully via apt"
    return 0
  else
    warn "Failed to install nano"
    return 1
  fi
}

# Verify nano configuration
verify_nano_config(){
  local config_file="$HOME/.nanorc"
  local backup_dir="$HOME/.nano_backups"
  
  # Check if config file exists and is readable
  if [ ! -f "$config_file" ]; then
    warn "Nano configuration file not found: $config_file"
    return 1
  fi
  
  if [ ! -r "$config_file" ]; then
    warn "Nano configuration file not readable: $config_file"
    return 1
  fi
  
  # Check if backup directory exists
  if [ ! -d "$backup_dir" ]; then
    info "Creating nano backup directory: $backup_dir"
    mkdir -p "$backup_dir" 2>/dev/null || true
  fi
  
  # Test nano with config
  if nano --version >/dev/null 2>&1; then
    debug "Nano configuration verified"
    return 0
  else
    warn "Nano not working properly"
    return 1
  fi
}

# Reset nano configuration to defaults
reset_nano_config(){
  local config_file="$HOME/.nanorc"
  local backup_dir="$HOME/.nano_backups"
  
  info "Resetting nano configuration to defaults..."
  
  # Backup existing config if present
  if [ -f "$config_file" ]; then
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  fi
  
  # Remove custom configuration
  rm -f "$config_file" 2>/dev/null || true
  
  # Clean up backup directory
  if [ -d "$backup_dir" ]; then
    rm -rf "$backup_dir" 2>/dev/null || true
  fi
  
  ok "Nano configuration reset to defaults"
}

# === Advanced Nano Features ===

# Create custom syntax highlighting for specific file types
setup_custom_syntax(){
  local syntax_dir="$HOME/.nano_syntax"
  
  # Create custom syntax directory
  mkdir -p "$syntax_dir" 2>/dev/null || true
  
  # Add custom syntax for common development files
  cat > "$syntax_dir/dockerfile.nanorc" << 'DOCKERFILE_SYNTAX_EOF'
# Dockerfile syntax highlighting
syntax "Dockerfile" "Dockerfile[^/]*$" "\.dockerfile$"
comment "#"

# Instructions
color brightblue "^(FROM|MAINTAINER|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)"
# Strings
color yellow ""(\\.|[^"])*""
color yellow "'(\\.|[^'])*'"
# Comments
color brightblack "(^|[[:space:]])#.*$"
# Variables
color brightred "\$[0-9A-Z_!@#$*?-]+"
color brightred "\$\{[0-9A-Z_!@#$*?-]+\}"
DOCKERFILE_SYNTAX_EOF

  # Add to main config
  if ! grep -q "$syntax_dir" "$HOME/.nanorc" 2>/dev/null; then
    echo "# Custom syntax files" >> "$HOME/.nanorc"
    echo "include \"$syntax_dir/*.nanorc\"" >> "$HOME/.nanorc"
  fi
  
  debug "Custom syntax highlighting configured"
}

# === Editor Alternatives ===

# Setup vim as alternative editor
setup_vim_alternative(){
  if ! command -v vim >/dev/null 2>&1; then
    info "Installing vim as alternative editor..."
    
    # Ensure selected mirror is applied before installing vim
    if command -v ensure_mirror_applied >/dev/null 2>&1; then
      ensure_mirror_applied
    fi
    
    if command -v pkg >/dev/null 2>&1; then
      run_with_progress "Install vim (pkg)" 15 bash -c 'pkg install -y vim >/dev/null 2>&1' || true
    else
      run_with_progress "Install vim (apt)" 15 bash -c 'yes | apt install -y vim >/dev/null 2>&1' || true
    fi
  fi
  
  # Create basic vim config
  if command -v vim >/dev/null 2>&1; then
    cat > "$HOME/.vimrc" << 'VIM_CONFIG_EOF'
" Basic vim configuration
set number
set syntax=on
set tabstop=2
set shiftwidth=2
set expandtab
set autoindent
set hlsearch
set incsearch
set mouse=a
colorscheme desert
VIM_CONFIG_EOF
    
    debug "Vim configured as alternative editor"
  fi
}

# === Editor Environment Setup ===

# Set nano as default editor
set_nano_as_default(){
  # Set EDITOR environment variable
  local bashrc="$HOME/.bashrc"
  
  if ! grep -q "export EDITOR=nano" "$bashrc" 2>/dev/null; then
    echo "" >> "$bashrc"
    echo "# Set nano as default editor" >> "$bashrc"
    echo "export EDITOR=nano" >> "$bashrc"
    echo "export VISUAL=nano" >> "$bashrc"
  fi
  
  # Set for current session
  export EDITOR=nano
  export VISUAL=nano
  
  debug "Nano set as default editor"
}