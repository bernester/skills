#!/usr/bin/env bash
# Read-only audit of worktree locks and Claude background sessions, sockets and task lists.
# Prints one tab-separated table, deletes nothing. Usage: digest.sh [repo-path ...]
set -uo pipefail

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

row() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$OUT"; }

repos=()
if [ $# -gt 0 ]; then
  for p in "$@"; do repos+=("${p/#\~/$HOME}"); done
else
  top=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "digest.sh: not in a git repo; pass repo paths" >&2; exit 1; }
  scope=$(dirname "$(cd "$top/.." && pwd)")
  for d in "$scope"/*/; do
    d="${d%/}"
    git -C "$d" rev-parse --show-toplevel >/dev/null 2>&1 || continue
    repos+=("$d")
  done
fi

now_epoch=$(date +%s)

default_branch() {
  local repo=$1 d
  d=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  if [ -z "$d" ]; then
    if git -C "$repo" rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1; then d=main; else d=master; fi
  fi
  printf '%s' "$d"
}

is_contained() { # is_contained <repo> <branch> <default>
  local repo=$1 branch=$2 default=$3
  if git -C "$repo" rev-parse --verify --quiet "origin/$default" >/dev/null 2>&1; then
    git -C "$repo" merge-base --is-ancestor "$branch" "origin/$default" 2>/dev/null
  else
    git -C "$repo" merge-base --is-ancestor "$branch" "$default" 2>/dev/null
  fi
}

# ============================================================
# locks: every repo's worktree admin locks
# ============================================================

for repo in "${repos[@]}"; do
  repo_name=$(basename "$repo")
  default=$(default_branch "$repo")
  for lockfile in "$repo"/.git/worktrees/*/locked; do
    [ -f "$lockfile" ] || continue
    wtdir=$(dirname "$lockfile")
    wtname=$(basename "$wtdir")
    locktext=$(cat "$lockfile" 2>/dev/null)
    pid=$(printf '%s' "$locktext" | grep -oE 'pid [0-9]+' | grep -oE '[0-9]+' | head -1)
    alive=no
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive=yes

    owner="-"; jobstate="-"
    if [ -n "$pid" ] && [ -f ~/.claude/sessions/"$pid".json ]; then
      owner=$(jq -r '.name // "-"' ~/.claude/sessions/"$pid".json 2>/dev/null)
      jobid=$(jq -r '.jobId // empty' ~/.claude/sessions/"$pid".json 2>/dev/null)
      if [ -n "$jobid" ] && [ -f ~/.claude/jobs/"$jobid"/state.json ]; then
        jobstate=$(jq -r '.state // "-"' ~/.claude/jobs/"$jobid"/state.json 2>/dev/null)
      fi
    fi

    wtbranch=$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk -v p="$wtdir" '
      /^worktree /{cur=substr($0,10)} /^branch /{ if (cur==p) print substr($0,8) }' | sed 's#^refs/heads/##')

    contained=no
    if [ -n "$wtbranch" ] && is_contained "$repo" "$wtbranch" "$default"; then contained=yes; fi

    class=report
    if [ "$alive" = no ] || { [ "$jobstate" = done ] && [ "$contained" = yes ]; }; then class=unlock; fi

    evidence="owner=$owner pid=$pid alive=$alive job=$jobstate contained=$contained"
    row "$repo_name" lock "$wtname" locked "$evidence" "$class"
  done
done

# ============================================================
# agents: claude agents --json
# ============================================================

if ! agents_json=$(claude agents --json 2>/dev/null) || [ -z "$agents_json" ]; then
  row agents - "claude agents unavailable" - - report
