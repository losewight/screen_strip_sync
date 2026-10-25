# Git hooks — no Agent identity or tags in commits

This directory is the project `core.hooksPath`. Hooks block
`cursoragent` / Agent trailers / `Co-authored-by: ...agent...` from
entering git history or GitHub.

| Hook | Role |
|------|------|
| `prepare-commit-msg` | Strips Agent trailers before commit |
| `commit-msg` | Rejects the commit if Agent tags/identities remain |
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

Do **not** use `--no-verify` to bypass these hooks for Agent trailers.
