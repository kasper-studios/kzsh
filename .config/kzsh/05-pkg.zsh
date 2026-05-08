# ~/.config/kzsh/05-pkg.zsh
# Package manager abstraction layer (kpkg)

kpkg() {
  [[ -z "$1" ]] && {
    echo "KASPERENOK PACKAGE HELPER"
    echo "usage: kpkg <install|update|check|search|clean> [packages|profile]"
    echo "profiles: core, dev, desktop, media, extra, all"
    return 1
  }

  local action="$1"
  shift
  local input_pkgs=("$@")
  local final_pkgs=()

  # Profile handling
  if [[ "$action" == "install" ]]; then
    for item in "${input_pkgs[@]}"; do
      case "$item" in
        core|dev|desktop|media|extra)
          local prof_list=$(kcfg get "profile_$item")
          if [[ -n "$prof_list" ]]; then
            print -P "%F{39}📦 Loading profile: %B$item%b%f"
            final_pkgs+=($=prof_list)
          else
            print -P "%F{242}Profile $item is empty, skipping.%f"
          fi
          ;;
        all)
          for p in core dev desktop media extra; do
            local prof_list=$(kcfg get "profile_$p")
            [[ -n "$prof_list" ]] && final_pkgs+=($=prof_list)
          done
          ;;
        *)
          final_pkgs+=("$item")
          ;;
      esac
    done
  else
    final_pkgs=("${input_pkgs[@]}")
  fi

  [[ ${#final_pkgs[@]} -eq 0 && "$action" == "install" ]] && return 0

  case "$KZSH_DISTRO" in
    ubuntu|debian|kali|pop|mint)
      case "$action" in
        install) sudo apt update && sudo apt install -y "${final_pkgs[@]}" ;;
        update)  sudo apt update && sudo apt upgrade -y ;;
        check)   dpkg -s "$1" >/dev/null 2>&1 ;;
        search)  apt search "$1" ;;
        clean)   sudo apt autoremove -y && sudo apt clean ;;
      esac
      ;;
    arch|manjaro|endeavouros)
      # Detect AUR helper
      local helper="pacman"
      if command -v yay >/dev/null 2>&1; then helper="yay"
      elif command -v paru >/dev/null 2>&1; then helper="paru"
      fi

      case "$action" in
        install)
          if [[ "$helper" == "pacman" ]]; then
            sudo pacman -S --noconfirm "${final_pkgs[@]}"
          else
            "$helper" -S --noconfirm "${final_pkgs[@]}"
          fi
          ;;
        update)
          if [[ "$helper" == "pacman" ]]; then
            sudo pacman -Syu --noconfirm
          else
            "$helper" -Syu --noconfirm
          fi
          ;;
        check)   pacman -Qs "^$1$" >/dev/null 2>&1 ;;
        search)  "$helper" -Ss "$1" ;;
        clean)   
          sudo pacman -Sc --noconfirm
          if command -v paccache >/dev/null 2>&1; then
            sudo paccache -r
          fi
          ;;
      esac
      ;;
    *)
      echo "kpkg: Unsupported distro ($KZSH_DISTRO)"
      return 1
      ;;
  esac
}
