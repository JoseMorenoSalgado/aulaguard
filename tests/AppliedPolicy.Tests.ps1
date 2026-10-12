$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $repo 'src\AulaGuard.Security.psm1') -Force
Import-Module (Join-Path $repo 'src\AulaGuard.Core.psm1') -Force

function Require([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "APPLIED POLICY TEST FAILED: $Message" }
}
function MustThrow([scriptblock]$Action,[string]$Message) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Require $threw $Message
}

$root = Join-Path $env:ProgramData ('AulaGuard-Applied-' + [guid]::NewGuid().ToString('N'))
try {
    Initialize-AulaGuardSecurity -Root $root
    $staged = New-AulaGuardSettings
    $staged.profileName = 'Aula de prueba'
    $staged.policyMode = 'Audit'
    $staged.protections.blockTaskManager = $true
    $staged.usb.blockStorage = $true
    Save-AulaGuardSettings -Root $root -Settings $staged | Out-Null

    $appliedPath = Get-AulaGuardAppliedPolicyPath -Root $root
    Require (-not (Test-Path -LiteralPath $appliedPath)) 'Saving staged settings created a deployment snapshot'

    $candidate = Read-AulaGuardSettings -Root $root
    $snapshot = Save-AulaGuardAppliedPolicy -Root $root -Settings $candidate
    Require (Test-Path -LiteralPath $appliedPath -PathType Leaf) 'Applied snapshot not created'
    Require (Test-Path -LiteralPath "$appliedPath.mac" -PathType Leaf) 'Applied snapshot signature missing'
    Require ($snapshot.schema -eq 'AulaGuard-AppliedPolicy/1') 'Unexpected applied snapshot schema'

    $applied = Read-AulaGuardAppliedPolicy -Root $root
    Require ($applied.protections.blockTaskManager) 'Applied snapshot lost protection setting'
    Require ($applied.usb.blockStorage) 'Applied snapshot lost USB setting'
    Require ($applied.PSObject.Properties.Name -notcontains 'appControl') 'Applied snapshot must not own AppLocker state'
    Require ($applied.PSObject.Properties.Name -notcontains 'premium') 'Applied snapshot must not contain Premium settings'
    Write-Host '[OK] Signed applied snapshot stores only deployed general/USB policy state'

    $staged.usb.blockStorage = $false
    $staged.protections.blockTaskManager = $false
    Save-AulaGuardSettings -Root $root -Settings $staged | Out-Null
    $afterStage = Read-AulaGuardAppliedPolicy -Root $root
    Require ($afterStage.usb.blockStorage) 'Saving staged USB setting changed deployed state'
    Require ($afterStage.protections.blockTaskManager) 'Saving staged protection changed deployed state'
    Write-Host '[OK] Staged configuration is independent from deployed policy'

    Add-Content -LiteralPath $appliedPath -Value 'tamper' -Encoding UTF8
    MustThrow { Read-AulaGuardAppliedPolicy -Root $root } 'Tampered applied snapshot was accepted'
    Write-Host '[OK] Applied snapshot tamper detection fails closed'

    Clear-AulaGuardAppliedPolicy -Root $root
    Require (-not (Test-Path -LiteralPath $appliedPath)) 'Applied snapshot was not cleared'
    Require (-not (Test-Path -LiteralPath "$appliedPath.mac")) 'Applied snapshot MAC was not cleared'

    $startup = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.Startup.ps1') -Raw
    Require ($startup -match 'Read-AulaGuardAppliedPolicy') 'Startup does not load deployed snapshot'
    Require ($startup -match 'Set-AulaGuardPolicies -Settings \$applied') 'Startup does not reapply the signed deployment snapshot'
    Require ($startup -notmatch 'Set-AulaGuardPolicies -Settings \$settings') 'Startup still applies staged settings directly'
    Require ($startup -match 'STARTUP_NO_APPLIED_POLICY') 'Startup lacks safe no-deployment state'

    $ui = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.ps1') -Raw
    Require ($ui -match '\$newSettings\.policyMode = \[string\]\$settings\.policyMode') 'Save button can still alter actual deployment mode'
    Require ($ui -match 'Save-AulaGuardAppliedPolicy -Settings \$candidate') 'Apply does not commit signed deployment state'
    Require ($ui -match 'Clear-AulaGuardAppliedPolicy -Root \$root') 'Reset does not clear deployment state'
    Write-Host '[OK] UI and startup separate staging, deployment and reset'
    Write-Host 'PASS: applied-policy state model'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
