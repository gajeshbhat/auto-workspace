# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, …) and humans working on this repository.

## What this repo is

Ansible that provisions a personal workstation, run against `localhost`:

- **Ubuntu 24.04 / 26.04 LTS**

## Layout

```text
ansible.cfg                   # inventory + output settings
ansible/site.yml              # entry playbook: platform assert, then the Ubuntu play
ansible/inventory/            # localhost inventory
ansible/group_vars/           # app lists, versions and identity (data)
ansible/roles/
  base/                       # OS packages, kernel headers, PATH
  vendor_repos/               # deb822 apt repos (Docker, VirtualBox, Wine, VS Code, Chrome, Zoom)
  packages/                   # apt/snap/flatpak/.deb apps
  docker/                     # Docker Engine + group
  virtualization/             # KVM/libvirt, LXD, VirtualBox extension pack
  languages/                  # rustup, Go, uv, fvm/Flutter, dotrun
  claude_code/                # Claude Code CLI
  dotfiles/                   # chezmoi from gajeshbhat/dotfiles
install.sh                    # one-line machine bootstrap (curl | bash)
scripts/setup-dev.sh          # one-line dev environment setup
scripts/test-in-vm.sh         # Multipass VM runner for site.yml
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
uv run ansible-playbook ansible/site.yml --syntax-check
scripts/test-in-vm.sh --release 26.04   # real run + idempotency in a Multipass VM
```

Tool versions are pinned in `pyproject.toml`/`uv.lock` and collections in `requirements.yml`. Change them deliberately, never float them.

## Safety rules

1. **Never run `ansible/site.yml` or `install.sh` for real on the machine you are working on.** They dist-upgrade the OS, rewrite system config and install dozens of packages as root. Use `ansible-playbook … --syntax-check` / `--check` (not `install.sh`, even with `--check`: it still installs packages first), or `scripts/test-in-vm.sh` (Multipass VM). Claude Code enforces this with `.claude/hooks/block-host-playbook.sh`.
2. The plays run with task-level `become`, so root-owned paths and user paths differ. For user files use `/home/{{ username }}` and set `owner`/`group`, or `become: false`.
3. Never commit secrets or personal credentials. `install-qt.sh` reads Qt credentials from flags or environment variables only.
4. Work on feature branches. Never push to or rewrite `master`.

## Conventions

- Apps are data: add or remove them in `ansible/group_vars/ubuntu.yml`, not as new tasks.
- Vendor apt repos use `ansible.builtin.deb822_repository` with `signed_by: <key URL>`; never `apt-key`, never a hand-written `.list` file.
- Every variable a role registers or sets is prefixed with the role's name (e.g. `docker_service_name`).
- FQCN for every module (`ansible.builtin.*`, `community.general.*`, …).
- `become` is set per task, not at the play level.
- A second run of any task must report `changed=0`.
- **CI must provision every supported platform.** `supported_ubuntu_versions` in `ansible/group_vars/all.yml` is the single list of supported releases; the `provision` matrix in `.github/workflows/ci.yml` must run each of them on amd64 and arm64 (`ubuntu-<ver>` and `ubuntu-<ver>-arm`). Adding or dropping a platform means changing both in the same commit; `tests/ansible/test_site.sh` fails otherwise. A platform GitHub cannot host is not supported.

## Definition of done

`uv run pre-commit run -a` and `tests/run.sh` pass, the relevant playbook passes `--syntax-check`, and CI (`.github/workflows/ci.yml`: lint + real provisioning with an idempotency re-run on every supported platform) is green on the PR.
