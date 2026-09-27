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

finish
