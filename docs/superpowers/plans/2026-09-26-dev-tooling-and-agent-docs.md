# Dev Tooling, Bootstrap Scripts, and Agent Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pinned lint toolchain, two one-line scripts (dev setup and machine bootstrap), shell tests, Claude Code project automation, and agent- and human-facing docs to the auto-workspace Ansible repo.

**Architecture:**
- **Toolchain:** a non-package uv project (`pyproject.toml` + `uv.lock`) pins every Python tool. pre-commit calls those tools through `uv run` as local hooks, so versions have a single source of truth.
- **Scripts:** the two entry scripts are plain bash. `install.sh` exposes testable functions behind an `AW_SOURCED` guard.
- **Claude hooks:** small bash scripts that read the hook JSON on stdin (parsed with `python3`, which exists on both OSes).
- **Tests:** plain-bash suites under `tests/`, run by `tests/run.sh`.

**Tech Stack:**

| Component | Version |
|---|---|
| uv | ≥0.12 |
| Python | ≥3.12 |
| ansible-core | 2.21.4 |
| ansible-lint | 26.9.0 |
| yamllint | 1.38.0 |
| pre-commit | 4.6.2 |
| shellcheck-py | 0.11.0.1 |
| pre-commit-hooks | v6.0.0 |
| community.general | 13.4.0 |

Also: bash, Multipass, and Claude Code hooks, agents, and skills.

**Spec:** `docs/superpowers/specs/2026-09-26-dev-tooling-and-agent-docs-design.md`

## Global Constraints

- Branch `feature/workspace-updates`. Never push to `master`, never force-push.
- Commit messages are conventional (`feat:`, `fix:`, `build:`, `style:`, `test:`, `docs:`) and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never run `ansible/linux.yml`, `ansible/macos.yml`, or `install.sh` for real on the host. Only `--syntax-check`, `--check` inside a VM, or `scripts/testing/test-linux-playbook.sh`.
- `requires-python = ">=3.12"` (Ubuntu 24.04 ships 3.12.3; ansible-core 2.21 requires ≥3.12).
- The Python tool versions are pinned exactly (`==`) in `pyproject.toml` and locked in `uv.lock`. Hook revisions in `.pre-commit-config.yaml` are pinned tags.
- `.ansible-lint` uses `profile: min` in this sub-project; sub-project 3 raises it to `production`.
- Scripts start with `set -euo pipefail` (hooks: `set -uo pipefail`, see Task 5), log with `[+]`, and report errors with `[!]` on stderr.
- `setup-dev.sh` never calls `sudo`.
- Shell scripts pass `shellcheck --severity=warning`.
- Changes to existing files are formatting-only (Task 2, separate `style:` commit) except the README fixes in Task 8.
- `AGENTS.md` is canonical. `CLAUDE.md` starts with `@AGENTS.md` and adds only Claude-specific content.

## Review Focus

1. **`curl … | bash` means stdin is the pipe.** A sudo password prompt must not hang or read script bytes. `install.sh` adds `-K` only when `sudo -n true` fails; Ansible's prompt reads `/dev/tty`. Pinned by the Task 9 VM run, where passwordless sudo must not prompt.
2. **`--dir` already exists with local changes, or on another branch.** `install.sh` must stop with git's error and never discard work. Pinned by the `dirty clone` test in Task 4.
3. **Claude runs `./install.sh`, `bash install.sh`, or `curl … install.sh | bash` on the host.** These must be blocked just like a direct `ansible-playbook` run, while `bash tests/scripts/test_install.sh` and `shellcheck install.sh` stay allowed. Pinned by the install cases in Task 5.
4. **PostToolUse hook given a deleted file, a file outside the repo, or input with no `file_path`.** It must exit 0 silently. Pinned by the `nonexistent` and `no file_path` tests in Task 5.
5. **`setup-dev.sh` invoked from another directory** (`bash ~/auto-workspace/scripts/setup-dev.sh` from `$HOME`). It must still act on the repo root. Pinned by Task 3 step 4.

---

## File map

| Path | Responsibility |
|---|---|
| `pyproject.toml`, `uv.lock` | Pinned dev toolchain |
| `requirements.yml` | Ansible Galaxy collections |
| `.gitignore` | Ignore `.venv/` |
| `.yamllint`, `.ansible-lint` | Lint rules |
| `.pre-commit-config.yaml` | Git hooks wiring the linters and the shell tests |
| `scripts/setup-dev.sh` | Dev environment one-liner |
| `install.sh` | Machine bootstrap one-liner |
| `tests/lib.sh` | Assertion helpers |
| `tests/run.sh` | Runs every `tests/*/test_*.sh` |
| `tests/scripts/test_install.sh` | `install.sh` tests |
| `tests/claude/test_hooks.sh` | Claude hook tests |
| `tests/claude/test_config.sh` | `.claude/` config validity tests |
| `.claude/settings.json` | Project hooks registration |
| `.claude/hooks/block-host-playbook.sh` | PreToolUse guard |
| `.claude/hooks/post-edit-check.sh` | PostToolUse lint feedback |
| `.claude/agents/ansible-reviewer.md` | Review subagent |
| `.claude/skills/add-app/SKILL.md` | Add-an-app workflow |
| `.claude/skills/test-in-vm/SKILL.md` | VM test workflow |
| `AGENTS.md`, `CLAUDE.md` | Agent instructions |
| `docs/development.md` | Human dev guide |
| `README.md` | Quickstart and fixes |
| Existing YAML and shell files | Formatting-only fixes (Task 2) |

---

### Task 1: Pinned toolchain and lint config

**Files:**
- Create: `pyproject.toml`, `uv.lock` (generated), `requirements.yml`, `.gitignore`, `.yamllint`, `.ansible-lint`, `.pre-commit-config.yaml`

**Interfaces:**
- Produces:
  - `.venv/bin/{ansible-playbook,ansible-lint,yamllint,shellcheck,pre-commit}` after `uv sync --locked --group dev`
  - pre-commit hook ids `trailing-whitespace`, `end-of-file-fixer`, `check-yaml`, `yamllint`, `ansible-lint`, `shellcheck`
  - collections installed via `uv run --locked ansible-galaxy collection install -r requirements.yml`

- [ ] **Step 1: Create `pyproject.toml`**

