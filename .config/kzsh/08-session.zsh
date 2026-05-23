# ~/.config/kzsh/08-session.zsh
# Auto-start session manager on TTY1

# Only run on TTY1 and if not already in a graphical session
if [[ "$(tty)" == "/dev/tty1" ]] && [[ -z "$DISPLAY" ]] && [[ -z "$WAYLAND_DISPLAY" ]]; then
    # Check if kstart-session is enabled
    local session_enabled=$(kcfg get "auto_start_session" 2>/dev/null)
    if [[ "$session_enabled" != "no" ]]; then
        # Source the session starter
        if [[ -f "${KZSH_DIR}/kstart-session.sh" ]]; then
            source "${KZSH_DIR}/kstart-session.sh"
        fi
    fi
fi
