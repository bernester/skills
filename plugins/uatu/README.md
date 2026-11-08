# uatu

A weekly report on how your Claude setup is really used, proposing changes with evidence.

**This one is for developers who keep their own harness repo.** It is built for its author's
setup. If you are not sure, skip it.

## What it helps with

uatu reads upstream Claude Code changes, how your skills and settings are actually used, and
whether your policy still matches your research notes. It comes back with at most seven
proposed changes, each with its evidence, and changes nothing you have not approved. Its data
lives in `~/.claude/uatu/`.

It picks one of two modes on each run, and the report says which:

- **Local mode**, the default. After the report, you answer each change: apply it, decline it
  with a reason, or defer it. uatu never commits.
- **PR mode**, when `~/.claude` is a git repo with a GitHub `origin`, `gh` is signed in and a
  `uatu` label exists. Each change becomes a pull request labelled `uatu`; merge it to accept,
  close it with a reason to decline. uatu never merges.

A declined change is not proposed again. Terms: [GLOSSARY.md](GLOSSARY.md).

## Example

> **You:** `/uatu`
>
> **Claude:** Digest written. Two recommendations this week:
> 1. Skill `deploy-notes` has not run in 41 days — retire it? Evidence: `history.tsv` rows 12–19.
> 2. Upstream added a hook event your policy does not mention. Edit `CLAUDE.md:30`?
>
> *Apply, Decline or Defer for each.*

`/uatu <skill-dir>` checks one skill's craft instead and prints the result.

## Install

[Follow the install steps on the index](../../README.md#install), then type `/uatu`. There is no
setup step.

`/uatu setup` is optional: it reports the mode, missing tools, and what PR mode still needs.

Optional variables:

- `UATU_HOME` — a folder other than `~/.claude` to keep `uatu/` and `research/` in.
- `UATU_MODE` — `local` or `pr` to override the pick.
- `UATU_LESSONS` — a markdown file of `## ` entries; an entry is open when it contains
  `**open**` or `**open, …**`.
- `UATU_PAPERCUTS` — one line per papercut, `YYYY-MM-DD · symptom · fix · repo`.

Each log is an absolute path; unset, its channel is skipped.

## Upgrading from 0.1

0.1 required `UATU_HOME`, a git repo and a `uatu` label. An install set up that way keeps
working in PR mode. Run `/uatu setup` once: it shows what the install can drop and applies the
parts you pick —

- `UATU_HOME` set to `~/.claude` is redundant; it prints the shell-profile line to remove.
- Switch to local mode: imports each closed `uatu` pull request into `uatu/declined.md` and
  lists the open ones to merge or close first.
- `UATU_HOME` set to another folder: copies its `uatu/` data into `~/.claude/uatu/`. The old
  folder is never deleted.

## Needs

`python3`, `jq`, and macOS. PR mode also needs `gh`.

## What it runs

[`skills/uatu/SKILL.md`](skills/uatu/SKILL.md)
