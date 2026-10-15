---
name: left
description: Lists what is still open in this session — asked-for work not done, uncommitted or unpushed changes, an unmerged branch or open MR — and says whether the session can be archived. Use when the user asks what is left, or before archiving a session.
disable-model-invocation: true
---

1. Git facts for the session's checkout: `git status --short`, commits ahead of the default
   branch and of the upstream, the MR/PR for the branch (`glab mr list --source-branch <b>` on
   GitLab, `gh pr list --head <b>` on GitHub). Name the branch's state with `/worktrees`'
   vocabulary; do not invent new states.
2. From this conversation, list each thing the user asked for that is not done, and each item
   you said you would follow up on.
3. If `~/.claude/bin/next-step` exists, run it from the session's directory; it prints one line
   or nothing.
4. Verdict first: **archive** or **not yet: <the one thing blocking it>**. Then step 3's line
   verbatim, if any. Then the open items, one line each. Nothing else.
