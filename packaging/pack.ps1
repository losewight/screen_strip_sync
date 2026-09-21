# Stage Flutter Release + helper.exe, then zip (+ optional Inno installer).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Staging = Join-Path $Root "dist_stage"
$OutDir = Join-Path $Root "dist_installer"
$Helper = Join-Path $Root "cpp_core\build\Release\helper.exe"
$FlutterRelease = Join-Path $Root "build\windows\x64\runner\Release"
$Iss = Join-Path $PSScriptRoot "screen_strip_sync.iss"
$Version = "1.0.2"
$Arch = "x64"
$ZipName = "ScreenStripSync-$Version-windows-$Arch.zip"

$IsccCandidates = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
  "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
)
$Iscc = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not (Test-Path $Helper)) {
  throw "Missing $Helper — run: cmake --build cpp_core/build --config Release"
}
if (-not (Test-Path (Join-Path $FlutterRelease "screen_strip_sync.exe"))) {
  throw "Missing Flutter Release — run: flutter build windows --release"
}

Write-Host "Staging -> $Staging"
if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory $Staging | Out-Null
Copy-Item (Join-Path $FlutterRelease "*") $Staging -Recurse
Copy-Item $Helper $Staging -Force

# 不把运行期垃圾打进安装包
Get-ChildItem $Staging -File | Where-Object {
  $_.Name -match '^(helper\.log|screen_strip_sync_config\.json|.*crash\.log)$'
} | Remove-Item -Force

if (-not (Test-Path (Join-Path $Staging "helper.exe"))) {
  throw "Staging missing helper.exe"
}
if (-not (Test-Path (Join-Path $Staging "screen_strip_sync.exe"))) {
  throw "Staging missing screen_strip_sync.exe"
}

# 旁路部署 MSVC CRT：目标机常无 VCRUNTIME140.dll；不静默装系统级 vc_redist，拷到 {app}。
function Resolve-MsvcCrtDir {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $vswhere) {
    $inst = & $vswhere -latest -products * -property installationPath 2>$null
    if ($inst) {
      $crt = Get-ChildItem (Join-Path $inst "VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT") -Directory -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1
      if ($crt) { return $crt.FullName }
    }
  }
  return $null
}

$crtDir = Resolve-MsvcCrtDir
$crtNames = @("vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll")
if ($crtDir) {
  Write-Host "Bundling CRT from $crtDir"
  foreach ($name in $crtNames) {
    $src = Join-Path $crtDir $name
    if (-not (Test-Path $src)) { throw "Missing CRT DLL: $src" }
    Copy-Item $src $Staging -Force
  }
}
else {
  Write-Host "VS Redist CRT not found; falling back to System32"
  foreach ($name in $crtNames) {
    $src = Join-Path $env:SystemRoot "System32\$name"
    if (-not (Test-Path $src)) { throw "Missing CRT DLL: $src (install VS or VC++ Redistributable)" }
    Copy-Item $src $Staging -Force
  }
}

$utf8Bom = New-Object System.Text.UTF8Encoding $true
$readmePortable = @"
Screen Strip Sync $Version ($Arch)

运行：双击 helper.exe（托盘常驻；界面由 helper 按需拉起）。
勿只开 screen_strip_sync.exe（那是纯前端）。

注意：
- 需要 64 位 Windows 10/11
- Flutter / 本项目不提供 32 位（x86）构建
- 首次使用请插上灯带后在设置里刷新串口

卸载绿色版：退出托盘后删除本文件夹；若开过「开机自启」，到设置关掉或删注册表
HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Screen Strip Sync
"@
[System.IO.File]::WriteAllText(
  (Join-Path $Staging "README.txt"),
  $readmePortable,
  $utf8Bom
)

# Inno 要求简中 .isl 为 UTF-8 BOM，否则语言选择/向导乱码
$ZhIsl = Join-Path $PSScriptRoot "Languages\ChineseSimplified.isl"
if (Test-Path $ZhIsl) {
  $raw = [System.IO.File]::ReadAllBytes($ZhIsl)
  $hasBom = ($raw.Length -ge 3) -and ($raw[0] -eq 0xEF) -and ($raw[1] -eq 0xBB) -and ($raw[2] -eq 0xBF)
  if (-not $hasBom) {
    $text = [System.IO.File]::ReadAllText($ZhIsl, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($ZhIsl, $text, (New-Object System.Text.UTF8Encoding $true))
    Write-Host "Fixed UTF-8 BOM on ChineseSimplified.isl"
  }
}

New-Item -ItemType Directory $OutDir -Force | Out-Null

# 清掉旧命名产物，避免 GitHub 上传混淆
Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue | Where-Object {
  $_.Name -like "ScreenStripSync-*"
} | Remove-Item -Force

if ($Iscc) {
  $issText = [System.IO.File]::ReadAllText($Iss, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText($Iss, $issText, $utf8Bom)
  Write-Host "Compiling with $Iscc"
  & $Iscc $Iss
  if ($LASTEXITCODE -ne 0) { throw "ISCC failed: $LASTEXITCODE" }
}
else {
  Write-Host "ISCC.exe not found — skip installer (winget install JRSoftware.InnoSetup)."
}

$ZipPath = Join-Path $OutDir $ZipName
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Write-Host "Zipping -> $ZipPath"
$ZipStageRoot = Join-Path $OutDir ("_zip_stage_ScreenStripSync-$Version-$Arch")
if (Test-Path $ZipStageRoot) { Remove-Item $ZipStageRoot -Recurse -Force }
New-Item -ItemType Directory $ZipStageRoot | Out-Null
Copy-Item (Join-Path $Staging "*") $ZipStageRoot -Recurse
Compress-Archive -Path $ZipStageRoot -DestinationPath $ZipPath -CompressionLevel Optimal
Remove-Item $ZipStageRoot -Recurse -Force

# SHA256 清单（方便 GitHub Release 校验）
$hashes = Join-Path $OutDir "SHA256SUMS.txt"
$lines = @()
Get-ChildItem $OutDir -File | Where-Object {
  $_.Name -like "ScreenStripSync-*" -and ($_.Extension -in ".exe", ".zip")
} | Sort-Object Name | ForEach-Object {
  $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  $lines += "$h  $($_.Name)"
  Write-Host ("OK: {0} ({1:N1} MB) sha256={2}" -f $_.Name, ($_.Length / 1MB), $h.Substring(0, 12))
}
[System.IO.File]::WriteAllLines($hashes, $lines)
Write-Host "Wrote $hashes"

$note = @"
Release 产物（本目录）

- ScreenStripSync-$Version-windows-x64-Setup.exe  … Inno 安装包（有 ISCC 时）
- ScreenStripSync-$Version-windows-x64.zip         … 绿色版（解压后运行 helper.exe）
- SHA256SUMS.txt

关于 32 位（x86）：
当前 Flutter stable（桌面 Windows）只提供 x64 引擎与工具链，本项目依赖 DXGI Desktop
Duplication + Flutter UI，无法产出可用的 Windows x86 安装包。请在 64 位 Windows 10/11 上使用。
"@
[System.IO.File]::WriteAllText(
  (Join-Path $OutDir "README-GitHub.txt"),
  $note,
  $utf8Bom
)
Write-Host "Done. Test from: $Staging\helper.exe  or  $ZipPath"
