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

# base
expect_task "Upgrade installed packages"
expect_task "Install base packages"
expect_task "Add Flathub remote"
expect_task "Check Homebrew is installed"
expect_task "Require Homebrew"

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

# Structural fixes found by the first VM smoke (Task 4 step 5):
# google-chrome-stable's postinst unconditionally rewrites its own .sources file if one already
# exists, clobbering our deb822 entry on first install; reasserting after install converges it.
expect_task "Reassert vendor apt repositories that package installs may overwrite"
# group_by always reports changed (fresh in-memory inventory every run); it changes nothing on
# disk, so it must not count against the "second run is a no-op" idempotency check.
site="$(cat ansible/site.yml)"
assert_contains "$site" "changed_when: false" "Group host by OS is marked changed_when: false"

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
  # vendor_repos' legacy-source cleanup list names old apt source files (e.g. mullvad.list) it
  # removes; that's not installing the app, so it's excluded from this "no longer installed" check.
  assert_eq "" "$(grep -rn "$gone" ansible/ | grep -v 'mullvad\.list' || true)" "dropped: $gone"
done

# docker + virtualization
expect_task "Enable and start Docker"
expect_task "Add user to the docker group"
expect_task "Install KVM and libvirt"
expect_task "Enable libvirtd socket activation"
# Ubuntu's libvirtd.service is socket-activated and exits after 120s idle (--timeout 120), so
# managing the service with state: started re-starts it (changed) on every later run.
vr_tasks="ansible/roles/virtualization/tasks/main.yml"
assert_eq "" "$(grep -nE 'name: libvirtd(\.service)?$' "$vr_tasks" || true)" "libvirtd.service is not managed directly"
assert_contains "$(cat "$vr_tasks")" "name: libvirtd.socket" "libvirtd.socket is enabled and started"
expect_task "Add user to virtualization groups"
expect_task "Check for LXD storage pools"
expect_task "Initialize LXD"
expect_task "Read VirtualBox version"
expect_task "Install the matching VirtualBox Extension Pack"

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

# claude_code + dotfiles
expect_task "Install Claude Code"
expect_task "Install chezmoi"
expect_task "Check for an existing chezmoi source"
expect_task "Initialize dotfiles with chezmoi"
expect_task "Pull dotfiles updates"
expect_task "Read chezmoi status"
expect_task "Warn about local dotfile edits"
expect_task "Apply dotfiles"
l_claude="$(printf '%s\n' "$TASKS" | grep -n 'Install Claude Code' | head -1 | cut -d: -f1)"
l_init="$(printf '%s\n' "$TASKS" | grep -n 'Initialize dotfiles with chezmoi' | head -1 | cut -d: -f1)"
assert_eq "true" "$([[ ${l_claude:-0} -gt 0 && ${l_claude:-0} -lt ${l_init:-0} ]] && echo true || echo false)" \
  "Claude Code install precedes chezmoi init"

# --- final review fixes --------------------------------------------------------
# ev EXPR [ARGS...] -> EXPR rendered by ansible (lists/dicts as compact JSON). ARGS are extra
# ansible args, typically -e @vars.yml / -e '<json>' supplying fake registered results.
ev() {
  local ex="$1"
  shift
  .venv/bin/ansible localhost -o -m ansible.builtin.debug -a "msg='{{ $ex }}'" "$@" 2>/dev/null \
    | sed -n 's/^localhost | SUCCESS => //p' \
    | .venv/bin/python -c 'import json,sys; m=json.load(sys.stdin)["msg"]; print(m if isinstance(m, str) else json.dumps(m, separators=(",", ":")))'
}

# Legacy apt sources written by the old playbooks: apt_repository named WineHQ's
# winehq-<codename>.list (Signed-By conflicts with winehq.sources) and ppa:wfg/0ad ppa_wfg_0ad_<codename>.list.
legacy="$(.venv/bin/python - <<'EOF'
import fnmatch, yaml
pats = yaml.safe_load(open("ansible/roles/vendor_repos/vars/main.yml"))["vendor_repos_legacy_sources"]
old = ["winehq-noble.list", "winehq-noble.sources", "ppa_wfg_0ad_noble.list", "wfg-ubuntu-0ad-noble.sources",
       "docker.list", "virtualbox.list", "protonvpn-stable.list", "mullvad.list", "google-chrome.list",
       "vscode.list", "github-cli.list"]
ours = ["docker.sources", "virtualbox.sources", "winehq.sources", "vscode.sources", "google-chrome.sources",
        "protonvpn.sources", "github-cli.sources"]
miss = [f for f in old if not any(fnmatch.fnmatch(f, p) for p in pats)]
hit = [f for f in ours if any(fnmatch.fnmatch(f, p) for p in pats)]
print("missed=%s removed_ours=%s" % (",".join(miss), ",".join(hit)))
EOF
)"
assert_eq "missed= removed_ours=" "$legacy" "legacy apt source patterns cover old files, spare ours"

