#!/usr/bin/env bash
# Regression test for uatu-setup.sh: a failing gh call must not read as a missing label.
# Usage: tests/uatu-setup-gh-failure.sh [path-to-uatu-setup.sh]
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
setup=${1:-$root/plugins/uatu/skills/uatu/scripts/uatu-setup.sh}
[ "${setup#/}" = "$setup" ] && setup=$PWD/$setup

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
export HOME=$tmp GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

git init -q -b main "$tmp/home"
git -C "$tmp/home" remote add origin https://github.com/x/y
export UATU_HOME=$tmp/home

mkdir "$tmp/bin" "$tmp/nogh"
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s' "${STUB_OUT:-}"
printf '%s' "${STUB_ERR:-}" >&2
exit "${STUB_EXIT:-0}"
SH
chmod +x "$tmp/bin/gh"
for t in git mkdir cat grep; do ln -s "$(command -v "$t")" "$tmp/nogh/$t"; done

fail=0
label_line() { bash "$setup" 2>&1 | grep 'label uatu' || true; }
expect() { # name, line, pattern that must match, pattern that must not
  if ! grep -q -- "$3" <<<"$2" || { [ -n "${4:-}" ] && grep -q -- "$4" <<<"$2"; }; then
    echo "FAIL $1: got '$2'" >&2
    fail=1
  fi
}

line=$(PATH=$tmp/bin:$PATH STUB_EXIT=1 STUB_ERR='GraphQL: Could not resolve to a Repository with the name x/y.' label_line)
expect "gh fails" "$line" "Could not resolve to a Repository" "gh label create"

line=$(PATH=$tmp/bin:$PATH STUB_OUT=uatu label_line)
expect "label present" "$line" "^ok    label uatu"

line=$(PATH=$tmp/bin:$PATH label_line)
expect "label absent" "$line" "^todo  label uatu — gh label create uatu"

out=$(PATH=$tmp/nogh /bin/bash "$setup" 2>&1 || true)
line=$(grep 'label uatu' <<<"$out" || true)
expect "no gh" "$line" "^todo  label uatu — install gh first"
if grep -q '^fail' <<<"$out"; then echo "FAIL no gh: fail line in output" >&2; fail=1; fi

[ "$fail" -eq 0 ] || exit 1
echo "ok uatu-setup gh failure"
