#!/bin/bash
# KZSH Session Starter - Lightweight display manager replacement
# Automatically starts the appropriate desktop environment based on installed profile

set -e  # Exit on error

# Only run on TTY1 and if not already in a graphical session
if [[ "$(tty)" != "/dev/tty1" ]] || [[ -n "$DISPLAY" ]] || [[ -n "$WAYLAND_DISPLAY" ]]; then
    return 0
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Error handler
handle_error() {
    echo -e "${RED}вњ— Session failed to start${NC}"
    echo -e "${YELLOW}Check logs: journalctl --user -xe${NC}"
    echo ""
    read -p "Press Enter to return to shell..."
    return 1
}

trap handle_error ERR

clear

echo -e "${CYAN}"
echo "в•”в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•—"
echo "в•‘     KASPERENOK SESSION MANAGER         в•‘"
echo "в•љв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ќ"
echo -e "${NC}"

# Detect installed desktop environments
declare -A available_sessions
session_count=0

# Check for Niri
if command -v niri-session >/dev/null 2>&1; then
    ((session_count++))
    available_sessions[$session_count]="niri|Niri Wayland Compositor|niri-session"
fi

# Check for GNOME
if command -v gnome-session >/dev/null 2>&1; then
    ((session_count++))
    available_sessions[$session_count]="gnome|GNOME Desktop|gnome-session"
fi

# Check for KDE Plasma
if command -v startplasma-wayland >/dev/null 2>&1; then
    ((session_count++))
    available_sessions[$session_count]="plasma|KDE Plasma (Wayland)|startplasma-wayland"
elif command -v startplasma-x11 >/dev/null 2>&1; then
    ((session_count++))
    available_sessions[$session_count]="plasma|KDE Plasma (X11)|startplasma-x11"
fi

# Check for Hyprland
if command -v Hyprland >/dev/null 2>&1; then
    ((session_count++))
    available_sessions[$session_count]="hyprland|Hyprland Compositor|Hyprland"
fi

# Check for Sway
if command -v sway >/dev/null 2>&1; then
    ((session_count++))
    available_sessions[$session_count]="sway|Sway Compositor|sway"
fi

if [[ $session_count -eq 0 ]]; then
    echo -e "${RED}вњ— No desktop environments found${NC}"
    echo -e "${YELLOW}Install one with: kpkg install desktop-niri${NC}"
    echo ""
    read -p "Press Enter to continue to shell..."
    return 0
fi

# Display available sessions
echo -e "${GREEN}Available sessions:${NC}"
echo ""
for i in $(seq 1 $session_count); do
    IFS='|' read -r id name cmd <<< "${available_sessions[$i]}"
    echo -e "  ${BLUE}[$i]${NC} $name"
done
echo -e "  ${BLUE}[s]${NC} Shell (no GUI)"
echo -e "  ${BLUE}[q]${NC} Quit"
echo ""

# Auto-select if only one session available
if [[ $session_count -eq 1 ]]; then
    echo -e "${CYAN}Auto-selecting the only available session...${NC}"
    choice=1
    sleep 1
else
    read -p "Select session [1]: " choice
    choice=${choice:-1}
fi

# Handle choice
case "$choice" in
    [1-9])
        if [[ $choice -le $session_count ]]; then
            IFS='|' read -r id name cmd <<< "${available_sessions[$choice]}"
            echo ""
            echo -e "${GREEN}Starting $name...${NC}"
            sleep 0.5
            
            # Set environment variables
            export XDG_SESSION_TYPE=wayland
            export XDG_CURRENT_DESKTOP="$id"
            export XDG_SESSION_DESKTOP="$id"
            
            # Special handling for different compositors
            case "$id" in
                niri)
                    export XDG_CURRENT_DESKTOP=niri
                    ;;
                gnome)
                    export XDG_CURRENT_DESKTOP=GNOME
                    export XDG_SESSION_TYPE=wayland
                    ;;
                plasma)
                    export XDG_CURRENT_DESKTOP=KDE
                    ;;
            esac
            
            # Verify command exists before exec
            if ! command -v $cmd >/dev/null 2>&1; then
                echo -e "${RED}вњ— Command not found: $cmd${NC}"
                handle_error
                return 1
            fi
            
            # Start the session
            exec $cmd
        else
            echo -e "${RED}Invalid choice${NC}"
            sleep 1
            exec bash "$0"
        fi
        ;;
    s|S)
        echo -e "${CYAN}Starting shell...${NC}"
        return 0
        ;;
    q|Q)
        echo -e "${CYAN}Goodbye!${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        sleep 1
        exec bash "$0"
        ;;
esac
