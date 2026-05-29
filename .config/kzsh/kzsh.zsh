# ~/.config/kzsh/kzsh.zsh
# KASPERENOK ZSH v5.0 - Main Entrypoint

export KZSH_DIR="${KZSH_DIR:-$HOME/.config/kzsh}"

# Helper to find the repository directory
kzsh_repo_dir() {
  if [[ -L "${KZSH_DIR}" ]]; then
    local link_target=$(readlink "${KZSH_DIR}")
    if [[ "$link_target" == /* ]]; then
      echo "$(cd "$(dirname "$link_target")/.." && pwd)"
    else
      echo "$(cd "$(dirname "${KZSH_DIR}")/$link_target/.." && pwd)"
    fi
  elif [[ -d "${KZSH_DIR}/.git" ]]; then
    echo "${KZSH_DIR}"
  elif [[ -d "$HOME/.kzsh-repo/.git" ]]; then
    echo "$HOME/.kzsh-repo"
  fi
}

kcfg() {
  local cfg="$KZSH_DIR/config.yaml"
  [[ ! -f $cfg ]] && touch "$cfg"

  case "$1" in
    get)
      if [[ -z "$2" ]]; then
        echo "usage: kcfg get <key>"
        return 1
      fi
      awk -v k="$2" -F': *' '$1 == k {print $2}' "$cfg" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
      ;;
    set)
      if [[ -z "$2" ]]; then
        echo "usage: kcfg set <key> <value>"
        return 1
      fi
      local key="$2"; shift 2
      local value="$*"

      # Validate key format (no special chars except underscore and dash)
      if [[ ! "$key" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "error: invalid key format '$key'"
        return 1
      fi

      if grep -q "^$key:" "$cfg"; then
        # Use sed with backup for cross-platform compatibility
        if sed --version 2>&1 | grep -q GNU; then
          sed -i "s|^$key:.*|$key: $value|" "$cfg"
        else
          sed -i '' "s|^$key:.*|$key: $value|" "$cfg"
        fi
      else
        # Ensure file ends with newline before appending
        [[ -n $(tail -c 1 "$cfg" 2>/dev/null) ]] && echo "" >> "$cfg"
        echo "$key: $value" >> "$cfg"
      fi
      ;;
    list)
      local prefix="$2"
      if [[ -z "$prefix" ]]; then
        cat "$cfg"
      else
        grep "^$prefix" "$cfg" | sed "s|^$prefix||"
      fi
      ;;
    edit)
      ${EDITOR:-nano} "$cfg" < /dev/tty
      ;;
    validate)
      # Basic YAML validation
      if ! awk -F': *' 'NF > 0 && !/^#/ && !/^[[:space:]]*$/ {
        if (NF < 2) {
          print "Invalid line: " $0
          exit 1
        }
      }' "$cfg"; then
        echo "error: config.yaml has invalid format"
        return 1
      fi
      echo "config.yaml is valid"
      ;;
    *)
      echo "usage: kcfg get <key> | kcfg set <key> <value> | kcfg list [prefix] | kcfg edit | kcfg validate"
      ;;
  esac
}

KZSH_BUN_DEFAULT="${KZSH_BUN_DEFAULT:-$(kcfg get bun_default)}"
[[ -z "$KZSH_BUN_DEFAULT" ]] && KZSH_BUN_DEFAULT="yes"

kreload() {
  exec zsh
}

alias krl='kreload'

for mod in 00-env 05-pkg 06-autoupdate 07-bootstrap 08-session 10-core 20-aliases 25-bun 30-git 40-docker 50-funcs 60-prompt 70-apps 80-sys; do
  [[ -f "$KZSH_DIR/$mod.zsh" ]] && source "$KZSH_DIR/$mod.zsh"
done

[[ -f "$KZSH_DIR/90-local.zsh" ]] && source "$KZSH_DIR/90-local.zsh"

if [[ -t 0 ]]; then
  local line1="  🧷  KASPERENOK ZSH v5.7"
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
setopt PROMPT_SUBST
