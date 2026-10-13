$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$adminPath = Join-Path $root 'tests\e2e\Admin-Preflight.ps1'
$studentPath = Join-Path $root 'tests\e2e\Student-Probe.ps1'
$docPath = Join-Path $root 'docs\E2E-WINDOWS-LAB.md'
function Require([bool]$condition,[string]$message) {
    if (-not $condition) { throw "E2E HARNESS TEST FAILED: $message" }
}
foreach ($path in @($adminPath,$studentPath)) {
    Require (Test-Path -LiteralPath $path -PathType Leaf) "Missing E2E script: $path"
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    Require ($errors.Count -eq 0) "PowerShell parser errors in $path : $($errors -join ', ')"
}

$admin = Get-Content -LiteralPath $adminPath -Raw -Encoding UTF8
$student = Get-Content -LiteralPath $studentPath -Raw -Encoding UTF8
$doc = Get-Content -LiteralPath $docPath -Raw -Encoding UTF8

Require ($admin -match 'Get-LocalUser' -and $admin -match 'S-1-5-32-544') 'Admin preflight must reject administrator student accounts'
Require ($admin -match 'Read-AulaGuardSettings' -and $admin -match 'Test-AulaGuardReadiness') 'Admin preflight must verify protected configuration'
Require ($admin -match 'Get-FileHash' -and $admin -match 'AulaGuard-E2E-Benign\.exe') 'Manifest must bind harmless fixture hash'
Require ($admin -match 'ReparsePoint' -and $admin -match 'Set-Acl') 'Published lab files require ACLs and link protection'
Require ($student -match 'IsInRole' -and $student -match 'Administrator') 'Student probe must reject elevated execution'
Require ($student -match 'manifest\.studentSid' -and $student -match 'manifest\.computer') 'Student probe must match account and machine'
Require ($student -match 'NativeErrorCode -eq 1260') 'AppLocker denial must require explicit group-policy evidence'
Require ($student -match 'manifest\.benignFixtureSha256' -and $student -match 'Get-FileHash') 'Student must hash-check the benign fixture'
Require ($student -match 'readyForProduction = \$false' -and $student -match 'completeE2E = \$false') 'Automated results must not claim release readiness'
Require ($student -match 'APPLOCKER_DENIED_PROCESS' -and $student -match 'USB_PHYSICAL_READ') 'Student-side functional checks missing'

foreach ($unsafe in @(
    '(?m)^\s*Set-AppLockerPolicy\b',
    '(?m)^\s*New-LocalUser\b',
    '(?m)^\s*Set-MpPreference\b',
    '(?m)^\s*Remove-MpPreference\b',
    '(?m)^\s*Set-AulaGuardPolicies\b',
    '(?m)^\s*Sync-AulaGuardUsbPolicy\b',
    '(?m)^\s*Reset-AulaGuardPolicies\b'
)) {
    Require ($admin -notmatch $unsafe) 'Preflight must not apply or remove restrictions.'
    Require ($student -notmatch $unsafe) 'Student probe must not apply or remove restrictions.'
}
Require ($doc -match 'Windows 10 Pro' -and $doc -match 'Windows 11 Pro') 'OS acceptance matrix incomplete'
Require ($doc -match 'snapshot' -and $doc -match 'Defender') 'Missing recovery or antivirus precautions'
Write-Host '[OK] E2E harness syntax, isolation, role and reporting guardrails verified.'
