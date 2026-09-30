#!/usr/bin/env bash
# Validates the committed Claude Code project config under .claude/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

# frontmatter FILE KEY -> value of KEY in the leading --- block ("" if absent)
frontmatter() {
  python3 - "$1" "$2" <<'EOF'
import sys
path, key = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().split("\n")
if not lines or lines[0] != "---":
    sys.exit(0)
for line in lines[1:]:
    if line == "---":
        break
    k, _, v = line.partition(":")
    if k.strip() == key:
        print(v.strip())
EOF
}

for f in .claude/agents/ansible-reviewer.md .claude/skills/add-app/SKILL.md .claude/skills/test-in-vm/SKILL.md; do
  assert_eq "true" "$(test -f "$ROOT/$f" && echo true)" "$f exists"
  [[ -f "$ROOT/$f" ]] || continue
  assert_eq "true" "$([[ -n "$(frontmatter "$ROOT/$f" name)" ]] && echo true)" "$f has name"
  assert_eq "true" "$([[ -n "$(frontmatter "$ROOT/$f" description)" ]] && echo true)" "$f has description"
done
for s in add-app test-in-vm; do
  f="$ROOT/.claude/skills/$s/SKILL.md"
  [[ -f "$f" ]] || continue
  assert_eq "$s" "$(frontmatter "$f" name)" "$s skill name matches directory"
  assert_eq "true" "$(frontmatter "$f" disable-model-invocation)" "$s is user-only"
done

assert_eq "0" "$(python3 -m json.tool "$ROOT/.claude/settings.json" >/dev/null 2>&1; echo $?)" "settings.json is valid JSON"
for h in "$ROOT"/.claude/hooks/*.sh; do
  assert_eq "true" "$(test -x "$h" && echo true)" "${h#"$ROOT"/} is executable"
done

assert_eq "@AGENTS.md" "$(head -1 "$ROOT/CLAUDE.md" 2>/dev/null)" "CLAUDE.md imports AGENTS.md"
agents="$(cat "$ROOT/AGENTS.md" 2>/dev/null || true)"
for needle in "./scripts/setup-dev.sh" "uv run pre-commit run -a" "tests/run.sh" "scripts/test-in-vm.sh" "Never run"; do
  assert_contains "$agents" "$needle" "AGENTS.md mentions $needle"
done

assert_eq "true" "$( (( $(wc -l < "$ROOT/README.md") <= 45 )) && echo true || echo false)" "README is short (<=45 lines)"
readme="$(cat "$ROOT/README.md")"
for needle in "install.sh" "24.04" "26.04" "group_vars" "Secure Boot" "docs/development.md"; do
  assert_contains "$readme" "$needle" "README mentions $needle"
done
assert_eq "true" "$( (( $(wc -l < "$ROOT/docs/development.md") <= 60 )) && echo true || echo false)" "dev guide fits one screen (<=60 lines)"
assert_contains "$(cat "$ROOT/.claude/skills/add-app/SKILL.md")" "group_vars" "add-app skill edits group_vars"
# "macos.yml" alone is not stale: ansible/group_vars/macos.yml is the current data file.
# Only a bare-directory reference to the old single-file entry playbook (ansible/macos.yml,
# ansible/linux.yml) counts as stale.
assert_eq "" "$(grep -rnE 'ansible/linux\.yml|ansible/macos\.yml|playbooks/linux|install-gui-apps|test-linux-playbook' "$ROOT"/README.md "$ROOT"/docs/development.md "$ROOT"/AGENTS.md "$ROOT"/CLAUDE.md "$ROOT"/.claude || true)" "no stale paths in docs"

finish
