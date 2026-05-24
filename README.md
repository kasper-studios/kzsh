# kzsh — KASPERENOK ZSH

Кастомная zsh-конфигурация + Arch Linux установщик + desktop профили.

---

## Quickstart — с нуля до десктопа

### 0. Загрузился с Arch ISO

```bash
# Подключение к Wi-Fi (если нужно)
iwctl station wlan0 connect "SSID"

# Запуск установщика
curl -sL https://raw.githubusercontent.com/kasper-studios/kzsh/main/arch-install/bootstrap.sh | bash
```

Bootstrap клонирует репо и запускает интерактивный `prep.sh` — разметка диска, ФС, загрузчик (BIOS/UEFI).

---

### 1. После prep.sh — chroot и post.sh

```bash
arch-chroot /mnt /root/arch-install/post.sh --hostname kasarch --user kasper   --kzsh yes
```

---

### 2. Ребут → первый логин в TTY

```bash
kinstall
```

Установит: `yay` (AUR helper) → mandatory пакеты → спросит про профили.

---

### 3. Установка десктопа

```bash
kpkg install desktop-niri
```

Поставит все пакеты и автоматически:
- Создаст конфиг Niri (`~/.config/niri/config.kdl`)
- Установит DankMaterialShell
- Включит SDDM
- Создаст `niri.desktop` для SDDM

---

### 4. Финальный ребут

```bash
sudo reboot
# → SDDM → выбираешь Niri → DankMaterialShell
```

---

## Профили

```bash
kpkg install core          # fastfetch, btop, htop, tree...
kpkg install dev           # node, docker, rust, go, python...
kpkg install desktop-niri  # Niri + SDDM + DankMaterialShell
kpkg install media         # firefox, discord, mpv, gimp...
kpkg install extra         # steam, wine, obs-studio
```

---

## Keybinds (Niri)

| Бинд | Действие |
|---|---|
| `Super+T` | Kitty (терминал) |
| `Super+D` | tofi (лаунчер) |
| `Super+Q` | Закрыть окно |
| `Super+F` | Максимизировать |
| `Super+Shift+F` | Fullscreen |
| `Super+← →` | Фокус окна |
| `Super+Ctrl+← →` | Переместить окно |
| `Super+1-4` | Переключить воркспейс |
| `Super+Shift+1-4` | Переместить на воркспейс |
| `Super+Shift+E` | Выйти из Niri |
| `Print` | Скриншот |

---

## kzsh команды

```bash
kinstall    # Полная установка
kpkg        # Менеджер пакетов (distro-agnostic)
kdeps       # Проверить зависимости
kupdate     # Обновить kzsh из GitHub
kcfg        # Редактировать конфиг
kapp        # Кастомные шорткаты команд
kstart      # Управление автостартом
khelp       # Шпаргалка
```

---

## Установка только zsh конфига (без Arch)

```bash
curl -sL https://raw.githubusercontent.com/kasper-studios/kzsh/main/install.sh | bash
```

Работает на Arch, Debian, Ubuntu.
