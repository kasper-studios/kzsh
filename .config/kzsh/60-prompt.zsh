# ~/.config/kzsh/60-prompt.zsh
# Premium Modern Prompt (Two-line boxed style)

autoload -Uz vcs_info
precmd() { vcs_info }

zstyle ':vcs_info:git:*' formats '%F{242}on%f %F{214} %b%f'
zstyle ':vcs_info:git:*' actionformats '%F{242}on%f %F{214} %b%f %F{red}(%a)%f'

# Prompt Parts
# Line 1: ┌─╼ [user@host] 📁 path [git]
PROMPT_TOP='%F{39}┌─╼ %F{242}[%F{112}%n%F{242}@%F{112}%m%F{242}] %F{39}📁 %~%f${vcs_info_msg_0_}'

# Line 2: └────╼ ❯❯❯ (with status color)
PROMPT_BOTTOM='%F{39}└────╼ %(?.%F{163}.%F{196})%B❯❯❯%b%f '

PROMPT='${PROMPT_TOP}
${PROMPT_BOTTOM}'

zstyle ':completion:*' menu select
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
