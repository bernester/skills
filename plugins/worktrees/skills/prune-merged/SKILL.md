---
name: prune-merged
description: Prune merged branches and stale git worktrees, using the forge's MR/PR state as the verdict. Use when the user wants to clean up after a merge, asks whether a branch or MR/PR got merged, or wants worktrees and leftover branches swept across their repos. The sweep is read-only, so it also answers "did this land?" without deleting anything; deletion happens only after the user says yes to a named list of rows. It never pushes, merges, or changes an MR, and it does not report worktree health or resumability — `/worktrees` owns that.
---

Every deletion is authorized by a **verdict** — what the forge says happened to the branch's MR/PR. Git ancestry does not issue verdicts: both GitLab and GitHub squash by default, so a merged branch's commits are absent from the default branch's history and `git branch --merged` reports it as unmerged forever. A `gone` upstream is likewise only a hint.

`sweep.sh` collects the verdicts. It is read-only. It picks the forge per repo from `origin` — `glab` for GitLab, `gh` for GitHub — and reports an `api-down` row for any repo where that CLI is missing, unauthenticated, or the host is neither.

## 1. Sweep

```
${CLAUDE_SKILL_DIR}/sweep.sh [path ...]
```

No argument sweeps the current repo. Pass a parent directory (e.g. `~/code`) when the ask spans repos — it expands to every clone inside. It fetches with `--prune` first, so expect a few seconds per repo.

Done when you have the table. Each row carries a verdict and an `ACTION` of `PRUNE` or `keep`; the three columns after it — `STATE`, `PULSE`, `RESUME` — belong to `/worktrees` and play no part in pruning. `ahead-of-PR` applies to worktrees as well as branches, so a clean worktree with commits after its merged MR is `keep`; on worktree rows it sits inside `VERDICT` (`merged !52 ahead-of-PR`) because `SAFETY` carries `clean`/`dirty` there. The branch the main checkout has checked out is always `keep` — git cannot delete it:

| verdict | means |
|---|---|
| `merged !N` / `merged #N` + `tip=PR` | merged, and the local tip is exactly what was merged — deleting loses nothing |
| `merged` + `behind-PR` | the local tip is an ancestor of the merged head or of the default branch, or one of the MR's own commits — nothing unique here |
| `merged` + `ahead-of-PR` | the local tip was never pushed to the MR — it may be work that exists only here |
| `no-mr in-<default>` | no MR/PR, every commit already reachable from the default branch |
| `detached in-<default>` | agent worktree with no branch, fully contained in the default branch |
| `open` / `closed` / `no-mr` | still live, or unique work never merged |
| `api-down` (repo row) | no verdicts available for that repo — the `SAFETY` column names the cause |
| `no-api` | that branch's verdict is unknown rather than absent; git alone still proves containment, so `no-api in-<default>` stays prunable |
| `dirty` | uncommitted changes in that worktree |

## 2. Confirm

Show the user the `PRUNE` rows and the `keep` rows with their reasons, then ask for a yes before deleting anything. Two rows to name aloud:

- `ahead-of-PR` — the one case where a mistaken delete destroys work with no remote copy.
- `api-down` — that repo was judged by git alone, so merged branches there hide among the `no-api` keeps. Installing or authenticating the CLI it names is what turns those into verdicts.

Done when the user has answered. A yes covers the rows you listed and nothing else.

## 3. Prune

Delete only rows the sweep marked `PRUNE`, worktrees before their branches:

```bash
git -C <repo> worktree remove <path>     # refuses on dirty — a backstop, not the gate
git -C <repo> branch -D <branch>         # -D is correct: squash-merged branches fail -d
git -C <repo> worktree prune             # clears admin entries for worktrees gone from disk
```

Clones themselves are reported, never removed — a repo directory with nothing left to prune is a result, not a target.

Done when every `PRUNE` row is deleted or has a stated reason it survived.

## 4. Report

Per repo: what was deleted, and what was kept with the verdict that spared it. Re-run the sweep on anything you are unsure of rather than reasoning about the tree from memory.
