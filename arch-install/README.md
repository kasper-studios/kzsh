# Arch Linux Automated Installer

Universal two-stage installer for Arch Linux with UEFI/BIOS support.

## Features

- ✅ **Universal Boot Support**: Auto-detects UEFI or BIOS/Legacy mode
- ✅ **Flexible Bootloader**: systemd-boot (UEFI) or GRUB (BIOS/UEFI)
- ✅ **Multiple Filesystems**: BTRFS with subvolumes or ext4
- ✅ **Modular Profiles**: Choose your installation type
- ✅ **Optional Swap**: Configurable swap file
- ✅ **Safety Features**: Validation, error cleanup, size checks

## Quick Start

### Interactive Installation (Recommended for first-time users)

```bash
curl -L https://raw.githubusercontent.com/kasper-studios/kzsh/main/arch-install/bootstrap.sh | bash
```

The installer will prompt you for:
- Target disk
- Hostname
- Username
- Filesystem type (btrfs/ext4)
- Swap size (optional)

### Automated Installation

```bash
curl -L https://raw.githubusercontent.com/kasper-studios/kzsh/main/arch-install/bootstrap.sh | bash -s -- \
  --disk /dev/sda \
  --hostname myarch \
  --user myuser \
  --profile desktop-sddm-niri \
  --fs btrfs \
  --swap 4096
```

## Installation Profiles

### Minimal
Bare minimum for a bootable system:
- nano, htop, wget

### Base (Recommended for CLI-only systems)
Common utilities for daily use:
- btop, tree, fastfetch, rsync, zip/unzip, man pages, bash-completion

### Dev
Full development environment:
- base-devel, git, github-cli
- Docker + docker-compose
- Node.js, Python, Rust, Go
- Modern CLI tools: ripgrep, fd, bat, fzf
- Neovim, tmux

### Desktop Profiles

#### desktop-gnome
- GNOME desktop environment
- GDM display manager
- Firefox browser
- Audio support (pipewire)

#### desktop-kde
- KDE Plasma desktop
- SDDM display manager
- Full KDE applications suite
- Firefox browser
- Audio support (pipewire)

#### desktop-sddm-niri
- Niri Wayland compositor
- SDDM display manager
- Waybar, Alacritty, Fuzzel
- Firefox browser
- Thunar file manager
- Audio support (pipewire)

## Options Reference

| Option | Description | Default | Example |
|--------|-------------|---------|---------|
| `--disk` | Target disk device | (interactive) | `/dev/sda` |
| `--hostname` | System hostname | `ponosik` | `myarch` |
| `--user` | Primary username | `kasperenok` | `myuser` |
| `--profile` | Installation profile | `desktop-sddm-niri` | `base` |
| `--fs` | Filesystem type | `btrfs` | `ext4` |
| `--swap` | Swap size in MB | none | `4096` |
| `--bootloader` | Bootloader choice | `auto` | `grub` |
| `--debug` | Enable debug output | disabled | - |

## Two-Stage Process

### Stage 1: Preparation (prep.sh)

Runs from ArchISO live environment:

1. Detects boot mode (UEFI/BIOS)
2. Partitions and formats disk
3. Creates filesystem (BTRFS subvolumes or ext4)
4. Installs base system with `pacstrap`
5. Generates fstab
6. Copies installer to `/mnt/root/arch-install`

**After Stage 1:**
```bash
arch-chroot /mnt /root/arch-install/post.sh --hostname myarch --user myuser --profile base
```

### Stage 2: Post-install (post.sh)

Runs inside chroot:

1. Configures timezone and locale
2. Sets hostname and hosts file
3. Creates user with sudo access
4. Installs and configures bootloader
5. Generates initramfs
6. Enables NetworkManager
7. Runs selected profile

**After Stage 2:**
```bash
exit
umount -R /mnt
reboot
```

## Boot Mode Details

### UEFI Mode
- **Partition scheme**: ESP (512MB FAT32) + Root
- **Default bootloader**: systemd-boot
- **Alternative**: GRUB (use `--bootloader grub`)

