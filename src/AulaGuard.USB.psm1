Set-StrictMode -Version Latest

# Per-user Removable Storage Access policy supported by Windows 10/11 Pro:
# HKCU\Software\Policies\Microsoft\Windows\RemovableStorageDevices\Deny_All
# Do not disable USBSTOR: USB keyboards, mice and administrator sessions must remain usable.
$script:UsbPolicySubkey = 'Software\Policies\Microsoft\Windows\RemovableStorageDevices'
$script:UsbPolicyValue = 'Deny_All'

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
        $p = $prop.Value
        if (-not ($p.PSObject.Properties.Name -contains 'hadValue') -or
            -not ($p.PSObject.Properties.Name -contains 'oldValue') -or
            -not ($p.PSObject.Properties.Name -contains 'managedValue')) {
            throw 'Estado de USB sin información de restauración.'
        }
        $profiles[$prop.Name] = [pscustomobject]@{
            hadValue = [bool]$p.hadValue
            oldValue = [int]$p.oldValue
            managedValue = [int]$p.managedValue
        }
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
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ Exists=$false; Value=0; Path=$path }
    }
    $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
    $exists = @($item.PSObject.Properties.Name) -contains $script:UsbPolicyValue
    return [pscustomobject]@{
        Exists = $exists
        Value = if ($exists) { [int]$item.Deny_All } else { 0 }
        Path = $path
    }
}

function Sync-AulaGuardUsbPolicy {
    param(
        [Parameter(Mandatory=$true)][bool]$BlockStorage,
        [Parameter(Mandatory=$true)][string]$Root,
        [switch]$WhatIfMode
    )
    Assert-AulaGuardElevated
    $state = Get-AulaGuardUsbState -Root $Root
    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($profile in @(Get-TargetUserProfiles)) {
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
                    if ($state.profiles.ContainsKey($sid)) {
                        # Existing HMAC-authenticated ownership: reapply only our restriction.
                        Set-RegistryDword -Path $current.Path -Name 'Deny_All' -Value 1
                        return
                    }
                    if ($current.Exists -and $current.Value -eq 1) {
                        # Another administrator or domain policy already denies storage.
                        # Never claim ownership or undo it on restore.
                        return
                    }
                    # Commit the pre-existing value before modifying the Windows registry.
                    $state.profiles[$sid] = [pscustomobject]@{
                        hadValue = [bool]$current.Exists
                        oldValue = [int]$current.Value
                        managedValue = 1
                    }
                    Save-AulaGuardUsbState -Root $Root -State $state
                    Set-RegistryDword -Path $current.Path -Name 'Deny_All' -Value 1
                } elseif ($state.profiles.ContainsKey($sid)) {
                    $original = $state.profiles[$sid]
                    if (-not $current.Exists -or $current.Value -ne $original.managedValue) {
                        throw 'Política USB modificada por otro administrador; no se sobrescribirá.'
                    }
                    if ($original.hadValue) {
                        Set-RegistryDword -Path $current.Path -Name 'Deny_All' -Value $original.oldValue
                    } else {
                        Remove-RegistryValueSafe -Path $current.Path -Name 'Deny_All'
                    }
                    $state.profiles.Remove($sid)
                    Save-AulaGuardUsbState -Root $Root -State $state
                }
            }
            $results.Add([pscustomobject]@{
                User=$username
                Status='OK'
                Detail=$(if ($BlockStorage) {'Almacenamiento extraíble restringido (sin alterar administradores).'} else {'Política USB administrada por AulaGuard restaurada.'})
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