```toml
[project]
name = "auto-workspace"
version = "0.0.0"
description = "Ansible provisioning for Ubuntu 24.04 and macOS workstations"
requires-python = ">=3.12"
dependencies = []

[dependency-groups]
dev = [
  "ansible-core==2.21.4",
  "ansible-lint==26.9.0",
  "yamllint==1.38.0",
  "pre-commit==4.6.2",
  "shellcheck-py==0.11.0.1",
]

[tool.uv]
package = false
```

- [ ] **Step 2: Create `requirements.yml`**

```yaml
---
collections:
  - name: community.general
    version: "13.4.0"
```

- [ ] **Step 3: Create `.gitignore`**

```gitignore
.venv/
__pycache__/
```

- [ ] **Step 4: Create `.yamllint`**

```yaml
---
extends: default

rules:
  line-length:
    max: 160
    level: warning
  truthy:
    allowed-values: ['true', 'false', 'yes', 'no']  # tightened in sub-project 3
    check-keys: false
  comments:
    min-spaces-from-content: 1
  comments-indentation: disable
  indentation:
    spaces: 2
    indent-sequences: consistent

ignore: |
  .venv/
  .claude/
```

- [ ] **Step 5: Create `.ansible-lint`**

The `kinds` entries are required. Without them, ansible-lint treats the task files under `ansible/playbooks/` as playbooks.

```yaml
---
profile: min  # raised to production in sub-project 3
offline: true  # collections come from requirements.yml via setup-dev.sh
exclude_paths:
  - .venv/
  - .claude/
  - docs/
kinds:
  - tasks: "**/ansible/playbooks/**/*.yml"
  - playbook: "**/ansible/*.yml"
```

- [ ] **Step 6: Create `.pre-commit-config.yaml`**

```yaml
---
# Python tool versions come from uv.lock (single source of truth); hooks call them via `uv run`.
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
        args: [--markdown-linebreak-ext=md]
      - id: end-of-file-fixer
      - id: check-yaml

  - repo: local
    hooks:
      - id: yamllint
        name: yamllint
        entry: uv run --locked yamllint
        language: system
        types: [yaml]
      - id: ansible-lint
        name: ansible-lint
        entry: uv run --locked ansible-lint
        language: system
        files: ^(ansible/|requirements\.yml$|\.ansible-lint$)
        pass_filenames: false
      - id: shellcheck
        name: shellcheck
        entry: uv run --locked shellcheck --severity=warning
        language: system
        types: [shell]
```

- [ ] **Step 7: Lock and install**

Run:
```bash
uv lock
uv sync --locked --group dev
uv run --locked ansible-galaxy collection install -r requirements.yml
```

Expected:
- `uv.lock` is created.
- `.venv/` exists.
- The output ends with `community.general:13.4.0 was installed successfully` or `... is already installed`.

- [ ] **Step 8: Verify the tools resolve to the pinned versions**

Run: `uv run --locked ansible --version | head -1 && uv run --locked ansible-lint --version | head -1 && uv run --locked yamllint --version && uv run --locked pre-commit --version && uv run --locked shellcheck --version | sed -n 2p`

Expected (in order): `ansible [core 2.21.4]`, `ansible-lint 26.9.0 …`, `yamllint 1.38.0`, `pre-commit 4.6.2`, `version: 0.11.0`

- [ ] **Step 9: Confirm the linters currently fail (red)**

Run: `uv run --locked pre-commit run -a`

Expected: FAIL.
- `yamllint` reports 11 errors: trailing spaces in `ansible/macos.yml:33`, `ansible/playbooks/linux/cleanup.yml:6`, and `install-docker.yml:46`; missing final newlines; `install-dev-tools.yml:189` too many blank lines; and `ansible/macos.yml:32` braces.
- `shellcheck` reports SC2010 at `ansible/playbooks/macos/install-qt.sh:30,156` and SC2034 at `scripts/testing/test-linux-playbook.sh:58`.
- `trailing-whitespace` and `end-of-file-fixer` modify files.
- `ansible-lint` passes.

Then discard the auto-fixes so that Task 2 owns them: `git checkout -- ansible scripts README.md`

- [ ] **Step 10: Commit**

