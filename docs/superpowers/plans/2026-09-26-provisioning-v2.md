# Provisioning v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat Ubuntu/macOS playbooks with one role-based, data-driven `ansible/site.yml` for Ubuntu 24.04/26.04 and macOS 15/26. It installs only the approved apps, including `gh`. Dotfiles and Claude Code config are managed through chezmoi from `gajeshbhat/dotfiles`.

**Architecture:**
- `site.yml` runs three plays: assert and `group_by`, then the Ubuntu play, then the macOS play.
- Roles are split by concern. Each role picks its OS tasks with static `import_tasks … when:`, and every app list lives in `ansible/group_vars/{all,ubuntu,macos}.yml`.
- Two kinds of verification:
  - `tests/ansible/test_site.sh` checks structure: syntax-check, `--list-tasks` expectations, and forbidden patterns.
  - `scripts/test-in-vm.sh` does real runs: Multipass install, then an idempotency run.

**Tech Stack:**
- ansible-core 2.21.4 and community.general 13.4.0, with `deb822_repository`, `snap`, `flatpak`, `homebrew*` and `mas`
- chezmoi, Multipass, bash
- the existing uv/pre-commit toolchain from sub-project 1

**Spec:** `docs/superpowers/specs/2026-09-26-provisioning-v2-design.md`

## Global Constraints

- **Branch:** `feature/workspace-updates`. The dotfiles work goes on branch `feature/chezmoi` of `gajeshbhat/dotfiles`, as a **draft** PR. Never push to `master`, never force-push, never merge.
- **Commits** are conventional and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. GPG signing is on; if a commit fails with `Inappropriate ioctl`, stop and ask the user to unlock GPG.
- **Never run `ansible/site.yml` or `install.sh` for real on the host.** Only use `--syntax-check`, `--list-tasks`, or `scripts/test-in-vm.sh`.
- **Supported platforms:** Ubuntu `24.04`, `26.04`; macOS major `15`, `26`.
- **Pinned versions:** `go_version: "1.27.1"`, `fvm_version: "4.3.1"`, VirtualBox package `virtualbox-7.2`.
- **Code style:**
  - FQCN modules everywhere
  - play-level `become: false`, task-level `become: true` only for system changes
  - every variable registered or set inside a role is prefixed with the role name (ansible-lint `var-naming[no-role-prefix]`)
  - `.ansible-lint` `profile: production`
  - yamllint truthy values `true`/`false` only
- **Idempotency:** a second run reports `changed=0`. `command`/`shell` tasks use `creates:` or `changed_when:`, and read-only probes set `changed_when: false` and `check_mode: false`.
- **Docs:** the README is at most ~40 lines, and `docs/development.md` fits on one screen.
- **Secrets:** never track or copy `~/.claude/.credentials.json`, history, sessions, projects, caches or `skills/synced`.
- **Git identity:** keep `git_user_name: "Gajesh Bhat"` and `git_user_email: "myemail@example.com"` (the existing values). Don't put a real email into the repo.

## Review Focus

1. **Upgrading the user's existing machine**, which has old `/etc/apt/sources.list.d/*.list` files with different `Signed-By` keyrings. Apt must not fail with "Conflicting values set for option Signed-By". → Task 4 removes the legacy sources, and Task 10 step 4 seeds a VM with a legacy `docker.list` and runs the playbook over it.
2. **Local dotfile edits,** e.g. Claude settings changed via `/config`, must never be overwritten by a re-run. → Task 9's role skips applying and warns, and Task 10 step 5 edits `~/.claude/settings.json` in the VM and re-runs.
3. **Running with `--tags <role>`** must still assert the platform and group the host. Otherwise the Ubuntu or macOS play silently matches no hosts. → Task 1 tags the play-1 tasks `always`, and `test_site.sh` checks `--list-tasks --tags languages`.
4. **arm64 hosts** (Linux on Apple Silicon or Graviton): amd64-only vendor apps (Chrome, Zoom, VirtualBox) must be skipped rather than failing. → the `architectures` filters (Tasks 4, 5), with `test_site.sh` assertions on the data. No arm64 VM exists here, so this gap is noted in the handoff.
5. **macOS runs can't be executed here.** A mistake would surface only on the user's Mac, e.g. Homebrew missing from PATH on Apple Silicon, or `mas` not signed in. → the macOS play sets PATH with `/opt/homebrew/bin`, the base role asserts `brew` exists, and `test_site.sh` checks the macOS task list. A real run is deferred to CI (sub-project 5) and stated in the handoff.

---

## File map

| Path | Responsibility |
|---|---|
| `ansible.cfg` | Root config: inventory path and output format |
| `ansible/inventory/hosts.yml` | localhost with a local connection |
| `ansible/site.yml` | assert + `group_by` play, Ubuntu play, macOS play |
| `ansible/group_vars/all.yml` | supported versions, user paths, git identity, dotfiles repo, versions |
| `ansible/group_vars/ubuntu.yml` | `dpkg_arch`, `base_packages`, `vendor_repos`, `apt_packages`, `snap_packages`, `flatpak_packages`, `deb_packages` |
| `ansible/group_vars/macos.yml` | `brew_formulae`, `brew_casks`, `mas_apps` |
| `ansible/roles/base/` | Ubuntu: upgrade, base packages, Flathub. macOS: assert Homebrew |
| `ansible/roles/vendor_repos/` | legacy-source cleanup, foreign archs, deb822 repos, vendor packages |
| `ansible/roles/packages/` | apt / snap / flatpak / .deb (Ubuntu); formulae / casks / mas (macOS) |
| `ansible/roles/docker/` | Docker service + `docker` group (Ubuntu) |
| `ansible/roles/virtualization/` | KVM/libvirt, groups, LXD init, VirtualBox Extension Pack (Ubuntu) |
| `ansible/roles/languages/` | Flutter deps, Go, uv (Ubuntu); fvm tap (macOS); rustup, fvm → Flutter, dotrun (both) |
| `ansible/roles/claude_code/` | Claude Code official installer |
| `ansible/roles/dotfiles/` | chezmoi install, first init, pull, safe apply |
| `install.sh` | detects `ubuntu`/`macos`, installs Homebrew on macOS, runs `ansible/site.yml` |
| `scripts/test-in-vm.sh` | Multipass real run + idempotency run |
| `scripts/vm-setup/macos-guest/run-ansible.sh` | points at `ansible/site.yml` |
| `tests/ansible/test_site.sh` | structure tests for the playbook |
| `tests/scripts/test_install.sh`, `tests/scripts/test_test_in_vm.sh` | script tests |
| `tests/claude/test_hooks.sh`, `tests/claude/test_config.sh` | updated for the new paths |
| `.claude/hooks/post-edit-check.sh` | syntax-check `ansible/site.yml` for `ansible/**` edits |
| `.ansible-lint`, `.yamllint` | production profile; strict truthy |
| `README.md`, `docs/development.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/skills/*`, `.claude/agents/ansible-reviewer.md` | docs for the new layout |
| **Deleted** | `ansible/linux.yml`, `ansible/macos.yml`, `ansible/hosts`, `ansible/playbooks/`, `scripts/testing/`, `scripts/README.md` |
| **Separate repo** `gajeshbhat/dotfiles` @ `feature/chezmoi` | chezmoi source (Task 8) |

---

### Task 1: New entry point, lint profile, and switched-over scripts/hooks

**Files:**
- Create:
  - `ansible.cfg`
  - `ansible/inventory/hosts.yml`, `ansible/site.yml`, `ansible/group_vars/all.yml`
  - `ansible/group_vars/ubuntu.yml`, `ansible/group_vars/macos.yml` (start with `---` only)
  - `ansible/roles/.gitkeep`
  - `tests/ansible/test_site.sh`
- Modify:
  - `.ansible-lint`, `.yamllint`
  - `install.sh`, `tests/scripts/test_install.sh`
  - `.claude/hooks/post-edit-check.sh`, `tests/claude/test_hooks.sh`
  - `scripts/vm-setup/macos-guest/run-ansible.sh`
- Delete: `ansible/linux.yml`, `ansible/macos.yml`, `ansible/hosts`, `ansible/playbooks/`

**Interfaces:**
- **Produces:**
  - `site.yml`, with its first play named `Check platform` and tasks `Assert supported platform` and `Group host by OS`, both tagged `always`; a play `Provision Ubuntu workstation` (`hosts: ubuntu`); and a play `Provision macOS workstation` (`hosts: macos`).
  - `tests/ansible/test_site.sh` with the helpers `list_tasks [ARGS…]` (prints `--list-tasks` output) and `expect_task NAME`. Later tasks append `expect_task` lines.
  - In `install.sh`: `detect_platform` prints `ubuntu` or `macos`, or returns 1.
  - Group vars: `workstation_home`, `workstation_user`, `local_bin`, `installer_cache`, `user_path`, `git_user_name`, `git_user_email`, `dotfiles_repo`, `dotfiles_branch`, `go_version`, `fvm_version`, `flutter_channel`.

- [ ] **Step 1: Write the failing structure test `tests/ansible/test_site.sh`**

```bash
#!/usr/bin/env bash
# Structure tests for ansible/site.yml: syntax, task inventory per play, and forbidden patterns.
# Needs the dev toolchain (./scripts/setup-dev.sh); skips cleanly without it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
cd "$ROOT"

if [[ ! -x .venv/bin/ansible-playbook ]]; then
  echo "  skip (toolchain missing; run ./scripts/setup-dev.sh)"
  exit 0
fi

# list_tasks [ARGS...] -> --list-tasks output (stderr folded in)
list_tasks() { .venv/bin/ansible-playbook ansible/site.yml --list-tasks "$@" 2>&1; }

TASKS="$(list_tasks)"
# expect_task NAME -> assert a task with this exact name is listed
expect_task() { assert_contains "$TASKS" "$1" "task listed: $1"; }

r=0; .venv/bin/ansible-playbook ansible/site.yml --syntax-check >/dev/null 2>&1 || r=$?
assert_eq 0 "$r" "site.yml passes --syntax-check"

assert_contains "$TASKS" "play #1 (localhost): Check platform" "play 1 checks platform"
assert_contains "$TASKS" "play #2 (ubuntu): Provision Ubuntu workstation" "play 2 is Ubuntu"
assert_contains "$TASKS" "play #3 (macos): Provision macOS workstation" "play 3 is macOS"
expect_task "Assert supported platform"
expect_task "Group host by OS"

TAGGED="$(list_tasks --tags languages)"
assert_contains "$TAGGED" "Assert supported platform" "--tags keeps platform assert (always)"
assert_contains "$TAGGED" "Group host by OS" "--tags keeps group_by (always)"

# Platform assert (success criterion 2). --check --tags always runs only play 1 (assert + group_by):
# no become, no changes. With the supported list emptied, this host must be rejected.
r=0; out="$(.venv/bin/ansible-playbook ansible/site.yml --check --tags always -e '{"supported_ubuntu_versions": [], "supported_macos_versions": []}' 2>&1)" || r=$?
assert_eq "true" "$([[ $r -ne 0 ]] && echo true || echo false)" "unsupported platform fails"
assert_contains "$out" "Unsupported platform" "unsupported platform message"
r=0; .venv/bin/ansible-playbook ansible/site.yml --check --tags always >/dev/null 2>&1 || r=$?
assert_eq 0 "$r" "this host passes the platform assert"

forbidden="$(grep -rnE 'apt-key|ignore_errors|newgrp|0777' ansible/ || true)"
assert_eq "" "$forbidden" "no apt-key / ignore_errors / newgrp / 0777 in ansible/"
assert_eq "false" "$(test -e ansible/linux.yml -o -e ansible/playbooks && echo true || echo false)" "old playbooks removed"

# --- role expectations are appended below by later tasks ---

finish
```

