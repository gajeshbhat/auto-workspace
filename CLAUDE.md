@AGENTS.md

# Claude Code notes

Everything above (from AGENTS.md) applies. This section adds Claude-specific workflow.

## Development workflow (superpowers SDLC)

Use the installed superpowers skills, in order:

1. `superpowers:brainstorming`: for any new feature or behavior change, before touching code. It produces a spec in `docs/superpowers/specs/`.
2. `superpowers:writing-plans`: turns the approved spec into a plan in `docs/superpowers/plans/`.
3. `superpowers:subagent-driven-development` or `superpowers:executing-plans`: carry out the plan task by task.
4. `superpowers:test-driven-development`: here "red" means a failing `tests/run.sh` case, lint error, `--syntax-check` or check-mode run *before* the fix.
5. `superpowers:systematic-debugging`: for any failing run or lint before proposing a fix.
6. `superpowers:verification-before-completion`: run `uv run pre-commit run -a` and `tests/run.sh` and show the output before claiming done.
7. `superpowers:requesting-code-review`, then `superpowers:finishing-a-development-branch`.
8. CI (`.github/workflows/ci.yml`) is the real test: open or update the PR and check it with `gh pr checks` instead of asking the user to test by hand. When adding or dropping a supported OS, change `supported_ubuntu_versions` and the CI `provision` matrix together (see AGENTS.md Conventions).

Work happens on a feature branch or worktree (`superpowers:using-git-worktrees`).

## Project automation (`.claude/`)

- **Hooks** (`.claude/settings.json`):
  - `post-edit-check.sh` lints and syntax-checks after every YAML or shell edit.
  - `block-host-playbook.sh` refuses real playbook or `install.sh` runs on this machine.
  - Change them via the `update-config` skill.
- **Subagent** `ansible-reviewer`: run it on any change under `ansible/` before opening a PR.
- **Skills** (user-invoked):
  - `/add-app <name>`: adds an app to the Ubuntu app lists, updates the README, commits.
  - `/test-in-vm`: runs `scripts/test-in-vm.sh` (real run + idempotency).

## Other useful installed tooling

- `/code-review` and `/security-review` before merging; `/simplify` for cleanup passes.
- `feature-dev` plugin agents: `code-explorer` (trace how something works), `code-architect` (design), `code-reviewer`.
- `claude-code-setup:claude-automation-recommender`: suggests further hooks, skills and MCP servers.
- The `security-guidance` plugin runs automatically on edits.

## Not relevant to this repo

dataviz, artifact and office-document skills (docx/xlsx/pptx/pdf), `mcp-server-dev`, `receipts`, and `claude-api`. Don't reach for them here.
