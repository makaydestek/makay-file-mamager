# Makay app icon + TV banner generator (GDI+).
# Design: dark petrol -> teal diagonal gradient, "Makay" wordmark on top,
# white folder with documents in the center. Style matches Makay app family.
# ASCII-only script (Turkish banner text uses [char] escapes).
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$outDir = Join-Path $PSScriptRoot 'generated'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function Draw-MakayIconCore([System.Drawing.Graphics]$g, [double]$S, [bool]$withText) {
  $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(30, 0, 18, 22))
  $g.FillEllipse($shadow, (128*$S), (402*$S), (260*$S), (44*$S))

  $tabBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 214, 224, 228))
  $backBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 198, 210, 215))
  $sheetBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
  $lineBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 128, 203, 196))

  # tab
  $tab = New-RoundedRectPath (134*$S) (200*$S) (124*$S) (56*$S) (16*$S)
  $g.FillPath($tabBrush, $tab)
  # back panel
  $back = New-RoundedRectPath (118*$S) (222*$S) (276*$S) (192*$S) (26*$S)
  $g.FillPath($backBrush, $back)
  # documents peeking with teal lines
  $sheet = New-RoundedRectPath (152*$S) (210*$S) (208*$S) (96*$S) (12*$S)
  $g.FillPath($sheetBrush, $sheet)
  foreach ($line in @(@(170, 232, 150), @(170, 252, 172), @(170, 272, 118))) {
    $lr = New-RoundedRectPath ($line[0]*$S) ($line[1]*$S) ($line[2]*$S) (10*$S) (5*$S)
    $g.FillPath($lineBrush, $lr)
  }
  # front panel (white gradient)
  $front = New-RoundedRectPath (118*$S) (266*$S) (276*$S) (150*$S) (26*$S)
  $p1 = [System.Drawing.PointF]::new(0, (266*$S))
  $p2 = [System.Drawing.PointF]::new(0, (416*$S))
  $cW = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
  $cG = [System.Drawing.Color]::FromArgb(255, 222, 231, 235)
  $fgrad = [System.Drawing.Drawing2D.LinearGradientBrush]::new($p1, $p2, $cW, $cG)
  $g.FillPath($fgrad, $front)

  if ($withText) {
    $font = [System.Drawing.Font]::new('Segoe UI', (108*$S), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = [System.Drawing.StringFormat]::new()
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $sbr = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(110, 0, 16, 20))
    $rShadow = [System.Drawing.RectangleF]::new((2*$S), (46*$S), (512*$S), (150*$S))
    $g.DrawString('Makay', $font, $sbr, $rShadow, $fmt)
    $tbr = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 232, 247, 246))
    $rText = [System.Drawing.RectangleF]::new(0, (42*$S), (512*$S), (150*$S))
    $g.DrawString('Makay', $font, $tbr, $rText, $fmt)
  }
}

function New-MakayMaster([int]$Px, [bool]$rounded, [bool]$withText) {
  $bmp = [System.Drawing.Bitmap]::new($Px, $Px)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $S = $Px / 512.0
  $c1 = [System.Drawing.Color]::FromArgb(255, 3, 48, 54)
  $c2 = [System.Drawing.Color]::FromArgb(255, 0, 150, 136)

  if ($rounded) {
    $shape = New-RoundedRectPath 0 0 $Px $Px (112*$S)
  } else {
    $shape = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $shape.AddRectangle([System.Drawing.Rectangle]::new(0, 0, $Px, $Px))
  }
  $bp1 = [System.Drawing.PointF]::new(0, 0)
  $bp2 = [System.Drawing.PointF]::new($Px, $Px)
  $bg = [System.Drawing.Drawing2D.LinearGradientBrush]::new($bp1, $bp2, $c1, $c2)
  $g.FillPath($bg, $shape)

  $g.SetClip($shape)
  # highlight from top-left
  $pg = [System.Drawing.Drawing2D.PathGradientBrush]::new($shape)
  $pg.CenterPoint = [System.Drawing.PointF]::new((0.30*$Px), (0.12*$Px))
  $pg.CenterColor = [System.Drawing.Color]::FromArgb(80, 255, 255, 255)
  $pg.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
  $g.FillPath($pg, $shape)
  # gloss ellipse on top
  $gloss = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $gloss.AddEllipse((-60*$S), (-340*$S), (632*$S), (430*$S))
  $gbr = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(26, 255, 255, 255))
  $g.FillPath($gbr, $gloss)
  # bottom shade
  $gp1 = [System.Drawing.PointF]::new(0, (0.62*$Px))
  $gp2 = [System.Drawing.PointF]::new(0, $Px)
  $sd1 = [System.Drawing.Color]::FromArgb(0, 0, 18, 22)
  $sd2 = [System.Drawing.Color]::FromArgb(50, 0, 18, 22)
  $sg = [System.Drawing.Drawing2D.LinearGradientBrush]::new($gp1, $gp2, $sd1, $sd2)
  $g.FillRectangle($sg, 0, (0.62*$Px), $Px, (0.38*$Px))

  Draw-MakayIconCore $g $S $withText
  $g.ResetClip()
  $g.Dispose()
  return $bmp
}

