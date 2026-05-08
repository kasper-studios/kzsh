# ~/.config/kzsh/kzsh.zsh
# KASPERENOK ZSH v5.0 - Main Entrypoint

export KZSH_DIR="${KZSH_DIR:-$HOME/.config/kzsh}"

kcfg() {
  local cfg="$KZSH_DIR/config.yaml"
  [[ ! -f $cfg ]] && touch "$cfg"

  case "$1" in
    get)
      awk -v k="$2" -F': *' '$1 == k {print $2}' "$cfg" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
      ;;
    set)
      local key="$2"; shift 2
      local value="$*"
      if grep -q "^$key:" "$cfg"; then
        sed -i "s|^$key:.*|$key: $value|" "$cfg"
      else
        # Ensure file ends with newline before appending
        [[ -n $(tail -c 1 "$cfg") ]] && echo "" >> "$cfg"
        echo "$key: $value" >> "$cfg"
      fi
      ;;
    list)
      local prefix="$2"
      grep "^$prefix" "$cfg" | sed "s|^$prefix||"
      ;;
    edit)
      ${EDITOR:-nvim} "$cfg" < /dev/tty
      ;;
    *)
      echo "usage: kcfg get <key> | kcfg set <key> <value> | kcfg list <prefix> | kcfg edit"
      ;;
  esac
}

KZSH_BUN_DEFAULT="${KZSH_BUN_DEFAULT:-$(kcfg get bun_default)}"
[[ -z "$KZSH_BUN_DEFAULT" ]] && KZSH_BUN_DEFAULT="yes"

kreload() {
  exec zsh
}

alias krl='kreload'

for mod in 00-env 05-pkg 07-bootstrap 10-core 20-aliases 25-bun 30-git 40-docker 50-funcs 60-prompt 70-apps 80-sys; do
  [[ -f "$KZSH_DIR/$mod.zsh" ]] && source "$KZSH_DIR/$mod.zsh"
done

[[ -f "$KZSH_DIR/90-local.zsh" ]] && source "$KZSH_DIR/90-local.zsh"

if [[ -t 0 ]]; then
  local line1="  🧷  KASPERENOK ZSH v5.5"
  local line2="  🚀  Distro: ${(C)KZSH_DISTRO}"
  echo ""
  print -P "%F{39}%B╭──────────────────────────────────────────╮%b%f"
  print -P "%F{39}%B│%b%f${(mr:42:: :)line1}%F{39}%B│%b%f"
  print -P "%F{39}%B│%b%f${(mr:42:: :)line2}%F{39}%B│%b%f"
  print -P "%F{39}%B╰──────────────────────────────────────────╯%b%f"
  print -P "📁 %F{242}%~%f"
  print -P "🔥 %F{242}kpkg, ksys, kapp, kstart, krl, khelp, kdeps%f"
  echo ""
fi

[[ -n "$(functions kzsh_post_load)" ]] && kzsh_post_load

# Ensure prompt substitution is active
setopt PROMPT_SUBST
