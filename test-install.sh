#!/bin/bash
# KZSH Installation Test Script
# Tests the installation process in a safe environment

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   KZSH INSTALLATION TEST SUITE        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Test counter
tests_passed=0
tests_failed=0

# Test function
test_check() {
    local name="$1"
    local command="$2"
    
    echo -n "Testing: $name... "
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((tests_passed++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((tests_failed++))
        return 1
    fi
}

# Test 1: Check if running on supported distro
test_check "Distro detection" "[[ -f /etc/os-release ]]"

# Test 2: Check for required commands
test_check "Git installed" "command -v git"
test_check "ZSH installed" "command -v zsh"
test_check "Curl installed" "command -v curl"

# Test 3: Check ZSH version
if command -v zsh >/dev/null 2>&1; then
    zsh_version=$(zsh --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    zsh_major=$(echo "$zsh_version" | cut -d. -f1)
    test_check "ZSH version >= 5.0" "[[ $zsh_major -ge 5 ]]"
fi

# Test 4: Check if KZSH is already installed
if [[ -d "$HOME/.config/kzsh" ]]; then
    echo -e "${YELLOW}⚠ KZSH already installed at ~/.config/kzsh${NC}"
    
    # Check if it's a symlink
    if [[ -L "$HOME/.config/kzsh" ]]; then
        target=$(readlink "$HOME/.config/kzsh")
        echo -e "${BLUE}  → Symlink target: $target${NC}"
        test_check "Symlink is valid" "[[ -e $HOME/.config/kzsh ]]"
    fi
    
    # Check if config.yaml exists
    test_check "config.yaml exists" "[[ -f $HOME/.config/kzsh/config.yaml ]]"
    
    # Check if kzsh.zsh exists
    test_check "kzsh.zsh exists" "[[ -f $HOME/.config/kzsh/kzsh.zsh ]]"
fi

# Test 5: Check if .zshrc has KZSH entrypoint
if [[ -f "$HOME/.zshrc" ]]; then
    test_check ".zshrc has KZSH entrypoint" "grep -q 'kzsh.zsh' $HOME/.zshrc"
fi

# Test 6: Check if repo exists
if [[ -d "$HOME/.kzsh-repo" ]]; then
    test_check "Repository exists" "[[ -d $HOME/.kzsh-repo/.git ]]"
    
    # Check if repo is clean
    cd "$HOME/.kzsh-repo"
    test_check "Repository is clean" "[[ -z \$(git status --porcelain) ]]"
    
    # Check if on main branch
    test_check "On main branch" "[[ \$(git branch --show-current) == 'main' ]]"
fi

# Test 7: Test kcfg function (if KZSH is loaded)
if command -v kcfg >/dev/null 2>&1; then
    test_check "kcfg command available" "command -v kcfg"
    test_check "kcfg can read config" "kcfg get first_run"
fi

# Test 8: Test kpkg function (if KZSH is loaded)
if command -v kpkg >/dev/null 2>&1; then
    test_check "kpkg command available" "command -v kpkg"
fi

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           TEST SUMMARY                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo -e "${GREEN}Passed: $tests_passed${NC}"
echo -e "${RED}Failed: $tests_failed${NC}"
echo ""

if [[ $tests_failed -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
