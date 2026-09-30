---
name: add-app
description: Add a new application to the auto-workspace Ubuntu playbooks, document it in the README, lint, and commit it.
disable-model-invocation: true
argument-hint: <app name>
---

# Add an app to auto-workspace

The app to add: **$ARGUMENTS**

## 1. Pick the Ubuntu install method (first that works)

1. **Snap.** Run `snap info <name>` to confirm it exists; use `classic: true` only if the snap requires it.
2. **Apt, from the Ubuntu archive.** Run `apt-cache policy <pkg>` to confirm a candidate exists.
3. **Flatpak**, verified publishers only.
4. **Vendor apt repo.** Only if none of the above work; needs its own `vendor_repos` entry (see step 2).

State which method you chose and why.

## 2. Add the app as data

- Ubuntu, in `ansible/group_vars/ubuntu.yml`: add the package name to `apt_packages`, `snap_packages`, `flatpak_packages` or `deb_packages`. A vendor apt repo (method 4) instead gets a new entry in `vendor_repos` with a `key` URL and `architectures`.

No new tasks — the `packages` and `vendor_repos` roles already loop over these lists.

## 3. Document it

Add the app to the matching list under "What you get" in `README.md`.

## 4. Verify

```bash
uv run pre-commit run -a
tests/run.sh
```

Both must pass. Offer `/test-in-vm` for a real install test; do not run the playbook on this machine.

## 5. Commit

```bash
git add ansible README.md
git commit -m "feat: Add <App>"
```
