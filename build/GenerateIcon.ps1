param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'AulaGuard.ico')
)

Add-Type -AssemblyName System.Drawing

$size = 256
$bitmap = New-Object System.Drawing.Bitmap($size, $size)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)

$blue = [System.Drawing.Color]::FromArgb(15,76,129)
$white = [System.Drawing.Color]::White

$shield = New-Object System.Drawing.Drawing2D.GraphicsPath
$points = [System.Drawing.Point[]]@(
    (New-Object System.Drawing.Point(128,18)),
    (New-Object System.Drawing.Point(224,52)),
    (New-Object System.Drawing.Point(214,145)),
    (New-Object System.Drawing.Point(188,195)),
    (New-Object System.Drawing.Point(128,238)),
    (New-Object System.Drawing.Point(68,195)),
    (New-Object System.Drawing.Point(42,145)),
    (New-Object System.Drawing.Point(32,52))
)
$shield.AddPolygon($points)

$brush = New-Object System.Drawing.SolidBrush($blue)
$graphics.FillPath($brush, $shield)

$font = New-Object System.Drawing.Font('Segoe UI',72,[System.Drawing.FontStyle]::Bold,[System.Drawing.GraphicsUnit]::Pixel)
$format = New-Object System.Drawing.StringFormat
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center

$textBrush = New-Object System.Drawing.SolidBrush($white)
$rect = New-Object System.Drawing.RectangleF(0,44,$size,150)
$graphics.DrawString('AG',$font,$textBrush,$rect,$format)

$icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
$stream = [System.IO.File]::Create($OutputPath)
$icon.Save($stream)
$stream.Close()

$icon.Dispose()
$textBrush.Dispose()
$font.Dispose()
$brush.Dispose()
$shield.Dispose()
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "Icono generado: $OutputPath"
