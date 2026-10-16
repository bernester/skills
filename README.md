# bernester/skills

Claude Code skills by Bernhard Ruoff, as a plugin marketplace.

| Plugin | Skills | What for |
|---|---|---|
| [`rubberduck`](plugins/rubberduck/README.md) | `/rubberduck` | Talk an idea through; it asks about what you said and hands back the gaps. |
| [`uatu`](plugins/uatu/README.md) | `/uatu` | Weekly report on how your harness is used, as proposed changes with evidence. |
| [`worktrees`](plugins/worktrees/README.md) | `/worktrees`, `/prune-merged`, `/agents-clean`, `/left` | Keep worktrees, branches and Claude sessions tidy. |

## Install

In the Claude desktop app:

1. Open **Customize**, then **Plugins**.
2. Choose **Add marketplace** and type `bernester/skills`.
3. Find the plugin you want and choose **Install**.
4. Start a new chat and type the plugin's command, for example `/rubberduck`.

## From the terminal

```
/plugin marketplace add bernester/skills
/plugin install worktrees@bernester
```

Swap `worktrees` for `rubberduck` or `uatu` as you like.

`worktrees` needs `jq` and `gh` or `glab`; `uatu` needs `python3`.

## uatu needs `UATU_HOME`

See [uatu's README](plugins/uatu/README.md#uatu-needs-uatu_home).

## Editing the skills

The plugin cache is a copy, so edits to a clone don't reach it. To work on the skills, link
them from your clone instead of installing the plugins:

```sh
for d in plugins/*/skills/*; do ln -sfn "$PWD/$d" ~/.claude/skills/"${d##*/}"; done
```

## License

MIT
