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

kcfg list "app_" | while read -r line; do
  [[ -z "$line" ]] && continue
  local name=$(echo "${line%%:*}" | xargs)
  local val=$(echo "${line#*: }" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" | xargs)
  alias "$name"="$val"
done

if [[ -t 0 ]]; then
  kcfg list "start_" | while read line; do
    local val="${line#*: }"
    eval "$val"
  done
fi

# --- DAEMONS (kdaemon) ---
kautostart() {
  local action="$1"
  local app="$2"
  
  case "$action" in
    add)
      if [[ -z "$app" ]]; then
        echo "usage: kautostart add <name> <command>"
        return 1
      fi
      local name="$2"; shift; shift
      local cmd="$*"
      echo "$name|$cmd|true" >> "$KZSH_DIR/.autostart"
      print -P "✅ Added %F{cyan}$name%f to autostart"
      ;;
    list)
      echo "🏁 Autostart Apps:"
      [[ -f "$KZSH_DIR/.autostart" ]] && cat "$KZSH_DIR/.autostart" | while IFS='|' read n cmd en; do
        print -P "  %F{cyan}$n%f -> $cmd (%F{$([[ "$en" == "true" ]] && echo green || echo red)}$en%f)"
      done
      ;;
    remove)
      if [[ -z "$app" ]]; then return 1; fi
      sed -i "/^$app|/d" "$KZSH_DIR/.autostart" 2>/dev/null
      print -P "🗑️ Removed %F{cyan}$app%f from autostart"
      ;;
    run)
      echo "🚀 Запускаю автозапуск..."
      while IFS='|' read name cmd enabled; do
        if [[ "$enabled" == "true" ]]; then
          print -P "  🚀 $name"
          eval "$cmd" &
        fi
      done < "$KZSH_DIR/.autostart"
      ;;
    *)
      echo "KZSH AUTOSTART MANAGER"
      echo "usage: kautostart add|list|remove|run"
      ;;
  esac
}

kdaemon() {
  local action="$1"
  local daemon="$2"
  
  case "$action" in
    check)
      node "$KZSH_DIR/../src/daemon-check.js"
      ;;
    enable)
      kcfg set "d_$daemon" "true"
      print -P "✅ Daemon %F{cyan}$daemon%f enabled"
      ;;
    disable)
      kcfg set "d_$daemon" "false"
      print -P "❌ Daemon %F{cyan}$daemon%f disabled"
      ;;
    start)
      node "$KZSH_DIR/../src/demons/$daemon.js" &
      print -P "🚀 Starting %F{cyan}$daemon%f..."
      ;;
    status)
      echo "📊 Daemon Status:"
      kcfg list "d_" | while read -r line; do
        local name="${line%%:*}"
        local val="${line#*: }"
        print -P "  %F{cyan}${name#d_}%f -> ${val}"
      done
      ;;
    *)
      echo "KZSH DAEMON MANAGER"
      echo "usage: kdaemon check|enable|disable|start|status"
      echo ""
      echo "Демоны:"
      echo "  autostart  - авто запуск приложений"
      echo "  termoregulator - температура + power profiles"
      ;;
  esac
}