Run: `chmod 755 tests/ansible/test_site.sh && bash tests/ansible/test_site.sh`
Expected: FAIL, because `ansible/site.yml` doesn't exist yet (syntax-check fails, the plays are missing, and "old playbooks removed" fails).

- [ ] **Step 2: Update `tests/scripts/test_install.sh` for `detect_platform` (red)**

Replace the `detect()` helper and the five detection assertions (the block under `# --- detect_playbook`) with:

```bash
# --- detect_platform ---------------------------------------------------------
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$TMP/noble"
printf 'ID=ubuntu\nVERSION_ID="26.04"\n' >"$TMP/resolute"
printf 'ID=ubuntu\nVERSION_ID="22.04"\n' >"$TMP/jammy"
printf 'ID=debian\nVERSION_ID="12"\n' >"$TMP/debian"

detect() { # detect UNAME OS_RELEASE_FILE
  AW_UNAME="$1" AW_OS_RELEASE="$2" AW_SOURCED=1 bash -c 'source "$1"; detect_platform' _ "$INSTALL"
}

assert_eq "0|ubuntu" "$(run_status detect Linux "$TMP/noble")" "ubuntu 24.04 -> ubuntu"
assert_eq "0|ubuntu" "$(run_status detect Linux "$TMP/resolute")" "ubuntu 26.04 -> ubuntu"
assert_eq "0|macos" "$(run_status detect Darwin "$TMP/noble")" "Darwin -> macos"
r="$(run_status detect Linux "$TMP/jammy")"
assert_eq "1" "${r%%|*}" "ubuntu 22.04 rejected"
assert_contains "$r" "Unsupported OS" "ubuntu 22.04 message"
r="$(run_status detect Linux "$TMP/debian")"
assert_eq "1" "${r%%|*}" "debian rejected"
r="$(run_status detect FreeBSD "$TMP/noble")"
assert_eq "1" "${r%%|*}" "FreeBSD rejected"
```

Also append before `finish`:

```bash
# --- playbook invocation ----------------------------------------------------
assert_contains "$(cat "$INSTALL")" "ansible/site.yml" "install.sh runs ansible/site.yml"
assert_eq "" "$(grep -E 'linux\.yml|macos\.yml' "$INSTALL" || true)" "install.sh no longer references linux/macos.yml"
```

Run: `bash tests/scripts/test_install.sh`
Expected: FAIL on `ubuntu 26.04 -> ubuntu`, `Darwin -> macos` and the invocation assertions.

- [ ] **Step 3: Update `tests/claude/test_hooks.sh` for the new layout (red)**

In the `post-edit-check` scratch-project block:
- replace `cp -R "$ROOT/ansible" "$ROOT/.yamllint" "$P/"` with `cp -R "$ROOT/ansible" "$ROOT/.yamllint" "$ROOT/ansible.cfg" "$P/"`
- replace both occurrences of `ansible/playbooks/linux/cleanup.yml` with `ansible/site.yml`

The broken-file case then writes invalid YAML into `$P/ansible/site.yml` and expects exit 2 and `syntax-check`.

Run: `bash tests/claude/test_hooks.sh`
Expected: FAIL. `cp` of `ansible.cfg` fails, or "valid task file passes" fails, because `site.yml` doesn't exist.

- [ ] **Step 4: Create `ansible.cfg`**

```ini
[defaults]
inventory = ansible/inventory/hosts.yml
stdout_callback = ansible.builtin.default
callback_result_format = yaml
retry_files_enabled = false
interpreter_python = auto_silent
```

- [ ] **Step 5: Create `ansible/inventory/hosts.yml`**

```yaml
---
all:
  hosts:
    localhost:
      ansible_connection: local
```

- [ ] **Step 6: Create `ansible/group_vars/all.yml`**

```yaml
---
supported_ubuntu_versions: ["24.04", "26.04"]
supported_macos_versions: ["15", "26"]

# The play runs as the invoking user; system tasks opt into become.
workstation_user: "{{ ansible_facts['user_id'] }}"
workstation_home: "{{ ansible_facts['user_dir'] }}"
local_bin: "{{ workstation_home }}/.local/bin"
installer_cache: "{{ workstation_home }}/.cache/auto-workspace"
user_path: >-
  {{ local_bin }}:{{ workstation_home }}/.cargo/bin:{{ workstation_home }}/fvm/bin:/usr/local/go/bin:/opt/homebrew/bin:/usr/local/bin:{{ ansible_facts['env']['PATH'] }}

git_user_name: "Gajesh Bhat"
git_user_email: "myemail@example.com"

dotfiles_repo: "gajeshbhat/dotfiles"
dotfiles_branch: "master"

go_version: "1.27.1"
fvm_version: "4.3.1"
flutter_channel: "stable"
```

Create `ansible/group_vars/ubuntu.yml` and `ansible/group_vars/macos.yml`, each containing only `---`, and create an empty `ansible/roles/.gitkeep`.

- [ ] **Step 7: Create `ansible/site.yml`**

```yaml
---
- name: Check platform
  hosts: localhost
  gather_facts: true
  tasks:
    - name: Assert supported platform
      tags: [always]
      ansible.builtin.assert:
        that: >-
          (ansible_facts['distribution'] == 'Ubuntu'
           and ansible_facts['distribution_version'] in supported_ubuntu_versions)
          or (ansible_facts['os_family'] == 'Darwin'
           and (ansible_facts['distribution_major_version'] | string) in supported_macos_versions)
        fail_msg: >-
          Unsupported platform: {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}.
          Supported: Ubuntu {{ supported_ubuntu_versions | join(', ') }}; macOS {{ supported_macos_versions | join(', ') }}.
        quiet: true

    - name: Group host by OS
      tags: [always]
      ansible.builtin.group_by:
        key: "{{ 'macos' if ansible_facts['os_family'] == 'Darwin' else 'ubuntu' }}"

- name: Provision Ubuntu workstation
  hosts: ubuntu
  gather_facts: false
  environment:
    PATH: "{{ user_path }}"
  roles: []

- name: Provision macOS workstation
  hosts: macos
  gather_facts: false
  environment:
    PATH: "{{ user_path }}"
  roles: []
```

- [ ] **Step 8: Delete the old tree and tighten the lint config**

Run: `git rm -r -q ansible/linux.yml ansible/macos.yml ansible/hosts ansible/playbooks`

Replace `.ansible-lint` with:

```yaml
---
profile: production
offline: true  # collections come from requirements.yml via setup-dev.sh
exclude_paths:
  - .venv/
  - .claude/
  - docs/
```

In `.yamllint`, replace the `truthy:` block with:

```yaml
  truthy:
    allowed-values: ['true', 'false']
    check-keys: false
```

- [ ] **Step 9: Update `install.sh`**

Replace `detect_playbook` with:

```bash
# Prints the platform (ubuntu | macos) or fails. Versions are enforced by the playbook's assert.
detect_platform() {
  local kernel="${AW_UNAME:-$(uname -s)}" id="" version=""
  if [[ "$kernel" == "Darwin" ]]; then
    echo "macos"
    return 0
  fi
  if [[ "$kernel" == "Linux" && -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck source=/dev/null
    id="$(. "$OS_RELEASE_FILE" && echo "${ID:-}")"
    # shellcheck source=/dev/null
    version="$(. "$OS_RELEASE_FILE" && echo "${VERSION_ID:-}")"
    if [[ "$id" == "ubuntu" && ("$version" == "24.04" || "$version" == "26.04") ]]; then
      echo "ubuntu"
      return 0
    fi
  fi
  err "Unsupported OS ($kernel ${id:-} ${version:-}). auto-workspace supports Ubuntu 24.04/26.04 and macOS 15/26."
  return 1
}
```

Replace `ensure_prereqs` with:

```bash
ensure_prereqs() {
  local platform="$1"
  if [[ "$platform" == "ubuntu" ]]; then
    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
      log "Installing git and curl (sudo)..."
      sudo apt-get update -y
      sudo apt-get install -y git curl
    fi
    return
  fi
  if ! xcode-select -p >/dev/null 2>&1; then
    log "Installing Xcode Command Line Tools - accept the macOS dialog..."
    xcode-select --install || true
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi
  if ! command -v brew >/dev/null 2>&1 && [[ ! -x /opt/homebrew/bin/brew && ! -x /usr/local/bin/brew ]]; then
    log "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}
```

In `run_playbook`, drop the `playbook` parameter and replace the line `local args=(-i ansible/hosts "ansible/$playbook")` with `local args=(ansible/site.yml)`. The inventory now comes from `ansible.cfg`. Change the signature to `run_playbook() {` and use `local become`.

In `main`, replace:

```bash
  local playbook
  playbook="$(detect_playbook)"
  log "Target: $playbook (branch $BRANCH, dir $DIR, check=$CHECK)"
  ensure_prereqs "$playbook"
  ensure_uv
  sync_repo
  run_playbook "$playbook"
```

with:

```bash
  local platform
  platform="$(detect_platform)"
  log "Target: $platform (branch $BRANCH, dir $DIR, check=$CHECK)"
  ensure_prereqs "$platform"
  ensure_uv
  sync_repo
  run_playbook
```

Update the header comment's support line to `# Supports Ubuntu 24.04/26.04 and macOS 15/26.`

- [ ] **Step 10: Update `.claude/hooks/post-edit-check.sh`**

Replace the inner `case "$rel" in … esac` for YAML with:

```bash
    case "$rel" in
      ansible/*)
        run .venv/bin/ansible-playbook ansible/site.yml --syntax-check ;;
    esac
```

