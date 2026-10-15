---
name: worktrees
description: One overview of every worktree, branch and leftover chat across the repos, each with one of seven states — finished, empty, live, ready, stranded, abandoned, orphaned — plus resume for the session behind a row and archive for an orphaned one. Use when the user asks what is going on across their worktrees or branches, what is merged, stranded, unpushed or abandoned, which chats can be archived, or wants to get back into the session that belongs to a worktree.
---

Nothing here deletes; that is `/prune-merged`'s job. The one write is `archive N`, and archiving
is reversible.

Vocabulary, used exactly:

- **Fate** — what the forge and git say became of a branch's commits: merged, open, closed or
  no MR, plus whether anything local is unique. Issued by the forge; ancestry never issues one,
  because squash merges hide merged commits. Not "verdict": that is a fate permitting deletion.
- **Pulse** — whether anyone still works a worktree: a running session, recent session
  activity, or an uncommitted change. Comes from the agent app, not from git.
- **Session** — the app's chat behind a worktree or repo, keyed by the directory it started
  in. Outlives the worktree.
- **State** — the one word a row shows, from Fate and Pulse; the seven are in the legend below.
  Not "status".
- **Resume** — reopen the Session belonging to a worktree. **Archive** — put an orphaned
  Session in the app's archived list; reversible, never a delete.

## 1. Sweep

Scope is the argument if the user gave a path, otherwise the parent directory of the current
repo, so every sibling clone is covered:

```sh
scope=$(dirname "$(cd "$(git rev-parse --git-common-dir)/.." && pwd)")
${CLAUDE_SKILL_DIR}/../prune-merged/sweep.sh "$scope"
```

It fetches every clone first; add `--no-fetch` only when the user asks for a quick look.
The TSV columns are `REPO KIND NAME VERDICT SAFETY ACTION STATE PULSE RESUME`; this skill reads
`STATE`, `PULSE`, `RESUME` and joins `VERDICT`+`SAFETY` into the Fate.

Then the sessions. Call `mcp__ccd_session_mgmt__list_sessions` with `limit` above the sidebar's
length (active only). Skip the tool when it is unavailable and say so under the table: the
overview then has no orphaned rows, not zero of them. A session is **orphaned** when it is not
running, its `cwd` is inside the scope, and either

- `cwd` no longer exists on disk, or
- `cwd` is a clone's main checkout, the session's `branch` is set,
  `git -C <cwd> rev-parse --verify -q refs/heads/<branch>` fails, **and** the worktree it names
  once existed — the app re-points a session at the root once its worktree is gone. Test the
  last part with the transcript directory the worktree would have had, since a preview or
  app-generated chat has a `branch` it never created:

  ```sh
  d=<cwd>/.claude/worktrees/<branch after the last "/">
  [ -d ~/.claude/projects/"$(echo "$d" | tr './' '--')" ] && echo orphaned
  ```

Every other session is already represented by a worktree row or is an ordinary repo-root chat.

## 2. Render

Group by `STATE`, most urgent first: **stranded → abandoned → ready → live → finished → empty
→ orphaned**. Within a group sort by `REPO`, then `NAME`. Number the rows continuously across
groups — the number is what `resume N` and `archive N` refer to.

Columns: `# REPO NAME SESSION STATE FATE PULSE RESUME`. `FATE` is `VERDICT` plus `SAFETY`
unless the latter is `-` or `clean` (`merged !52 ahead-of-PR`, `merged !52 ahead-of-PR dirty`,
`open !65`). `NAME` is the worktree path with its `[branch]`, or the bare branch for a branch
without a worktree; the main checkout appears as the branch it has checked out. An orphaned row
is a session, not a path: `REPO` from its `cwd`, `NAME` the gone path with `[branch]` (just
`[branch]` when only the branch is gone), `FATE` `-`, `PULSE` the hours since the app's last
activity, `RESUME` `-`.

`SESSION` is the app's `title` for the session whose `cwd` is the row's path (most recent
`lastActivityAt` if several). When the app has none but `RESUME` is set, the transcript has no
stored title — quote its first prompt instead, cut to 80 characters:

```sh
f=$(find ~/.claude/projects -name '<RESUME>.jsonl' | head -1)
jq -r 'select(.type=="user" and (.isMeta|not)) | .message.content
       | if type=="array" then map(select(.type=="text").text)|join(" ") else . end' "$f" \
  | sed -E 's/<[^>]+>//g' | grep -m1 . | cut -c1-80
```

A prompt that starts "This session is being continued" renders as `(continued session)`; the
current session as `(this session)`; no session at all as `-`.

Rows whose `STATE` is `-` are not table rows: an `api-down` repo row becomes one line under the
table ("no verdicts for `spark-pro` — origin is neither gitlab nor github"), a
`gone-from-disk` row one line saying stale worktree entries exist.

Drop a branch row whose `VERDICT` is `in-<its own NAME>` and `STATE` is `empty`: a clone parked
on its default branch with nothing unique. It cannot be pruned, resumed or archived, so it is
only length — a chat that once ran in the clone root does not change that. Count them for the
footer.

Legend, one line under the table, only for the states present:
stranded = MR merged or closed, but the local tip was never pushed to it — pruning loses work ·
abandoned = unique commits, no session for 14 days or none on record ·
ready = unique commits, no MR, quiet for under 14 days ·
live = MR open, session running, or worked in the last 24 h ·
finished = merged, nothing unique · empty = no MR, nothing unique ·
orphaned = chat whose worktree or branch is gone — `archive N` puts it in the app's archived list.

Footer: counts per state in the same order, then the dropped clones as
`+ 4 idle clones` when any were dropped, then — if any `finished` or `empty` row exists —
`/prune-merged` removes the finished and empty rows after a confirmation.

## 3. Resume N

Only rows with a path can be resumed. The sweep resolves each clone as `<scope>/<REPO>`, so
a worktree row's path is `<scope>/<REPO>/<NAME before " [">` and the main checkout's branch
row is `<scope>/<REPO>`; when the scope given was a single repo, use that path in place of
`<scope>/<REPO>`. Any other branch row has no worktree — say so; there is no session to resume.

`RESUME` is `-` → say no session is on record for that path and offer
`cd <path> && claude`. Otherwise:

1. `mcp__ccd_session_mgmt__list_sessions` (raise `limit` if the sidebar is long); pick the
   session whose `cwd` equals the path — the most recent `lastActivityAt` if several.
2. Found: tell the user this marks another session and prompts once in default mode, then
   `mcp__ccd_sidebar__set_unread` with that `session_id` and `unread: true`. Report the
   session's `title`: that is the entry now carrying the blue dot in the sidebar.
3. Not found: skip the dot and say the app has no session for that path.

Always print the fallback, whether or not the dot landed:

```sh
cd <path> && claude --resume <RESUME>
```

The app opens only sessions it started itself, so the dot plus the command is the whole
action; do not try `open_session_in` on someone else's session.

## 4. Archive N [N ...]

Only `orphaned` rows. Any other number is refused with that row's state — there is no override,
and archiving never widens into deleting a worktree or a session.

For each row call `mcp__ccd_session_mgmt__archive_session` with its `sessionId` and the reason
`orphaned — <cwd or branch> gone`. The app prompts once per session in default mode. Report per
row: archived, or the app's refusal as it came back (pinned, open on screen, still working) —
those stay in the sidebar and the user resolves them there.