# VBoxManage --version may print a vboxdrv warning banner (Secure Boot, pending reboot) first.
vbox_vars=(-e @ansible/roles/virtualization/vars/main.yml)
banner='{"virtualization_vbox_version_raw": {"stdout": "WARNING: The vboxdrv kernel module is not loaded. Either there is no module\n         available for the current kernel (6.8.0-45-generic) or it failed to\n         load. Please recompile the kernel module and install it by\n\n           sudo /sbin/vboxconfig\n\n         You will not be able to start VMs until this problem is fixed.\n7.2.4r170995"}}'
assert_eq "7.2.4" "$(ev virtualization_vbox_version "${vbox_vars[@]}" -e "$banner")" "VirtualBox version parsed past a warning banner"
assert_eq "7.2.4" "$(ev virtualization_vbox_version "${vbox_vars[@]}" -e '{"virtualization_vbox_version_raw": {"stdout": "7.2.4r170995"}}')" \
  "VirtualBox version parsed from plain output"

# Snaps: spotify and proton-pass are published for amd64 only (snap store channel-map, 2026-09-28).
snap_args=(-e @ansible/group_vars/ubuntu.yml -e @ansible/roles/packages/vars/main.yml)
assert_eq '["lxd","multipass","powershell"]' \
  "$(ev "packages_snaps | map(attribute='name') | list" "${snap_args[@]}" -e '{"dpkg_arch": "arm64"}')" "arm64 skips amd64-only snaps"
assert_eq '["lxd","multipass","powershell","proton-pass","spotify"]' \
  "$(ev "packages_snaps | map(attribute='name') | list" "${snap_args[@]}" -e '{"dpkg_arch": "amd64"}')" "amd64 installs every snap"
assert_contains "$(cat ansible/roles/packages/tasks/debian.yml)" 'loop: "{{ packages_snaps }}"' "snap install loops over the arch-filtered list"

# Dotfiles: never clobber an existing machine's files or git identity.
expect_task "Read the existing git user name"
expect_task "Read the existing git user email"
expect_task "Keep machine-specific git settings in ~/.gitconfig.local"
expect_task "Read chezmoi state"
expect_task "Back up existing files before chezmoi takes them over"
df_tasks="$(cat ansible/roles/dotfiles/tasks/main.yml)"
assert_eq "" "$(grep -nE -- '- --(apply|force)$' ansible/roles/dotfiles/tasks/main.yml || true)" "chezmoi init neither applies nor forces"
assert_contains "$df_tasks" "Git email={{ dotfiles_git_email }}" "chezmoi is given the resolved git email"
df_args=(-e @ansible/group_vars/all.yml -e @ansible/roles/dotfiles/vars/main.yml)
assert_eq "real@example.org" "$(ev dotfiles_git_email "${df_args[@]}" -e '{"dotfiles_git_email_current": {"config_value": "real@example.org"}}')" \
  "existing git email is kept"
assert_eq "myemail@example.com" "$(ev dotfiles_git_email "${df_args[@]}" -e '{"dotfiles_git_email_current": {"config_value": ""}}')" \
  "git email falls back to group_vars when unset"
assert_eq "Gajesh Bhat" "$(ev dotfiles_git_name "${df_args[@]}" -e '{"dotfiles_git_name_current": {"config_value": ""}}')" \
  "git name falls back to group_vars when unset"
assert_eq "Gajesh Bhat" "$(ev dotfiles_git_name "${df_args[@]}" -e '{"dotfiles_git_name_current": {"skipped": true}}')" \
  "git name falls back when the probe was skipped"
# chezmoi status: ' M' = exists, differs, chezmoi never wrote it (no entryState) -> back up before apply.
# 'MM' = edited after chezmoi wrote it (left alone; apply is skipped), ' A' = absent, ' R' = script.
df_state='{"workstation_home": "/h", "dotfiles_status": {"stdout_lines": [" M .vimrc", " M .screenrc", "MM .bashrc", " A .gitconfig", " R install.sh", " M .claude/settings.json"]}, "dotfiles_state": {"stdout": "{\"entryState\": {\"/h/.screenrc\": {}, \"/h/.bashrc\": {}}}"}}'
assert_eq '[".vimrc",".claude/settings.json"]' "$(ev dotfiles_backup_files "${df_args[@]}" -e "$df_state")" \
  "back up existing files chezmoi never wrote"

# macOS: casks that sudo need the become password; base runs brew update.
assert_contains "$(cat ansible/roles/packages/tasks/darwin.yml)" 'sudo_password: "{{ ansible_become_password | default(omit) }}"' \
  "homebrew_cask gets the become password"
expect_task "Update Homebrew"
assert_contains "$(cat ansible/roles/base/tasks/darwin.yml)" "update_homebrew: true" "base updates Homebrew"
guest="$(cat scripts/vm-setup/macos-guest/run-ansible.sh)"
assert_eq "" "$(grep -nE 'ANSIBLE_STDOUT_CALLBACK|ansible-playbook.*\|\| true' scripts/vm-setup/macos-guest/run-ansible.sh || true)" \
  "macOS guest runner: no removed yaml callback, failures propagate"
assert_contains "$guest" 'cd "$SHARE_ROOT"' "macOS guest runner runs from the repo root"

# README accuracy.
readme="$(cat README.md)"
assert_contains "$readme" "cd ~/auto-workspace && uv run ansible-playbook ansible/site.yml -K --tags languages" "README tag example is runnable"
assert_eq "" "$(grep -n "only changes what's missing" README.md || true)" "README does not claim re-runs change nothing"

finish
