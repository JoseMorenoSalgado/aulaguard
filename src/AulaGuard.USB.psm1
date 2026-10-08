Set-StrictMode -Version Latest

# Per-user Removable Storage Access policy supported by Windows 10/11 Pro:
# HKCU\Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}\Deny_Read and Deny_Write
# Do not disable USBSTOR: USB keyboards, mice and administrator sessions must remain usable.
$script:UsbPolicySubkey = 'Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}'
$script:UsbPolicyValues = @('Deny_Read','Deny_Write')

function Get-AulaGuardUsbState {
    param([Parameter(Mandatory=$true)][string]$Root)
    $path = Join-Path $Root 'config\usb-policy-state.json'
    if (-not (Test-Path -LiteralPath $path)) {
        if (Test-Path -LiteralPath "$path.mac") { throw 'Estado USB sin archivo pero con firma: integridad no válida.' }
        return @{ version=1; profiles=@{} }
    }
    Assert-AulaGuardSignedFile -Path $path -Root $Root
    $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($data.version -ne 1 -or -not ($data.PSObject.Properties.Name -contains 'profiles')) {
        throw 'Estado de restauración USB desconocido.'
    }
    $profiles = @{}
    foreach ($prop in $data.profiles.PSObject.Properties) {
        if ($prop.Name -notmatch '^S-1-\d+(-\d+)+$') { throw 'SID inválido en estado de USB.' }
        $values = @{}
        foreach ($valueName in $script:UsbPolicyValues) {
            if (-not ($prop.Value.PSObject.Properties.Name -contains $valueName)) {
                throw 'Estado USB incompleto; no se restaurarán valores desconocidos.'
            }
            $snapshot = $prop.Value.$valueName
            if (-not ($snapshot.PSObject.Properties.Name -contains 'exists') -or
                -not ($snapshot.PSObject.Properties.Name -contains 'value')) {
                throw 'Copia de seguridad USB inválida.'
            }
            $values[$valueName] = @{ exists = [bool]$snapshot.exists; value = [int]$snapshot.value }
        }
        $profiles[$prop.Name] = $values
    }
    return @{ version=1; profiles=$profiles }
}

function Save-AulaGuardUsbState {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][hashtable]$State)
    $json = $State | ConvertTo-Json -Depth 6 -ErrorAction Stop
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
    Set-AulaGuardSignedFile -Path (Join-Path $Root 'config\usb-policy-state.json') -Data $bytes -Root $Root
}

function Get-AulaGuardUsbPolicyValue {
    param([Parameter(Mandatory=$true)][string]$HiveRoot)
    $path = Join-Path $HiveRoot $script:UsbPolicySubkey
    $values = @{}
    $item = if (Test-Path -LiteralPath $path) {
        Get-ItemProperty -LiteralPath $path -ErrorAction Stop
    } else { $null }
    foreach ($name in $script:UsbPolicyValues) {
        $exists = ($null -ne $item -and @($item.PSObject.Properties.Name) -contains $name)
        $values[$name] = @{
            exists = [bool]$exists
            value = if ($exists) { [int]$item.$name } else { 0 }
        }
    }
    return [pscustomobject]@{ Path=$path; Values=$values }
}

function Sync-AulaGuardUsbPolicy {
    param(
        [Parameter(Mandatory=$true)][bool]$BlockStorage,
        [Parameter(Mandatory=$true)][string]$Root,
        [switch]$WhatIfMode,
        [object[]]$Profiles = $null
    )
    Assert-AulaGuardElevated
    if ($null -eq $Profiles) { $Profiles = @(Get-TargetUserProfiles) }
    $state = Get-AulaGuardUsbState -Root $Root
    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($profile in @($Profiles)) {
        $sid = [string]$profile.SID
        $username = Split-Path $profile.LocalPath -Leaf
        if ($WhatIfMode) {
            $results.Add([pscustomobject]@{ User=$username; Status='SIMULADO'; Detail='Acceso USB sin cambios.' })
            continue
        }
        try {
            Invoke-WithUserHive -Profile $profile -Script {
                param([string]$hive)
                $current = Get-AulaGuardUsbPolicyValue -HiveRoot $hive
                if ($BlockStorage) {
                    if (-not $state.profiles.ContainsKey($sid)) {
                        $alreadyDenied = $true
                        foreach ($name in $script:UsbPolicyValues) {
                            if (-not $current.Values[$name].exists -or $current.Values[$name].value -ne 1) {
                                $alreadyDenied = $false
                            }
                        }
                        if ($alreadyDenied) {
                            # Existing GPO / administrative policy: do not take ownership.
                            return
                        }
                        $state.profiles[$sid] = $current.Values
                        # Authenticate recovery snapshot BEFORE changing registry values.
                        Save-AulaGuardUsbState -Root $Root -State $state
                    }
                    foreach ($name in $script:UsbPolicyValues) {
                        Set-RegistryDword -Path $current.Path -Name $name -Value 1
                    }
                } elseif ($state.profiles.ContainsKey($sid)) {
                    $original = $state.profiles[$sid]
                    foreach ($name in $script:UsbPolicyValues) {
                        if (-not $current.Values[$name].exists -or $current.Values[$name].value -ne 1) {
                            throw 'Restricción modificada externamente; no se sobrescribirán las directivas.'
                        }
                    }
                    foreach ($name in $script:UsbPolicyValues) {
                        if ($original[$name].exists) {
                            Set-RegistryDword -Path $current.Path -Name $name -Value ([int]$original[$name].value)
                        } else {
                            Remove-RegistryValueSafe -Path $current.Path -Name $name
                        }
                    }
                    $state.profiles.Remove($sid)
                    Save-AulaGuardUsbState -Root $Root -State $state
                }
            }
            $results.Add([pscustomobject]@{
                User=$username
                Status='OK'
                Detail=$(if ($BlockStorage) {'Lectura y escritura de discos USB extraíbles restringidas.'} else {'Valores USB originales restaurados.'})
            })
        } catch {
            $results.Add([pscustomobject]@{ User=$username; Status='ERROR'; Detail=$_.Exception.Message })
        }
    }
    return $results
}

function Get-AulaGuardRemovableDrives {
    try {
        return @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2' -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{
                    Letter = [string]$_.DeviceID
                    Name = [string]$_.VolumeName
                    FileSystem = [string]$_.FileSystem
                }
            })
    } catch { return @() }
}

Export-ModuleMember -Function Get-AulaGuardUsbState,Sync-AulaGuardUsbPolicy,Get-AulaGuardRemovableDrives