and update the header comment line to `#   *.yml/*.yaml -> yamllint the file; files under ansible/ also syntax-check ansible/site.yml`.

- [ ] **Step 11: Point the macOS guest runner at `site.yml`**

In `scripts/vm-setup/macos-guest/run-ansible.sh`:
- change the sanity check `ansible/macos.yml` to `ansible/site.yml` (both occurrences, including the error message)
- change the run line to `ANSIBLE_STDOUT_CALLBACK=yaml ansible-playbook "$SHARE_ROOT/ansible/site.yml" --skip-tags virtualization -K -vv || true`

- [ ] **Step 12: Run everything green**

Run: `bash tests/ansible/test_site.sh && bash tests/scripts/test_install.sh && bash tests/claude/test_hooks.sh`
Expected: each ends `all passed`.

Run: `uv run --locked pre-commit run -a`
Expected: all hooks `Passed`, with ansible-lint on the `production` profile.

- [ ] **Step 13: Commit**

```bash
git add -A ansible ansible.cfg .ansible-lint .yamllint install.sh .claude/hooks/post-edit-check.sh scripts/vm-setup tests
git commit -m "refactor: Replace per-OS playbooks with site.yml entry point and production lint

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `scripts/test-in-vm.sh` (real run + idempotency)

**Files:**
- Create: `scripts/test-in-vm.sh` (755), `tests/scripts/test_test_in_vm.sh`
- Modify: `.claude/skills/test-in-vm/SKILL.md`, `AGENTS.md` (commands block), `tests/claude/test_config.sh` (needle)
- Delete: `scripts/testing/`, `scripts/README.md`

**Interfaces:**
- **Produces:**
  - The command `scripts/test-in-vm.sh [--release 24.04|26.04] [--keep] [--tags <t>] [--dotfiles-branch <b>] [--name <vm>] [--no-second-run]`, which exits non-zero if either run fails or the second recap shows `changed>0`.
  - When sourced with `TIV_SOURCED=1`: `parse_args "$@"`, which sets `RELEASE`, `KEEP`, `TAGS`, `DOTFILES_BRANCH`, `NAME` and `SECOND_RUN`, and exits 2 on bad args; and `recap_changed LOGFILE`, which prints the `changed=` count from the last `PLAY RECAP` line.

- [ ] **Step 1: Write the failing tests `tests/scripts/test_test_in_vm.sh`**

```bash
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
```

Run: `bash tests/scripts/test_test_in_vm.sh`
Expected: FAIL (the script doesn't exist).

- [ ] **Step 2: Create `scripts/test-in-vm.sh`**

```bash
#!/usr/bin/env bash
# Real provisioning test in a throwaway Multipass VM:
#   scripts/test-in-vm.sh [--release 24.04|26.04] [--keep] [--tags <tags>] [--dotfiles-branch <b>]
# Streams this working tree into the VM (tar over stdin, so hidden/worktree paths work), runs
# ansible/site.yml, then runs it again and fails if the second run changed anything.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE="24.04"
KEEP="false"
TAGS=""
DOTFILES_BRANCH=""
NAME=""
SECOND_RUN="true"
LOG_DIR="${TIV_LOG_DIR:-${TMPDIR:-/tmp}}"

log() { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

usage() {
  cat <<EOF
Usage: scripts/test-in-vm.sh [--release 24.04|26.04] [--keep] [--tags <tags>] [--dotfiles-branch <b>] [--name <vm>] [--no-second-run]
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --release) RELEASE="${2:-}"; shift 2 ;;
      --keep) KEEP="true"; shift ;;
      --tags) TAGS="${2:-}"; shift 2 ;;
      --dotfiles-branch) DOTFILES_BRANCH="${2:-}"; shift 2 ;;
      --name) NAME="${2:-}"; shift 2 ;;
      --no-second-run) SECOND_RUN="false"; shift ;;
      -h | --help) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage >&2; exit 2 ;;
    esac
  done
  if [[ "$RELEASE" != "24.04" && "$RELEASE" != "26.04" ]]; then
    err "Unsupported release: $RELEASE (use 24.04 or 26.04)"
    exit 2
  fi
  NAME="${NAME:-aw-test-${RELEASE//./}}"
}

# recap_changed LOGFILE -> changed= count from the last PLAY RECAP host line, or "missing"
recap_changed() {
  local n
  n="$(awk '/^PLAY RECAP/{seen=1; next} seen && /changed=/{match($0, /changed=[0-9]+/); v=substr($0, RSTART+8, RLENGTH-8)} END{print v}' "$1")"
  echo "${n:-missing}"
}

vm() { multipass exec "$NAME" -- bash -lc "$1"; }

run_playbook() { # run_playbook LOGFILE
  local extra=""
  [[ -n "$TAGS" ]] && extra+=" --tags $TAGS"
  [[ -n "$DOTFILES_BRANCH" ]] && extra+=" -e dotfiles_branch=$DOTFILES_BRANCH"
  vm "cd ~/auto-workspace && ~/.local/bin/uv run --locked ansible-playbook ansible/site.yml$extra" 2>&1 | tee "$1"
  return "${PIPESTATUS[0]}"
}

cleanup() {
  if [[ "$KEEP" == "true" ]]; then
    log "Keeping VM $NAME (multipass delete $NAME && multipass purge)"
  else
    multipass delete "$NAME" && multipass purge
  fi
}

main() {
  parse_args "$@"
  command -v multipass >/dev/null 2>&1 || { err "multipass is not installed"; exit 1; }
  log "Launching $NAME (Ubuntu $RELEASE, 4 CPU, 8G, 40G)"
  multipass launch "$RELEASE" --name "$NAME" --cpus 4 --memory 8G --disk 40G
  trap cleanup EXIT

  log "Copying working tree into the VM"
  vm "rm -rf ~/auto-workspace && mkdir -p ~/auto-workspace"
  (cd "$ROOT" && git ls-files -co --exclude-standard -z | tar --null -cf - -T -) \
    | multipass exec "$NAME" -- tar -xf - -C /home/ubuntu/auto-workspace

  log "Bootstrapping uv and the pinned toolchain"
  vm "curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh >/dev/null"
  vm "cd ~/auto-workspace && ~/.local/bin/uv sync --locked --group dev -q && ~/.local/bin/uv run --locked ansible-galaxy collection install -r requirements.yml >/dev/null"

  local run1="$LOG_DIR/$NAME-run1.log" run2="$LOG_DIR/$NAME-run2.log"
  log "Run 1 (log: $run1)"
  run_playbook "$run1"
  if [[ "$SECOND_RUN" == "true" ]]; then
    log "Run 2 - idempotency (log: $run2)"
    run_playbook "$run2"
    local changed
    changed="$(recap_changed "$run2")"
    if [[ "$changed" != "0" ]]; then
      err "Second run reported changed=$changed; tasks that changed:"
      grep -E '^changed:' -B2 "$run2" | grep -E '^TASK' >&2 || true
      exit 1
    fi
    log "Idempotent: second run changed=0"
  fi
  log "PASS ($NAME, Ubuntu $RELEASE)"
}

if [[ -z "${TIV_SOURCED:-}" ]]; then
  main "$@"
fi
```

Run: `chmod 755 scripts/test-in-vm.sh && bash tests/scripts/test_test_in_vm.sh`
Expected: `all passed`.

- [ ] **Step 3: Remove the old runner and update references**

Run: `git rm -r -q scripts/testing scripts/README.md`

- In `AGENTS.md`, replace `scripts/testing/test-linux-playbook.sh -k -v   # real run inside a Multipass VM` with `scripts/test-in-vm.sh --release 24.04   # real run + idempotency in a Multipass VM`, and replace `scripts/testing/` in the layout block with `scripts/test-in-vm.sh`.
- In `tests/claude/test_config.sh`, replace the needle `"test-linux-playbook.sh"` with `"scripts/test-in-vm.sh"`.
- In `.claude/hooks/block-host-playbook.sh`, replace the message line `scripts/testing/test-linux-playbook.sh -k -v   # real run inside a Multipass VM` with `scripts/test-in-vm.sh --release 24.04   # real run inside a Multipass VM`. In `tests/claude/test_hooks.sh`, replace the needle `"test-linux-playbook.sh"` with `"test-in-vm.sh"`.
- Replace `.claude/skills/test-in-vm/SKILL.md` with:

````markdown
---
name: test-in-vm
description: Run ansible/site.yml for real in a throwaway Multipass VM (Ubuntu 24.04 or 26.04), then an idempotency run, and report failures and non-idempotent tasks.
disable-model-invocation: true
argument-hint: "[--release 24.04|26.04] [--tags <tags>] [--dotfiles-branch <b>] [--keep]"
---

# Test site.yml in a Multipass VM

The only sanctioned way to run the playbook for real.

1. `multipass version` must work and the host needs ~8G free RAM and ~40G disk.
2. Run in the background and wait for it:

   ```bash
   TIV_LOG_DIR="$CLAUDE_JOB_DIR/tmp" scripts/test-in-vm.sh $ARGUMENTS
   ```

3. Report:
   - the `PLAY RECAP` of both runs
   - every `fatal:` task with its message (from `<vm>-run1.log`)
   - any task listed as changed on run 2
   - the VM name, if `--keep` was used
````

- [ ] **Step 4: Tests and lint**

Run: `tests/run.sh && uv run --locked pre-commit run -a`
Expected: all suites `all passed`; all hooks `Passed`.

- [ ] **Step 5: Commit**

```bash
git add -A scripts tests .claude AGENTS.md
git commit -m "test: Add Multipass test-in-vm.sh with idempotency check; drop old runner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `base` role

**Files:**
- Create: `ansible/roles/base/tasks/{main,debian,darwin}.yml`, `ansible/roles/base/meta/main.yml`
- Modify: `ansible/group_vars/ubuntu.yml` (`dpkg_arch`, `ubuntu_release`, `base_packages`), `ansible/site.yml` (add the role to both plays), `tests/ansible/test_site.sh`

**Interfaces:**
- **Produces:** group vars `dpkg_arch` (`amd64` | `arm64`) and `ubuntu_release` (`noble` | `resolute`). Flathub is added as a system remote, and on macOS the play fails early if Homebrew is missing.

- [ ] **Step 1: Append the expectations to `tests/ansible/test_site.sh` (before `finish`) and see them fail**

```bash
# base
expect_task "Upgrade installed packages"
expect_task "Install base packages"
expect_task "Add Flathub remote"
expect_task "Check Homebrew is installed"
expect_task "Require Homebrew"
```

Run: `bash tests/ansible/test_site.sh`
Expected: FAIL on the five `task listed` assertions.

- [ ] **Step 2: Add the Ubuntu data to `ansible/group_vars/ubuntu.yml`**

```yaml
---
dpkg_arch: "{{ {'x86_64': 'amd64', 'aarch64': 'arm64'}[ansible_facts['architecture']] }}"
ubuntu_release: "{{ ansible_facts['distribution_release'] }}"

