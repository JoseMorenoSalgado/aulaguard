Set-StrictMode -Version Latest

function Get-TargetUserProfiles {
    $adminSids = @()
    try {
        $adminSids = @(Get-LocalGroupMember -Group (Get-LocalGroup -SID 'S-1-5-32-544').Name -ErrorAction Stop | ForEach-Object { $_.SID.Value })
    } catch {}

    Get-CimInstance Win32_UserProfile | Where-Object {
        -not $_.Special -and $_.SID -and $_.LocalPath -and ($adminSids -notcontains $_.SID)
    }
}

function Invoke-WithUserHive {
    param(
        [Parameter(Mandatory=$true)]$Profile,
        [Parameter(Mandatory=$true)][scriptblock]$Script
    )

    $sid = $Profile.SID
    $loaded = Test-Path "Registry::HKEY_USERS\$sid"
    $mountName = "AulaGuard_$($sid.Replace('-','_'))"
    $mountRoot = "Registry::HKEY_USERS\$mountName"
    $didLoad = $false

    try {
        if ($loaded) {
            & $Script "Registry::HKEY_USERS\$sid"
            return
        }

        $ntUser = Join-Path $Profile.LocalPath 'NTUSER.DAT'
        if (-not (Test-Path $ntUser)) { return }

        & reg.exe load "HKU\$mountName" "$ntUser" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "No se pudo cargar $ntUser" }
        $didLoad = $true
        & $Script $mountRoot
    }
    finally {
        if ($didLoad) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            & reg.exe unload "HKU\$mountName" | Out-Null
        }
    }
}

