#!/usr/bin/env bash
set -euo pipefail

# Run Ansible playbook from the auto-mounted UTM share on a macOS guest.
# Usage (inside guest Terminal):
#   sudo bash "/Volumes/My Shared Files/<Your Share Name>/scripts/macos-guest/run-ansible.sh"

log() { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

# Discover the auto-mounted UTM share path that contains this script.
# This allows you to invoke the script regardless of the share folder name.
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)"
SHARE_ROOT="$(cd "$SCRIPT_PATH/../../" && pwd)"  # This should resolve to the repo root inside the share

# Sanity check: does ansible/macos.yml exist?
if [[ ! -f "$SHARE_ROOT/ansible/macos.yml" ]]; then
  err "Could not find ansible/macos.yml under $SHARE_ROOT. Are you running from the auto-mounted share?"
  exit 1
fi

install_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then return; fi
  log "Installing Xcode Command Line Tools (may prompt)..."
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  PROD=$(softwareupdate -l 2>/dev/null | awk -F'*' '/Command Line Tools/ {print $2}' | sed 's/^ *//' | tail -n1 || true)
  if [[ -n "$PROD" ]]; then
    softwareupdate -i "$PROD" --agree-to-license || true
  fi
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress || true
}

install_homebrew() {
  if command -v brew >/dev/null 2>&1; then return; fi
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -d /opt/homebrew/bin ]]; then
    eval "$('/opt/homebrew/bin/brew' shellenv)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /etc/zprofile
  elif [[ -d /usr/local/bin ]]; then
    eval "$('/usr/local/bin/brew' shellenv)"
    echo 'eval "$(/usr/local/bin/brew shellenv)"' >> /etc/zprofile
  fi
}

install_ansible() {
  if command -v ansible >/dev/null 2>&1; then return; fi
  log "Installing Ansible via Homebrew..."
  brew install ansible
}

run_playbook() {
  log "Running Ansible macOS playbook (skip virtualization tags in VM)"
  ANSIBLE_STDOUT_CALLBACK=yaml ansible-playbook "$SHARE_ROOT/ansible/macos.yml" --skip-tags virtualization,docker,virtualbox,multipass -K -vv || true
}

main() {
  install_xcode_clt || true
  install_homebrew || true
  install_ansible || true
  run_playbook
  log "Done."
}

main "$@"

