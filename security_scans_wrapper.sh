#!/bin/bash
set -eo pipefail

# --- Configuration ---
HOST_ROOT="/opt/mount" 
HOST_SCAN_DIR="${HOST_ROOT}/security_scans"
LOG_FILE="${HOST_SCAN_DIR}/security_scans.log"
SCANNER_CONTENT_DIR="/scanner_files/scc-5.10_rhel8_x86_64"

# --- SSH Configuration (NEW) ---
# We need this here for the final chown command
VM_IP="${VM_IP:-$(grep 'host.containers.internal' /etc/hosts | awk '{print $1}')}"
USERNAME="cpeinfra"
KEY_FILE="/opt/mount/id_rsa"
# -n = disconnects stdin
SSH_CMD="ssh -i ${KEY_FILE} -o StrictHostKeyChecking=no -o ServerAliveInterval=60 ${USERNAME}@${VM_IP}"

SCRIPTS_TO_RUN=(
    "/app/run_openScap.sh"
    "/app/run_STIG.sh"
)
SUCCESS_COUNT=0
FAILURE_COUNT=0
TOTAL_COUNT=${#SCRIPTS_TO_RUN[@]}

# --- Logging Function ---
print2log() {
    local message="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S.%6N")
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# --- Main Logic ---

# --- Cleanup Section ---
print2log "--- Cleaning up old log and result files ---"
rm -f "${HOST_SCAN_DIR}"/*.log 2>/dev/null || true
rm -f "${HOST_SCAN_DIR}"/output.txt 2>/dev/null || true
rm -rf "${HOST_SCAN_DIR}/openscap_results" 2>/dev/null || true
print2log "===== Security Scan Orchestrator Started ====="

# --- Host Preparation ---
print2log "Preparing host scan directory at ${HOST_SCAN_DIR}..."
mkdir -p "${HOST_SCAN_DIR}"
mkdir -p "${HOST_SCAN_DIR}/Resources/Results"
mkdir -p "${HOST_SCAN_DIR}/openscap_results"

print2log "Copying STIG scanner assets to shared volume..."
if [ -d "${SCANNER_CONTENT_DIR}/scc_5.10" ]; then
    cp -rn "${SCANNER_CONTENT_DIR}/scc_5.10"/* "${HOST_SCAN_DIR}/" 2>/dev/null || true
fi
if [ -f /scanner_files/U_RHEL_8_V2R1_STIG_SCAP_1-3_Benchmark.zip ]; then
    cp -n /scanner_files/U_RHEL_8_V2R1_STIG_SCAP_1-3_Benchmark.zip "${HOST_SCAN_DIR}/" 2>/dev/null || true
fi

print2log "Host preparation complete. Scanner tools are in place."
print2log "Total scripts to process: $TOTAL_COUNT"
print2log ""

# --- Script Execution Loop ---
for i in "${!SCRIPTS_TO_RUN[@]}"; do
    script_path="${SCRIPTS_TO_RUN[$i]}"
    script_name=$(basename "$script_path")
    count=$((i + 1))

    print2log "[$count/$TOTAL_COUNT] ===== Executing $script_name ====="
    
    if [ -x "$script_path" ]; then
        print2log "Launching $script_name..."
        
        # Temporarily disable exit-on-error to capture the exit code properly
        set +e
        ( "$script_path" ) # Run in a subshell
        exit_code=$?
        set -e

        if [ "$exit_code" -eq 0 ]; then
            print2log "SUCCESS: $script_name completed successfully."
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            print2log "ERROR: $script_name failed with exit code $exit_code."
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
        fi
    else
        print2log "ERROR: $script_name not found or not executable"
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
    fi
    
    print2log "[$count/$TOTAL_COUNT] ===== $script_name execution completed ====="
    print2log ""
done

print2log ""

print2log "===== All Scans Finished ====="
print2log "Total scripts processed: $TOTAL_COUNT"
print2log "Successful scripts: $SUCCESS_COUNT"
print2log "Failed scripts: $FAILURE_COUNT"
print2log "=============================="
print2log ""

# --- Final Ownership Change (NEW) ---
print2log "Attempting to change ownership of ${HOST_SCAN_DIR} to ${USERNAME}..."
if [ -z "$VM_IP" ]; then
  print2log "ERROR: Could not determine VM_IP. Skipping ownership change."
elif [ "$FAILURE_COUNT" -gt 0 ]; then
  print2log "WARNING: Scans failed. Skipping ownership change."
else
  # Use sudo to chown the directory on the host
  COMMAND_TO_RUN="sudo chown -R ${USERNAME}:${USERNAME} ${HOST_SCAN_DIR}"
  if ! $SSH_CMD "$COMMAND_TO_RUN"; then
      print2log "WARNING: Failed to change ownership of ${HOST_SCAN_DIR}."
  else
      print2log "SUCCESS: Ownership changed to ${USERNAME}."
  fi
fi

if [ "$FAILURE_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0