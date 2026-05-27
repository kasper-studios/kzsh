# ~/.config/kzsh/06-autoupdate.zsh
# Auto-update KZSH from GitHub
# Uses kzsh_repo_dir from 50-funcs.zsh

# Check if auto-update is enabled
local auto_update=$(kcfg get "auto_update" 2>/dev/null)
[[ "$auto_update" == "no" ]] && return 0

# Find the repo directory
local repo_dir=$(kzsh_repo_dir)
[[ -z "$repo_dir" ]] && return 0

# Check last update time (once per day)
local update_file="${KZSH_DIR}/.last_update"
local current_time=$(date +%s)
local last_update=0

if [[ -f "$update_file" ]]; then
  last_update=$(cat "$update_file" 2>/dev/null || echo 0)
fi

# 86400 seconds = 24 hours
local time_diff=$((current_time - last_update))
[[ $time_diff -lt 86400 ]] && return 0

# Update KZSH in background
(
  cd "$repo_dir" || exit
  git fetch origin main --quiet 2>/dev/null || exit
  local local_commit=$(git rev-parse HEAD 2>/dev/null)
  local remote_commit=$(git rev-parse origin/main 2>/dev/null)

  if [[ "$local_commit" != "$remote_commit" ]]; then
    print -P "\n%F{39}📦 KZSH updates available!%f"
    print -P "%F{242}Run 'kupdate' to update%f\n"
  fi
  echo "$current_time" > "$update_file"
) &!
