$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$iss = Get-Content -LiteralPath (Join-Path $repoRoot 'installer\AulaGuard.iss') -Raw -Encoding UTF8
$build = Get-Content -LiteralPath (Join-Path $repoRoot 'build\Build-App.ps1') -Raw -Encoding UTF8

# The GUI executable intentionally has a requireAdministrator manifest.
if ($build -notmatch '(?<!\w)-RequireAdmin\b') {
    throw 'The AulaGuard EXE must require elevation for protected administrative actions.'
}

$runMatch = [regex]::Match($iss, '(?ms)^\[Run\]\s*\r?\n(?<body>.*?)(?=^\[|\z)')
if (-not $runMatch.Success) { throw 'Inno Setup [Run] section missing.' }

$launchLines = @($runMatch.Groups['body'].Value -split '\r?\n' | Where-Object {
    $_ -match '^Filename:\s*"\{app\}\\src\\AulaGuard\.exe"\s*;'
})
if ($launchLines.Count -ne 1) {
    throw "Expected exactly one AulaGuard GUI launch in [Run]; found $($launchLines.Count)."
}

$line = $launchLines[0]
foreach ($flag in @('postinstall','skipifsilent','runascurrentuser')) {
    if ($line -notmatch "(?i)\b$flag\b") {
        throw "Missing post-install launch flag: $flag (possible CreateProcess error 740)."
    }
}
if ($line -match '(?i)\brunasoriginaluser\b') {
    throw 'Post-install launch must never drop elevation to the original unelevated user.'
}

$versionMatch = [regex]::Match($iss, '(?m)^#define MyAppVersion "([0-9]+\.[0-9]+\.[0-9]+)"$')
if (-not $versionMatch.Success) { throw 'Installer version not found.' }
$version = $versionMatch.Groups[1].Value
if ($build -notmatch [regex]::Escape("-Version '$version.0'")) {
    throw "The EXE version does not match installer v$version."
}
$default = Get-Content -LiteralPath (Join-Path $repoRoot 'config\default.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($default.version -ne $version) {
    throw "Default configuration ($($default.version)) differs from installer version ($version)."
}
Write-Host "[OK] RequireAdmin manifest + runascurrentuser postinstall flags prevent error 740."
Write-Host "[OK] Version consistent across EXE, installer and default profile: v$version."