base_packages:
  - build-essential
  - curl
  - dkms
  - flatpak
  - git
  - htop
  - ifstat
  - "linux-headers-{{ ansible_facts['kernel'] }}"
  - net-tools
  - nmap
  - python3-debian
  - screen
  - snapd
  - tmux
  - unzip
  - vim
  - vnstat
  - wget
```

- [ ] **Step 3: Create the role files**

`ansible/roles/base/meta/main.yml`:

```yaml
---
galaxy_info:
  author: Gajesh Bhat
  description: Base system packages and package managers
  license: MIT
  min_ansible_version: "2.17"
  platforms:
    - name: Ubuntu
      versions: [noble]
    - name: macOS
      versions: [all]
dependencies: []
```

`ansible/roles/base/tasks/main.yml`:

```yaml
---
- name: Ubuntu base
  ansible.builtin.import_tasks: debian.yml
  when: ansible_facts['os_family'] == 'Debian'

- name: macOS base
  ansible.builtin.import_tasks: darwin.yml
  when: ansible_facts['os_family'] == 'Darwin'
```

`ansible/roles/base/tasks/debian.yml`:

```yaml
---
- name: Upgrade installed packages
  become: true
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600
    upgrade: dist

- name: Install base packages
  become: true
  ansible.builtin.apt:
    name: "{{ base_packages }}"
    state: present

- name: Add Flathub remote
  become: true
  community.general.flatpak_remote:
    name: flathub
    flatpakrepo_url: https://dl.flathub.org/repo/flathub.flatpakrepo
    method: system
    state: present
```

`ansible/roles/base/tasks/darwin.yml`:

```yaml
---
- name: Check Homebrew is installed
  ansible.builtin.command: brew --version
  register: base_brew
  changed_when: false
  failed_when: false
  check_mode: false

- name: Require Homebrew
  ansible.builtin.assert:
    that: base_brew.rc == 0
    fail_msg: "Homebrew is missing. Run install.sh (it installs Homebrew) or see https://brew.sh."
    quiet: true
```

- [ ] **Step 4: Wire the role into `site.yml`**

In the Ubuntu play and in the macOS play, replace `roles: []` with:

```yaml
  roles:
    - role: base
      tags: [base]
```

- [ ] **Step 5: Green, lint, commit**

Run: `bash tests/ansible/test_site.sh && uv run --locked pre-commit run -a`
Expected: `all passed`; all hooks `Passed`. If ansible-lint's `meta` rules reject a `platforms` entry, fix the metadata to satisfy the rule and record a ledger ruling.

```bash
git add ansible tests/ansible/test_site.sh
git commit -m "feat: Add base role (upgrade, base packages, Flathub; Homebrew check)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `vendor_repos` role (Ubuntu) + first VM smoke

**Files:**
- Create: `ansible/roles/vendor_repos/{tasks/main.yml,handlers/main.yml,vars/main.yml,meta/main.yml}`
- Modify: `ansible/group_vars/ubuntu.yml` (`vendor_repos`), `ansible/site.yml`, `tests/ansible/test_site.sh`

**Interfaces:**
- **Consumes:** `dpkg_arch`, `ubuntu_release` (Task 3)
- **Produces:**
  - the data schema `vendor_repos: [{name, uri, suite, component, key, architectures, foreign_architectures?, packages}]`
  - the handler `Update apt cache`
  - installed `docker-ce`, `virtualbox-7.2` (amd64), `winehq-stable` (amd64), `code`, `google-chrome-stable` (amd64), `proton-vpn-gnome-desktop` and `gh`

- [ ] **Step 1: Append the expectations (red)**

```bash
# vendor_repos
expect_task "Find legacy apt sources from the previous playbooks"
expect_task "Remove legacy apt sources"
expect_task "Enable foreign architectures needed by vendor repos"
expect_task "Stop Chrome from adding its own apt source"
expect_task "Stop VS Code from adding its own apt source"
expect_task "Add vendor apt repositories"
expect_task "Install vendor packages"
repos="$(cat ansible/group_vars/ubuntu.yml)"
for r in docker virtualbox winehq vscode google-chrome protonvpn github-cli; do
  assert_contains "$repos" "- name: $r" "vendor repo defined: $r"
done
amd64_only="$(.venv/bin/python - <<'EOF'
import yaml
d = yaml.safe_load(open("ansible/group_vars/ubuntu.yml"))
print(",".join(sorted(r["name"] for r in d["vendor_repos"] if r["architectures"] == ["amd64"])))
EOF
)"
assert_eq "google-chrome,virtualbox,winehq" "$amd64_only" "amd64-only vendor repos"
```

Run: `bash tests/ansible/test_site.sh`
Expected: FAIL on the new assertions.

- [ ] **Step 2: Append the repository data to `ansible/group_vars/ubuntu.yml`**

```yaml

# Vendor apt repositories. `key` is fetched by deb822_repository into /etc/apt/keyrings.
# `architectures` lists the host archs the vendor supports; entries not matching dpkg_arch are skipped.
vendor_repos:
  - name: docker
    uri: https://download.docker.com/linux/ubuntu
    suite: "{{ ubuntu_release }}"
    component: stable
    key: https://download.docker.com/linux/ubuntu/gpg
    architectures: [amd64, arm64]
    packages: [docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin]
  - name: virtualbox
    uri: https://download.virtualbox.org/virtualbox/debian
    suite: "{{ ubuntu_release }}"
    component: contrib
    key: https://www.virtualbox.org/download/oracle_vbox_2016.asc
    architectures: [amd64]
    packages: [virtualbox-7.2]
  - name: winehq
    uri: https://dl.winehq.org/wine-builds/ubuntu
    suite: "{{ ubuntu_release }}"
    component: main
    key: https://dl.winehq.org/wine-builds/winehq.key
    architectures: [amd64]
    foreign_architectures: [i386]
    packages: [winehq-stable]
  - name: vscode
    uri: https://packages.microsoft.com/repos/code
    suite: stable
    component: main
    key: https://packages.microsoft.com/keys/microsoft.asc
    architectures: [amd64, arm64]
    packages: [code]
  - name: google-chrome
    uri: https://dl.google.com/linux/chrome/deb
    suite: stable
    component: main
    key: https://dl.google.com/linux/linux_signing_key.pub
    architectures: [amd64]
    packages: [google-chrome-stable]
  - name: protonvpn
    uri: https://repo.protonvpn.com/debian
    suite: stable
    component: main
    key: https://repo.protonvpn.com/debian/public_key.asc
    architectures: [amd64, arm64]
    packages: [proton-vpn-gnome-desktop]
  - name: github-cli
    uri: https://cli.github.com/packages
    suite: stable
    component: main
    key: https://cli.github.com/packages/githubcli-archive-keyring.gpg
    architectures: [amd64, arm64]
    packages: [gh]
```

- [ ] **Step 3: Create the role**

`ansible/roles/vendor_repos/vars/main.yml`:

```yaml
---
vendor_repos_enabled: "{{ vendor_repos | selectattr('architectures', 'contains', dpkg_arch) | list }}"
vendor_repos_foreign_archs: "{{ vendor_repos_enabled | map(attribute='foreign_architectures', default=[]) | flatten | unique }}"
# Source files written by the pre-v2 playbooks (or by vendor postinst scripts). Their Signed-By
# differs from ours, which makes apt fail with "Conflicting values set for option Signed-By".
vendor_repos_legacy_sources:
  - docker.list
  - virtualbox.list
  - winehq-*.sources
  - protonvpn-stable.list
  - mullvad.list
  - google-chrome.list
  - vscode.list
  - github-cli.list
  - wfg-ubuntu-0ad-*
```

`ansible/roles/vendor_repos/handlers/main.yml`:

```yaml
---
- name: Update apt cache
  become: true
  ansible.builtin.apt:
    update_cache: true
```

`ansible/roles/vendor_repos/meta/main.yml`: the same as base's, with `description: Vendor apt repositories and their packages` and only the Ubuntu platform.

`ansible/roles/vendor_repos/tasks/main.yml`:

```yaml
---
- name: Find legacy apt sources from the previous playbooks
  ansible.builtin.find:
    paths: /etc/apt/sources.list.d
    patterns: "{{ vendor_repos_legacy_sources }}"
  register: vendor_repos_legacy

- name: Remove legacy apt sources
  become: true
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: absent
  loop: "{{ vendor_repos_legacy.files }}"
  loop_control:
    label: "{{ item.path }}"
  notify: Update apt cache

- name: List foreign dpkg architectures
  ansible.builtin.command: dpkg --print-foreign-architectures
  register: vendor_repos_foreign
  changed_when: false
  check_mode: false

- name: Enable foreign architectures needed by vendor repos
  become: true
  ansible.builtin.command: dpkg --add-architecture {{ item }}
  loop: "{{ vendor_repos_foreign_archs }}"
  when: item not in vendor_repos_foreign.stdout_lines
  changed_when: true
  notify: Update apt cache

- name: Stop Chrome from adding its own apt source
  become: true
  ansible.builtin.copy:
    dest: /etc/default/google-chrome
    content: |
      repo_add_once="false"
      repo_reenable_on_distupgrade="false"
    owner: root
    group: root
    mode: "0644"

- name: Stop VS Code from adding its own apt source
  become: true
  ansible.builtin.debconf:
    name: code
    question: code/add-microsoft-repo
    value: "false"
    vtype: boolean

- name: Add vendor apt repositories
  become: true
  ansible.builtin.deb822_repository:
    name: "{{ item.name }}"
    uris: "{{ item.uri }}"
    suites: "{{ item.suite }}"
    components: "{{ item.component }}"
    architectures: "{{ [dpkg_arch] + item.foreign_architectures | default([]) }}"
    signed_by: "{{ item.key }}"
  loop: "{{ vendor_repos_enabled }}"
  loop_control:
    label: "{{ item.name }}"
  notify: Update apt cache

- name: Apply pending apt cache update
  ansible.builtin.meta: flush_handlers

- name: Install vendor packages
  become: true
  ansible.builtin.apt:
    name: "{{ vendor_repos_enabled | map(attribute='packages') | flatten }}"
    state: present
```

In `site.yml`, add to the Ubuntu play's roles after `base`:

```yaml
    - role: vendor_repos
      tags: [repos]
```

- [ ] **Step 4: Green and lint**