### BIOS/Legacy Mode
- **Partition scheme**: BIOS boot (1MB) + Root
- **Bootloader**: GRUB (only option)
- **Auto-detected**: No manual configuration needed

## Filesystem Details

### BTRFS (Default)
**Subvolume layout:**
- `@` → `/` (root)
- `@home` → `/home`
- `@log` → `/var/log`
- `@pkg` → `/var/cache/pacman/pkg`
- `@swap` → `/swap` (if swap enabled)

**Mount options:** `compress=zstd,noatime`

**Benefits:**
- Snapshots support
- Compression
- Easy backup/restore

### ext4
**Layout:**
- Single root partition
- Standard directories

**Benefits:**
- Proven stability
- Wider compatibility
- Simpler structure

## Post-Installation

### 1. First Boot

After reboot, log in with your created user.

### 2. Install KZSH (Optional)

```bash
curl -sL https://raw.githubusercontent.com/kasper-studios/kzsh/main/install.sh | bash
```

This installs the KZSH shell configuration framework.

### 3. Install AUR Helper (Optional)

```bash
# Install yay
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

## Troubleshooting

### No Internet After Reboot

```bash
# Check NetworkManager status
systemctl status NetworkManager

# If not running
sudo systemctl start NetworkManager
sudo systemctl enable NetworkManager

# Connect to WiFi
nmtui
```

### No Audio

```bash
# Check pipewire status
systemctl --user status pipewire pipewire-pulse wireplumber

# If not running
systemctl --user start pipewire pipewire-pulse wireplumber
systemctl --user enable pipewire pipewire-pulse wireplumber
```

### GRUB Not Booting

```bash
# Boot from ArchISO, mount system
mount /dev/sdXY /mnt
arch-chroot /mnt

# Reinstall GRUB
grub-install --target=i386-pc /dev/sdX  # BIOS
# or
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB  # UEFI

grub-mkconfig -o /boot/grub/grub.cfg
```

### Display Manager Not Starting

```bash
# Check service status
systemctl status sddm  # or gdm

# Check logs
journalctl -xeu sddm

# Reinstall display manager
sudo pacman -S sddm
sudo systemctl enable sddm
```

## Safety Features

- **Disk size validation**: Minimum 8GB required
- **Profile validation**: Checks profile exists before starting
- **Error cleanup**: Auto-unmounts on failure
- **Confirmation prompt**: Must type "ERASE" to proceed
- **Debug mode**: Use `--debug` for verbose output

## Limitations

- ❌ No LUKS/LVM encryption support (yet)
- ❌ Single disk only (no RAID)
- ❌ No dual-boot configuration
- ❌ No custom partition layouts

## Examples

### Minimal BIOS System with ext4
```bash
curl -L https://raw.githubusercontent.com/kasper-studios/kzsh/main/arch-install/bootstrap.sh | bash -s -- \
  --disk /dev/sda \
  --hostname miniarch \
  --user admin \
  --profile minimal \
  --fs ext4 \
  --bootloader grub
```

### Development Workstation (UEFI)
```bash
curl -L https://raw.githubusercontent.com/kasper-studios/kzsh/main/arch-install/bootstrap.sh | bash -s -- \
  --disk /dev/nvme0n1 \
  --hostname devbox \
  --user developer \
  --profile dev \
  --fs btrfs \
  --swap 8192
```

### Desktop with GNOME (UEFI)
```bash
curl -L https://raw.githubusercontent.com/kasper-studios/kzsh/main/arch-install/bootstrap.sh | bash -s -- \
  --disk /dev/sda \
  --hostname desktop \
  --user user \
  --profile desktop-gnome \
  --fs btrfs \
  --swap 4096
```

## Contributing

To add a new profile:

1. Create `arch-install/profiles/your-profile.sh`
2. Follow the existing profile structure
3. Include essential packages only
4. Enable required services
5. Test in a VM

## License

Part of the KZSH project. See main repository for license details.