else
  now_ms=$((now_epoch * 1000))

  while IFS= read -r a; do
    [ -z "$a" ] && continue
    id=$(jq -r '.id // empty' <<< "$a")
    name=$(jq -r '.name // "-"' <<< "$a")
    status=$(jq -r '.status // "-"' <<< "$a")
    cwd=$(jq -r '.cwd // "-"' <<< "$a")
    startedAt=$(jq -r '.startedAt // 0' <<< "$a")

    jobfile=~/.claude/jobs/"$id"/state.json
    state="-"; needs=""; detail=""
    if [ -f "$jobfile" ]; then
      state=$(jq -r '.state // "-"' "$jobfile" 2>/dev/null)
      needs=$(jq -r '.needs // ""' "$jobfile" 2>/dev/null)
      detail=$(jq -r '.detail // ""' "$jobfile" 2>/dev/null)
    fi
    age_h=$(( (now_ms - startedAt) / 3600000 ))
    needs_trunc=$(printf '%s' "$needs" | cut -c1-60)

    class=report
    case "$state" in done|blocked) class=stop ;; esac

    row agents background "$name [$id]" "$status/$state" "cwd=$cwd age=${age_h}h needs=$needs_trunc" "$class"
  done < <(jq -c '.[] | select(.kind=="background")' <<< "$agents_json")

  while IFS= read -r a; do
    [ -z "$a" ] && continue
    name=$(jq -r '.name // "-"' <<< "$a")
    cwd=$(jq -r '.cwd // "-"' <<< "$a")
    evidence="cwd=$cwd"
    case "$cwd" in "$PWD") evidence="$evidence (this session)" ;; esac
    row agents interactive "$name" "-" "$evidence" report
  done < <(jq -c '.[] | select(.kind=="interactive")' <<< "$agents_json")
fi

# ============================================================
# agents: dead sockets
# ============================================================

for f in /tmp/cc-socks/*.sock; do
  [ -e "$f" ] || continue
  pid=$(basename "$f" .sock)
  if ! kill -0 "$pid" 2>/dev/null; then
    row agents socket "$pid" dead "path=$f" rm-socket
  fi
done

# ============================================================
# agents: stale in-session task lists
# ============================================================

thirty_days=$((30 * 86400))
for d in ~/.claude/tasks/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"
  tid=$(basename "$d")
  mtime=$(stat -f %m "$d" 2>/dev/null)
  [ -z "$mtime" ] && continue
  age=$((now_epoch - mtime))
  pending=0
  for j in "$d"/*.json; do
    [ -f "$j" ] || continue
    st=$(jq -r '.status // "unknown"' "$j" 2>/dev/null)
    [ "$st" != completed ] && pending=$((pending + 1))
  done
  if [ "$pending" -gt 0 ] || [ "$age" -gt "$thirty_days" ]; then
    mdate=$(date -j -f %s "$mtime" +%Y-%m-%d 2>/dev/null)
    row agents tasklist "$tid" stale "pending=$pending mtime=$mdate" report
  fi
done

# ============================================================
# agents: scheduled tasks / daemon workers — report only when non-empty
# ============================================================

if [ -d ~/.claude/scheduled-tasks ] && [ -n "$(ls -A ~/.claude/scheduled-tasks 2>/dev/null)" ]; then
  count=$(ls ~/.claude/scheduled-tasks 2>/dev/null | wc -l | tr -d ' ')
  row agents scheduled-tasks - nonempty "count=$count" report
fi

if [ -f ~/.claude/daemon.status.json ]; then
  workers=$(jq -r '.workers | length' ~/.claude/daemon.status.json 2>/dev/null)
  if [ -n "$workers" ] && [ "$workers" != 0 ] && [ "$workers" != null ]; then
    row agents daemon-workers - "workers=$workers" - report
  fi
fi

# ============================================================
# print: header, rows, summary
# ============================================================

printf 'STORE\tKIND\tNAME\tSTATE\tEVIDENCE\tCLASS\n'
cat "$OUT"

summary=$(awk -F'\t' '{c[$6]++} END{for (k in c) printf "%s=%s ", k, c[k]}' "$OUT" | sed 's/ *$//')
[ -z "$summary" ] && summary="-"
printf 'SUMMARY\t-\t-\t-\t%s\t-\n' "$summary"

exit 0
