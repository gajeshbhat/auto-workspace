# Provisioning v2 — Design

- **Date:** 2026-09-26
- **Branch:** `feature/workspace-updates`
- **Status:** Approved in brainstorming; awaiting written-spec review
- **Replaces roadmap sub-projects 2–4:** trim packages, refactor to best practices, and Claude Code + dotfiles. Sub-project 1 is done and pushed. CI (5) and the final review (6) follow this.

## Goal

Rewrite the playbooks as one clean, role-based, data-driven Ansible project that provisions exactly the apps in use, on **Ubuntu 24.04 and 26.04 LTS** and on **macOS 15 and 26**. Dotfiles, including Claude Code settings and plugins, are managed by chezmoi from `gajeshbhat/dotfiles`, and backup is one command.

## Success criteria

1. `site.yml` completes on fresh Multipass VMs for **Ubuntu 24.04 and 26.04**. A second run reports **`changed=0`**.
2. On an unsupported OS or version, the play fails in its first task with a clear message.
3. `uv run pre-commit run -a` passes with `.ansible-lint` at `profile: production`, and `tests/run.sh` passes.
4. Adding an app that uses an existing install method means adding one line to `group_vars`.
5. On a new machine, `chezmoi init --apply gajeshbhat/dotfiles` alone restores the shell, vim and screen configs, plus the Claude settings, skills and plugins. `dotfiles-backup` pushes local edits back.
6. The README is at most ~40 lines, and `docs/development.md` fits on one screen.

## Layout

```
install.sh                      # bootstrap → ansible/site.yml (macOS: also installs Homebrew)
ansible/
  ansible.cfg                   # inventory, roles_path, stdout callback
  site.yml                      # assert supported OS → group_by OS → roles
  inventory/hosts.yml           # localhost, local connection
  group_vars/
    all.yml                     # git identity, dotfiles repo, versions
    ubuntu.yml                  # apt / vendor repos / snap / flatpak / deb_urls lists
    macos.yml                   # brew formulae / casks / mas lists
  roles/
    base/                       # Ubuntu: apt upgrade, CLI tools, flatpak + flathub; macOS: brew update, mas
    vendor_repos/               # Ubuntu only: keyrings + deb822 repos from data
    packages/                   # installs every list in group_vars for the current OS
    docker/                     # Ubuntu: service + docker group; macOS: docker-desktop cask via packages
    virtualization/             # KVM/libvirt, LXD, VirtualBox 7.2 + extpack, Multipass; UTM on macOS
    languages/                  # rustup, Go, uv, fvm → Flutter stable, dotrun (uv tool)
    claude_code/                # official installer
    dotfiles/                   # chezmoi init/update --apply
scripts/test-in-vm.sh           # Multipass run + idempotency run (replaces scripts/testing/)
scripts/vm-setup/               # UTM helpers, pointed at site.yml
```

Removed: `ansible/linux.yml`, `ansible/macos.yml`, `ansible/hosts`, `ansible/playbooks/`, both `install-qt.sh` scripts, the empty `docker-daemon.json`, `scripts/README.md`, and `scripts/testing/`.

## Conventions

- **Supported-platform assert** is the first task. It accepts:
  - `ansible_distribution == "Ubuntu"` with version `24.04` or `26.04`
  - `ansible_os_family == "Darwin"` with major version `15` or `26`
- **Vendor repos derive everything from facts.** They use `ansible_distribution_release` (noble or resolute) and the dpkg architecture, never hard-coded values. Keys are dearmored into `/etc/apt/keyrings/<name>.gpg` and referenced with `signed-by`, and repos are added with `ansible.builtin.deb822_repository`. A repo entry can restrict architectures; Chrome is amd64-only.
- **Privilege:** the play runs with `become: false`. System tasks set `become: true`, and user files never pass through root.
- **Module names:** FQCN everywhere.
- **Services** restart through handlers.
- **Re-runs change nothing:**
  - `command`/`shell` tasks declare `creates:` or `changed_when:`
  - read-only probes set `check_mode: false` and `changed_when: false`