Run: `bash tests/ansible/test_site.sh && uv run --locked pre-commit run -a`
Expected: `all passed`; all hooks `Passed`.

- [ ] **Step 5: First VM smoke on 26.04 (the newest and riskiest release)**

Run in the background: `TIV_LOG_DIR="$CLAUDE_JOB_DIR/tmp" scripts/test-in-vm.sh --release 26.04 --tags base,repos`
Expected: run 1 recap `failed=0`, run 2 `changed=0`, `PASS`. Any fatal is a real bug; fix it with superpowers:systematic-debugging, and add a `test_site.sh` assertion when the bug is structural.

- [ ] **Step 6: Commit**

```bash
git add ansible tests/ansible/test_site.sh
git commit -m "feat: Add vendor_repos role (deb822 repos, legacy cleanup, gh)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `packages` role

**Files:**
- Create: `ansible/roles/packages/{tasks/main.yml,tasks/debian.yml,tasks/darwin.yml,vars/main.yml,meta/main.yml}`
- Modify: `ansible/group_vars/ubuntu.yml`, `ansible/group_vars/macos.yml`, `ansible/site.yml`, `tests/ansible/test_site.sh`

**Interfaces:**
- **Consumes:** `dpkg_arch`; Flathub remote (Task 3)
- **Produces:** the data lists `apt_packages`, `snap_packages: [{name, classic?}]`, `flatpak_packages`, `deb_packages: [{name, url, architectures}]`, `brew_formulae`, `brew_casks` and `mas_apps: [{id, name}]`

- [ ] **Step 1: Append the expectations (red)**

```bash
# packages
expect_task "Install apt packages"
expect_task "Install snaps"
expect_task "Install Flatpaks"
expect_task "Check which .deb packages are installed"
expect_task "Install .deb packages from vendor URLs"
expect_task "Install Homebrew formulae"
expect_task "Install Homebrew casks"
expect_task "Install Mac App Store apps"
data="$(cat ansible/group_vars/ubuntu.yml ansible/group_vars/macos.yml)"
for p in brasero deluge libreoffice simple-scan vlc lxd multipass powershell proton-pass spotify \
  com.play0ad.zeroad org.gnome.Snapshot org.localsend.localsend_app zoom \
  docker-desktop google-chrome localsend protonvpn utm visual-studio-code 775737590 gh chezmoi uv go; do
  assert_contains "$data" "$p" "package data lists $p"
done
for gone in postman steam telegram mullvad tightvnc microk8s juju maas charmcraft snapcraft transmission pipx astral-uv; do
  assert_eq "" "$(grep -rn "$gone" ansible/ || true)" "dropped: $gone"
done
```

Run: `bash tests/ansible/test_site.sh`
Expected: FAIL on the new task and data assertions. The `dropped:` assertions already pass, because the old tree was deleted in Task 1.

- [ ] **Step 2: Append the data**

`ansible/group_vars/ubuntu.yml`:

```yaml

apt_packages: [brasero, deluge, libreoffice, simple-scan, vlc]

snap_packages:
  - name: lxd
  - name: multipass
  - name: powershell
    classic: true
  - name: proton-pass
  - name: spotify

flatpak_packages:  # Flathub, verified publishers only
  - com.play0ad.zeroad
  - org.gnome.Snapshot
  - org.localsend.localsend_app

deb_packages:  # vendor .deb downloads without an apt repo
  - name: zoom
    url: https://zoom.us/client/latest/zoom_amd64.deb
    architectures: [amd64]
```

`ansible/group_vars/macos.yml`:

```yaml
---
brew_formulae: [chezmoi, gh, git, go, htop, mas, python@3.13, screen, uv, vim]

brew_casks:
  - docker-desktop
  - google-chrome
  - localsend
  - multipass
  - protonvpn
  - spotify
  - utm
  - virtualbox
  - visual-studio-code
  - vlc

mas_apps:  # requires being signed in to the App Store
  - id: 775737590
    name: iA Writer
```

- [ ] **Step 3: Create the role**

`ansible/roles/packages/vars/main.yml`:

```yaml
---
packages_debs: "{{ deb_packages | default([]) | selectattr('architectures', 'contains', dpkg_arch) | list }}"
```

`ansible/roles/packages/tasks/main.yml`: the same two-import pattern as base (`Ubuntu packages` → `debian.yml`, `macOS packages` → `darwin.yml`).

`ansible/roles/packages/tasks/debian.yml`:

```yaml
---
- name: Install apt packages
  become: true
  ansible.builtin.apt:
    name: "{{ apt_packages }}"
    state: present

- name: Install snaps
  become: true
  community.general.snap:
    name: "{{ item.name }}"
    classic: "{{ item.classic | default(false) }}"
    state: present
  loop: "{{ snap_packages }}"
  loop_control:
    label: "{{ item.name }}"

- name: Install Flatpaks
  become: true
  community.general.flatpak:
    name: "{{ flatpak_packages }}"
    remote: flathub
    method: system
    state: present

- name: Check which .deb packages are installed
  ansible.builtin.command: dpkg-query -W -f=${Status} {{ item.name }}
  loop: "{{ packages_debs }}"
  loop_control:
    label: "{{ item.name }}"
  register: packages_deb_status
  changed_when: false
  failed_when: false
  check_mode: false

- name: Install .deb packages from vendor URLs
  become: true
  ansible.builtin.apt:
    deb: "{{ item.item.url }}"
  loop: "{{ packages_deb_status.results }}"
  loop_control:
    label: "{{ item.item.name }}"
  when: "'install ok installed' not in item.stdout"
```

`ansible/roles/packages/tasks/darwin.yml`:

```yaml
---
- name: Install Homebrew formulae
  community.general.homebrew:
    name: "{{ brew_formulae }}"
    state: present

- name: Install Homebrew casks
  community.general.homebrew_cask:
    name: "{{ brew_casks }}"
    state: present
    accept_external_apps: true

- name: Install Mac App Store apps
  community.general.mas:
    id: "{{ mas_apps | map(attribute='id') | list }}"
    state: present
```

`meta/main.yml`: as base's, with `description: Apps from apt, snap, Flathub, vendor .debs, Homebrew and the Mac App Store`.

In `site.yml`, add to the Ubuntu play after `vendor_repos`, and to the macOS play after `base`:

```yaml
    - role: packages
      tags: [packages]
```

- [ ] **Step 4: Green, lint, commit**

Run: `bash tests/ansible/test_site.sh && uv run --locked pre-commit run -a`
Expected: `all passed`; all hooks `Passed`.

```bash
git add ansible tests/ansible/test_site.sh
git commit -m "feat: Add packages role with data-driven app lists for Ubuntu and macOS

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `docker` and `virtualization` roles (Ubuntu)

**Files:**
- Create: `ansible/roles/docker/{tasks/main.yml,meta/main.yml}`, `ansible/roles/virtualization/{tasks/main.yml,tasks/virtualbox.yml,vars/main.yml,meta/main.yml}`
- Modify: `ansible/site.yml`, `tests/ansible/test_site.sh`

**Interfaces:**
- **Consumes:** Docker and VirtualBox packages (Task 4), the `lxd` snap (Task 5), `workstation_user`, `dpkg_arch`
- **Produces:** the user is in `docker`, `libvirt`, `kvm` and `lxd` (plus `vboxusers` on amd64); LXD is initialized; the matching Extension Pack is installed

- [ ] **Step 1: Append the expectations (red)**

```bash
# docker + virtualization
expect_task "Enable and start Docker"
expect_task "Add user to the docker group"
expect_task "Install KVM and libvirt"
expect_task "Enable and start libvirtd"
expect_task "Add user to virtualization groups"
expect_task "Check for LXD storage pools"
expect_task "Initialize LXD"
expect_task "Read VirtualBox version"
expect_task "Install the matching VirtualBox Extension Pack"
```

Run: `bash tests/ansible/test_site.sh`
Expected: FAIL on these nine.

- [ ] **Step 2: Create `docker`**

`ansible/roles/docker/tasks/main.yml`:

```yaml
---
- name: Enable and start Docker
  become: true
  ansible.builtin.systemd_service:
    name: docker
    enabled: true
    state: started

- name: Add user to the docker group
  become: true
  ansible.builtin.user:
    name: "{{ workstation_user }}"
    groups: docker
    append: true
```

`meta/main.yml`: as base's, with `description: Docker Engine service and group` and Ubuntu only.

- [ ] **Step 3: Create `virtualization`**

`ansible/roles/virtualization/vars/main.yml`:

```yaml
---
virtualization_qemu_package: "{{ 'qemu-system-arm' if dpkg_arch == 'arm64' else 'qemu-system-x86' }}"
virtualization_groups: "{{ ['libvirt', 'kvm', 'lxd'] + (['vboxusers'] if dpkg_arch == 'amd64' else []) }}"
virtualization_extpack_path: "{{ installer_cache }}/Oracle_VirtualBox_Extension_Pack.vbox-extpack"
```

`ansible/roles/virtualization/tasks/main.yml`:

```yaml
---
- name: Install KVM and libvirt
  become: true
  ansible.builtin.apt:
    name:
      - "{{ virtualization_qemu_package }}"
      - qemu-utils
      - libvirt-daemon-system
      - libvirt-clients
      - virtinst
      - virt-manager
      - bridge-utils
    state: present

- name: Enable and start libvirtd
  become: true
  ansible.builtin.systemd_service:
    name: libvirtd
    enabled: true
    state: started

- name: Add user to virtualization groups
  become: true
  ansible.builtin.user:
    name: "{{ workstation_user }}"
    groups: "{{ virtualization_groups }}"
    append: true

- name: Check for LXD storage pools
  become: true
  ansible.builtin.command: lxc storage list --format csv
  register: virtualization_lxd_pools
  changed_when: false
  check_mode: false

- name: Initialize LXD
  become: true
  ansible.builtin.command: lxd init --auto
  when: virtualization_lxd_pools.stdout | length == 0
  changed_when: true

- name: VirtualBox Extension Pack
  ansible.builtin.import_tasks: virtualbox.yml
  when: dpkg_arch == 'amd64'
```

`ansible/roles/virtualization/tasks/virtualbox.yml`:

```yaml
---
- name: Read VirtualBox version
  ansible.builtin.command: VBoxManage --version
  register: virtualization_vbox_version_raw
  changed_when: false
  check_mode: false

- name: List installed extension packs
  ansible.builtin.command: VBoxManage list extpacks
  register: virtualization_vbox_extpacks
  changed_when: false
  check_mode: false

- name: Install the matching VirtualBox Extension Pack
  vars:
    virtualization_vbox_version: "{{ virtualization_vbox_version_raw.stdout | regex_replace('r\\d+$', '') }}"
  when: virtualization_vbox_version not in virtualization_vbox_extpacks.stdout
  block:
    - name: Create installer cache directory
      ansible.builtin.file:
        path: "{{ installer_cache }}"
        state: directory
        mode: "0755"

    - name: Download Extension Pack {{ virtualization_vbox_version }}
      ansible.builtin.get_url:
        url: "https://download.virtualbox.org/virtualbox/{{ virtualization_vbox_version }}/Oracle_VirtualBox_Extension_Pack-{{ virtualization_vbox_version }}.vbox-extpack"
        dest: "{{ virtualization_extpack_path }}"
        mode: "0644"
        force: true

    - name: Compute Extension Pack license hash
      ansible.builtin.shell: >-
        set -o pipefail &&
        tar -xzOf {{ virtualization_extpack_path | quote }} --wildcards '*ExtPack-license.txt' | sha256sum | cut -d' ' -f1
      args:
        executable: /bin/bash
      register: virtualization_extpack_license
      changed_when: false

    - name: Install Extension Pack
      become: true
      ansible.builtin.command: >-
        VBoxManage extpack install --replace
        --accept-license={{ virtualization_extpack_license.stdout }}
        {{ virtualization_extpack_path | quote }}
      changed_when: true
```

`meta/main.yml` for both roles, as base's (Ubuntu only).

In `site.yml`, add to the Ubuntu play after `packages`:

```yaml
    - role: docker
      tags: [docker]
    - role: virtualization
      tags: [virtualization]
```

- [ ] **Step 4: Green, lint, commit**

Run: `bash tests/ansible/test_site.sh && uv run --locked pre-commit run -a`
Expected: `all passed`; all hooks `Passed`.

```bash
git add ansible tests/ansible/test_site.sh
git commit -m "feat: Add docker and virtualization roles (KVM, LXD, VirtualBox 7.2 extpack)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `languages` role

**Files:**
- Create: `ansible/roles/languages/{tasks/main.yml,tasks/debian.yml,tasks/darwin.yml,tasks/common.yml,meta/main.yml}`
- Modify: `ansible/site.yml` (both plays), `tests/ansible/test_site.sh`

**Interfaces:**
- **Consumes:** `installer_cache`, `local_bin`, `go_version`, `fvm_version`, `flutter_channel`, `dpkg_arch`; brew `go`/`uv` (Task 5, macOS)
- **Produces:**
  - `~/.cargo/bin/rustup` (stable)
  - `/usr/local/go` at `go_version` (Ubuntu)
  - `~/.local/bin/uv` (Ubuntu)
  - `~/fvm/bin/fvm`, `~/fvm/versions/stable`, `~/fvm/default`
  - `~/.local/bin/dotrun`

- [ ] **Step 1: Append the expectations (red)**

```bash
# languages
expect_task "Install Flutter desktop build dependencies"
expect_task "Read installed Go version"
expect_task "Install Go"
expect_task "Install uv"
expect_task "Tap fvm"
expect_task "Install Rust (stable) with rustup"
expect_task "Install fvm"
expect_task "Install Flutter with fvm"
expect_task "Set global Flutter version"
expect_task "Install dotrun"
```

Run: `bash tests/ansible/test_site.sh`
Expected: FAIL on these.

- [ ] **Step 2: Create the role**

`ansible/roles/languages/tasks/main.yml`:

```yaml
---
- name: Create installer cache directory
  ansible.builtin.file:
    path: "{{ installer_cache }}"
    state: directory
    mode: "0755"

- name: Ubuntu language toolchains
  ansible.builtin.import_tasks: debian.yml
  when: ansible_facts['os_family'] == 'Debian'

- name: macOS language toolchains
  ansible.builtin.import_tasks: darwin.yml
  when: ansible_facts['os_family'] == 'Darwin'

- name: Cross-platform language toolchains
  ansible.builtin.import_tasks: common.yml
```

`ansible/roles/languages/tasks/debian.yml`:

```yaml
---
- name: Install Flutter desktop build dependencies
  become: true
  ansible.builtin.apt:
    name: [clang, cmake, ninja-build, pkg-config, libgtk-3-dev]
    state: present

- name: Read installed Go version
  ansible.builtin.command: /usr/local/go/bin/go env GOVERSION
  register: languages_go_installed
  changed_when: false
  failed_when: false
  check_mode: false

- name: Install Go
  when: languages_go_installed.stdout != 'go' ~ go_version
  block:
    - name: Remove previous Go installation
      become: true
      ansible.builtin.file:
        path: /usr/local/go
        state: absent

    - name: Unpack Go {{ go_version }}
      become: true
      ansible.builtin.unarchive:
        src: "https://go.dev/dl/go{{ go_version }}.linux-{{ dpkg_arch }}.tar.gz"
        dest: /usr/local
        remote_src: true

- name: Download uv installer
  ansible.builtin.get_url:
    url: https://astral.sh/uv/install.sh
    dest: "{{ installer_cache }}/uv-install.sh"
    mode: "0755"

- name: Install uv
  ansible.builtin.command: sh {{ installer_cache }}/uv-install.sh
  environment:
    UV_NO_MODIFY_PATH: "1"
  args:
    creates: "{{ local_bin }}/uv"

- name: Download fvm installer
  ansible.builtin.get_url:
    url: https://fvm.app/install.sh
    dest: "{{ installer_cache }}/fvm-install.sh"
    mode: "0755"

- name: Install fvm
  ansible.builtin.command: bash {{ installer_cache }}/fvm-install.sh {{ fvm_version }}
  args:
    creates: "{{ workstation_home }}/fvm/bin/fvm"
```

`ansible/roles/languages/tasks/darwin.yml`:

```yaml
---
- name: Tap fvm
  community.general.homebrew_tap:
    name: leoafarias/fvm
    state: present

- name: Install fvm
  community.general.homebrew:
    name: leoafarias/fvm/fvm
    state: present
```

`ansible/roles/languages/tasks/common.yml`:

```yaml
---
- name: Download rustup installer
  ansible.builtin.get_url:
    url: https://sh.rustup.rs
    dest: "{{ installer_cache }}/rustup-init.sh"
    mode: "0755"

- name: Install Rust (stable) with rustup
  ansible.builtin.command: sh {{ installer_cache }}/rustup-init.sh -y --no-modify-path --default-toolchain stable
  args:
    creates: "{{ workstation_home }}/.cargo/bin/rustup"

- name: Install Flutter with fvm
  ansible.builtin.command: fvm install {{ flutter_channel }} --fvm-skip-input
  args:
    creates: "{{ workstation_home }}/fvm/versions/{{ flutter_channel }}"

- name: Set global Flutter version
  ansible.builtin.command: fvm global {{ flutter_channel }} --fvm-skip-input
  args:
    creates: "{{ workstation_home }}/fvm/default"

- name: Install dotrun
  ansible.builtin.command: uv tool install dotrun
  args:
    creates: "{{ local_bin }}/dotrun"
```

`meta/main.yml`: as base's, with `description: Rust, Go, uv, Flutter (fvm) and dotrun`.

In `site.yml`, add to the Ubuntu play after `virtualization`, and to the macOS play after `packages`:

```yaml
    - role: languages
      tags: [languages]
```

- [ ] **Step 3: Green, lint, commit**

Run: `bash tests/ansible/test_site.sh && uv run --locked pre-commit run -a`
Expected: `all passed`; all hooks `Passed`.

```bash
git add ansible tests/ansible/test_site.sh
git commit -m "feat: Add languages role (rustup, Go, uv, fvm/Flutter, dotrun)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Convert `gajeshbhat/dotfiles` to chezmoi (separate repo, draft PR)

**Files (in a clone at `$CLAUDE_JOB_DIR/tmp/dotfiles`, branch `feature/chezmoi`):**
- Rename (`git mv`): `.bashrc` → `dot_bashrc`, `.zshrc` → `dot_zshrc`, `.vimrc` → `dot_vimrc`, `.vimrc.plug` → `dot_vimrc.plug`, `.screenrc` → `dot_screenrc`
- Create:
  - `.chezmoi.toml.tmpl`, `.chezmoiignore`, `dot_gitconfig.tmpl`
  - `dot_claude/settings.json`
  - `dot_local/bin/executable_dotfiles-backup`
  - `.chezmoiscripts/run_onchange_after_10-vim-plug.sh.tmpl`, `.chezmoiscripts/run_onchange_after_20-claude-plugins.sh.tmpl`
- Modify: `README.md` (short)

**Interfaces:**
- **Produces:**
  - chezmoi prompts `Git name` and `Git email`. The Ansible role passes them as `--promptString "Git name=…"` and `--promptString "Git email=…"`.
  - the target `~/.local/bin/dotfiles-backup`
  - `~/.claude/settings.json` from `dot_claude/settings.json`

- [ ] **Step 1: Clone and branch**

Run:
```bash
gh repo clone gajeshbhat/dotfiles "$CLAUDE_JOB_DIR/tmp/dotfiles" && git -C "$CLAUDE_JOB_DIR/tmp/dotfiles" switch -c feature/chezmoi
```

- [ ] **Step 2: Rename to chezmoi source names and build `dot_bashrc`**

Run the five `git mv` renames. Then write `dot_bashrc` as:
1. the exact content of `/etc/skel/.bashrc` from this Ubuntu machine
2. a line `# --- dotfiles additions ---`
3. the previous 7 lines of `.bashrc`
4. this PATH block:

```bash
# --- PATH (tools installed by auto-workspace) ---
for d in "$HOME/.local/bin" "$HOME/fvm/bin" "$HOME/fvm/default/bin" "/usr/local/go/bin" "$HOME/go/bin"; do
  [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export PATH
```

Append the same PATH block to `dot_zshrc`, preceded by:

```bash
# --- Homebrew ---
if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
```

- [ ] **Step 3: chezmoi config, ignore rules and gitconfig**

`.chezmoi.toml.tmpl`:

```
{{- $name := promptStringOnce . "name" "Git name" -}}
{{- $email := promptStringOnce . "email" "Git email" -}}
[data]
  name = {{ $name | quote }}
  email = {{ $email | quote }}
```

`.chezmoiignore`:

```
README.md
{{ if ne .chezmoi.os "linux" }}
.bashrc
{{ end }}
{{ if ne .chezmoi.os "darwin" }}
.zshrc
{{ end }}
```

`dot_gitconfig.tmpl`:

```
[user]
	name = {{ .name }}
	email = {{ .email }}
[init]
	defaultBranch = main
[pull]
	ff = only
```

- [ ] **Step 4: Claude settings (portable subset only)**

