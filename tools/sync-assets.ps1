# =====================================================================
#  Sync the creator's working folder (the one containing 03_*.png) into
#  assets/, which is what the game actually loads.  Run it after editing
#  any source image, then refresh the browser -- the game cache-busts
#  every asset with a timestamp.
#
#  ASCII-ONLY ON PURPOSE.  PowerShell 5.1 decodes a UTF-8 script without a
#  BOM as ANSI, so ANY Chinese literal here would be mangled and break the
#  parser.  Character names are therefore read out of the game HTML
#  (explicitly decoded as UTF-8) instead of being hard-coded.
# =====================================================================
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$DST  = Join-Path $ROOT 'assets'
New-Item -ItemType Directory -Force -Path $DST | Out-Null

# ---- source folder = the one containing 03_*.png ----
$SRC = $null
foreach ($d in (Get-ChildItem $ROOT -Directory)) {
  if (Get-ChildItem $d.FullName -Filter '03_*.png' -File -ErrorAction SilentlyContinue) { $SRC = $d.FullName; break }
}
if (-not $SRC) { throw 'source image folder not found (no 03_*.png anywhere)' }
Write-Output "source: $(Split-Path -Leaf $SRC)"

# ---- game html = largest *.html that is neither index.html nor *bundle* ----
$GAME = (Get-ChildItem $ROOT -Filter *.html -File |
         Where-Object { $_.Name -notmatch 'bundle' -and $_.Name -ne 'index.html' } |
         Sort-Object Length -Descending | Select-Object -First 1).FullName
if (-not $GAME) { throw 'game html not found' }
Write-Output "game:   $(Split-Path -Leaf $GAME)"

function Newest($pattern, $exclude) {
  return (Get-ChildItem $SRC -Filter $pattern -File -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -notmatch $exclude } |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}
function Save-Png($bmp, $name) {
  $p = Join-Path $DST $name
  $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  Write-Output ("  {0,-22} {1,6} KB" -f $name, [Math]::Round((Get-Item $p).Length / 1KB))
}
function Save-Jpg($bmp, $name, $quality) {
  $p = Join-Path $DST $name
  $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $ps = New-Object System.Drawing.Imaging.EncoderParameters -ArgumentList 1
  $ps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter -ArgumentList ([System.Drawing.Imaging.Encoder]::Quality), $quality
  $bmp.Save($p, $enc, $ps); $bmp.Dispose()
  Write-Output ("  {0,-22} {1,6} KB" -f $name, [Math]::Round((Get-Item $p).Length / 1KB))
}
function Resize-To($path, $w, $h, $alpha) {
  $img = [System.Drawing.Bitmap]::FromFile($path)
  $fmt = if ($alpha) { [System.Drawing.Imaging.PixelFormat]::Format32bppArgb }
         else { [System.Drawing.Imaging.PixelFormat]::Format24bppRgb }
  $bmp = New-Object System.Drawing.Bitmap -ArgumentList $w, $h, $fmt
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($img, 0, 0, $w, $h); $g.Dispose(); $img.Dispose()
  return $bmp
}

# ---- board plate (keeps alpha: the portrait slots are cut out) ----
$b = Newest '03_*.png' '\(3\)'
if ($b) { Save-Png (Resize-To $b.FullName 1600 900 $true) 'bg-board.png' }

# ---- coin screen (keeps alpha: the coin slot is cut out) ----
$cn = Newest '01_*.png' '\(3\)'
if ($cn) { Save-Png (Resize-To $cn.FullName 1600 900 $true) 'bg-coin2.png' }

# ---- start screen ----
$st = Newest '00_*.png' 'zzz'
if ($st) { Save-Jpg (Resize-To $st.FullName 1600 900 $false) 'bg-start.jpg' 90 }

# ---- menu background (arbitrary aspect; CSS cover-fits it) ----
$mn = Get-ChildItem $SRC -Filter '*.png' -File |
      Where-Object { $_.Name -notmatch '^\d\d_' -and $_.Length -gt 400KB -and $_.Length -lt 700KB } |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($mn) {
  $img = [System.Drawing.Bitmap]::FromFile($mn.FullName)
  $w = 1600; $h = [int]($img.Height * $w / $img.Width)
  $bmp = New-Object System.Drawing.Bitmap -ArgumentList $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($img, 0, 0, $w, $h); $g.Dispose(); $img.Dispose()
  Save-Jpg $bmp 'bg-menu.jpg' 88
}

# ---- portraits: id -> display name is parsed from CARDS in the game html,
#      so this script never needs a Chinese literal of its own ----
$html = [IO.File]::ReadAllText($GAME, [Text.Encoding]::UTF8)
$map = [regex]::Matches($html, "(\w+):\{\s*name:'([^']+)',\s*role:")
Write-Output "portraits: $($map.Count) characters found in CARDS"
foreach ($m in $map) {
  $id = $m.Groups[1].Value
  $nm = $m.Groups[2].Value
  $p  = Join-Path $SRC ($nm + '.png')
  if (-not (Test-Path $p)) { Write-Output "  MISSING $nm.png"; continue }
  $img = [System.Drawing.Bitmap]::FromFile($p)
  $size = 256
  $sq = New-Object System.Drawing.Bitmap -ArgumentList $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($sq)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $r = [Math]::Max($size / $img.Width, $size / $img.Height)
  $w2 = [int]($img.Width * $r); $h2 = [int]($img.Height * $r)
  $g.DrawImage($img, [int](($size - $w2) / 2), [int](($size - $h2) / 2), $w2, $h2)
  $g.Dispose(); $img.Dispose()
  Save-Png $sq ('av-' + $id + '.png')
}

Write-Output ''
Write-Output 'done. refresh the browser to see changes.'
Write-Output 'NOT synced (one-off slicing; overwrite the png directly): die-d4/d6/d8.png, die-ace.png'
