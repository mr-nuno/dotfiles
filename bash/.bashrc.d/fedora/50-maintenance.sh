# ~/.bashrc.d/fedora/50-maintenance.sh

function update {
    echo "📦 Updating DNF packages..."
    sudo dnf upgrade --refresh -y
    
    if command -v flatpak >/dev/null 2>&1 && [ -n "$(flatpak list --columns=application)" ]; then
        echo "📦 Updating Flatpaks (Skipping AppStream)..."
        flatpak update -y $(flatpak list --columns=application)
    fi
    
    echo "🔧 Checking Firmware updates..."
    if command -v fwupdmgr >/dev/null 2>&1; then
        fwupdmgr update 
    fi
    
    echo "🔄 Reboot status:"
    if dnf needs-restarting -r > /dev/null; then
        echo "✅ All good! No system restart required."
    else
        echo "⚠️  Fedora OS libraries updated. A reboot is required."
    fi

    if command -v flatpak >/dev/null 2>&1; then
        echo "🧹 Cleaning up unused Flatpaks..."
        flatpak uninstall --unused -y
    fi
}