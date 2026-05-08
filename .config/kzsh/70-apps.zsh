# ~/.config/kzsh/70-apps.zsh
# Custom App Registry (kapp) and Autostart (kstart)
kapp() {
  local cmd="$1"
  case "$cmd" in
    add)
      if [[ -z "$2" || -z "$3" ]]; then
        echo "usage: kapp add <name> <command>"
        return 1
      fi 

      if [[ ! "$2" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print -P "%F{red}error:%f Name can only contain letters, numbers, - and _"
        return 1
      fi

      local clean_cmd="${3//\\//}"
      
      kcfg set "app_$2" "$clean_cmd"
      print -P "🚀 App %F{cyan}$2%f registered! Reload shell to apply."
      ;;
    list)
      echo "📦 Registered Apps:"
      kcfg list "app_" | while read line; do
        [[ -z "$line" ]] && continue
        local name="${line%%:*}"
        local val="${line#*: }"
        print -P "  %F{cyan}${(r:15:: :)name}%f -> $val"
      done
      ;;
    remove)
      if [[ -z "$2" ]]; then
        echo "usage: kapp remove <name>"
        return 1
      fi
      sed -i "/^app_$2:/d" "$KZSH_DIR/config.yaml"
      echo "🗑️  App $2 removed."
      ;;
    *)
      echo "KASPERENOK APP REGISTRY"
      echo "usage: kapp add|list|remove"
      ;;
  esac
}

kstart() {
  local cmd="$1"
  case "$cmd" in
    add)
      if [[ -z "$2" ]]; then
        echo "usage: kstart add <command>"
        return 1
      fi
      local id=$(date +%s%N)
      kcfg set "start_$id" "$2"
      print -P "🏁 Startup command added!"
      ;;
    list)
      echo "🏁 Startup Commands:"
      kcfg list "start_" | awk -F': ' '{print "  %F{yellow}•%f " $2}' | while read line; do print -P "$line"; done
      ;;
    remove)
      if [[ -z "$2" ]]; then
        echo "usage: kstart remove <id>"
        echo "Run 'kstart list' to see IDs."
        return 1
      fi
      sed -i "/^start_$2:/d" "$KZSH_DIR/config.yaml"
      echo "🗑️  Startup removed."
      ;;
    *)
      echo "KASPERENOK STARTUP MANAGER"
      echo "usage: kstart add|list|remove <id>"
      ;;
  esac
}

kcfg list "app_" | while read line; do
  local name="${line%%:*}"
  local val="${line#*: }"
  alias "$name"="$val"
done

if [[ -t 0 ]]; then
  kcfg list "start_" | while read line; do
    local val="${line#*: }"
    eval "$val"
  done
fi
