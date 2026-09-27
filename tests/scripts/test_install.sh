#!/usr/bin/env bash
# Tests for install.sh. Functions are exercised by sourcing the script with AW_SOURCED=1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
INSTALL="$ROOT/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_status CMD... -> prints "<exit code>|<combined output>"
run_status() {
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  printf '%s|%s' "$rc" "$out"
}

# --- detect_playbook ---------------------------------------------------------
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$TMP/noble"
printf 'ID=ubuntu\nVERSION_ID="22.04"\n' >"$TMP/jammy"
printf 'ID=debian\nVERSION_ID="12"\n' >"$TMP/debian"

detect() { # detect UNAME OS_RELEASE_FILE
  AW_UNAME="$1" AW_OS_RELEASE="$2" AW_SOURCED=1 bash -c 'source "$1"; detect_playbook' _ "$INSTALL"
}

assert_eq "0|linux.yml" "$(run_status detect Linux "$TMP/noble")" "ubuntu 24.04 -> linux.yml"
assert_eq "0|macos.yml" "$(run_status detect Darwin "$TMP/noble")" "Darwin -> macos.yml"
r="$(run_status detect Linux "$TMP/jammy")"
assert_eq "1" "${r%%|*}" "ubuntu 22.04 rejected"
assert_contains "$r" "Unsupported OS" "ubuntu 22.04 message"
r="$(run_status detect Linux "$TMP/debian")"
assert_eq "1" "${r%%|*}" "debian rejected"
r="$(run_status detect FreeBSD "$TMP/noble")"
assert_eq "1" "${r%%|*}" "FreeBSD rejected"

# --- parse_args --------------------------------------------------------------
r="$(run_status bash "$INSTALL" --bogus)"
assert_eq "2" "${r%%|*}" "unknown flag exits 2"
assert_contains "$r" "Unknown argument: --bogus" "unknown flag message"
r="$(run_status bash "$INSTALL" --branch)"
assert_eq "2" "${r%%|*}" "--branch without value exits 2"
r="$(run_status bash "$INSTALL" --help)"
assert_eq "0" "${r%%|*}" "--help exits 0"
assert_contains "$r" "Usage:" "--help prints usage"
parsed="$(AW_SOURCED=1 bash -c 'source "$1"; shift; parse_args "$@"; echo "$CHECK $BRANCH $DIR"' _ "$INSTALL" --check --branch dev --dir /x/y)"
assert_eq "true dev /x/y" "$parsed" "flags parsed"

# --- sync_repo ---------------------------------------------------------------
# A local "remote" whose path contains auto-workspace, with one commit on master.
REMOTE="$TMP/auto-workspace.git"
git init -q --bare -b master "$REMOTE"
git clone -q "$REMOTE" "$TMP/seed" 2>/dev/null
git -C "$TMP/seed" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$TMP/seed" -c push.gpgSign=false push -q origin master

sync() { # sync DIR
  AW_REPO_URL="$REMOTE" AW_SOURCED=1 bash -c 'source "$1"; DIR="$2"; BRANCH=master; sync_repo' _ "$INSTALL" "$1"
}

assert_eq "0" "$(run_status sync "$TMP/clone" | status_code)" "fresh clone"
assert_eq "true" "$(test -d "$TMP/clone/.git" && echo true)" "clone created"
assert_eq "0" "$(run_status sync "$TMP/clone" | status_code)" "re-run pulls"

mkdir "$TMP/notgit"
r="$(run_status sync "$TMP/notgit")"
assert_eq "1" "${r%%|*}" "existing non-git dir refused"
assert_contains "$r" "not a git clone" "non-git message"

git init -q "$TMP/other"
git -C "$TMP/other" remote add origin https://example.com/someone/else.git
r="$(run_status sync "$TMP/other")"
assert_eq "1" "${r%%|*}" "foreign clone refused"
assert_contains "$r" "not an auto-workspace clone" "foreign clone message"

# Review Focus 2: a dirty clone on another branch must not be clobbered.
git -C "$TMP/clone" checkout -q -b wip
echo local >"$TMP/clone/keep.txt"
git -C "$TMP/clone" add keep.txt
echo changed >"$TMP/clone/keep.txt"
r="$(run_status sync "$TMP/clone")"
assert_eq "changed" "$(cat "$TMP/clone/keep.txt")" "dirty clone: local edit preserved"

finish
