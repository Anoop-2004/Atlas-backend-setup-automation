#!/usr/bin/env bash
# Checkpoint and state management for resumable execution

STATE_FILE="${STATE_FILE:-./setup/state/checkpoint.json}"

# Initialize checkpoint file
init_checkpoint() {
    local state_dir
    state_dir=$(dirname "$STATE_FILE")
    ensure_dir "$state_dir"
    
    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" <<EOF
{
  "version": "1.0.0",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "current_phase": null,
  "current_step": null,
  "completed_phases": [],
  "completed_steps": [],
  "failed_steps": []
}
EOF
        log_info "Checkpoint initialized: $STATE_FILE"
    fi
}

# Update checkpoint field
update_checkpoint() {
    local field="$1"
    local value="$2"
    
    # Use jq if available, otherwise use sed
    if command_exists jq; then
        local tmp_file="${STATE_FILE}.tmp"
        jq --arg val "$value" \
           --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           ".$field = \$val | .last_updated = \$time" \
           "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"
    else
        # Fallback: simple sed replacement (less robust)
        sed -i.bak "s/\"$field\": \"[^\"]*\"/\"$field\": \"$value\"/" "$STATE_FILE"
        rm -f "${STATE_FILE}.bak"
    fi
}

# Add to array in checkpoint
add_to_checkpoint_array() {
    local field="$1"
    local value="$2"
    
    if command_exists jq; then
        local tmp_file="${STATE_FILE}.tmp"
        jq --arg val "$value" \
           --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           ".$field += [\$val] | .last_updated = \$time" \
           "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"
    fi
}

# Check if step is completed
is_step_completed() {
    local step="$1"
    
    if command_exists jq; then
        jq -e --arg step "$step" '.completed_steps | index($step)' "$STATE_FILE" >/dev/null 2>&1
        return $?
    else
        grep -q "\"$step\"" "$STATE_FILE"
        return $?
    fi
}

# Check if phase is completed
is_phase_completed() {
    local phase="$1"
    
    if command_exists jq; then
        jq -e --arg phase "$phase" '.completed_phases | index($phase)' "$STATE_FILE" >/dev/null 2>&1
        return $?
    else
        grep -q "\"$phase\"" "$STATE_FILE"
        return $?
    fi
}

# Mark step as completed
mark_step_completed() {
    local step="$1"
    
    if ! is_step_completed "$step"; then
        add_to_checkpoint_array "completed_steps" "$step"
        update_checkpoint "current_step" "null"
        log_info "Checkpoint: Step completed - $step"
    fi
}

# Mark phase as completed
mark_phase_completed() {
    local phase="$1"
    
    if ! is_phase_completed "$phase"; then
        add_to_checkpoint_array "completed_phases" "$phase"
        update_checkpoint "current_phase" "null"
        log_info "Checkpoint: Phase completed - $phase"
    fi
}

# Set current phase
set_current_phase() {
    local phase="$1"
    update_checkpoint "current_phase" "$phase"
}

# Set current step
set_current_step() {
    local step="$1"
    update_checkpoint "current_step" "$step"
}

# Record failed step
record_failed_step() {
    local step="$1"
    add_to_checkpoint_array "failed_steps" "$step"
}

# Get checkpoint summary
show_checkpoint_summary() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "No checkpoint file found"
        return
    fi
    
    echo ""
    echo "=== Setup State Summary ==="
    
    if command_exists jq; then
        echo "Last Updated: $(jq -r '.last_updated' "$STATE_FILE")"
        echo "Completed Phases: $(jq -r '.completed_phases | length' "$STATE_FILE")"
        echo "Completed Steps: $(jq -r '.completed_steps | length' "$STATE_FILE")"
        echo "Failed Steps: $(jq -r '.failed_steps | length' "$STATE_FILE")"
        
        local current_phase
        current_phase=$(jq -r '.current_phase' "$STATE_FILE")
        if [ "$current_phase" != "null" ]; then
            echo "Current Phase: $current_phase"
        fi
        
        local current_step
        current_step=$(jq -r '.current_step' "$STATE_FILE")
        if [ "$current_step" != "null" ]; then
            echo "Current Step: $current_step"
        fi
    else
        cat "$STATE_FILE"
    fi
    
    echo "=========================="
    echo ""
}

# Reset checkpoint
reset_checkpoint() {
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        log_info "Checkpoint reset"
    fi
    init_checkpoint
}

# Execute step with checkpoint
execute_step() {
    local step_name="$1"
    local step_func="$2"
    
    # Check if already completed
    if is_step_completed "$step_name"; then
        log_skip "$step_name (already completed)"
        return 0
    fi
    
    # Set current step
    set_current_step "$step_name"
    log_step "$step_name"
    
    # Execute step function
    if $step_func; then
        mark_step_completed "$step_name"
        return 0
    else
        record_failed_step "$step_name"
        log_error "Step failed: $step_name"
        return 1
    fi
}

# Execute phase with checkpoint
execute_phase() {
    local phase_name="$1"
    shift
    local steps=("$@")
    
    # Check if already completed
    if is_phase_completed "$phase_name"; then
        log_skip "Phase: $phase_name (already completed)"
        return 0
    fi
    
    # Set current phase
    set_current_phase "$phase_name"
    log_phase "$phase_name"
    
    # Execute all steps
    local failed=0
    for step in "${steps[@]}"; do
        if ! execute_step "$step" "$step"; then
            failed=1
            break
        fi
    done
    
    if [ $failed -eq 0 ]; then
        mark_phase_completed "$phase_name"
        log_info "Phase completed: $phase_name"
        return 0
    else
        log_error "Phase failed: $phase_name"
        return 1
    fi
}