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
scripts/test-in-vm.sh         # Multipass VM runner for site.yml
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
scripts/test-in-vm.sh --release 24.04   # real run + idempotency in a Multipass VM
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
