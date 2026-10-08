$ErrorActionPreference = 'Stop'

# Exercise the actual Windows uninstaller on an isolated CI runner.
$installRoot = Join-Path $env:ProgramFiles 'AulaGuard'
$dataRoot = Join-Path $env:ProgramData 'AulaGuard'
$uninstaller = Join-Path $installRoot 'unins000.exe'
if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
    throw "No se encontró el desinstalador real: $uninstaller"
}
if (-not (Test-Path -LiteralPath (Join-Path $dataRoot 'config\settings.json'))) {
    throw 'No se encontró la configuración original; se aborta la prueba destructiva.'
}
# Residues left by older installers, only within the app-owned subdirectories.
foreach ($relative in @('src\obsolete-version.psm1','docs\old-manual.txt','config\old-default.json')) {
    $path = Join-Path $installRoot $relative
    [IO.File]::WriteAllText($path, 'AulaGuard legacy cleanup test')
}

$uninstall = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -WorkingDirectory $env:TEMP -PassThru -Wait -ErrorAction Stop
if ($uninstall.ExitCode -ne 0) {
    throw "El desinstalador devolvió error $($uninstall.ExitCode)."
}

$deadline = [DateTime]::UtcNow.AddSeconds(15)
while ((Test-Path -LiteralPath $installRoot) -and ([DateTime]::UtcNow -lt $deadline)) {
    Start-Sleep -Milliseconds 500
}
if (Test-Path -LiteralPath $installRoot) {
    $remaining = @(Get-ChildItem -LiteralPath $installRoot -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    throw "Quedaron archivos en Program Files tras desinstalar: $($remaining -join '; ')"
}
Write-Host '[OK] Eliminada carpeta de Program Files con residuos de versiones anteriores.'

$task = Get-ScheduledTask -TaskName 'PolicySync' -TaskPath '\AulaGuard\' -ErrorAction SilentlyContinue
if ($null -ne $task) { throw 'La tarea AulaGuard\PolicySync continúa instalada.' }
$logonTask = Get-ScheduledTask -TaskName 'PolicySyncLogon' -TaskPath '\AulaGuard\' -ErrorAction SilentlyContinue
if ($null -ne $logonTask) { throw 'La tarea de sincronización al iniciar sesión continúa instalada.' }
Write-Host '[OK] Eliminada tarea programada.'

if (-not (Test-Path -LiteralPath (Join-Path $dataRoot 'config\settings.json')) -or
    -not (Test-Path -LiteralPath (Join-Path $dataRoot 'config\settings.json.mac'))) {
    throw 'La desinstalación borró ajustes o firmas que debían conservarse.'
}
Import-Module (Join-Path $PSScriptRoot '..\src\AulaGuard.Security.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\AulaGuard.Core.psm1') -Force
Assert-AulaGuardSignedFile -Path (Join-Path $dataRoot 'config\settings.json') -Root $dataRoot
Write-Host '[OK] Configuración firmada en ProgramData preservada y verificada.'
Write-Host 'PASS: Windows uninstall regression tests.'
