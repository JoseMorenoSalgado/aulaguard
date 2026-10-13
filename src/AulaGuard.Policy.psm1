Set-StrictMode -Version Latest

function Get-TargetUserProfiles {
    $adminSids = @()
    try {
        $adminGroup = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
        $adminSids = @(Get-LocalGroupMember -Group $adminGroup.Name -ErrorAction Stop |
            Where-Object { $null -ne $_.SID } | ForEach-Object { $_.SID.Value })
    } catch {
        # An empty administrator list would include administrator profiles.
        # Fail closed rather than risk applying classroom restrictions to admins.
        throw "No se pudo identificar a los administradores de Windows: $($_.Exception.Message)"
    }
    $profiles = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object {
        -not $_.Special -and $_.SID -and $_.LocalPath -and ($adminSids -notcontains $_.SID)
    })
    return $profiles
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
        if (-not (Test-Path -LiteralPath $ntUser -PathType Leaf)) {
            throw "No se encontró el perfil NTUSER.DAT de $sid; no se aplicó ninguna política."
        }

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


function Set-AulaGuardPolicyForHive {
    param(
        [Parameter(Mandatory=$true)][string]$HiveRoot,
        [Parameter(Mandatory=$true)]$Settings
    )

    $explorer = Join-Path $HiveRoot 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $system = Join-Path $HiveRoot 'Software\Microsoft\Windows\CurrentVersion\Policies\System'
    $activeDesktop = Join-Path $HiveRoot 'Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'
    $desktop = Join-Path $HiveRoot 'Control Panel\Desktop'

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
        Set-AulaGuardBrowserWhitelist -HiveRoot $HiveRoot -AllowedWebsites @($Settings.allowedWebsites)
    } else {
        Clear-AulaGuardBrowserWhitelist -HiveRoot $HiveRoot
    }
}

