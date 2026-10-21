# uatu

A weekly report on how your Claude setup is really used, proposing changes as pull requests with evidence.

**This one is for developers who keep their own harness repo.** It is built for its author's
setup. If you are not sure, skip it.

## What it helps with

uatu reads upstream Claude Code changes, how your skills and settings are actually used, and
whether your policy still matches your research notes. It comes back with at most seven
proposed changes, each with its evidence. Each change to `$UATU_HOME` becomes its own pull request
labelled `uatu`; anything else stays in the report. It never merges, and commits only its weekly
report to `$UATU_HOME/uatu/`.

## Example

> **You:** `/uatu`
>
> **Claude:** Digest written. Two recommendations this week:
> 1. Skill `deploy-notes` has not run in 41 days — retire it? Evidence: `history.tsv` rows 12–19.
> 2. Upstream added a hook event your policy does not mention. Opened a pull request for `policy.md:30`.

Merge the pull request to accept; close it with a reason to decline, and uatu will not propose
it again.

`/uatu <skill-dir>` checks one skill's craft instead and prints the result.

## uatu needs `UATU_HOME`

uatu keeps its history and reports in `$UATU_HOME/uatu/` and reads `$UATU_HOME/GLOSSARY.md`
and `$UATU_HOME/research/*.md`. Point `UATU_HOME` at the git repo holding them; without it,
uatu stops. To open pull requests, `$UATU_HOME` needs a GitHub `origin` and a `uatu` label;
without them it reports only. It is built for its author's own harness repo, so expect to adapt it.

Two more optional variables name logs uatu reads as channels, each an absolute path; unset,
the channel is skipped. `UATU_LESSONS` is a markdown file of `## ` entries; an entry is open
when it contains `**open**` or `**open, …**`. `UATU_PAPERCUTS` has one line per papercut,
`YYYY-MM-DD · symptom · fix · repo`.

## Install

[Follow the install steps on the index](../../README.md#install), then set `UATU_HOME` (above)
and type `/uatu` to start.

## Needs

`python3`, `jq`, `gh`, and macOS.

## What it runs

[`skills/uatu/SKILL.md`](skills/uatu/SKILL.md)
