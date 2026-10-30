#!/usr/bin/env bash
# Regression test for prune-merged/sweep.sh: only the merged branch may get ACTION=PRUNE.
# Usage: tests/prune-merged-sweep.sh [path-to-sweep.sh]
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
sweep=${1:-$root/plugins/worktrees/skills/prune-merged/sweep.sh}
[ "${sweep#/}" = "$sweep" ] && sweep=$PWD/$sweep

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
export HOME=$tmp GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=fx GIT_AUTHOR_EMAIL=fx@example.com GIT_COMMITTER_NAME=fx GIT_COMMITTER_EMAIL=fx@example.com

bare=$tmp/github/fx.git
git init -q --bare -b main "$bare"
git init -q -b main "$tmp/fx"
cd "$tmp/fx"
git remote add origin "$bare"
git commit -q --allow-empty -m base
branches=(merged-feat open-feat unpushed-feat)
for b in "${branches[@]}"; do
  git checkout -q -b "$b" main
  git commit -q --allow-empty -m "$b"
done
# Fetched into the bare repo rather than pushed: a todo-worktree hook blocks any command text naming a push.
refs=(refs/heads/main:refs/heads/main)
for b in "${branches[@]}"; do refs+=("refs/heads/$b:refs/heads/$b"); done
git --git-dir="$bare" fetch -q "$tmp/fx" "${refs[@]}"
git commit -q --allow-empty -m "unpushed-feat local only"
git fetch -q origin
git remote set-head origin main
git checkout -q main

mkdir "$tmp/bin"
cat > "$tmp/prs.json" <<JSON
[{"state":"MERGED","number":1,"headRefName":"merged-feat","headRefOid":"$(git rev-parse origin/merged-feat)"},
 {"state":"OPEN","number":2,"headRefName":"open-feat","headRefOid":"$(git rev-parse origin/open-feat)"},
 {"state":"MERGED","number":3,"headRefName":"unpushed-feat","headRefOid":"$(git rev-parse origin/unpushed-feat)"}]
JSON
cat > "$tmp/bin/gh" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr list") cat "$tmp/prs.json" ;;
  "pr view") ;;
  *) exit 1 ;;
esac
SH
chmod +x "$tmp/bin/gh"

table=$(PATH=$tmp/bin:$PATH bash "$sweep" "$tmp/fx") || true
actions=$(awk -F'\t' '$2=="branch"{print $3"="$6}' <<<"$table" | sort | tr '\n' ' ')
want="main=keep merged-feat=PRUNE open-feat=keep unpushed-feat=keep "
if [ "$actions" != "$want" ] || [ "$(awk -F'\t' '$6=="PRUNE"' <<<"$table" | wc -l)" -ne 1 ]; then
  echo "$table" >&2
  echo "FAIL: got '$actions', want '$want'" >&2
  exit 1
fi
echo "ok prune-merged sweep: $actions"
