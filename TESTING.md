# KZSH Testing Guide

## Quick Test on Virtual Machine

### 1. Prepare VM
```bash
# Arch Linux ISO or existing Arch installation
# Minimum 2GB RAM, 10GB disk
```

### 2. Test Installation Script

#### Option A: Test from local files
```bash
# Copy project to VM
scp -r kzsh/ user@vm:/tmp/

# On VM
cd /tmp/kzsh
bash install.sh
```

#### Option B: Test from GitHub (after push)
```bash
# On VM
curl -sL https://raw.githubusercontent.com/kasper-studios/kzsh/main/install.sh | bash
```

### 3. Run Test Suite
```bash
# After installation
bash /tmp/kzsh/test-install.sh
```

### 4. Test KZSH Functions
```bash
# Start ZSH
zsh

# Test basic commands
kdeps          # Check dependencies
kcfg list      # List config
kcfg validate  # Validate config.yaml
kpkg check git # Check if package installed

# Test profile installation
kpkg install core

# Test update
kupdate
```

### 5. Test Desktop Installation (Full Test)
```bash
# Install desktop profile
kpkg install desktop-niri

# Check if hook ran successfully
ls ~/.config/niri/config.kdl
command -v tofi
command -v yay

# Reboot and test session manager
sudo reboot
# Should see KZSH Session Manager on TTY1
```

## Expected Results

### ✅ Installation Success Indicators
- [ ] No errors during `install.sh`
- [ ] Symlink created: `~/.config/kzsh -> ~/.kzsh-repo/.config/kzsh`
- [ ] `config.yaml` exists and is valid
- [ ] `.zshrc` contains KZSH entrypoint
- [ ] Shell changed to ZSH
- [ ] All test-install.sh tests pass

### ✅ Runtime Success Indicators
- [ ] ZSH starts without errors
- [ ] KZSH banner displays
- [ ] `kdeps` shows installed dependencies
- [ ] `kpkg` can install packages
- [ ] `kcfg` can read/write config
- [ ] `kupdate` can check for updates

### ✅ Desktop Installation Success
- [ ] AUR helper (yay) installed
- [ ] AUR packages (tofi, quickshell-git) installed
- [ ] Niri config created
- [ ] Session manager works on TTY1
- [ ] Desktop starts without errors

## Common Issues & Solutions

### Issue: "Failed to clone repository"
**Solution:** Check internet connection, try with `--depth 1` flag

### Issue: "Symlink is broken"
**Solution:** Remove old symlink: `rm ~/.config/kzsh`, run install again

### Issue: "config.yaml not found"
**Solution:** Config should be created automatically. Check if symlink is valid.

### Issue: "AUR packages fail to install"
**Solution:** Ensure `base-devel` is installed, check internet connection

### Issue: "Session manager doesn't start"
**Solution:** Check if `auto_start_session: yes` in config.yaml

## Rollback

### Uninstall KZSH
```bash
# Remove symlink
rm ~/.config/kzsh

# Remove repository
rm -rf ~/.kzsh-repo

# Remove entrypoint from .zshrc
sed -i '/KASPERENOK ZSH/,+2d' ~/.zshrc

# Change shell back to bash
chsh -s /bin/bash
```

### Restore from backup
```bash
# If backup was created
mv ~/.config/kzsh.backup.* ~/.config/kzsh
```

## Performance Tests

### Shell Startup Time
```bash
# Should be < 100ms
time zsh -i -c exit
```

### Config Read Performance
```bash
# Should be instant
time kcfg get first_run
```

## Automated Testing (TODO)

Future improvements:
- [ ] Docker-based testing
- [ ] CI/CD integration
- [ ] Automated VM testing with Vagrant
- [ ] Unit tests for individual functions
- [ ] Integration tests for full workflow
