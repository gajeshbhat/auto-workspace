---
name: test-in-vm
description: Run the Linux playbook for real inside a throwaway Multipass Ubuntu 24.04 VM, then report failed tasks and non-idempotent tasks.
disable-model-invocation: true
argument-hint: "[extra test-linux-playbook.sh flags, e.g. -c 4 -m 8G]"
---

# Test linux.yml in a Multipass VM

This is the only sanctioned way to run `ansible/linux.yml` for real.

1. Check prerequisites: `multipass version` must work. Ensure there is enough free host memory for the VM (the default is 12G; pass `-m 8G` if tight).
2. Start the run in the background, keeping the VM and logging to a file:

   ```bash
   scripts/testing/test-linux-playbook.sh -k -v $ARGUMENTS 2>&1 | tee "$CLAUDE_JOB_DIR/tmp/vm-run-1.log"
   ```

   It takes about 40 minutes. Note the VM name from the `Launching Ubuntu 24.04 VM: <name>` line.
3. Summarize run 1 from the log:
   - the `PLAY RECAP` line
   - every `fatal:` or `FAILED!` task, with its task name and the error message
4. Idempotency check: re-run the playbook in the same VM and capture the recap.

   ```bash
   multipass exec <name> -- bash -lc "cd ~/auto-workspace && ansible-playbook -i ansible/hosts ansible/linux.yml" 2>&1 | tee "$CLAUDE_JOB_DIR/tmp/vm-run-2.log"
   ```

   List every task that reports `changed:` in run 2; each is an idempotency bug.
5. Report: failures (run 1), non-idempotent tasks (run 2), and the VM name, plus the cleanup command `multipass delete <name> && multipass purge`. Ask before deleting the VM.
