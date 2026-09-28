---
name: test-in-vm
description: Run ansible/site.yml for real in a throwaway Multipass VM (Ubuntu 24.04 or 26.04), then an idempotency run, and report failures and non-idempotent tasks.
disable-model-invocation: true
argument-hint: "[--release 24.04|26.04] [--tags <tags>] [--dotfiles-branch <b>] [--keep]"
---

# Test site.yml in a Multipass VM

The only sanctioned way to run the playbook for real.

1. `multipass version` must work and the host needs ~8G free RAM and ~40G disk.
2. Run in the background and wait for it:

   ```bash
   TIV_LOG_DIR="$CLAUDE_JOB_DIR/tmp" scripts/test-in-vm.sh $ARGUMENTS
   ```

3. Report:
   - the `PLAY RECAP` of both runs
   - every `fatal:` task with its message (from `<vm>-run1.log`)
   - any task listed as changed on run 2
   - the VM name, if `--keep` was used
