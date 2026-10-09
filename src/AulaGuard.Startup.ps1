$ErrorActionPreference = 'Stop'

$root = Join-Path $env:ProgramData 'AulaGuard'
$src = $PSScriptRoot

try {
    Import-Module (Join-Path $src 'AulaGuard.Security.psm1') -Force
    Import-Module (Join-Path $src 'AulaGuard.Core.psm1') -Force
    Import-Module (Join-Path $src 'AulaGuard.Policy.psm1') -Force
    Import-Module (Join-Path $src 'AulaGuard.USB.psm1') -Force
    Import-Module (Join-Path $src 'AulaGuard.Wallpaper.psm1') -Force
    Import-Module (Join-Path $src 'AulaGuard.AppControl.psm1') -Force

    # Do not create a new trust key or downgrade settings during unattended startup.
    $settings = Read-AulaGuardSettings -Root $root

    if ($settings.policyMode -eq 'Enforce') {
        $result = @(Apply-AulaGuardPolicies -Settings $settings)
        $policyErrors = @($result | Where-Object { $_.Status -eq 'ERROR' })
        if ($policyErrors.Count -gt 0) { throw "No se pudieron sincronizar políticas: $($policyErrors[0].Detail)" }
        $usbResult = @(Sync-AulaGuardUsbPolicy -BlockStorage ([bool]$settings.usb.blockStorage) -Root $root)
        $usbErrors = @($usbResult | Where-Object {$_.Status -eq 'ERROR'})
        if ($usbErrors.Count -gt 0) {
            throw "Falló la sincronización USB para $($usbErrors.Count) perfil(es): $($usbErrors[0].Detail)"
        }
        if ($settings.protections.protectPublicDesktop) {
            Protect-AulaGuardPublicDesktop
        }
        Write-AulaGuardAudit -Action 'STARTUP_POLICIES_SYNC' -Level 'SECURITY' -Detail "Profiles=$($result.Count);USB=$($usbResult.Count)" -Root $root
    } else {
        Write-AulaGuardAudit -Action 'STARTUP_AUDIT_MODE' -Detail 'Las políticas generales permanecen en modo auditoría.' -Root $root
    }

    if ($settings.appControl.enabled) {
        try {
            Enable-AulaGuardApplicationIdentity | Out-Null
            Sync-AulaGuardStudentsGroup | Out-Null
            Write-AulaGuardAudit -Action 'STARTUP_APPCONTROL_READY' -Level 'SECURITY' -Detail "Mode=$($settings.appControl.mode)" -Root $root
        } catch {
            Write-AulaGuardAudit -Action 'STARTUP_APPCONTROL_ERROR' -Level 'ERROR' -Detail $_.Exception.Message -Root $root
        }
    }
}
catch {
    # Preserve existing Windows restrictions on failure. Report the problem outside the local JSON log.
    try {
        $description = "AulaGuard no inició por error de integridad o carga: $($_.Exception.Message)"
        & eventcreate.exe /L APPLICATION /T ERROR /ID 101 /SO AulaGuard /D $description | Out-Null
    } catch {}
    exit 1
}
