# ~/.config/kzsh/08-session.zsh
# Auto-start session manager on TTY1

# Run autostart apps before session
if [[ -f "$KZSH_DIR/.autostart" ]]; then
  echo ""
  print -P "%F{39}%B🏁 AUTOSTART%b%f"
  echo ""
  while IFS='|' read name cmd enabled; do
    if [[ "$enabled" == "true" ]]; then
      print -P "  🚀 %F{cyan}$name%f"
      eval "$cmd" &
    fi
  done < "$KZSH_DIR/.autostart"
  echo ""
fi

# Only run on TTY1 and if not already in a graphical session
if [[ "$(tty)" == "/dev/tty1" ]] && \
   [[ -z "$DISPLAY" ]] && \
   [[ -z "$WAYLAND_DISPLAY" ]] && \
   [[ -z "$XDG_SESSION_TYPE" ]] && \
   [[ -z "$DESKTOP_SESSION" ]]; then

  # Additional check: don't run if compositor is already running
  if ! pgrep -x niri >/dev/null 2>&1 && \
     ! pgrep -x gnome-shell >/dev/null 2>&1 && \
     ! pgrep -x plasmashell >/dev/null 2>&1 && \
     ! pgrep -x Hyprland >/dev/null 2>&1 && \
     ! pgrep -x sway >/dev/null 2>&1; then

    # Check if kstart-session is enabled
    local session_enabled=$(kcfg get "auto_start_session" 2>/dev/null)
    if [[ "$session_enabled" != "no" ]]; then
      # Source the session starter
      if [[ -f "${KZSH_DIR}/kstart-session.sh" ]]; then
        source "${KZSH_DIR}/kstart-session.sh"
      fi
    fi
  fi
fi
