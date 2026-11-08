#!/usr/bin/env bash
# Regression test for uatu-mode.sh: a failing gh call must not read as a missing label.
# Usage: tests/uatu-mode-gh-failure.sh [path-to-uatu-mode.sh]
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-$root/plugins/uatu/skills/uatu/scripts/uatu-mode.sh}
[ "${mode#/}" = "$mode" ] && mode=$PWD/$mode

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR UATU_MODE
export HOME=$tmp GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

git init -q -b main "$tmp/home"
git -C "$tmp/home" remote add origin https://github.com/x/y
export UATU_HOME=$tmp/home

mkdir "$tmp/bin" "$tmp/nogh"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = auth ] && exit 0
printf '%s' "${STUB_OUT:-}"
printf '%s' "${STUB_ERR:-}" >&2
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$tmp/bin/gh"
for t in git mktemp grep head rm; do ln -s "$(command -v "$t")" "$tmp/nogh/$t"; done

fail=0
expect() { # name, line, pattern that must match, pattern that must not
  if ! grep -q -- "$3" <<<"$2" || { [ -n "${4:-}" ] && grep -q -- "$4" <<<"$2"; }; then
    echo "FAIL $1: got '$2'" >&2
    fail=1
  fi
}

line=$(PATH=$tmp/bin:$PATH STUB_EXIT=1 STUB_ERR='GraphQL: Could not resolve to a Repository with the name x/y.' bash "$mode")
expect "gh fails" "$line" "^local.*Could not resolve to a Repository" "gh label create"

line=$(PATH=$tmp/bin:$PATH STUB_OUT=uatu bash "$mode")
expect "label present" "$line" "^pr"

line=$(PATH=$tmp/bin:$PATH bash "$mode")
expect "label absent" "$line" "^local.*gh label create uatu"

line=$(PATH=$tmp/nogh /bin/bash "$mode")
expect "no gh" "$line" "^local.*install gh"

line=$(UATU_MODE=local PATH=$tmp/bin:$PATH STUB_OUT=uatu bash "$mode")
expect "forced local" "$line" "^local.*UATU_MODE=local"

line=$(bash "$mode" "$tmp")
expect "no git" "$line" "^local.*git -C $tmp init"

[ "$fail" -eq 0 ] || exit 1
echo "ok uatu-mode gh failure"
