$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $repo 'src\AulaGuard.Maintenance.psm1') -Force

function Require([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "MAINTENANCE TEST FAILED: $Message" }
}

$future = [datetime]::UtcNow.AddMinutes(30)
$settings = [pscustomobject]@{
    maintenance = [pscustomobject]@{
        enabled = $true
        expiresUtc = $future.ToString('o')
        previousPolicyMode = 'Enforce'
        previousAppControlMode = 'Enabled'
        previousAppControlEnabled = $true
    }
}
$status = Get-AulaGuardMaintenanceStatus -Settings $settings -NowUtc ([datetime]::UtcNow)
Require $status.Enabled 'Enabled state was not detected.'
Require (-not $status.Expired) 'Future maintenance was marked expired.'
Require ($status.RemainingMinutes -ge 29 -and $status.RemainingMinutes -le 30) 'Remaining time is invalid.'

$past = [datetime]::UtcNow.AddMinutes(-1)
$settings.maintenance.expiresUtc = $past.ToString('o')
$status = Get-AulaGuardMaintenanceStatus -Settings $settings -NowUtc ([datetime]::UtcNow)
Require $status.Expired 'Expired maintenance was not detected.'
Require ($status.RemainingMinutes -eq 0) 'Expired maintenance must have zero remaining minutes.'

$settings.maintenance.enabled = $false
$status = Get-AulaGuardMaintenanceStatus -Settings $settings -NowUtc ([datetime]::UtcNow)
Require (-not $status.Enabled -and -not $status.Expired) 'Disabled maintenance reported active state.'

$source = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.Maintenance.psm1') -Raw
Require ($source -match "ValidateRange\(5,480\)") 'Maintenance duration is not bounded.'
Require ($source -match "Reset-AulaGuardPolicies" -and $source -match "Sync-AulaGuardUsbPolicy -BlockStorage \$false") 'Maintenance does not relax owned local policies safely.'
Require ($source -match "previousPolicyMode" -and $source -match "previousAppControlMode") 'Previous enforcement state is not preserved.'
Require ($source -match "MAINTENANCE_STARTED" -and $source -match "MAINTENANCE_ENDED") 'Maintenance lifecycle is not audited.'

Write-Host '[OK] Maintenance state and safety invariants passed.'
