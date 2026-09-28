# Dev Tooling, Bootstrap Scripts, and Agent Docs — Design

- **Date:** 2026-09-26
- **Branch:** `feature/workspace-updates`
- **Status:** Approved in brainstorming; awaiting written-spec review
- **Sub-project:** 1 of 6

## Roadmap context

The workspace overhaul is split into sub-projects, each with its own spec → plan → implementation cycle, in this agreed order:

1. **Dev tooling + agent docs** (this spec)
2. Trim packages the user no longer uses
3. Refactor to Ansible best-practice structure (roles, `group_vars`, `site.yml`); raise lint profile to `production`
4. Claude Code + dotfiles role (install and configure Claude Code)
5. GitHub Actions CI following the GitHub Well-Architected Framework
6. Final review (`/code-review`, `/security-review`) and branch finish (PR)

Decisions that apply across sub-projects:

- **macOS stays supported** and is refactored alongside Ubuntu 24.04.
- The SDLC process is the installed **superpowers** workflow (brainstorming → writing-plans → execution → verification → review → finish).
- The user prefers **simple one-line shell entry points** over multi-step instructions.

## Goal

Give the repo a reproducible, pinned lint toolchain; two one-line scripts (dev environment, machine bootstrap); and agent-facing docs (`AGENTS.md`, `CLAUDE.md`, project `.claude/` config) so that humans and coding agents can work on it safely.

## Success criteria

1. On a clean clone, `./scripts/setup-dev.sh` completes and afterwards `uv run pre-commit run -a` runs yamllint, ansible-lint, and shellcheck. Existing code passes under the initial lint configuration.
2. Re-running `setup-dev.sh` is a no-op apart from confirming state; it never uses `sudo` or changes system packages.
3. `install.sh --check` on Ubuntu 24.04 (Multipass VM) bootstraps uv, clones the repo, and starts `linux.yml` in check mode. On an unsupported OS it exits non-zero with a clear message. Today's tasks are not all check-mode-safe; for example, the Zoom `stat` task runs after a download that check mode skips. A playbook failure *inside* check mode is therefore recorded as input for sub-project 3 and does not fail this criterion.
4. `AGENTS.md` alone is enough for a non-Claude agent to set up, lint, and test the repo and know the safety rules. `CLAUDE.md` imports it and adds only Claude-specific guidance.
5. The project hooks behave as designed. An edit to a `.yml` file triggers a syntax check, and an edit to a `.sh` file triggers shellcheck. A real `ansible-playbook ansible/linux.yml` Bash call is blocked, while `--syntax-check` and `--check` calls are allowed.

## Design

### 1. Pinned toolchain

| File | Purpose |
|---|---|
| `pyproject.toml` | Non-package uv project. `[dependency-groups] dev` pins `ansible-core`, `ansible-lint`, `yamllint`, `pre-commit`, `shellcheck-py`. `requires-python` matches Ubuntu 24.04's `python3` (≥3.12). |
| `uv.lock` | Committed lockfile. CI (sub-project 5) uses the same lock. |
| `requirements.yml` | Galaxy collections the playbooks use: `community.general` (Homebrew and mas modules). |
| `.yamllint` | Extends `default`. `line-length` is a warning at 160, `truthy` allows `yes/no` for now (tightened in sub-project 3), and `.venv/` and `.git/` are ignored. |
| `.ansible-lint` | `profile: min` for now, so the current code passes; sub-project 3 raises it to `production`. `exclude_paths`: `.venv/`, `.claude/`, `docs/`. |
| `.pre-commit-config.yaml` | Hooks: `trailing-whitespace`, `end-of-file-fixer`, `check-yaml`, `yamllint`, `ansible-lint`, and `shellcheck` (via `shellcheck-py`). Hook revisions are pinned. |
| `.gitignore` | Adds `.venv/`. |

The versions of the Python tools come from `uv.lock`. The hook versions come from the `rev:` pins in `.pre-commit-config.yaml`. Both are updated deliberately, never floated.

### 2. `scripts/setup-dev.sh` — dev environment one-liner

Usage: `./scripts/setup-dev.sh` from a clone. It is idempotent and never uses sudo.

