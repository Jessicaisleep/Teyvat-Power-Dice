# =====================================================================
#  Bundle the game into a single-file HTML (every asset inlined base64).
#
#  The source file is auto-detected as: the largest *.html that is neither
#  index.html nor a *.bundle.html.  That avoids hard-coding the CJK file
#  name, because PowerShell 5.1 decodes UTF-8 scripts without a BOM as
#  ANSI and would mangle any Chinese literal in this file.
#
#  Output: <source-name>.bundle.html next to the source.
# =====================================================================
$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

$SRC = (Get-ChildItem $ROOT -Filter *.html -File |
        Where-Object { $_.Name -notmatch 'bundle' -and $_.Name -ne 'index.html' } |
        Sort-Object Length -Descending | Select-Object -First 1).FullName
if (-not $SRC) { throw 'no source html found' }
$DST = [IO.Path]::Combine($ROOT, [IO.Path]::GetFileNameWithoutExtension($SRC) + '.bundle.html')
Write-Output "source: $(Split-Path -Leaf $SRC)"

$html = [IO.File]::ReadAllText($SRC, [Text.Encoding]::UTF8)

# A data: URI must not carry the cache-busting query, so unwrap asset() first.
$html = $html -replace "asset\('(assets/[^']+)'\)", "'`$1'"

$map = [ordered]@{
  'assets/bg-start.jpg'   = 'image/jpeg'
  'assets/bg-coin2.png'   = 'image/png'
  'assets/bg-board.png'   = 'image/png'
  'assets/bg-menu.jpg'    = 'image/jpeg'
  'assets/die-d4.png'     = 'image/png'
  'assets/die-d6.png'     = 'image/png'
  'assets/die-d8.png'     = 'image/png'
  'assets/die-ace.png'    = 'image/png'
  'assets/av-hutao.png'   = 'image/png'
  'assets/av-xiao.png'    = 'image/png'
  'assets/av-zhongli.png' = 'image/png'
  'assets/av-raiden.png'  = 'image/png'
  'assets/av-bennett.png' = 'image/png'
  'assets/av-xingqiu.png' = 'image/png'
  'assets/av-venti.png'   = 'image/png'
  'assets/av-ayaka.png'   = 'image/png'
  'assets/av-nahida.png'  = 'image/png'
  'assets/av-neuvil.png'  = 'image/png'
  'assets/av-ganyu.png'   = 'image/png'
  'assets/av-columb.png'  = 'image/png'
}

$total = 0
foreach ($k in $map.Keys) {
  $p = Join-Path $ROOT ($k -replace '/', '\')
  if (-not (Test-Path $p)) { Write-Output "  MISSING $k"; continue }
  $bytes = [IO.File]::ReadAllBytes($p)
  $total += $bytes.Length
  $html = $html.Replace($k, "data:$($map[$k]);base64," + [Convert]::ToBase64String($bytes))
  Write-Output ("  inlined {0,-22} {1,6} KB" -f $k, [Math]::Round($bytes.Length / 1KB))
}

[IO.File]::WriteAllText($DST, $html, (New-Object Text.UTF8Encoding($false)))

# self-check: nothing may still point at assets/
$left = ([regex]::Matches($html, 'assets/')).Count
Write-Output ''
Write-Output ''
Write-Output ("bundled -> {0}  ({1} KB, assets {2} KB)" -f `
  (Split-Path -Leaf $DST), [Math]::Round((Get-Item $DST).Length / 1KB), [Math]::Round($total / 1KB))
if ($left -gt 0) { Write-Output "  WARNING: $left references to assets/ remain" }
else { Write-Output '  OK: self-contained, no external references' }