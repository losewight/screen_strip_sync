# Git hooks — no Cursor agent identity in commits

This directory is the project `core.hooksPath`. Hooks block
`cursoragent` / `Co-authored-by: Cursor <cursoragent@cursor.com>` from
entering git history or GitHub.

| Hook | Role |
|------|------|
| `prepare-commit-msg` | Strips Cursor agent trailers before commit |
| `commit-msg` | Rejects the commit if those strings remain |
| `pre-push` | Rejects push if any outgoing commit message still has them |

## Enable (once per clone)

PowerShell:

```powershell
.\scripts\setup-git-hooks.ps1
```

Or manually:

```bash
git config core.hooksPath .githooks
```

Verify:

```bash
git config --get core.hooksPath
# expect: .githooks
```

Do **not** use `--no-verify` to bypass these hooks for Cursor agent trailers.
