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

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}

Import-Module ps2exe -Force

$outputExe = Join-Path $OutputDir 'AulaGuard.exe'

Invoke-PS2EXE -InputFile (Join-Path $src 'AulaGuard.ps1') -OutputFile $outputExe -IconFile $icon -Title 'AulaGuard' -Product 'AulaGuard' -Company 'Elearning Cloud' -Description 'Administración, protección y control educativo para aulas Windows' -Version '0.3.2.0' -NoConsole -RequireAdmin -STA

Write-Host "Aplicación generada: $outputExe"