function Test-AulaGuardPolicyEngine {
    param([Parameter(Mandatory=$true)]$Settings)

    $lab = "Registry::HKEY_CURRENT_USER\Software\AulaGuardPolicyLab_$([guid]::NewGuid().ToString('N'))"
    try {
        New-Item -Path $lab -Force | Out-Null
        Set-AulaGuardPolicyForHive -HiveRoot $lab -Settings $Settings

        $checks = New-Object 'System.Collections.Generic.List[object]'
        $explorer = Join-Path $lab 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        $system = Join-Path $lab 'Software\Microsoft\Windows\CurrentVersion\Policies\System'
        $activeDesktop = Join-Path $lab 'Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'

        $expected = @(
            @{Code='WALLPAPER'; Path=$activeDesktop; Name='NoChangingWallPaper'; Enabled=[bool]$Settings.protections.lockWallpaper},
            @{Code='PERSONALIZATION'; Path=$explorer; Name='NoThemesTab'; Enabled=[bool]$Settings.protections.disablePersonalization},
            @{Code='CONTROL_PANEL'; Path=$explorer; Name='NoControlPanel'; Enabled=[bool]$Settings.protections.blockControlPanel},
            @{Code='REGISTRY'; Path=$system; Name='DisableRegistryTools'; Enabled=[bool]$Settings.protections.blockRegistryTools},
            @{Code='TASK_MANAGER'; Path=$system; Name='DisableTaskMgr'; Enabled=[bool]$Settings.protections.blockTaskManager}
        )

        foreach ($item in $expected) {
            $value = $null
            if (Test-Path $item.Path) {
                $obj = Get-ItemProperty -LiteralPath $item.Path -Name $item.Name -ErrorAction SilentlyContinue
                if ($null -ne $obj) { $value = $obj.($item.Name) }
            }
            $passed = if ($item.Enabled) { $value -eq 1 } else { $null -eq $value }
            $checks.Add([pscustomobject]@{Code=$item.Code; Passed=$passed; Detail=$(if ($passed) {'Estado de registro correcto.'} else {'El motor no produjo el estado esperado.'})})
        }

        if ($Settings.protections.browserWhitelist) {
            $edgeAllow = Join-Path $lab 'Software\Policies\Microsoft\Edge\URLAllowlist'
            $edgeBlock = Join-Path $lab 'Software\Policies\Microsoft\Edge\URLBlocklist'
            $browserPassed = (Test-Path $edgeAllow) -and (Test-Path $edgeBlock)
        } else {
            $browserPassed = -not (Test-Path (Join-Path $lab 'Software\Policies\Microsoft\Edge\URLAllowlist'))
        }
        $checks.Add([pscustomobject]@{Code='BROWSER'; Passed=$browserPassed; Detail=$(if ($browserPassed) {'Lista web coherente.'} else {'La política web no quedó en el estado esperado.'})})

        return [pscustomobject]@{
            Passed = (@($checks | Where-Object { -not $_.Passed }).Count -eq 0)
            Checks = $checks.ToArray()
        }
    }
    finally {
        Remove-Item -LiteralPath $lab -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# Verify the actual target user's registry hive, not only the isolated
# preflight registry tree. This proves settings were written to the correct
# profile, but Windows may still require a sign-out for UI policy refresh.
function Test-AulaGuardAppliedPolicyForHive {
    param(
        [Parameter(Mandatory=$true)][string]$HiveRoot,
        [Parameter(Mandatory=$true)]$Settings
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $checked = 0
    $policies = @(
        @{ Name='NoChangingWallPaper'; Path=(Join-Path $HiveRoot 'Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'); Enabled=[bool]$Settings.protections.lockWallpaper },
        @{ Name='NoThemesTab'; Path=(Join-Path $HiveRoot 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'); Enabled=[bool]$Settings.protections.disablePersonalization },
        @{ Name='NoControlPanel'; Path=(Join-Path $HiveRoot 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'); Enabled=[bool]$Settings.protections.blockControlPanel },
        @{ Name='DisableRegistryTools'; Path=(Join-Path $HiveRoot 'Software\Microsoft\Windows\CurrentVersion\Policies\System'); Enabled=[bool]$Settings.protections.blockRegistryTools },
        @{ Name='DisableTaskMgr'; Path=(Join-Path $HiveRoot 'Software\Microsoft\Windows\CurrentVersion\Policies\System'); Enabled=[bool]$Settings.protections.blockTaskManager }
    )

    foreach ($policy in $policies) {
        $value = $null
        $exists = $false
        if (Test-Path -LiteralPath $policy.Path) {
            $properties = Get-ItemProperty -LiteralPath $policy.Path -ErrorAction Stop
            $exists = @($properties.PSObject.Properties.Name) -contains $policy.Name
            if ($exists) { $value = $properties.($policy.Name) }
        }
        $checked++
        $correct = if ($policy.Enabled) { $exists -and $value -eq 1 } else { -not $exists }
        if (-not $correct) { $errors.Add("$($policy.Name): el Registro no refleja la restricción solicitada.") }
    }

    foreach ($browser in @('Microsoft\Edge','Google\Chrome')) {
        $root = Join-Path $HiveRoot "Software\Policies\$browser"
        $blockPath = Join-Path $root 'URLBlocklist'
        $allowPath = Join-Path $root 'URLAllowlist'
        $checked++
        if ($Settings.protections.browserWhitelist) {
            $blocked = if (Test-Path -LiteralPath $blockPath) {
                (Get-ItemProperty -LiteralPath $blockPath -Name '1' -ErrorAction SilentlyContinue).'1'
            } else { $null }
            if ($blocked -cne '*' -or -not (Test-Path -LiteralPath $allowPath)) {
                $errors.Add("$browser : no se confirmó la lista blanca de sitios.")
                continue
            }
            $expected = @($Settings.allowedWebsites | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $actual = Get-ItemProperty -LiteralPath $allowPath -ErrorAction Stop
            for ($i = 0; $i -lt $expected.Count; $i++) {
                $name = [string]($i + 1)
                if (($actual.PSObject.Properties.Name -notcontains $name) -or
                    ([string]$actual.$name -cne ([string]$expected[$i]).Trim())) {
                    $errors.Add("$browser : sitio permitido $($i+1) ausente o diferente.")
                }
            }
        } else {
            if (Test-Path -LiteralPath $blockPath) { $errors.Add("$browser : quedó un bloqueo anterior.") }
            if (Test-Path -LiteralPath $allowPath) { $errors.Add("$browser : quedó una lista de excepciones anterior.") }
        }
    }

    return [pscustomobject]@{
        Passed = ($errors.Count -eq 0)
        CheckCount = $checked
        Errors = @($errors.ToArray())
    }
}

function Set-AulaGuardPolicies {
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
    $profiles = @(Get-TargetUserProfiles)
    if ($profiles.Count -eq 0 -and -not $WhatIfMode) {
        throw 'No se encontraron perfiles estándar de estudiantes. Crea o inicia sesión al menos una vez con un usuario estándar y vuelve a aplicar la protección.'
    }
    foreach ($profile in $profiles) {
        if ($WhatIfMode) {
            $results.Add([pscustomobject]@{User=(Split-Path $profile.LocalPath -Leaf); Status='SIMULADO'; Detail='No se realizaron cambios.'})
            continue
        }

        try {
            $verified = $null
            Invoke-WithUserHive -Profile $profile -Script {
                param($hive)
                Set-AulaGuardPolicyForHive -HiveRoot $hive -Settings $Settings
                $verified = Test-AulaGuardAppliedPolicyForHive -HiveRoot $hive -Settings $Settings
                if (-not $verified.Passed) { throw ($verified.Errors -join ' | ') }
            }

            $results.Add([pscustomobject]@{User=(Split-Path $profile.LocalPath -Leaf); Status='OK'; Detail='Restricciones verificadas en el Registro del estudiante; cerrar sesión para actualizar Windows.'})
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