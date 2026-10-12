$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$uiPath = Join-Path $repo 'src\AulaGuard.ps1'
$ui = Get-Content -LiteralPath $uiPath -Raw -Encoding UTF8

function Require([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "PROFESSIONAL UI TEST FAILED: $Message" }
}

Require ($ui -match "# AulaGuard v0\.5\.1") 'Source banner is not v0.5.1'
Require ($ui -match '\$homeLayout = New-Object System\.Windows\.Forms\.TableLayoutPanel') 'Home is not using responsive TableLayoutPanel'
Require ($ui -match '\$homeLayout\.Dock = ''Fill''') 'Home does not fill available workspace'
Require ($ui -match '\$metrics\.ColumnCount = 4' -and $ui -match '\$quick\.ColumnCount = 3') 'Home metric/action structure missing'
Require ($ui -match '\$webLayout = New-Object System\.Windows\.Forms\.TableLayoutPanel' -and $ui -match '\$webLayout\.Dock = ''Fill''') 'Internet page is not responsive'
Require ($ui -match '\$desktopLayout = New-Object System\.Windows\.Forms\.TableLayoutPanel' -and $ui -match '\$desktopLayout\.Dock = ''Fill''') 'Desktop page is not responsive'
Require ($ui -match '\$auditLayout = New-Object System\.Windows\.Forms\.TableLayoutPanel' -and $ui -match '\$auditLayout\.Dock = ''Fill''') 'Audit page is not responsive'
Require ($ui -match '\$usbView\.Dock = ''Fill''' -and $ui -match '\$programLayout\.Dock = ''Fill''' -and $ui -match '\$healthLayout\.Dock = ''Fill''') 'Existing professional pages lost responsive fill layout'

Require ($ui -notmatch '\$gridUsers\.Location\s*=') 'Dashboard user table reverted to fixed coordinates'
Require ($ui -notmatch '\$lstWebsites\.Location\s*=') 'Internet list reverted to fixed coordinates'
Require ($ui -notmatch '\$lstShortcuts\.Location\s*=') 'Desktop list reverted to fixed coordinates'
Require ($ui -notmatch '\$txtAudit\.Location\s*=') 'Audit log reverted to fixed coordinates'

Require ($ui -match 'function New-Surface' -and $ui -match 'function New-MetricSurface' -and $ui -match 'function Style-Input') 'Professional visual helpers missing'
Require ($ui -match '\$homeState\.BackColor = \$SoftGreen' -and $ui -match '\$homeState\.BackColor = \$SoftRed') 'Dashboard health banner is not synchronized with readiness state'
Require ($ui -match "BLOQUEAR USB" -and $ui -match "PERMITIR USB") 'USB control language is ambiguous'
Require ($ui -match '\$usbCard\.BackColor = \$SoftRed') 'USB destructive state lacks visual warning'
Require ($ui -match '\$status\.Text = "\$prefix  \$Message"') 'Footer status does not use consistent semantic indicator'
Require ($ui -match 'foreach \(\$layout in @\(\$homeLayout,\$healthLayout,\$programLayout,\$appLayout,\$webLayout,\$desktopLayout,\$usbView,\$auditLayout\)\)') 'Runtime UI self-test does not cover all professional pages'

$core = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.Core.psm1') -Raw -Encoding UTF8
$default = Get-Content -LiteralPath (Join-Path $repo 'config\default.json') -Raw -Encoding UTF8
$installer = Get-Content -LiteralPath (Join-Path $repo 'installer\AulaGuard.iss') -Raw -Encoding UTF8
Require ($core -match '0\.5\.1') 'Core version is not aligned to 0.5.1'
Require ($default -match '"version"\s*:\s*"0\.5\.1"') 'Default settings version is not aligned to 0.5.1'
Require ($installer -match '#define MyAppVersion "0\.5\.1"') 'Installer version is not aligned to 0.5.1'

Write-Host '[OK] Responsive Home, Internet, Desktop, USB and Audit visual structure verified'
Write-Host '[OK] Semantic status, health feedback and version alignment verified'
Write-Host 'PASS: professional UI regressions'
