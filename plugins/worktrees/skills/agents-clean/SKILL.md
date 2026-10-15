---
name: agents-clean
description: "Clean up Claude's runtime leftovers: unlock worktree locks whose session is dead, stop finished or blocked background Claude sessions, remove dead sockets. Use when sessions or locks have piled up. Never touches interactive sessions or branches."
disable-model-invocation: true
---

Claude sessions leave state behind: worktree locks from dead processes, finished background jobs,
sockets whose pid is gone. `digest.sh` finds them; this skill acts on them after one yes.
Branches and worktrees themselves are `/prune-merged`'s and `/worktrees`'s job.

Success: re-running the digest shows zero `unlock`, `stop` and `rm-socket` rows. Anything left
carries the reason it survived.

## 1. Digest

```sh
${CLAUDE_SKILL_DIR}/digest.sh [path ...]
```

Read-only. Paths are repos to check for locks; none means every sibling clone of the current
repo (the parent directory of its main checkout). The table is the evidence; do not re-derive a
verdict from memory.

## 2. Triage

Group findings by `CLASS`, most consequential first, one line each: `unlock` → `stop` →
`rm-socket` → `report`.

## 3. Confirm

Show the exact action list — paths, session names, pids — and ask once. That yes covers the
`unlock`, `stop` and `rm-socket` rows and nothing else. `report` rows are printed, not acted on.

## 4. Act

Each step is idempotent and re-checks its row first.

1. **`unlock`** — only when the owner pid is dead, or its job is `done` and the branch is
   merged or contained; otherwise leave the lock and say which session holds it:
   ```sh
   git -C <repo> worktree unlock <path>
   ```
2. **`stop`** — one background session at a time. Reversible: `claude attach <id>` resumes it.
   ```sh
   claude stop <id>
   ```
3. **`rm-socket`** — dead pid, dead socket:
   ```sh
   rm /tmp/cc-socks/<pid>.sock
   ```

## 5. Re-run the digest

Clean means zero `unlock`, `stop`, `rm-socket`.

## 6. Report

What was unlocked, stopped and removed. What was kept, and why. Unlocked worktrees are now
prunable: suggest `/prune-merged`, then `/worktrees` for orphaned chats.

## Never

- Push, or open or merge an MR/PR.
- `claude rm` a session.
- Kill a `kind=interactive` session.
- Delete a `report` row.
- Touch a repo outside the digest's scope.
