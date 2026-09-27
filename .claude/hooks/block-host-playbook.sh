#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) hook.
# Blocks real runs of the workstation playbooks (and install.sh) on the
# developer's own machine. Allowed: --syntax-check, --check/-C, and anything
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
[[ "$cmd" =~ $check_flag ]] && exit 0

if [[ "$cmd" == *ansible-playbook* && "$cmd" =~ $playbook ]] || [[ "$cmd" =~ $install_run ]]; then
  cat >&2 <<'EOF'
Blocked by .claude/hooks/block-host-playbook.sh: this would provision the
developer's own machine (dist-upgrade, system config, packages as root).
Use instead:
  uv run ansible-playbook -i ansible/hosts ansible/linux.yml --syntax-check
  uv run ansible-playbook -i ansible/hosts ansible/linux.yml --check
  scripts/testing/test-linux-playbook.sh -k -v   # real run inside a Multipass VM
EOF
  exit 2
fi
exit 0
