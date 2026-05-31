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

# --- DAEMONS (systemd) ---
kdaemon() {
  local action="$1"
  local daemon="$2"
  local svc_name="kzsh-$daemon"
  
  case "$action" in
    check)
      node "$KZSH_DIR/src/daemon-check.js"
      ;;
    install)
      if [[ -z "$daemon" ]]; then
        echo "usage: kdaemon install <daemon>"
        echo "Available: termoregulator, autostart"
        return 1
      fi
      local repo_dir=$(kzsh_repo_dir)
      local src="${repo_dir}/.config/systemd/user/${svc_name}.service"
      local dst="$HOME/.config/systemd/user/${svc_name}.service"
      if [[ -f "$src" ]]; then
        mkdir -p "$HOME/.config/systemd/user"
        cp "$src" "$dst"
        systemctl --user daemon-reload
        print -P "✅ Service %F{cyan}$svc_name.service%f installed"
      else
        print -P "%F{red}✗ Service file not found%f"
      fi
      ;;
    enable)
      systemctl --user enable "$svc_name" 2>/dev/null && \
        print -P "✅ Daemon %F{cyan}$daemon%f enabled" || \
        print -P "%F{yellow}⚠ Install first: kdaemon install $daemon%f"
      ;;
    disable)
      systemctl --user disable "$svc_name" 2>/dev/null && \
        print -P "❌ Daemon %F{cyan}$daemon%f disabled"
      ;;
    start)
      systemctl --user start "$svc_name" 2>/dev/null && \
        print -P "🚀 Starting %F{cyan}$daemon%f..." || \
        node "$KZSH_DIR/src/demons/$daemon.js" &
      ;;
    stop)
      systemctl --user stop "$svc_name" 2>/dev/null && \
        print -P "⏹️ Stopped %F{cyan}$daemon%f"
      ;;
    status)
      systemctl --user status "$svc_name" 2>/dev/null || \
        print -P "%F{red}✗ Not installed.%f Run: kdaemon install $daemon"
      ;;
    *)
      echo "KZSH DAEMON MANAGER (systemd)"
      echo "usage: kdaemon check|install|enable|disable|start|stop|status <daemon>"
      echo ""
      echo "Демоны:"
      echo "  termoregulator - температура + power profiles (http://localhost:9110)"
      echo "  autostart - авто запуск приложений"
      ;;
  esac
}

# Autostart apps manager
kautostart() {
  local action="$1"
  local app="$2"
  
  case "$action" in
    add)
      if [[ -z "$2" ]]; then
        echo "usage: kautostart add <name> <command>"
        return 1
      fi
      local name="$2"; shift; shift
      local cmd="$*"
      echo "$name|$cmd|true" >> "$KZSH_DIR/.autostart"
      print -P "✅ Added %F{cyan}$name%f to autostart (systemd)"
      ;;
    list)
      echo "🏁 Autostart Apps:"
      [[ -f "$KZSH_DIR/.autostart" ]] && cat "$KZSH_DIR/.autostart" | while IFS='|' read n cmd en; do
        print -P "  %F{cyan}$n%f -> $cmd %F{$([[ "$en" == "true" ]] && echo green || echo red)}($en)%f"
      done
      ;;
    remove)
      if [[ -z "$app" ]]; then return 1; fi
      sed -i "/^$app|/d" "$KZSH_DIR/.autostart" 2>/dev/null
      print -P "🗑️ Removed %F{cyan}$app%f from autostart"
      ;;
    *)
      echo "KZSH AUTOSTART"
      echo "usage: kautostart add|list|remove <name>"
      echo ""
      echo "Управляется systemd: kzsh-autostart.service"
      echo "Установить: kdaemon install autostart"
      ;;
  esac
}