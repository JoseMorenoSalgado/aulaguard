$ErrorActionPreference = 'Stop'

$root = Join-Path $env:ProgramData 'AulaGuard'
$src = Join-Path $root 'src'

try {
    Import-Module (Join-Path $src 'AulaGuard.Core.psm1') -Force
    Import-Module (Join-Path $src 'AulaGuard.Policy.psm1') -Force
    Import-Module (Join-Path $src 'AulaGuard.AppControl.psm1') -Force

    $settings = Read-AulaGuardSettings -Root $root

    if ($settings.policyMode -eq 'Enforce') {
        $result = @(Apply-AulaGuardPolicies -Settings $settings)
        if ($settings.protections.protectPublicDesktop) {
            Protect-AulaGuardPublicDesktop
        }
        Write-AulaGuardAudit -Action 'STARTUP_POLICIES_SYNC' -Level 'SECURITY' -Detail "Profiles=$($result.Count)" -Root $root
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
    try {
        $logs = Join-Path $root 'logs'
        if (-not (Test-Path $logs)) { New-Item -ItemType Directory -Path $logs -Force | Out-Null }
        $line = "$(Get-Date -Format o) STARTUP_ERROR $($_.Exception.Message)"
        Add-Content -Path (Join-Path $logs 'startup.log') -Value $line -Encoding UTF8
    } catch {}
    exit 1
}
