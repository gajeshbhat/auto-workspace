#!/usr/bin/env bash
set -euo pipefail

# - Launches a new VM
# - Copies the current repo into the VM
# - Installs Ansible inside the VM
# - Runs ansible/linux.yml
# - Optionally deletes the VM afterward

NAME="aw-test-$(date +%s)"
CPUS="2"
MEM="12G"
DISK="50G"
KEEP="false"
VERBOSE="false"

usage() {
  cat <<EOF
Usage: $0 [-n name] [-c cpus] [-m mem] [-d disk] [-k] [-v]
  -n name   Name for the Multipass VM (default: $NAME)
  -c cpus   Number of CPUs (default: $CPUS)
  -m mem    Memory size, e.g., 4G (default: $MEM)
  -d disk   Disk size, e.g., 20G (default: $DISK)
  -k        Keep the VM after the run (default: delete)
  -v        Verbose Ansible output
EOF
}

while getopts ":n:c:m:d:kv" opt; do
  case $opt in
    n) NAME="$OPTARG" ;;
    c) CPUS="$OPTARG" ;;
    m) MEM="$OPTARG" ;;
    d) DISK="$OPTARG" ;;
    k) KEEP="true" ;;
    v) VERBOSE="true" ;;
    *) usage; exit 1 ;;
  esac
done

log() { echo -e "[+] $*"; }
err() { echo -e "[!] $*" >&2; }

ensure_multipass() {
  if ! command -v multipass >/dev/null 2>&1; then
    err "Multipass is not installed. Please install it first: https://multipass.run/"
    exit 1
  fi
}

launch_vm() {
  log "Launching Ubuntu 24.04 VM: $NAME (cpus=$CPUS, mem=$MEM, disk=$DISK)"
  multipass launch 24.04 --name "$NAME" --cpus "$CPUS" --mem "$MEM" --disk "$DISK"
}

wait_for_vm() {
  log "Waiting for VM to be running and SSH-ready..."
  for i in {1..60}; do
    state=$(multipass info "$NAME" --format json | grep -o '"state": *"[^"]*"' || true)
    if [[ "$state" == *"Running"* ]]; then
      # Also verify we can exec a command
      if multipass exec "$NAME" -- bash -lc 'echo ok' >/dev/null 2>&1; then
        log "VM is up."
        return 0
      fi
    fi
    sleep 2
  done
  err "VM did not become ready in time."; exit 1
}

copy_repo() {
  log "Copying repository into VM..."
  multipass exec "$NAME" -- bash -lc 'rm -rf ~/auto-workspace && mkdir -p ~/auto-workspace'
  multipass transfer -r . "$NAME":/home/ubuntu/auto-workspace
}

install_ansible_in_vm() {
  log "Installing Ansible and helpers in VM..."
  multipass exec "$NAME" -- bash -lc 'sudo apt-get update -y'
  multipass exec "$NAME" -- bash -lc 'sudo apt-get install -y ansible git ca-certificates curl gnupg python3-apt'
}

check_passwordless_sudo() {
  if multipass exec "$NAME" -- sudo -n true 2>/dev/null; then
    echo "passwordless"
  else
    echo "prompt"
  fi
}

run_playbook() {
  local sudo_mode
  sudo_mode=$(check_passwordless_sudo)

  local extra=""
  if [[ "$VERBOSE" == "true" ]]; then
    extra="-vvv"
  fi

  log "Running isolated Ansible playbook inside VM (sudo: $sudo_mode)..."
  if [[ "$sudo_mode" == "passwordless" ]]; then
    multipass exec "$NAME" -- bash -lc "cd ~/auto-workspace && \
      ANSIBLE_STDOUT_CALLBACK=yaml ansible-playbook -i ansible/hosts ansible/linux.yml $extra"
  else
    echo "If prompted, press Enter if sudo is passwordless; otherwise provide the VM's sudo password."
    multipass exec -i "$NAME" -- bash -lc "cd ~/auto-workspace && \
      ANSIBLE_STDOUT_CALLBACK=yaml ansible-playbook -i ansible/hosts ansible/linux.yml -K $extra"
  fi
}

cleanup() {
  if [[ "$KEEP" == "true" ]]; then
    log "Keeping VM: $NAME"
  else
    log "Deleting VM: $NAME"
    multipass delete "$NAME" || true
    multipass purge || true
  fi
}

main() {
  ensure_multipass
  launch_vm
  wait_for_vm
  copy_repo
  install_ansible_in_vm
  run_playbook
  log "Playbook run completed."
  cleanup
}

main "$@"