```bash
git add pyproject.toml uv.lock requirements.yml .gitignore .yamllint .ansible-lint .pre-commit-config.yaml
git commit -m "build: Add pinned uv toolchain, lint config and pre-commit hooks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Formatting-only fixes so the linters pass

**Files:**
- Modify (whitespace and EOF only):
  - `ansible/macos.yml`
  - `ansible/playbooks/linux/{cleanup,install-docker,install-dev-tools,initial-setup,install-lxd,install-virtualbox}.yml`
  - `ansible/playbooks/macos/{cleanup,install-applications}.yml`
  - `ansible/playbooks/*/install-qt.sh`
  - any other file the pre-commit fixers touch
- Modify: `ansible/macos.yml:32` (brace spacing)
- Modify: `ansible/playbooks/macos/install-qt.sh:29,155` (shellcheck directives)
- Modify: `scripts/testing/test-linux-playbook.sh:58` (unused loop var)

**Interfaces:** Consumes the Task 1 hooks. Produces a repo where `uv run --locked pre-commit run -a` exits 0.

- [ ] **Step 1: Let the fixers run**

Run: `uv run --locked pre-commit run -a trailing-whitespace; uv run --locked pre-commit run -a end-of-file-fixer`
Expected: the first run of each reports "Fixed …"; re-running each passes.

- [ ] **Step 2: Fix the remaining yamllint errors by hand**

- In `ansible/macos.yml` line 32, change `- { id: 775737590, name: "iA Writer" }` to `- {id: 775737590, name: "iA Writer"}`.
- In `ansible/playbooks/linux/install-dev-tools.yml`, delete the two trailing blank lines at the end of the file, leaving exactly one final newline.

- [ ] **Step 3: Fix the shellcheck warnings without changing behavior**

In `ansible/playbooks/macos/install-qt.sh`, add this line directly above line 30 (`for vol in $(ls /Volumes/ …`) and directly above line 156 (`QT_VOLUME=$(ls /Volumes/ …`), matching each line's indentation:

```bash
# shellcheck disable=SC2010  # volume names are known ASCII; rewritten in sub-project 3
```

In `scripts/testing/test-linux-playbook.sh` line 58, change `for i in {1..60}; do` to `for _ in {1..60}; do`.

- [ ] **Step 4: Verify green, and that only whitespace changed in the YAML**

Run: `uv run --locked pre-commit run -a`
Expected: every hook reports `Passed`.

Run: `git diff --ignore-all-space --ignore-blank-lines --stat -- ansible`
Expected: substantive changes appear only in `ansible/macos.yml` (braces) and `ansible/playbooks/macos/install-qt.sh` (2 comment lines). Any other file listed may differ only by a trailing newline at EOF. Confirm with `git diff -w -- <file>`, which should show only `\ No newline at end of file` changes.

- [ ] **Step 5: Commit**

```bash
git add -A ansible scripts README.md
git commit -m "style: Fix whitespace and lint findings in existing playbooks and scripts

Formatting only; no behavior change.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `scripts/setup-dev.sh`

**Files:**
- Create: `scripts/setup-dev.sh` (mode 755)

**Interfaces:**
- Consumes: `pyproject.toml`, `uv.lock`, `requirements.yml`, `.pre-commit-config.yaml` (Task 1)
- Produces: the command `./scripts/setup-dev.sh`, which is idempotent and exits 0 on success

- [ ] **Step 1: Confirm the failing state**

Run: `./scripts/setup-dev.sh`
Expected: FAIL with `No such file or directory`.

- [ ] **Step 2: Create `scripts/setup-dev.sh`**

```bash
#!/usr/bin/env bash
# One-line dev environment setup for auto-workspace:
#   ./scripts/setup-dev.sh
# Installs uv (if missing), the pinned lint toolchain from uv.lock, the Ansible
# collections from requirements.yml, and the git pre-commit hooks.
# Safe to re-run. Never uses sudo and never changes system packages.
set -euo pipefail

log() { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    log "uv found: $(uv --version)"
    return
  fi
  log "Installing uv (user-local, ~/.local/bin)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v uv >/dev/null 2>&1; then
    err "uv installation failed; see https://docs.astral.sh/uv/"
    exit 1
  fi
}

main() {
  cd "$ROOT"
  ensure_uv
  log "Syncing pinned toolchain from uv.lock..."
  uv sync --locked --group dev
  log "Installing Ansible collections from requirements.yml..."
  uv run --locked ansible-galaxy collection install -r requirements.yml
  log "Installing git pre-commit hooks..."
  uv run --locked pre-commit install
  cat <<'EOF'

[+] Dev environment ready. Next steps:
    uv run pre-commit run -a        # lint everything
    tests/run.sh                    # shell tests
    uv run ansible-playbook -i ansible/hosts ansible/linux.yml --syntax-check
    scripts/testing/test-linux-playbook.sh -k -v   # full run in a Multipass VM
EOF
}

main "$@"
```

Run: `chmod 755 scripts/setup-dev.sh`

- [ ] **Step 3: Run it twice; both runs must succeed**

Run: `./scripts/setup-dev.sh && ./scripts/setup-dev.sh`
Expected:
- Both runs end with `Dev environment ready.`
- The second run prints `uv found`, and `pre-commit installed at …`.
- The exit code is 0.

- [ ] **Step 4: Run it from another directory (Review Focus 5)**

Run: `(cd /tmp && bash "$OLDPWD/scripts/setup-dev.sh" >/dev/null && echo OK)`
Expected: `OK`, and no `.venv` is created in `/tmp` (check with `test ! -e /tmp/.venv && echo clean` → `clean`).

- [ ] **Step 5: Lint and commit**

Run: `uv run --locked pre-commit run --files scripts/setup-dev.sh`
Expected: all hooks pass.

```bash
git add scripts/setup-dev.sh
git commit -m "feat: Add one-line dev environment setup script

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `install.sh` bootstrap and shell test harness

**Files:**
- Create: `tests/lib.sh`, `tests/run.sh` (755), `tests/scripts/test_install.sh`, `install.sh` (755)
- Modify: `.pre-commit-config.yaml` (add the `shell-tests` hook)

**Interfaces:**
- Produces:
  - `tests/lib.sh` functions: `assert_eq EXPECTED ACTUAL NAME`, `assert_contains HAYSTACK NEEDLE NAME`, `status_code` (reads `<rc>|<output>` on stdin and prints `<rc>`), `finish` (exits 1 if any assertion failed)
  - `tests/run.sh`: runs every `tests/*/test_*.sh` and exits non-zero if any suite fails
  - `install.sh`, when sourced with `AW_SOURCED=1`, defines:
    - `parse_args "$@"`, which sets `CHECK`, `BRANCH`, and `DIR`, and exits 2 on bad arguments
    - `detect_playbook`, which prints `linux.yml` or `macos.yml`, or returns 1 with `Unsupported OS`
    - `sync_repo`, which uses `DIR`, `BRANCH`, and `REPO_URL`
    - `ansible_become_flags`, which prints `-K` or nothing
  - Environment overrides: `AW_OS_RELEASE` (os-release path), `AW_UNAME` (kernel name), `AW_REPO_URL` (clone URL)

- [ ] **Step 1: Create `tests/lib.sh`**

```bash
# shellcheck shell=bash
# Minimal assertion helpers for the shell test suites. Source, assert, then call `finish`.
FAILS=0

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
```

- [ ] **Step 2: Create `tests/run.sh`**

```bash
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
```

Run: `chmod 755 tests/run.sh`

- [ ] **Step 3: Write the failing tests in `tests/scripts/test_install.sh`**

```bash
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
```

The dirty-clone case is expected to *succeed* at checking out `master`, because git carries uncommitted changes across branches when it can. What matters is that the local edit survives. The assertion checks that, not the exit code.

- [ ] **Step 4: Run the tests and confirm they fail**

Run: `bash tests/scripts/test_install.sh`
Expected: FAIL. Every case that sources `install.sh` fails, because the file does not exist, ending with `N failure(s)`.

- [ ] **Step 5: Create `install.sh`**

```bash
#!/usr/bin/env bash
# auto-workspace machine bootstrap (Ubuntu 24.04 or macOS):
#   curl -fsSL https://raw.githubusercontent.com/gajeshbhat/auto-workspace/master/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --check --branch <branch> --dir <dir>
# Installs git + uv, clones/updates the repo, syncs the pinned toolchain and
# runs the matching playbook. Everything runs from main() on the last line, so a
# partially downloaded script never executes.
set -euo pipefail

