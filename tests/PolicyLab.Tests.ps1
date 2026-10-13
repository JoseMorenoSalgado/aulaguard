$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $repo 'src\AulaGuard.Policy.psm1') -Force

function Require([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "POLICY LAB TEST FAILED: $Message" }
}

$settings = [pscustomobject]@{
    wallpaper = ''
    allowedWebsites = @('https://example.edu/*')
    protections = [pscustomobject]@{
        lockWallpaper = $true
        disablePersonalization = $true
        protectPublicDesktop = $true
        browserWhitelist = $true
        blockControlPanel = $true
        blockRegistryTools = $true
        blockTaskManager = $true
        blockCommandPrompt = $false
        blockPowerShell = $false
    }
}

$result = Test-AulaGuardPolicyEngine -Settings $settings
Require $result.Passed 'Enabled policy set failed isolated validation.'
Require (@($result.Checks).Count -ge 6) 'Expected policy checks are missing.'
Require (@($result.Checks | Where-Object { -not $_.Passed }).Count -eq 0) 'One or more policy checks failed.'

$settings.protections.lockWallpaper = $false
$settings.protections.disablePersonalization = $false
$settings.protections.browserWhitelist = $false
$settings.protections.blockControlPanel = $false
$settings.protections.blockRegistryTools = $false
$settings.protections.blockTaskManager = $false

$result = Test-AulaGuardPolicyEngine -Settings $settings
Require $result.Passed 'Disabled policy set failed isolated validation.'
Require (@($result.Checks | Where-Object { -not $_.Passed }).Count -eq 0) 'Policy reversal validation failed.'

$leftovers = @(Get-ChildItem 'Registry::HKEY_CURRENT_USER\Software' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -like 'AulaGuardPolicyLab_*' })
Require ($leftovers.Count -eq 0) 'Policy laboratory left registry residue.'


# Verifier must catch tampering even when the setter has returned successfully.
$verificationRoot = "Registry::HKEY_CURRENT_USER\Software\AulaGuardVerify_$([guid]::NewGuid().ToString('N'))"
try {
    New-Item -Path $verificationRoot -Force | Out-Null
    $settings.protections.lockWallpaper = $true
    $settings.protections.blockControlPanel = $true
    $settings.protections.browserWhitelist = $true
    Set-AulaGuardPolicyForHive -HiveRoot $verificationRoot -Settings $settings
    $good = Test-AulaGuardAppliedPolicyForHive -HiveRoot $verificationRoot -Settings $settings
    Require $good.Passed 'Verifier rejected valid student policy values.'
    Require ($good.CheckCount -ge 7) 'Verifier did not inspect all Windows/Chrome/Edge rules.'
    $desktop = Join-Path $verificationRoot 'Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'
    New-ItemProperty -Path $desktop -Name 'NoChangingWallPaper' -Value 0 -PropertyType DWord -Force | Out-Null
    $bad = Test-AulaGuardAppliedPolicyForHive -HiveRoot $verificationRoot -Settings $settings
    Require (-not $bad.Passed) 'Verifier failed to detect a removed wallpaper restriction.'
    Require (@($bad.Errors | Where-Object { $_ -match 'NoChangingWallPaper' }).Count -gt 0) 'Verifier missing actionable error detail.'
    Set-AulaGuardPolicyForHive -HiveRoot $verificationRoot -Settings $settings
    $recovered = Test-AulaGuardAppliedPolicyForHive -HiveRoot $verificationRoot -Settings $settings
    Require $recovered.Passed 'Failed to restore tampered policy to verified state.'
} finally {
    Remove-Item -LiteralPath $verificationRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$policySource = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.Policy.psm1') -Raw -Encoding UTF8
Require ($policySource -match 'No se encontraron perfiles estándar') 'Protection must reject zero student accounts'
Require ($policySource -match 'Test-AulaGuardAppliedPolicyForHive -HiveRoot \$hive') 'Protection must verify each actual target user hive'

Write-Host '[OK] Applied student policy verification detects tampering and recovers.'

Write-Host '[OK] Isolated policy application/reversal laboratory passed.'
