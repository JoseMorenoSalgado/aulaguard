Set-StrictMode -Version Latest

function Get-AulaGuardSystemInfo {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
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
    $adminGroup = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
    $admins = @(Get-LocalGroupMember -Group $adminGroup.Name -ErrorAction Stop)
    $adminSids = @($admins | Where-Object { $null -ne $_.SID } | ForEach-Object { $_.SID.Value })
    $profiles = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object {
        -not $_.Special -and $_.LocalPath -and $_.SID
    })

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

function New-AulaGuardReadinessCheck {
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][bool]$Passed,
        [ValidateSet('Info','Warning','Critical')][string]$Severity = 'Info',
        [string]$Detail = '',
        [bool]$BlocksPolicies = $false,
        [bool]$BlocksAppControl = $false
    )
    [pscustomobject]@{
        Code = $Code
        Name = $Name
        Passed = $Passed
        Severity = if ($Passed) { 'Info' } else { $Severity }
        Detail = $Detail
        BlocksPolicies = [bool]$BlocksPolicies
        BlocksAppControl = [bool]$BlocksAppControl
    }
}

function Test-AulaGuardReadiness {
    [CmdletBinding()]
    param(
        [string]$Root = (Join-Path $env:ProgramData 'AulaGuard'),
        $Settings = $null
    )

    $checks = New-Object 'System.Collections.Generic.List[object]'

    $isAdmin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $checks.Add((New-AulaGuardReadinessCheck -Code 'ADMIN' -Name 'Permisos de administrador' -Passed $isAdmin -Severity Critical -Detail 'Necesarios para administrar políticas de Windows.' -BlocksPolicies $true -BlocksAppControl $true))

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $caption = [string]$os.Caption
        $supported = ($caption -match 'Windows 10|Windows 11')
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'WINDOWS' -Name 'Windows compatible' -Passed $supported -Severity Critical -Detail "$caption · build $($os.BuildNumber)" -BlocksPolicies $true -BlocksAppControl $true))
        $editionRecommended = ($caption -match 'Pro|Enterprise|Education')
        $editionDetail = if ($editionRecommended) { $caption } else { 'Se recomienda Windows Pro, Enterprise o Education para administración de aula.' }
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'EDITION' -Name 'Edición recomendada' -Passed $editionRecommended -Severity Warning -Detail $editionDetail))
    } catch {
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'WINDOWS' -Name 'Windows compatible' -Passed $false -Severity Critical -Detail $_.Exception.Message -BlocksPolicies $true -BlocksAppControl $true))
    }

    $checks.Add((New-AulaGuardReadinessCheck -Code 'POWERSHELL' -Name 'PowerShell 5.1 o superior' -Passed ($PSVersionTable.PSVersion.Major -ge 5) -Severity Critical -Detail $PSVersionTable.PSVersion.ToString() -BlocksPolicies $true -BlocksAppControl $true))

    try {
        $freeGB = [double]((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop).FreeSpace / 1GB)
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'DISK' -Name 'Espacio libre' -Passed ($freeGB -ge 0.5) -Severity Warning -Detail ("{0:N1} GB libres en C:" -f $freeGB)))
    } catch {
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'DISK' -Name 'Espacio libre' -Passed $false -Severity Warning -Detail 'No fue posible consultar el disco del sistema.'))
    }

    try {
        Assert-AulaGuardSignedFile -Path (Join-Path $Root 'config\settings.json') -Root $Root
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'SETTINGS' -Name 'Configuración protegida' -Passed $true -Detail 'Firma HMAC de configuración válida.' -BlocksPolicies $true -BlocksAppControl $true))
    } catch {
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'SETTINGS' -Name 'Configuración protegida' -Passed $false -Severity Critical -Detail $_.Exception.Message -BlocksPolicies $true -BlocksAppControl $true))
    }

    try {
        $users = @(Get-AulaGuardLocalUsers)
        $students = @($users | Where-Object { -not $_.IsAdministrator })
        $studentDetail = if ($students.Count -gt 0) { "$($students.Count) perfil(es) estándar detectado(s)." } else { 'No hay perfiles estándar a los que aplicar políticas.' }
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'STUDENTS' -Name 'Perfiles de estudiantes' -Passed ($students.Count -gt 0) -Severity Critical -Detail $studentDetail -BlocksPolicies $true -BlocksAppControl $true))
    } catch {
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'STUDENTS' -Name 'Perfiles de estudiantes' -Passed $false -Severity Critical -Detail $_.Exception.Message -BlocksPolicies $true -BlocksAppControl $true))
    }

    try {
        $commands = @('Get-AppLockerFileInformation','New-AppLockerPolicy','Get-AppLockerPolicy','Set-AppLockerPolicy','Test-AppLockerPolicy')
        $missing = @($commands | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        $service = Get-Service -Name AppIDSvc -ErrorAction SilentlyContinue
        $ok = ($missing.Count -eq 0 -and $null -ne $service)
        $detail = if ($ok) { "AppLocker disponible · Application Identity: $($service.Status)" } else { "Faltan: $($missing -join ', ')$(if (-not $service) {' · Servicio AppIDSvc no disponible'})" }
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'APPLOCKER' -Name 'Motor de control de aplicaciones' -Passed $ok -Severity Critical -Detail $detail -BlocksAppControl $true))
    } catch {
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'APPLOCKER' -Name 'Motor de control de aplicaciones' -Passed $false -Severity Critical -Detail $_.Exception.Message -BlocksAppControl $true))
    }

    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $defender = Get-MpComputerStatus -ErrorAction Stop
            $active = [bool]$defender.AntivirusEnabled
            $defenderDetail = if ($active) { "Antivirus activo · firmas $($defender.AntivirusSignatureVersion)" } else { 'Microsoft Defender no está activo.' }
            [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'DEFENDER' -Name 'Microsoft Defender' -Passed $active -Severity Warning -Detail $defenderDetail))
        } else {
            [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'DEFENDER' -Name 'Microsoft Defender' -Passed $false -Severity Warning -Detail 'No se puede consultar Microsoft Defender en este equipo.'))
        }
    } catch {
        [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'DEFENDER' -Name 'Microsoft Defender' -Passed $false -Severity Warning -Detail $_.Exception.Message))
    }

    if ($null -ne $Settings) {
        try {
            if ($Settings.protections.lockWallpaper -and -not [string]::IsNullOrWhiteSpace([string]$Settings.wallpaper)) {
                [void](Test-AulaGuardWallpaperFile -Path ([string]$Settings.wallpaper))
            }
            $wallpaperDetail = if ($Settings.protections.lockWallpaper) { 'Imagen institucional disponible.' } else { 'Control de fondo desactivado.' }
            [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'WALLPAPER' -Name 'Fondo institucional' -Passed $true -Detail $wallpaperDetail -BlocksPolicies $true))
        } catch {
            [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'WALLPAPER' -Name 'Fondo institucional' -Passed $false -Severity Critical -Detail $_.Exception.Message -BlocksPolicies $true))
        }

        try {
            $usbState = Join-Path $Root 'config\usb-policy-state.json'
            if (Test-Path -LiteralPath $usbState -PathType Leaf) {
                Assert-AulaGuardSignedFile -Path $usbState -Root $Root
            } elseif (Test-Path -LiteralPath "$usbState.mac") {
                throw 'Existe una firma USB sin su archivo de estado.'
            }
            [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'USBSTATE' -Name 'Estado de memorias USB' -Passed $true -Detail 'Estado de restauración consistente.' -BlocksPolicies $true))
        } catch {
            [void]$checks.Add((New-AulaGuardReadinessCheck -Code 'USBSTATE' -Name 'Estado de memorias USB' -Passed $false -Severity Critical -Detail $_.Exception.Message -BlocksPolicies $true))
        }
    }

    return $checks.ToArray()
}

