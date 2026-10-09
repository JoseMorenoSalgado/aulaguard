Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing -ErrorAction Stop

# Secure institutional wallpaper cache: readable by standard students, writable
# only by SYSTEM / local Administrators, separate from signed private settings.
function Get-AulaGuardWallpaperDirectory {
    param([string]$AssetsRoot = (Join-Path $env:ProgramData 'AulaGuardAssets'))
    $base = [IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\') + '\'
    $actual = [IO.Path]::GetFullPath($AssetsRoot)
    if (-not $actual.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Parent $actual).TrimEnd('\') -ine $env:ProgramData.TrimEnd('\') -or
        (Split-Path -Leaf $actual) -notmatch '^AulaGuardAssets(?:Test-[a-f0-9]{32})?$') {
        throw 'Ruta de recursos institucionales fuera de ProgramData.'
    }
    return $actual
}

function Assert-AulaGuardWallpaperCache {
    param([string]$AssetsRoot = (Join-Path $env:ProgramData 'AulaGuardAssets'),[switch]$Create)
    Assert-AulaGuardElevated
    $folder = Get-AulaGuardWallpaperDirectory -AssetsRoot $AssetsRoot
    $admins = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $users = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    if (-not (Test-Path -LiteralPath $folder)) {
        if (-not $Create) { throw 'Carpeta de fondo institucional no encontrada.' }
        [void](New-Item -ItemType Directory -Path $folder -ErrorAction Stop)
    }
    $item = Get-Item -LiteralPath $folder -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Carpeta de fondo institucional insegura: enlace o tipo inválido.'
    }
    $current = Get-Acl -LiteralPath $folder -ErrorAction Stop
    $owner = $current.GetOwner([Security.Principal.SecurityIdentifier]).Value
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if (@($admins.Value,$system.Value,$identity) -notcontains $owner) {
        throw 'La carpeta de fondo institucional no pertenece a un administrador confiable.'
    }
    # Reset explicit ACLs to avoid inherited write access for students.
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner($admins)
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
    foreach ($principal in @($admins,$system)) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $principal,[Security.AccessControl.FileSystemRights]::FullControl,
            $inherit,[Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
        [void]$acl.AddAccessRule($rule)
    }
    $read = [Security.AccessControl.FileSystemAccessRule]::new(
        $users,[Security.AccessControl.FileSystemRights]::ReadAndExecute,
        $inherit,[Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow)
    [void]$acl.AddAccessRule($read)
    Set-Acl -LiteralPath $folder -AclObject $acl -ErrorAction Stop
    return $folder
}

function Test-AulaGuardWallpaperFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$AssetsRoot = (Join-Path $env:ProgramData 'AulaGuardAssets')
    )
    $dir = Get-AulaGuardWallpaperDirectory -AssetsRoot $AssetsRoot
    $expected = [IO.Path]::GetFullPath((Join-Path $dir 'institutional.jpg'))
    $actual = [IO.Path]::GetFullPath($Path)
    if ($actual -ine $expected) { throw 'La imagen debe estar en la carpeta institucional protegida.' }
    $file = Get-Item -LiteralPath $actual -Force -ErrorAction Stop
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'La imagen institucional no es un archivo normal.'
    }
    if ($file.Length -lt 1024 -or $file.Length -gt 25000000) {
        throw 'La imagen institucional está vacía o supera el límite de 25 MB.'
    }
    $users = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    $acl = Get-Acl -LiteralPath $file.FullName -ErrorAction Stop
    $aclRead = @($acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadData) -ne 0 -and
        $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq $users.Value
    })
    if ($aclRead.Count -eq 0) { throw 'Los estudiantes no tienen acceso de lectura a la imagen.' }
    $stream = [IO.File]::Open($actual,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $image = [Drawing.Image]::FromStream($stream,$false,$true)
        try {
            if ($image.Width -lt 1 -or $image.Height -lt 1) { throw 'Imagen con dimensiones inválidas.' }
        } finally { $image.Dispose() }
    } finally { $stream.Dispose() }
    return $actual
}

function Publish-AulaGuardWallpaper {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [string]$AssetsRoot = (Join-Path $env:ProgramData 'AulaGuardAssets')
    )
    Assert-AulaGuardElevated
    if ([string]::IsNullOrWhiteSpace($SourcePath)) { throw 'Selecciona primero una imagen institucional.' }
    $folder = Assert-AulaGuardWallpaperCache -AssetsRoot $AssetsRoot -Create
    $target = Join-Path $folder 'institutional.jpg'
    if ([IO.Path]::GetFullPath($SourcePath) -ieq [IO.Path]::GetFullPath($target)) {
        return (Test-AulaGuardWallpaperFile -Path $target -AssetsRoot $AssetsRoot)
    }
    $source = Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
    if ($source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $source.Extension -notin @('.jpg','.jpeg','.png','.bmp')) {
        throw 'Solo se admiten imágenes JPG, PNG o BMP sin enlaces.'
    }
    if ($source.Length -gt 25000000 -or $source.Length -lt 100) {
        throw 'La imagen de origen debe ocupar entre 100 bytes y 25 MB.'
    }

    $temp = Join-Path $folder ('wallpaper-' + [guid]::NewGuid().ToString('N') + '.jpg')
    try {
        $inputStream = [IO.File]::Open($source.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            $original = [Drawing.Image]::FromStream($inputStream,$false,$true)
            try {
                if ($original.Width -lt 128 -or $original.Height -lt 128 -or
                    $original.Width -gt 10000 -or $original.Height -gt 10000) {
                    throw 'La imagen debe tener entre 128 y 10 000 píxeles por dimensión.'
                }
                $ratio = [Math]::Min(1.0,[Math]::Min(3200.0 / $original.Width,1800.0 / $original.Height))
                $width = [Math]::Max(128,[int][Math]::Round($original.Width * $ratio))
                $height = [Math]::Max(128,[int][Math]::Round($original.Height * $ratio))
                $bitmap = [Drawing.Bitmap]::new($width,$height)
                try {
                    $graphics = [Drawing.Graphics]::FromImage($bitmap)
                    try {
                        $graphics.Clear([Drawing.Color]::White)
                        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                        $graphics.DrawImage($original,0,0,$width,$height)
                    } finally { $graphics.Dispose() }
                    $bitmap.Save($temp,[Drawing.Imaging.ImageFormat]::Jpeg)
                } finally { $bitmap.Dispose() }
            } finally { $original.Dispose() }
        } finally { $inputStream.Dispose() }
        $tempFile = Get-Item -LiteralPath $temp -Force -ErrorAction Stop
        if ($tempFile.Length -lt 1024) { throw 'No se pudo generar una imagen institucional válida.' }
        Move-Item -LiteralPath $temp -Destination $target -Force -ErrorAction Stop
        # The directory has protected inheritance for the final file.
        $fileAcl = Get-Acl -LiteralPath $folder -ErrorAction Stop
        $file = Get-Item -LiteralPath $target -Force
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Archivo institucional redirigido inesperadamente.'
        }
        return (Test-AulaGuardWallpaperFile -Path $target -AssetsRoot $AssetsRoot)
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Publish-AulaGuardWallpaper,Test-AulaGuardWallpaperFile,Get-AulaGuardWallpaperDirectory
