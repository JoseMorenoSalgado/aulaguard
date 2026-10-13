Set-StrictMode -Version Latest

function Get-AulaGuardRoot {
    $installedRoot = Join-Path $env:ProgramData 'AulaGuard'
    if (Test-Path (Join-Path $installedRoot 'config')) { return $installedRoot }
    return (Split-Path -Parent $PSScriptRoot)
}

function Test-AulaGuardAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-AulaGuardStorage {
    param([string]$Root = (Get-AulaGuardRoot))
    foreach ($name in @('config','logs','backup','profiles')) {
        $path = Join-Path $Root $name
        if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }
    return $Root
}

function Get-AulaGuardSettingsPath {
    param([string]$Root = (Get-AulaGuardRoot))
    return (Join-Path $Root 'config\settings.json')
}

function New-AulaGuardSettings {
    [pscustomobject]@{
        version = '0.5.5'
        profileName = 'Aula principal'
        policyMode = 'Audit'
        wallpaper = ''
        allowedPrograms = @()
        allowedWebsites = @()
        protectedShortcuts = @()
        protections = [pscustomobject]@{
            lockWallpaper = $true
            disablePersonalization = $true
            protectPublicDesktop = $true
            browserWhitelist = $false
            blockControlPanel = $false
            blockRegistryTools = $false
            blockTaskManager = $false
            blockCommandPrompt = $false
            blockPowerShell = $false
        }
        appControl = [pscustomobject]@{
            mode = 'AuditOnly'
            enabled = $false
            lastAppliedUtc = $null
            lastBackup = $null
        }
        usb = [pscustomobject]@{
            blockStorage = $false
        }
        maintenance = [pscustomobject]@{
            enabled = $false
            expiresUtc = $null
            previousPolicyMode = 'Audit'
            previousAppControlMode = 'AuditOnly'
            previousAppControlEnabled = $false
        }
        premium = [pscustomobject]@{
            serverMode = 'LocalOnly'
            endpoint = ''
            deviceId = ''
        }
        auditEnabled = $true
        lastAppliedUtc = $null
    }
}

function Read-AulaGuardSettings {
    param([string]$Root = (Get-AulaGuardRoot))
    $path = Get-AulaGuardSettingsPath -Root $Root
    # Never silently fall back to permissive defaults when the signed state is missing or corrupt.
    Assert-AulaGuardSignedFile -Path $path -Root $Root
    $defaults = New-AulaGuardSettings
    $s = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

    foreach ($property in @('version','profileName','policyMode','wallpaper','allowedPrograms','allowedWebsites','protectedShortcuts','appControl','usb','maintenance','premium','auditEnabled','lastAppliedUtc')) {
        if (-not ($s.PSObject.Properties.Name -contains $property)) {
            $s | Add-Member NoteProperty $property $defaults.$property
        }
    }
    if (-not ($s.PSObject.Properties.Name -contains 'protections') -or $null -eq $s.protections) {
        $s | Add-Member NoteProperty protections $defaults.protections -Force
    } else {
        foreach ($property in $defaults.protections.PSObject.Properties.Name) {
            if (-not ($s.protections.PSObject.Properties.Name -contains $property)) {
                $s.protections | Add-Member NoteProperty $property $defaults.protections.$property
            }
        }
    }
    if ($null -eq $s.appControl) {
        $s | Add-Member NoteProperty appControl $defaults.appControl -Force
    } else {
        foreach ($property in $defaults.appControl.PSObject.Properties.Name) {
            if (-not ($s.appControl.PSObject.Properties.Name -contains $property)) {
                $s.appControl | Add-Member NoteProperty $property $defaults.appControl.$property
            }
        }
    }
    if ($null -eq $s.usb) {
        $s | Add-Member NoteProperty usb $defaults.usb -Force
    } elseif (-not ($s.usb.PSObject.Properties.Name -contains 'blockStorage')) {
        $s.usb | Add-Member NoteProperty blockStorage $false
    }
    if ($null -eq $s.maintenance) {
        $s | Add-Member NoteProperty maintenance $defaults.maintenance -Force
    } else {
        foreach ($property in $defaults.maintenance.PSObject.Properties.Name) {
            if (-not ($s.maintenance.PSObject.Properties.Name -contains $property)) {
                $s.maintenance | Add-Member NoteProperty $property $defaults.maintenance.$property
            }
        }
    }
    if ($null -eq $s.premium) {
        $s | Add-Member NoteProperty premium $defaults.premium -Force
    } else {
        foreach ($property in $defaults.premium.PSObject.Properties.Name) {
            if (-not ($s.premium.PSObject.Properties.Name -contains $property)) {
                $s.premium | Add-Member NoteProperty $property $defaults.premium.$property
            }
        }
    }
    # Premium network operation is not implemented. Imported profiles cannot enable it.
    $s.premium.serverMode = 'LocalOnly'
    $s.premium.endpoint = ''
    $s.premium.deviceId = ''
    if ($s.policyMode -notin @('Audit','Enforce') -or $s.appControl.mode -notin @('AuditOnly','Enabled')) {
        throw 'Modo de políticas inválido en configuración protegida.'
    }
    $s.version = '0.5.5'
    return $s
}

