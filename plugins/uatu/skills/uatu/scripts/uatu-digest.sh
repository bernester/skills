#!/bin/bash
# The deterministic half of a uatu run: counts and diffs over every repo ~/.claude links into, no
# model tokens. Writes $UATU_CACHE/digest.md, appends a row to $UATU_HOME/uatu/history.tsv.
# Usage: uatu-digest.sh [--out <file>] [--window <days>] [--no-fetch]

set -uo pipefail
# cut -c splits multibyte characters, and sort rejects the halves under a UTF-8 locale.
export LC_ALL=C

CLAUDE_DIR="$HOME/.claude"
DATA="${UATU_HOME:?set it to the repo holding uatu/}/uatu"
CACHE="${UATU_CACHE:-$HOME/.cache/uatu}"
OUT="$CACHE/digest.md"
HISTORY="$DATA/history.tsv"
WINDOW=30
FETCH=1
SCHEMA=4

while (($#)); do
  case $1 in
    --out) OUT=$2; shift 2 ;;
    --window) WINDOW=$2; shift 2 ;;
    --no-fetch) FETCH=0; shift ;;
    *) echo "uatu-digest: unknown argument $1" >&2; exit 2 ;;
  esac
done

[[ -d $DATA ]] || { echo "uatu-digest: no data directory at $DATA — run /uatu setup" >&2; exit 1; }

TODAY=$(date +%F)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$CACHE/docs"

HIST="$CLAUDE_DIR/history.jsonl"
PROJECTS="$CLAUDE_DIR/projects"

# Transcripts touched in the window. The whole store is ~900 MB; the weekly question is
# what changed, so everything below reads this list, not the store.
recent_files="$TMP/recent.txt"
find "$PROJECTS" -name '*.jsonl' -mtime "-$WINDOW" -print0 > "$recent_files" 2>/dev/null
recent_count=$(tr -dc '\0' < "$recent_files" | wc -c | tr -d ' ')

# The file list is NUL-delimited and can run to thousands of paths — always via xargs,
# never as $(cat …) on argv.
each_recent() { xargs -0 "$@" < "$recent_files" 2>/dev/null; }
all_count=$(find "$PROJECTS" -name '*.jsonl' | wc -l | tr -d ' ')
store_mb=$(du -sm "$PROJECTS" 2>/dev/null | cut -f1)

cli_version=$(claude --version 2>/dev/null | awk '{print $1}')

# One row per live link: repo toplevel, target relative to it, link relative to ~/.claude.
# A dangling link or a target outside any git repo (vendored skills) drops out here.
links="$TMP/links.tsv"
find "$CLAUDE_DIR" -maxdepth 2 -type l -not -path "$PROJECTS/*" 2>/dev/null | while read -r link; do
  target=$(realpath "$link" 2>/dev/null) || continue
  top=$(git -C "$(dirname "$target")" rev-parse --show-toplevel 2>/dev/null) || continue
  printf '%s\t%s\t%s\n' "$top" "${target#"$top"/}" "${link#"$CLAUDE_DIR"/}"
done | sort > "$links"

section() { printf '\n## %s\n\n' "$1" >> "$OUT"; }

: > "$OUT"
{
  echo "# Uatu digest — $TODAY"
  echo
  echo "Deterministic. Regenerate with \`~/.claude/skills/uatu/scripts/uatu-digest.sh\`."
  echo
  echo "- CLI: \`$cli_version\` · window ${WINDOW}d"
  echo "- Transcripts: $recent_count of $all_count files touched in the window, ${store_mb} MB total"
} >> "$OUT"

# ---------------------------------------------------------------- coverage

section "Coverage"

