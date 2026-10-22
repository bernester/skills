#!/bin/bash
# Creates what uatu needs under $UATU_HOME and lists what only the person can do.
# Never commits, never creates the GitHub label.
# Usage: uatu-setup.sh

set -uo pipefail

if [[ -z ${UATU_HOME:-} ]]; then
  echo "uatu-setup: UATU_HOME is unset. Add this to your shell profile, then run again:" >&2
  echo "  export UATU_HOME=/path/to/your/harness/repo" >&2
  exit 1
fi
git -C "$UATU_HOME" rev-parse --git-dir > /dev/null 2>&1 \
  || { echo "uatu-setup: $UATU_HOME is not a git repo — run git init there first" >&2; exit 1; }

cd "$UATU_HOME" || exit 1
for d in uatu research; do
  if [[ -d $d ]]; then echo "exists   $d/"; else mkdir "$d" && echo "created  $d/"; fi
done

write_if_absent() {
  if [[ -e $1 ]]; then
    echo "exists   $1"
  else
    cat > "$1"
    echo "created  $1"
  fi
}

write_if_absent uatu/declined.md <<'MD'
# Declined

Every recommendation you rejected without a pull request, one line each. uatu reads this file
and never proposes these again.

```
- <YYYY-MM-DD> · <recommendation> — <why you declined it>
```
MD

# Indented inside a list item: the digest treats any column-0 "- section: " line as a real section.
write_if_absent uatu/sources.md <<'MD'
# Sources

Which sections of a dropped issue count as tips, and why the source is trusted. uatu reads
nothing from an issue this file does not name; a source with no section line is read whole.

- Format, one heading per source:

  ```
  ## <source name>

  - from: <sender or site>
  - trusted because: <why>
  - section: <heading of the part that holds the tips>
  ```
MD

echo
check() {
  if eval "$2" > /dev/null 2>&1; then
    echo "ok    $1"
  else
    echo "todo  $1 — $3"
  fi
}

check "GitHub origin" "git remote get-url origin" "git remote add origin <url>"
if git remote get-url origin > /dev/null 2>&1; then
  check "label uatu" "gh label list --search uatu --json name --jq '.[].name' | grep -qx uatu" \
    "gh label create uatu"
else
  echo "todo  label uatu — needs a GitHub origin first"
fi
check "python3" "command -v python3" "install python3"
check "jq" "command -v jq" "install jq"
check "gh" "command -v gh" "install gh"
for v in UATU_LESSONS UATU_PAPERCUTS; do
  [[ -n ${!v:-} ]] && echo "ok    $v" || echo "optional  $v — unset"
done
exit 0
