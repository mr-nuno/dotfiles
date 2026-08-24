# 1. Fallback-prompt (Den gröna du gillar)
# Denna visas om Starship av någon anledning inte skulle starta
export PS1="\[\e[32m\]\u@\h\[\e[m\]:\[\e[34m\]\w\[\e[m\]\$ "

# 2. Starship Init
# Denna skriver över PS1 om Starship är installerat
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi