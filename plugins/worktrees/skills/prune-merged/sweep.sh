#!/usr/bin/env bash
# Read-only survey of worktrees and branches. Asks the forge for every verdict, plus one MR commit
# list per merged branch that git alone cannot place. Deletes nothing.
# Usage: sweep.sh [--no-fetch] [repo-or-parent-dir ...]   (default: current repo)
set -uo pipefail

LIVE_H=24
ABANDONED_D=14

fetch=1
targets=()
for a in "$@"; do
  case "$a" in
    --no-fetch) fetch=0 ;;
    *) targets+=("$a") ;;
  esac
done
[ ${#targets[@]} -eq 0 ] && targets=(.)

# A linked worktree resolves to its main worktree, so a repo's worktrees are listed once.
repos=()
add_repo() {
  local main r
  main=$(git -C "$1" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  [ -n "$main" ] || return 1
  for r in ${repos[@]+"${repos[@]}"}; do [ "$r" = "$main" ] && return 0; done
  repos+=("$main")
}
for t in "${targets[@]}"; do
  t="${t%/}"
  if git -C "$t" rev-parse --show-toplevel >/dev/null 2>&1; then
    add_repo "$t"
  else
    for d in "$t"/*/; do add_repo "$d"; done
  fi
done

newest_transcript() {
  local dir="$HOME/.claude/projects/$(printf '%s' "$1" | tr '/.' '--')"
  ls -t "$dir"/*.jsonl 2>/dev/null | head -1
}

pulse_of() { # path [excluded-subpath ...] -> running | <N>h | -
  local path=$1 f cwd pid x skip t mtime; shift
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -f "$f" ] || continue
    IFS=$'\t' read -r cwd pid < <(jq -r '[.cwd // "", (.pid // "" | tostring)] | @tsv' "$f" 2>/dev/null)
    case "$cwd" in "$path"|"$path"/*) ;; *) continue ;; esac
    skip=0
    if [ $# -gt 0 ]; then for x in "$@"; do case "$cwd" in "$x"|"$x"/*) skip=1 ;; esac; done; fi
    [ $skip -eq 1 ] && continue
    [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && { echo running; return; }
  done
  t=$(newest_transcript "$path")
  [ -z "$t" ] && { echo -; return; }
  mtime=$(stat -c %Y "$t" 2>/dev/null || stat -f %m "$t" 2>/dev/null)
  [ -z "$mtime" ] && { echo -; return; }
  echo "$(( ($(date +%s) - mtime) / 3600 ))h"
}

resume_of() {
  local t
  t=$(newest_transcript "$1")
  [ -z "$t" ] && { echo -; return; }
  basename "$t" .jsonl
}

row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"; }
row REPO KIND NAME VERDICT SAFETY ACTION STATE PULSE RESUME

for repo in ${repos[@]+"${repos[@]}"}; do
  name=$(basename "$repo")
  git -C "$repo" rev-parse --verify --quiet HEAD >/dev/null 2>&1 || continue
  [ $fetch -eq 1 ] && git -C "$repo" fetch --prune --quiet 2>/dev/null

  default=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  [ -z "$default" ] && default=$(git -C "$repo" rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1 && echo main || echo master)

  # --- forge detection ---
  origin=$(git -C "$repo" remote get-url origin 2>/dev/null)
  case "$origin" in
    *gitlab*) host=gitlab; cli=glab; marker='!' ;;
    *github*) host=github; cli=gh;   marker='#' ;;
    *)        host=unknown; cli='';  marker='!' ;;
  esac

  # Normalise both forges to [{state,iid,sha,branch}]. Non-zero return = no verdicts available.
  query() { # $1 = extra args ("" for all, or --source-branch/--head <b>)
    local out
    case $host in
      gitlab)
        out=$(cd "$repo" && glab mr list --all $1 --per-page 100 -F json 2>/dev/null) || return 1
        printf '%s' "$out" | jq -e '[.[]|{state:(.state|sub("^opened$";"open")),iid:.iid,sha:.sha,branch:.source_branch}]' 2>/dev/null ;;
      github)
        out=$(cd "$repo" && gh pr list --state all $1 --limit 100 --json state,number,headRefName,headRefOid 2>/dev/null) || return 1
        printf '%s' "$out" | jq -e '[.[]|{state:(.state|ascii_downcase),iid:.number,sha:.headRefOid,branch:.headRefName}]' 2>/dev/null ;;
      *) return 1 ;;
    esac
  }

  api=up; why=''
  if [ -z "$origin" ]; then
    api=down; why="no origin remote"
  elif [ "$host" = unknown ]; then
    api=down; why="origin is neither gitlab nor github"
  elif ! command -v "$cli" >/dev/null 2>&1; then
    api=down; why="$cli not installed"
  elif ! prs=$(query ""); then
    api=down; why="$cli returned no usable JSON — auth?"
  fi
  [ "$api" = down ] && { prs='[]'; row "$name" repo "($host)" "api-down" "$why" "verdicts-unavailable" - - -; }

  verdict_of() { # branch -> "state|iid|sha", empty when unknown
    [ "$api" = down ] && return
    local b=$1 hit flag
    hit=$(printf '%s' "$prs" | jq -r --arg b "$b" '[.[]|select(.branch==$b)]|sort_by(.iid)|last // empty|"\(.state)|\(.iid)|\(.sha)"')
    if [ -z "$hit" ]; then
      [ "$host" = gitlab ] && flag="--source-branch $b" || flag="--head $b"
      hit=$(query "$flag" | jq -r 'sort_by(.iid)|last // empty|"\(.state)|\(.iid)|\(.sha)"' 2>/dev/null)
    fi
    printf '%s' "$hit"
  }

  pr_commits() { # iid -> one merged commit sha per line, empty when unknown
    if [ "$host" = gitlab ]; then
      (cd "$repo" && glab api --paginate "projects/:id/merge_requests/$1/commits?per_page=100" 2>/dev/null | jq -r '.[].id' 2>/dev/null)
    else
      (cd "$repo" && gh pr view "$1" --json commits --jq '.commits[].oid' 2>/dev/null)
    fi
  }

  none_verdict() { [ "$api" = down ] && echo "no-api" || echo "no-mr"; }

  fate_of() { # branch [tip] -> "verdict<TAB>safety"
    local b=$1 tip=${2:-} v state iid prsha
    v=$(verdict_of "$b")
    if [ -z "$v" ]; then
      if git -C "$repo" merge-base --is-ancestor "$b" "origin/$default" 2>/dev/null; then
        printf '%s in-%s\tno-unique-commits\n' "$(none_verdict)" "$default"
      else
        printf '%s\t-\n' "$(none_verdict)"
      fi
      return
    fi
    state=${v%%|*}; iid=$(printf '%s' "$v"|cut -d'|' -f2); prsha=$(printf '%s' "$v"|cut -d'|' -f3)
    [ -z "$tip" ] && tip=$(git -C "$repo" rev-parse "$b" 2>/dev/null)
    if [ "$state" != merged ] && [ "$state" != closed ]; then
      printf '%s %s%s\t-\n' "$state" "$marker" "$iid"
    elif [ "$tip" = "$prsha" ]; then
      printf '%s %s%s\ttip=PR\n' "$state" "$marker" "$iid"
    elif git -C "$repo" rev-parse --verify --quiet "$prsha^{commit}" >/dev/null 2>&1 \
      && git -C "$repo" merge-base --is-ancestor "$tip" "$prsha" 2>/dev/null; then
      printf '%s %s%s\tbehind-PR\n' "$state" "$marker" "$iid"
    elif git -C "$repo" merge-base --is-ancestor "$tip" "origin/$default" 2>/dev/null; then
      printf '%s %s%s\tbehind-PR\n' "$state" "$marker" "$iid"
    elif [ "$state" = merged ] && grep -qxF -- "$tip" <<<"$(pr_commits "$iid")"; then
      printf '%s %s%s\tbehind-PR\n' "$state" "$marker" "$iid"
    else
      printf '%s %s%s\tahead-of-PR\n' "$state" "$marker" "$iid"
    fi
  }

  action_of() { # verdict fate-safety clean|dirty -> PRUNE|keep
    case "$1:$2:$3" in
      merged*:tip=PR:clean|merged*:behind-PR:clean|*"in-$default":*:clean) echo PRUNE ;;
      *) echo keep ;;
    esac
  }

  state_of() { # verdict safety pulse -> live|finished|empty|stranded|ready|abandoned
    local verdict=$1 safety=$2 pulse=$3 h
    case "$pulse:$safety" in running:*|*:dirty) echo live; return ;; esac
    case "$verdict:$safety" in merged*:tip=PR|merged*:behind-PR) echo finished; return ;; esac
    case "$verdict" in *"in-$default") echo empty; return ;; open*) echo live; return ;; esac
    case "$verdict:$safety" in merged*:ahead-of-PR|closed*:ahead-of-PR) echo stranded; return ;; esac
    case "$pulse" in
      -) echo abandoned ;;
      *) h=${pulse%h}
         if [ "$h" -lt "$LIVE_H" ]; then echo live
         elif [ "$h" -ge $((ABANDONED_D * 24)) ]; then echo abandoned
         else echo ready; fi ;;
    esac
  }

  # --- secondary worktrees ---
  wt_branches=""; wt_paths=(); wt_path=""; wt_branch=""; wt_head=""; first=1
  flush_wt() {
    [ -z "$wt_path" ] && return
    if [ $first -eq 1 ]; then first=0; wt_path=""; wt_branch=""; wt_head=""; return; fi
    local label safety verdict fsafety action rel f pulse resume st_safety state
    wt_paths+=("$wt_path")
    rel=${wt_path#"$repo"/}
    safety=$( [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ] && echo dirty || echo clean )
    if [ -n "$wt_branch" ]; then
      wt_branches="$wt_branches $wt_branch"
      f=$(fate_of "$wt_branch" "$(git -C "$wt_path" rev-parse HEAD 2>/dev/null)")
      verdict=${f%%$'\t'*}; fsafety=${f##*$'\t'}
      label="$rel [$wt_branch]"
    else
      verdict="detached"; fsafety="-"
      git -C "$repo" merge-base --is-ancestor "$wt_head" "origin/$default" 2>/dev/null && verdict="detached in-$default"
      label="$rel [detached ${wt_head:0:8}]"
    fi
    action=$(action_of "$verdict" "$fsafety" "$safety")
    pulse=$(pulse_of "$wt_path"); resume=$(resume_of "$wt_path")
    [ "$safety" = dirty ] && st_safety=dirty || st_safety=$fsafety
    state=$(state_of "$verdict" "$st_safety" "$pulse")
    [ "$fsafety" != - ] && verdict="$verdict $fsafety"
    row "$name" worktree "$label" "$verdict" "$safety" "$action" "$state" "$pulse" "$resume"
    wt_path=""; wt_branch=""; wt_head=""
  }
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) flush_wt; wt_path=${line#worktree } ;;
      branch\ *)   wt_branch=$(printf '%s' "${line#branch }" | sed 's#^refs/heads/##') ;;
      HEAD\ *)     wt_head=${line#HEAD } ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null)
  flush_wt

  [ -n "$(git -C "$repo" worktree prune --dry-run 2>/dev/null)" ] && \
    row "$name" worktree "(stale admin entries)" "gone-from-disk" "-" PRUNE - - -

  # --- local branches; the checked-out one is the main checkout's row and is never PRUNE ---
  current=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
  while IFS= read -r b; do
    case " $wt_branches " in *" $b "*) continue ;; esac
    if [ "$b" = "$current" ]; then
      pulse=$(pulse_of "$repo" ${wt_paths[@]+"${wt_paths[@]}"}); resume=$(resume_of "$repo")
    elif [ "$b" = "$default" ]; then
      continue
    else
      pulse=-; resume=-
    fi
    if [ "$b" = "$default" ]; then
      verdict="in-$default"; fsafety=-; action=keep
    else
      f=$(fate_of "$b"); verdict=${f%%$'\t'*}; fsafety=${f##*$'\t'}
      action=$(action_of "$verdict" "$fsafety" clean)
      [ "$b" = "$current" ] && action=keep
    fi
    row "$name" branch "$b" "$verdict" "$fsafety" "$action" \
      "$(state_of "$verdict" "$fsafety" "$pulse")" "$pulse" "$resume"
  done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
done
