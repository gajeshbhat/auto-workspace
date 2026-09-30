#!/usr/bin/env bash
# Real provisioning test in a throwaway Multipass VM:
#   scripts/test-in-vm.sh [--release 24.04|26.04] [--keep] [--tags <tags>] [--dotfiles-branch <b>]
# Streams this working tree into the VM (tar over stdin, so hidden/worktree paths work), runs
# ansible/site.yml, then runs it again and fails if the second run changed anything.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE="24.04"
KEEP="false"
TAGS=""
DOTFILES_BRANCH=""
NAME=""
SECOND_RUN="true"
LOG_DIR="${TIV_LOG_DIR:-${TMPDIR:-/tmp}}"

log() { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

usage() {
  cat <<EOF
Usage: scripts/test-in-vm.sh [--release 24.04|26.04] [--keep] [--tags <tags>] [--dotfiles-branch <b>] [--name <vm>] [--no-second-run]
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --release) RELEASE="${2:-}"; shift 2 ;;
      --keep) KEEP="true"; shift ;;
      --tags) TAGS="${2:-}"; shift 2 ;;
      --dotfiles-branch) DOTFILES_BRANCH="${2:-}"; shift 2 ;;
      --name) NAME="${2:-}"; shift 2 ;;
      --no-second-run) SECOND_RUN="false"; shift ;;
      -h | --help) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage >&2; exit 2 ;;
    esac
  done
  if [[ "$RELEASE" != "24.04" && "$RELEASE" != "26.04" ]]; then
    err "Unsupported release: $RELEASE (use 24.04 or 26.04)"
    exit 2
  fi
  NAME="${NAME:-aw-test-${RELEASE//./}}"
}

# recap_changed LOGFILE -> changed= count from the last PLAY RECAP host line, or "missing"
recap_changed() {
  local n
  n="$(awk '/^PLAY RECAP/{seen=1; next} seen && /changed=/{match($0, /changed=[0-9]+/); v=substr($0, RSTART+8, RLENGTH-8)} END{print v}' "$1")"
  echo "${n:-missing}"
}

vm() { multipass exec "$NAME" -- bash -lc "$1"; }

run_playbook() { # run_playbook LOGFILE
  local extra=""
  [[ -n "$TAGS" ]] && extra+=" --tags $TAGS"
  [[ -n "$DOTFILES_BRANCH" ]] && extra+=" -e dotfiles_branch=$DOTFILES_BRANCH"
  vm "cd ~/auto-workspace && ~/.local/bin/uv run --locked ansible-playbook ansible/site.yml$extra" 2>&1 | tee "$1"
  return "${PIPESTATUS[0]}"
}

cleanup() {
  if [[ "$KEEP" == "true" ]]; then
    log "Keeping VM $NAME (multipass delete $NAME && multipass purge)"
  else
    multipass delete "$NAME" && multipass purge
  fi
}

main() {
  parse_args "$@"
  command -v multipass >/dev/null 2>&1 || { err "multipass is not installed"; exit 1; }
  log "Launching $NAME (Ubuntu $RELEASE, 4 CPU, 8G, 40G)"
  multipass launch "$RELEASE" --name "$NAME" --cpus 4 --memory 8G --disk 40G
  trap cleanup EXIT

  log "Copying working tree into the VM"
  vm "rm -rf ~/auto-workspace && mkdir -p ~/auto-workspace"
  (cd "$ROOT" && git ls-files -co --exclude-standard -z | tar --null -cf - -T -) \
    | multipass exec "$NAME" -- tar -xf - -C /home/ubuntu/auto-workspace

  log "Bootstrapping uv and the pinned toolchain"
  vm "curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh >/dev/null"
  vm "cd ~/auto-workspace && ~/.local/bin/uv sync --locked --group dev -q && ~/.local/bin/uv run --locked ansible-galaxy collection install --no-deps -r requirements.yml >/dev/null"

  local run1="$LOG_DIR/$NAME-run1.log" run2="$LOG_DIR/$NAME-run2.log"
  log "Run 1 (log: $run1)"
  run_playbook "$run1"
  if [[ "$SECOND_RUN" == "true" ]]; then
    log "Run 2 - idempotency (log: $run2)"
    run_playbook "$run2"
    local changed
    changed="$(recap_changed "$run2")"
    if [[ "$changed" != "0" ]]; then
      err "Second run reported changed=$changed; tasks that changed:"
      grep -E '^changed:' -B2 "$run2" | grep -E '^TASK' >&2 || true
      exit 1
    fi
    log "Idempotent: second run changed=0"
  fi
  log "PASS ($NAME, Ubuntu $RELEASE)"
}

if [[ -z "${TIV_SOURCED:-}" ]]; then
  main "$@"
fi
