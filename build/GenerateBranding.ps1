param(
    [string]$OutputDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

function New-BrandImage {
    param(
        [int]$Width,
        [int]$Height,
        [string]$Path,
        [switch]$Compact
    )

    $bmp = New-Object System.Drawing.Bitmap($Width,$Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $blue = [System.Drawing.Color]::FromArgb(30,64,175)
    $blue2 = [System.Drawing.Color]::FromArgb(37,99,235)
    $white = [System.Drawing.Color]::White
    $soft = [System.Drawing.Color]::FromArgb(219,234,254)

    $rect = New-Object System.Drawing.Rectangle(0,0,$Width,$Height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,$blue,$blue2,90
    )
    $g.FillRectangle($brush,$rect)

    if ($Compact) {
        $badgeSize = [Math]::Min($Width,$Height) - 16
        $badgeX = [Math]::Floor(($Width-$badgeSize)/2)
        $badgeY = [Math]::Floor(($Height-$badgeSize)/2)
        $badge = New-Object System.Drawing.Rectangle($badgeX,$badgeY,$badgeSize,$badgeSize)
        $badgeBrush = New-Object System.Drawing.SolidBrush($white)
        $g.FillEllipse($badgeBrush,$badge)
        $font = New-Object System.Drawing.Font('Segoe UI',18,[System.Drawing.FontStyle]::Bold,[System.Drawing.GraphicsUnit]::Pixel)
        $textBrush = New-Object System.Drawing.SolidBrush($blue)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = 'Center'
        $fmt.LineAlignment = 'Center'
        $g.DrawString('AG',$font,$textBrush,[System.Drawing.RectangleF]$badge,$fmt)
        $fmt.Dispose(); $textBrush.Dispose(); $font.Dispose(); $badgeBrush.Dispose()
    }
    else {
        $badge = New-Object System.Drawing.Rectangle(26,34,112,112)
        $badgeBrush = New-Object System.Drawing.SolidBrush($white)
        $g.FillEllipse($badgeBrush,$badge)

        $agFont = New-Object System.Drawing.Font('Segoe UI',34,[System.Drawing.FontStyle]::Bold,[System.Drawing.GraphicsUnit]::Pixel)
        $agBrush = New-Object System.Drawing.SolidBrush($blue)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = 'Center'
        $fmt.LineAlignment = 'Center'
        $g.DrawString('AG',$agFont,$agBrush,[System.Drawing.RectangleF]$badge,$fmt)

        $titleFont = New-Object System.Drawing.Font('Segoe UI',22,[System.Drawing.FontStyle]::Bold,[System.Drawing.GraphicsUnit]::Pixel)
        $bodyFont = New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel)
        $whiteBrush = New-Object System.Drawing.SolidBrush($white)
        $softBrush = New-Object System.Drawing.SolidBrush($soft)

        $g.DrawString('AulaGuard',$titleFont,$whiteBrush,18,176)
        $g.DrawString('Protección y control',$bodyFont,$softBrush,20,218)
        $g.DrawString('del aula Windows',$bodyFont,$softBrush,20,238)

        $linePen = New-Object System.Drawing.Pen($soft,1)
        $g.DrawLine($linePen,20,276,$Width-20,276)

        $smallFont = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString('Elearning Cloud',$smallFont,$softBrush,20,$Height-34)

        $smallFont.Dispose(); $linePen.Dispose(); $softBrush.Dispose(); $whiteBrush.Dispose()
        $bodyFont.Dispose(); $titleFont.Dispose(); $fmt.Dispose(); $agBrush.Dispose(); $agFont.Dispose(); $badgeBrush.Dispose()
    }

    $bmp.Save($Path,[System.Drawing.Imaging.ImageFormat]::Bmp)
    $brush.Dispose()
    $g.Dispose()
    $bmp.Dispose()
}

New-BrandImage -Width 164 -Height 314 -Path (Join-Path $OutputDir 'WizardImage.bmp')
New-BrandImage -Width 55 -Height 55 -Path (Join-Path $OutputDir 'WizardSmallImage.bmp') -Compact

Write-Host "Branding de instalador generado en $OutputDir"
