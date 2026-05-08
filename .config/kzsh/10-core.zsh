# ~/.config/kzsh/10-core.zsh
# ZSH options, history, completion

setopt autocd
setopt correct
setopt notify
setopt hist_ignore_dups
setopt share_history

HISTSIZE=50000
SAVEHIST=50000
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"

autoload -Uz compinit

local zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
if [[ -n "$zcompdump"(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

if [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
fi

if [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)
  ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=blue'
  ZSH_HIGHLIGHT_STYLES[precommand]='fg=green,bold'
  ZSH_HIGHLIGHT_STYLES[command]='fg=cyan'
  ZSH_HIGHLIGHT_STYLES[alias]='fg=blue'
  ZSH_HIGHLIGHT_STYLES[function]='fg=blue'
  ZSH_HIGHLIGHT_STYLES[builtin]='fg=cyan'
  ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=yellow'
  ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=magenta'
  ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=magenta'
  ZSH_HIGHLIGHT_STYLES[back-quoted-argument]='bg=237'
  ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red'
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'

if [[ -f ~/.fzf.zsh ]]; then
  source ~/.fzf.zsh
fi
