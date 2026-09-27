#!/usr/bin/env bash
# Structure tests for ansible/site.yml: syntax, task inventory per play, and forbidden patterns.
# Needs the dev toolchain (./scripts/setup-dev.sh); skips cleanly without it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
cd "$ROOT"

if [[ ! -x .venv/bin/ansible-playbook ]]; then
  echo "  skip (toolchain missing; run ./scripts/setup-dev.sh)"
  exit 0
fi

# list_tasks [ARGS...] -> --list-tasks output (stderr folded in)
list_tasks() { .venv/bin/ansible-playbook ansible/site.yml --list-tasks "$@" 2>&1; }

TASKS="$(list_tasks)"
# expect_task NAME -> assert a task with this exact name is listed
expect_task() { assert_contains "$TASKS" "$1" "task listed: $1"; }

r=0; .venv/bin/ansible-playbook ansible/site.yml --syntax-check >/dev/null 2>&1 || r=$?
assert_eq 0 "$r" "site.yml passes --syntax-check"

assert_contains "$TASKS" "play #1 (localhost): Check platform" "play 1 checks platform"
assert_contains "$TASKS" "play #2 (ubuntu): Provision Ubuntu workstation" "play 2 is Ubuntu"
assert_contains "$TASKS" "play #3 (macos): Provision macOS workstation" "play 3 is macOS"
expect_task "Assert supported platform"
expect_task "Group host by OS"

TAGGED="$(list_tasks --tags languages)"
assert_contains "$TAGGED" "Assert supported platform" "--tags keeps platform assert (always)"
assert_contains "$TAGGED" "Group host by OS" "--tags keeps group_by (always)"

# Platform assert (success criterion 2). --check --tags always runs only play 1 (assert + group_by):
# no become, no changes. With the supported list emptied, this host must be rejected.
r=0; out="$(.venv/bin/ansible-playbook ansible/site.yml --check --tags always -e '{"supported_ubuntu_versions": [], "supported_macos_versions": []}' 2>&1)" || r=$?
assert_eq "true" "$([[ $r -ne 0 ]] && echo true || echo false)" "unsupported platform fails"
assert_contains "$out" "Unsupported platform" "unsupported platform message"
r=0; .venv/bin/ansible-playbook ansible/site.yml --check --tags always >/dev/null 2>&1 || r=$?
assert_eq 0 "$r" "this host passes the platform assert"

forbidden="$(grep -rnE 'apt-key|ignore_errors|newgrp|0777' ansible/ || true)"
assert_eq "" "$forbidden" "no apt-key / ignore_errors / newgrp / 0777 in ansible/"
assert_eq "false" "$(test -e ansible/linux.yml -o -e ansible/playbooks && echo true || echo false)" "old playbooks removed"

# --- role expectations are appended below by later tasks ---

# base
expect_task "Upgrade installed packages"
expect_task "Install base packages"
expect_task "Add Flathub remote"
expect_task "Check Homebrew is installed"
expect_task "Require Homebrew"

finish
