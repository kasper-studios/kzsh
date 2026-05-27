# ~/.config/kzsh/60-prompt.zsh
# Premium Modern Prompt (Two-line boxed style)

autoload -Uz vcs_info
autoload -Uz add-zsh-hook
setopt PROMPT_SUBST

# Update vcs_info before each prompt
add-zsh-hook precmd vcs_info

# Clean vcs_info style (colors will be interpreted by prompt_subst)
zstyle ':vcs_info:git:*' formats 'on %F{214} %b%f'
zstyle ':vcs_info:git:*' actionformats 'on %F{214} %b%f %F{196}(%a)%f'

# Premium Modern Prompt (Two-line boxed style)
PROMPT='%F{39}┌─╼ %F{242}[%F{112}%n%F{242}@%F{112}%m%F{242}] %F{39}📁 %~%f %F{242}${vcs_info_msg_0_}%f
%F{39}└────╼ %(?.%F{163}.%F{196})%B❯❯❯%b%f '
