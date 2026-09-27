#!/usr/bin/env bash
# Claude Code PostToolUse(Edit|Write|MultiEdit) hook: fast lint feedback.
#   *.yml/*.yaml -> yamllint the file; files under ansible/ also syntax-check
#                   their playbook (macos.yml for macOS files, else linux.yml)
#   *.sh         -> shellcheck --severity=warning
# Exit 2 feeds the failure output back to Claude. Fails open (exit 0) when the
# toolchain isn't installed yet.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
file="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)"

[[ -n "$file" && -f "$file" ]] || exit 0
case "$file" in *.yml | *.yaml | *.sh) ;; *) exit 0 ;; esac
cd "$ROOT" || exit 0

if [[ ! -x .venv/bin/ansible-playbook ]]; then
  echo "post-edit-check: lint toolchain missing, skipping (run ./scripts/setup-dev.sh)" >&2
  exit 0
fi

rel="${file#"$ROOT"/}"
failed=0

run() {
  local out
  if ! out="$("$@" 2>&1)"; then
    printf '$ %s\n%s\n' "$*" "$out" >&2
    failed=1
  fi
}

case "$rel" in
  *.yml | *.yaml)
    run .venv/bin/yamllint "$rel"
    case "$rel" in
      ansible/macos.yml | ansible/playbooks/macos/*)
        run .venv/bin/ansible-playbook -i ansible/hosts ansible/macos.yml --syntax-check ;;
      ansible/*)
        run .venv/bin/ansible-playbook -i ansible/hosts ansible/linux.yml --syntax-check ;;
    esac
    ;;
  *.sh)
    run .venv/bin/shellcheck --severity=warning "$rel"
    ;;
esac

if ((failed)); then exit 2; fi
exit 0
