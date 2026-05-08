# ~/.config/kzsh/80-sys.zsh
# Systemd management utility (ksys)

ksys() {
  local cmd="$1"
  local svc="$2"

  case "$cmd" in
    list)
      echo "📋 Active Systemd Units:"
      systemctl list-units --type=service --state=running | head -n -6 | tail -n +2 | awk '{print "  %F{green}●%f " $1}' | while read line; do print -P "$line"; done
      ;;
    start|stop|restart|reload|enable|disable)
      if [[ -z "$svc" ]]; then
        echo "usage: ksys $cmd <service>"
        return 1
      fi
      echo "⚙️  Executing: sudo systemctl $cmd $svc"
      sudo systemctl "$cmd" "$svc"
      ;;
    status)
      if [[ -z "$svc" ]]; then
        ksys list
        return
      fi
      systemctl status "$svc"
      ;;
    log)
      if [[ -z "$svc" ]]; then
        echo "usage: ksys log <service>"
        return 1
      fi
      echo "📜 Tailing logs for $svc (Ctrl+C to stop)..."
      journalctl -u "$svc" -f
      ;;
    *)
      echo "KASPERENOK SYSTEMD HELPER"
      echo "usage: ksys <command> [service]"
      echo ""
      echo "Commands:"
      echo "  list      - List running services"
      echo "  start     - Start a service"
      echo "  stop      - Stop a service"
      echo "  restart   - Restart a service"
      echo "  status    - Show service status"
      echo "  log       - Tail service logs (journalctl)"
      echo "  enable    - Enable on boot"
      echo "  disable   - Disable from boot"
      ;;
  esac
}

# Aliases for even faster access
alias ksl='ksys list'
alias kss='ksys status'
