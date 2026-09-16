# =====================================================================
#  Publish the current build into the git working copy.
#
#  The workspace root is where everything is edited; the git repo lives in
#  a subfolder.  This script mirrors the publishable files across so the
#  creator can commit and push directly, without hand-copying.
#
#  ASCII-ONLY: PowerShell 5.1 decodes UTF-8 scripts without a BOM as ANSI,
#  so a Chinese literal here would be mangled and break the parser.
# =====================================================================
$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# ---- find the git working copy: a subfolder holding index.html + assets ----
$REPO = $null
foreach ($d in (Get-ChildItem $ROOT -Directory)) {
  if ($d.Name -in @('assets','docs','tools')) { continue }
  if ((Test-Path (Join-Path $d.FullName 'index.html')) -and
      (Test-Path (Join-Path $d.FullName 'assets'))) { $REPO = $d.FullName; break }
}
if (-not $REPO) { throw 'git working copy not found (no subfolder with index.html + assets)' }
Write-Output "repo: $(Split-Path -Leaf $REPO)"

# ---- files and folders to mirror ----
$files = @()
$files += Get-ChildItem $ROOT -File -Include *.html,*.md,LICENSE,.gitignore -ErrorAction SilentlyContinue
$files += Get-ChildItem $ROOT -File | Where-Object { $_.Name -match '^\.(gitignore|gitattributes)$' }
$files += Get-ChildItem $ROOT -File -Filter '*.html'
$files += Get-ChildItem $ROOT -File -Filter '*.md'
$files += Get-ChildItem $ROOT -File -Filter 'LICENSE'
$files = $files | Sort-Object FullName -Unique

$n = 0
foreach ($f in $files) {
  Copy-Item $f.FullName (Join-Path $REPO $f.Name) -Force
  Write-Output ("  {0,-30} {1,7} KB" -f $f.Name, [Math]::Round($f.Length / 1KB))
  $n++
}

# ---- mirror the asset / doc folders ----
foreach ($sub in @('assets','docs','tools')) {
  $src = Join-Path $ROOT $sub
  if (-not (Test-Path $src)) { continue }
  $dst = Join-Path $REPO $sub
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  $c = 0
  Get-ChildItem $src -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $dst $_.Name) -Force; $c++
  }
  # drop files in the repo that no longer exist at the source
  Get-ChildItem $dst -File | Where-Object { -not (Test-Path (Join-Path $src $_.Name)) } | ForEach-Object {
    Remove-Item $_.FullName -Force; Write-Output "  removed stale: $sub/$($_.Name)"
  }
  Write-Output ("  {0}/  {1} files" -f $sub, $c)
  $n += $c
}

Write-Output ''
Write-Output "synced $n files -> $(Split-Path -Leaf $REPO)"
Write-Output 'NOT mirrored: the raw image working folder (gitignored) and tmp dirs.'
