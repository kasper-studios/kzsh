# ~/.config/kzsh/20-aliases.zsh
# Common aliases

# ls / lsd (with safety check)
if command -v lsd >/dev/null 2>&1; then
  alias ls='lsd'
  alias ll='lsd -lah'
  alias la='lsd -A'
  alias l='lsd -l'
fi

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias proj='cd ~/Desktop/projects 2>/dev/null || { mkdir -p ~/Desktop/projects && cd ~/Desktop/projects; }'
alias tools='cd ~/Desktop/tools'
alias scripts='cd ~/Desktop/scripts 2>/dev/null || { mkdir -p ~/Desktop/scripts && cd ~/Desktop/scripts; }'

alias cls='clear'
alias update='kpkg update'

# Systemd
alias sc='ksys'

# Reload
alias src='source ~/.zshrc'
