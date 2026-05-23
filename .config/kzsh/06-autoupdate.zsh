# ~/.config/kzsh/06-autoupdate.zsh
# Auto-update KZSH from GitHub

# Check if auto-update is enabled
local auto_update=$(kcfg get "auto_update" 2>/dev/null)
[[ "$auto_update" == "no" ]] && return 0

# Find the repo directory
local repo_dir=""
if [[ -L "${KZSH_DIR}" ]]; then
    # KZSH_DIR is a symlink, find the real repo
    repo_dir=$(readlink -f "${KZSH_DIR}/../..")
elif [[ -d "${KZSH_DIR}/.git" ]]; then
    # Old installation, KZSH_DIR itself is a git repo
    repo_dir="${KZSH_DIR}"
elif [[ -d "$HOME/.kzsh-repo/.git" ]]; then
    # New installation, repo is in ~/.kzsh-repo
    repo_dir="$HOME/.kzsh-repo"
else
    # Not a git repository
    return 0
fi

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
    cd "$repo_dir" || exit
    
    # Fetch updates
    git fetch origin main --quiet 2>/dev/null || exit
    
    # Check if updates available
    local local_commit=$(git rev-parse HEAD 2>/dev/null)
    local remote_commit=$(git rev-parse origin/main 2>/dev/null)
    
    if [[ "$local_commit" != "$remote_commit" ]]; then
        # Updates available
        print -P "\n%F{39}📦 KZSH updates available!%f"
        print -P "%F{242}Run 'kupdate' to update%f\n"
    fi
    
    # Update last check time
    echo "$current_time" > "$update_file"
) &!
