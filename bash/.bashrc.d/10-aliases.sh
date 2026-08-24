# --- Navigation & Listning ---
# Använder eza för en modern upplevelse (kräver 'eza' installerat)
if command -v eza >/dev/null 2>&1; then
    alias ls='eza -alh --icons=always --group-directories-first'
    alias lt='eza --tree --level=2'
else
    alias ls='ls -alh --color=auto --group-directories-first'
fi

# --- System & Verktyg ---
alias cls='clear'
alias k='kubectl'
alias reload='source ~/.bashrc'

# --- Windows-vana (Valfritt men smidigt) ---
alias dir='ls'
alias ..='cd ..'

# Snabbkoll på processer (likt Task Manager)
alias taskmgr='htop' # Se till att htop är installerat: sudo dnf install htop

# Visa lagringsutrymme i GB/MB (istället för bytes)
alias df='df -h'
alias du='du -h -d 1'

# Nätverk (istället för ipconfig)
alias ipconfig='ip -c a'

# Fråga innan man skriver över eller raderar (viktigt!)
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias rd='rm -rfiv'

# Restart to BIOS
alias bios='systemctl reboot --firmware-setup' 

# Reboot
alias reboot='systemctl reboot' 

# Shut down
alias shutdown='shutdown now' 

# LKAB VDI
alias vdi='npm run vdi --prefix ~/Projects/tools'

# Files
alias files='setsid nautilus >/dev/null 2>&1'

# Home
alias projects='cd ~/Projects'
alias home='cd ~/'
alias downloads='cd ~/Downloads'

# LazyGit
alias lg="lazygit"

# Search
find() {
    # 1. Search recursively, case-insensitive, ignoring junk
    # 2. Use 'sed' with a pipe separator | to avoid slash errors
    grep -rin --exclude-dir={.git,node_modules,dist,bin,obj} "$1" . | \
    sed -E "s|^([^:]+):([^:]+):|Filename: \1, Row: \2\nContent: |"
}

# NVM
alias nvm='fnm'

# open files
alias open='xdg-open &> /dev/null'
alias files='(nautilus &> /dev/null &)'