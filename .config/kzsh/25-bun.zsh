# ~/.config/kzsh/25-bun.zsh
# Bun-first, npm-second aliases

# Bun shortcuts (only if bun exists)
if command -v bun >/dev/null 2>&1; then
  alias b='bun'
  alias bx='bunx'
  alias ba='bun add'
  alias bad='bun add --dev'
  alias bi='bun install'
  alias br='bun run'
  alias brd='bun run dev'
  alias brb='bun run build'
  alias bu='bun update'
  alias bre='bun remove'
  alias bpm='bun pm'
fi

# Legacy npm aliases (only if npm exists)
if command -v npm >/dev/null 2>&1; then
  alias npms='npm start'
  alias npmi='npm install'
fi

# Dynamic default runner based on config
brun() {
  local tool="npm"
  [[ "$KZSH_BUN_DEFAULT" == "yes" ]] && command -v bun >/dev/null 2>&1 && tool="bun"

  print -P "%F{242}🚀 Running with $tool...%f"
  if [[ "$tool" == "bun" ]]; then
    bun run "$@"
  else
    npm run "$@"
  fi
}

alias rd='brun dev'
alias rb='brun build'
alias rs='brun start'

# Hard cleanup of node/bun garbage
nukejs() {
  print -P "%F{196}💣 Nuking JS garbage...%f"
  rm -rf node_modules bun.lockb package-lock.json pnpm-lock.yaml yarn.lock .next dist build .turbo .cache
  echo "✨ Clean as a whistle. Не благодари."
}
