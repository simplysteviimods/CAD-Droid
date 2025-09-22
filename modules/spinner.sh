#!/usr/bin/env bash
###############################################################################
# CAD-Droid Spinner Module
# Progress tracking, step management, and animated progress displays
###############################################################################

# Prevent multiple inclusion
if [ -n "${_CAD_SPINNER_LOADED:-}" ]; then
    return 0
fi
readonly _CAD_SPINNER_LOADED=1

# === Step Registration and Management ===

# Register a new installation step
# Parameters: step_name, function_name, estimated_time_seconds
cad_register_step(){ 
  STEP_NAME+=("${1:-}")
  STEP_FUNCS+=("${2:-}")
  local eta="${3:-30}"
  
  # Validate eta is numeric
  case "$eta" in
    *[!0-9]*) eta=30 ;;
    *) [ "$eta" -lt 1 ] && eta=30 ;;
  esac
  
  STEP_ETA+=("$eta")
}

# Recalculate total steps and estimated time with safe arithmetic
# Call this after registering all steps
recompute_totals(){ 
  TOTAL_STEPS=${#STEP_NAME[@]}
  TOTAL_EST=0
  
  # Sum all step estimates safely
  local i=0
  while [ "$i" -lt "$TOTAL_STEPS" ]; do
    local step_eta="${STEP_ETA[$i]:-30}"
    # Validate step_eta is numeric
    case "$step_eta" in
      *[!0-9]*) step_eta=30 ;;
    esac
    
    # Safe addition with overflow protection
    local new_total
    new_total=$(add_int "$TOTAL_EST" "$step_eta")
    if [ $? -eq 0 ]; then
      TOTAL_EST="$new_total"
    fi
    
    i=$(add_int "$i" 1) || break
  done
}

# === Step Execution Control ===

# Mark the beginning of a step with timing
start_step(){
  local step_idx="${1:-$CURRENT_STEP_INDEX}"
  
  # Validate step index
  if ! is_nonneg_int "$step_idx" || [ "$step_idx" -ge "${#STEP_NAME[@]}" ]; then
    return 1
  fi
  
  # Record start time
  STEP_START_TIME["$step_idx"]=$(date +%s 2>/dev/null || echo 0)
  
  # Log step start
  local step_name="${STEP_NAME[$step_idx]:-unknown}"
  log_event step_start "$step_idx" start "$step_name"
  
  # Show step header
  draw_phase_header "Step $((step_idx + 1))/$TOTAL_STEPS: $step_name"
}

# Mark the end of a step and calculate duration
end_step(){
  local step_idx="${1:-$CURRENT_STEP_INDEX}"
  
  # Validate step index
  if ! is_nonneg_int "$step_idx" || [ "$step_idx" -ge "${#STEP_NAME[@]}" ]; then
    return 1
  fi
  
  # Calculate duration
  local start_time="${STEP_START_TIME[$step_idx]:-0}"
  local end_time=$(date +%s 2>/dev/null || echo 0)
  local duration=0
  
  if [ "$start_time" -gt 0 ] && [ "$end_time" -ge "$start_time" ]; then
    duration=$((end_time - start_time))
  fi
  
  # Record duration
  STEP_END_TIME["$step_idx"]="$end_time"
  STEP_DURATIONS["$step_idx"]="$duration"
  
  # Default status to success if not already set
  if [ -z "${STEP_STATUS[$step_idx]:-}" ]; then
    STEP_STATUS["$step_idx"]="success"
  fi
  
  # Log step completion
  local step_name="${STEP_NAME[$step_idx]:-unknown}"
  local status="${STEP_STATUS[$step_idx]:-success}"
  log_event step_end "$step_idx" "$status" "$step_name" "$duration"
  
  # Show completion message
  local duration_str
  duration_str=$(format_duration "$duration")
  case "$status" in
    success) ok "Completed: $step_name ($duration_str)" ;;
    warning) warn "Completed with warnings: $step_name ($duration_str)" ;;
    *) err "Failed: $step_name ($duration_str)" ;;
  esac
}