function Set-RegistryDword {
    param([string]$Path,[string]$Name,[int]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Remove-RegistryValueSafe {
    param([string]$Path,[string]$Name)
    if (Test-Path $Path) {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    }
}

function Set-AulaGuardBrowserWhitelist {
    param(
        [string]$HiveRoot,
        [string[]]$AllowedWebsites
    )

    $edge = Join-Path $HiveRoot 'Software\Policies\Microsoft\Edge'
    $chrome = Join-Path $HiveRoot 'Software\Policies\Google\Chrome'

    foreach ($root in @($edge,$chrome)) {
        if (-not (Test-Path $root)) { New-Item $root -Force | Out-Null }
        $block = Join-Path $root 'URLBlocklist'
        $allow = Join-Path $root 'URLAllowlist'
        Remove-Item $block,$allow -Recurse -Force -ErrorAction SilentlyContinue
        New-Item $block -Force | Out-Null
        New-ItemProperty $block -Name '1' -PropertyType String -Value '*' -Force | Out-Null

        New-Item $allow -Force | Out-Null
        $i = 1
        foreach ($site in $AllowedWebsites) {
            if (-not [string]::IsNullOrWhiteSpace($site)) {
                New-ItemProperty $allow -Name ([string]$i) -PropertyType String -Value $site.Trim() -Force | Out-Null
                $i++
            }
        }
    }
}

function Clear-AulaGuardBrowserWhitelist {
    param([string]$HiveRoot)
    foreach ($root in @(
        (Join-Path $HiveRoot 'Software\Policies\Microsoft\Edge'),
        (Join-Path $HiveRoot 'Software\Policies\Google\Chrome')
    )) {
        Remove-Item (Join-Path $root 'URLBlocklist') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $root 'URLAllowlist') -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Apply-AulaGuardPolicies {
    param(
        [Parameter(Mandatory=$true)]$Settings,
        [switch]$WhatIfMode
    )

    # Fail before touching any student's registry if an image is missing,
    # private or malformed. The default blank wallpaper does not set a new image.
    if (-not $WhatIfMode -and $Settings.protections.lockWallpaper -and
        -not [string]::IsNullOrWhiteSpace([string]$Settings.wallpaper)) {
        [void](Test-AulaGuardWallpaperFile -Path ([string]$Settings.wallpaper))
    }
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($profile in Get-TargetUserProfiles) {
        if ($WhatIfMode) {
            $results.Add([pscustomobject]@{User=(Split-Path $profile.LocalPath -Leaf); Status='SIMULADO'; Detail='No se realizaron cambios.'})
            continue
        }

        try {
            Invoke-WithUserHive -Profile $profile -Script {
                param($hive)
                $explorer = Join-Path $hive 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
                $system = Join-Path $hive 'Software\Microsoft\Windows\CurrentVersion\Policies\System'
                $activeDesktop = Join-Path $hive 'Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'
                $desktop = Join-Path $hive 'Control Panel\Desktop'

                if ($Settings.protections.lockWallpaper) {
                    Set-RegistryDword $activeDesktop 'NoChangingWallPaper' 1
                    if ($Settings.wallpaper) {
                        if (-not (Test-Path $desktop)) { New-Item $desktop -Force | Out-Null }
                        New-ItemProperty $desktop -Name 'Wallpaper' -PropertyType String -Value $Settings.wallpaper -Force | Out-Null
                        New-ItemProperty $desktop -Name 'WallpaperStyle' -PropertyType String -Value '10' -Force | Out-Null
                        New-ItemProperty $desktop -Name 'TileWallpaper' -PropertyType String -Value '0' -Force | Out-Null
                    }
                } else {
                    Remove-RegistryValueSafe $activeDesktop 'NoChangingWallPaper'
                }

                if ($Settings.protections.disablePersonalization) {
                    Set-RegistryDword $explorer 'NoThemesTab' 1
                } else {
                    Remove-RegistryValueSafe $explorer 'NoThemesTab'
                }

                foreach ($pair in @(
                    @{Name='NoControlPanel'; Enabled=[bool]$Settings.protections.blockControlPanel},
                    @{Name='DisableRegistryTools'; Enabled=[bool]$Settings.protections.blockRegistryTools},
                    @{Name='DisableTaskMgr'; Enabled=[bool]$Settings.protections.blockTaskManager}
                )) {
                    $target = if ($pair.Name -eq 'NoControlPanel') { $explorer } else { $system }
                    if ($pair.Enabled) { Set-RegistryDword $target $pair.Name 1 }
                    else { Remove-RegistryValueSafe $target $pair.Name }
                }

                if ($Settings.protections.browserWhitelist) {
                    Set-AulaGuardBrowserWhitelist -HiveRoot $hive -AllowedWebsites @($Settings.allowedWebsites)
                } else {
                    Clear-AulaGuardBrowserWhitelist -HiveRoot $hive
                }
            }

            $results.Add([pscustomobject]@{User=(Split-Path $profile.LocalPath -Leaf); Status='OK'; Detail='Políticas aplicadas.'})
        } catch {
            $results.Add([pscustomobject]@{User=(Split-Path $profile.LocalPath -Leaf); Status='ERROR'; Detail=$_.Exception.Message})
        }
    }

    return $results
}

function Reset-AulaGuardPolicies {
    param([string[]]$ManagedWallpapers = @())
    # When previous releases left an inaccessible wallpaper path, restore the
    # Windows bundled image only when the value still matches AulaGuard's path.
    $windowsWallpaper = Join-Path $env:WINDIR 'Web\Wallpaper\Windows\img0.jpg'
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($profile in Get-TargetUserProfiles) {
        try {
            Invoke-WithUserHive -Profile $profile -Script {
                param($hive)
                $explorer = Join-Path $hive 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
                $system = Join-Path $hive 'Software\Microsoft\Windows\CurrentVersion\Policies\System'
                $activeDesktop = Join-Path $hive 'Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'

                Remove-RegistryValueSafe $activeDesktop 'NoChangingWallPaper'
                if (@($ManagedWallpapers).Count -gt 0 -and (Test-Path -LiteralPath $windowsWallpaper -PathType Leaf)) {
                    $desktop = Join-Path $hive 'Control Panel\Desktop'
                    if (Test-Path -LiteralPath $desktop) {
                        $current = [string](Get-ItemProperty -LiteralPath $desktop -Name 'Wallpaper' -ErrorAction SilentlyContinue).Wallpaper
                        if ($current -and @($ManagedWallpapers | Where-Object { $_ -and $_ -ieq $current }).Count -gt 0) {
                            New-ItemProperty -Path $desktop -Name 'Wallpaper' -PropertyType String -Value $windowsWallpaper -Force | Out-Null
                            New-ItemProperty -Path $desktop -Name 'WallpaperStyle' -PropertyType String -Value '10' -Force | Out-Null
                            New-ItemProperty -Path $desktop -Name 'TileWallpaper' -PropertyType String -Value '0' -Force | Out-Null
                        }
                    }
                }
                Remove-RegistryValueSafe $explorer 'NoThemesTab'
                Remove-RegistryValueSafe $explorer 'NoControlPanel'
                Remove-RegistryValueSafe $system 'DisableRegistryTools'
                Remove-RegistryValueSafe $system 'DisableTaskMgr'
                Clear-AulaGuardBrowserWhitelist -HiveRoot $hive
            }
            $results.Add([pscustomobject]@{User=(Split-Path $profile.LocalPath -Leaf); Status='OK'; Detail='Políticas de AulaGuard retiradas.'})
        } catch {
            $results.Add([pscustomobject]@{User=(Split-Path $profile.LocalPath -Leaf); Status='ERROR'; Detail=$_.Exception.Message})
        }
    }
    return $results
}

function Protect-AulaGuardPublicDesktop {
    param([switch]$Restore)
    $desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    if (-not (Test-Path $desktop)) { return }

    $users = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
    Get-ChildItem $desktop -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $acl = Get-Acl $_.FullName
        if ($Restore) {
            $acl.SetAccessRuleProtection($false,$true)
        } else {
            $acl.SetAccessRuleProtection($true,$true)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $users,
                'ReadAndExecute',
                'Allow'
            )
            $acl.SetAccessRule($rule)
        }
        Set-Acl $_.FullName $acl
    }
}

Export-ModuleMember -Function *