{
  if [[ -f $HIST ]]; then
    hist_total=$(wc -l < "$HIST" | tr -d ' ')
    hist_mtime=$(stat -f %m "$HIST")
    newest_transcript=$(each_recent stat -f %m | sort -n | tail -1)
    echo "\`history.jsonl\`: $hist_total prompts, never expires. Last written $(date -r "$hist_mtime" +%F), $(( ($(date +%s) - hist_mtime) / 86400 ))d ago."
    # The desktop app writes transcripts but not history.jsonl.
    (( ${newest_transcript:-0} - hist_mtime > 86400 )) &&
      echo "  **Stale**: transcripts were written after it. Only \`prompts_all\` reads it; the window counts read transcripts."
    echo
    for field in display timestamp project sessionId; do
      n=$(jq -r --arg f "$field" 'select(has($f)) | 1' "$HIST" 2>/dev/null | wc -l | tr -d ' ')
      printf -- '- `%s`: %s/%s\n' "$field" "$n" "$hist_total"
    done
  else
    hist_total=0
    echo "\`history.jsonl\`: absent."
  fi

  echo
  versions=$(each_recent grep -ho '"version":"[0-9][0-9.]*"' \
    | sed 's/.*:"//; s/"//' | sort -uV | tr '\n' ' ' | sed 's/ $//')
  echo "CLI versions represented in the window: ${versions:-none}"
  echo
  echo "Field spellings seen (a rename upstream shows up here first):"
  echo
  for field in sessionId session_id timestamp cwd version origin; do
    n=$(each_recent grep -l "\"$field\":" | wc -l | tr -d ' ')
    printf -- '- `%s`: in %s/%s files\n' "$field" "$n" "$recent_count"
  done
} >> "$OUT"

# ---------------------------------------------------------------- setup usage

section "Setup usage"

