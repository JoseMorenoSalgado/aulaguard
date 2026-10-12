$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $repo 'src\AulaGuard.Security.psm1') -Force
Import-Module (Join-Path $repo 'src\AulaGuard.Core.psm1') -Force
Import-Module (Join-Path $repo 'src\AulaGuard.Diagnostics.psm1') -Force

function Require([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "PROFESSIONAL READINESS TEST FAILED: $Message" }
}

$root = Join-Path $env:ProgramData ('AulaGuard-Readiness-' + [guid]::NewGuid().ToString('N'))
$report = Join-Path $env:TEMP ('AulaGuard-Diagnostic-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    Initialize-AulaGuardSecurity -Root $root
    $settings = New-AulaGuardSettings
    Save-AulaGuardSettings -Root $root -Settings $settings | Out-Null

    $checks = @(Test-AulaGuardReadiness -Root $root -Settings $settings)
    Require ($checks.Count -ge 7) 'Readiness engine returned too few checks'
    Require (@($checks | Where-Object { -not $_.Code -or -not $_.Name }).Count -eq 0) 'Readiness check without code/name'
    Require (@($checks | Where-Object { $_.Severity -notin @('Info','Warning','Critical') }).Count -eq 0) 'Unexpected readiness severity'

    $summary = Get-AulaGuardReadinessSummary -Checks $checks
    Require ($summary.Total -eq $checks.Count) 'Readiness summary count mismatch'
    Require ($summary.Passed + $summary.Critical + $summary.Warnings -ge $summary.Total) 'Summary omitted state'
    Write-Host "[OK] Readiness engine produced $($checks.Count) structured checks"

    $saved = Export-AulaGuardDiagnosticReport -Path $report -Root $root -Settings $settings
    Require (Test-Path -LiteralPath $saved -PathType Leaf) 'Diagnostic report was not created'
    $json = Get-Content -LiteralPath $saved -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    Require ($json.schema -eq 'AulaGuard-Diagnostics/1') 'Unexpected diagnostic schema'
    Require ($json.PSObject.Properties.Name -notcontains 'secret') 'Diagnostic report exposed secret field'
    $raw = Get-Content -LiteralPath $saved -Raw -Encoding UTF8
    Require ($raw -notmatch 'secret\.key|audit\.log|HMAC-SHA') 'Diagnostic report leaked protected file content'
    Write-Host '[OK] Support report contains readiness metadata without secret/audit payloads'

    $ui = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.ps1') -Raw
    Require ($ui -match '\$tabHealth = New-Object System\.Windows\.Forms\.TabPage') 'System Status page missing'
    Require ($ui -match 'BlocksPolicies' -and $ui -match 'BlocksAppControl') 'Apply actions are not gated by readiness'
    Require ($ui -match 'Protección incompleta: \$errors error\(es\)') 'Partial failures are still presented as success'
    Require ($ui -match '\$simulation[\s\S]*?lastAppliedUtc') 'Applied timestamp logic missing simulation distinction'

    $startup = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.Startup.ps1') -Raw
    Require ($startup -match 'STARTUP_PREFLIGHT_BLOCKED' -and $startup -match 'BlocksPolicies') 'Unattended startup can bypass readiness preflight'
    Require ($startup -match 'BlocksAppControl') 'Startup AppLocker state can bypass readiness checks'
    Write-Host '[OK] Scheduled startup uses the same readiness gate as the UI'

    $app = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.AppControl.psm1') -Raw
    Require ($app -match 'Faltantes=\$\(\$missing\.Count\); inesperados=\$\(\$unexpected\.Count\)') 'AppLocker group membership is not verified'
    Require ($app -notmatch 'Remove-LocalGroupMember[\s\S]{0,160}ErrorAction SilentlyContinue') 'AppLocker group sync still hides failures'
    Write-Host '[OK] Professional UI preflight and strict AppLocker group verification detected'
    Write-Host 'PASS: professional readiness and diagnostics'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue
}
