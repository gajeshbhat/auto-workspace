#!/usr/bin/env bash
# Tests for scripts/test-in-vm.sh argument parsing and recap parsing (no VM is launched).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
TIV="$ROOT/scripts/test-in-vm.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run_status() { local out rc=0; out="$("$@" 2>&1)" || rc=$?; printf '%s|%s' "$rc" "$out"; }
parsed() { TIV_SOURCED=1 bash -c 'source "$1"; shift; parse_args "$@"; echo "$RELEASE|$KEEP|$TAGS|$DOTFILES_BRANCH|$SECOND_RUN"' _ "$TIV" "$@"; }

assert_eq "24.04|false|||true" "$(parsed)" "defaults"
assert_eq "26.04|true|base,repos|feature/chezmoi|false" \
  "$(parsed --release 26.04 --keep --tags base,repos --dotfiles-branch feature/chezmoi --no-second-run)" "all flags"
r="$(run_status bash "$TIV" --release 22.04)"
assert_eq "2" "${r%%|*}" "unsupported release exits 2"
r="$(run_status bash "$TIV" --bogus)"
assert_eq "2" "${r%%|*}" "unknown flag exits 2"
r="$(run_status bash "$TIV" --help)"
assert_eq "0" "${r%%|*}" "--help exits 0"

cat >"$TMP/run.log" <<'EOF'
PLAY RECAP *********************************************************************
localhost                  : ok=12   changed=0    unreachable=0    failed=0    skipped=3    rescued=0    ignored=0
EOF
assert_eq "0" "$(TIV_SOURCED=1 bash -c 'source "$1"; recap_changed "$2"' _ "$TIV" "$TMP/run.log")" "recap changed=0"
sed -i 's/changed=0 /changed=4 /' "$TMP/run.log"
assert_eq "4" "$(TIV_SOURCED=1 bash -c 'source "$1"; recap_changed "$2"' _ "$TIV" "$TMP/run.log")" "recap changed=4"
printf 'no recap here\n' >"$TMP/empty.log"
assert_eq "missing" "$(TIV_SOURCED=1 bash -c 'source "$1"; recap_changed "$2"' _ "$TIV" "$TMP/empty.log")" "missing recap"

finish
