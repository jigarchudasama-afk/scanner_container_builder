#!/bin/bash
set -eo pipefail

# --- Configuration ---
HOST_ROOT="/opt/mount"
HOST_SCAN_DIR="${HOST_ROOT}/security_scans"
LOG_FILE="${HOST_SCAN_DIR}/stig_scan.log"

# --- SSH Configuration ---
VM_IP="${VM_IP:-$(grep 'host.containers.internal' /etc/hosts | awk '{print $1}')}"
USERNAME="cpeinfra"
KEY_FILE="/opt/mount/id_rsa"
SSH_CMD="ssh -i ${KEY_FILE} -o StrictHostKeyChecking=no -o ServerAliveInterval=60 ${USERNAME}@${VM_IP}"

# --- Host-Side Paths ---
# These are the paths *on the host*
HOST_CSCC_BIN="${HOST_SCAN_DIR}/cscc"
HOST_BENCHMARK="${HOST_SCAN_DIR}/U_RHEL_8_V2R1_STIG_SCAP_1-3_Benchmark.zip"
HOST_RESULTS_DIR="${HOST_SCAN_DIR}/Resources/Results"
HOST_LOG_FILE="${HOST_SCAN_DIR}/stig_run_output.log"

# --- Logging Function ---
# --- Logging Function ---
print2log() {
    local message="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S.%6N")
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}


# --- Main Logic ---
print2log "STIG scan process started (via SSH)."

if [ -z "$VM_IP" ]; then
  print2log "ERROR: Could not determine VM_IP from /etc/hosts. Aborting."
  exit 1
fi

# 1. Install the STIG benchmark profile *on the host*
print2log "Installing STIG benchmark profile on host via SSH..."
COMMAND_TO_RUN="sudo ${HOST_CSCC_BIN} -is ${HOST_BENCHMARK}"

if ! output=$($SSH_CMD "$COMMAND_TO_RUN" 2>&1); then
    print2log "ERROR: Failed to install STIG benchmark profile. See details below:"
    print2log "$(echo "$output" | sed 's/^/    /')"
    exit 1
fi

# 2. Run the scan *on the host*
print2log "Starting STIG scan on host via SSH. This may take a while..."
# We redirect the remote command's output to a log file on the shared mount
CMD_WITH_REDIR="'${HOST_CSCC_BIN} -u ${HOST_RESULTS_DIR}/ > ${HOST_LOG_FILE} 2>&1'"
COMMAND_TO_RUN="sudo bash -c $CMD_WITH_REDIR"

if ! $SSH_CMD "$COMMAND_TO_RUN"; then
    print2log "ERROR: STIG scan command failed. Check ${HOST_LOG_FILE} on the host for details."
    exit 1
fi

print2log "STIG scan command completed successfully."
print2log "Raw results are in ${HOST_RESULTS_DIR} on the host."
exit 0