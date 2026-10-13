# AulaGuard - preflight for a dedicated Windows classroom LAB only.
# Never applies policies, creates accounts, disables Defender, or invokes student programs.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$StudentAccount,
    [string]$DataRoot = (Join-Path $env:ProgramData 'AulaGuard'),
    [switch]$RequireEnforcement,
    [switch]$CreateBenignFixture
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') { throw 'Este comprobador solo funciona en Windows.' }
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Abre PowerShell como administrador para realizar la prevalidación.'
}

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
if ($os.Caption -notmatch 'Windows 10|Windows 11' -or $os.Caption -notmatch '\bPro\b') {
    throw "Laboratorio no aprobado: se requiere Windows 10/11 Pro; detectado $($os.Caption)."
}
$student = Get-LocalUser -Name $StudentAccount -ErrorAction Stop
if (-not $student.Enabled) { throw 'La cuenta de pruebas debe estar habilitada.' }

$sid = [string]$student.SID.Value
$admins = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
$adminSids = @(Get-LocalGroupMember -Group $admins.Name -ErrorAction Stop |
    Where-Object { $null -ne $_.SID } | ForEach-Object { $_.SID.Value })
if ($sid -in $adminSids) { throw 'La cuenta de laboratorio no puede ser administradora.' }
$profiles = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { $_.SID -eq $sid })
if ($profiles.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$profiles[0].LocalPath)) {
    throw 'Inicia sesión al menos una vez en la cuenta estándar para crear su perfil antes de ejecutar la prueba.'
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach ($name in @('AulaGuard.Security.psm1','AulaGuard.Core.psm1','AulaGuard.Diagnostics.psm1','AulaGuard.Wallpaper.psm1')) {
    Import-Module (Join-Path $repo "src\$name") -Force -ErrorAction Stop
}
$settings = Read-AulaGuardSettings -Root $DataRoot
if ($settings.maintenance.enabled) { throw 'Finaliza el modo mantenimiento antes de iniciar la verificación E2E.' }
if ($RequireEnforcement -and $settings.policyMode -ne 'Enforce') {
    throw 'La protección general debe estar en Enforce para probar bloqueos reales.'
}

$checks = @(Test-AulaGuardReadiness -Root $DataRoot -Settings $settings)
$blocking = @($checks | Where-Object { -not $_.Passed -and ($_.BlocksPolicies -or $_.BlocksAppControl) })
if ($blocking.Count -gt 0) {
    $reason = ($blocking | Select-Object -First 5 | ForEach-Object { "$($_.Code): $($_.Detail)" }) -join ' | '
    throw "Prevalidación fallida: $reason"
}

$group = Get-LocalGroup -Name 'AulaGuardStudents' -ErrorAction SilentlyContinue
$isMember = $false
if ($group) {
    $members = @(Get-LocalGroupMember -Group $group.Name -ErrorAction Stop |
        Where-Object { $null -ne $_.SID } | ForEach-Object { $_.SID.Value })
    $isMember = ($sid -in $members)
}
if ($settings.appControl.enabled -and -not $isMember) {
    throw 'AppLocker está configurado, pero el estudiante de laboratorio no pertenece a AulaGuardStudents.'
}
if ($settings.appControl.enabled) {
    $appsvc = Get-Service -Name AppIDSvc -ErrorAction Stop
    if ($appsvc.Status -ne 'Running') { throw 'Application Identity no está iniciado; no se puede validar AppLocker.' }
}

# Publish a read-only manifest for the standard user, outside AulaGuard's private data root.
# The path is fixed, requires trusted ownership, and rejects junctions/reparse points.
$labRoot = Join-Path $env:ProgramData 'AulaGuardLab'
$labParent = Get-Item -LiteralPath $env:ProgramData -Force -ErrorAction Stop
if (($labParent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'La ruta ProgramData no debe ser un punto de redirección.'
}
if (Test-Path -LiteralPath $labRoot) {
    $item = Get-Item -LiteralPath $labRoot -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Se rechaza AulaGuardLab porque es un punto de redirección.'
    }
    $owner = (Get-Acl -LiteralPath $labRoot).GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -notin @('S-1-5-32-544','S-1-5-18', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
        throw 'La carpeta AulaGuardLab no pertenece a un administrador confiable.'
    }
} else {
    New-Item -Path $labRoot -ItemType Directory -ErrorAction Stop | Out-Null
}

$administrators = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
$system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
$users = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
$acl.SetOwner($administrators)
foreach ($id in @($administrators,$system,$users)) {
    $rights = if ($id.Value -eq $users.Value) {
        [Security.AccessControl.FileSystemRights]::ReadAndExecute
    } else {
        [Security.AccessControl.FileSystemRights]::FullControl
    }
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
        $id,$rights,
        [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow
    )
    [void]$acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $labRoot -AclObject $acl -ErrorAction Stop

$manifestPath = Join-Path $labRoot 'manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    $old = Get-Item -LiteralPath $manifestPath -Force -ErrorAction Stop
    if (($old.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'El manifiesto existente no puede ser un enlace o punto de redirección.'
    }
    $oldOwner = (Get-Acl -LiteralPath $manifestPath).GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($oldOwner -notin @('S-1-5-32-544','S-1-5-18',[Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
        throw 'El manifiesto existente tiene un propietario no confiable.'
    }
}
$manifest = [pscustomobject]@{
    schema = 'AulaGuard-LabManifest/1'
    generatedUtc = [datetime]::UtcNow.ToString('o')
    computer = $env:COMPUTERNAME
    studentSid = $sid
    expected = [pscustomobject]@{
        policyMode = [string]$settings.policyMode
        appControlEnabled = [bool]$settings.appControl.enabled
        appControlMode = [string]$settings.appControl.mode
        lockWallpaper = [bool]$settings.protections.lockWallpaper
        disablePersonalization = [bool]$settings.protections.disablePersonalization
        blockControlPanel = [bool]$settings.protections.blockControlPanel
        blockRegistryTools = [bool]$settings.protections.blockRegistryTools
        blockTaskManager = [bool]$settings.protections.blockTaskManager
        browserWhitelist = [bool]$settings.protections.browserWhitelist
        blockUsbStorage = [bool]$settings.usb.blockStorage
        protectPublicDesktop = [bool]$settings.protections.protectPublicDesktop
    }
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction Stop
# A pre-existing file could have an unsafe DACL; explicitly replace it.
$fileAcl = New-Object System.Security.AccessControl.FileSecurity
$fileAcl.SetAccessRuleProtection($true,$false)
$fileAcl.SetOwner($administrators)
foreach ($id in @($administrators,$system,$users)) {
    $rights = if ($id.Value -eq $users.Value) {
        [Security.AccessControl.FileSystemRights]::ReadAndExecute
    } else {
        [Security.AccessControl.FileSystemRights]::FullControl
    }
    [void]$fileAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($id,$rights,[Security.AccessControl.AccessControlType]::Allow)))
}
Set-Acl -LiteralPath $manifestPath -AclObject $fileAcl -ErrorAction Stop

# Optional harmless console fixture. Built, but NEVER executed, by the administrator.
# A student's attempt to launch it outside Windows/Program Files tests AppLocker enforcement.
$fixturePath = Join-Path $labRoot 'AulaGuard-E2E-Benign.exe'
if ($CreateBenignFixture) {
    if (Test-Path -LiteralPath $fixturePath) {
        $existingFixture = Get-Item -LiteralPath $fixturePath -Force -ErrorAction Stop
        if (($existingFixture.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'El ejecutable de pruebas no puede ser un enlace.'
        }
        throw 'El ejecutable de pruebas ya existe: no se sobrescribirá sin revisión del administrador.'
    }
    $fixtureSource = @'
using System;
public static class AulaGuardE2EBenign {
    public static int Main(string[] args) { return 0; }
}
'@
    Add-Type -TypeDefinition $fixtureSource -OutputAssembly $fixturePath -OutputType ConsoleApplication -ErrorAction Stop
    Set-Acl -LiteralPath $fixturePath -AclObject $fileAcl -ErrorAction Stop
}

if (Test-Path -LiteralPath $fixturePath -PathType Leaf) {
    $existingFixture = Get-Item -LiteralPath $fixturePath -Force -ErrorAction Stop
    if (($existingFixture.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'El ejecutable de prueba existente es un enlace inseguro.'
    }
    $fixtureOwner = (Get-Acl -LiteralPath $fixturePath).GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($fixtureOwner -notin @('S-1-5-32-544','S-1-5-18',[Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
        throw 'El ejecutable de prueba existente tiene un propietario no confiable.'
    }
    Set-Acl -LiteralPath $fixturePath -AclObject $fileAcl -ErrorAction Stop
    $manifest | Add-Member NoteProperty benignFixtureSha256 (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash -Force
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction Stop
    Set-Acl -LiteralPath $manifestPath -AclObject $fileAcl -ErrorAction Stop
}
$hash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
[pscustomobject]@{
    Ready = $true
    Windows = $os.Caption
    Build = $os.BuildNumber
    Student = $student.Name
    Manifest = $manifestPath
    ManifestSHA256 = $hash
    BenignFixture = if (Test-Path -LiteralPath $fixturePath -PathType Leaf) { $fixturePath } else { 'No creado' }
    AppLockerMembershipVerified = $isMember
    Notes = 'Sin cambios en las políticas. Inicia sesión como estudiante y ejecuta Student-Probe.ps1.'
} | Format-List
