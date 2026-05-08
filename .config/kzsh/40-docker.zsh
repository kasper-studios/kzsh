# Docker / Compose aliases
if command -v docker >/dev/null 2>&1; then
  alias dc='docker compose'
  alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
  alias dstats='docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"'
  alias dlogs='docker compose logs -f'
  alias dcu='docker compose up -d'
  alias dcd='docker compose down'
  alias dce='docker compose exec'

  compdef dc='docker'
fi
