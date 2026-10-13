Set-StrictMode -Version Latest

function Get-AulaGuardMaintenanceStatus {
    param(
        [Parameter(Mandatory=$true)]$Settings,
        [datetime]$NowUtc = ([datetime]::UtcNow)
    )

    $enabled = $false
    $expires = $null
    if ($Settings.PSObject.Properties.Name -contains 'maintenance' -and $null -ne $Settings.maintenance) {
        $enabled = [bool]$Settings.maintenance.enabled
        if ($Settings.maintenance.expiresUtc) {
            $expires = [datetime]::Parse(
                [string]$Settings.maintenance.expiresUtc,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind
            ).ToUniversalTime()
        }
    }

    $expired = ($enabled -and $null -ne $expires -and $NowUtc.ToUniversalTime() -ge $expires)
    $remaining = if ($enabled -and $null -ne $expires -and -not $expired) {
        [Math]::Max(0,[Math]::Ceiling(($expires - $NowUtc.ToUniversalTime()).TotalMinutes))
    } else { 0 }

    [pscustomobject]@{
        Enabled = $enabled
        ExpiresUtc = $expires
        Expired = $expired
        RemainingMinutes = [int]$remaining
    }
}

function Start-AulaGuardMaintenanceMode {
    param(
        [ValidateRange(5,480)][int]$DurationMinutes = 30,
        [string]$Root = (Get-AulaGuardRoot)
    )

    Assert-AulaGuardElevated
    $settings = Read-AulaGuardSettings -Root $Root
    $state = Get-AulaGuardMaintenanceStatus -Settings $settings
    if ($state.Enabled -and -not $state.Expired) {
        throw "El modo mantenimiento ya está activo por aproximadamente $($state.RemainingMinutes) minuto(s)."
    }

    Backup-AulaGuardConfiguration -Root $Root | Out-Null

    $previousPolicyMode = [string]$settings.policyMode
    $previousAppMode = [string]$settings.appControl.mode
    $previousAppEnabled = [bool]$settings.appControl.enabled
    $expiresUtc = [datetime]::UtcNow.AddMinutes($DurationMinutes)

    # Relax only restrictions owned by AulaGuard. If any operation fails before
    # the signed settings are saved, startup will still see the prior protected
    # state and re-apply it (fail closed).
    $policyResult = @(Reset-AulaGuardPolicies -ManagedWallpapers @([string]$settings.wallpaper))
    $policyErrors = @($policyResult | Where-Object { $_.Status -eq 'ERROR' })
    if ($policyErrors.Count -gt 0) {
        throw "No se pudieron suspender las políticas generales: $($policyErrors[0].Detail)"
    }

    $usbResult = @(Sync-AulaGuardUsbPolicy -BlockStorage $false -Root $Root)
    $usbErrors = @($usbResult | Where-Object { $_.Status -eq 'ERROR' })
    if ($usbErrors.Count -gt 0) {
        throw "No se pudo restaurar temporalmente el acceso USB: $($usbErrors[0].Detail)"
    }

    if ($settings.protections.protectPublicDesktop) {
        Protect-AulaGuardPublicDesktop -Restore
    }

    if ($previousAppEnabled) {
        Set-AulaGuardAppControlPolicy -AllowedPrograms @($settings.allowedPrograms) -Mode 'AuditOnly' -BackupDirectory (Join-Path $Root 'backup') | Out-Null
    }

    $settings.maintenance.enabled = $true
    $settings.maintenance.expiresUtc = $expiresUtc.ToString('o')
    $settings.maintenance.previousPolicyMode = $previousPolicyMode
    $settings.maintenance.previousAppControlMode = $previousAppMode
    $settings.maintenance.previousAppControlEnabled = $previousAppEnabled
    $settings.policyMode = 'Audit'
    if ($previousAppEnabled) {
        $settings.appControl.mode = 'AuditOnly'
    }

    Save-AulaGuardSettings -Settings $settings -Root $Root | Out-Null
    Write-AulaGuardAudit -Action 'MAINTENANCE_STARTED' -Level 'SECURITY' -Detail "Minutes=$DurationMinutes;ExpiresUtc=$($settings.maintenance.expiresUtc)" -Root $Root

    return (Get-AulaGuardMaintenanceStatus -Settings $settings)
}

