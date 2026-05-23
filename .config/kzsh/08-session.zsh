# ~/.config/kzsh/08-session.zsh
# Auto-start session manager on TTY1

# Only run on TTY1 and if not already in a graphical session
if [[ "$(tty)" == "/dev/tty1" ]] && \
   [[ -z "$DISPLAY" ]] && \
   [[ -z "$WAYLAND_DISPLAY" ]] && \
   [[ -z "$XDG_SESSION_TYPE" ]] && \
   [[ -z "$DESKTOP_SESSION" ]]; then
    
    # Additional check: don't run if compositor is already running
    if pgrep -x "niri|gnome-shell|plasmashell|Hyprland|sway" >/dev/null 2>&1; then
        return 0
    fi
    
    # Check if kstart-session is enabled
    local session_enabled=$(kcfg get "auto_start_session" 2>/dev/null)
    if [[ "$session_enabled" != "no" ]]; then
        # Source the session starter
        if [[ -f "${KZSH_DIR}/kstart-session.sh" ]]; then
            source "${KZSH_DIR}/kstart-session.sh"
        fi
    fi
fi
