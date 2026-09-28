#!/usr/bin/env bash
# One-line dev environment setup for auto-workspace:
#   ./scripts/setup-dev.sh
# Installs uv (if missing), the pinned lint toolchain from uv.lock, the Ansible
# collections from requirements.yml, and the git pre-commit hooks.
# Safe to re-run. Never uses sudo and never changes system packages.
set -euo pipefail

log() { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    log "uv found: $(uv --version)"
    return
  fi
  log "Installing uv (user-local, ~/.local/bin)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v uv >/dev/null 2>&1; then
    err "uv installation failed; see https://docs.astral.sh/uv/"
    exit 1
  fi
}

main() {
  cd "$ROOT"
  ensure_uv
  log "Syncing pinned toolchain from uv.lock..."
  uv sync --locked --group dev
  log "Installing Ansible collections from requirements.yml..."
  uv run --locked ansible-galaxy collection install -r requirements.yml
  log "Installing git pre-commit hooks..."
  uv run --locked pre-commit install
  cat <<'EOF'

[+] Dev environment ready. Next steps:
    uv run pre-commit run -a        # lint everything
    tests/run.sh                    # shell tests
    uv run ansible-playbook ansible/site.yml --syntax-check
    scripts/test-in-vm.sh --release 26.04   # full run in a Multipass VM
EOF
}

main "$@"