REPO_URL="${AW_REPO_URL:-https://github.com/gajeshbhat/auto-workspace.git}"
OS_RELEASE_FILE="${AW_OS_RELEASE:-/etc/os-release}"
DIR="$HOME/auto-workspace"
BRANCH="master"
CHECK="false"

log() { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

usage() {
  cat <<EOF
Usage: install.sh [--check] [--branch <branch>] [--dir <dir>]
  --check            Run the playbook in check mode (no changes)
  --branch <branch>  Git branch to use (default: $BRANCH)
  --dir <dir>        Clone location (default: $DIR)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) CHECK="true"; shift ;;
      --branch | --dir)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          err "$1 needs a value"; usage >&2; exit 2
        fi
        if [[ "$1" == "--branch" ]]; then BRANCH="$2"; else DIR="$2"; fi
        shift 2 ;;
      -h | --help) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage >&2; exit 2 ;;
    esac
  done
}

# Prints the playbook for this OS (linux.yml | macos.yml) or fails.
detect_playbook() {
  local kernel="${AW_UNAME:-$(uname -s)}" id="" version=""
  if [[ "$kernel" == "Darwin" ]]; then
    echo "macos.yml"
    return 0
  fi
  if [[ "$kernel" == "Linux" && -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck source=/dev/null
    id="$(. "$OS_RELEASE_FILE" && echo "${ID:-}")"
    # shellcheck source=/dev/null
    version="$(. "$OS_RELEASE_FILE" && echo "${VERSION_ID:-}")"
    if [[ "$id" == "ubuntu" && "$version" == "24.04" ]]; then
      echo "linux.yml"
      return 0
    fi
  fi
  err "Unsupported OS ($kernel ${id:-} ${version:-}). auto-workspace supports Ubuntu 24.04 and macOS only."
  return 1
}

ensure_prereqs() {
  local playbook="$1"
  if [[ "$playbook" == "linux.yml" ]]; then
    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
      log "Installing git and curl (sudo)..."
      sudo apt-get update -y
      sudo apt-get install -y git curl
    fi
  elif ! xcode-select -p >/dev/null 2>&1; then
    log "Installing Xcode Command Line Tools - accept the macOS dialog..."
    xcode-select --install || true
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi
}

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    return
  fi
  log "Installing uv (user-local, ~/.local/bin)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1 || { err "uv installation failed"; exit 1; }
}

sync_repo() {
  if [[ -d "$DIR/.git" ]]; then
    local origin
    origin="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$origin" != *auto-workspace* ]]; then
      err "$DIR is not an auto-workspace clone (origin: ${origin:-none}). Pass --dir."
      return 1
    fi
    log "Updating $DIR ($BRANCH)..."
    git -C "$DIR" fetch --quiet origin
    git -C "$DIR" checkout --quiet "$BRANCH"
    git -C "$DIR" pull --quiet --ff-only origin "$BRANCH"
  elif [[ -e "$DIR" ]]; then
    err "$DIR exists but is not a git clone. Move it or pass --dir."
    return 1
  else
    log "Cloning $REPO_URL ($BRANCH) into $DIR..."
    git clone --quiet --branch "$BRANCH" "$REPO_URL" "$DIR"
  fi
}

# Ask for the sudo password only when sudo actually needs one.
ansible_become_flags() {
  if ! sudo -n true 2>/dev/null; then
    echo "-K"
  fi
}

run_playbook() {
  local playbook="$1" become
  cd "$DIR"
  log "Syncing pinned toolchain..."
  uv sync --locked --group dev
  uv run --locked ansible-galaxy collection install -r requirements.yml
  local args=(-i ansible/hosts "ansible/$playbook")
  become="$(ansible_become_flags)"
  if [[ -n "$become" ]]; then args+=("$become"); fi
  if [[ "$CHECK" == "true" ]]; then args+=(--check); fi
  log "Running: ansible-playbook ${args[*]}"
  uv run --locked ansible-playbook "${args[@]}"
}

main() {
  parse_args "$@"
  local playbook
  playbook="$(detect_playbook)"
  log "Target: $playbook (branch $BRANCH, dir $DIR, check=$CHECK)"
  ensure_prereqs "$playbook"
  ensure_uv
  sync_repo
  run_playbook "$playbook"
  log "Done. Log out and back in to apply group changes; a reboot may be required."
}

if [[ -z "${AW_SOURCED:-}" ]]; then
  main "$@"
fi
```

Run: `chmod 755 install.sh`

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `bash tests/scripts/test_install.sh`
Expected: every line reads `ok`, ending with `all passed`, exit 0.

Run: `tests/run.sh`
Expected: `== tests/scripts/test_install.sh … all passed`, exit 0.

- [ ] **Step 7: Wire the tests into pre-commit**

Append to the `local` hooks in `.pre-commit-config.yaml`:

```yaml
      - id: shell-tests
        name: shell tests
        entry: tests/run.sh
        language: system
        files: ^(install\.sh|scripts/|tests/|\.claude/)
        pass_filenames: false
