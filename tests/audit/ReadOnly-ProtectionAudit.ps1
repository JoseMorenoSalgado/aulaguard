# AulaGuard v0.5.5 - read-only protection audit.
# This script DOES NOT set policies, touch ACLs, load offline hives or disable security software.
[CmdletBinding()]
param(
    [string]$InstallSource = (Join-Path $env:ProgramFiles 'AulaGuard\src'),
    [string]$DataRoot = (Join-Path $env:ProgramData 'AulaGuard'),
    [string]$ReportPath = (Join-Path $env:TEMP ('AulaGuard-Auditoria-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json'))
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'Este diagnóstico requiere Windows.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Ejecute este diagnóstico en PowerShell como administrador.'
}
if ([IO.Path]::GetExtension($ReportPath) -ne '.json') { throw 'El reporte debe ser JSON.' }
if ([IO.Path]::GetFullPath($ReportPath).StartsWith([IO.Path]::GetFullPath($DataRoot).TrimEnd('\') + '\',
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'No guarde el reporte dentro de la carpeta privada de AulaGuard.'
}

foreach ($name in @(
    'AulaGuard.Security.psm1',
    'AulaGuard.Core.psm1',
    'AulaGuard.Policy.psm1',
    'AulaGuard.USB.psm1',
    'AulaGuard.Diagnostics.psm1',
    'AulaGuard.Wallpaper.psm1'
)) {
    $file = Join-Path $InstallSource $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "No existe el módulo instalado: $file"
    }
    Import-Module -Name $file -Force -ErrorAction Stop
}

# Reading this value authenticates the settings using AulaGuard's existing HMAC.
$settings = Read-AulaGuardSettings -Root $DataRoot
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
$profiles = @(Get-TargetUserProfiles)
$observations = New-Object 'System.Collections.Generic.List[object]'

foreach ($profile in $profiles) {
    $sid = [string]$profile.SID
    $hive = "Registry::HKEY_USERS\$sid"
    $entry = [ordered]@{
        sid = $sid
        profileLoaded = [bool](Test-Path -LiteralPath $hive)
        policyRegistryState = 'NOT_CHECKED'
        policyDetails = @()
        usbRegistryState = 'NOT_CHECKED'
    }
    if (-not $entry.profileLoaded) {
        $entry.policyRegistryState = 'UNKNOWN_OFFLINE_HIVE'
        $entry.policyDetails = @('Se requiere iniciar sesión con el alumno para inspeccionar su hive sin montarlo.')
        $entry.usbRegistryState = 'UNKNOWN_OFFLINE_HIVE'
        $observations.Add([pscustomobject]$entry)
        continue
    }

    if ($settings.policyMode -ne 'Enforce') {
        $entry.policyRegistryState = 'AUDIT_MODE'
        $entry.policyDetails = @('Auditoría: la configuración guardada no solicita bloqueo general nuevo.')
    } else {
        try {
            $check = Test-AulaGuardAppliedPolicyForHive -HiveRoot $hive -Settings $settings
            $entry.policyRegistryState = if ($check.Passed) { 'REGISTRY_MATCH' } else { 'REGISTRY_MISMATCH' }
            $entry.policyDetails = @($check.Errors)
        } catch {
            $entry.policyRegistryState = 'ERROR'
            $entry.policyDetails = @($_.Exception.Message)
        }
    }

    try {
        $usbPath = Join-Path $hive 'Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}'
        $denyRead = $null
        $denyWrite = $null
        if (Test-Path -LiteralPath $usbPath) {
            $props = Get-ItemProperty -LiteralPath $usbPath -ErrorAction Stop
            if (@($props.PSObject.Properties.Name) -contains 'Deny_Read') { $denyRead = $props.Deny_Read }
            if (@($props.PSObject.Properties.Name) -contains 'Deny_Write') { $denyWrite = $props.Deny_Write }
        }
        if ($settings.policyMode -ne 'Enforce') {
            $entry.usbRegistryState = 'AUDIT_MODE'
        } elseif ($settings.usb.blockStorage) {
            $entry.usbRegistryState = if ($denyRead -eq 1 -and $denyWrite -eq 1) {
                'REGISTRY_MATCH'
            } else { 'REGISTRY_MISMATCH' }
        } else {
            $entry.usbRegistryState = 'NOT_REQUESTED'
        }
    } catch {
        $entry.usbRegistryState = 'ERROR: ' + $_.Exception.Message
    }
    $observations.Add([pscustomobject]$entry)
}

$studentsGroup = [ordered]@{ exists=$false; memberSids=@(); error=$null }
try {
    $group = Get-LocalGroup -Name 'AulaGuardStudents' -ErrorAction SilentlyContinue
    if ($group) {
        $studentsGroup.exists = $true
        $studentsGroup.memberSids = @(
            Get-LocalGroupMember -Group $group.Name -ErrorAction Stop |
            Where-Object { $null -ne $_.SID } |
            ForEach-Object { $_.SID.Value }
        )
    }
} catch { $studentsGroup.error = $_.Exception.Message }

$appLocker = [ordered]@{
    configured = [bool]$settings.appControl.enabled
    requestedMode = [string]$settings.appControl.mode
    appIdentityService = 'UNKNOWN'
    effectivePolicyRead = $false
    effectiveCollections = @()
    recentExeEventIds = @()
    error = $null
}
try {
    $svc = Get-Service -Name AppIDSvc -ErrorAction Stop
    $appLocker.appIdentityService = $svc.Status.ToString()
    $xmlText = Get-AppLockerPolicy -Effective -Xml -ErrorAction Stop
    [xml]$xml = $xmlText
    $appLocker.effectivePolicyRead = $true
    $appLocker.effectiveCollections = @(
        foreach ($collection in @($xml.AppLockerPolicy.RuleCollection)) {
            [pscustomobject]@{
                type = [string]$collection.Type
                enforcement = [string]$collection.EnforcementMode
                ruleCount = @($collection.ChildNodes | Where-Object {
                    $_.NodeType -eq [System.Xml.XmlNodeType]::Element
                }).Count
            }
        }
    )
    try {
        $appLocker.recentExeEventIds = @(
            Get-WinEvent -FilterHashtable @{
                LogName = 'Microsoft-Windows-AppLocker/EXE and DLL'
                StartTime = (Get-Date).AddDays(-1)
            } -MaxEvents 30 -ErrorAction Stop | Select-Object -ExpandProperty Id
        )
    } catch {}
} catch { $appLocker.error = $_.Exception.Message }

$tasks = New-Object 'System.Collections.Generic.List[object]'
foreach ($name in @('PolicySync','PolicySyncLogon')) {
    try {
        $task = Get-ScheduledTask -TaskName $name -TaskPath '\AulaGuard\' -ErrorAction Stop
        $history = Get-ScheduledTaskInfo -TaskName $name -TaskPath '\AulaGuard\' -ErrorAction Stop
        $tasks.Add([pscustomobject]@{
            task=$name
            exists=$true
            state=$task.State.ToString()
            lastTaskResult=$history.LastTaskResult
            lastRunTime=$history.LastRunTime
        })
    } catch {
        $tasks.Add([pscustomobject]@{task=$name;exists=$false;error=$_.Exception.Message})
    }
}

$report = [ordered]@{
    schema = 'AulaGuard-ReadOnlyAudit/1'
    collectedAtUtc = [datetime]::UtcNow.ToString('o')
    system = [pscustomobject]@{windows=$os.Caption; build=$os.BuildNumber}
    savedModes = [pscustomobject]@{
        policyMode = $settings.policyMode
        maintenanceEnabled = [bool]$settings.maintenance.enabled
        usbBlockRequested = [bool]$settings.usb.blockStorage
        browserWhitelistRequested = [bool]$settings.protections.browserWhitelist
        allowedWebsitesCount = @($settings.allowedWebsites).Count
    }
    profiles = @($observations.ToArray())
    appLockerStudentsGroup = $studentsGroup
    appLocker = $appLocker
    scheduledTasks = @($tasks.ToArray())
    limits = @(
        'REGISTRY_MATCH no confirma bloqueo funcional en Windows.',
        'UNKNOWN_OFFLINE_HIVE no es un fallo de política. Inicie sesión como estudiante.',
        'No se ha ejecutado un EXE prohibido ni probado un USB físico.',
        'No se han aplicado ni restaurado restricciones.'
    )
}

$report | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $ReportPath -Encoding UTF8 -ErrorAction Stop
Write-Host "Auditoría de solo lectura guardada en: $ReportPath"
Write-Host "Modo general: $($settings.policyMode); alumnos con perfil: $($profiles.Count)"
Write-Host "AppLocker solicitado: $($appLocker.configured); servicio: $($appLocker.appIdentityService)"
Write-Host 'El informe contiene identificadores SID de cuentas locales. Revíselo antes de compartirlo.'