Create `dot_claude/settings.json` from `~/.claude/settings.json`, keeping **only** these keys if present: `permissions`, `enabledPlugins`, `extraKnownMarketplaces`, `skillOverrides`, `hooks`, `theme`, `editorMode`, `timeFormat`, `worktree`, `enableWorkflows`, `feedbackDrafts`. Use:

```bash
python3 - "$HOME/.claude/settings.json" > "$CLAUDE_JOB_DIR/tmp/dotfiles/dot_claude/settings.json" <<'EOF'
import json, sys
keep = ["permissions", "enabledPlugins", "extraKnownMarketplaces", "skillOverrides", "hooks", "theme",
        "editorMode", "timeFormat", "worktree", "enableWorkflows", "feedbackDrafts"]
src = json.load(open(sys.argv[1]))
print(json.dumps({k: src[k] for k in keep if k in src}, indent=2))
EOF
```

If `~/.claude/CLAUDE.md`, `~/.claude/agents/` or user-authored skills outside `~/.claude/skills/synced/` exist, copy them under `dot_claude/`. Otherwise add nothing. Verify with `git -C … ls-files | grep -Ei 'credential|history|session|synced'`, which must print nothing.

- [ ] **Step 5: Backup command and run-once scripts**

`dot_local/bin/executable_dotfiles-backup`:

```bash
#!/usr/bin/env bash
# Back up local dotfile edits (incl. ~/.claude/settings.json) to the dotfiles repo.
set -euo pipefail
chezmoi re-add
if chezmoi git -- diff --quiet && chezmoi git -- diff --cached --quiet; then
  echo "[+] Nothing to back up."
  exit 0
fi
chezmoi git -- add -A
chezmoi git -- commit -m "backup: $(hostname) $(date +%Y-%m-%d)"
chezmoi git -- push
echo "[+] Dotfiles backed up."
```

`.chezmoiscripts/run_onchange_after_10-vim-plug.sh.tmpl`:

```bash
#!/usr/bin/env bash
# vimrc.plug hash: {{ include "dot_vimrc.plug" | sha256sum }}
set -euo pipefail
plug="$HOME/.vim/autoload/plug.vim"
[ -f "$plug" ] || curl -fsSLo "$plug" --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
vim -Es -u "$HOME/.vimrc" +PlugInstall +qall || true
```

`.chezmoiscripts/run_onchange_after_20-claude-plugins.sh.tmpl`:

```bash
#!/usr/bin/env bash
# enabledPlugins hash: {{ include "dot_claude/settings.json" | sha256sum }}
set -uo pipefail
command -v claude >/dev/null 2>&1 || { echo "[!] claude not installed; skipping plugin install"; exit 0; }
plugins="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("\n".join(k for k,v in d.get("enabledPlugins",{}).items() if v))' "$HOME/.claude/settings.json")"
for p in $plugins; do
  claude plugin install "$p" >/dev/null 2>&1 && echo "[+] plugin $p" || echo "[!] could not install plugin $p"
done
```

- [ ] **Step 6: README (short) and a local dry run**

Replace `README.md` with at most 15 lines: what it is, `chezmoi init --apply gajeshbhat/dotfiles`, `dotfiles-backup`, and what's tracked or never tracked.

Dry run against a throwaway HOME:
```bash
H="$CLAUDE_JOB_DIR/tmp/chezmoi-home"; rm -rf "$H"; mkdir -p "$H"
HOME="$H" chezmoi init --source "$CLAUDE_JOB_DIR/tmp/dotfiles" --promptString "Git name=Test" --promptString "Git email=t@example.com" --apply --dry-run --verbose 2>&1 | tail -30
```
Expected: it lists `.bashrc`, `.vimrc`, `.vimrc.plug`, `.screenrc`, `.gitconfig`, `.claude/settings.json` and `.local/bin/dotfiles-backup`; `.zshrc` and `README.md` are not listed; no errors. If `chezmoi` isn't on the host, run this step inside the Task 10 VM instead and record a ledger ruling.

- [ ] **Step 7: Commit, push the branch, open a draft PR**

```bash
git -C "$CLAUDE_JOB_DIR/tmp/dotfiles" add -A
git -C "$CLAUDE_JOB_DIR/tmp/dotfiles" commit -m "feat: Convert to chezmoi; add Claude settings, plugins sync and dotfiles-backup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C "$CLAUDE_JOB_DIR/tmp/dotfiles" push -u origin feature/chezmoi
gh pr create --repo gajeshbhat/dotfiles --draft --base master --head feature/chezmoi \
  --title "Convert to chezmoi (Claude settings, plugins, dotfiles-backup)" \
  --body "Converts the repo to a chezmoi source used by auto-workspace's dotfiles role. Tracks shell/vim/screen configs, a portable subset of ~/.claude/settings.json, and installs enabled Claude plugins on apply. Never tracks credentials, history or caches. Backup: \`dotfiles-backup\`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

Record the PR URL in the ledger.

---

### Task 9: `claude_code` and `dotfiles` roles

**Files:**
- Create: `ansible/roles/claude_code/{tasks/main.yml,meta/main.yml}`, `ansible/roles/dotfiles/{tasks/main.yml,vars/main.yml,meta/main.yml}`
- Modify: `ansible/site.yml` (both plays), `tests/ansible/test_site.sh`

**Interfaces:**
- **Consumes:** `installer_cache`, `local_bin`, `workstation_home`, `git_user_name`, `git_user_email`, `dotfiles_repo`, `dotfiles_branch`; the chezmoi prompts `Git name`/`Git email` (Task 8)
- **Produces:** `~/.local/bin/claude`, `~/.local/bin/chezmoi` (Ubuntu), `~/.local/share/chezmoi`, and a one-time `~/.bashrc.pre-chezmoi` or `~/.zshrc.pre-chezmoi`

- [ ] **Step 1: Append the expectations (red)**

```bash
# claude_code + dotfiles
expect_task "Install Claude Code"
expect_task "Install chezmoi"
expect_task "Check for an existing chezmoi source"
expect_task "Back up the shell rc file before chezmoi takes it over"
expect_task "Initialize dotfiles with chezmoi"
expect_task "Pull dotfiles updates"
expect_task "Read chezmoi status"
expect_task "Warn about local dotfile edits"
expect_task "Apply dotfiles"
l_claude="$(printf '%s\n' "$TASKS" | grep -n 'Install Claude Code' | head -1 | cut -d: -f1)"
l_init="$(printf '%s\n' "$TASKS" | grep -n 'Initialize dotfiles with chezmoi' | head -1 | cut -d: -f1)"
assert_eq "true" "$([[ ${l_claude:-0} -gt 0 && ${l_claude:-0} -lt ${l_init:-0} ]] && echo true || echo false)" \
  "Claude Code install precedes chezmoi init"
```

Run: `bash tests/ansible/test_site.sh`
Expected: FAIL on these.

- [ ] **Step 2: Create `claude_code`**

`ansible/roles/claude_code/tasks/main.yml`:

```yaml
---
- name: Create installer cache directory
  ansible.builtin.file:
    path: "{{ installer_cache }}"
    state: directory
    mode: "0755"

- name: Download Claude Code installer
  ansible.builtin.get_url:
    url: https://claude.ai/install.sh
    dest: "{{ installer_cache }}/claude-install.sh"
    mode: "0755"

- name: Install Claude Code
  ansible.builtin.command: bash {{ installer_cache }}/claude-install.sh
  args:
    creates: "{{ local_bin }}/claude"
```

- [ ] **Step 3: Create `dotfiles`**

`ansible/roles/dotfiles/vars/main.yml`:

```yaml
---
dotfiles_source_dir: "{{ workstation_home }}/.local/share/chezmoi"
dotfiles_shell_rc: "{{ '.zshrc' if ansible_facts['os_family'] == 'Darwin' else '.bashrc' }}"
# chezmoi status: column 1 != ' ' means the file changed locally since chezmoi last wrote it.
dotfiles_local_edits: "{{ dotfiles_status.stdout_lines | default([]) | select('match', '^[^ ]') | list }}"
dotfiles_pending: "{{ dotfiles_status.stdout_lines | default([]) | length > 0 }}"
```

`ansible/roles/dotfiles/tasks/main.yml`:

```yaml
---
- name: Create installer cache directory
  ansible.builtin.file:
    path: "{{ installer_cache }}"
    state: directory
    mode: "0755"

- name: Download chezmoi installer
  when: ansible_facts['os_family'] == 'Debian'
  ansible.builtin.get_url:
    url: https://get.chezmoi.io
    dest: "{{ installer_cache }}/chezmoi-install.sh"
    mode: "0755"

- name: Install chezmoi
  when: ansible_facts['os_family'] == 'Debian'
  ansible.builtin.command: sh {{ installer_cache }}/chezmoi-install.sh -b {{ local_bin }}
  args:
    creates: "{{ local_bin }}/chezmoi"

- name: Check for an existing chezmoi source
  ansible.builtin.stat:
    path: "{{ dotfiles_source_dir }}/.git"
  register: dotfiles_source

- name: Check for an existing shell rc file
  ansible.builtin.stat:
    path: "{{ workstation_home }}/{{ dotfiles_shell_rc }}"
  register: dotfiles_rc

- name: Back up the shell rc file before chezmoi takes it over
  ansible.builtin.copy:
    src: "{{ workstation_home }}/{{ dotfiles_shell_rc }}"
    dest: "{{ workstation_home }}/{{ dotfiles_shell_rc }}.pre-chezmoi"
    remote_src: true
    force: false
    mode: "0644"
  when: not dotfiles_source.stat.exists and dotfiles_rc.stat.exists

- name: Initialize dotfiles with chezmoi
  ansible.builtin.command:
    argv:
      - chezmoi
      - init
      - --apply
      - --force
      - --branch
      - "{{ dotfiles_branch }}"
      - --promptString
      - "Git name={{ git_user_name }}"
      - --promptString
      - "Git email={{ git_user_email }}"
      - "{{ dotfiles_repo }}"
  when: not dotfiles_source.stat.exists
  changed_when: true

- name: Update existing dotfiles
  when: dotfiles_source.stat.exists
  block:
    - name: Pull dotfiles updates
      ansible.builtin.command: chezmoi git -- pull --ff-only
      register: dotfiles_pull
      changed_when: "'Already up to date' not in dotfiles_pull.stdout"

    - name: Read chezmoi status
      ansible.builtin.command: chezmoi status
      register: dotfiles_status
      changed_when: false
      check_mode: false

    - name: Warn about local dotfile edits
      ansible.builtin.debug:
        msg: >-
          Not applying dotfiles: edited locally since the last apply: {{ dotfiles_local_edits | join(', ') }}.
          Run `dotfiles-backup` to keep them (or `chezmoi apply --force` to discard), then re-run.
      when: dotfiles_local_edits | length > 0

    - name: Apply dotfiles
      ansible.builtin.command: chezmoi apply --no-tty
      when: dotfiles_pending and dotfiles_local_edits | length == 0
      changed_when: true
