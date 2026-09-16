# =====================================================================
#  Alignment check v3: boxes + CJK-metric glyph placeholders (one square
#  per character, 1em wide) so wrapping inside the banner can be judged.
#  ASCII-ONLY on purpose: PS 5.1 mis-decodes UTF-8 script files.
# =====================================================================
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$b = [System.Drawing.Bitmap]::FromFile((Join-Path $ROOT 'assets\bg-board.png'))
$W = $b.Width; $H = $b.Height
$g = [System.Drawing.Graphics]::FromImage($b)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$cqh = $H / 100.0

$boxes = @(
  @('skillTop',   38.40,  4.00, 34.20, 11.00, '255,60,60',   46),
  @('skillBot',   40.00, 83.40, 22.00, 11.00, '60,255,120',  38),
  @('hpTop',      32.88,  5.56,  4.13,  8.00, '255,220,0',    0),
  @('hpBot',      62.20, 84.80,  5.00,  8.90, '255,220,0',    0),
  @('avTop',      21.30,  0.10,  9.70, 17.20, '255,120,255',  0),
  @('avBot',      68.20, 79.50,  9.70, 17.20, '255,120,255',  0),
  @('avMiniTop',  16.20, 36.60,  5.00,  8.90, '255,120,255',  0),
  @('avMiniBot',  16.00, 55.60,  5.20,  9.20, '255,120,255',  0),
  @('hotAce',     89.05, 41.36,  6.50, 11.56, '0,255,255',    0),
  @('hotReroll',  87.88, 60.00,  8.25, 14.67, '0,255,255',    0),
  @('hotOk',      87.88, 78.00,  8.25, 14.67, '0,255,255',    0),
  @('roundBox',   16.45, 45.80,  4.70,  8.35, '255,255,255',  0),
  @('midBox',     20.00, 23.00, 58.00, 55.00, '140,255,255',  0)
)
$lblFont = New-Object System.Drawing.Font -ArgumentList 'Arial', 13, ([System.Drawing.FontStyle]::Bold)
foreach ($x in $boxes) {
  $p = $x[5] -split ','
  $col = [System.Drawing.Color]::FromArgb(255, $p[0], $p[1], $p[2])
  $pen = New-Object System.Drawing.Pen -ArgumentList $col, 3
  $px=[int]($W*$x[1]/100); $py=[int]($H*$x[2]/100)
  $pw=[int]($W*$x[3]/100); $ph=[int]($H*$x[4]/100)
  $g.DrawRectangle($pen,$px,$py,$pw,$ph)
  $bg = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(215,0,0,0))
  $tb = New-Object System.Drawing.SolidBrush -ArgumentList $col
  $sz = $g.MeasureString($x[0], $lblFont)
  $g.FillRectangle($bg,$px,$py,$sz.Width+4,$sz.Height)
  $g.DrawString($x[0],$lblFont,$tb,$px+2,$py)
  $pen.Dispose()

  # CJK-metric glyph squares: 1em per char, 1.55em line height
  $n = [int]$x[6]
  if ($n -le 0) { continue }
  $em = $cqh * 1.28
  $boxW = $pw; $boxH = $ph
  $perLine = [Math]::Max(1, [Math]::Floor($boxW / $em))
  $glyph = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(150,219,230,247))
  for ($i = 0; $i -lt $n; $i++) {
    $row = [Math]::Floor($i / $perLine); $colI = $i % $perLine
    $gx = $px + $colI * $em
    $gy = $py + $row * $em * 1.55
    if ($gy + $em -gt $py + $boxH) { break }   # would be clipped by overflow:hidden
    $g.FillRectangle($glyph, $gx + 1, $gy + 2, $em - 2, $em - 4)
  }
}
# red crosshair markers
foreach ($q in @(@('nameTop',22.4,15.9),@('nameBot',68.3,95.2),@('buffTop',38.4,16.5),@('buffBot',40.0,78.4))) {
  $pen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(255,255,0,0)), 4
  $px=[int]($W*$q[1]/100); $py=[int]($H*$q[2]/100)
  $g.DrawLine($pen,$px-14,$py,$px+14,$py); $g.DrawLine($pen,$px,$py-14,$px,$py+14)
  $pen.Dispose()
}
$g.Dispose()
$out = Join-Path $ROOT 'assets\_align.png'
$b.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$b.Dispose()
Write-Output "written assets\_align.png  ($([Math]::Round((Get-Item $out).Length/1KB)) KB)"