function Stop-AulaGuardMaintenanceMode {
    param(
        [ValidateSet('Manual','Expired')][string]$Reason = 'Manual',
        [string]$Root = (Get-AulaGuardRoot)
    )

    Assert-AulaGuardElevated
    $settings = Read-AulaGuardSettings -Root $Root
    $state = Get-AulaGuardMaintenanceStatus -Settings $settings
    if (-not $state.Enabled) { return $state }

    $target = $settings | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $target.policyMode = [string]$settings.maintenance.previousPolicyMode
    $target.appControl.mode = [string]$settings.maintenance.previousAppControlMode
    $target.appControl.enabled = [bool]$settings.maintenance.previousAppControlEnabled

    if ($target.policyMode -eq 'Enforce') {
        $checks = @(Test-AulaGuardReadiness -Root $Root -Settings $target)
        $blocking = @($checks | Where-Object { -not $_.Passed -and $_.BlocksPolicies })
        if ($blocking.Count -gt 0) {
            $reasonText = ($blocking | Select-Object -First 3 | ForEach-Object { "$($_.Code): $($_.Detail)" }) -join ' | '
            throw "No se puede finalizar mantenimiento porque la protección no está lista: $reasonText"
        }

        $policyResult = @(Set-AulaGuardPolicies -Settings $target)
        $policyErrors = @($policyResult | Where-Object { $_.Status -eq 'ERROR' })
        if ($policyErrors.Count -gt 0) {
            throw "No se pudieron restaurar las políticas generales: $($policyErrors[0].Detail)"
        }

        $usbResult = @(Sync-AulaGuardUsbPolicy -BlockStorage ([bool]$target.usb.blockStorage) -Root $Root)
        $usbErrors = @($usbResult | Where-Object { $_.Status -eq 'ERROR' })
        if ($usbErrors.Count -gt 0) {
            throw "No se pudo restaurar la política USB: $($usbErrors[0].Detail)"
        }

        if ($target.protections.protectPublicDesktop) {
            Protect-AulaGuardPublicDesktop
        }
    }

    if ($target.appControl.enabled) {
        $checks = @(Test-AulaGuardReadiness -Root $Root -Settings $target)
        $blocking = @($checks | Where-Object { -not $_.Passed -and $_.BlocksAppControl })
        if ($blocking.Count -gt 0) {
            $reasonText = ($blocking | Select-Object -First 3 | ForEach-Object { "$($_.Code): $($_.Detail)" }) -join ' | '
            throw "No se puede restaurar AppLocker: $reasonText"
        }

        $appResult = Set-AulaGuardAppControlPolicy -AllowedPrograms @($target.allowedPrograms) -Mode ([string]$target.appControl.mode) -BackupDirectory (Join-Path $Root 'backup')
        $target.appControl.lastAppliedUtc = [datetime]::UtcNow.ToString('o')
        $target.appControl.lastBackup = $appResult.Backup
    }

    $target.maintenance.enabled = $false
    $target.maintenance.expiresUtc = $null
    $target.maintenance.previousPolicyMode = 'Audit'
    $target.maintenance.previousAppControlMode = 'AuditOnly'
    $target.maintenance.previousAppControlEnabled = $false
    Save-AulaGuardSettings -Settings $target -Root $Root | Out-Null

    Write-AulaGuardAudit -Action 'MAINTENANCE_ENDED' -Level 'SECURITY' -Detail "Reason=$Reason;PolicyMode=$($target.policyMode);AppMode=$($target.appControl.mode)" -Root $Root
    return (Get-AulaGuardMaintenanceStatus -Settings $target)
}

function Invoke-AulaGuardMaintenanceExpiry {
    param([string]$Root = (Get-AulaGuardRoot))

    $settings = Read-AulaGuardSettings -Root $Root
    $state = Get-AulaGuardMaintenanceStatus -Settings $settings
    if (-not $state.Enabled) { return $state }
    if (-not $state.Expired) { return $state }

    return (Stop-AulaGuardMaintenanceMode -Reason 'Expired' -Root $Root)
}

Export-ModuleMember -Function Get-AulaGuardMaintenanceStatus,Start-AulaGuardMaintenanceMode,Stop-AulaGuardMaintenanceMode,Invoke-AulaGuardMaintenanceExpiry
