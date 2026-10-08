$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $repo 'src\AulaGuard.InstalledApps.psm1') -Force

function Assert([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "Installed apps test failed: $Message" }
}

$notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
Assert (Test-Path -LiteralPath $notepad -PathType Leaf) 'Windows Notepad fixture missing'
Assert ((Resolve-AulaGuardExecutablePath -Candidate ('"{0}",0' -f $notepad)) -eq $notepad) 'Quoted DisplayIcon must resolve'
Assert ((Resolve-AulaGuardExecutablePath -Candidate "$notepad,0") -eq $notepad) 'Unquoted icon indexes must resolve'
Assert (-not (Resolve-AulaGuardExecutablePath -Candidate 'powershell.exe -NoProfile')) 'Command-line input must not resolve'
Assert (-not (Resolve-AulaGuardExecutablePath -Candidate '\\host\share\app.exe')) 'UNC network executable must be rejected'
Assert (-not (Resolve-AulaGuardExecutablePath -Candidate 'C:\DoesNotExist\unknown.exe')) 'Missing EXE cannot be selectable'
Write-Host '[OK] Safe executable resolution: quoted paths, icon indexes, missing files and command strings'

$apps = @(Get-AulaGuardInstalledApplications -SkipStore -SkipShortcuts)
Assert ($apps.Count -gt 0) 'No installed Win32 applications detected from Windows registry'
Assert (@($apps | Where-Object { $_.Name -and $_.Type -eq 'Win32' }).Count -eq $apps.Count) 'Registry results contain invalid app records'
Assert (@($apps | Where-Object { $_.CanAllow -and -not (Test-Path -LiteralPath $_.ExecutablePath -PathType Leaf) }).Count -eq 0) 'App marked as selectable without a file'
Assert (@($apps | Where-Object { $_.ExecutablePath -match '(?i)unins\d*\.exe$' -and $_.CanAllow }).Count -eq 0) 'Never allow an uninstaller by inference'
Write-Host "[OK] Windows registry inventory: $($apps.Count) applications, no executable launched or policy modified"

$source = Get-Content -LiteralPath (Join-Path $repo 'src\AulaGuard.ps1') -Raw
Assert ($source -match '\$renderPrograms = \{' -and $source -match '\$loadPrograms = \{') 'Missing switch list population / filtering'
Assert ($source -match '\$gridPrograms.Add_CellClick' -and $source -match '\$syncProgramSelection') 'Toggle does not persist to allow-list'
Assert ($source -match '\$programLayout.Dock = ''Fill''' -and $source -match '\$appLayout.Dock = ''Fill''') 'Pages must be responsive'
Assert ($source -match '\$radAppAudit.Add_CheckedChanged' -and $source -match '\$radAppEnforce.Add_CheckedChanged') 'Audit / Enforce mutual exclusion missing'
Write-Host '[OK] Responsive panel and switch bindings found'
Write-Host 'PASS: installed application inventory regression tests'
