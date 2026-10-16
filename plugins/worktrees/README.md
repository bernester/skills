# worktrees

Keep your git worktrees, branches and Claude sessions tidy.

## What it helps with

Working with Claude on several tasks at once leaves branches, copies of a project folder
(worktrees) and old chats behind. These four commands show what is still open, what is merged
and safe to delete, and what Claude left lying around. Nothing is deleted until you say yes to
a named list.

| Command | What it does |
|---|---|
| `/worktrees` | One overview of every worktree, branch and leftover chat, each with a state: finished, empty, live, ready, stranded, abandoned or orphaned. |
| `/prune-merged` | Lists merged branches and stale worktrees, then deletes the ones you approve. |
| `/agents-clean` | Clears leftovers of dead Claude sessions, after one yes. |
| `/left` | Says whether the current session can be archived, and what is still open. |

## Example

> **You:** `/prune-merged`
>
> **Claude:** I checked 4 repos. 3 branches are merged and safe to delete:
> `fix-header`, `docs-typos`, `new-footer`. `old-experiment` has commits that were never
> pushed, so I keep it. Delete the three?
>
> **You:** Yes.
>
> **Claude:** Deleted `fix-header`, `docs-typos`, `new-footer`. `old-experiment` stays.

## Install

[Follow the install steps on the index](../../README.md#install), then type a command above
to start.

## Needs

These commands work on git projects. Install first: `jq`, and `gh` (GitHub) or `glab` (GitLab),
signed in.

## What it runs

- [`skills/worktrees/SKILL.md`](skills/worktrees/SKILL.md)
- [`skills/prune-merged/SKILL.md`](skills/prune-merged/SKILL.md)
- [`skills/agents-clean/SKILL.md`](skills/agents-clean/SKILL.md)
- [`skills/left/SKILL.md`](skills/left/SKILL.md)
