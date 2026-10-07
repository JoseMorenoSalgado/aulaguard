Set-StrictMode -Version Latest

function Get-AulaGuardSystemInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        Windows = $os.Caption
        Version = $os.Version
        Build = $os.BuildNumber
        Architecture = $os.OSArchitecture
        MemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        FreeDiskGB = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 1) } else { $null }
        PowerShell = $PSVersionTable.PSVersion.ToString()
        Domain = $cs.Domain
    }
}

function Get-AulaGuardLocalUsers {
    $adminSids = @()
    try {
        $admins = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop
        $adminSids = @($admins | ForEach-Object { $_.SID.Value })
    } catch {}

    $profiles = Get-CimInstance Win32_UserProfile | Where-Object {
        -not $_.Special -and $_.LocalPath -and $_.SID
    }

    foreach ($p in $profiles) {
        [pscustomobject]@{
            SID = $p.SID
            User = Split-Path $p.LocalPath -Leaf
            Path = $p.LocalPath
            Loaded = [bool]$p.Loaded
            IsAdministrator = ($adminSids -contains $p.SID)
        }
    }
}

function Test-AulaGuardReadiness {
    $checks = @()

    $checks += [pscustomobject]@{
        Name='Ejecutando como administrador'
        Passed=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
        Detail='Necesario para aplicar y revertir políticas.'
    }

    $checks += [pscustomobject]@{
        Name='PowerShell 5.1 o superior'
        Passed=($PSVersionTable.PSVersion.Major -ge 5)
        Detail=$PSVersionTable.PSVersion.ToString()
    }

    $checks += [pscustomobject]@{
        Name='Windows Pro/Enterprise/Education'
        Passed=((Get-CimInstance Win32_OperatingSystem).Caption -match 'Pro|Enterprise|Education')
        Detail=(Get-CimInstance Win32_OperatingSystem).Caption
    }

    $checks += [pscustomobject]@{
        Name='Carpeta ProgramData disponible'
        Passed=(Test-Path $env:ProgramData)
        Detail=$env:ProgramData
    }

    return $checks
}

Export-ModuleMember -Function *