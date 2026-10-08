Set-StrictMode -Version Latest

# Windows PowerShell 5.1 does not always load the .NET Framework DPAPI assembly by default.
Add-Type -AssemblyName System.Security -ErrorAction Stop

# Security boundary: only elevated Administrators and LocalSystem can write AulaGuard data.
# Machine DPAPI protects the local HMAC key at rest. ACLs protect the DPAPI blob from students.
$script:Entropy = [Text.Encoding]::UTF8.GetBytes('AulaGuard|machine-storage|v1')
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Assert-AulaGuardElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -and
        -not $identity.User.IsWellKnown([Security.Principal.WellKnownSidType]::LocalSystemSid)) {
        throw 'Se requiere una sesión de administrador elevada o LocalSystem.'
    }
}

function Assert-AulaGuardDataRoot {
    param([Parameter(Mandatory=$true)][string]$Root)
    $base = [IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\') + '\'
    $candidate = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $candidate.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or
        $candidate.Equals($base,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'La carpeta de datos debe estar dentro de ProgramData.'
    }
    $current = $candidate.TrimEnd('\')
    while ($current.Length -ge $base.Length) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Ruta insegura: punto de redirección detectado en $current."
            }
        }
        $next = Split-Path -Parent $current
        if (-not $next -or $next -eq $current) { break }
        $current = $next
    }
}

function Protect-AulaGuardDataAcl {
    param([Parameter(Mandatory=$true)][string]$Root)
    Assert-AulaGuardElevated
    Assert-AulaGuardDataRoot -Root $Root
    if (-not (Test-Path -LiteralPath $Root)) {
        [void](New-Item -ItemType Directory -Path $Root -Force)
    }
    $admins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    # Walk explicitly: never recurse through an attacker-created junction.
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        $item = Get-Item -LiteralPath $pending.Pop() -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Ruta insegura: punto de redirección detectado en $($item.FullName)."
        }
        $isDir = $item.PSIsContainer
        $acl = if ($isDir) {
            New-Object Security.AccessControl.DirectorySecurity
        } else {
            New-Object Security.AccessControl.FileSecurity
        }
        $acl.SetAccessRuleProtection($true,$false)
        $inheritance = if ($isDir) {
            [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        } else { [Security.AccessControl.InheritanceFlags]::None }
        foreach ($sid in @($admins,$system)) {
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $sid, [Security.AccessControl.FileSystemRights]::FullControl,
                $inheritance, [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow
            )
            [void]$acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $item.FullName -AclObject $acl -ErrorAction Stop
        if ($isDir) {
            foreach ($child in (Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop)) {
                $pending.Push($child.FullName)
            }
        }
    }
}

function Get-AulaGuardSecret {
    param([Parameter(Mandatory=$true)][string]$Root,[switch]$Create)
    $path = Join-Path $Root 'config\machine-key.dpapi'
    if (Test-Path -LiteralPath $path) {
        $encrypted = [IO.File]::ReadAllBytes($path)
        try {
            $key = [Security.Cryptography.ProtectedData]::Unprotect(
                $encrypted,$script:Entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
        } catch { throw 'La clave criptográfica de AulaGuard está dañada o pertenece a otro equipo.' }
        if ($key.Length -ne 32) { throw 'Longitud de clave criptográfica inválida.' }
        return ,$key
    }
    if (-not $Create) { throw 'Falta la clave de integridad: configuración no confiable.' }
    Assert-AulaGuardElevated
    $key = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($key) } finally { $rng.Dispose() }
    $encrypted = [Security.Cryptography.ProtectedData]::Protect(
        $key,$script:Entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
    $stream = New-Object IO.FileStream(
        $path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($encrypted,0,$encrypted.Length); $stream.Flush() }
    finally { $stream.Dispose() }
    return ,$key
}

function Get-AulaGuardHmac {
    param([byte[]]$Bytes,[byte[]]$Key)
    $h = [Security.Cryptography.HMACSHA256]::new($Key)
    try { return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $h.Dispose() }
}

function Test-AulaGuardEqualMac {
    param([string]$Expected,[string]$Actual)
    if ($Expected -notmatch '^[0-9a-fA-F]{64}$' -or $Actual -notmatch '^[0-9a-fA-F]{64}$') { return $false }
    $a = [Text.Encoding]::ASCII.GetBytes($Expected.ToLowerInvariant())
    $b = [Text.Encoding]::ASCII.GetBytes($Actual.ToLowerInvariant())
    $difference = 0
    for ($i=0; $i -lt $a.Length; $i++) { $difference = $difference -bor ($a[$i] -bxor $b[$i]) }
    return ($difference -eq 0)
}

function Set-AulaGuardSignedFile {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][byte[]]$Data,
          [Parameter(Mandatory=$true)][string]$Root)
    Assert-AulaGuardElevated
    $key = Get-AulaGuardSecret -Root $Root
    $mac = Get-AulaGuardHmac -Bytes $Data -Key $key
    $id = [guid]::NewGuid().ToString('N')
    $tmp = "$Path.$id.tmp"
    $tmpMac = "$Path.mac.$id.tmp"
    try {
        [IO.File]::WriteAllBytes($tmp,$Data)
        [IO.File]::WriteAllText($tmpMac,$mac,$script:Utf8)
        Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
        Move-Item -LiteralPath $tmpMac -Destination "$Path.mac" -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $tmp,$tmpMac -Force -ErrorAction SilentlyContinue
    }
}

