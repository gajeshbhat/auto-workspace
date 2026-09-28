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
