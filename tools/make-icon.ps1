# Renders the 1024x1024 app icon: black background, two systemBlue rings and a
# crosshair, approximating the SF Symbol "scope".
param([string]$Out = "$PSScriptRoot\..\App\Assets.xcassets\AppIcon.appiconset\icon-1024.png")

Add-Type -AssemblyName System.Drawing

$size = 1024
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Black)

$blue = [System.Drawing.Color]::FromArgb(255, 10, 132, 255)
$glow = [System.Drawing.Color]::FromArgb(70, 10, 132, 255)
$c = $size / 2

function Ring($radius, $width, $color) {
    $pen = New-Object System.Drawing.Pen $color, $width
    $g.DrawEllipse($pen, $c - $radius, $c - $radius, 2 * $radius, 2 * $radius)
    $pen.Dispose()
}

Ring 330 90 $glow
Ring 330 44 $blue
Ring 150 36 $blue

$pen = New-Object System.Drawing.Pen $blue, 40
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($pen, $c, 120, $c, 380)
$g.DrawLine($pen, $c, 644, $c, 904)
$g.DrawLine($pen, 120, $c, 380, $c)
$g.DrawLine($pen, 644, $c, 904, $c)
$pen.Dispose()

$brush = New-Object System.Drawing.SolidBrush $blue
$g.FillEllipse($brush, $c - 26, $c - 26, 52, 52)
$brush.Dispose()

New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$bmp.Save((Resolve-Path -LiteralPath (Split-Path $Out)).Path + "\" + (Split-Path $Out -Leaf), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
Write-Output "wrote $Out"
