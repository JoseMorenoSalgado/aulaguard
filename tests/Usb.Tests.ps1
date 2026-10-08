$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $repoRoot 'src\AulaGuard.Security.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\AulaGuard.Core.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\AulaGuard.Policy.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\AulaGuard.USB.psm1') -Force

$root = Join-Path $env:ProgramData ('AulaGuardUsbTest-' + [guid]::NewGuid().ToString('N'))
try {
    Initialize-AulaGuardSecurity -Root $root
    $profile = New-AulaGuardSettings
    if ($profile.usb.blockStorage -ne $false) {
        throw 'USB blocking must be disabled by default.'
    }
    Save-AulaGuardSettings -Root $root -Settings $profile | Out-Null
    $loaded = Read-AulaGuardSettings -Root $root
    if ($loaded.usb.blockStorage -ne $false) {
        throw 'USB configuration did not persist safely.'
    }
    Write-Host '[OK] USB disabled by default in signed local configuration.'

    $result = @(Sync-AulaGuardUsbPolicy -Root $root -BlockStorage $true -WhatIfMode -Profiles @())
    if ($result.Count -ne 0) { throw 'USB simulation with no target profiles should be empty.' }
    if (Test-Path (Join-Path $root 'config\usb-policy-state.json')) {
        throw 'USB simulation must not write snapshots or policies.'
    }
    Write-Host '[OK] Simulation with no targets never modifies USB policy.'

    $moduleSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\AulaGuard.USB.psm1') -Raw
    if ($moduleSource -notmatch [regex]::Escape('53f5630d-b6bf-11d0-94f2-00a0c91efb8b') -or
        $moduleSource -notmatch 'Deny_Read' -or $moduleSource -notmatch 'Deny_Write') {
        throw 'Expected removable-disk access class read/write policy was not found.'
    }
    if ($moduleSource -match '\bUSBSTOR\b\s+-?Name\b') {
        throw 'USB mass storage driver may not be disabled system-wide.'
    }
    Write-Host '[OK] Implementation targets removable-disk class rather than all USB device controllers.'

    if ($loaded.premium.serverMode -ne 'LocalOnly' -or $loaded.premium.endpoint -ne '') {
        throw 'Premium remote connection must be disabled until implemented.'
    }
    Write-Host '[OK] Premium is local-only; no unimplemented network connection is activated.'
    Write-Host 'PASS: non-destructive USB and Premium regressions.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
