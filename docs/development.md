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
