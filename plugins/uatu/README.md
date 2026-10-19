# uatu

A weekly report on how your Claude setup is really used, as proposed changes with evidence.

**This one is for developers who keep their own harness repo.** It is built for its author's
setup. If you are not sure, skip it.

## What it helps with

uatu reads upstream Claude Code changes, how your skills and settings are actually used, and
whether your policy still matches your research notes. It comes back with at most seven
proposed changes, each with its evidence and the exact edit. It never applies them, but it does commit its weekly report to
`$UATU_HOME/uatu/`.

## Example

> **You:** `/uatu`
>
> **Claude:** Digest written. Two recommendations this week:
> 1. Skill `deploy-notes` has not run in 41 days — retire it? Evidence: `history.tsv` rows 12–19.
> 2. Upstream added a hook event your policy does not mention. Proposed edit: `policy.md:30`.
>
> **You:** Skip the first, I still use it.
>
> **Claude:** Noted in `declined.md`.

`/uatu <skill-dir>` checks one skill's craft instead and prints the result.

## uatu needs `UATU_HOME`

uatu keeps its history and reports in `$UATU_HOME/uatu/` and reads `$UATU_HOME/GLOSSARY.md`
and `$UATU_HOME/research/*.md`. Point `UATU_HOME` at the git repo holding them; without it,
uatu stops. It is built for its author's own harness repo, so expect to adapt it.

## Install

[Follow the install steps on the index](../../README.md#install), then set `UATU_HOME` (above)
and type `/uatu` to start.

## Needs

`python3`, `jq`, and macOS.

## What it runs

[`skills/uatu/SKILL.md`](skills/uatu/SKILL.md)