function Assert-AulaGuardSignedFile {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Root)
    if (-not (Test-Path -LiteralPath $Path) -or -not (Test-Path -LiteralPath "$Path.mac")) {
        throw 'Configuración sin firma de integridad. No se aplicarán políticas.'
    }
    $key = Get-AulaGuardSecret -Root $Root
    $actual = Get-AulaGuardHmac -Bytes ([IO.File]::ReadAllBytes($Path)) -Key $key
    $expected = [IO.File]::ReadAllText("$Path.mac").Trim()
    if (-not (Test-AulaGuardEqualMac -Expected $expected -Actual $actual)) {
        throw 'ALERTA: La configuración de AulaGuard fue modificada o está corrupta.'
    }
}

function Initialize-AulaGuardSecurity {
    param([string]$Root = (Join-Path $env:ProgramData 'AulaGuard'),[switch]$MigrateLegacy)
    Assert-AulaGuardElevated
    Assert-AulaGuardDataRoot -Root $Root
    # Lock the root first so standard users cannot race creation of subdirectories.
    Protect-AulaGuardDataAcl -Root $Root
    foreach ($directory in @('config','logs','backup','profiles')) {
        $path = Join-Path $Root $directory
        if (-not (Test-Path -LiteralPath $path)) {
            [void](New-Item -ItemType Directory -Path $path -Force)
        }
    }
    Protect-AulaGuardDataAcl -Root $Root
    $settings = Join-Path $Root 'config\settings.json'
    $keyPath = Join-Path $Root 'config\machine-key.dpapi'
    if (-not (Test-Path -LiteralPath $keyPath)) {
        if ((Test-Path -LiteralPath $settings) -and -not $MigrateLegacy) {
            throw 'Configuración antigua sin protección: revise y migre con -MigrateLegacy.'
        }
        [void](Get-AulaGuardSecret -Root $Root -Create)
        if (Test-Path -LiteralPath $settings) {
            # Migration requires a deliberate admin action; never automatically trust a legacy Enforce profile.
            $legacy = [IO.File]::ReadAllText($settings) | ConvertFrom-Json -ErrorAction Stop
            $legacy | Add-Member NoteProperty policyMode 'Audit' -Force
            if ($legacy.PSObject.Properties.Name -contains 'appControl' -and $null -ne $legacy.appControl) {
                $legacy.appControl | Add-Member NoteProperty enabled $false -Force
                $legacy.appControl | Add-Member NoteProperty mode 'AuditOnly' -Force
            }
            $safeBytes = $script:Utf8.GetBytes(($legacy | ConvertTo-Json -Depth 12))
            Set-AulaGuardSignedFile -Path $settings -Data $safeBytes -Root $Root
        }
    }
    if (Test-Path -LiteralPath $settings) {
        Assert-AulaGuardSignedFile -Path $settings -Root $Root
    }
}

