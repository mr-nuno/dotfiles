# Fedora Dotfiles

This repository manages system configurations and terminal environments using [GNU Stow](https://www.gnu.org/software/stow/). 

## Prerequisites
Ensure the target machine has the core tools installed before deploying the configuration:
* `git`
* `stow`
* `starship` (for the terminal prompt)
* `claude`

```bash
sudo dnf install git stow -y
```

## Deployment Steps

**1. Clone the repository**
Clone these dotfiles directly into your home directory:
```bash
git clone <YOUR_REPO_URL_HERE> ~/dotfiles
cd ~/dotfiles
```

**2. Configure Git to ignore local secrets**
Before creating any local overrides inside the repository, ensure Git is configured to ignore them so your API keys and machine-specific tools don't get pushed:
```bash
echo "bash/.bashrc.d/00-env.sh" > .gitignore
echo "bash/.bashrc.d/20-tools.sh" >> .gitignore
git add .gitignore
git commit -m "Add gitignore for local overrides"
```

**3. Prepare target directories**
Ensure the destination folders exist on the target machine. If Stow doesn't see an existing folder, it will symlink the entire directory rather than the individual files, breaking local untracked overrides.
```bash
mkdir -p ~/.bashrc.d
mkdir -p ~/.config
```

**4. Remove conflicting existing files (Crucial)**
Stow will throw a conflict error and safely abort if a physical file already exists where it needs to create a symlink. Delete the existing files you are actively syncing via Git, **but keep your untracked local overrides intact**.
```bash
# Remove tracked files to make room for symlinks
rm ~/.bashrc.d/10-aliases.sh
rm ~/.bashrc.d/30-prompt.sh
rm ~/.bashrc.d/update.sh
rm ~/.config/starship.toml

# DO NOT remove 00-env.sh or 20-tools.sh!
```

**5. Claude Code configurations**
Ensure the base `.claude` directory exists before stowing, so Stow creates symlinks inside the folder rather than trying to hijack the entire directory (which would interfere with untracked local files like `.credentials.json`).
```bash
mkdir -p ~/.claude
```

**6. Deploy the configurations**
Use Stow to automatically map the symlinks to your home folder. You can use the `--simulate` (or `-n`) flag first if you want to preview the changes safely.
```bash
stow bash
stow starship
stow claude
```

## Local Overrides (Untracked)
The following files are explicitly ignored via `.gitignore` to protect machine-specific secrets and configurations. You can safely create these files directly inside `~/dotfiles/bash/.bashrc.d/` so Stow symlinks them, but Git will never track them:
* `00-env.sh` (For local environment variables and API keys)
* `20-tools.sh` (For hardware-specific CLI tools)