# CAD-Droid Module System

This directory contains the modularized components of the CAD-Droid setup script. The original monolithic `setup.sh` script has been refactored into logical, reusable modules for better maintainability and clarity.

## Module Structure

### Core Foundation Modules

#### constants.sh
- **Purpose**: Global variables, configuration constants, and environment settings
- **Contents**: Feature flags, timeouts, package lists, color palettes, state variables
- **Dependencies**: None (loaded first)
- **Key Variables**: `CORE_PACKAGES`, `PASTEL_HEX`, `VIBRANT_HEX`, all global state vars

#### utils.sh  
- **Purpose**: Safe arithmetic, validation functions, and utility operations
- **Contents**: Input validation, safe math operations, array handling, environment setup
- **Dependencies**: Constants
- **Key Functions**: `safe_calc()`, `validate_input()`, `sanitize_string()`, `ask_yes_no()`

#### logging.sh
- **Purpose**: Structured logging, output formatting, and progress display  
- **Contents**: Message functions, JSON logging, duration formatting, disk space checks
- **Dependencies**: Constants, Utils
- **Key Functions**: `info()`, `warn()`, `err()`, `log_event()`, `format_duration()`

#### color.sh
- **Purpose**: Terminal color support, visual effects, and UI components
- **Contents**: RGB handling, gradients, cards, terminal detection, text formatting
- **Dependencies**: Constants, Utils, Logging
- **Key Functions**: `rgb_seq()`, `gradient_line()`, `draw_card()`, `supports_truecolor()`

#### spinner.sh
- **Purpose**: Progress tracking, step management, and animated displays
- **Contents**: Step registration, progress calculation, execution engine, summary reporting
- **Dependencies**: Constants, Utils, Logging, Color
- **Key Functions**: `cad_register_step()`, `run_with_progress()`, `execute_all_steps()`

### Specialized Modules

#### termux_props.sh
- **Purpose**: Termux-specific configuration and Android system integration
- **Contents**: Phone detection, API interaction, properties setup, file management
- **Dependencies**: All core modules
- **Key Functions**: `detect_phone()`, `configure_termux_properties()`, `wait_for_termux_api()`

#### apk.sh
- **Purpose**: APK download, F-Droid/GitHub integration, and file verification
- **Contents**: HTTP downloads, API clients, batch operations, integrity checks
- **Dependencies**: Core modules, Termux Props
- **Key Functions**: `fetch_fdroid_api()`, `fetch_github_release()`, `batch_download_apks()`

#### adb.sh  
- **Purpose**: Android Debug Bridge wireless setup and device management
- **Contents**: Network detection, port scanning, device pairing, connection management
- **Dependencies**: Core modules, Termux Props
- **Key Functions**: `adb_wireless_helper()`, `pair_adb_device()`, `scan_device_ports()`

#### core_packages.sh
- **Purpose**: Package installation, APT operations, and system maintenance
- **Contents**: Mirror management, package operations, system updates, tool installation
- **Dependencies**: Core modules
- **Key Functions**: `step_mirror()`, `install_core_packages()`, `apt_install_if_needed()`

#### nano.sh
- **Purpose**: Nano text editor configuration and setup
- **Contents**: Editor configuration, syntax highlighting, key bindings, alternatives
- **Dependencies**: Core modules
- **Key Functions**: `configure_nano_editor()`, `setup_custom_syntax()`, `set_nano_as_default()`

## Module Loading Order

The modules must be sourced in dependency order to ensure all required functions and variables are available:

```bash
# 1. Foundation layer
source modules/constants.sh
source modules/utils.sh

# 2. Core functionality  
source modules/logging.sh
source modules/color.sh
source modules/spinner.sh

# 3. Specialized modules (can be loaded in any order)
source modules/termux_props.sh
source modules/apk.sh
source modules/adb.sh
source modules/core_packages.sh
source modules/nano.sh

# Additional modules would be loaded here...
```

## Module Design Principles

### Inclusion Guards
Each module uses inclusion guards to prevent multiple loading:
```bash
if [ -n "${_CAD_MODULE_NAME_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_MODULE_NAME_LOADED=1
```

### Dependency Management
- Modules declare their dependencies in comments
- Core modules are loaded first
- Specialized modules can reference any core functionality
- No circular dependencies are allowed

### Function Naming
- Module-specific functions use descriptive names
- Step functions follow the `step_*` pattern
- Internal helper functions use module prefixes when needed
- Public API functions are documented

### Error Handling
- All modules use consistent error handling patterns
- Functions return 0 for success, non-zero for failure
- Critical errors use `err()` and may exit
- Warnings use `warn()` and continue execution

### Configuration
- Module behavior is controlled by global variables from constants.sh
- Environment variables can override defaults
- Debug output is controlled by `DEBUG` variable

## Usage in Main Script

The main `setup.sh` becomes a thin orchestrator:

```bash
#!/usr/bin/env bash
# Load all modules
for module in constants utils logging color spinner termux_props apk adb core_packages nano; do
    source "modules/${module}.sh"
done

# Apply validations
validate_curl_timeouts
validate_timeout_vars
validate_spinner_delay
validate_apk_size

# Initialize color support
init_pastel_colors

# Register and execute steps
main_execution "$@"
```

## Testing and Validation

Each module can be tested independently:
- Source the module and its dependencies
- Call individual functions with test data
- Verify expected behavior and error handling
- Check that global variables are set correctly

## Future Extensions

New modules should follow the established patterns:
- Include proper guards and dependencies
- Use consistent error handling
- Document public functions
- Follow the naming conventions
- Add to this README when complete

## Module Status

- [COMPLETE] **constants.sh** - Complete (129 lines)
- [COMPLETE] **utils.sh** - Complete (341 lines)  
- [COMPLETE] **logging.sh** - Complete (364 lines)
- [COMPLETE] **color.sh** - Complete (446 lines)
- [COMPLETE] **spinner.sh** - Complete (380 lines)
- [COMPLETE] **termux_props.sh** - Complete (429 lines)
- [COMPLETE] **apk.sh** - Complete (497 lines)
- [COMPLETE] **adb.sh** - Complete (517 lines)
- [COMPLETE] **core_packages.sh** - Complete (350 lines)
- [COMPLETE] **nano.sh** - Complete (280 lines)

**Total**: 3,933 lines across 10 modules (originally 5,484 lines in single file)

## Benefits of Modularization

1. **Maintainability**: Each module has a focused responsibility
2. **Reusability**: Modules can be used independently or in other projects
3. **Testing**: Individual components can be tested in isolation
4. **Readability**: Code is organized by logical function groups
5. **Collaboration**: Multiple developers can work on different modules
6. **Debugging**: Issues can be traced to specific modules
7. **Extension**: New functionality can be added without affecting existing code