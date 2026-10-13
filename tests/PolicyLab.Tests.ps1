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

Write-Host '[OK] Isolated policy application/reversal laboratory passed.'
