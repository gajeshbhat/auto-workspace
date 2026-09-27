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