- **Tags:** one per role (`base`, `repos`, `packages`, `docker`, `virtualization`, `languages`, `claude`, `dotfiles`).
- **Lint:** `.ansible-lint` is set to `profile: production`, and `.yamllint` truthy allows only `true`/`false`.

## App matrix

### Ubuntu 24.04 and 26.04

| Method | Items |
|---|---|
| apt | CLI tools: curl, wget, git, vim, htop, build-essential, unzip, screen, tmux, ifstat, vnstat, nmap, net-tools |
| apt | brasero, libreoffice, vlc, deluge, simple-scan |
| apt | flatpak |
| vendor apt repo | Docker CE, CLI, containerd, buildx and compose plugins |
| vendor apt repo | VirtualBox `virtualbox-7.2` |
| vendor apt repo | WineHQ `winehq-stable` (i386 arch enabled) |
| vendor apt repo | VS Code `code` |
| vendor apt repo | Google Chrome (amd64 only) |
| vendor apt repo | Proton VPN `proton-vpn-gnome-desktop` |
| `.deb` URL (only when the package is absent) | Zoom |
| apt (virtualization role) | qemu-system-x86 (or qemu-system-arm on arm64), qemu-utils, libvirt-daemon-system, libvirt-clients, virtinst, virt-manager, bridge-utils |
| snap | lxd, multipass (classic), powershell (classic), spotify, proton-pass |
| Flathub (verified only) | LocalSend `org.localsend.localsend_app` |
| Flathub (verified only) | 0 A.D. `com.play0ad.zeroad` |
| Flathub (verified only) | GNOME Snapshot `org.gnome.Snapshot`, which replaces Cheese (absent from 26.04) |

**Group memberships:** docker, libvirt, kvm, lxd, vboxusers.

**LXD** is initialized with `lxd init --auto` only when no storage pool exists yet.

**VirtualBox Extension Pack:**
- Its version is taken from `VBoxManage --version`.
- It installs with the license hash computed from the downloaded pack.
- It is skipped when `VBoxManage list extpacks` already shows that version.

**Workarounds dropped:**
- the libvirt socket set to `0777`
- the `qemu:///session` default URI
- the `newgrp` shell tasks
- the AppIndicator `gnome-extensions enable` task (Ubuntu enables `ubuntu-appindicators` by default)
- `sysctl` inotify (only MicroK8s needed it)

**Known limitation:** VirtualBox kernel modules require manual MOK enrollment on Secure Boot machines. The README says this in one line.

### macOS 15 and 26

| Method | Items |
|---|---|
| install.sh | Homebrew (official installer, `NONINTERACTIVE=1`) |
| brew formulae | git, screen, htop, vim, python@3.13, mas |
| brew casks | google-chrome, spotify, visual-studio-code, vlc, protonvpn, virtualbox, multipass, docker-desktop, utm, localsend |
| mas | iA Writer (775737590) |

### Both OSes, user-level (languages, claude_code, dotfiles roles)

| Tool | Ubuntu | macOS |
|---|---|---|
| Rust | rustup official installer (`creates: ~/.cargo/bin/rustup`) | brew `rustup` + `rustup default stable` |
| Go | official tarball → `/usr/local/go`, version `go_version` (1.27.1), replaced only on version change | brew `go` |
| uv | official installer → `~/.local/bin` | brew `uv` |
| Flutter | fvm (official install script, `fvm_version` 4.3.1), then `fvm install stable` + `fvm global stable`; apt deps clang, cmake, ninja-build, pkg-config, libgtk-3-dev | fvm via brew tap `leoafarias/fvm`, then the same fvm steps |
| dotrun | `uv tool install dotrun` | same |
| Claude Code | official installer `https://claude.ai/install.sh` (`creates: ~/.local/bin/claude`) | same |
| chezmoi | official installer → `~/.local/bin` | brew `chezmoi` |

**Dropped:**
- MicroK8s, MicroCloud, MicroOVN, MicroCeph, Juju, MAAS
- Postman, Steam, TightVNC, Data Science Stack, Snapcraft, Charmcraft, Telegram, Mullvad Browser
- ADB/Fastboot, both Qt scripts
- Transmission, pipx
- the `astral-uv` snap
- the `rust` formula

