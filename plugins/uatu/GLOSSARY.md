# uatu glossary

**UATU home** — the folder uatu reads policy and research from and keeps its `uatu/` data in.
`~/.claude` unless `UATU_HOME` names another.

**Harness** — every repo `~/.claude` links into, the Claude Code runtime it runs on, and
upstream. A repo's own product work is outside it.

**Local mode** — the human answers each recommendation in the session that wrote the report.
uatu never commits in it.

**PR mode** — each recommendation that edits the home becomes a pull request labelled `uatu`.
Merging accepts it; closing it declines it.

**Recommendation** — one proposed change, with its evidence, its exact edit and why it earns its
cost. At most seven per report.

**Decline** — the human rejecting a recommendation, with a reason. A declined recommendation is
not proposed again unless new evidence overturns the reason.

**Defer** — the human leaving a recommendation unanswered. Nothing is recorded; it may come back.
