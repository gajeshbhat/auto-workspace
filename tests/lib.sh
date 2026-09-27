# shellcheck shell=bash
# Minimal assertion helpers for the shell test suites. Source, assert, then call `finish`.
FAILS=0

# Inside a git hook (e.g. pre-commit) git exports GIT_DIR, GIT_INDEX_FILE, ... Clear them so
# tests that build scratch repos never touch the repository being committed to.
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1" >&2; FAILS=$((FAILS + 1)); }

# assert_eq EXPECTED ACTUAL NAME
assert_eq() {
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (expected '$1', got '$2')"; fi
}

# assert_contains HAYSTACK NEEDLE NAME
assert_contains() {
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (missing '$2' in: $1)"; fi
}

# status_code: reads "<rc>|<output>" (possibly multi-line) on stdin, prints <rc>
status_code() {
  local r
  r="$(cat)"
  echo "${r%%|*}"
}

finish() {
  if ((FAILS > 0)); then
    echo "$FAILS failure(s)" >&2
    exit 1
  fi
  echo "  all passed"
}