function Save-Downscale([System.Drawing.Bitmap]$master, [string]$path, [int]$px) {
  $bmp = [System.Drawing.Bitmap]::new($px, $px)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.DrawImage($master, 0, 0, $px, $px)
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output ("  -> " + $path)
}

# --- 1) Master 1024 (rounded, with text) ---
$master = New-MakayMaster 1024 $true $true
$master.Save((Join-Path $outDir 'makay_master_1024.png'), [System.Drawing.Imaging.ImageFormat]::Png)

# Legacy Android mipmap sizes
Save-Downscale $master (Join-Path $outDir 'ic_launcher_48.png') 48
Save-Downscale $master (Join-Path $outDir 'ic_launcher_72.png') 72
Save-Downscale $master (Join-Path $outDir 'ic_launcher_96.png') 96
Save-Downscale $master (Join-Path $outDir 'ic_launcher_144.png') 144
Save-Downscale $master (Join-Path $outDir 'ic_launcher_192.png') 192

# Web icons
Save-Downscale $master (Join-Path $outDir 'web_512.png') 512
Save-Downscale $master (Join-Path $outDir 'web_192.png') 192
$master.Dispose()

# --- 2) Maskable web icons: full-bleed square, content at 80% ---
$mbCore = [System.Drawing.Bitmap]::new(1024, 1024)
$g2 = [System.Drawing.Graphics]::FromImage($mbCore)
$g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g2.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$rectFull = [System.Drawing.Rectangle]::new(0, 0, 1024, 1024)
$c1f = [System.Drawing.Color]::FromArgb(255, 3, 48, 54)
$c2f = [System.Drawing.Color]::FromArgb(255, 0, 150, 136)
$fp1 = [System.Drawing.PointF]::new(0, 0)
$fp2 = [System.Drawing.PointF]::new(1024, 1024)
$fbg = [System.Drawing.Drawing2D.LinearGradientBrush]::new($fp1, $fp2, $c1f, $c2f)
$g2.FillRectangle($fbg, $rectFull)
$g2.FillPath($fbg, (New-RoundedRectPath 0 0 1024 1024 1))
$g2.TranslateTransform(102.4, 102.4)
$g2.ScaleTransform(0.8, 0.8)
Draw-MakayIconCore $g2 2.0 $true
$g2.Dispose()
Save-Downscale $mbCore (Join-Path $outDir 'web_maskable_512.png') 512
Save-Downscale $mbCore (Join-Path $outDir 'web_maskable_192.png') 192
$mbCore.Dispose()

# --- 3) Favicon: simplified (folder only) ---
$fav = New-MakayMaster 256 $true $false
$favSmall = [System.Drawing.Bitmap]::new(48, 48)
$g3 = [System.Drawing.Graphics]::FromImage($favSmall)
$g3.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g3.DrawImage($fav, 0, 0, 48, 48)
$g3.Dispose()
$favSmall.Save((Join-Path $outDir 'favicon_48.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$favSmall.Dispose()
$fav.Dispose()
Write-Output "  -> favicon_48.png"

# --- 4) TV banner 640x360 (2x of 320x180) ---
$bn = [System.Drawing.Bitmap]::new(640, 360)
$g4 = [System.Drawing.Graphics]::FromImage($bn)
$g4.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g4.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$bRect = [System.Drawing.Rectangle]::new(0, 0, 640, 360)
$bp1b = [System.Drawing.PointF]::new(0, 0)
$bp2b = [System.Drawing.PointF]::new(640, 360)
$bc1 = [System.Drawing.Color]::FromArgb(255, 3, 48, 54)
$bc2 = [System.Drawing.Color]::FromArgb(255, 0, 138, 123)
$bgrad = [System.Drawing.Drawing2D.LinearGradientBrush]::new($bp1b, $bp2b, $bc1, $bc2)
$g4.FillRectangle($bgrad, $bRect)
$gloss2 = [System.Drawing.Drawing2D.GraphicsPath]::new()
$gloss2.AddEllipse(-80, -260, 800, 420)
$g4.FillPath(([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(22, 255, 255, 255))), $gloss2)

# folder emblem on the left: draw master scaled into 256x256 box (top-left 512 units)
$embMaster = New-MakayMaster 1024 $false $true
$embDst = [System.Drawing.RectangleF]::new(30, 52, 256, 256)
$embSrc = [System.Drawing.RectangleF]::new(0, 0, 1024, 1024)
$g4.DrawImage($embMaster, $embDst, $embSrc, [System.Drawing.GraphicsUnit]::Pixel)
$embMaster.Dispose()

$fontBig = [System.Drawing.Font]::new('Segoe UI', 64, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fontSub = [System.Drawing.Font]::new('Segoe UI', 30, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 236, 250, 249))
$subBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 178, 223, 219))
$subText = 'Dosya Y' + [char]0x00F6 + 'neticisi'
$g4.DrawString('Makay', $fontBig, $white, [System.Drawing.PointF]::new(312, 92))
$g4.DrawString($subText, $fontSub, $subBrush, [System.Drawing.PointF]::new(316, 184))
$g4.Dispose()
$bn.Save((Join-Path $outDir 'tv_banner_640x360.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bn.Dispose()
Write-Output "  -> tv_banner_640x360.png"

Write-Output 'DONE'