function Save-AulaGuardSettings {
    param(
        [Parameter(Mandatory=$true)]$Settings,
        [string]$Root = (Get-AulaGuardRoot)
    )
    Assert-AulaGuardElevated
    $path = Get-AulaGuardSettingsPath -Root $Root
    if ($Settings.policyMode -notin @('Audit','Enforce') -or
        $Settings.appControl.mode -notin @('AuditOnly','Enabled')) {
        throw 'Modo de políticas inválido.'
    }
    if ($Settings.PSObject.Properties.Name -contains 'maintenance' -and $null -ne $Settings.maintenance) {
        if ([bool]$Settings.maintenance.enabled) {
            if ([string]::IsNullOrWhiteSpace([string]$Settings.maintenance.expiresUtc)) {
                throw 'Modo mantenimiento activo sin fecha de expiración.'
            }
            try {
                $expiry = [datetime]::Parse(
                    [string]$Settings.maintenance.expiresUtc,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::RoundtripKind
                )
            } catch {
                throw 'Fecha de expiración del modo mantenimiento inválida.'
            }
            if ($Settings.maintenance.previousPolicyMode -notin @('Audit','Enforce') -or
                $Settings.maintenance.previousAppControlMode -notin @('AuditOnly','Enabled')) {
                throw 'Estado previo del modo mantenimiento inválido.'
            }
        }
    }
    if ($Settings.PSObject.Properties.Name -contains 'premium') {
        if ($Settings.premium.serverMode -ne 'LocalOnly' -or
            -not [string]::IsNullOrEmpty([string]$Settings.premium.endpoint)) {
            throw 'La conexión Premium no está implementada; no se guardarán credenciales ni endpoints.'
        }
    }
    $json = $Settings | ConvertTo-Json -Depth 12 -ErrorAction Stop
    if ($json.Length -gt 1048576) { throw 'El perfil excede el tamaño permitido (1 MB).' }
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
    Set-AulaGuardSignedFile -Path $path -Data $bytes -Root $Root
    return $path
}

function Write-AulaGuardAudit {
    param(
        [Parameter(Mandatory=$true)][string]$Action,
        [string]$Detail = '',
        [ValidateSet('INFO','WARN','ERROR','SECURITY')][string]$Level = 'INFO',
        [string]$Root = (Get-AulaGuardRoot)
    )
    Write-AulaGuardSecureAudit -Action $Action -Detail $Detail -Level $Level -Root $Root
}

function Backup-AulaGuardConfiguration {
    param([string]$Root = (Get-AulaGuardRoot))
    Initialize-AulaGuardStorage -Root $Root | Out-Null
    $source = Get-AulaGuardSettingsPath -Root $Root
    if (-not (Test-Path $source)) { return $null }
    $dest = Join-Path $Root ("backup\settings-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Assert-AulaGuardSignedFile -Path $source -Root $Root
    Copy-Item -LiteralPath $source -Destination $dest -Force
    Copy-Item -LiteralPath "$source.mac" -Destination "$dest.mac" -Force
    Write-AulaGuardAudit -Action 'CONFIG_BACKUP' -Detail $dest -Root $Root
    return $dest
}

function Export-AulaGuardProfile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Root = (Get-AulaGuardRoot)
    )
    $settings = Read-AulaGuardSettings -Root $Root
    $settings | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
    Write-AulaGuardAudit -Action 'PROFILE_EXPORT' -Detail $Path -Root $Root
}

function Import-AulaGuardProfile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Root = (Get-AulaGuardRoot)
    )
    $settings = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $settings -or
        -not ($settings.PSObject.Properties.Name -contains 'protections') -or
        -not ($settings.PSObject.Properties.Name -contains 'appControl') -or
        $null -eq $settings.protections) {
        throw 'El archivo importado no es un perfil AulaGuard válido.'
    }
    # Exported JSON is not authenticated. It must NEVER activate a policy just
    # because a third-party or older machine exported policyMode=Enforce.
    $previous = Read-AulaGuardSettings -Root $Root
    $defaults = New-AulaGuardSettings
    foreach ($property in $defaults.PSObject.Properties.Name) {
        if (-not ($settings.PSObject.Properties.Name -contains $property)) {
            $settings | Add-Member NoteProperty $property $defaults.$property
        }
    }
    foreach ($name in $defaults.protections.PSObject.Properties.Name) {
        if (-not ($settings.protections.PSObject.Properties.Name -contains $name)) {
            $settings.protections | Add-Member NoteProperty $name $defaults.protections.$name
        }
    }
    # Preserve the actual AppLocker state recorded for this computer. Importing
    # another machine's flags must not falsely claim that policies were applied.
    $settings.appControl = $previous.appControl
    $settings.policyMode = 'Audit'
    $settings.wallpaper = ''
    $settings.protections.lockWallpaper = $false
    $settings.usb = $defaults.usb
    $settings.maintenance = $defaults.maintenance
    $settings.premium = $defaults.premium
    $settings.lastAppliedUtc = $previous.lastAppliedUtc
    $settings.version = $defaults.version
    Save-AulaGuardSettings -Settings $settings -Root $Root | Out-Null
    Write-AulaGuardAudit -Action 'PROFILE_IMPORT' -Detail 'Perfil externo importado en modo Auditoría; estado AppLocker local preservado; fondo y USB requieren nueva configuración.' -Root $Root
    return $settings
}

Export-ModuleMember -Function *