```

Run: `uv run --locked pre-commit run -a`
Expected: all hooks pass, including `shell tests` and `shellcheck` on `install.sh` and `tests/*.sh`.

- [ ] **Step 8: Commit**

```bash
git add install.sh tests/lib.sh tests/run.sh tests/scripts/test_install.sh .pre-commit-config.yaml
git commit -m "feat: Add one-line machine bootstrap install.sh with shell tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Claude Code project hooks

**Files:**
- Create: `.claude/hooks/block-host-playbook.sh` (755), `.claude/hooks/post-edit-check.sh` (755), `tests/claude/test_hooks.sh`
- Create: `.claude/settings.json`. Make this edit through the `update-config` skill, which is the harness's sanctioned way to add hooks.

**Interfaces:**
- Consumes: the hook JSON on stdin (`{"tool_name":…, "tool_input":{"command":…}}` or `{"tool_input":{"file_path":…}}`), and `CLAUDE_PROJECT_DIR`
- Produces: exit 0 to allow or pass, exit 2 to block or report with the message on stderr

- [ ] **Step 1: Write the failing tests in `tests/claude/test_hooks.sh`**

```bash
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
assert_contains "$msg" "test-linux-playbook.sh" "block message suggests VM runner"

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
  cp -R "$ROOT/ansible" "$ROOT/.yamllint" "$P/"
  ln -s "$ROOT/.venv" "$P/.venv"

  assert_eq 0 "$(post "$P" "$P/ansible/playbooks/linux/cleanup.yml" | status_code)" "valid task file passes"

  printf -- '---\n- name: broken\n  apt:\n   name: x\n  bad_indent: [\n' >"$P/ansible/playbooks/linux/cleanup.yml"
  r="$(post "$P" "$P/ansible/playbooks/linux/cleanup.yml")"
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `bash tests/claude/test_hooks.sh`
Expected: FAIL with many `FAIL` lines, because the hook scripts don't exist.

- [ ] **Step 3: Create `.claude/hooks/block-host-playbook.sh`**

```bash
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
```

- [ ] **Step 4: Create `.claude/hooks/post-edit-check.sh`**

```bash
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
```

Run: `chmod 755 .claude/hooks/*.sh`

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `bash tests/claude/test_hooks.sh`
Expected: all `ok`, ending with `all passed`. If any `install.sh` regex case fails, fix the regex in `block-host-playbook.sh`, not the test.

- [ ] **Step 6: Register the hooks in `.claude/settings.json` (via the `update-config` skill)**

The target content:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-host-playbook.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-edit-check.sh", "timeout": 120 }
        ]
      }
    ]
  }
}
```

Run: `python3 -m json.tool .claude/settings.json >/dev/null && echo valid`
Expected: `valid`

- [ ] **Step 7: Full lint and tests, then commit**

Run: `uv run --locked pre-commit run -a && tests/run.sh`
Expected: all pass.

```bash
git add .claude/hooks .claude/settings.json tests/claude/test_hooks.sh
git commit -m "feat: Add Claude Code hooks for post-edit lint and host-run protection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Project subagent and skills

**Files:**
- Create: `.claude/agents/ansible-reviewer.md`, `.claude/skills/add-app/SKILL.md`, `.claude/skills/test-in-vm/SKILL.md`, `tests/claude/test_config.sh`

**Interfaces:**
- Consumes: `scripts/testing/test-linux-playbook.sh` (flags `-n -c -m -d -k -v`), `tests/lib.sh`
- Produces:
  - the subagent `ansible-reviewer`
  - the user-only skills `/add-app <app name>` and `/test-in-vm`
  - `tests/claude/test_config.sh`, which validates every agent and skill frontmatter plus `settings.json`

- [ ] **Step 1: Write the failing config test in `tests/claude/test_config.sh`**

```bash
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
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bash tests/claude/test_config.sh`
Expected: FAIL on `… exists` for all three files.

- [ ] **Step 3: Create `.claude/agents/ansible-reviewer.md`**

```markdown
---
name: ansible-reviewer
description: Reviews Ansible changes in auto-workspace for idempotency, become/user mistakes, apt repo and keyring hygiene, architecture assumptions and Ubuntu/macOS parity. Use after editing anything under ansible/ and before opening a PR.
tools: Read, Grep, Glob, Bash
---

You review Ansible changes in the auto-workspace repo, which provisions Ubuntu 24.04 and macOS workstations against localhost. Review only what changed (`git diff master...HEAD -- ansible/`, plus any file the diff imports). Read-only: do not edit files, and never run a playbook except with `--syntax-check`.

Check every changed task against this list:

1. **Idempotency.** A second run must report `ok`, not `changed`. `shell`/`command` tasks need `creates:`, `removes:`, or `changed_when:`. Downloads use `get_url`. Repo files are written once.
2. **Privilege and user.** Plays run with `become: yes`. Anything touching the user's home must use `/home/{{ username }}` (or `ansible_env.HOME` with `become: false`), never `~`, and files must be owned by `{{ username }}`.
3. **Apt repositories.** Keys live in `/etc/apt/keyrings/<name>.gpg` (dearmored) and are referenced with `signed-by=`. No `apt-key`, no piping keys through `sudo tee` inside `shell`. Prefer `ansible.builtin.deb822_repository`, or `apt_repository` with `filename:`.
4. **Architecture.** Flag hard-coded `amd64`/`x86_64`. Use `{{ ansible_architecture }}` or the dpkg arch, or guard the task with `when:`.
5. **Error masking.** `ignore_errors: yes` needs a reason. Prefer `failed_when:` with an explicit condition.
6. **Check mode.** Tasks that depend on earlier downloads or commands should survive `--check` (use `check_mode: false` for read-only probes, or `when: not ansible_check_mode`).
7. **Parity and docs.** A new Linux app should have a macOS equivalent in `ansible/macos.yml` (`brew_casks`/`brew_formulae`/`mas_applications`) or a stated reason why not, and should be listed in `README.md`.
8. **Secrets.** No credentials, tokens or personal emails in YAML. Qt credentials come from the environment only.

Output one finding per line, most severe first:

`<severity: high|medium|low> <file>:<line> — <problem> → <fix>`

End with `No findings.` if there are none. Do not pad with style nits that ansible-lint already reports.
```

- [ ] **Step 4: Create `.claude/skills/add-app/SKILL.md`**

````markdown
---
name: add-app
description: Add a new application to the auto-workspace playbooks (Ubuntu and macOS), document it in the README, lint, and commit it.
disable-model-invocation: true
argument-hint: <app name>
---

# Add an app to auto-workspace

The app to add: **$ARGUMENTS**

## 1. Pick the Ubuntu install method (first that works)

1. **Snap.** Run `snap info <name>` to confirm it exists; use `classic: true` only if the snap requires it.
2. **Apt, from the Ubuntu 24.04 archive.** Run `apt-cache policy <pkg>` to confirm a candidate exists.
3. **Vendor apt repo.** The key goes to `/etc/apt/keyrings/<name>.gpg` (dearmored), and the repo line uses `signed-by=`. Never use `apt-key`.

State which method you chose and why.

## 2. Add the Ubuntu task

- GUI apps go in `ansible/playbooks/linux/install-gui-apps.yml`; CLI and dev tools in `ansible/playbooks/linux/install-dev-tools.yml`.
- Follow the existing pattern exactly:

```yaml
# --- Install <App> ---
- name: Install <App>
  snap:            # or apt:
    name: <package>
    state: present
  become: true
```

## 3. Add the macOS equivalent

In `ansible/macos.yml`, add the Homebrew cask to `brew_casks`, the formula to `brew_formulae`, or `{id: <n>, name: "<App>"}` to `mas_applications`. Confirm the name with `brew info --cask <name>` when on macOS; otherwise cite formulae.brew.sh. If there is no macOS build, say so in the commit body.

## 4. Document it

Add the app to the matching list under "What Gets Installed" in `README.md`, for both Linux and macOS.

## 5. Verify

```bash
uv run pre-commit run -a
uv run ansible-playbook -i ansible/hosts ansible/linux.yml --syntax-check
```

Both must pass. Offer `/test-in-vm` for a real install test; do not run the playbook on this machine.

## 6. Commit

```bash
git add ansible README.md
git commit -m "feat: Add <App>"
```
````

- [ ] **Step 5: Create `.claude/skills/test-in-vm/SKILL.md`**

````markdown
---
name: test-in-vm
description: Run the Linux playbook for real inside a throwaway Multipass Ubuntu 24.04 VM, then report failed tasks and non-idempotent tasks.
disable-model-invocation: true
argument-hint: "[extra test-linux-playbook.sh flags, e.g. -c 4 -m 8G]"
---

# Test linux.yml in a Multipass VM

This is the only sanctioned way to run `ansible/linux.yml` for real.

1. Check prerequisites: `multipass version` must work. Ensure there is enough free host memory for the VM (the default is 12G; pass `-m 8G` if tight).
2. Start the run in the background, keeping the VM and logging to a file:

   ```bash
   scripts/testing/test-linux-playbook.sh -k -v $ARGUMENTS 2>&1 | tee "$CLAUDE_JOB_DIR/tmp/vm-run-1.log"
   ```

   It takes about 40 minutes. Note the VM name from the `Launching Ubuntu 24.04 VM: <name>` line.
3. Summarize run 1 from the log:
   - the `PLAY RECAP` line
   - every `fatal:` or `FAILED!` task, with its task name and the error message
4. Idempotency check: re-run the playbook in the same VM and capture the recap.

   ```bash
   multipass exec <name> -- bash -lc "cd ~/auto-workspace && ansible-playbook -i ansible/hosts ansible/linux.yml" 2>&1 | tee "$CLAUDE_JOB_DIR/tmp/vm-run-2.log"
   ```

   List every task that reports `changed:` in run 2; each is an idempotency bug.
5. Report: failures (run 1), non-idempotent tasks (run 2), and the VM name, plus the cleanup command `multipass delete <name> && multipass purge`. Ask before deleting the VM.
````

- [ ] **Step 6: Run the config test and confirm it passes**

Run: `bash tests/claude/test_config.sh && tests/run.sh`
Expected: all `ok` / `all passed`, exit 0.

- [ ] **Step 7: Lint and commit**

Run: `uv run --locked pre-commit run -a`
Expected: all pass.

```bash
git add .claude/agents .claude/skills tests/claude/test_config.sh
git commit -m "feat: Add ansible-reviewer subagent and add-app/test-in-vm skills

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `AGENTS.md` and `CLAUDE.md`

**Files:**
- Create: `AGENTS.md`, `CLAUDE.md`
- Modify: `tests/claude/test_config.sh` (add doc assertions)

**Interfaces:**
- Consumes: the command names from Tasks 1–6 (`./scripts/setup-dev.sh`, `uv run pre-commit run -a`, `tests/run.sh`, `scripts/testing/test-linux-playbook.sh`, `/add-app`, `/test-in-vm`, `ansible-reviewer`)

- [ ] **Step 1: Add the failing assertions to `tests/claude/test_config.sh`** (insert before `finish`)

```bash
assert_eq "@AGENTS.md" "$(head -1 "$ROOT/CLAUDE.md" 2>/dev/null)" "CLAUDE.md imports AGENTS.md"
agents="$(cat "$ROOT/AGENTS.md" 2>/dev/null || true)"
for needle in "./scripts/setup-dev.sh" "uv run pre-commit run -a" "tests/run.sh" "test-linux-playbook.sh" "Never run"; do
  assert_contains "$agents" "$needle" "AGENTS.md mentions $needle"
done
```

Run: `bash tests/claude/test_config.sh`
Expected: FAIL on the new assertions.

- [ ] **Step 2: Create `AGENTS.md`**

````markdown
# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, …) and humans working on this repository.

## What this repo is

Ansible playbooks that provision a personal workstation, run against `localhost`:

- **Ubuntu 24.04 LTS**: `ansible/linux.yml`
- **macOS 15**: `ansible/macos.yml`

## Layout

```text
ansible/
  hosts                       # inventory: localhost, local connection
  linux.yml, macos.yml        # entry playbooks: vars + import_tasks
  playbooks/linux/*.yml       # task files imported by linux.yml (not standalone playbooks)
  playbooks/macos/*.yml       # task files imported by macos.yml
  playbooks/*/install-qt.sh   # optional, interactive Qt installer