## Dotfiles (`gajeshbhat/dotfiles` → chezmoi)

The conversion happens on branch `feature/chezmoi` and is delivered as a draft PR. The repo's existing README is kept and shortened.

```
.chezmoi.toml.tmpl            # data: git name/email (promptStringOnce; Ansible passes --promptString)
.chezmoiignore                # dot_bashrc on Linux only; dot_zshrc on macOS only
dot_bashrc                    # full file: Ubuntu /etc/skel/.bashrc + current dotfiles additions
dot_zshrc
dot_vimrc  dot_vimrc.plug  dot_screenrc
dot_gitconfig.tmpl            # [user] name/email from data
dot_claude/
  settings.json               # portable subset of ~/.claude/settings.json (see below)
  CLAUDE.md, agents/, skills/ # only if user-authored content exists
dot_local/bin/executable_dotfiles-backup   # chezmoi re-add && chezmoi git add/commit/push
.chezmoiscripts/
  run_onchange_after_10-vim-plug.sh.tmpl          # hash of dot_vimrc.plug → install plug.vim, vim +PlugInstall +qa
  run_onchange_after_20-claude-plugins.sh.tmpl    # hash of enabledPlugins → `claude plugin install <id>` each; skips if claude missing
```

- **The portable subset of `settings.json`** covers `permissions`, `enabledPlugins`, `extraKnownMarketplaces` (if any), `skillOverrides`, `hooks`, `theme`, `editorMode`, `timeFormat`, `worktree`, `enableWorkflows` and `feedbackDrafts`. Nothing machine-specific or secret goes in it.
- **Never tracked:**
  - `~/.claude/.credentials.json`
  - `history.jsonl`
  - `projects/`, `sessions/`, `jobs/`
  - `cache/`, `plugins/cache`, `skills/synced/`
  - `file-history/`, `backups/`, `state/`, `daemon*`, `stats-cache.json`
- **Ansible `dotfiles` role:**
  - The first run is `chezmoi init --apply --promptString name=… --promptString email=… {{ dotfiles_repo }}`.
  - Later runs use `chezmoi update --apply`.
  - `changed` comes from `chezmoi status` before and after.
- **Order:** the `claude_code` role runs before `dotfiles`, so the plugin script finds `claude`.
- **Before the playbook's first run replaces an existing `~/.bashrc`,** the role backs it up to `~/.bashrc.pre-chezmoi` once.

## Testing

- **Lint:** pre-commit, as in sub-project 1. The post-edit Claude hook syntax-checks `ansible/site.yml` for any change under `ansible/`.
- **`tests/run.sh`:** the existing suites are updated for the new paths (hooks, config, install.sh). `install.sh` tests cover the new `site.yml` invocation and the macOS Homebrew step, which is gated so tests never run it.
- **`scripts/test-in-vm.sh --release 24.04|26.04 [--keep]`:**
  1. launches a Multipass VM (4 CPU, 8G, 40G)
  2. copies in the working tree
  3. runs `install.sh`-equivalent steps plus `site.yml`
  4. runs `site.yml` again and fails if the second recap shows `changed>0`
  5. deletes the VM unless `--keep` is given
- **Out of scope for VMs:** the snap, Flatpak and GUI apps install, but their GUIs aren't exercised. macOS is validated in CI (sub-project 5).

## Docs

- **README, about 40 lines max:**
  - title and one sentence
  - supported platforms
  - the one-liner
  - "what gets installed" as one short line per group
  - how to customize: edit `ansible/group_vars/*.yml`
  - the Secure Boot note
  - a link to `docs/development.md`
- **`docs/development.md`:** setup one-liner, lint, VM test, adding an app, and dotfiles backup, one screen at most.
- **Updated to the new layout:**
  - `AGENTS.md`, `CLAUDE.md`
  - `.claude/skills/add-app` (adds one line to `group_vars`), `.claude/skills/test-in-vm` (wraps `scripts/test-in-vm.sh`)
  - `.claude/agents/ansible-reviewer.md`

## Out of scope

- GitHub Actions CI (sub-project 5)
- the final whole-branch review (sub-project 6)
- any scheduled or automatic dotfiles backup
- Molecule