# What the human typed in the window, one line per prompt — a prompt's own newlines are
# flattened, or every count below reads lines instead of prompts. Read from transcripts:
# the desktop app never writes history.jsonl. Records without `origin` (older CLIs) are
# not counted. Resumed sessions copy records into a new file, hence the uuid dedupe.
each_recent grep -h '"kind":"human"' | jq -r --arg cutoff "$(date -u -v-"${WINDOW}"d +%FT%T)" --arg home "$HOME" '
  select(.type == "user" and .origin.kind == "human" and (.isSidechain | not)
    and (.timestamp // "") > $cutoff)
  | (.message.content | if type == "string" then . else map(.text // empty) | join(" ") end
    | gsub("(?s)<system-reminder>.*?</system-reminder>"; "")
    | gsub("(?s)<(?<t>artifact-view-context|launch-selected-element|bash-stdout|bash-stderr)[^>]*>.*?</\\k<t>>"; "")
    | gsub("<!-- reply -->\\s*(>[^\n]*\n)*"; "")
    | gsub("(?s)<command-message>.*?</command-message>"; "")
    | gsub("<command-name>(?<n>[^<]*)</command-name>\\s*(<command-args>(?<a>(?s:.)*?)</command-args>)?"; "\(.n) \(.a // "")")
    | gsub("(?s)<bash-input>(?<c>.*?)</bash-input>"; "!\(.c)")
    | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ")) as $text
  | select($text != "")
  | [.uuid, (.cwd // "" | sub("/\\.claude/worktrees/.*"; "") | sub("^" + $home; "~")), $text]
  | @tsv' 2>/dev/null | sort -u -t $'\t' -k1,1 > "$TMP/typed.tsv"
cut -f3 "$TMP/typed.tsv" > "$TMP/prompts.txt"
prompts_window=$(wc -l < "$TMP/prompts.txt" | tr -d ' ')

grep -oE '^/[a-z0-9:-]+' "$TMP/prompts.txt" 2>/dev/null | sort | uniq -c | sort -rn > "$TMP/typed-skills.txt"

# What actually ran, including model-invoked skills and subagent turns.
each_recent grep -ho '"attributionSkill":"[^"]*"' \
  | sed 's/.*:"//; s/"//' | sort | uniq -c | sort -rn > "$TMP/ran-skills.txt"

{
  echo "Typed invocations in the window (transcripts, $prompts_window typed prompts):"
  echo
  if [[ -s $TMP/typed-skills.txt ]]; then
    sed 's/^ */- /' "$TMP/typed-skills.txt" | head -20
  else
    echo "- none"
  fi
  echo
  echo "Skill turns in the window (\`attributionSkill\`, includes model-invoked):"
  echo
  if [[ -s $TMP/ran-skills.txt ]]; then
    sed 's/^ */- /' "$TMP/ran-skills.txt" | head -20
  else
    echo "- none"
  fi
} >> "$OUT"

# Scoped to skills linked from a repo, not to every installed skill.
{
  echo
  echo "Authored skills with no invocation in the window:"
  echo
  idle=0
  while read -r rel; do
    [[ $rel == skills/* ]] || continue
    name=${rel#skills/}
    if ! grep -qx "$name" <(awk '{print $2}' "$TMP/ran-skills.txt") \
      && ! grep -qx "/$name" <(awk '{print $2}' "$TMP/typed-skills.txt"); then
      echo "- \`/$name\`"
      idle=$((idle + 1))
    fi
  done < <(cut -f3 "$links")
  ((idle)) || echo "- none"
} >> "$OUT"

# ---------------------------------------------------------------- repeats and corrections

section "Prompts worth a skill"

# Same prompt typed three times or more: the documented trigger for saving a skill.
# Pastes are excluded — their placeholder text repeats without the prompt repeating.
grep -v '^[/!]' "$TMP/prompts.txt" 2>/dev/null | grep -v '^\[Pasted text' \
  | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9 ]//g; s/  */ /g; s/^ //; s/ $//' \
  | awk 'length > 12 { print substr($0, 1, 60) }' \
  | sort | uniq -c | sort -rn | awk '$1 >= 3' > "$TMP/repeats.txt"
repeat_count=$(wc -l < "$TMP/repeats.txt" | tr -d ' ')

{
  if [[ -s $TMP/repeats.txt ]]; then
    sed 's/^ */- /' "$TMP/repeats.txt" | head -10
  else
    echo "None repeated three times or more."
  fi
} >> "$OUT"

section "Corrections"

# The human telling an agent it got it wrong. A cheap proxy, and it reads the human's own
# words rather than inferring from transcripts.
grep -icE '\b(no|nope|dont|don.t|wrong|not what|i said|revert|undo|actually|stop)\b' \
  "$TMP/prompts.txt" > "$TMP/corr-count.txt" 2>/dev/null
corr_count=$(cat "$TMP/corr-count.txt")

{
  echo "$corr_count of $prompts_window typed prompts in the window read as a correction. Most recent:"
  echo
  grep -iE '\b(no|nope|dont|don.t|wrong|not what|i said|revert|undo|actually|stop)\b' \
    "$TMP/prompts.txt" 2>/dev/null | tail -8 | cut -c1-100 | sed 's/^/- /'
} >> "$OUT"

section "Activity by project"

cut -f2 "$TMP/typed.tsv" | sort | uniq -c | sort -rn | head -12 \
  | sed 's/^ */- /' >> "$OUT"

# ---------------------------------------------------------------- tool errors

section "Tool errors"

# Error text, normalised so the same failure collapses into one row, and named with the tool
# that produced it — a count with no tool name cannot become an edit. The name lives on the
# assistant's tool_use line, so it takes a tool_use_id join across lines.
each_recent grep -h '"type":"tool_use"' \
  | jq -r '.message.content[]? | select(.type == "tool_use") | [.id, .name] | @tsv' 2>/dev/null \
  | sort -u > "$TMP/tool-names.tsv"

# Bash commands by id, so a classifier or worktree-guard rejection can name what it rejected.
each_recent grep -h '"type":"tool_use"' \
  | jq -r '.message.content[]? | select(.type == "tool_use" and .name == "Bash")
           | [.id, ((.input.command // "") | gsub("\n"; " "))] | @tsv' 2>/dev/null \
  | sort -u -k1,1 > "$TMP/bash-cmds.tsv"

each_recent grep -h '"is_error":true' \
  | jq -r '.message.content[]? | select(.type == "tool_result" and .is_error == true)
           | [ .tool_use_id,
               ((if (.content | type) == "array" then (.content[0].text? // "") else (.content | tostring) end)
                | gsub("\n"; " ")) ] | @tsv' 2>/dev/null \
  | sed -E "s#$HOME[^ ]*#<path>#g; s/[0-9a-f]{8}-[0-9a-f-]{20,}/<uuid>/g" \
  | sort -k1,1 > "$TMP/errors-by-id.tsv"
error_total=$(wc -l < "$TMP/errors-by-id.tsv" | tr -d ' ')

# An id with no tool_use line — its half of the pair aged out of the window — would vanish in
# the join, so it is kept under a placeholder name and the coverage is reported.
join -t $'\t' -a1 -e '<unpaired>' -o '2.2,1.2' -1 1 -2 1 \
  "$TMP/errors-by-id.tsv" "$TMP/tool-names.tsv" 2>/dev/null \
  | awk -F'\t' '{ printf "%s\t%s\n", ($1 == "" ? "<unpaired>" : $1), substr($2, 1, 80) }' \
  | sort | uniq -c | sort -rn > "$TMP/errors.txt"
paired=$(grep -cv '^ *[0-9]* *<unpaired>' "$TMP/errors.txt")

grep -E $'\t.*(auto mode classifier|too complex to verify)' "$TMP/errors-by-id.tsv" \
  | cut -f1 | sort -u > "$TMP/rejected-ids.txt"
rejected_total=$(wc -l < "$TMP/rejected-ids.txt" | tr -d ' ')
join -t $'\t' -o '2.2' "$TMP/rejected-ids.txt" "$TMP/bash-cmds.tsv" 2>/dev/null \
  | sed -E "s#$HOME[^ ]*#<path>#g" | cut -c1-90 | sort | uniq -c | sort -rn > "$TMP/rejected-cmds.txt"
rejected_paired=$(awk '{s+=$1} END{print s+0}' "$TMP/rejected-cmds.txt")

{
  echo "$error_total error results in the window, over $(wc -l < "$TMP/tool-names.tsv" | tr -d ' ') tool calls."
  echo "By tool and signature ($paired of $(wc -l < "$TMP/errors.txt" | tr -d ' ') signatures paired to a tool name):"
  echo
  if [[ -s $TMP/errors.txt ]]; then
    sed 's/^ */- /' "$TMP/errors.txt" | head -15
  else
    echo "- none"
  fi
  echo
  echo "Bash commands behind classifier and worktree-guard rejections ($rejected_paired of $rejected_total paired to a command):"
  echo
  if [[ -s $TMP/rejected-cmds.txt ]]; then
    sed 's/^ */- /' "$TMP/rejected-cmds.txt" | head -12
  else
    echo "- none"
  fi
} >> "$OUT"

# ---------------------------------------------------------------- the setup itself

section "Setup"

# Run from a worktree, the links still point at the main checkouts, so this reports the live setup.
nearest_verify() { # <toplevel> <target relative to it>
  local dir
  dir=$(dirname "$1/$2")
  while :; do
    [[ -x $dir/verify.sh ]] && { echo "$dir/verify.sh"; return; }
    [[ $dir == "$1" || $dir == / ]] && return
    dir=$(dirname "$dir")
  done
}

verify_status=clean
setup_commits=0
repo_count=0
{
  while read -r top; do
    repo_count=$((repo_count + 1))
    awk -F'\t' -v t="$top" '$1 == t { print $2 }' "$links" > "$TMP/paths.txt"
    echo "### ${top##*/} (\`${top/#$HOME/~}\`), $(wc -l < "$TMP/paths.txt" | tr -d ' ') paths linked"
    echo
    verifies=$(while read -r rel; do nearest_verify "$top" "$rel"; done < "$TMP/paths.txt" | sort -u)
    [[ -n $verifies ]] || echo "No \`verify.sh\` above any linked path."
    while read -r verify_sh; do
      [[ -n $verify_sh ]] || continue
      if verify_out=$("$verify_sh" 2>&1 < /dev/null); then verdict=clean; else verdict=DRIFT; verify_status=DRIFT; fi
      echo "\`${verify_sh#"$top"/}\`: **$verdict**"
      echo
      echo '```'
      echo "$verify_out"
      echo '```'
      echo
    done <<< "$verifies"
    repo_log=$(tr '\n' '\0' < "$TMP/paths.txt" | xargs -0 git -C "$top" log --oneline --since="$WINDOW days ago" -- 2>/dev/null)
    n=$(printf '%s' "$repo_log" | grep -c . )
    setup_commits=$((setup_commits + n))
    echo "Commits on the linked paths in the window: $n"
    echo
    if [[ -n $repo_log ]]; then
      printf '%s\n' "$repo_log" | sed 's/^/- /'
    else
      echo "- none"
    fi
    echo
  done < <(cut -f1 "$links" | sort -u)
  echo "### ~/.claude (\`git status\`, excluding \`uatu/\`)"
  echo
  if claude_drift=$(git --no-optional-locks -C "$CLAUDE_DIR" status --porcelain -- . ':!uatu' 2>&1) && [[ -z $claude_drift ]]; then
    echo "\`git status\`: **clean**"
  else
    verify_status=DRIFT
    printf '`git status`: **DRIFT**\n\n```\n%s\n```\n' "$claude_drift"
  fi
  echo
  echo "Repos linked into \`~/.claude\`: $repo_count. Verify overall: **$verify_status**"
  echo
  echo "### skill-doctor"
  echo
  echo '```'
  if doctor_out=$(cd "$CLAUDE_DIR" && claude -p "/skill-doctor" </dev/null 2>/dev/null) && [[ -n $doctor_out ]] \
    && doctor_out=$(grep -v 'claude.ai sync' <<< "$doctor_out") \
    && ! grep -v 'synced from claude.ai' <<< "$doctor_out" | grep -q 'claude\.ai'; then
    printf '%s\n' "$doctor_out"
  else
    echo "skill-doctor failed — no listing-cost verdict this run."
  fi
  echo '```'
  echo
  echo "Retention: \`cleanupPeriodDays\` = $(jq -r '.cleanupPeriodDays // "unset"' "$CLAUDE_DIR/settings.json" 2>/dev/null)."
  oldest=$(find "$PROJECTS" -name '*.jsonl' -print0 2>/dev/null | xargs -0 ls -tr 2>/dev/null | head -1)
  [[ -n $oldest ]] && echo "Oldest transcript: $(date -r "$oldest" +%F) (\`${oldest##*/}\`)."
} >> "$OUT"

# ---------------------------------------------------------------- upstream

section "Upstream"

changelog_new=0
docs_changed=0

if ((FETCH)); then
  if curl -sSf -o "$TMP/CHANGELOG.md" \
      https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md 2>/dev/null; then
    # Every released version above the one installed here.
    awk '/^## /{v=$2; print v}' "$TMP/CHANGELOG.md" > "$TMP/versions.txt"
    awk -v have="$cli_version" '$0 == have {exit} {print}' "$TMP/versions.txt" > "$TMP/newer.txt"
    changelog_new=$(wc -l < "$TMP/newer.txt" | tr -d ' ')

    {
      if ((changelog_new)); then
        echo "**$changelog_new releases newer than \`$cli_version\`.** Their entries:"
        echo
        awk -v stop="$cli_version" '/^## /{v = $2; if (v == stop) exit} {print}' "$TMP/CHANGELOG.md" \
          > "$TMP/newer-entries.md"
        new_lines=$(wc -l < "$TMP/newer-entries.md" | tr -d ' ')
        sed 's/^/  /' "$TMP/newer-entries.md" | head -400
        ((new_lines > 400)) && echo "  … $((new_lines - 400)) further lines withheld; read \`$CACHE/CHANGELOG.md\` down to \`## $cli_version\`."
      else
        echo "Installed \`$cli_version\` is the newest release in the changelog."
      fi
    } >> "$OUT"
    cp "$TMP/CHANGELOG.md" "$CACHE/CHANGELOG.md"
  else
    echo "Changelog fetch failed — no upstream verdict this run." >> "$OUT"
  fi

  # A changed page can overturn a finding in research/*.md, so every Anthropic page a note
  # cites is watched, plus four scheduling pages no note cites yet.
  RESEARCH="$UATU_HOME/research"
  echo >> "$OUT"
  echo "Doc pages (cache: \`$CACHE/docs/\`):" >> "$OUT"
  echo >> "$OUT"
  {
    cat "$RESEARCH"/*.md 2>/dev/null |
      grep -oE 'https://(code\.claude\.com|platform\.claude\.com|www\.anthropic\.com)/[^][ <>()"`'"'"']*' |
      sed -E 's/#.*$//; s/[.,;:*_]+$//; s/\.md$//'
    printf 'https://code.claude.com/docs/en/%s\n' scheduled-tasks routines desktop-scheduled-tasks headless
  } | sort -u > "$TMP/doc-urls.txt"
  while read -r url; do
    # code.claude.com keys stay bare page names so the caches from before this list still match.
    case $url in
      https://code.claude.com/docs/en/*) key=${url#https://code.claude.com/docs/en/} ;;
      *) key=${url#https://} ;;
    esac
    key=${key//\//_}
    fetched="$TMP/$key.md"
    if [[ $url == https://www.anthropic.com/* ]]; then
      if ! type=$(curl -sSfL -o "$TMP/$key.html" -w '%{content_type}' "$url" 2>/dev/null); then
        echo "- \`$key\`: fetch failed" >> "$OUT"
        continue
      fi
      if [[ $type != text/html* ]]; then
        echo "- \`$key\`: skipped (${type%%;*})" >> "$OUT"
        continue
      fi
      if ! textutil -stdin -format html -convert txt -stdout < "$TMP/$key.html" > "$fetched"; then
        echo "- \`$key\`: text extraction failed" >> "$OUT"
        continue
      fi
    elif ! curl -sSfL -o "$fetched" "$url.md" 2>/dev/null; then
      echo "- \`$key\`: fetch failed" >> "$OUT"
      continue
    fi
    cached="$CACHE/docs/$key.md"
    if [[ ! -f $cached ]]; then
      cp "$fetched" "$cached"
      echo "- \`$key\`: baseline captured ($(wc -l < "$cached" | tr -d ' ') lines)" >> "$OUT"
      continue
    fi
    if diff -q "$cached" "$fetched" > /dev/null; then
      echo "- \`$key\`: unchanged" >> "$OUT"
    else
      docs_changed=$((docs_changed + 1))
      added=$(diff "$cached" "$fetched" | grep -c '^>')
      removed=$(diff "$cached" "$fetched" | grep -c '^<')
      mkdir -p "$CACHE/diffs"
      diff -u "$cached" "$fetched" > "$CACHE/diffs/$TODAY-$key.diff"
      echo "- \`$key\`: **changed** (+$added/-$removed), diff in \`$CACHE/diffs/$TODAY-$key.diff\`" >> "$OUT"
      # grep -F would also count a note citing hooks-guide as citing hooks.
      url_re=$(sed 's/[][\.*^$()+?{}|]/\\&/g' <<< "$url")
      grep -lE "$url_re([^a-z0-9-]|\$)" "$RESEARCH"/*.md 2>/dev/null | while read -r note; do
        echo "  Cited by: research/${note##*/} — refresh with \`/research\`" >> "$OUT"
      done
      heads=$(diff "$cached" "$fetched" | grep -E '^[<>] #{1,4} ' | head -8)
      [[ -n $heads ]] && { echo "  Changed headings:" >> "$OUT"; sed 's/^/    /' <<< "$heads" >> "$OUT"; }
      cp "$fetched" "$cached"
    fi
  done < "$TMP/doc-urls.txt"

  # Plain "- name:" lines, no backticks, so these never count as doc pages.
  echo >> "$OUT"
  echo "New pages since last run (leads, not evidence):" >> "$OUT"
  echo >> "$OUT"
  mkdir -p "$CACHE/index"
  for name in code-llms platform-llms anthropic-engineering; do
    case $name in
      code-llms) src=https://code.claude.com/docs/llms.txt ;;
      platform-llms) src=https://platform.claude.com/llms.txt ;;
      anthropic-engineering) src=https://www.anthropic.com/engineering ;;
    esac
    # A transfer cut short would still yield links, and saving them makes the tail "new" next run.
    links=0
    if curl -sSfL -o "$TMP/index-$name.raw" "$src" 2>/dev/null; then
      case $name in
        code-llms) grep -oE 'https://code\.claude\.com/[^) ]+' ;;
        platform-llms) grep -oE 'https://platform\.claude\.com/[^) ]+' ;;
        # The engineering index has no hrefs; its article slugs sit in escaped JSON.
        anthropic-engineering) grep -oE '\\"slug\\":\{[^}]*current\\":\\"[a-z0-9-]+' |
          sed -E 's|.*\\"|https://www.anthropic.com/engineering/|' ;;
      esac < "$TMP/index-$name.raw" | sort -u > "$TMP/index-$name.txt"
      links=$(wc -l < "$TMP/index-$name.txt" | tr -d ' ')
    fi
    saved="$CACHE/index/$name.txt"
    if ((links == 0)); then
      echo "- $name: link extraction failed" >> "$OUT"
      continue
    fi
    if [[ ! -f $saved ]]; then
      echo "- $name: baseline captured ($links links)" >> "$OUT"
    else
      comm -13 "$saved" "$TMP/index-$name.txt" > "$TMP/new-$name.txt"
      new=$(wc -l < "$TMP/new-$name.txt" | tr -d ' ')
      {
        if ((new == 0)); then
          echo "- $name: none new"
        else
          echo "- $name: $new new"
          head -10 "$TMP/new-$name.txt" | sed 's/^/  - /'
          ((new > 10)) && echo "  … $((new - 10)) more in $saved"
        fi
      } >> "$OUT"
    fi
    cp "$TMP/index-$name.txt" "$saved"
  done
else
  echo "Skipped (\`--no-fetch\`)." >> "$OUT"
fi

{
  echo
  echo "Model IDs named in linked skills:"
  echo
  ids=$(while IFS=$'\t' read -r top rel link; do
    [[ $link == skills/* ]] || continue
    (cd "$top" && grep -rnoE 'claude-(opus|sonnet|haiku|fable|[0-9])[a-z0-9.-]*[0-9]' "$rel" 2>/dev/null | sed "s|^|${top##*/}/|")
  done < "$links")
  if [[ -n $ids ]]; then sed -E 's/^([^:]+:[0-9]+):(.*)$/- \1: \2/' <<< "$ids" | sort -u; else echo "- none"; fi
} >> "$OUT"

# ---------------------------------------------------------------- sources

section "Sources"

# An issue is read once its .md is committed; delete the .md to re-read it.
issues_read=0
INBOX="$DATA/inbox"
for eml in "$INBOX"/*.eml; do
  [[ -f $eml && ! -f ${eml%.eml}.md ]] || continue
  python3 "$(dirname "$0")/eml-to-md.py" "$eml" "${eml%.eml}.md" ||
    echo "- \`inbox/${eml##*/}\`: conversion failed" >> "$OUT"
done
for src in "$INBOX"/*.pdf "$INBOX"/*.url; do
  [[ -f $src && ! -f ${src%.*}.md ]] || continue
  issues_read=$((issues_read + 1))
  echo "- \`inbox/${src##*/}\`: **to convert** into \`inbox/$(basename "${src%.*}").md\`" >> "$OUT"
done
for md in "$INBOX"/*.md; do
  [[ -f $md ]] || continue
  if git -C "$INBOX" ls-files --error-unmatch "$md" > /dev/null 2>&1; then
    echo "- \`inbox/${md##*/}\`: already read" >> "$OUT"
    continue
  fi
  issues_read=$((issues_read + 1))
  echo "- \`inbox/${md##*/}\`: **new** ($(wc -l < "$md" | tr -d ' ') lines) — sections named in \`uatu/sources.md\`:" >> "$OUT"
  grep -n -F -f <(grep -o '^- section: .*' "$DATA/sources.md" | sed 's/^- section: //') "$md" \
    | sed 's/^/    /' >> "$OUT"
done
((issues_read)) || echo "No unread issue." >> "$OUT"

# ---------------------------------------------------------------- logs

section "Logs"

if [[ -f ${UATU_LESSONS:-} && -r $UATU_LESSONS ]]; then
  open=$(awk '/^## /{h=$0;hl=FNR} /\*\*open[*,]/ && hl!=done {print "- "FILENAME":"hl": "h; done=hl}' \
    "$UATU_LESSONS")
  echo "${open:-- none open in \`$UATU_LESSONS\`}" >> "$OUT"
else
  echo "Lessons: not configured — set \`UATU_LESSONS\` to an absolute path (README)." >> "$OUT"
fi
if [[ -f ${UATU_PAPERCUTS:-} && -r $UATU_PAPERCUTS ]]; then
  awk -v since="$(date -v-"${WINDOW}"d +%F)" -v f="$UATU_PAPERCUTS" '
    /^(- )?[0-9]{4}-[0-9]{2}-[0-9]{2} · / {
      n++; d = $0; sub(/^- /, "", d); if (substr(d, 1, 10) >= since) m++
    }
    END { printf "Papercuts: %s — %d entries, %d in the window.\n", f, n, m }' \
    "$UATU_PAPERCUTS" >> "$OUT"
else
  echo "Papercuts: not configured — set \`UATU_PAPERCUTS\` to an absolute path (README)." >> "$OUT"
fi

# ---------------------------------------------------------------- history row

if [[ ! -f $HISTORY ]]; then
  printf 'schema\tdate\tcli\tprompts_all\tprompts_window\ttranscripts_window\ttranscripts_all\tstore_mb\ttool_errors\tcorrections\trepeats\tsetup_commits\tverify\tchangelog_new\tdocs_changed\tissues_read\n' > "$HISTORY"
fi
grep -q 'issues_read' "$HISTORY" || sed -i '' '1s/$/\tissues_read/' "$HISTORY"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$SCHEMA" "$TODAY" "$cli_version" "${hist_total:-0}" "$prompts_window" \
  "$recent_count" "$all_count" "${store_mb:-0}" "$error_total" "$corr_count" \
  "$repeat_count" "$setup_commits" "$verify_status" "$changelog_new" "$docs_changed" \
  "$issues_read" >> "$HISTORY"

section "History"

{
  echo '```'
  column -t -s $'\t' "$HISTORY" 2>/dev/null | tail -8
  echo '```'
} >> "$OUT"

echo "uatu-digest: wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines), appended a row to $HISTORY"