install.sh                    # one-line machine bootstrap (curl | bash)
scripts/setup-dev.sh          # one-line dev environment setup
scripts/testing/              # Multipass VM runner for linux.yml
scripts/vm-setup/             # UTM helpers for testing macos.yml in a VM
tests/                        # shell tests (tests/run.sh)
docs/development.md           # human development guide
docs/superpowers/             # design specs and implementation plans
.claude/                      # Claude Code hooks, subagent and skills
```

## Commands

```bash
./scripts/setup-dev.sh        # install uv, pinned toolchain, collections, git hooks
uv run pre-commit run -a      # all linters: yamllint, ansible-lint, shellcheck, whitespace
tests/run.sh                  # shell tests for install.sh and the Claude hooks
uv run ansible-playbook -i ansible/hosts ansible/linux.yml --syntax-check
uv run ansible-playbook -i ansible/hosts ansible/macos.yml --syntax-check
scripts/testing/test-linux-playbook.sh -k -v   # real run inside a Multipass VM
```

Tool versions are pinned in `pyproject.toml`/`uv.lock` and collections in `requirements.yml`. Change them deliberately, never float them.

## Safety rules

1. **Never run `ansible/linux.yml`, `ansible/macos.yml` or `install.sh` for real on the machine you are working on.** They dist-upgrade the OS, rewrite system config and install dozens of packages as root. Use `--syntax-check`, `--check`, or `scripts/testing/test-linux-playbook.sh` (Multipass VM). Claude Code enforces this with `.claude/hooks/block-host-playbook.sh`.
2. The plays run with `become: yes`, so `~` and `$HOME` resolve to **root**. For user files use `/home/{{ username }}` and set `owner`/`group`, or `become: false`.
3. Never commit secrets or personal credentials. `install-qt.sh` reads Qt credentials from flags or environment variables only.
4. Work on feature branches. Never push to or rewrite `master`.

## Conventions

- One task per app, with a `# --- Install <App> ---` header comment, grouped by file: GUI apps in `install-gui-apps.yml`, CLI/dev tools in `install-dev-tools.yml`.
- Prefer snap, then Ubuntu apt, then a vendor apt repo. Vendor keys go in `/etc/apt/keyrings/<name>.gpg`, referenced via `signed-by=`; never `apt-key`.
- `shell`/`command` tasks declare `creates:`, `removes:` or `changed_when:` so re-runs are idempotent.
- Every app added on Linux gets its macOS equivalent in `ansible/macos.yml` (`brew_casks`, `brew_formulae`, `mas_applications`) when one exists, and a line in `README.md`.
- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, `[+]` progress and `[!]` error logging, and they must be clean under `shellcheck --severity=warning`.
- Commits: `feat|fix|refactor|docs|build|style|test: <summary>`, one logical change each.

