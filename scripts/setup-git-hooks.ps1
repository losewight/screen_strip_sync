# Setup project git hooks (blocks Cursor agent identity in commits/pushes)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root ".githooks"))) {
    throw "Missing .githooks directory at repo root."
}
Push-Location $root
try {
    python (Join-Path $PSScriptRoot "write_githooks_lf.py")
    git config core.hooksPath .githooks
    $path = git config --get core.hooksPath
    Write-Host "core.hooksPath = $path"
    Write-Host "OK: commit-msg / prepare-commit-msg / pre-push are active."
}
finally {
    Pop-Location
}
