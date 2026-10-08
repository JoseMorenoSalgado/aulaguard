Set-StrictMode -Version Latest

# Inventory only. Nothing returned by this module is launched or allowed
# automatically. Every effective allow rule still requires admin confirmation.
function Get-AulaGuardAppProperty {
    param([object]$Item,[string]$Name,[string]$Default='')
    if ($null -eq $Item) { return $Default }
    $p = $Item.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return [string]$p.Value
}

function Resolve-AulaGuardExecutablePath {
    param([string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }
    $source = [Environment]::ExpandEnvironmentVariables($Candidate.Trim())
    $exe = $null
    if ($source -match '^\s*"([^"]+\.exe)"(?:\s*,\s*-?\d+)?\s*$') {
        $exe = $Matches[1]
    } elseif ($source -match '^\s*(.+?\.exe)(?:\s*,\s*-?\d+)?\s*$') {
        $exe = $Matches[1]
    } else { return $null }
    try {
        if (-not [IO.Path]::IsPathRooted($exe) -or $exe -notmatch '^[a-zA-Z]:\\') { return $null }
        $full = [IO.Path]::GetFullPath($exe)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
        return $full
    } catch { return $null }
}

function New-AulaGuardAppRecord {
    param([string]$Name,[string]$Publisher,[string]$Version,[string]$Type,[string]$Path,[string]$Source)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $valid = if ($Type -eq 'Win32') { Resolve-AulaGuardExecutablePath $Path } else { $null }
    return [pscustomobject]@{
        Name = $Name.Trim()
        Publisher = [string]$Publisher
        Version = [string]$Version
        Type = $Type
        ExecutablePath = if ($valid) { $valid } else { '' }
        CanAllow = [bool]$valid
        Reason = if ($valid) { '' } elseif ($Type -eq 'Store') {
            'Microsoft Store: las reglas de paquetes aún no están implementadas.'
        } else { 'No se encontró el archivo ejecutable: usa Agregar EXE.' }
        Source = $Source
    }
}

function Get-AulaGuardInstalledApplications {
    [CmdletBinding()]
    param([switch]$SkipStore,[switch]$SkipShortcuts)

    $found = New-Object 'System.Collections.Generic.List[object]'
    foreach ($location in @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        foreach ($item in @(Get-ItemProperty -Path $location -ErrorAction SilentlyContinue)) {
            $name = Get-AulaGuardAppProperty $item 'DisplayName'
            if (-not $name -or (Get-AulaGuardAppProperty $item 'SystemComponent') -eq '1') { continue }
            $exe = Resolve-AulaGuardExecutablePath (Get-AulaGuardAppProperty $item 'DisplayIcon')
            $dir = Get-AulaGuardAppProperty $item 'InstallLocation'
            if (-not $exe -and $dir -and (Test-Path -LiteralPath $dir -PathType Container)) {
                # Top-level only, no recursive filesystem scan.
                $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -notmatch '(?i)^(unins|uninstall|setup|update|crash|helper)' } |
                    Select-Object -First 20)
                $simple = $name -replace '[^a-zA-Z0-9]',''
                $match = @($files | Where-Object { ($_.BaseName -replace '[^a-zA-Z0-9]','') -eq $simple } | Select-Object -First 1)
                if ($match.Count -eq 1) { $exe = $match[0].FullName }
                elseif ($files.Count -eq 1) { $exe = $files[0].FullName }
            }
            $rec = New-AulaGuardAppRecord -Name $name -Publisher (Get-AulaGuardAppProperty $item 'Publisher') -Version (Get-AulaGuardAppProperty $item 'DisplayVersion') -Type 'Win32' -Path $exe -Source 'Programas instalados'
            if ($rec) { $found.Add($rec) }
        }
    }

    # Windows App Paths entries often have a reliable executable even if the
    # uninstall registry points to an icon dll rather than an .exe.
    foreach ($location in @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
        'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'
    )) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $location -ErrorAction SilentlyContinue)) {
            $item = Get-Item -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            $target = try { [string]$item.GetValue('') } catch { '' }
            $valid = Resolve-AulaGuardExecutablePath $target
            if (-not $valid) { continue }
            $rec = New-AulaGuardAppRecord -Name ([IO.Path]::GetFileNameWithoutExtension($entry.PSChildName)) -Publisher '' -Version '' -Type 'Win32' -Path $valid -Source 'Windows App Paths'
            if ($rec) { $found.Add($rec) }
        }
    }

    if (-not $SkipShortcuts) {
        $startMenus = @([Environment]::GetFolderPath('CommonPrograms'),[Environment]::GetFolderPath('Programs')) |
            Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
        $shell = $null
        try { $shell = New-Object -ComObject WScript.Shell -ErrorAction Stop } catch {}
        if ($shell) {
            foreach ($folder in $startMenus) {
                foreach ($shortcut in @(Get-ChildItem -LiteralPath $folder -Recurse -File -Filter '*.lnk' -ErrorAction SilentlyContinue |
                    Select-Object -First 600)) {
                    try {
                        $target = $shell.CreateShortcut($shortcut.FullName).TargetPath
                        $valid = Resolve-AulaGuardExecutablePath $target
                        if (-not $valid) { continue }
                        $rec = New-AulaGuardAppRecord -Name $shortcut.BaseName -Publisher '' -Version '' -Type 'Win32' -Path $valid -Source 'Menú Inicio'
                        if ($rec) { $found.Add($rec) }
                    } catch { continue }
                }
            }
        }
    }

    if (-not $SkipStore) {
        try {
            foreach ($package in @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
                -not $_.IsFramework -and -not $_.IsResourcePackage -and $_.Name -notmatch '^Microsoft\.(Windows|VCLibs|NET|UI\.Xaml)'
            })) {
                $rec = New-AulaGuardAppRecord -Name ([string]$package.Name) -Publisher ([string]$package.Publisher) -Version ([string]$package.Version) -Type 'Store' -Path '' -Source 'Microsoft Store'
                if ($rec) { $found.Add($rec) }
            }
        } catch {
            Write-Verbose "No se pudieron consultar aplicaciones Store: $($_.Exception.Message)"
        }
    }

    $unique = @{}
    foreach ($app in $found) {
        if (-not $app) { continue }
        $key = if ($app.ExecutablePath) { 'exe:' + $app.ExecutablePath.ToLowerInvariant() }
            else { $app.Type.ToLowerInvariant() + ':' + $app.Name.ToLowerInvariant() }
        if (-not $unique.ContainsKey($key) -or
            ($app.Source -eq 'Programas instalados' -and $unique[$key].Source -ne 'Programas instalados')) {
            $unique[$key] = $app
        }
    }
    return @($unique.Values | Sort-Object Name,Type)
}

Export-ModuleMember -Function Get-AulaGuardInstalledApplications,Resolve-AulaGuardExecutablePath
