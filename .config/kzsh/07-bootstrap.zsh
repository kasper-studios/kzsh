# ~/.config/kzsh/07-bootstrap.zsh
# First-run detection and bootstrap trigger

KZSH_FIRST_RUN=$(kcfg get first_run)

[[ -z "$KZSH_FIRST_RUN" ]] && KZSH_FIRST_RUN="yes"

if [[ "$KZSH_FIRST_RUN" == "yes" && -t 0 ]]; then
  echo ""
  print -P "%F{yellow}👋 Welcome to KASPERENOK ZSH!%f"
  print -P "It looks like this is your %F{cyan}first run%f on this system."
  echo ""
  read -q "ans?Would you like to run the installer (kinstall)? [y/N] "
  echo ""
  if [[ "$ans" == [yY] ]]; then
    export KZSH_TRIGGER_INSTALL="yes"
  else
    kcfg set first_run "no"
    print -P "%F{242}Skipping. You can run 'kinstall' later.%f"
  fi
fi

kzsh_post_load() {
  if [[ "$KZSH_TRIGGER_INSTALL" == "yes" ]]; then
    unset KZSH_TRIGGER_INSTALL
    kinstall
  fi
}
