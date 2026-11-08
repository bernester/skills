#!/bin/bash
# Doctor for uatu: reports the home, mode, tools and logs, and the changes a 0.1 install can make.
# Changes nothing without --apply. Never edits shell rc files, never creates the GitHub label.
# Usage: uatu-setup.sh [--apply local,copy]

set -uo pipefail

CLAUDE_DIR="$HOME/.claude"
HOME_FROM_ENV=${UATU_HOME:-}
UATU_HOME=${UATU_HOME:-$CLAUDE_DIR}
SKILL_DIR=$(cd "$(dirname "$0")/.." && pwd)
RC_FILES=("$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")

apply=
case ${1:-} in
  --apply) apply=",${2:?--apply takes local, copy or local,copy},"; ;;
  '') ;;
  *) echo "uatu-setup: unknown argument $1" >&2; exit 2 ;;
esac

same_dir() { [[ $(cd "$1" 2>/dev/null && pwd -P) == $(cd "$2" 2>/dev/null && pwd -P) ]]; }
rc_lines() { grep -n 'UATU_HOME' "${RC_FILES[@]}" 2>/dev/null | sed 's/^/        /'; }

# Closed, unmerged uatu PRs become decline lines once; the PR number marks one as imported.
import_declines() { # <repo dir> <declined.md>
  local rows n date title why added=0
  [[ -e $2 ]] || cp "$SKILL_DIR/templates/declined.md" "$2"
  if ! rows=$(cd "$1" && gh pr list --state closed --label uatu --limit 1000 \
      --json number,title,comments,mergedAt,closedAt --jq '.[] | select(.mergedAt == null)
        | [.number, .closedAt[:10], .title,
           (((.comments | last | .body) // "no reason given") | gsub("\\s+"; " "))] | @tsv'); then
    echo "fail    gh pr list failed — no declines imported"
    return 1
  fi
  while IFS=$'\t' read -r n date title why; do
    [[ -n $n ]] || continue
    grep -qF "(uatu PR #$n)" "$2" && continue
    printf -- '- %s · %s — %s (uatu PR #%s)\n' "$date" "$title" "$why" "$n" >> "$2"
    added=$((added + 1))
  done <<< "$rows"
  echo "done    imported $added closed uatu pull requests into $2"
}

# Never overwrites: a report already there stays, declines and history rows are merged.
copy_data() { # <from uatu/> <to uatu/>
  local f name
  mkdir -p "$2"
  for f in "$1"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*.md; do
    [[ -f $f ]] || continue
    name=${f##*/}
    if [[ -e $2/$name ]]; then echo "exists  $2/$name"; else cp -p "$f" "$2/" && echo "copied  $name"; fi
  done
  if [[ -f $1/declined.md ]]; then
    if [[ ! -e $2/declined.md ]]; then
      cp -p "$1/declined.md" "$2/" && echo "copied  declined.md"
    else
      grep '^- ' "$1/declined.md" | grep -vxF -f "$2/declined.md" >> "$2/declined.md"
      echo "merged  declined.md"
    fi
  fi
  if [[ -f $1/history.tsv ]]; then
    if [[ ! -e $2/history.tsv ]]; then
      cp -p "$1/history.tsv" "$2/" && echo "copied  history.tsv"
    else
      { head -n 1 "$2/history.tsv"
        tail -n +2 "$1/history.tsv"; tail -n +2 "$2/history.tsv"; } > "$2/history.tsv.new"
      { head -n 1 "$2/history.tsv.new"; tail -n +2 "$2/history.tsv.new" | sort -u | sort -s -t $'\t' -k2,2; } \
        > "$2/history.tsv" && rm "$2/history.tsv.new"
      echo "merged  history.tsv"
    fi
  fi
  echo "kept    $1 — nothing there was deleted"
}

# Writes through a symlinked settings.json instead of replacing the link.
set_local_mode() {
  local settings="$CLAUDE_DIR/settings.json" new
  [[ -e $settings ]] || echo '{}' > "$settings"
  new=$(jq '.env.UATU_MODE = "local"' "$settings") || { echo "fail    $settings is not valid JSON"; return 1; }
  printf '%s\n' "$new" > "$settings"
  echo "done    UATU_MODE=local in $settings (env)"
}

if [[ -n $apply ]]; then
  [[ -n $HOME_FROM_ENV ]] || { echo "uatu-setup: UATU_HOME is unset — nothing to migrate" >&2; exit 1; }
  target=$UATU_HOME
  if [[ $apply == *,copy,* ]]; then
    copy_data "$UATU_HOME/uatu" "$CLAUDE_DIR/uatu"
    target=$CLAUDE_DIR
  fi
  if [[ $apply == *,local,* ]]; then
    import_declines "$UATU_HOME" "$target/uatu/declined.md"
    set_local_mode
  fi
  if [[ $apply == *,copy,* ]]; then
    echo "todo    remove UATU_HOME from your shell profile so uatu reads ~/.claude:"
    rc_lines
  fi
  exit 0
fi

check() { # <what> <command> <todo>
  if eval "$2" > /dev/null 2>&1; then echo "ok      $1"; else echo "$4  $1 — $3"; fi
}

if [[ -n $HOME_FROM_ENV ]]; then echo "home    $UATU_HOME (from UATU_HOME)"; else echo "home    $UATU_HOME (default)"; fi
[[ -d $UATU_HOME ]] || echo "fail    $UATU_HOME does not exist"
IFS=$'\t' read -r mode mode_why < <("$SKILL_DIR/scripts/uatu-mode.sh" "$UATU_HOME")
if [[ $mode == pr ]]; then
  echo "mode    PR — pull requests to $mode_why"
else
  echo "mode    local — next step to PR mode: $mode_why"
fi
check python3 "command -v python3" "install python3" "fail  "
check jq "command -v jq" "install jq" "fail  "
check gh "command -v gh" "only PR mode needs it" "optional"
for v in UATU_LESSONS UATU_PAPERCUTS; do
  [[ -n ${!v:-} ]] && echo "ok      $v" || echo "optional  $v — unset"
done

[[ -n $HOME_FROM_ENV ]] || exit 0
echo
if same_dir "$UATU_HOME" "$CLAUDE_DIR"; then
  echo "note    UATU_HOME is ~/.claude, the default — remove it from your shell profile yourself:"
  rc_lines
fi
if [[ $mode == pr && ${UATU_MODE:-auto} == auto ]]; then
  echo "offer local  switch to local mode: imports each closed, unmerged uatu pull request into"
  echo "        uatu/declined.md once, and sets UATU_MODE=local in ~/.claude/settings.json."
  if open=$(cd "$UATU_HOME" && gh pr list --label uatu --json number,title,url --jq '.[] | "        #\(.number) \(.title) \(.url)"' 2>/dev/null) && [[ -n $open ]]; then
    echo "        Merge or close these open uatu pull requests first:"
    printf '%s\n' "$open"
  fi
fi
if ! same_dir "$UATU_HOME" "$CLAUDE_DIR" && [[ -d $UATU_HOME/uatu ]]; then
  echo "offer copy  copy declined.md, history.tsv and reports from $UATU_HOME/uatu into ~/.claude/uatu,"
  echo "        never overwriting and never deleting the old folder; then drop UATU_HOME."
fi
exit 0