function Export-AulaGuardDiagnosticReport {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Root = (Join-Path $env:ProgramData 'AulaGuard'),
        $Settings = $null
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Selecciona una ruta para el diagnóstico.' }
    $full = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($full) -ine '.json') { throw 'El diagnóstico debe guardarse como archivo .json.' }
    $checks = @(Test-AulaGuardReadiness -Root $Root -Settings $Settings)
    $report = [pscustomobject]@{
        schema = 'AulaGuard-Diagnostics/1'
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        aulaGuardVersion = if ($Settings -and $Settings.version) { [string]$Settings.version } else { 'unknown' }
        system = Get-AulaGuardSystemInfo
        readiness = Get-AulaGuardReadinessSummary -Checks $checks
        checks = @($checks | Select-Object Code,Name,Passed,Severity,Detail,BlocksPolicies,BlocksAppControl)
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $full -Encoding UTF8 -ErrorAction Stop
    return $full
}

function Get-AulaGuardReadinessSummary {
    param([object[]]$Checks)
    $all = @($Checks)
    $critical = @($all | Where-Object { -not $_.Passed -and $_.Severity -eq 'Critical' }).Count
    $warnings = @($all | Where-Object { -not $_.Passed -and $_.Severity -eq 'Warning' }).Count
    [pscustomobject]@{
        Total = $all.Count
        Passed = @($all | Where-Object {$_.Passed}).Count
        Critical = $critical
        Warnings = $warnings
        Ready = ($critical -eq 0)
        PoliciesReady = (@($all | Where-Object { -not $_.Passed -and $_.BlocksPolicies }).Count -eq 0)
        AppControlReady = (@($all | Where-Object { -not $_.Passed -and $_.BlocksAppControl }).Count -eq 0)
    }
}

Export-ModuleMember -Function Get-AulaGuardSystemInfo,Get-AulaGuardLocalUsers,Test-AulaGuardReadiness,Get-AulaGuardReadinessSummary,Export-AulaGuardDiagnosticReport
