param([switch]$MigrateLegacy)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:ProgramData 'AulaGuard'
Import-Module (Join-Path $PSScriptRoot 'AulaGuard.Security.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AulaGuard.Core.psm1') -Force

try {
    Initialize-AulaGuardSecurity -Root $root -MigrateLegacy:$MigrateLegacy
    $settingsPath = Get-AulaGuardSettingsPath -Root $root
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Save-AulaGuardSettings -Settings (New-AulaGuardSettings) -Root $root | Out-Null
    }
    [void](Read-AulaGuardSettings -Root $root)
    Write-AulaGuardAudit -Action 'SECURITY_INITIALIZED' -Level 'SECURITY' -Root $root
    Write-Host 'AulaGuard: permisos y configuración firmada correctamente.'
} catch {
    Write-Error "No se ha completado la inicialización segura: $($_.Exception.Message)"
    exit 1
}