# Set the status of a step
# Parameters: status (success/warning/error)
mark_step_status() {
  local status="${1:-success}"
  local step_idx="${CURRENT_STEP_INDEX:-0}"
  
  # Validate step index
  if is_nonneg_int "$step_idx" && [ "$step_idx" -lt "${#STEP_NAME[@]}" ]; then
    STEP_STATUS["$step_idx"]="$status"
  fi
}

# === Progress Calculation ===

# Calculate overall progress percentage
calculate_progress() {
  local completed_steps="${1:-0}"
  local current_step_progress="${2:-0}"
  
  # Validate inputs
  case "$completed_steps" in *[!0-9]*) completed_steps=0 ;; esac
  case "$current_step_progress" in *[!0-9]*) current_step_progress=0 ;; esac
  
  # Prevent division by zero
  if [ "$TOTAL_STEPS" -le 0 ]; then
    echo "0"
    return
  fi
  
  # Calculate base progress from completed steps
  local base_progress
  base_progress=$(safe_progress_div "$completed_steps" "$TOTAL_STEPS")
  
  # Add fractional progress from current step
  local step_fraction=0
  if [ "$TOTAL_STEPS" -gt 0 ] && [ "$current_step_progress" -gt 0 ]; then
    step_fraction=$(safe_progress_div "$current_step_progress" "$TOTAL_STEPS")
  fi
  
  # Combine and ensure bounds
  local total_progress=$((base_progress + step_fraction))
  if [ "$total_progress" -gt 100 ]; then
    total_progress=100
  fi
  
  echo "$total_progress"
}

# === Step Finding and Validation ===

# Find step index by number or name
# Parameters: identifier (number or name)
# Returns: step index or -1 if not found
find_step_index() {
  local identifier="$1"
  
  # Try as numeric index first (1-based input, convert to 0-based)
  if [[ "$identifier" =~ ^[0-9]+$ ]]; then
    local idx=$((identifier - 1))
    if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#STEP_NAME[@]}" ]; then
      echo "$idx"
      return 0
    fi
  fi
  
  # Try as step name
  local i=0
  while [ "$i" -lt "${#STEP_NAME[@]}" ]; do
    if [ "${STEP_NAME[$i]}" = "$identifier" ]; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  
  echo "-1"
  return 1
}

# Validate that a step function exists
validate_step_function() {
  local func_name="$1"
  
  # Check if function is defined
  if declare -f "$func_name" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# === Progress Animation ===

# Display a simple progress bar
show_progress_bar() {
  local current="${1:-0}" total="${2:-100}" width="${3:-40}"
  
  # Validate inputs
  case "$current" in *[!0-9]*) current=0 ;; esac
  case "$total" in *[!0-9]*) total=100 ;; esac
  case "$width" in *[!0-9]*) width=40 ;; esac
  
  # Prevent division by zero
  if [ "$total" -eq 0 ]; then
    total=1
  fi
  
  # Calculate filled portion
  local filled
  filled=$(safe_progress_div "$current" "$total")
  local filled_width=$((filled * width / 100))
  
  # Ensure bounds
  if [ "$filled_width" -gt "$width" ]; then
    filled_width="$width"
  fi
  
  # Draw progress bar
  printf "["
  
  # Filled portion
  local i=0
  while [ "$i" -lt "$filled_width" ]; do
    printf "="
    i=$((i + 1))
  done
  
  # Empty portion
  while [ "$i" -lt "$width" ]; do
    printf " "
    i=$((i + 1))
  done
  
  printf "] %3d%%\n" "$filled"
}

# === Countdown and Delays ===

# Display a countdown with message
countdown_prompt() {
  local message="$1" seconds="${2:-5}"
  
  # Validate seconds is numeric
  case "$seconds" in
    *[!0-9]*) seconds=5 ;;
  esac
  
  local i="$seconds"
  while [ "$i" -gt 0 ]; do
    printf "\r%s (%d seconds remaining)..." "$message" "$i"
    safe_sleep 1
    i=$((i - 1))
  done
  printf "\r%s                                \n" "$message"
}

