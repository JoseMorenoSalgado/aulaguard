$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $repo 'src\AulaGuard.Security.psm1') -Force
Import-Module (Join-Path $repo 'src\AulaGuard.Core.psm1') -Force
function Require([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "FUNCTIONAL WORKFLOW TEST FAILED: $Message" }
}
$root = Join-Path $env:ProgramData ('AulaGuard-Functional-' + [guid]::NewGuid().ToString('N'))
$profile = Join-Path $env:TEMP ('AulaGuard-Imported-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    Initialize-AulaGuardSecurity -Root $root
    $current = New-AulaGuardSettings
    $current.appControl.enabled = $true
    $current.appControl.mode = 'Enabled'
    $current.appControl.lastBackup = 'local-backup.xml'
    Save-AulaGuardSettings -Root $root -Settings $current | Out-Null

    $foreign = New-AulaGuardSettings
    $foreign.policyMode = 'Enforce'
    $foreign.wallpaper = 'C:\Users\Administrator\Downloads\private.jpg'
    $foreign.protections.lockWallpaper = $true
    $foreign.usb.blockStorage = $true
    $foreign.appControl.enabled = $true
    $foreign.appControl.mode = 'Enabled'
    $foreign.appControl.lastBackup = 'another-computer.xml'
    $foreign.allowedPrograms = @('C:\Windows\system32\notepad.exe')
    $foreign.profileName = 'Importado de otra aula'
    $foreign | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $profile -Encoding UTF8
    $result = Import-AulaGuardProfile -Path $profile -Root $root
    $loaded = Read-AulaGuardSettings -Root $root
    Require ($loaded.policyMode -eq 'Audit') 'Import enabled student policies without confirmation'
    Require (-not $loaded.usb.blockStorage) 'Import enabled USB restrictions without confirmation'
    Require (-not $loaded.protections.lockWallpaper -and
             [string]::IsNullOrWhiteSpace([string]$loaded.wallpaper)) 'Import retained inaccessible wallpaper'
    Require ($loaded.appControl.enabled -and $loaded.appControl.mode -eq 'Enabled' -and
             $loaded.appControl.lastBackup -eq 'local-backup.xml') 'Import replaced actual machine AppLocker state'
    Require ($loaded.profileName -eq 'Importado de otra aula') 'Import lost profile information'
    Require (@($loaded.allowedPrograms).Count -eq 1) 'Import lost selected programs'
    Write-Host '[OK] Imported profile is safe; applied AppLocker state remains attached to this computer'

    $ui = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.ps1') -Raw
    Require ($ui -match 'elseif \(\$tabs.SelectedTab -eq \$tabPrograms\) \{[\s\S]*?if \(-not \$script:inventoryLoaded\) \{ & \$loadPrograms \}') 'Dashboard tab navigation does not trigger inventory scan'
    Require ($ui -match '\$btnImport.Add_Click\(\{[\s\S]*?\$script:settings = Read-AulaGuardSettings -Root \$root') 'UI does not reload the imported settings'
    Require ($ui -match '\$btnApply.Add_Click\(\{[\s\S]*?MessageBox\]::Show\(\$message[\s\S]*?Save-FromUi') 'General Apply must ask for consent before saving'
    Require ($ui -match '\$btnAppApply.Add_Click\(\{[\s\S]*?Show\(\$warningText[\s\S]*?Save-FromUi') 'AppLocker Apply must ask for consent before saving'
    Require ($ui -match 'mode = \[string\]\$settings.appControl.mode') 'Saving selections must not invent an applied AppLocker mode'
    Require ($ui -match 'programCatalog\.Count -lt 1' -and $ui -match 'toggleProgramRow \$targetRow') 'WinForms selftest does not test the program inventory and switches'
    Write-Host '[OK] UI changes save only after confirmation and navigate into populated programs'
    Write-Host 'PASS: functional workflow regressions'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $profile -Force -ErrorAction SilentlyContinue
}