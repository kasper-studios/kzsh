# ~/.config/kzsh/06-autoupdate.zsh
# Auto-update KZSH from GitHub

# Check if auto-update is enabled
local auto_update=$(kcfg get "auto_update" 2>/dev/null)
[[ "$auto_update" == "no" ]] && return 0

# Check if we're in a git repository
[[ ! -d "${KZSH_DIR}/.git" ]] && return 0

# Check last update time (once per day)
local update_file="${KZSH_DIR}/.last_update"
local current_time=$(date +%s)
local last_update=0

if [[ -f "$update_file" ]]; then
    last_update=$(cat "$update_file" 2>/dev/null || echo 0)
fi

# 86400 seconds = 24 hours
local time_diff=$((current_time - last_update))
if [[ $time_diff -lt 86400 ]]; then
    return 0
fi

# Update KZSH in background
(
    cd "${KZSH_DIR}" || exit
    
    # Fetch updates
    git fetch origin main --quiet 2>/dev/null || exit
    
    # Check if updates available
    local local_commit=$(git rev-parse HEAD 2>/dev/null)
    local remote_commit=$(git rev-parse origin/main 2>/dev/null)
    
    if [[ "$local_commit" != "$remote_commit" ]]; then
        # Updates available
        print -P "\n%F{39}📦 KZSH updates available!%f"
        print -P "%F{242}Updating from GitHub...%f"
        
        # Stash local changes if any
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            git stash push -m "Auto-stash before update $(date)" --quiet 2>/dev/null
        fi
        
        # Pull updates
        if git pull origin main --quiet 2>/dev/null; then
            print -P "%F{32}✓ KZSH updated successfully!%f"
            print -P "%F{242}Restart your shell to apply changes: exec zsh%f\n"
        else
            print -P "%F{31}✗ Failed to update KZSH%f"
            print -P "%F{242}Run 'cd ~/.config/kzsh && git pull' manually%f\n"
        fi
    fi
    
    # Update last check time
    echo "$current_time" > "$update_file"
) &!
