#!/bin/bash
set -eo pipefail

# --- Configuration ---
HOST_ROOT="/opt/mount"
HOST_SCAN_DIR="${HOST_ROOT}/security_scans"
LOG_FILE="${HOST_SCAN_DIR}/openscap_scan.log"
HOST_REPORT_DIR="${HOST_SCAN_DIR}/openscap_results"

# --- SSH Configuration ---
VM_IP="${VM_IP:-$(grep 'host.containers.internal' /etc/hosts | awk '{print $1}')}"
USERNAME="cpeinfra"
KEY_FILE="/opt/mount/id_rsa"
# -n = disconnects stdin
SSH_CMD="ssh -i ${KEY_FILE} -o StrictHostKeyChecking=no -o ServerAliveInterval=60 ${USERNAME}@${VM_IP}"

# --- Logging Function ---
print2log() {
    local message="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S.%6N")
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# --- Function to run a single OVAL scan ---
run_scan() {
    local scan_type="$1"
    local oval_url="$2"
    local oval_file_path="$3"
    local report_file_path="$4"
    local run_log_path="$5"

    print2log "--- Starting $scan_type Scan ---"
    
    # 1. Download OVAL file directly to the shared mount
    print2log "Downloading $scan_type OVAL file to ${oval_file_path}..."
    if ! wget -q -O - "$oval_url" | bzip2 --decompress > "$oval_file_path"; then
      print2log "FAILURE: Failed to download $scan_type OVAL file. Skipping."
      return 1 # Use return code to signal failure
    fi
    print2log "SUCCESS: $scan_type OVAL file downloaded."

    # 2. Run the scan on the host
    print2log "Running $scan_type scan on host via SSH (using sudo)..."
    local CMD_WITH_REDIR="'/usr/bin/oscap oval eval --report ${report_file_path} ${oval_file_path} > ${run_log_path} 2>&1'"
    local COMMAND_TO_RUN="sudo bash -c $CMD_WITH_REDIR"

    # Disconnect stdio to prevent pipe corruption in the wrapper
    if ! $SSH_CMD "$COMMAND_TO_RUN"; then
        print2log "FAILURE: $scan_type 'oscap' command failed on host. Check ${run_log_path} for details."
        rm "$oval_file_path" # Attempt to clean up
        return 1
    fi
    print2log "SUCCESS: $scan_type scan complete. Report is at ${report_file_path}"

    # 3. Cleanup
    print2log "Cleaning up $scan_type OVAL file..."
    rm "$oval_file_path"
    print2log "--- Finished $scan_type Scan ---"
    return 0
}


# --- Main Logic ---
print2log "OpenSCAP scan process started (via SSH)."

if [ -z "$VM_IP" ]; then
  print2log "ERROR: Could not determine VM_IP from /etc/hosts. Aborting."
  exit 1
fi

# 1. Check if oscap is installed on the host VM
print2log "INFO: Checking if oscap is installed on host..."
if ! $SSH_CMD "command -v /usr/bin/oscap > /dev/null 2>&1"; then
    print2log "FAILURE: /usr/bin/oscap is not installed on the host VM. Aborting."
    exit 1
fi
print2log "SUCCESS: oscap is installed."

# 2. Run the scans
scan_failed=0

# --- Patched Scan ---
run_scan "Patched" \
    "https://security.access.redhat.com/data/oval/v2/RHEL8/rhel-8.oval.xml.bz2" \
    "${HOST_SCAN_DIR}/rhel-8-patched.oval.xml" \
    "${HOST_REPORT_DIR}/rhel8-patched.html" \
    "${HOST_SCAN_DIR}/openscap_patched_run_output.log"
if [ $? -ne 0 ]; then scan_failed=1; fi

# --- Unpatched Scan (NEW) ---
run_scan "Unpatched" \
    "https://security.access.redhat.com/data/oval/v2/RHEL8/rhel-8-including-unpatched.oval.xml.bz2" \
    "${HOST_SCAN_DIR}/rhel-8-unpatched.oval.xml" \
    "${HOST_REPORT_DIR}/rhel8-including-unpatched.html" \
    "${HOST_SCAN_DIR}/openscap_unpatched_run_output.log"
if [ $? -ne 0 ]; then scan_failed=1; fi


# 3. Final Exit
if [ "$scan_failed" -eq 1 ]; then
    print2log "ERROR: One or more OpenSCAP scans failed."
    exit 1
fi

print2log "All OpenSCAP scans completed successfully."
exit 0