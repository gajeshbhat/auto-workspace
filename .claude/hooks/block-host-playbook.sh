#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) hook.
# Blocks real runs of the workstation playbooks (and install.sh, even with --check: it still
# installs packages and clones before the dry run) on the developer's own machine.
# Allowed: ansible-playbook with --syntax-check/--check/-C in the same invocation, and anything
# executed inside a Multipass VM. Exit 2 blocks; stderr is shown to Claude.
set -uo pipefail

if ! cmd="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')"; then
  echo "block-host-playbook: could not parse hook input; blocking to be safe" >&2
  exit 2
fi

check_flag='(^|[[:space:]])(--syntax-check|--check|-C)([[:space:]]|$)'
playbook='(linux|macos|site)\.yml'
install_run='(^|[;&|[:space:]])(\./install\.sh|(ba)?sh[[:space:]]+([^[:space:]]*/)?install\.sh)|install\.sh[^|]*\|[[:space:]]*(ba)?sh'

[[ "$cmd" == *"multipass exec"* ]] && exit 0

blocked="false"
[[ "$cmd" =~ $install_run ]] && blocked="true"
# Judge each command segment (split on ; & | and newlines) on its own, so a check flag only
# counts when it is an argument of that ansible-playbook invocation.
while IFS= read -r seg; do
  if [[ "$seg" == *ansible-playbook* && "$seg" =~ $playbook && ! "$seg" =~ $check_flag ]]; then
    blocked="true"
  fi
done < <(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')

if [[ "$blocked" == "true" ]]; then
  cat >&2 <<'MSG'
Blocked by .claude/hooks/block-host-playbook.sh: this would provision the
developer's own machine (dist-upgrade, system config, packages as root).
Use instead:
  uv run ansible-playbook ansible/site.yml --syntax-check
  uv run ansible-playbook ansible/site.yml --check --tags always
  scripts/test-in-vm.sh --release 26.04   # real run inside a Multipass VM
MSG
  exit 2
fi
exit 0
