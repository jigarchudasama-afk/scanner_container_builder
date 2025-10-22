# Dockerfile
FROM registry.access.redhat.com/ubi8/ubi:latest

LABEL maintainer="JIGAR"
LABEL description="SSH-based STIG and OpenSCAP scanner."

# Install only the client tools needed.
# openssh-clients provides 'ssh' and 'scp'
RUN dnf install -y \
    wget \
    openssh-clients \
    bzip2 \
  && dnf clean all

# Create directories for our application and scanner files
RUN mkdir -p /app /scanner_files

# Set the working directory
WORKDIR /app

# Copy the STIG scanner assets (to be copied to the host)
COPY Vulnerability/ /scanner_files/

# Copy all scripts into the container
COPY run_STIG.sh .
COPY run_openScap.sh .
COPY security_scans_wrapper.sh .

# Make all scripts executable
RUN chmod +x *.sh

# Set the wrapper script as the default command to run
CMD ["/app/security_scans_wrapper.sh"]