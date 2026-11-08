#!/bin/bash
# Prints this run's mode, a tab, and why: "pr<TAB><origin>" or "local<TAB><the one step to PR mode>".
# UATU_MODE=local|pr overrides the pick; pr skips the checks, and a failing gh call later drops to local.
# Usage: uatu-mode.sh [<uatu home>]

set -uo pipefail

dir=${1:-${UATU_HOME:-$HOME/.claude}}
local_mode() { printf 'local\t%s\n' "$1"; exit 0; }

case ${UATU_MODE:-auto} in
  local) local_mode "UATU_MODE=local is set — unset it to let uatu pick" ;;
  pr) printf 'pr\tUATU_MODE=pr\n'; exit 0 ;;
  auto) ;;
  *) local_mode "UATU_MODE=$UATU_MODE is not local, pr or auto" ;;
esac

git -C "$dir" rev-parse --git-dir > /dev/null 2>&1 || local_mode "make $dir a git repo: git -C $dir init"
origin=$(git -C "$dir" remote get-url origin 2>/dev/null) \
  || local_mode "add a GitHub origin: git -C $dir remote add origin <url>"
[[ $origin == *github* ]] || local_mode "origin $origin is not on GitHub"
command -v gh > /dev/null || local_mode "install gh, then: gh auth login"
gh auth status --hostname github.com > /dev/null 2>&1 || local_mode "sign in to gh: gh auth login"
err=$(mktemp)
trap 'rm -f "$err"' EXIT
labels=$(cd "$dir" && gh label list --search uatu --json name --jq '.[].name' 2> "$err") \
  || local_mode "gh label list failed: $(head -n 1 "$err")"
grep -qx uatu <<< "$labels" || local_mode "create the label: (cd $dir && gh label create uatu)"
printf 'pr\t%s\n' "$origin"
