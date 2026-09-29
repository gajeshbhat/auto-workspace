#!/usr/bin/env bash
# auto-workspace machine bootstrap:
#   curl -fsSL https://raw.githubusercontent.com/gajeshbhat/auto-workspace/master/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --check --branch <branch> --dir <dir>
# Installs git + uv, clones/updates the repo, syncs the pinned toolchain and
# runs the matching playbook. Everything runs from main() on the last line, so a
# partially downloaded script never executes.
# Supports Ubuntu 24.04/26.04 and macOS 15/26.
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

# Prints the platform (ubuntu | macos) or fails. Versions are enforced by the playbook's assert.
detect_platform() {
  local kernel="${AW_UNAME:-$(uname -s)}" id="" version=""
  if [[ "$kernel" == "Darwin" ]]; then
    echo "macos"
    return 0
  fi
  if [[ "$kernel" == "Linux" && -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck source=/dev/null
    id="$(. "$OS_RELEASE_FILE" && echo "${ID:-}")"
    # shellcheck source=/dev/null
    version="$(. "$OS_RELEASE_FILE" && echo "${VERSION_ID:-}")"
    if [[ "$id" == "ubuntu" && ("$version" == "24.04" || "$version" == "26.04") ]]; then
      echo "ubuntu"
      return 0
    fi
  fi
  err "Unsupported OS ($kernel ${id:-} ${version:-}). auto-workspace supports Ubuntu 24.04/26.04 and macOS 15/26."
  return 1
}

# Prints the newest "Command Line Tools" label from `softwareupdate -l` output, or nothing.
clt_label_from() {
  printf '%s\n' "$1" | sed -n -e 's/^\* Label: \(Command Line Tools.*\)$/\1/p' \
    -e 's/^ *\* \(Command Line Tools.*\)$/\1/p' | tail -n 1
}

# Installs the Xcode Command Line Tools without the GUI dialog when softwareupdate offers them
# (the same technique Homebrew's installer uses); falls back to the dialog otherwise.
install_clt() {
  xcode-select -p >/dev/null 2>&1 && return
  local flag=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
  log "Installing Xcode Command Line Tools (headless)..."
  touch "$flag"
  label="$(clt_label_from "$(softwareupdate -l 2>&1 || true)")"
  if [[ -n "$label" ]]; then
    refresh_sudo
    sudo softwareupdate -i "$label" --verbose
  fi
  rm -f "$flag"
  if ! xcode-select -p >/dev/null 2>&1; then
    log "softwareupdate did not install them - click Install in the macOS dialog..."
    xcode-select --install || true
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi
}

# Asks for the sudo password once (from the terminal, also under `curl | bash`) unless sudo is
# passwordless, validates it and caches sudo (Homebrew's non-interactive installer only uses
# `sudo -n`). Prints the password on stdout; prints nothing when sudo needs no password.
read_sudo_password() {
  local pw attempt
  if sudo -k -n true 2>/dev/null; then
    return 0
  fi
  for attempt in 1 2 3; do
    printf '[+] Password for %s (sudo, asked once): ' "$USER" >/dev/tty
    IFS= read -rs pw </dev/tty
    printf '\n' >/dev/tty
    if printf '%s\n' "$pw" | sudo -S -p '' -v 2>/dev/null; then
      printf '%s' "$pw"
      return 0
    fi
    err "Wrong password (attempt $attempt/3)."
  done
  err "Could not validate the sudo password."
  return 1
}

# Re-validates the cached sudo timestamp before sudo-using steps (it expires after ~5 minutes,
# and the headless Command Line Tools install can take longer).
refresh_sudo() {
  if [[ -n "${SUDO_PASSWORD:-}" ]]; then
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' -v 2>/dev/null || true
  fi
}

# Reads the password on stdin, writes {"ansible_become_password": ...} to a new mode-600 temp
# file and prints its path. Ansible gets it via `-e @file`; -K never sets the variable.
write_become_vars() {
  local file
  file="$(mktemp "${TMPDIR:-/tmp}/aw-become.XXXXXX")"
  chmod 600 "$file"
  python3 -c 'import json, sys; json.dump({"ansible_become_password": sys.stdin.read()}, open(sys.argv[1], "w"))' "$file"
  printf '%s' "$file"
}

ensure_prereqs() {
  local platform="$1"
  if [[ "$platform" == "ubuntu" ]]; then
    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
      log "Installing git and curl (sudo)..."
      refresh_sudo
      sudo apt-get update -y
      sudo apt-get install -y git curl
    fi
    return
  fi
  install_clt
  if ! command -v brew >/dev/null 2>&1 && [[ ! -x /opt/homebrew/bin/brew && ! -x /usr/local/bin/brew ]]; then
    log "Installing Homebrew..."
    refresh_sudo  # the installer only uses `sudo -n`, so the timestamp must be fresh
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
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

# playbook_args VARS_FILE -> ansible-playbook arguments (VARS_FILE may be empty).
playbook_args() {
  local args=(ansible/site.yml)
  if [[ -n "$1" ]]; then args+=(-e "@$1"); fi
  if [[ "$CHECK" == "true" ]]; then args+=(--check); fi
  echo "${args[*]}"
}

run_playbook() { # run_playbook VARS_FILE
  local args
  cd "$DIR"
  log "Syncing pinned toolchain..."
  uv sync --locked --group dev
  uv run --locked ansible-galaxy collection install -r requirements.yml
  read -ra args <<<"$(playbook_args "$1")"
  log "Running: ansible-playbook ${args[*]}"
  uv run --locked ansible-playbook "${args[@]}"
}

main() {
  parse_args "$@"
  local platform
  platform="$(detect_platform)"
  log "Target: $platform (branch $BRANCH, dir $DIR, check=$CHECK)"
  local vars_file=""
  SUDO_PASSWORD="$(read_sudo_password)"
  ensure_prereqs "$platform"
  ensure_uv
  sync_repo
  # Written only now: on a fresh Mac, python3 is a stub until the Command Line Tools exist.
  if [[ -n "$SUDO_PASSWORD" ]]; then
    vars_file="$(printf '%s' "$SUDO_PASSWORD" | write_become_vars)"
    # shellcheck disable=SC2064  # expand now: remove this exact file on any exit
    trap "rm -f '$vars_file'" EXIT
  fi
  unset SUDO_PASSWORD
  run_playbook "$vars_file"
  log "Done. Log out and back in to apply group changes; a reboot may be required."
}

if [[ -z "${AW_SOURCED:-}" ]]; then
  main "$@"
fi
