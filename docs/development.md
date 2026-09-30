# Development

```bash
./scripts/setup-dev.sh         # uv toolchain, collections, git hooks (no sudo)
uv run pre-commit run -a       # yamllint, ansible-lint (production), shellcheck, shell tests
tests/run.sh                   # shell + playbook structure tests
scripts/test-in-vm.sh --release 26.04   # real run + idempotency check in a Multipass VM
```

Never run `ansible/site.yml` or `install.sh` for real on your own machine while developing; use the VM script.

## Layout

- `ansible/site.yml` – checks the platform, then runs the Ubuntu play
- `ansible/group_vars/` – all app lists and versions (data)
- `ansible/roles/` – base, vendor_repos, packages, docker, virtualization, languages, claude_code, dotfiles

## Add an app

Add one line to the matching list in `ansible/group_vars/ubuntu.yml` (a new vendor apt repo is one `vendor_repos` entry). With Claude Code: `/add-app <name>`. Then lint and run the VM test.

## Dotfiles

Managed by chezmoi from `gajeshbhat/dotfiles`. `dotfiles-backup` pushes local edits (including `~/.claude/settings.json`). The playbook never overwrites locally edited dotfiles; it warns instead. Files it would replace for the first time are saved as `<file>.pre-chezmoi`, and an existing `~/.gitconfig` moves to `~/.gitconfig.local` (still included).

## Tool versions

Pinned in `pyproject.toml`/`uv.lock` and `requirements.yml`; bump with `uv add --dev <tool>==<ver>` and commit the lock.
