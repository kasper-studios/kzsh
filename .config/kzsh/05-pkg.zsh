# ~/.config/kzsh/05-pkg.zsh
# Package manager abstraction layer (kpkg)

kpkg() {
  [[ -z "$1" ]] && {
    echo "KASPERENOK PACKAGE HELPER"
    echo "usage: kpkg <install|update|check|search|clean> [packages|profile]"
    echo "profiles: core, dev, desktop, media, extra, all"
    echo ""
    echo "Distro-specific profiles:"
    echo "  arch_*  - Arch Linux specific packages"
    echo "  debian_* - Debian/Ubuntu specific packages"
    return 1
  }

  local action="$1"
  # Shorthands
  [[ "$action" == "i" ]] && action="install"
  [[ "$action" == "u" ]] && action="update"
  [[ "$action" == "s" ]] && action="search"
  [[ "$action" == "c" ]] && action="check"
  
  shift
  local input_pkgs=("$@")
  local final_pkgs=()

  # Profile handling
  if [[ "$action" == "install" ]]; then
    local installed_profiles=()  # Track which profiles were installed
    
    for item in "${input_pkgs[@]}"; do
      case "$item" in
        core|dev|desktop|media|extra|desktop-*|desktop_*)
          # Normalize for display (dashes)
          local display_name="${item//_/-}"
          # Normalize for yaml key lookup (underscores)
          local key_name="${item//-/_}"

          # Try distro-specific profile first, then fallback to generic
          local prof_name="profile_${KZSH_DISTRO}_${key_name}"
          local prof_list=$(kcfg get "$prof_name")
          if [[ -z "$prof_list" ]]; then
            prof_name="profile_${key_name}"
            prof_list=$(kcfg get "$prof_name")
          fi
          if [[ -n "$prof_list" ]]; then
            print -P "%F{39}📦 Loading profile: %B$display_name%b%f (%F{242}$KZSH_DISTRO%f)"
            final_pkgs+=($=prof_list)
            installed_profiles+=("$display_name")
          else
            print -P "%F{242}Profile $display_name is empty, skipping.%f"
          fi
          ;;
        all)
          for p in core dev desktop media extra; do
            local prof_name="profile_${KZSH_DISTRO}_${p}"
            local prof_list=$(kcfg get "$prof_name")
            if [[ -z "$prof_list" ]]; then
              prof_name="profile_${p}"
              prof_list=$(kcfg get "$prof_name")
            fi
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

  # Helper for sudo
  _ksudo() {
    if [[ "$EUID" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
      sudo "$@"
    else
      "$@"
    fi
  }

  case "$KZSH_DISTRO" in
    ubuntu|debian|kali|pop|mint)
      case "$action" in
        install) _ksudo apt update && _ksudo apt install -y "${final_pkgs[@]}" ;;
        update)  _ksudo apt update && _ksudo apt upgrade -y ;;
        check)   dpkg -s "$1" >/dev/null 2>&1 ;;
        search)  apt search "$1" ;;
        clean)   _ksudo apt autoremove -y && _ksudo apt clean ;;
      esac
      ;;
    arch|manjaro|endeavouros)
      # Package mapping (Ubuntu -> Arch)
      local arch_pkgs=()
      local aur_pkgs=()
      
      for p in "${final_pkgs[@]}"; do
        case "$p" in
          build-essential) arch_pkgs+=("base-devel") ;;
          # AUR packages (need AUR helper)
          tofi|quickshell-git|yay|paru)
            aur_pkgs+=("$p")
            ;;
          *)
            arch_pkgs+=("$p")
            ;;
        esac
      done

      # Detect AUR helper
      local helper="pacman"
      if command -v yay >/dev/null 2>&1; then helper="yay"
      elif command -v paru >/dev/null 2>&1; then helper="paru"
      fi

      case "$action" in
        install)
          # Install official packages first
          if [[ ${#arch_pkgs[@]} -gt 0 ]]; then
            if [[ "$helper" == "pacman" ]]; then
              _ksudo pacman -S --noconfirm --needed "${arch_pkgs[@]}"
            else
              "$helper" -S --noconfirm --needed "${arch_pkgs[@]}"
            fi
          fi
          
          # Install AUR packages if AUR helper available
          if [[ ${#aur_pkgs[@]} -gt 0 ]]; then
            if [[ "$helper" == "pacman" ]]; then
              print -P "%F{yellow}⚠ AUR packages require yay or paru: ${aur_pkgs[*]}%f"
              print -P "%F{242}Install yay first: kinstall%f"
            else
              "$helper" -S --noconfirm --needed "${aur_pkgs[@]}"
            fi
          fi
          ;;
        update)
          if [[ "$helper" == "pacman" ]]; then
            _ksudo pacman -Syu --noconfirm
          else
            "$helper" -Syu --noconfirm
          fi
          ;;
        check)   pacman -Qs "^$1$" >/dev/null 2>&1 ;;
        search)  "$helper" -Ss "$1" ;;
        clean)   
          _ksudo pacman -Sc --noconfirm
          if command -v paccache >/dev/null 2>&1; then
            _ksudo paccache -r
          fi
          ;;
      esac
      ;;
    *)
      echo "kpkg: Unsupported distro ($KZSH_DISTRO)"
      return 1
      ;;
  esac

  # Run post-install hooks for profiles
  if [[ "$action" == "install" && ${#installed_profiles[@]} -gt 0 ]]; then
    for profile in "${installed_profiles[@]}"; do
      # Run universal preflight ONLY for desktop-* profiles.
      # Keep it profile-based: base installs safe packages, desktop is checks only.
      # Vendor driver install must remain manual.
      if [[ "$profile" == desktop-* ]]; then
        if command -v kpreflight >/dev/null 2>&1; then
          print -P "\n%F{39}🧪 Running preflight: %Bbase%b (install safe base) ...%f"
          kpreflight base --install
          print -P "\n%F{39}🧪 Running preflight: %Bdesktop%b (checks) ...%f"
          kpreflight desktop
        fi
      fi

      local hook_file="${KZSH_DIR}/hooks/${profile}.sh"
      if [[ -f "$hook_file" && -r "$hook_file" ]]; then
        print -P "\n%F{39}🔧 Running post-install hook for %B$profile%b...%f"
        bash "$hook_file"
      fi
    done
  fi
}
