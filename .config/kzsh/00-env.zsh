# ~/.config/kzsh/00-env.zsh
# OS Detection & Environment variables

# Detect Distro
if [[ -f /etc/os-release ]]; then
  export KZSH_DISTRO=$(grep "^ID=" /etc/os-release | cut -d= -f2 | sed 's/"//g')
elif [[ "$OSTYPE" == "darwin"* ]]; then
  export KZSH_DISTRO="macos"
else
  export KZSH_DISTRO="unknown"
fi

# PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Editor and viewer
export EDITOR="${EDITOR:-nvim}"

# Safe aliases with command checks
if command -v bat >/dev/null 2>&1; then
  alias cat='bat'
  alias batp='bat --pager=always'
fi
