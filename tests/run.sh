#!/usr/bin/env bash
# Runs every fast shell test suite (tests/*/test_*.sh). Used by pre-commit and CI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0
for suite in "$ROOT"/tests/*/test_*.sh; do
  echo "== ${suite#"$ROOT"/}"
  bash "$suite" || rc=1
done
exit "$rc"
