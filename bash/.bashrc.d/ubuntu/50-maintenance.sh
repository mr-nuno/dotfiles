# ~/.bashrc.d/ubuntu/50-maintenance.sh

function update {
    echo "📦 Updating APT packages (system & security)..."
    sudo apt update && sudo apt upgrade -y && sudo apt full-upgrade -y

    if command -v snap >/dev/null 2>&1; then
        echo "📦 Refreshing Snap packages..."
        sudo snap refresh
    fi

    echo "🔧 Checking Firmware updates via fwupdmgr..."
    if command -v fwupdmgr >/dev/null 2>&1; then
        fwupdmgr refresh && fwupdmgr update
    fi

    echo "🧹 Cleaning up unused APT packages..."
    sudo apt autoremove -y && sudo apt clean

    echo "🔄 Reboot status:"
    if [ -f /var/run/reboot-required ]; then
        echo "⚠️  Ubuntu system libraries updated. A reboot is required."
        if [ -f /var/run/reboot-required.pkgs ]; then
            echo "Packages triggering reboot:"
            cat /var/run/reboot-required.pkgs
        fi
    else
        echo "✅ All good! No system restart required."
    fi
}