## Definition of done

`uv run pre-commit run -a` and `tests/run.sh` pass, the relevant playbook passes `--syntax-check`, and behavior changes to playbooks have been exercised in a VM (or the gap is stated in the PR).
````

- [ ] **Step 3: Create `CLAUDE.md`**

```markdown
@AGENTS.md

# Claude Code notes

Everything above (from AGENTS.md) applies. This section adds Claude-specific workflow.

## Development workflow (superpowers SDLC)

Use the installed superpowers skills, in order:

1. `superpowers:brainstorming`: for any new feature or behavior change, before touching code. It produces a spec in `docs/superpowers/specs/`.
2. `superpowers:writing-plans`: turns the approved spec into a plan in `docs/superpowers/plans/`.
3. `superpowers:subagent-driven-development` or `superpowers:executing-plans`: carry out the plan task by task.
4. `superpowers:test-driven-development`: here "red" means a failing `tests/run.sh` case, lint error, `--syntax-check` or check-mode run *before* the fix.
5. `superpowers:systematic-debugging`: for any failing run or lint before proposing a fix.
6. `superpowers:verification-before-completion`: run `uv run pre-commit run -a` and `tests/run.sh` and show the output before claiming done.
7. `superpowers:requesting-code-review`, then `superpowers:finishing-a-development-branch`.

Work happens on a feature branch or worktree (`superpowers:using-git-worktrees`).

## Project automation (`.claude/`)

- **Hooks** (`.claude/settings.json`):
  - `post-edit-check.sh` lints and syntax-checks after every YAML or shell edit.
  - `block-host-playbook.sh` refuses real playbook or `install.sh` runs on this machine.
  - Change them via the `update-config` skill.
- **Subagent** `ansible-reviewer`: run it on any change under `ansible/` before opening a PR.
- **Skills** (user-invoked):
  - `/add-app <name>`: adds an app on Ubuntu and macOS, updates the README, commits.
  - `/test-in-vm`: runs the real playbook in a Multipass VM and reports failures and non-idempotent tasks.

## Other useful installed tooling

- `/code-review` and `/security-review` before merging; `/simplify` for cleanup passes.
- `feature-dev` plugin agents: `code-explorer` (trace how something works), `code-architect` (design), `code-reviewer`.
- `claude-code-setup:claude-automation-recommender`: suggests further hooks, skills and MCP servers.
- The `security-guidance` plugin runs automatically on edits.

## Not relevant to this repo

dataviz, artifact and office-document skills (docx/xlsx/pptx/pdf), `mcp-server-dev`, `receipts`, and `claude-api`. Don't reach for them here.
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `bash tests/claude/test_config.sh && uv run --locked pre-commit run -a`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md CLAUDE.md tests/claude/test_config.sh
git commit -m "docs: Add AGENTS.md and CLAUDE.md with SDLC workflow and safety rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `docs/development.md` and README fixes

**Files:**
- Create: `docs/development.md`
- Modify: `README.md`:
  - prerequisites and clone steps: lines 16-45
  - add a Quickstart section after the intro paragraph (line 3)
  - fix the clone URL (`Auto-Workspace-GUI` → `auto-workspace`)
  - fix the variable names in step 3 (`git_user_name`/`git_user_email` → `git_global_user_name`/`git_global_user_email`; `username` is auto-detected)

**Interfaces:** Consumes the commands and paths from Tasks 1–7.

- [ ] **Step 1: Write a failing check for the stale README values**

Run: `grep -nE 'Auto-Workspace-GUI|git_user_name|git_user_email' README.md`
Expected: matches at the clone URL and the vars block. These are the bugs to fix.

- [ ] **Step 2: Create `docs/development.md`**

````markdown
# Development guide

## Prerequisites

- Ubuntu 24.04 or macOS, with `git` and `curl`
- [Multipass](https://multipass.run/) for Linux VM tests; [UTM](https://mac.getutm.app/) for macOS VM tests
- Everything else (uv, Python ≥3.12, ansible-core, linters) is installed by the setup script

## One-line setup

```bash
git clone git@github.com:gajeshbhat/auto-workspace.git && cd auto-workspace && ./scripts/setup-dev.sh
```

`setup-dev.sh` is safe to re-run and never uses sudo. It:

1. installs [uv](https://docs.astral.sh/uv/) if missing
2. runs `uv sync` against `uv.lock`, pinning ansible-core, ansible-lint, yamllint, pre-commit and shellcheck
3. installs the Ansible collections in `requirements.yml`
4. installs the git pre-commit hooks

## Everyday commands

| Task | Command |
|---|---|
| Lint everything | `uv run pre-commit run -a` |
| Shell tests | `tests/run.sh` |
| Syntax-check Linux | `uv run ansible-playbook -i ansible/hosts ansible/linux.yml --syntax-check` |
| Syntax-check macOS | `uv run ansible-playbook -i ansible/hosts ansible/macos.yml --syntax-check` |
| Real Linux run in a VM | `scripts/testing/test-linux-playbook.sh -k -v` |
| macOS VM run | `scripts/vm-setup/utm/quickstart-utm-macos.sh --open`, then `run-ansible.sh` inside the guest |

The pre-commit hooks run automatically on `git commit`. The linters are:

- **yamllint** (`.yamllint`): YAML style
- **ansible-lint** (`.ansible-lint`): currently profile `min`, raised to `production` during the planned refactor
- **shellcheck**: `--severity=warning`
- **whitespace fixers**

> Never run `linux.yml`, `macos.yml` or `install.sh` for real on your own workstation while developing. Use the VM runners.

## Updating pinned tools

```bash
uv add --dev ansible-lint==<new>   # edits pyproject.toml and uv.lock
uv run pre-commit autoupdate       # bumps pre-commit-hooks rev
```

Commit the lockfile changes on their own (`build: Bump ...`).

## Bootstrapping a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/gajeshbhat/auto-workspace/master/install.sh | bash
```