# === Summary and Reporting ===

# Calculate and display basic step statistics
show_step_statistics() {
  local total_duration=0 success_count=0 warning_count=0 error_count=0
  
  # Calculate statistics
  local i=0
  while [ "$i" -lt "${#STEP_NAME[@]}" ]; do
    local duration="${STEP_DURATIONS[$i]:-0}"
    local status="${STEP_STATUS[$i]:-unknown}"
    
    # Validate and accumulate duration
    case "$duration" in
      *[!0-9]*) duration=0 ;;
    esac
    total_duration=$((total_duration + duration))
    
    # Count by status
    case "$status" in
      success) success_count=$((success_count + 1)) ;;
      warning) warning_count=$((warning_count + 1)) ;;
      error|fail*) error_count=$((error_count + 1)) ;;
    esac
    
    i=$((i + 1))
  done
  
  # Simple completion message
  info "Setup completed in $(format_duration $total_duration)"
  info "Steps: $success_count successful, $warning_count warnings, $error_count errors"
}

# === Step Execution Engine ===

# Execute a single step by index
execute_step() {
  local step_idx="$1"
  
  # Validate step index
  if ! is_nonneg_int "$step_idx" || [ "$step_idx" -ge "${#STEP_NAME[@]}" ]; then
    err "Invalid step index: $step_idx"
    return 1
  fi
  
  # Set current step
  CURRENT_STEP_INDEX="$step_idx"
  
  # Get step details
  local step_name="${STEP_NAME[$step_idx]}"
  local step_func="${STEP_FUNCS[$step_idx]}"
  
  # Start the step
  start_step "$step_idx"
  
  # Execute step function if it exists
  if validate_step_function "$step_func"; then
    # Run the step function
    if "$step_func"; then
      mark_step_status "success"
    else
      mark_step_status "error"
    fi
  else
    warn "Step function $step_func not found"
    mark_step_status "error"
  fi
  
  # Complete the step
  end_step "$step_idx"
  
  # Return success/failure based on step status
  case "${STEP_STATUS[$step_idx]}" in
    success) return 0 ;;
    *) return 1 ;;
  esac
}

# Execute all registered steps in order
execute_all_steps() {
  local step_count="${#STEP_NAME[@]}"
  local main_step_index=0
  
  info "Starting installation with $step_count steps..."
  [ "${DEBUG_STEPS:-0}" = "1" ] && echo "DEBUG: Step execution starting with step_count=$step_count" >&2
  
  while [ "$main_step_index" -lt "$step_count" ]; do
    [ "${DEBUG_STEPS:-0}" = "1" ] && echo "DEBUG: About to execute step $main_step_index (${STEP_NAME[$main_step_index]:-UNKNOWN}) - current step_count=$step_count" >&2
    
    if ! execute_step "$main_step_index"; then
      # Step failed - decide whether to continue or abort
      local step_name="${STEP_NAME[$main_step_index]}"
      if ask_yes_no "Step '$step_name' failed. Continue with remaining steps?" "y"; then
        warn "Continuing despite failure in step: $step_name"
      else
        err "Installation aborted at step: $step_name"
        return 1
      fi
    fi
    
    [ "${DEBUG_STEPS:-0}" = "1" ] && echo "DEBUG: Completed step $main_step_index, about to increment" >&2
    
    # Safe increment
    main_step_index=$(add_int "$main_step_index" 1) || break
    
    [ "${DEBUG_STEPS:-0}" = "1" ] && echo "DEBUG: Incremented to main_step_index=$main_step_index, step_count is now ${#STEP_NAME[@]}" >&2
    
    # Update progress
    local progress
    progress=$(calculate_progress "$main_step_index" 0)
    debug "Progress: $progress% ($main_step_index/$step_count steps)"
  done
  
  [ "${DEBUG_STEPS:-0}" = "1" ] && echo "DEBUG: Step execution loop finished with main_step_index=$main_step_index, step_count=${#STEP_NAME[@]}" >&2
  
  # Show basic statistics - detailed completion handled by completion module
  show_step_statistics
  return 0
}