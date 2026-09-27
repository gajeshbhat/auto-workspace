#!/usr/bin/env bash
# auto-workspace machine bootstrap (Ubuntu 24.04 or macOS):
#   curl -fsSL https://raw.githubusercontent.com/gajeshbhat/auto-workspace/master/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --check --branch <branch> --dir <dir>
# Installs git + uv, clones/updates the repo, syncs the pinned toolchain and
# runs the matching playbook. Everything runs from main() on the last line, so a
# partially downloaded script never executes.
set -euo pipefail

REPO_URL="${AW_REPO_URL:-https://github.com/gajeshbhat/auto-workspace.git}"
OS_RELEASE_FILE="${AW_OS_RELEASE:-/etc/os-release}"
DIR="$HOME/auto-workspace"
BRANCH="master"
CHECK="false"

log() { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

usage() {
  cat <<EOF
Usage: install.sh [--check] [--branch <branch>] [--dir <dir>]
  --check            Run the playbook in check mode (no changes)
  --branch <branch>  Git branch to use (default: $BRANCH)
  --dir <dir>        Clone location (default: $DIR)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) CHECK="true"; shift ;;
      --branch | --dir)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          err "$1 needs a value"; usage >&2; exit 2
        fi
        if [[ "$1" == "--branch" ]]; then BRANCH="$2"; else DIR="$2"; fi
        shift 2 ;;
      -h | --help) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage >&2; exit 2 ;;
    esac
  done
}

# Prints the playbook for this OS (linux.yml | macos.yml) or fails.
detect_playbook() {
  local kernel="${AW_UNAME:-$(uname -s)}" id="" version=""
  if [[ "$kernel" == "Darwin" ]]; then
    echo "macos.yml"
    return 0
  fi
  if [[ "$kernel" == "Linux" && -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck source=/dev/null
    id="$(. "$OS_RELEASE_FILE" && echo "${ID:-}")"
    # shellcheck source=/dev/null
    version="$(. "$OS_RELEASE_FILE" && echo "${VERSION_ID:-}")"
    if [[ "$id" == "ubuntu" && "$version" == "24.04" ]]; then
      echo "linux.yml"
      return 0
    fi
  fi
  err "Unsupported OS ($kernel ${id:-} ${version:-}). auto-workspace supports Ubuntu 24.04 and macOS only."
  return 1
}

ensure_prereqs() {
  local playbook="$1"
  if [[ "$playbook" == "linux.yml" ]]; then
    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
      log "Installing git and curl (sudo)..."
      sudo apt-get update -y
      sudo apt-get install -y git curl
    fi
  elif ! xcode-select -p >/dev/null 2>&1; then
    log "Installing Xcode Command Line Tools - accept the macOS dialog..."
    xcode-select --install || true
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi
}

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    return
  fi
  log "Installing uv (user-local, ~/.local/bin)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1 || { err "uv installation failed"; exit 1; }
}

sync_repo() {
  if [[ -d "$DIR/.git" ]]; then
    local origin
    origin="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$origin" != *auto-workspace* ]]; then
      err "$DIR is not an auto-workspace clone (origin: ${origin:-none}). Pass --dir."
      return 1
    fi
    log "Updating $DIR ($BRANCH)..."
    git -C "$DIR" fetch --quiet origin
    git -C "$DIR" checkout --quiet "$BRANCH"
    git -C "$DIR" pull --quiet --ff-only origin "$BRANCH"
  elif [[ -e "$DIR" ]]; then
    err "$DIR exists but is not a git clone. Move it or pass --dir."
    return 1
  else
    log "Cloning $REPO_URL ($BRANCH) into $DIR..."
    git clone --quiet --branch "$BRANCH" "$REPO_URL" "$DIR"
  fi
}

# Ask for the sudo password only when sudo actually needs one.
ansible_become_flags() {
  if ! sudo -n true 2>/dev/null; then
    echo "-K"
  fi
}

run_playbook() {
  local playbook="$1" become
  cd "$DIR"
  log "Syncing pinned toolchain..."
  uv sync --locked --group dev
  uv run --locked ansible-galaxy collection install -r requirements.yml
  local args=(-i ansible/hosts "ansible/$playbook")
  become="$(ansible_become_flags)"
  if [[ -n "$become" ]]; then args+=("$become"); fi
  if [[ "$CHECK" == "true" ]]; then args+=(--check); fi
  log "Running: ansible-playbook ${args[*]}"
  uv run --locked ansible-playbook "${args[@]}"
}

main() {
  parse_args "$@"
  local playbook
  playbook="$(detect_playbook)"
  log "Target: $playbook (branch $BRANCH, dir $DIR, check=$CHECK)"
  ensure_prereqs "$playbook"
  ensure_uv
  sync_repo
  run_playbook "$playbook"
  log "Done. Log out and back in to apply group changes; a reboot may be required."
}

if [[ -z "${AW_SOURCED:-}" ]]; then
  main "$@"
fi
