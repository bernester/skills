# bernester/skills

Claude Code skills by Bernhard Ruoff, as a plugin marketplace.

| Plugin | Skills | What for |
|---|---|---|
| `rubberduck` | `/rubberduck` | Talk an idea through; it asks about what you said and hands back the gaps. |
| `uatu` | `/uatu` | Weekly report on how your harness is used, as proposed changes with evidence. |
| `worktrees` | `/worktrees`, `/prune-merged`, `/agents-clean`, `/left` | Keep worktrees, branches and Claude sessions tidy. |

## Install

```
/plugin marketplace add bernester/skills
/plugin install worktrees@bernester
```

Swap `worktrees` for `rubberduck` or `uatu` as you like.

`worktrees` needs `jq` and `gh` or `glab`; `uatu` needs `python3`.

## uatu needs `UATU_HOME`

uatu keeps its history and reports in `$UATU_HOME/uatu/` and reads `$UATU_HOME/GLOSSARY.md`
and `$UATU_HOME/research/*.md`. Point `UATU_HOME` at the git repo holding them; without it,
uatu stops. It is built for its author's own harness repo, so expect to adapt it.

## Editing the skills

The plugin cache is a copy, so edits to a clone don't reach it. To work on the skills, link
them from your clone instead of installing the plugins:

```sh
for d in plugins/*/skills/*; do ln -sfn "$PWD/$d" ~/.claude/skills/"${d##*/}"; done
```

## License

MIT
