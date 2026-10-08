$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $repo 'src\AulaGuard.Security.psm1') -Force
Import-Module (Join-Path $repo 'src\AulaGuard.Core.psm1') -Force

$root = Join-Path $env:ProgramData ('AulaGuard-SecurityTest-' + [guid]::NewGuid().ToString('N'))
function Assert-Test([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "TEST FAILED: $Message" }
}
function Assert-Throws([scriptblock]$Operation,[string]$Message) {
    $didThrow = $false
    try { & $Operation | Out-Null } catch { $didThrow = $true }
    Assert-Test $didThrow $Message
}

try {
    Initialize-AulaGuardSecurity -Root $root
    $settings = New-AulaGuardSettings
    $settings.policyMode = 'Enforce'
    Save-AulaGuardSettings -Settings $settings -Root $root | Out-Null
    $loaded = Read-AulaGuardSettings -Root $root
    Assert-Test ($loaded.policyMode -eq 'Enforce') 'Valid signed configuration must load'
    Write-Host '[OK] Signed configuration loads'

    $path = Get-AulaGuardSettingsPath -Root $root
    $original = [IO.File]::ReadAllBytes($path)
    $changed = [Text.Encoding]::UTF8.GetString($original).Replace('"Enforce"','"Audit"')
    [IO.File]::WriteAllText($path,$changed)
    Assert-Throws { Read-AulaGuardSettings -Root $root } 'Modification without the HMAC must be rejected'
    Write-Host '[OK] Altered settings blocked'

    [IO.File]::WriteAllBytes($path,$original)
    [IO.File]::Delete("$path.mac")
    Assert-Throws { Read-AulaGuardSettings -Root $root } 'Missing signature must be rejected'
    Write-Host '[OK] Missing signature blocked'
    Save-AulaGuardSettings -Settings $settings -Root $root | Out-Null

    Write-AulaGuardAudit -Action 'SECURITY_TEST_ONE' -Detail 'A' -Root $root
    Write-AulaGuardAudit -Action 'SECURITY_TEST_TWO' -Detail 'B' -Root $root
    $log = Get-ChildItem (Join-Path $root 'logs') -Filter 'secure-audit-*.jsonl' | Select-Object -First 1
    $good = Test-AulaGuardAuditLog -Path $log.FullName -Root $root
    Assert-Test ($good.Valid -and $good.Count -eq 2) 'Audit HMAC chain must verify'
    Write-Host '[OK] Chained audit verified'

    $mutated = [IO.File]::ReadAllText($log.FullName).Replace('SECURITY_TEST_ONE','SECURITY_TEST_FAKE')
    [IO.File]::WriteAllText($log.FullName,$mutated)
    $bad = Test-AulaGuardAuditLog -Path $log.FullName -Root $root
    Assert-Test (-not $bad.Valid) 'Altered audit must be detected'
    Assert-Throws { Write-AulaGuardAudit -Action 'THIRD' -Root $root } 'Do not append to altered log'
    Write-Host '[OK] Audit alteration detected and append refused'

    $acl = Get-Acl -LiteralPath $root
    $insecureAce = @($acl.Access | Where-Object {
        ($_.IdentityReference.Value -in @('BUILTIN\Users','Everyone','NT AUTHORITY\Authenticated Users')) -and
        $_.AccessControlType -eq 'Allow' -and
        (($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write) -ne 0)
    })
    Assert-Test ($insecureAce.Count -eq 0) 'Students must not have write access to ProgramData'
    Write-Host '[OK] ACL does not grant Users write access'

    $legacyRoot = Join-Path $root 'legacy'
    # Root ACL inherits administrators-only. The explicit migration must never preserve Enforce.
    [void](New-Item -Path (Join-Path $legacyRoot 'config') -ItemType Directory -Force)
    $legacy = New-AulaGuardSettings
    $legacy.policyMode = 'Enforce'
    $legacy | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $legacyRoot 'config\settings.json') -Encoding UTF8
    Assert-Throws { Initialize-AulaGuardSecurity -Root $legacyRoot } 'Legacy config must require explicit migration'
    Initialize-AulaGuardSecurity -Root $legacyRoot -MigrateLegacy
    Assert-Test ((Read-AulaGuardSettings -Root $legacyRoot).policyMode -eq 'Audit') 'Legacy migration must downgrade to Audit'
    Write-Host '[OK] Explicit legacy migration safely disables enforcement'
    Write-Host 'PASS: all AulaGuard security regression tests'
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