1. `set -euo pipefail`, then `cd` to the repo root (resolved from the script path).
2. If `uv` is missing, install it with the official installer (`curl -LsSf https://astral.sh/uv/install.sh | sh`) and add `~/.local/bin` to `PATH` for the rest of the run.
3. Run `uv sync --group dev`.
4. Run `uv run ansible-galaxy collection install -r requirements.yml`.
5. Run `uv run pre-commit install`.
6. Print the next commands: `uv run pre-commit run -a`, and the path to the VM test script.

### 3. `install.sh` — machine bootstrap one-liner

Usage: `curl -fsSL https://raw.githubusercontent.com/gajeshbhat/auto-workspace/master/install.sh | bash [-s -- --check --branch <b> --dir <d>]`

1. Parse flags. Defaults: `--dir ~/auto-workspace`, `--branch master`, and a real run unless `--check` is given.
2. Detect the OS:
   - Ubuntu 24.04 (via `/etc/os-release`) → `linux.yml`
   - macOS (`uname -s` = Darwin) → `macos.yml`
   - anything else → exit 1 with a clear message
3. Ensure git is installed:
   - on Ubuntu, `sudo apt-get install -y git curl`
   - on macOS, trigger the Xcode Command Line Tools install if `xcode-select -p` fails, then wait for it and re-check
4. Install uv if it is missing (same method as `setup-dev.sh`).
5. Clone the repo into `--dir`. If it is already a clone, run `git fetch` and then `git checkout <branch>` and `git pull --ff-only`. If the directory exists but is not this repo, refuse to continue.
6. From `--dir`, run `uv sync --group dev` and install the collections.
7. Run `uv run ansible-playbook -i ansible/hosts ansible/<os>.yml -K`. Add `--check` when the flag is set.
8. Print the post-install notes: log out and back in for group changes, and possibly reboot.

The script is written for `bash` (the documented one-liner pipes to `bash`) and passes shellcheck. The whole body is wrapped in a `main` function that runs on the last line, so a partial download cannot execute half a script.

### 4. `AGENTS.md` — canonical agent instructions

Sections:

- **What this repo is.** Ansible provisioning for Ubuntu 24.04 and macOS workstations, run against localhost.
- **Layout.** The current tree, to be updated in sub-project 3.
- **Commands.** Setup, lint, syntax-check, and VM test.
- **Conventions:**
  - one task per app with a `# --- <App> ---` header
  - vendor apt repos use `/etc/apt/keyrings/*.gpg` with `signed-by`, never `apt-key`
  - `shell`/`command` tasks declare `creates:` or `changed_when:`
  - new apps are listed in the README
  - commit style is `feat|fix|refactor: <summary>`
- **Safety rules:**
  - Never run `linux.yml` or `macos.yml` for real on the developer's host. Use `--syntax-check`, `--check`, or `scripts/testing/test-linux-playbook.sh`.
  - Plays run with `become: yes`, so `~` resolves to root. Use `/home/{{ username }}`, or set `become: false`, for user files.
  - Never commit secrets. The Qt credentials in `install-qt.sh` are passed via environment variables or flags only.

### 5. `CLAUDE.md` — Claude-specific layer

- The first line is `@AGENTS.md`, which imports the canonical instructions.
- **SDLC workflow**, using the superpowers skills:
  1. `superpowers:brainstorming` for any feature or behavior change
  2. `superpowers:writing-plans`
  3. `superpowers:executing-plans` or `superpowers:subagent-driven-development`
  4. `superpowers:test-driven-development`, where "red" means a failing lint, syntax check, or check-mode run before the fix
  5. `superpowers:systematic-debugging` for failures
  6. `superpowers:verification-before-completion`
  7. `superpowers:requesting-code-review`
  8. `superpowers:finishing-a-development-branch`
  - Work happens on feature branches or worktrees (`superpowers:using-git-worktrees`).
- **Relevant installed tooling:**
  - `/code-review`, `/security-review`, and `/simplify`
  - `update-config`, for hook changes
  - the `feature-dev` plugin agents (`code-explorer`, `code-architect`, `code-reviewer`)
  - `claude-code-setup:claude-automation-recommender`
  - the `security-guidance` plugin
  - the project agent `ansible-reviewer`, and the project skills `add-app` and `test-in-vm`
