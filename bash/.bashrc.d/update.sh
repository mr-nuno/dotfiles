function update {
    echo "📦 Updating DNF packages..."
    sudo dnf upgrade --refresh -y
    
    echo "📦 Updating Flatpaks (Skipping AppStream)..."
    # Passing specific application IDs prevents the AppStream update
    flatpak update -y $(flatpak list --columns=application)
    
    echo "🔧 Checking Firmware updates..."
    # Removed the -y flag. It will safely check for updates and cleanly exit. 
    # If it actually finds one, it will pause and ask if you want to install it.
    fwupdmgr update 
    
    echo "🔄 Reboot status:"
    # 0 (success) means no reboot needed, triggering the 'then' block
    if dnf needs-restarting -r > /dev/null; then
        echo "✅ All good! No system restart required."
    else
        echo "⚠️  Fedora OS libraries updated. A reboot is required."
    fi

    echo "🧹 Cleaning up unused Flatpaks..."
    flatpak uninstall --unused -y
}