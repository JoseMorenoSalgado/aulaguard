param(
    [string]$OutputDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$src = Join-Path $repoRoot 'src'
$icon = Join-Path $PSScriptRoot 'AulaGuard.ico'

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not (Test-Path $icon)) {
    & (Join-Path $PSScriptRoot 'GenerateIcon.ps1') -OutputPath $icon
}

# Use a reviewed, explicitly pinned packaging tool instead of updating to
# whichever PowerShell Gallery version happens to be latest on build day.
$ps2exeVersion = '1.0.18'
$module = @(Get-Module -ListAvailable -Name ps2exe | Where-Object { $_.Version.ToString() -eq $ps2exeVersion })
if ($module.Count -eq 0) {
    if ($env:AULAGUARD_OFFLINE_RELEASE -eq '1') {
        throw "El entorno de publicación necesita ps2exe $ps2exeVersion preinstalado y revisado."
    }
    Install-Module -Name ps2exe -RequiredVersion $ps2exeVersion -Repository PSGallery -Scope CurrentUser -Force -ErrorAction Stop
}
Import-Module ps2exe -RequiredVersion $ps2exeVersion -Force -ErrorAction Stop

$outputExe = Join-Path $OutputDir 'AulaGuard.exe'

Invoke-PS2EXE -InputFile (Join-Path $src 'AulaGuard.ps1') -OutputFile $outputExe -IconFile $icon -Title 'AulaGuard' -Product 'AulaGuard' -Company 'Elearning Cloud' -Description 'Administración, protección y control educativo para aulas Windows' -Version '0.4.1.0' -NoConsole -RequireAdmin -STA

Write-Host "Aplicación generada: $outputExe"