Flags (after `bash -s --`):

- `--check`: check mode, no changes
- `--branch <b>`: use a branch other than `master`
- `--dir <d>`: clone location, default `~/auto-workspace`

It detects Ubuntu 24.04 or macOS, installs git and uv, clones or updates the repo, and runs the matching playbook. It prompts for sudo only if sudo needs a password.

## Adding an app

With Claude Code: `/add-app <name>`. Manually: follow **Conventions** in [`AGENTS.md`](../AGENTS.md). In short:

1. Add the snap/apt task.
2. Add the macOS cask or formula.
3. Add a README line.
4. Run the lint and syntax-check.
5. Commit as `feat: Add <App>`.

## Working with Claude Code

`CLAUDE.md` describes the workflow (superpowers SDLC), the project hooks, the `ansible-reviewer` subagent, and the `/add-app` and `/test-in-vm` skills.
````

- [ ] **Step 3: Update `README.md`**

Insert after the first paragraph (after line 3):

````markdown
### Quickstart

On a fresh Ubuntu 24.04 or macOS machine:

```bash
curl -fsSL https://raw.githubusercontent.com/gajeshbhat/auto-workspace/master/install.sh | bash
```

Add `-s -- --check` after `bash` for a dry run. Developing on this repo? See [docs/development.md](docs/development.md).
````

Replace the step 2 clone block with:

```bash
git clone https://github.com/gajeshbhat/auto-workspace.git
cd auto-workspace
```

Replace the step 3 text and YAML with:

````markdown
3. Update the vars in `ansible/linux.yml` (or `ansible/macos.yml`) with your Git identity. `username` is detected from `$USER`:

```yaml
vars:
  git_global_user_name: "Your Name"
  git_global_user_email: "your.email@example.com"
```
````

Replace the step 4 run block with:

```bash
./scripts/setup-dev.sh
uv run ansible-playbook -i ansible/hosts ansible/linux.yml -K
# -K prompts for your sudo password. Takes ~40 minutes depending on your connection and hardware.
```

- [ ] **Step 4: Verify the fixes and lint**

Run: `grep -nE 'Auto-Workspace-GUI|git_user_name|git_user_email' README.md; echo "rc=$?"`
Expected: `rc=1` (no matches).

Run: `uv run --locked pre-commit run -a`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add docs/development.md README.md
git commit -m "docs: Add development guide and fix README quickstart, clone URL and vars

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: End-to-end verification and push

**Files:** none new. Results go to the PR/handoff notes. Any check-mode playbook failures are listed as input for sub-project 3.

- [ ] **Step 1: Clean-clone check of success criteria 1–2**

Run:
```bash
rm -rf "$CLAUDE_JOB_DIR/tmp/cc" && git clone -q --branch feature/workspace-updates "$(git rev-parse --show-toplevel)" "$CLAUDE_JOB_DIR/tmp/cc" \
  && (cd "$CLAUDE_JOB_DIR/tmp/cc" && ./scripts/setup-dev.sh >/dev/null && uv run --locked pre-commit run -a && tests/run.sh)
```
Expected: pre-commit reports all `Passed`, `tests/run.sh` reports `all passed` for every suite, and the exit code is 0.

- [ ] **Step 2: Push the branch so the raw `install.sh` URL resolves**

Run: `git push origin feature/workspace-updates`

- [ ] **Step 3: Bootstrap check in a fresh Multipass VM (success criterion 3, Review Focus 1)**

Run:
```bash
multipass launch 24.04 --name aw-boot --cpus 2 --memory 4G --disk 20G
multipass exec aw-boot -- bash -lc 'curl -fsSL https://raw.githubusercontent.com/gajeshbhat/auto-workspace/feature/workspace-updates/install.sh | bash -s -- --check --branch feature/workspace-updates' 2>&1 | tee "$CLAUDE_JOB_DIR/tmp/aw-boot.log"
```
Expected:
- The log shows `[+] Target: linux.yml (branch feature/workspace-updates …, check=true)`, the uv install, the clone into `/home/ubuntu/auto-workspace`, and `Running: ansible-playbook -i ansible/hosts ansible/linux.yml --check`.
- There is **no** `-K` and no password prompt, because the `ubuntu` user has passwordless sudo.
- `PLAY [Ubuntu 24.04 LTS Workstation Setup]` starts.

A failure inside check mode (e.g. `Ensure Zoom package was downloaded`) is acceptable per the spec. Record every `fatal:` task name for sub-project 3.

- [ ] **Step 4: Unsupported-OS check in a VM**

Run: `multipass exec aw-boot -- bash -lc 'printf "ID=debian\nVERSION_ID=12\n" > /tmp/osr; AW_OS_RELEASE=/tmp/osr bash ~/auto-workspace/install.sh --check; echo rc=$?'`
Expected: `[!] Unsupported OS …` and `rc=1`.

- [ ] **Step 5: Tear down the VM and confirm the tree is clean**

Run: `multipass delete aw-boot && multipass purge && git status --short`
Expected: no output from `git status --short`.

- [ ] **Step 6: Hook smoke test in a live Claude session**

In Claude Code, ask it to run `uv run ansible-playbook -i ansible/hosts ansible/linux.yml`. Expected: the tool call is blocked, with the message suggesting `test-linux-playbook.sh`. Then edit `ansible/playbooks/linux/cleanup.yml` to add a trailing space. Expected: the PostToolUse hook reports the yamllint `trailing-spaces` error. Revert the edit.
