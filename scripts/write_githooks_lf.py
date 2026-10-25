"""Write .githooks scripts with LF endings and no BOM (Windows-safe)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOKS = ROOT / ".githooks"

PREPARE = r"""#!/bin/sh
# Strip Agent trailers before the editor / commit finalizes.

MSG_FILE="$1"
[ -n "$MSG_FILE" ] && [ -f "$MSG_FILE" ] || exit 0

tmp="${MSG_FILE}.strip-agent.$$"
# Drop any Co-authored-by referencing agents/bots, cursoragent, or agent signature lines.
if ! grep -viE \
  -e '^[[:space:]]*Co-authored-by:[[:space:]]*.*(cursor|agent|antigravity|copilot|gemini|claude|chatgpt|openai|anthropic|bot)' \
  -e 'cursoragent' \
  -e '^[[:space:]]*Signed-off-by:[[:space:]]*.*(agent|bot)' \
  -e '^[[:space:]]*(\[?[Aa]gent\]?|🤖|Generated[ -]by:)' \
  "$MSG_FILE" >"$tmp"
then
  : >"$tmp"
fi

# Collapse runs of 3+ blank lines to a single blank line.
awk '
  BEGIN { blank = 0 }
  /^[[:space:]]*$/ {
    blank++
    if (blank <= 1) print ""
    next
  }
  { blank = 0; print }
' "$tmp" >"${tmp}.2" && mv "${tmp}.2" "$MSG_FILE"
rm -f "$tmp" "${tmp}.2"
exit 0
"""

COMMIT_MSG = r"""#!/bin/sh
# Reject commits whose message contains Agent tags or identity.
MSG_FILE="$1"
[ -n "$MSG_FILE" ] && [ -f "$MSG_FILE" ] || exit 0

pattern='cursoragent|Co-authored-by:[[:space:]]*.*(cursor|agent|antigravity|copilot|gemini|claude|chatgpt|openai|anthropic|bot)|Signed-off-by:[[:space:]]*.*(agent|bot)|^[[:space:]]*(\[?[Aa]gent\]?|🤖|Generated[ -]by:)'

if grep -qiE -e "$pattern" "$MSG_FILE"; then
  echo "error: commit message must not contain Agent tags or identity" >&2
  echo "       (cursoragent / Co-authored-by with agent/bot / [agent] / AI tags)" >&2
  echo "       Remove those lines and commit again." >&2
  exit 1
fi
exit 0
"""

PRE_PUSH = r"""#!/bin/sh
# Block push if any outgoing commit message still has Agent tags or identity.

zero="0000000000000000000000000000000000000000"
pattern='cursoragent|Co-authored-by:[[:space:]]*.*(cursor|agent|antigravity|copilot|gemini|claude|chatgpt|openai|anthropic|bot)|Signed-off-by:[[:space:]]*.*(agent|bot)|^[[:space:]]*(\[?[Aa]gent\]?|🤖|Generated[ -]by:)'

while read -r local_ref local_sha remote_ref remote_sha
do
  [ -z "$local_sha" ] && continue
  if [ "$local_sha" = "$zero" ]; then
    continue
  fi
  if [ "$remote_sha" = "$zero" ] || [ -z "$remote_sha" ]; then
    range="$local_sha"
  else
    range="${remote_sha}..${local_sha}"
  fi

  bad_commits="$(
    git rev-list "$range" 2>/dev/null | while read -r c; do
      if git log -1 --format='%B' "$c" | grep -qiE -e "$pattern"; then
        echo "$c"
      fi
    done
  )"
  if [ -n "$bad_commits" ]; then
    echo "error: push blocked — commit message(s) contain Agent tags or identity:" >&2
    echo "$bad_commits" | while read -r c; do
      [ -n "$c" ] || continue
      echo "  $(git log -1 --format='%h %s' "$c")" >&2
    done
    echo "Rewrite those commits before pushing." >&2
    exit 1
  fi
done

exit 0
"""


def write_lf(path: Path, text: str) -> None:
    path.write_bytes(text.replace("\r\n", "\n").encode("utf-8"))


def main() -> None:
    HOOKS.mkdir(parents=True, exist_ok=True)
    write_lf(HOOKS / "prepare-commit-msg", PREPARE)
    write_lf(HOOKS / "commit-msg", COMMIT_MSG)
    write_lf(HOOKS / "pre-push", PRE_PUSH)
    print("wrote LF hooks under", HOOKS)


if __name__ == "__main__":
    main()
