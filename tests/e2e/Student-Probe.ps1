# AulaGuard - read-only student-session E2E probe.
# Run interactively as a STANDARD student, never with Run as Administrator.
# Does not modify policy, wallpaper, browser settings or attached drives.
[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path $env:ProgramData 'AulaGuardLab\manifest.json'),
    [string]$ReportPath = (Join-Path $env:TEMP 'AulaGuard-Student-E2E.json'),
    [string]$DeniedFixturePath = '',
    [string]$AllowedExecutable = '',
    [string]$UsbDrive = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'Se requiere Windows.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'La prueba debe ejecutarse con la cuenta estándar del estudiante, sin elevación.'
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw 'Falta el manifiesto del administrador. Ejecuta Admin-Preflight.ps1 primero.'
}

$manifestItem = Get-Item -LiteralPath $ManifestPath -Force
if (($manifestItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Se rechaza un manifiesto que es un enlace o punto de redirección.'
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
if ($manifest.schema -ne 'AulaGuard-LabManifest/1' -or $null -eq $manifest.expected) {
    throw 'Formato de manifiesto de laboratorio no reconocido.'
}
if ($manifest.computer -ine $env:COMPUTERNAME -or $manifest.studentSid -cne $identity.User.Value) {
    throw 'El manifiesto pertenece a otro equipo o a otra cuenta de estudiante.'
}
$issued = [datetime]::Parse(
    [string]$manifest.generatedUtc,
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::RoundtripKind
).ToUniversalTime()
$age = ([datetime]::UtcNow - $issued).TotalHours
if ($age -lt -0.1 -or $age -gt 24) {
    throw 'El manifiesto tiene más de 24 horas o una fecha inválida; genera uno nuevo.'
}

$results = New-Object 'System.Collections.Generic.List[object]'
function Add-ProbeResult {
    param(
        [string]$Code,
        [ValidateSet('PASS','FAIL','SKIP','INCONCLUSIVE')][string]$Status,
        [string]$Detail
    )
    $script:results.Add([pscustomobject]@{Code=$Code;Status=$Status;Detail=$Detail})
}
function Read-PolicyDword {
    param([string]$Path,[string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{Exists=$false;Value=$null}
    }
    $properties = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    if ($properties.PSObject.Properties.Name -contains $Name) {
        return [pscustomobject]@{Exists=$true;Value=[int]$properties.$Name}
    }
    return [pscustomobject]@{Exists=$false;Value=$null}
}
function Assert-DwordExpectation {
    param([string]$Code,[string]$Path,[string]$Name,[bool]$Enabled)
    if ($manifest.expected.policyMode -ne 'Enforce') {
        Add-ProbeResult $Code 'SKIP' 'Protección general en Auditoría; no corresponde exigir bloqueo.'
        return
    }
    try {
        $item = Read-PolicyDword -Path $Path -Name $Name
        $ok = if ($Enabled) { $item.Exists -and $item.Value -eq 1 } else { -not $item.Exists }
        if ($ok) { Add-ProbeResult $Code 'PASS' 'Valor esperado en HKCU.' }
        else { Add-ProbeResult $Code 'FAIL' "Valor inesperado en HKCU: $Name; existe=$($item.Exists); valor=$($item.Value)." }
    } catch {
        Add-ProbeResult $Code 'FAIL' "Error leyendo la política: $($_.Exception.Message)"
    }
}

$explorer = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$system = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\System'
$activeDesktop = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'

Assert-DwordExpectation 'WALLPAPER_REGISTRY' $activeDesktop 'NoChangingWallPaper' ([bool]$manifest.expected.lockWallpaper)
Assert-DwordExpectation 'PERSONALIZATION_REGISTRY' $explorer 'NoThemesTab' ([bool]$manifest.expected.disablePersonalization)
Assert-DwordExpectation 'CONTROL_PANEL_REGISTRY' $explorer 'NoControlPanel' ([bool]$manifest.expected.blockControlPanel)
Assert-DwordExpectation 'REGISTRY_TOOLS_REGISTRY' $system 'DisableRegistryTools' ([bool]$manifest.expected.blockRegistryTools)
Assert-DwordExpectation 'TASK_MANAGER_REGISTRY' $system 'DisableTaskMgr' ([bool]$manifest.expected.blockTaskManager)

if ($manifest.expected.policyMode -ne 'Enforce') {
    Add-ProbeResult 'BROWSER_REGISTRY' 'SKIP' 'En modo Auditoría no se esperan restricciones activas.'
} else {
    try {
        $ok = $true
        foreach ($browser in @('Microsoft\Edge','Google\Chrome')) {
            $root = "Registry::HKEY_CURRENT_USER\Software\Policies\$browser"
            $blocked = Read-PolicyDword -Path (Join-Path $root 'URLBlocklist') -Name '1'
            # URLBlocklist is REG_SZ; compare the string rather than interpreting as DWORD.
            $rawBlock = if (Test-Path -LiteralPath (Join-Path $root 'URLBlocklist')) {
                (Get-ItemProperty -LiteralPath (Join-Path $root 'URLBlocklist') -Name '1' -ErrorAction SilentlyContinue).'1'
            } else { $null }
            $hasAllow = Test-Path -LiteralPath (Join-Path $root 'URLAllowlist')
            if ([bool]$manifest.expected.browserWhitelist) {
                if ($rawBlock -cne '*' -or -not $hasAllow) { $ok = $false }
            } else {
                if ($rawBlock -eq '*' -or $hasAllow) { $ok = $false }
            }
        }
        Add-ProbeResult 'BROWSER_REGISTRY' $(if ($ok) {'PASS'} else {'FAIL'}) 'Estado de políticas de Edge y Chrome.'
    } catch {
        Add-ProbeResult 'BROWSER_REGISTRY' 'FAIL' $_.Exception.Message
    }
}

$usbPath = 'Registry::HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}'
if ($manifest.expected.policyMode -ne 'Enforce') {
    Add-ProbeResult 'USB_REGISTRY' 'SKIP' 'Modo Auditoría; no se activa el bloqueo USB.'
} elseif ([bool]$manifest.expected.blockUsbStorage) {
    $r = Read-PolicyDword -Path $usbPath -Name 'Deny_Read'
    $w = Read-PolicyDword -Path $usbPath -Name 'Deny_Write'
    Add-ProbeResult 'USB_REGISTRY' $(if ($r.Exists -and $r.Value -eq 1 -and $w.Exists -and $w.Value -eq 1) {'PASS'} else {'FAIL'}) 'Deny_Read y Deny_Write comprobados en HKCU.'
} else {
    Add-ProbeResult 'USB_REGISTRY' 'SKIP' 'Sin bloqueo USB esperado; otras directivas del equipo pueden conservar restricciones ajenas a AulaGuard.'
}

# Optional physical removable-drive probe: read-only, no writes or formatting.
if ([bool]$manifest.expected.blockUsbStorage -and $manifest.expected.policyMode -eq 'Enforce' -and $UsbDrive) {
    if ($UsbDrive -notmatch '^[A-Z]:$') {
        Add-ProbeResult 'USB_PHYSICAL_READ' 'FAIL' 'Usa una letra en mayúsculas, por ejemplo E:.'
    } else {
        try {
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$UsbDrive'" -ErrorAction Stop
            if (-not $disk -or [int]$disk.DriveType -ne 2) {
                Add-ProbeResult 'USB_PHYSICAL_READ' 'SKIP' 'Windows no clasifica esta unidad como extraíble; comprueba manualmente.'
            } else {
                try {
                    Get-ChildItem -LiteralPath ($UsbDrive + '\') -ErrorAction Stop | Select-Object -First 1 | Out-Null
                    Add-ProbeResult 'USB_PHYSICAL_READ' 'FAIL' 'La cuenta de estudiante logró enumerar el almacenamiento extraíble.'
                } catch [System.UnauthorizedAccessException] {
                    Add-ProbeResult 'USB_PHYSICAL_READ' 'PASS' 'Acceso de lectura denegado a la unidad extraíble.'
                } catch {
                    Add-ProbeResult 'USB_PHYSICAL_READ' 'INCONCLUSIVE' "Fallo no atribuible con seguridad a la política: $($_.Exception.Message)"
                }
            }
        } catch {
            Add-ProbeResult 'USB_PHYSICAL_READ' 'INCONCLUSIVE' $_.Exception.Message
        }
    }
} else {
    Add-ProbeResult 'USB_PHYSICAL_READ' 'SKIP' 'Prueba opcional: indica -UsbDrive E: con una memoria de prueba.'
}

# AppLocker: test actual child-process execution in student context.
# A positive block is only claimed for Win32 error 1260 (blocked by group policy).
if ([bool]$manifest.expected.appControlEnabled -and $manifest.expected.appControlMode -eq 'Enabled') {
    if (-not $AllowedExecutable) { $AllowedExecutable = Join-Path $env:WINDIR 'System32\whoami.exe' }
    if (-not (Test-Path -LiteralPath $AllowedExecutable -PathType Leaf)) {
        Add-ProbeResult 'APPLOCKER_ALLOWED_PROCESS' 'SKIP' 'No se encontró el programa de control permitido.'
    } else {
        try {
            $run = Start-Process -FilePath $AllowedExecutable -NoNewWindow -Wait -PassThru -ErrorAction Stop
            Add-ProbeResult 'APPLOCKER_ALLOWED_PROCESS' $(if ($run.ExitCode -eq 0) {'PASS'} else {'FAIL'}) "Ejecutable permitido: código $($run.ExitCode)."
        } catch {
            Add-ProbeResult 'APPLOCKER_ALLOWED_PROCESS' 'FAIL' "No se pudo iniciar el ejecutable permitido: $($_.Exception.Message)"
        }
    }

    if (-not $DeniedFixturePath) {
        $DeniedFixturePath = Join-Path $env:ProgramData 'AulaGuardLab\AulaGuard-E2E-Benign.exe'
    }
    if (-not (Test-Path -LiteralPath $DeniedFixturePath -PathType Leaf)) {
        Add-ProbeResult 'APPLOCKER_DENIED_PROCESS' 'SKIP' 'No existe el programa inofensivo de prueba; no se afirmó un bloqueo.'
    } else {
        try {
            $run = Start-Process -FilePath $DeniedFixturePath -NoNewWindow -Wait -PassThru -ErrorAction Stop
            Add-ProbeResult 'APPLOCKER_DENIED_PROCESS' 'FAIL' 'El ejecutable que debía bloquearse se inició.'
        } catch [System.ComponentModel.Win32Exception] {
            if ($_.Exception.NativeErrorCode -eq 1260) {
                Add-ProbeResult 'APPLOCKER_DENIED_PROCESS' 'PASS' 'Windows rechazó el programa mediante directiva de grupo (1260).'
            } else {
                Add-ProbeResult 'APPLOCKER_DENIED_PROCESS' 'INCONCLUSIVE' "Error Win32 $($_.Exception.NativeErrorCode); revisa los eventos AppLocker."
            }
        } catch {
            Add-ProbeResult 'APPLOCKER_DENIED_PROCESS' 'INCONCLUSIVE' "Error de arranque: $($_.Exception.Message). Revisar eventos."
        }
    }
} else {
    Add-ProbeResult 'APPLOCKER_ALLOWED_PROCESS' 'SKIP' 'AppLocker no se encuentra configurado para bloqueo real.'
    Add-ProbeResult 'APPLOCKER_DENIED_PROCESS' 'SKIP' 'AppLocker no se encuentra configurado para bloqueo real.'
}

# These require genuine interaction; registry or ACL values alone do not prove UX behavior.
Add-ProbeResult 'WALLPAPER_CONTEXT_MENU' 'SKIP' 'Manual: intentar Establecer como fondo desde el menú contextual, sin cambiar la política.'
Add-ProbeResult 'DESKTOP_SHORTCUT_RENAME' 'SKIP' 'Manual: intentar renombrar un acceso directo de prueba del Escritorio público.'
Add-ProbeResult 'BROWSER_USER_NAVIGATION' 'SKIP' 'Manual: probar URL permitida y bloqueada en Edge/Chrome.'
Add-ProbeResult 'USB_WRITE_ATTEMPT' 'SKIP' 'Manual: probar escritura solo en memoria desechable de laboratorio.'
Add-ProbeResult 'RESTORE_AFTER_LOGON' 'SKIP' 'Manual: comprobar reversión y nuevo inicio de sesión.'

$all = @($results.ToArray())
$failed = @($all | Where-Object { $_.Status -eq 'FAIL' }).Count
$inconclusive = @($all | Where-Object { $_.Status -eq 'INCONCLUSIVE' }).Count
$skipped = @($all | Where-Object { $_.Status -eq 'SKIP' }).Count
$passed = @($all | Where-Object { $_.Status -eq 'PASS' }).Count
$report = [pscustomobject]@{
    schema = 'AulaGuard-StudentE2E/1'
    timestampUtc = [datetime]::UtcNow.ToString('o')
    computer = $env:COMPUTERNAME
    studentSid = $identity.User.Value
    manifestSHA256 = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash
    results = $all
    summary = [pscustomobject]@{
        passed = $passed
        failed = $failed
        skipped = $skipped
        inconclusive = $inconclusive
        automaticChecksPassed = ($failed -eq 0 -and $inconclusive -eq 0 -and $passed -gt 0)
        completeE2E = $false
        readyForProduction = $false
    }
}
if ([IO.Path]::GetExtension($ReportPath) -ine '.json') { throw 'El reporte debe guardarse como JSON.' }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8 -ErrorAction Stop
Write-Host "Reporte creado: $ReportPath"
Write-Host "PASS=$passed FAIL=$failed INCONCLUSIVE=$inconclusive SKIP=$skipped"
Write-Host 'Las pruebas manuales, el funcionamiento real de Windows y la restauración siguen pendientes.'
if ($failed -gt 0 -or $inconclusive -gt 0) { exit 1 }
if ($passed -eq 0) { exit 2 }
