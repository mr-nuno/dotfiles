# ~/.bashrc.d/01-os.sh
# Universal OS detection for distro-aware shell configurations

if [ -f /etc/os-release ]; then
    . /etc/os-release
    export OS_ID="$ID" # Will be "fedora", "ubuntu", etc.
else
    export OS_ID="unknown"
fi