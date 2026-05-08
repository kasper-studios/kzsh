# Git aliases
if command -v git >/dev/null 2>&1; then
  alias g='git'
  alias gs='git status -sb'
  alias ga='git add'
  alias gaa='git add .'
  alias gc='git commit -m'
  alias gca='git commit --amend --no-edit'
  alias gp='git push'
  alias gpl='git pull'
  alias gb='git branch'
  alias gco='git checkout'
  alias gcb='git checkout -b'
  
  # Premium Log
  alias gl='git log --oneline --graph --decorate -n 15'
  alias glog="git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all"

  # Completion
  compdef g=git
fi
