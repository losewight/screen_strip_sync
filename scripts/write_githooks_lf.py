"""Write .githooks scripts with LF endings and no BOM (Windows-safe)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOKS = ROOT / ".githooks"

PREPARE = r"""#!/bin/sh
# Strip Cursor agent trailers before the editor / commit finalizes.

MSG_FILE="$1"
[ -n "$MSG_FILE" ] && [ -f "$MSG_FILE" ] || exit 0

tmp="${MSG_FILE}.strip-cursoragent.$$"
# Drop Co-authored-by: Cursor <cursoragent@cursor.com> and any cursoragent line.
if ! grep -viE \
  -e '^[[:space:]]*Co-authored-by:[[:space:]]*Cursor[[:space:]]*<cursoragent@cursor\.com>[[:space:]]*$' \
  -e 'cursoragent@cursor\.com' \
  -e '(^|[^[:alnum:]_])cursoragent([^[:alnum:]_]|$)' \
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
# Reject commits whose message still mentions Cursor agent identity.
MSG_FILE="$1"
[ -n "$MSG_FILE" ] && [ -f "$MSG_FILE" ] || exit 0

if grep -qiE \
  -e 'cursoragent@cursor\.com' \
  -e 'Co-authored-by:[[:space:]]*Cursor' \
  -e '(^|[^[:alnum:]_])cursoragent([^[:alnum:]_]|$)' \
  "$MSG_FILE"
then
  echo "error: commit message must not contain Cursor agent identity" >&2
  echo "       (cursoragent / Co-authored-by: Cursor <cursoragent@cursor.com>)" >&2
  echo "       Remove those lines and commit again." >&2
  exit 1
fi
exit 0
"""

PRE_PUSH = r"""#!/bin/sh
# Block push if any outgoing commit message still has Cursor agent identity.

zero="0000000000000000000000000000000000000000"
pattern='cursoragent@cursor\.com|Co-authored-by:[[:space:]]*Cursor|(^|[^[:alnum:]_])cursoragent([^[:alnum:]_]|$)'

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
    echo "error: push blocked — commit message(s) contain Cursor agent identity:" >&2
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
