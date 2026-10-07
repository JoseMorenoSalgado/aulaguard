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
        version = '0.3.1'
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
    Initialize-AulaGuardStorage -Root $Root | Out-Null
    $defaults = New-AulaGuardSettings
    $path = Get-AulaGuardSettingsPath -Root $Root

    if (-not (Test-Path $path)) { return $defaults }

    try {
        $s = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json

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

        if (-not ($s.PSObject.Properties.Name -contains 'appControl') -or $null -eq $s.appControl) {
            $s | Add-Member NoteProperty appControl $defaults.appControl -Force
        } else {
            foreach ($property in $defaults.appControl.PSObject.Properties.Name) {
                if (-not ($s.appControl.PSObject.Properties.Name -contains $property)) {
                    $s.appControl | Add-Member NoteProperty $property $defaults.appControl.$property
                }
            }
        }

        $s.version = '0.3.1'
        return $s
    }
    catch {
        return $defaults
    }
}

function Save-AulaGuardSettings {
    param(
        [Parameter(Mandatory=$true)]$Settings,
        [string]$Root = (Get-AulaGuardRoot)
    )
    Initialize-AulaGuardStorage -Root $Root | Out-Null
    $path = Get-AulaGuardSettingsPath -Root $Root
    $tmp = "$path.tmp"
    $Settings | ConvertTo-Json -Depth 8 | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Path $tmp -Destination $path -Force
    return $path
}

function Write-AulaGuardAudit {
    param(
        [Parameter(Mandatory=$true)][string]$Action,
        [string]$Detail = '',
        [ValidateSet('INFO','WARN','ERROR','SECURITY')][string]$Level = 'INFO',
        [string]$Root = (Get-AulaGuardRoot)
    )
    Initialize-AulaGuardStorage -Root $Root | Out-Null
    $path = Join-Path $Root ("logs\audit-{0}.jsonl" -f (Get-Date -Format 'yyyy-MM-dd'))
    $entry = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        level = $Level
        computer = $env:COMPUTERNAME
        user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        action = $Action
        detail = $Detail
    }
    ($entry | ConvertTo-Json -Compress) | Add-Content -Path $path -Encoding UTF8
}

function Backup-AulaGuardConfiguration {
    param([string]$Root = (Get-AulaGuardRoot))
    Initialize-AulaGuardStorage -Root $Root | Out-Null
    $source = Get-AulaGuardSettingsPath -Root $Root
    if (-not (Test-Path $source)) { return $null }
    $dest = Join-Path $Root ("backup\settings-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item $source $dest -Force
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
    $settings = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Save-AulaGuardSettings -Settings $settings -Root $Root | Out-Null
    Write-AulaGuardAudit -Action 'PROFILE_IMPORT' -Detail $Path -Root $Root
    return $settings
}

Export-ModuleMember -Function *