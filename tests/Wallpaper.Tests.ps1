$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $repoRoot 'src\AulaGuard.Security.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\AulaGuard.Core.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\AulaGuard.Policy.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\AulaGuard.Wallpaper.psm1') -Force

function Require([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "Wallpaper regression failed: $Message" } }
function MustThrow([scriptblock]$Action,[string]$Message) {
    $failed=$false; try { & $Action | Out-Null } catch { $failed=$true }
    Require $failed $Message
}

$folder = Join-Path $env:ProgramData ('AulaGuardAssetsTest-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $env:TEMP ('AulaGuard-image-test-' + [guid]::NewGuid().ToString('N') + '.png')
try {
    $bitmap = [Drawing.Bitmap]::new(512,320)
    try {
        $g = [Drawing.Graphics]::FromImage($bitmap)
        try { $g.Clear([Drawing.Color]::ForestGreen) } finally { $g.Dispose() }
        $bitmap.Save($source,[Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
    $installed = Publish-AulaGuardWallpaper -SourcePath $source -AssetsRoot $folder
    Require (Test-Path -LiteralPath $installed -PathType Leaf) 'Published wallpaper missing'
    Require ($installed -like '*.jpg') 'Published wallpaper must be normalized JPEG'
    Require ($installed.StartsWith($folder,[StringComparison]::OrdinalIgnoreCase)) 'Published outside institutional cache'
    Require ((Test-AulaGuardWallpaperFile -Path $installed -AssetsRoot $folder) -eq $installed) 'Wallpaper was not verified'
    Write-Host '[OK] Institutional image normalized to verified Windows-readable JPEG'

    $acl = Get-Acl -LiteralPath $installed
    $users = 'S-1-5-32-545'
    $userAces = @($acl.Access | Where-Object {
        $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq $users -and
        $_.AccessControlType -eq 'Allow'
    })
    Require ($userAces.Count -gt 0) 'Standard users need read permission'
    foreach ($ace in $userAces) {
        Require (($ace.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write) -eq 0) 'Standard user must not have write permission'
    }
    Write-Host '[OK] Read-only access granted to standard users; write access denied'

    MustThrow { Test-AulaGuardWallpaperFile -Path $source -AssetsRoot $folder } 'Private Downloads path must be rejected'
    MustThrow { Publish-AulaGuardWallpaper -SourcePath 'C:\Nonexistent\missing.png' -AssetsRoot $folder } 'Missing wallpaper should never be saved'
    $badSettings = New-AulaGuardSettings
    $badSettings.policyMode = 'Enforce'
    $badSettings.wallpaper = 'C:\Users\Administrator\Downloads\private.jpg'
    MustThrow { Apply-AulaGuardPolicies -Settings $badSettings } 'Invalid wallpaper should fail before changes are applied'
    Write-Host '[OK] Invalid / private wallpaper rejected before registry modification'

    Require ((Publish-AulaGuardWallpaper -SourcePath $installed -AssetsRoot $folder) -eq $installed) 'Cache path should be idempotent'
    Write-Host '[OK] Re-saving the approved cached image is safe'

    Write-Host 'PASS: wallpaper access, integrity and recovery regressions'
} finally {
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue
}
