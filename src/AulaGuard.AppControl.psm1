Set-StrictMode -Version Latest

function Test-AulaGuardAppLockerSupport {
    $required = @('Get-AppLockerFileInformation','New-AppLockerPolicy','Get-AppLockerPolicy','Set-AppLockerPolicy','Test-AppLockerPolicy')
    $missing = @()
    foreach ($cmd in $required) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { $missing += $cmd }
    }
    $service = Get-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Supported = ($missing.Count -eq 0 -and $null -ne $service)
        MissingCommands = $missing
        ServiceFound = ($null -ne $service)
        ServiceStatus = if ($service) { $service.Status.ToString() } else { 'No disponible' }
    }
}


function Sync-AulaGuardStudentsGroup {
    $groupName = 'AulaGuardStudents'

    if (-not (Get-LocalGroup -Name $groupName -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $groupName -Description 'Usuarios estándar administrados por AulaGuard' | Out-Null
    }

    $adminSids = @()
    try {
        $adminSids = @(Get-LocalGroupMember -Group (Get-LocalGroup -SID 'S-1-5-32-544').Name -ErrorAction Stop | ForEach-Object { $_.SID.Value })
    } catch {}

    $excluded = @('Administrator','Guest','DefaultAccount','WDAGUtilityAccount')
    $users = @(Get-LocalUser | Where-Object {
        $_.Enabled -and
        $excluded -notcontains $_.Name -and
        $adminSids -notcontains $_.SID.Value
    })

    $current = @()
    try { $current = @(Get-LocalGroupMember -Group $groupName -ErrorAction Stop) } catch {}

    foreach ($member in $current) {
        try { Remove-LocalGroupMember -Group $groupName -Member $member -ErrorAction SilentlyContinue } catch {}
    }

    foreach ($user in $users) {
        try { Add-LocalGroupMember -Group $groupName -Member $user.Name -ErrorAction Stop } catch {}
    }

    return [pscustomobject]@{
        Group = $groupName
        Users = @($users | Select-Object -ExpandProperty Name)
        Count = $users.Count
    }
}

function Enable-AulaGuardApplicationIdentity {
    $service = Get-Service -Name AppIDSvc -ErrorAction Stop
    try { Set-Service -Name AppIDSvc -StartupType Automatic -ErrorAction Stop }
    catch { & sc.exe config AppIDSvc start= auto | Out-Null }
    if ($service.Status -ne 'Running') { Start-Service -Name AppIDSvc -ErrorAction Stop }
    return (Get-Service -Name AppIDSvc)
}

function Get-AulaGuardExistingAppLockerPolicyXml {
    try { return (Get-AppLockerPolicy -Local -Xml -ErrorAction Stop) }
    catch { return $null }
}

function Backup-AulaGuardAppLockerPolicy {
    param([Parameter(Mandatory=$true)][string]$BackupDirectory)
    if (-not (Test-Path $BackupDirectory)) { New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null }
    $xml = Get-AulaGuardExistingAppLockerPolicyXml
    if ([string]::IsNullOrWhiteSpace($xml)) { return $null }
    $path = Join-Path $BackupDirectory ("applocker-{0}.xml" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Set-Content -Path $path -Value $xml -Encoding UTF8
    return $path
}

function Set-AulaGuardAppLockerEnforcementMode {
    param(
        [Parameter(Mandatory=$true)][string]$Xml,
        [ValidateSet('AuditOnly','Enabled')][string]$Mode
    )
    [xml]$doc = $Xml
    foreach ($collection in @($doc.AppLockerPolicy.RuleCollection)) { $collection.EnforcementMode = $Mode }
    return $doc.OuterXml
}

function New-AulaGuardAppLockerPolicyXml {
    param(
        [Parameter(Mandatory=$true)][string[]]$AllowedPrograms,
        [ValidateSet('AuditOnly','Enabled')][string]$Mode = 'AuditOnly'
    )

    $support = Test-AulaGuardAppLockerSupport
    if (-not $support.Supported) {
        throw "AppLocker no está disponible. Comandos faltantes: $($support.MissingCommands -join ', ')"
    }

    $validPrograms = @($AllowedPrograms | Where-Object { $_ -and (Test-Path $_ -PathType Leaf) } | Select-Object -Unique)
    $targetGroup = Sync-AulaGuardStudentsGroup
    if ($targetGroup.Count -eq 0) { throw 'No se detectaron usuarios estándar para aplicar el control de aplicaciones.' }

    if ($Mode -eq 'Enabled' -and $validPrograms.Count -eq 0) {
        throw 'No se puede activar el bloqueo sin al menos un programa autorizado. Use Auditoría primero.'
    }

    if ($validPrograms.Count -gt 0) {
        $fileInfo = Get-AppLockerFileInformation -Path $validPrograms -ErrorAction Stop
        $params = @{
            FileInformation = $fileInfo
            AllowWindows = $true
            RuleType = @('Publisher','Hash')
            User = $targetGroup.Group
            Optimize = $true
            IgnoreMissingFileInformation = $true
            Xml = $true
        }
        $xml = New-AppLockerPolicy @params
    } else {
        $params = @{
            AllowWindows = $true
            RuleType = @('Path')
            User = $targetGroup.Group
            Optimize = $true
            Xml = $true
        }
        $xml = New-AppLockerPolicy @params
    }

    if ([string]::IsNullOrWhiteSpace($xml)) { throw 'No fue posible generar la política AppLocker.' }
    return (Set-AulaGuardAppLockerEnforcementMode -Xml $xml -Mode $Mode)
}

function Test-AulaGuardGeneratedPolicy {
    param([Parameter(Mandatory=$true)][string]$Xml,[string[]]$Paths)
    $existing = @($Paths | Where-Object { $_ -and (Test-Path $_ -PathType Leaf) })
    if ($existing.Count -eq 0) { return @() }
    return @(Test-AppLockerPolicy -XmlPolicy $Xml -Path $existing -User 'AulaGuardStudents' -Filter All)
}

function Set-AulaGuardAppControlPolicy {
    param(
        [Parameter(Mandatory=$true)][string[]]$AllowedPrograms,
        [ValidateSet('AuditOnly','Enabled')][string]$Mode = 'AuditOnly',
        [Parameter(Mandatory=$true)][string]$BackupDirectory
    )

    Enable-AulaGuardApplicationIdentity | Out-Null
    $backup = Backup-AulaGuardAppLockerPolicy -BackupDirectory $BackupDirectory
    $xml = New-AulaGuardAppLockerPolicyXml -AllowedPrograms $AllowedPrograms -Mode $Mode
    $temp = Join-Path $env:TEMP ("AulaGuard-AppLocker-{0}.xml" -f ([guid]::NewGuid().ToString('N')))

    try {
        Set-Content -Path $temp -Value $xml -Encoding UTF8
        Set-AppLockerPolicy -XmlPolicy $temp -ErrorAction Stop
    } finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        Mode = $Mode
        Backup = $backup
        AllowedPrograms = @($AllowedPrograms).Count
        AppliedAt = Get-Date
    }
}

function Restore-AulaGuardAppLockerPolicy {
    param([Parameter(Mandatory=$true)][string]$BackupDirectory)
    $backup = Get-ChildItem -Path $BackupDirectory -Filter 'applocker-*.xml' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $backup) { throw 'No existe una copia de seguridad previa de AppLocker.' }
    Set-AppLockerPolicy -XmlPolicy $backup.FullName -ErrorAction Stop
    [pscustomobject]@{ RestoredFrom=$backup.FullName; RestoredAt=Get-Date }
}