```

`meta/main.yml` for both roles, as base's.

In `site.yml`, add to both plays after `languages`:

```yaml
    - role: claude_code
      tags: [claude]
    - role: dotfiles
      tags: [dotfiles]
```

- [ ] **Step 4: Green, lint, commit**

Run: `bash tests/ansible/test_site.sh && uv run --locked pre-commit run -a`
Expected: `all passed`; all hooks `Passed`.

```bash
git add ansible tests/ansible/test_site.sh
git commit -m "feat: Add claude_code and chezmoi-based dotfiles roles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Full VM verification on 24.04 and 26.04

**Files:** fixes only, wherever the runs expose bugs. Each fix gets a `test_site.sh` assertion when it's structural.

- [ ] **Step 1: Push so the VM's clone of dotfiles resolves** — `git push origin feature/workspace-updates`

- [ ] **Step 2: Ubuntu 26.04, full run + idempotency**

Run in the background: `TIV_LOG_DIR="$CLAUDE_JOB_DIR/tmp" scripts/test-in-vm.sh --release 26.04 --dotfiles-branch feature/chezmoi --keep`
Expected: run 1 `failed=0`; run 2 `changed=0`; `PASS`. Keep the VM for steps 4–5.

- [ ] **Step 3: Ubuntu 24.04, full run + idempotency**

Run in the background: `TIV_LOG_DIR="$CLAUDE_JOB_DIR/tmp" scripts/test-in-vm.sh --release 24.04 --dotfiles-branch feature/chezmoi`
Expected: `PASS`.

- [ ] **Step 4: Legacy-source upgrade (Review Focus 1)** — in the kept 26.04 VM `aw-test-2604`:

```bash
multipass exec aw-test-2604 -- sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu resolute stable" > /etc/apt/sources.list.d/docker.list'
multipass exec aw-test-2604 -- bash -lc 'cd ~/auto-workspace && ~/.local/bin/uv run --locked ansible-playbook ansible/site.yml --tags repos -e dotfiles_branch=feature/chezmoi'
multipass exec aw-test-2604 -- test ! -e /etc/apt/sources.list.d/docker.list
```
Expected: the run has `failed=0`, and the last command exits 0 (the legacy file was removed).

- [ ] **Step 5: Local dotfile edit is preserved (Review Focus 2)**

```bash
multipass exec aw-test-2604 -- bash -lc 'python3 - <<EOF
import json,os; p=os.path.expanduser("~/.claude/settings.json"); d=json.load(open(p)); d["theme"]="light"; json.dump(d,open(p,"w"))
EOF'
multipass exec aw-test-2604 -- bash -lc 'cd ~/auto-workspace && ~/.local/bin/uv run --locked ansible-playbook ansible/site.yml --tags dotfiles -e dotfiles_branch=feature/chezmoi' | tee "$CLAUDE_JOB_DIR/tmp/dotfiles-edit.log"
multipass exec aw-test-2604 -- bash -lc 'grep -c "\"theme\": \"light\"\|\"theme\":\"light\"" ~/.claude/settings.json'
```
Expected: the log contains `Not applying dotfiles`, and the grep prints `1`.

- [ ] **Step 6: Tear down** — `multipass delete aw-test-2604 && multipass purge`

- [ ] **Step 7: Commit any fixes** (`fix: …`) and push.

---

### Task 11: Docs, agent guidance and skills for the new layout

**Files:**
- Modify: `README.md`, `docs/development.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/skills/add-app/SKILL.md`, `.claude/agents/ansible-reviewer.md`, `tests/claude/test_config.sh`

- [ ] **Step 1: Add the failing doc checks to `tests/claude/test_config.sh` (before `finish`)**

```bash
assert_eq "true" "$( (( $(wc -l < "$ROOT/README.md") <= 45 )) && echo true || echo false)" "README is short (<=45 lines)"
readme="$(cat "$ROOT/README.md")"
for needle in "install.sh" "24.04" "26.04" "macOS" "group_vars" "Secure Boot" "docs/development.md"; do
  assert_contains "$readme" "$needle" "README mentions $needle"
done
assert_eq "true" "$( (( $(wc -l < "$ROOT/docs/development.md") <= 60 )) && echo true || echo false)" "dev guide fits one screen (<=60 lines)"
assert_contains "$(cat "$ROOT/.claude/skills/add-app/SKILL.md")" "group_vars" "add-app skill edits group_vars"
assert_eq "" "$(grep -rnE 'linux\.yml|macos\.yml|playbooks/linux|install-gui-apps|test-linux-playbook' "$ROOT"/README.md "$ROOT"/docs/development.md "$ROOT"/AGENTS.md "$ROOT"/CLAUDE.md "$ROOT"/.claude || true)" "no stale paths in docs"
```

Run: `bash tests/claude/test_config.sh`
Expected: FAIL (the README is long, and there are stale paths in `AGENTS.md` and the skills).

- [ ] **Step 2: Rewrite `README.md` (≤ 45 lines)**

````markdown
# auto-workspace

Ansible that sets up my workstation: **Ubuntu 24.04 / 26.04 LTS** and **macOS 15 / 26**.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/gajeshbhat/auto-workspace/master/install.sh | bash
```

Dry run: `… | bash -s -- --check`. Re-run any time; it only changes what's missing.
Run one part: `uv run ansible-playbook ansible/site.yml --tags languages` (tags: base, repos, packages, docker, virtualization, languages, claude, dotfiles).

## What you get

- **Dev:** git, gh, vim, tmux, screen, build tools, Rust (rustup), Go, uv, Flutter (fvm), dotrun, Claude Code
- **Containers & VMs:** Docker, KVM/libvirt, LXD, VirtualBox 7.2, Multipass (UTM on macOS)
- **Apps:** Chrome, VS Code, Spotify, VLC, LibreOffice, Proton VPN, Proton Pass, Zoom, LocalSend, Wine, 0 A.D., …
- **Dotfiles:** [chezmoi](https://chezmoi.io) from `gajeshbhat/dotfiles`, incl. Claude Code settings and plugins. Back up local edits with `dotfiles-backup`.

## Customize

Edit the lists in `ansible/group_vars/`: `ubuntu.yml` (apt, vendor repos, snaps, Flatpaks), `macos.yml` (Homebrew, App Store), `all.yml` (git identity, versions, dotfiles repo).

## Notes

- Log out and back in after the first run (new groups: docker, libvirt, kvm, lxd, vboxusers).
- Secure Boot: VirtualBox kernel modules need a one-time MOK enrollment prompt on reboot.
- macOS: sign in to the App Store first (for iA Writer).

Developing on this repo: [docs/development.md](docs/development.md).
````

- [ ] **Step 3: Rewrite `docs/development.md` (≤ 60 lines)**

````markdown
# Development

```bash
./scripts/setup-dev.sh         # uv toolchain, collections, git hooks (no sudo)
uv run pre-commit run -a       # yamllint, ansible-lint (production), shellcheck, shell tests
tests/run.sh                   # shell + playbook structure tests
scripts/test-in-vm.sh --release 26.04   # real run + idempotency check in a Multipass VM
```

Never run `ansible/site.yml` or `install.sh` for real on your own machine while developing; use the VM script.

## Layout

- `ansible/site.yml` – checks the platform, then runs the Ubuntu or macOS play
- `ansible/group_vars/` – all app lists and versions (data)
- `ansible/roles/` – base, vendor_repos, packages, docker, virtualization, languages, claude_code, dotfiles

## Add an app

Add one line to the matching list in `ansible/group_vars/ubuntu.yml` or `macos.yml` (a new vendor apt repo is one `vendor_repos` entry). With Claude Code: `/add-app <name>`. Then lint and run the VM test.

## Dotfiles

Managed by chezmoi from `gajeshbhat/dotfiles`. `dotfiles-backup` pushes local edits (including `~/.claude/settings.json`). The playbook never overwrites locally edited dotfiles; it warns instead.

## Tool versions

Pinned in `pyproject.toml`/`uv.lock` and `requirements.yml`; bump with `uv add --dev <tool>==<ver>` and commit the lock.
````

- [ ] **Step 4: Update `AGENTS.md`, `CLAUDE.md`, the skill and the agent**

- `AGENTS.md`:
  - Replace the **Layout** block with the new tree: `ansible.cfg`, `ansible/site.yml`, `ansible/inventory/`, `ansible/group_vars/`, `ansible/roles/<eight roles>`, `install.sh`, `scripts/setup-dev.sh`, `scripts/test-in-vm.sh`, `scripts/vm-setup/`, `tests/`, `docs/`, `.claude/`.
  - Replace the syntax-check commands with `uv run ansible-playbook ansible/site.yml --syntax-check`.
  - Safety rule 1 names `ansible/site.yml` and `install.sh`.
  - Rewrite **Conventions** as:
    - apps are data in `group_vars`
    - vendor repos use `deb822_repository` with `signed_by: <key URL>`
    - role-prefixed registered vars
    - FQCN
    - `become` per task
    - second run must be `changed=0`
- `CLAUDE.md`: in **Project automation**, change the `/test-in-vm` description to "runs `scripts/test-in-vm.sh` (real run + idempotency)".
- `.claude/skills/add-app/SKILL.md`: rewrite steps 2–3 so they edit data only:
  - Ubuntu: add to `apt_packages`, `snap_packages`, `flatpak_packages` (verified only), `deb_packages`, or a new `vendor_repos` entry with `key` URL and `architectures`
  - macOS: add to `brew_formulae`, `brew_casks` or `mas_apps` in `ansible/group_vars/macos.yml`
  - verify with `uv run pre-commit run -a` and `tests/run.sh`
  - offer `/test-in-vm`
- `.claude/agents/ansible-reviewer.md`: replace checklist item 3 with "Vendor repos: an entry in `vendor_repos` using `deb822_repository` `signed_by: <key URL>`, with `architectures`; no `apt-key`, no hand-written `.list` files". Add item 9: "Registered/set variables inside a role are prefixed with the role name".

- [ ] **Step 5: Green, lint, commit, push**

Run: `tests/run.sh && uv run --locked pre-commit run -a`
Expected: all suites `all passed`; all hooks `Passed`.

```bash
git add README.md docs/development.md AGENTS.md CLAUDE.md .claude tests/claude/test_config.sh
git commit -m "docs: Short README and dev guide; update agent docs and skills for site.yml

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin feature/workspace-updates
```
