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
        version = '0.3.6'
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

    foreach ($property in @('version','profileName','policyMode','wallpaper','allowedPrograms','allowedWebsites','protectedShortcuts','appControl','auditEnabled','lastAppliedUtc')) {
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
    if ($s.policyMode -notin @('Audit','Enforce') -or $s.appControl.mode -notin @('AuditOnly','Enabled')) {
        throw 'Modo de políticas inválido en configuración protegida.'
    }
    $s.version = '0.3.6'
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
    if (-not ($settings.PSObject.Properties.Name -contains 'protections') -or
        -not ($settings.PSObject.Properties.Name -contains 'appControl')) {
        throw 'El archivo importado no es un perfil AulaGuard válido.'
    }
    Save-AulaGuardSettings -Settings $settings -Root $Root | Out-Null
    Write-AulaGuardAudit -Action 'PROFILE_IMPORT' -Detail $Path -Root $Root
    return $settings
}

Export-ModuleMember -Function *