function Get-AulaGuardAppLockerEvents {
    param([int]$MaxEvents = 200)

    $logs = @(
        'Microsoft-Windows-AppLocker/EXE and DLL',
        'Microsoft-Windows-AppLocker/MSI and Script',
        'Microsoft-Windows-AppLocker/Packaged app-Execution'
    )
    $events = New-Object System.Collections.Generic.List[object]

    foreach ($log in $logs) {
        try {
            foreach ($event in (Get-WinEvent -LogName $log -MaxEvents $MaxEvents -ErrorAction Stop)) {
                $message = $event.Message
                $path = $null
                if ($message -match '([A-Z]:\\[^\r\n"]+\.(exe|com|msi|msp|ps1|bat|cmd|vbs|js|dll|ocx))') { $path = $matches[1] }
                $events.Add([pscustomobject]@{
                    TimeCreated = $event.TimeCreated
                    EventId = $event.Id
                    Level = $event.LevelDisplayName
                    Log = $log
                    File = $path
                    Message = (($message -replace '\r?\n',' ') -replace '\s+',' ').Trim()
                })
            }
        } catch {}
    }

    return @($events | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents)
}

function Get-AulaGuardAppLockerAuditStatistics {
    try { return @(Get-AppLockerFileInformation -EventLog -EventType Audited -Statistics -ErrorAction Stop) }
    catch { return @() }
}

Export-ModuleMember -Function *