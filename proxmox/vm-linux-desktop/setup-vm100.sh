#!/usr/bin/env bash
# setup-vm100.sh — Post-boot setup for VM 100 (Ubuntu with GPU passthrough)
#
# Usage (run as root INSIDE VM 100, or via SSH):
#   bash setup-vm100.sh
#
# This script:
#   1. Installs git, gh (GitHub CLI), essential tools
#   2. Configures git identity
#   3. Authenticates with GitHub via gh auth login
#   4. Clones FItnaai and hub-mcp repos
#   5. Sets up basic development environment
#
# Run after VM 100 is booted and has network access.

set -euo pipefail

# ============================================================================
# Configuration — EDIT THESE
# ============================================================================

GIT_USER="${GIT_USER:-XessShare}"
GIT_EMAIL="${GIT_EMAIL:-jonas@fitnaai.de}"
GIT_NAME="${GIT_NAME:-Jonas}"
WORKSPACE="/home/${SUDO_USER:-$(whoami)}/projects"

# ============================================================================
# Functions
# ============================================================================

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# ============================================================================
# System packages
# ============================================================================

log "=== VM 100 Post-Boot Setup ==="
log ""

# Detect OS
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
else
    echo "ERROR: Unsupported package manager"
    exit 1
fi

log "Installing essential packages..."
if [[ "$PKG_MGR" == "apt" ]]; then
    apt-get update -qq

    # Git
    apt-get install -y -qq git curl wget

    # GitHub CLI
    if ! command -v gh &>/dev/null; then
        log "Installing GitHub CLI..."
        (type -p wget >/dev/null || apt-get install wget -y -qq) \
        && mkdir -p -m 755 /etc/apt/keyrings \
        && out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        && cat "$out" | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
        && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli-stable.list > /dev/null \
        && apt-get update -qq \
        && apt-get install gh -y -qq
    fi

    # Build essentials for Python/Node development
    apt-get install -y -qq build-essential python3 python3-pip python3-venv \
        htop tmux jq tree unzip 2>/dev/null || true
fi

log "Packages installed."

# ============================================================================
# Git configuration
# ============================================================================

log "Configuring git..."
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch master
git config --global pull.rebase false
git config --global core.editor "nano"

log "Git configured: ${GIT_NAME} <${GIT_EMAIL}>"

# ============================================================================
# GitHub authentication
# ============================================================================

log ""
log "=== GitHub Authentication ==="

if gh auth status &>/dev/null 2>&1; then
    log "Already authenticated with GitHub."
    gh auth status
else
    log "Please authenticate with GitHub:"
    log ""
    log "Option 1 (Browser — recommended if VM has browser):"
    log "  gh auth login"
    log ""
    log "Option 2 (Token — if no browser available):"
    log "  1. Go to: https://github.com/settings/tokens?type=beta"
    log "  2. Generate new token with 'Contents' read/write permission"
    log "  3. Run: echo 'YOUR_TOKEN' | gh auth login --with-token"
    log ""
    log "Option 3 (SSH key):"
    log "  ssh-keygen -t ed25519 -C '${GIT_EMAIL}'"
    log "  gh auth login -p ssh"
    log ""

    # Try interactive login
    if [[ -t 0 ]]; then
        read -p "Attempt interactive gh auth login now? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gh auth login -p https -w
        fi
    else
        log "Non-interactive mode — run 'gh auth login' manually after setup."
    fi
fi

# ============================================================================
# Clone repositories
# ============================================================================

log ""
log "=== Setting up workspace ==="
mkdir -p "$WORKSPACE"

clone_repo() {
    local repo="$1"
    local dest="${WORKSPACE}/$(basename "$repo")"

    if [[ -d "$dest/.git" ]]; then
        log "Repo already exists: $dest — pulling latest..."
        git -C "$dest" pull --ff-only 2>/dev/null || log "  Pull failed (check auth)"
    else
        log "Cloning ${repo}..."
        gh repo clone "$repo" "$dest" 2>/dev/null || \
            git clone "https://github.com/${repo}.git" "$dest" 2>/dev/null || {
                log "  Clone failed — authenticate first: gh auth login"
                return 1
            }
    fi
    log "  OK: $dest"
}

clone_repo "${GIT_USER}/hub-mcp" || true
clone_repo "${GIT_USER}/FItnaai" || true

# ============================================================================
# Summary
# ============================================================================

log ""
log "=== Setup Complete ==="
log ""
log "Workspace: ${WORKSPACE}"
ls -la "$WORKSPACE" 2>/dev/null || true
log ""
log "Next steps:"
log "  1. If GitHub auth pending: gh auth login"
log "  2. Check GPU: lspci | grep -i amd"
log "  3. Check ROCm: rocm-smi (if installed)"
log "  4. Start development: cd ${WORKSPACE}/FItnaai"
log ""
log "To install ROCm (if needed):"
log "  wget https://repo.radeon.com/amdgpu-install/latest/ubuntu/jammy/amdgpu-install_6.0.60002-1_all.deb"
log "  apt install ./amdgpu-install_*.deb"
log "  amdgpu-install --usecase=rocm"