function ConvertTo-AulaGuardAuditBytes {
    param($Entry)
    $signed = [ordered]@{
        timestamp = [string]$Entry.timestamp
        level = [string]$Entry.level
        computer = [string]$Entry.computer
        user = [string]$Entry.user
        action = [string]$Entry.action
        detail = [string]$Entry.detail
        prev = [string]$Entry.prev
    }
    return ,$script:Utf8.GetBytes(($signed | ConvertTo-Json -Compress -Depth 4))
}

function Test-AulaGuardAuditContent {
    param([string]$Text,[byte[]]$Key)
    $previous = '0' * 64
    $count = 0
    foreach ($line in ($Text -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json -ErrorAction Stop } catch {
            throw "Entrada de auditoría inválida en línea $($count + 1)."
        }
        $names = @($entry.PSObject.Properties.Name)
        if ($names.Count -ne 8 -or
            @('timestamp','level','computer','user','action','detail','prev','mac').Where({$names -notcontains $_}).Count -gt 0) {
            throw "Estructura de auditoría inválida en línea $($count + 1)."
        }
        $computed = Get-AulaGuardHmac -Bytes (ConvertTo-AulaGuardAuditBytes -Entry $entry) -Key $Key
        if ($entry.prev -cne $previous -or -not (Test-AulaGuardEqualMac -Expected $entry.mac -Actual $computed)) {
            throw "Cadena de auditoría alterada en línea $($count + 1)."
        }
        $previous = [string]$entry.mac
        $count++
    }
    return [pscustomobject]@{ Count=$count; LastMac=$previous }
}

function Write-AulaGuardSecureAudit {
    param([string]$Action,[string]$Detail = '',
          [ValidateSet('INFO','WARN','ERROR','SECURITY')][string]$Level = 'INFO',
          [string]$Root = (Join-Path $env:ProgramData 'AulaGuard'))
    Assert-AulaGuardElevated
    $key = Get-AulaGuardSecret -Root $Root
    $path = Join-Path $Root ("logs\secure-audit-{0}.jsonl" -f (Get-Date -Format 'yyyy-MM-dd'))
    $stream = New-Object IO.FileStream($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
    try {
        $reader = New-Object IO.StreamReader($stream,$script:Utf8,$true,1024,$true)
        try { $existing = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $state = Test-AulaGuardAuditContent -Text $existing -Key $key
        $entry = [ordered]@{
            timestamp = (Get-Date).ToString('o')
            level = $Level
            computer = $env:COMPUTERNAME
            user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            action = $Action
            detail = $Detail
            prev = $state.LastMac
        }
        $entry['mac'] = Get-AulaGuardHmac -Bytes (ConvertTo-AulaGuardAuditBytes -Entry $entry) -Key $key
        $writer = New-Object IO.StreamWriter($stream,$script:Utf8,1024,$true)
        try {
            [void]$stream.Seek(0,[IO.SeekOrigin]::End)
            $writer.WriteLine(($entry | ConvertTo-Json -Compress -Depth 4))
            $writer.Flush()
            $stream.Flush($true)
        } finally { $writer.Dispose() }
    } finally { $stream.Dispose() }
}

function Test-AulaGuardAuditLog {
    param([Parameter(Mandatory=$true)][string]$Path,
          [string]$Root = (Join-Path $env:ProgramData 'AulaGuard'))
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $logs = [IO.Path]::GetFullPath((Join-Path $Root 'logs')).TrimEnd('\') + '\'
        if (-not $full.StartsWith($logs,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Archivo fuera de la carpeta de auditoría.'
        }
        $key = Get-AulaGuardSecret -Root $Root
        $verified = Test-AulaGuardAuditContent -Text ([IO.File]::ReadAllText($full)) -Key $key
        return [pscustomobject]@{ Valid=$true; Count=$verified.Count; Detail='Cadena HMAC verificada.' }
    } catch {
        return [pscustomobject]@{ Valid=$false; Count=0; Detail=$_.Exception.Message }
    }
}

Export-ModuleMember -Function Assert-AulaGuardElevated,Protect-AulaGuardDataAcl,Get-AulaGuardSecret,Initialize-AulaGuardSecurity,Set-AulaGuardSignedFile,Assert-AulaGuardSignedFile,Write-AulaGuardSecureAudit,Test-AulaGuardAuditLog
