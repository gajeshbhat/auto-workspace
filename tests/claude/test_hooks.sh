#!/usr/bin/env bash
# Tests for the Claude Code project hooks in .claude/hooks/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
BLOCK="$ROOT/.claude/hooks/block-host-playbook.sh"
POST="$ROOT/.claude/hooks/post-edit-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

json_cmd() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }
json_file() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1]}}))' "$1"; }

# block CMD -> exit code of the PreToolUse hook
block() {
  local rc=0
  json_cmd "$1" | bash "$BLOCK" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# --- block-host-playbook: blocked --------------------------------------------
assert_eq 2 "$(block 'uv run ansible-playbook -i ansible/hosts ansible/linux.yml')" "real linux run blocked"
assert_eq 2 "$(block 'ansible-playbook -i ansible/hosts ansible/linux.yml -K')" "real linux run with -K blocked"
assert_eq 2 "$(block 'cd ~/x && ansible-playbook ansible/macos.yml')" "real macos run blocked"
assert_eq 2 "$(block 'ansible-playbook site.yml --checkout-foo')" "--check prefix does not count"
assert_eq 2 "$(block './install.sh')" "./install.sh blocked"
assert_eq 2 "$(block 'bash install.sh --branch dev')" "bash install.sh blocked"
assert_eq 2 "$(block 'curl -fsSL https://raw.githubusercontent.com/gajeshbhat/auto-workspace/master/install.sh | bash')" "curl | bash blocked"
# --- block-host-playbook: allowed --------------------------------------------
assert_eq 0 "$(block 'uv run ansible-playbook -i ansible/hosts ansible/linux.yml --syntax-check')" "syntax-check allowed"
assert_eq 0 "$(block 'ansible-playbook -i ansible/hosts ansible/linux.yml --check')" "--check allowed"
assert_eq 0 "$(block 'ansible-playbook -C ansible/macos.yml')" "-C allowed"
assert_eq 0 "$(block 'multipass exec vm -- bash -lc "cd ~/aw && ansible-playbook -i ansible/hosts ansible/linux.yml"')" "inside multipass allowed"
assert_eq 0 "$(block 'bash install.sh --check')" "install.sh --check allowed"
assert_eq 0 "$(block 'bash tests/scripts/test_install.sh')" "install test suite allowed"
assert_eq 0 "$(block 'shellcheck install.sh')" "shellcheck install.sh allowed"
assert_eq 0 "$(block 'ansible-playbook other.yml')" "unrelated playbook allowed"
assert_eq 0 "$(block 'ls -la')" "unrelated command allowed"
msg="$(json_cmd 'ansible-playbook ansible/linux.yml' | bash "$BLOCK" 2>&1 || true)"
assert_contains "$msg" "test-in-vm.sh" "block message suggests VM runner"

# --- post-edit-check ---------------------------------------------------------
# post PROJECT_DIR FILE -> "<rc>|<stderr>"
post() {
  local rc=0 out
  out="$(json_file "$2" | CLAUDE_PROJECT_DIR="$1" bash "$POST" 2>&1 >/dev/null)" || rc=$?
  printf '%s|%s' "$rc" "$out"
}

# Fail-open when the toolchain is missing.
mkdir -p "$TMP/bare"
printf -- '---\na: 1\n' >"$TMP/bare/x.yml"
r="$(post "$TMP/bare" "$TMP/bare/x.yml")"
assert_eq 0 "${r%%|*}" "no toolchain -> fail open"
assert_contains "$r" "setup-dev.sh" "no toolchain -> hint"

# No-op inputs (Review Focus 4).
assert_eq 0 "$(post "$ROOT" "$TMP/does-not-exist.yml" | status_code)" "nonexistent file ignored"
r=0; printf '{"tool_input":{}}' | CLAUDE_PROJECT_DIR="$ROOT" bash "$POST" >/dev/null 2>&1 || r=$?
assert_eq 0 "$r" "no file_path ignored"
assert_eq 0 "$(post "$ROOT" "$ROOT/README.md" | status_code)" "markdown ignored"

if [[ -x "$ROOT/.venv/bin/ansible-playbook" ]]; then
  # A scratch project: a copy of ansible/ + lint config, sharing the real .venv.
  P="$TMP/proj"
  mkdir -p "$P"
  cp -R "$ROOT/ansible" "$ROOT/.yamllint" "$ROOT/ansible.cfg" "$P/"
  ln -s "$ROOT/.venv" "$P/.venv"

  assert_eq 0 "$(post "$P" "$P/ansible/site.yml" | status_code)" "valid task file passes"

  printf -- '---\n- name: broken\n  apt:\n   name: x\n  bad_indent: [\n' >"$P/ansible/site.yml"
  r="$(post "$P" "$P/ansible/site.yml")"
  assert_eq 2 "${r%%|*}" "broken task file reported"
  assert_contains "$r" "syntax-check" "broken task file runs syntax-check"

  printf '#!/usr/bin/env bash\nfor i in 1 2; do echo hi; done\n' >"$P/bad.sh"
  r="$(post "$P" "$P/bad.sh")"
  assert_eq 2 "${r%%|*}" "shellcheck warning reported"
  assert_contains "$r" "SC2034" "shellcheck code shown"

  printf '#!/usr/bin/env bash\necho ok\n' >"$P/good.sh"
  assert_eq 0 "$(post "$P" "$P/good.sh" | status_code)" "clean script passes"
else
  echo "  skip post-edit toolchain cases (.venv missing; run ./scripts/setup-dev.sh)"
fi

finish