- **Explicitly irrelevant here:** dataviz and artifact skills, office-document skills, `mcp-server-dev`, `receipts`, and `claude-api`.

### 6. Project `.claude/` config (committed)

- **`.claude/settings.json` hooks:**
  - **PostToolUse** (`Edit|Write|MultiEdit`) runs `.claude/hooks/post-edit-check.sh`, which reads the hook JSON from stdin:
    - For `*.yml`/`*.yaml` files it runs `uv run ansible-playbook -i ansible/hosts ansible/linux.yml --syntax-check`, or `macos.yml` when the path is under `macos/` or is `macos.yml`.
    - For `*.sh` files it runs `uv run shellcheck <file>`.
    - On failure it exits with code 2 and prints the output to stderr, which is fed back to Claude.
    - If `.venv` is missing it skips with a note.
  - **PreToolUse** (`Bash`) runs `.claude/hooks/block-host-playbook.sh`:
    - It denies (exit 2) any command that contains `ansible-playbook` together with `linux.yml`, `macos.yml`, or `site.yml` and has neither `--syntax-check` nor `--check`/`-C`.
    - It allows `multipass exec` wrappers, because those runs happen inside a VM.
- **`.claude/agents/ansible-reviewer.md`.** Reviews Ansible diffs against a checklist: idempotency, become/user and `~` usage, keyrings and `signed-by`, amd64/arm64 assumptions, `ignore_errors` masking failures, a missing README entry, and parity with the macOS playbook.
- **`.claude/skills/add-app/SKILL.md`** (`disable-model-invocation: true`). Given an app name, it:
  1. chooses the install method in this order: snap → apt → vendor repo with a keyring
  2. adds a task to the right Linux task file and a cask or formula to the macOS vars
  3. updates the README and runs the lint
  4. commits as `feat: Add <app>`
- **`.claude/skills/test-in-vm/SKILL.md`** (`disable-model-invocation: true`). Runs `scripts/testing/test-linux-playbook.sh -k -v` and reports:
  - failed tasks
  - tasks that report changed on a second run (idempotency)
  - the VM name, so the VM can be cleaned up

### 7. Human docs

- **`docs/development.md`:**
  - prerequisites
  - the two one-liners
  - linting and pre-commit
  - syntax/check mode
  - VM testing for Linux (Multipass) and macOS (UTM)
  - repo layout
  - how to add an app
- **`README.md`:**
  - a new quickstart with the `install.sh` one-liner
  - a link to `docs/development.md`
  - fix the wrong clone URL (`Auto-Workspace-GUI`)
  - fix the wrong variable names (`git_user_*` should be `git_global_user_*`)

## Error handling

- Both scripts use `set -euo pipefail` and print `[+]` progress and `[!]` error lines, matching the existing `scripts/` style.
- Every step can be re-run safely.
- Hooks fail open when the toolchain isn't installed (they print a note and exit 0), so a fresh clone isn't blocked. The block-host-playbook hook always fails closed.

## Testing and verification

- Lint: `uv run pre-commit run -a` passes on the whole repo.
- Scripts:
  - `shellcheck` is clean.
  - `setup-dev.sh` runs twice in a row with success both times.
  - `install.sh --check --branch feature/workspace-updates` runs inside a fresh Multipass 24.04 VM.
  - `install.sh` on an unsupported OS is simulated by overriding the path of the `/etc/os-release` file it reads.
- Hooks are fed sample hook-input JSON on stdin:
  - a real playbook command → exit 2
  - `--check` → exit 0
  - `multipass exec … ansible-playbook` → exit 0
  - a broken YAML edit → exit 2 with the syntax error

## Out of scope (later sub-projects)

- Fixing existing lint violations beyond what `profile: min` requires (sub-project 3). The one exception: formatting-only fixes that the new hooks require are in scope, such as trailing whitespace, EOF newlines, `---` document starts, and comment indentation. They go in a separate `style:` commit, with no change in behavior.
- The Claude Code install role and dotfiles automation (sub-project 4).
- CI workflows (sub-project 5).
- Removing or adding apps (sub-project 2).
