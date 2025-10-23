Add all of these files in a folder and build the container using command : **sudo podman build -t security-scans:4.0 .**\
and run\
**sudo podman run \
  --rm \
  -it \
  --add-host=host.containers.internal:host-gateway \
  -v /opt/mount:/opt/mount:Z \
  security-scans:4.0**
