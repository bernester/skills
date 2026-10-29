---
name: uatu
description: "Reports how the harness is actually used, what changed upstream in Claude Code, and whether policy still matches research/*.md, as at most seven proposed changes, each with its evidence and the exact edit; an edit to `$UATU_HOME` is opened as a pull request, never merged. Use for the weekly harness report, `/uatu <skill-dir>` to check one skill's craft, or `/uatu setup` to create what uatu needs."
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/uatu-digest.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/uatu-setup.sh), Bash(git remote get-url *), Bash(git fetch *), Bash(git worktree add *), Bash(git worktree remove *), Bash(git add *), Bash(git commit *), Bash(git push -u origin uatu/*), Bash(gh label list *), Bash(gh pr create *), Bash(gh pr list *)
---

The observer. It reads upstream Claude Code changes, how the harness is really used, and
policy against the research, and comes back with recommendations the human can veto.

Work in `$UATU_HOME` on branch main; every `uatu/`, `research/` and policy
path below is relative to it.
If `UATU_HOME` is unset and the command is not `/uatu setup`, stop, say so and point to
`/uatu setup`: it names the repo that holds that data.
`UATU_LESSONS` and `UATU_PAPERCUTS` name two optional logs; unset, the digest says so and
that channel is skipped.

Two rules decide everything below:

- **Deterministic first, judgment second.** Counts come from the digest script, not from you.
  A recommendation with no number or `file:line` behind it does not ship.
- **It proposes as pull requests; it never merges, and never edits the `$UATU_HOME` main
  checkout** beyond its own `uatu/`. An edit lands only on a `uatu/*` branch in a throwaway
  worktree; nothing under `~/.claude`, no policy file and no skill changes in place.

Scope is **the harness**: every repo `~/.claude` links into, the runtime it runs on, and
upstream. A repo's own product work stays out.

The report, and every pull request title, body and commit message, goes to a public repo: it
names repos, skills and counts, and never quotes prompt text or paths and plugin keys from repos
outside the ones `~/.claude` links into.

`/uatu <skill-dir>` runs only the skill-craft check in [Policy](#policy) on that one skill,
inline, and prints its block. No digest, no report, no commit.

`/uatu setup` runs `${CLAUDE_SKILL_DIR}/scripts/uatu-setup.sh`, prints its output, and stops.

## 1. Digest

```sh
${CLAUDE_SKILL_DIR}/scripts/uatu-digest.sh
```

Writes `~/.cache/uatu/digest.md` and appends one row to `uatu/history.tsv`.
The cache sits outside the checkout so a run from a worktree still has last week's doc baselines.
Costs no tokens. Read the digest file; do not re-derive its numbers by hand.

If a section reads `fetch failed`, say so in the report and draw no upstream conclusion from
that page this run.

## 2. Read what already happened

- Declines — every recommendation the human rejected, with the reason: closed, unmerged pull
  requests labelled `uatu` (the last comment is the reason), and `uatu/declined.md`.
  **Never propose one of these again.** If new evidence genuinely overturns a decline, say
  which line it overturns and what changed; otherwise stay silent.
  ```sh
  gh pr list --state closed --label uatu --limit 1000 --json title,body,comments,mergedAt
  ```
  Keep the entries whose `mergedAt` is null.
- Open `uatu` pull requests (`gh pr list --label uatu`) and the last two reports in `uatu/` —
  an open recommendation is a follow-up line, not a fresh recommendation.
- `research/*.md` — the guidance every judgment is measured against. Each carries an ISO date
  in its first three lines; list any older than four weeks in the report and point to
  `/research` to refresh it.
- `uatu/history.tsv` — three rows or more make a trend; fewer make a number. Rows before
  schema 4 count one product's setup, not every linked repo.
- `uatu/sources.md` — which sections of a dropped issue count as tips, and why the
  source is trusted. Read nothing from an issue that this file does not name; a source
  with no `section:` line is read whole.

Pull requests need a GitHub origin for `$UATU_HOME` (`git remote get-url origin`); with any
other origin, skip the `gh` calls and keep every recommendation report-only. On GitHub, check the
label exists:

```sh
gh label list --search uatu --json name
```

If no `uatu` label comes back, keep every recommendation report-only this run, and say in one
line of the report that the label needs creating. Never create it.

Convert every inbox file the digest marks **to convert** before judging: a `.pdf` with Read, a
`.url` (one URL per file) with WebFetch, each into the `.md` the digest names. Then judge it as
**new**.

## 3. Judge

Coverage is **reported, not asserted**. The transcript store spans two dozen CLI
versions and two spellings of `sessionId`; a field missing from some records is a fact for
the report, not a failure. No threshold fires until three rows of history exist.

Eight channels, in this order:

**Behaviour.** Prompts typed three times or more → a skill candidate. A correction count
that jumps → name the prompts. A tool-error signature with a double-digit count → the fix is
usually one line in a skill or one allow rule, and the signature says which.

**Setup hygiene.** An authored skill with no invocation in the window — propose deleting it
or say why it is a keeper. The `### skill-doctor` block is the listing-cost verdict: a
never-invoked skill with listing context is a deletion candidate the same way. Its
synced-from-claude.ai summary line is report-only — a deleted copy re-downloads; the fix is
disabling it on claude.ai. uatu's own counts stay the source for authored skills.
`skill-doctor failed` means no verdict this run. A `verify.sh` reading **DRIFT** whose output
names a detached link is **urgent**: the CLI has replaced a symlinked file and live config has
silently stopped being tracked. The recovery is that repo's own installer — name it from the failing
`verify.sh` output, which says what to run. `~/.claude` reading **DRIFT** under `git status` is
a CLI save or a hand edit — commit or revert it (ADR 0015); not urgent. A `T` entry is
a detached link: urgent, as above.

**Upstream.** Releases newer than the installed CLI, and changed doc pages. The bar is
narrow: does it change a finding in `research/*.md`? A new hook event, a new skill
frontmatter field, a scheduling feature that reaches `~/.claude`, a model ID a skill names
that no longer exists — take the IDs from the digest's "Model IDs named" list and check them
against the current IDs in the `claude-api` skill (load it with the Skill tool); never infer
current IDs from the changelog or docs. If `claude-api` does not load, say so and draw no
model-ID conclusion. "47 releases happened" is not a recommendation. A changed page with a
`Cited by:` line meets the bar as "refresh `research/<f>.md`", ranked above a note that is
only old.

**Retention.** `cleanupPeriodDays` and the oldest surviving transcript. The history file is
what makes the trend outlive the sweep; if a column has gone flat because data expired,
say that rather than reading it as a change in behaviour.

**Sources.** Every issue the digest marks **new** under *Sources*. A tip becomes a
recommendation only when it maps to one concrete edit in a linked repo — a `file:line` and a
diff; the tip itself is quoted as evidence with its `inbox/<issue>.md:<line>`. Rank tips by
corroboration: a tip that names a signature already in the Behaviour or Setup-hygiene
numbers outranks one that stands alone. A tip about a runtime feature is Upstream and meets
that bar, not this one. A source under `## Pointers` in `sources.md` is a lead to check, never
evidence. Everything else goes under **Noted** in the report, once; the issue is never
re-read, so a noted tip is never raised again.

**Lessons.** Each open entry the digest lists under *Logs* maps to one edit in the skill or
script it names — a `file:line` and a diff. Cite the entry as `<file>:<line>` and never quote
it. An entry that maps to no edit is not raised.

**Papercuts.** Read the log the digest names. A symptom logged twice or more, however
worded, or whose fix is a workaround, becomes a recommendation naming the tool, config or
skill to change. Cite entries by line and never quote them: they name repos outside the
linked ones.

**Policy.** See the next section. Its findings become recommendations like any other.

## Policy

The axis the drift checks cannot see: they check a machine, this checks policy
against the guidance in `research/*.md`.

Run the sweep only when `research/` or a policy file changed since the last report:

```sh
git log --oneline --since="<last report's date>" -- research <the targets listed below>
```

Empty output: the report's Policy section is one line, `unchanged since <date>`. Otherwise
run the sweep in one `fable` subagent that reads every target below, so it can see where two
targets disagree (a rule in `CLAUDE.md` that the output style undoes). Findings come back with
`file:line`.

- `CLAUDE.md`
- `output-styles/*.md`
- `agents/*.md`
- `settings.json`
- `skills.txt`
- every authored skill (Skill-craft below)

Every finding cites `research/<file>.md:<line>`. If no `research/` file bears on a topic,
stay silent on it — do not reason from your own knowledge of what Anthropic recommends.
**Skip claims the research file marks unverified** — anything under an "Unverified / could
not confirm" heading, or hedged inline. Do not report them, do not list them.

### Currency — a config artifact against guidance

Walk the `research/*.md` sections that bear on the artifact. Classify each bearing
recommendation:

- **contradiction** — the artifact does the opposite of the guidance. Reported first.
- **gap** — the guidance covers a topic the artifact is silent on.
- match, or deliberate divergence — not reported. `research/anthropic-best-practices.md`
  has a "Divergences worth noticing" section listing known deliberate calls; check it
  before reporting, and drop any finding that only restates one.

### Skill-craft — a skill authored here against Agent Skills guidance

Only for authored skills — live `~/.claude/skills` links into a git repo — or the
`/uatu <skill-dir>` target. Source:
`research/anthropic-best-practices.md` §3.

Mechanical — run these, do not just describe them:

- opening `---` is line 1, frontmatter parses
- `name`: ≤ 64 chars, lowercase / digits / hyphens only, no "anthropic" or "claude"
- `description`: non-empty, ≤ 1024 chars, states both what it does and when to use it
- `SKILL.md` body under 500 lines
- file references exactly one level deep from `SKILL.md`
- no exec bit on bundled files that are not scripts

Judgement:

- description is third person with concrete trigger terms
- body is standing instructions, not one-time steps — it is sticky across turns once loaded
- one default with an escape hatch, not a menu of options
- one term per concept, used consistently

The sweep's block in the report leads with contradictions and prints every class header even
when empty (`none`):

```
contradictions
  <artifact>:<line>  "<quoted phrase>"
    research/<file>.md:<line> — the guidance it contradicts, in a sentence or two.

gaps
  <artifact>  — <topic the guidance covers, cited to research/<file>.md:<line>>

skill-craft  skills/<name>
  mechanical: pass
  judgement: none
```

## 4. Write the report

`uatu/YYYY-MM-DD.md`. **At most seven recommendations**, most valuable first. Fewer
is better, and none is a legitimate answer — a report that says "nothing to do" and shows the
counts behind it did its job.

Each recommendation carries three things, and is dropped if it cannot:

~~~markdown
### 1. Drop `/rubberduck` — unused for 30 days

**Evidence.** `~/.cache/uatu/digest.md` *Setup usage*: no invocation in the window;
`~/.claude/skills/rubberduck` still links it; last typed 2026-08-02 (`history.jsonl`).

**Edit.**

```sh
rm ~/.claude/skills/rubberduck
```

**Why it earns its cost.** Every installed skill is a name the human has to remember. This
one has not paid for its slot in a month.
~~~

Then the closing sections:

- **Policy** — the sweep's block, or its one line.
- **Research freshness** — each `research/*.md` date and age.
- **Follow-ups** — recommendations from earlier reports that are neither done nor declined.
- **Noted** — tips from this run's new issues that map to no edit, one line each with
  the `inbox/<issue>.md:<line>` they came from; then the digest's new pages since last run,
  one line each. These are leads, never recommendations.
- **Counts** — the history table's last rows, so a reader sees the trend without the digest.
- **Not looked at** — anything the digest could not reach this run.

Keep it short. A recommendation is a paragraph and a diff, not an essay.

A recommendation whose diff edits a file in `$UATU_HOME` becomes one pull request. From
`$UATU_HOME`:

```sh
git fetch origin
git worktree add -b uatu/<report-stem>-<n>-<slug> <tmp> origin/main
```

`<report-stem>` is the report's file name without `.md`, so a same-day rerun cannot collide.
Then `cd <tmp>` as its own call, make the recommendation's edit there with the Edit tool, and
write the commit message and the PR body (Evidence and Why) to files in `<tmp>` with the Write
tool — model prose never goes inside shell quotes. The title is single-quoted:

```sh
git add <its files>
git commit -F <message file>
git push -u origin uatu/<report-stem>-<n>-<slug>
gh pr create --label uatu --title '<the recommendation's title>' --body-file <body file>
```

Then `cd "$UATU_HOME"` and `git worktree remove <tmp>`. If any step fails, remove the worktree
and keep the recommendation report-only. In the report, a recommendation opened as a pull request
is one line with its URL. A diff into another repo, or a manual action, stays in full.

## 5. Hand over

```sh
cd $UATU_HOME && git add uatu && git commit -m "uatu(<date>): <the one-line verdict>" -- uatu
```

Commit the report, `history.tsv`, `declined.md` and the converted `inbox/*.md` only. The
cache under `~/.cache/uatu/` is regenerable and never enters the repo.

If any recommendation is marked **urgent** (only a detached link is urgent), fire one
notification:

```sh
osascript -e 'display notification "<what broke>" with title "uatu"'
```

Never push main; only `uatu/*` branches are pushed, and they branch from `origin/main`, so local
commits on main never reach a pull request. Print the report's headline, the count of
recommendations and each pull request's URL, then stop.

## 6. When the human answers

A pull request is accepted by merging it, and rejected by closing it with a comment that gives
the reason. A rejected report-only recommendation gets one line in `uatu/declined.md`:

```
- 2026-09-08 · drop /rubberduck — used in bursts; a quiet month is not a dead skill.
```

The reason is the part that matters: it is what stops the next run from re-proposing. An
accepted report-only recommendation needs no bookkeeping — the edit lands as a normal commit,
and the next digest shows it.
