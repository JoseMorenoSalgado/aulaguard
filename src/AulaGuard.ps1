# AulaGuard v0.2.0
# Advanced classroom endpoint administration for Windows 10/11 Pro.

$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    Import-Module (Join-Path $PSScriptRoot 'AulaGuard.Core.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'AulaGuard.Policy.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'AulaGuard.Diagnostics.psm1') -Force

    if (-not (Test-AulaGuardAdministrator)) {
        [System.Windows.Forms.MessageBox]::Show(
            'AulaGuard debe ejecutarse como administrador.',
            'AulaGuard','OK','Warning'
        ) | Out-Null
        exit 1
    }

    $root = Initialize-AulaGuardStorage
    $settings = Read-AulaGuardSettings -Root $root

    function New-AGButton {
        param([string]$Text,[int]$X,[int]$Y,[int]$W=130,[int]$H=34)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $Text
        $b.Location = New-Object System.Drawing.Point($X,$Y)
        $b.Size = New-Object System.Drawing.Size($W,$H)
        $b.FlatStyle = 'Flat'
        $b.Cursor = 'Hand'
        return $b
    }

    function New-AGLabel {
        param([string]$Text,[int]$X,[int]$Y,[int]$Size=9,[bool]$Bold=$false)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $Text
        $l.AutoSize = $true
        $l.Location = New-Object System.Drawing.Point($X,$Y)
        $fontName = if ($Bold) { 'Segoe UI Semibold' } else { 'Segoe UI' }
        $l.Font = New-Object System.Drawing.Font($fontName,$Size)
        return $l
    }

    function Add-ListItems {
        param($List,[object[]]$Items)
        $List.Items.Clear()
        foreach ($item in @($Items)) {
            if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
                [void]$List.Items.Add([string]$item)
            }
        }
    }

    function Get-ListItems {
        param($List)
        $out = @()
        foreach ($item in $List.Items) { $out += [string]$item }
        return $out
    }

    function Set-Status {
        param([string]$Text)
        $status.Text = $Text
    }

    function Get-UiSettings {
        $p = [pscustomobject]@{
            lockWallpaper = $chkLockWallpaper.Checked
            disablePersonalization = $chkPersonalization.Checked
            protectPublicDesktop = $chkProtectDesktop.Checked
            browserWhitelist = $chkBrowserWhitelist.Checked
            blockControlPanel = $chkControlPanel.Checked
            blockRegistryTools = $chkRegistry.Checked
            blockTaskManager = $chkTaskMgr.Checked
            blockCommandPrompt = $false
            blockPowerShell = $false
        }

        return [pscustomobject]@{
            version = '0.2.0'
            profileName = $txtProfileName.Text.Trim()
            policyMode = if ($radEnforce.Checked) { 'Enforce' } else { 'Audit' }
            wallpaper = $txtWallpaper.Text.Trim()
            allowedPrograms = @(Get-ListItems $lstPrograms)
            allowedWebsites = @(Get-ListItems $lstWebsites)
            protectedShortcuts = @(Get-ListItems $lstShortcuts)
            protections = $p
            auditEnabled = $true
            lastAppliedUtc = $settings.lastAppliedUtc
        }
    }

    function Save-FromUi {
        $script:settings = Get-UiSettings
        Backup-AulaGuardConfiguration -Root $root | Out-Null
        Save-AulaGuardSettings -Settings $script:settings -Root $root | Out-Null
        Write-AulaGuardAudit -Action 'CONFIG_SAVED' -Detail "Perfil=$($settings.profileName)" -Root $root
        Set-Status "Configuración guardada · $(Get-Date -Format 'HH:mm:ss')"
    }

    function Refresh-Dashboard {
        $info = Get-AulaGuardSystemInfo
        $users = @(Get-AulaGuardLocalUsers)
        $standard = @($users | Where-Object { -not $_.IsAdministrator })

        $lblPcValue.Text = $info.ComputerName
        $lblWindowsValue.Text = "$($info.Windows) · build $($info.Build)"
        $lblUsersValue.Text = "$($standard.Count) perfil(es) estándar detectado(s)"
        $lblModeValue.Text = if ($radEnforce.Checked) { 'Protección activa' } else { 'Auditoría / simulación' }

        $gridUsers.Rows.Clear()
        foreach ($u in $users) {
            [void]$gridUsers.Rows.Add(
                $u.User,
                $(if ($u.IsAdministrator) { 'Administrador' } else { 'Estudiante/estándar' }),
                $(if ($u.Loaded) { 'Sesión cargada' } else { 'Sin sesión' }),
                $u.SID
            )
        }

        $gridChecks.Rows.Clear()
        foreach ($c in Get-AulaGuardReadiness) {
            [void]$gridChecks.Rows.Add($(if ($c.Passed) {'OK'} else {'REVISAR'}),$c.Name,$c.Detail)
        }
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'AulaGuard 0.2'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1120,760)
    $form.MinimumSize = New-Object System.Drawing.Size(1000,680)
    $form.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $form.BackColor = [System.Drawing.Color]::FromArgb(244,247,251)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 82
    $header.BackColor = [System.Drawing.Color]::FromArgb(15,76,129)
    $form.Controls.Add($header)

    $brand = New-AGLabel 'AulaGuard' 24 12 22 $true
    $brand.ForeColor = [System.Drawing.Color]::White
    $header.Controls.Add($brand)

    $tagline = New-AGLabel 'Control y protección profesional para aulas Windows' 27 48 9 $false
    $tagline.ForeColor = [System.Drawing.Color]::FromArgb(215,232,247)
    $header.Controls.Add($tagline)

    $badge = New-AGLabel 'v0.2.0' 1018 24 9 $true
    $badge.ForeColor = [System.Drawing.Color]::White
    $badge.Anchor = 'Top,Right'
    $header.Controls.Add($badge)

    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = 'Bottom'
    $footer.Height = 56
    $footer.BackColor = [System.Drawing.Color]::White
    $form.Controls.Add($footer)

    $status = New-AGLabel 'Listo' 18 20 9 $false
    $status.ForeColor = [System.Drawing.Color]::FromArgb(71,85,105)
    $footer.Controls.Add($status)

    $btnSave = New-AGButton 'Guardar' 835 11 115 34
    $btnSave.Anchor = 'Top,Right'
    $footer.Controls.Add($btnSave)

    $btnApply = New-AGButton 'Aplicar políticas' 958 11 135 34
    $btnApply.Anchor = 'Top,Right'
    $btnApply.BackColor = [System.Drawing.Color]::FromArgb(22,163,74)
    $btnApply.ForeColor = [System.Drawing.Color]::White
    $footer.Controls.Add($btnApply)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    $tabs.Padding = New-Object System.Drawing.Point(14,7)
    $form.Controls.Add($tabs)
    $tabs.BringToFront()

    $tabDashboard = New-Object System.Windows.Forms.TabPage
    $tabDashboard.Text = 'Resumen'
    $tabDashboard.BackColor = [System.Drawing.Color]::White
    $tabs.TabPages.Add($tabDashboard)

    $tabDashboard.Controls.Add((New-AGLabel 'Estado del equipo' 22 18 13 $true))
    $tabDashboard.Controls.Add((New-AGLabel 'Equipo:' 22 58 9 $true))
    $lblPcValue = New-AGLabel '-' 120 58 9 $false
    $tabDashboard.Controls.Add($lblPcValue)

    $tabDashboard.Controls.Add((New-AGLabel 'Windows:' 22 86 9 $true))
    $lblWindowsValue = New-AGLabel '-' 120 86 9 $false
    $tabDashboard.Controls.Add($lblWindowsValue)

    $tabDashboard.Controls.Add((New-AGLabel 'Usuarios:' 22 114 9 $true))
    $lblUsersValue = New-AGLabel '-' 120 114 9 $false
    $tabDashboard.Controls.Add($lblUsersValue)

    $tabDashboard.Controls.Add((New-AGLabel 'Modo:' 22 142 9 $true))
    $lblModeValue = New-AGLabel '-' 120 142 9 $false
    $tabDashboard.Controls.Add($lblModeValue)

    $gridUsers = New-Object System.Windows.Forms.DataGridView
    $gridUsers.Location = New-Object System.Drawing.Point(22,190)
    $gridUsers.Size = New-Object System.Drawing.Size(1035,190)
    $gridUsers.Anchor = 'Top,Left,Right'
    $gridUsers.ReadOnly = $true
    $gridUsers.AllowUserToAddRows = $false
    $gridUsers.RowHeadersVisible = $false
    $gridUsers.AutoSizeColumnsMode = 'Fill'
    [void]$gridUsers.Columns.Add('User','Usuario')
    [void]$gridUsers.Columns.Add('Role','Tipo')
    [void]$gridUsers.Columns.Add('State','Estado')
    [void]$gridUsers.Columns.Add('SID','SID')
    $tabDashboard.Controls.Add($gridUsers)

    $tabDashboard.Controls.Add((New-AGLabel 'Diagnóstico' 22 402 12 $true))
    $gridChecks = New-Object System.Windows.Forms.DataGridView
    $gridChecks.Location = New-Object System.Drawing.Point(22,435)
    $gridChecks.Size = New-Object System.Drawing.Size(1035,145)
    $gridChecks.Anchor = 'Top,Left,Right,Bottom'
    $gridChecks.ReadOnly = $true
    $gridChecks.AllowUserToAddRows = $false
    $gridChecks.RowHeadersVisible = $false
    $gridChecks.AutoSizeColumnsMode = 'Fill'
    [void]$gridChecks.Columns.Add('State','Estado')
    [void]$gridChecks.Columns.Add('Check','Comprobación')
    [void]$gridChecks.Columns.Add('Detail','Detalle')
    $tabDashboard.Controls.Add($gridChecks)

    $tabPolicies = New-Object System.Windows.Forms.TabPage
    $tabPolicies.Text = 'Protecciones'
    $tabPolicies.BackColor = [System.Drawing.Color]::White
    $tabs.TabPages.Add($tabPolicies)

    $tabPolicies.Controls.Add((New-AGLabel 'Perfil y modo de trabajo' 22 18 13 $true))
    $tabPolicies.Controls.Add((New-AGLabel 'Nombre del perfil' 22 60 9 $true))
    $txtProfileName = New-Object System.Windows.Forms.TextBox
    $txtProfileName.Location = New-Object System.Drawing.Point(160,56)
    $txtProfileName.Size = New-Object System.Drawing.Size(330,28)
    $txtProfileName.Text = [string]$settings.profileName
    $tabPolicies.Controls.Add($txtProfileName)

    $radAudit = New-Object System.Windows.Forms.RadioButton
    $radAudit.Text = 'Auditoría / simulación'
    $radAudit.Location = New-Object System.Drawing.Point(22,105)
    $radAudit.AutoSize = $true
    $tabPolicies.Controls.Add($radAudit)

    $radEnforce = New-Object System.Windows.Forms.RadioButton
    $radEnforce.Text = 'Aplicar protección'
    $radEnforce.Location = New-Object System.Drawing.Point(210,105)
    $radEnforce.AutoSize = $true
    $tabPolicies.Controls.Add($radEnforce)

    if ($settings.policyMode -eq 'Enforce') { $radEnforce.Checked = $true } else { $radAudit.Checked = $true }

    $tabPolicies.Controls.Add((New-AGLabel 'Protecciones del usuario estándar' 22 154 12 $true))

    $chkLockWallpaper = New-Object System.Windows.Forms.CheckBox
    $chkLockWallpaper.Text = 'Bloquear cambio de fondo de escritorio'
    $chkLockWallpaper.Location = New-Object System.Drawing.Point(22,195)
    $chkLockWallpaper.AutoSize = $true
    $chkLockWallpaper.Checked = [bool]$settings.protections.lockWallpaper
    $tabPolicies.Controls.Add($chkLockWallpaper)

    $chkPersonalization = New-Object System.Windows.Forms.CheckBox
    $chkPersonalization.Text = 'Deshabilitar opciones de personalización'
    $chkPersonalization.Location = New-Object System.Drawing.Point(22,228)
    $chkPersonalization.AutoSize = $true
    $chkPersonalization.Checked = [bool]$settings.protections.disablePersonalization
    $tabPolicies.Controls.Add($chkPersonalization)

    $chkProtectDesktop = New-Object System.Windows.Forms.CheckBox
    $chkProtectDesktop.Text = 'Proteger accesos del escritorio público'
    $chkProtectDesktop.Location = New-Object System.Drawing.Point(22,261)
    $chkProtectDesktop.AutoSize = $true
    $chkProtectDesktop.Checked = [bool]$settings.protections.protectPublicDesktop
    $tabPolicies.Controls.Add($chkProtectDesktop)

    $chkBrowserWhitelist = New-Object System.Windows.Forms.CheckBox
    $chkBrowserWhitelist.Text = 'Permitir únicamente los sitios definidos en AulaGuard (Edge/Chrome)'
    $chkBrowserWhitelist.Location = New-Object System.Drawing.Point(22,294)
    $chkBrowserWhitelist.AutoSize = $true
    $chkBrowserWhitelist.Checked = [bool]$settings.protections.browserWhitelist
    $tabPolicies.Controls.Add($chkBrowserWhitelist)

    $chkControlPanel = New-Object System.Windows.Forms.CheckBox
    $chkControlPanel.Text = 'Bloquear Panel de control y Configuración'
    $chkControlPanel.Location = New-Object System.Drawing.Point(560,195)
    $chkControlPanel.AutoSize = $true
    $chkControlPanel.Checked = [bool]$settings.protections.blockControlPanel
    $tabPolicies.Controls.Add($chkControlPanel)

    $chkRegistry = New-Object System.Windows.Forms.CheckBox
    $chkRegistry.Text = 'Bloquear Editor del Registro'
    $chkRegistry.Location = New-Object System.Drawing.Point(560,228)
    $chkRegistry.AutoSize = $true
    $chkRegistry.Checked = [bool]$settings.protections.blockRegistryTools
    $tabPolicies.Controls.Add($chkRegistry)

    $chkTaskMgr = New-Object System.Windows.Forms.CheckBox
    $chkTaskMgr.Text = 'Bloquear Administrador de tareas'
    $chkTaskMgr.Location = New-Object System.Drawing.Point(560,261)
    $chkTaskMgr.AutoSize = $true
    $chkTaskMgr.Checked = [bool]$settings.protections.blockTaskManager
    $tabPolicies.Controls.Add($chkTaskMgr)

    $tabPolicies.Controls.Add((New-AGLabel 'Fondo institucional' 22 350 11 $true))
    $txtWallpaper = New-Object System.Windows.Forms.TextBox
    $txtWallpaper.Location = New-Object System.Drawing.Point(22,384)
    $txtWallpaper.Size = New-Object System.Drawing.Size(790,28)
    $txtWallpaper.ReadOnly = $true
    $txtWallpaper.Text = [string]$settings.wallpaper
    $tabPolicies.Controls.Add($txtWallpaper)

    $btnWallpaper = New-AGButton 'Seleccionar imagen' 825 381 150 32
    $tabPolicies.Controls.Add($btnWallpaper)

    $tabPolicies.Controls.Add((New-AGLabel 'Importar / exportar perfiles de aula' 22 455 11 $true))
    $btnExport = New-AGButton 'Exportar perfil' 22 490 140 34
    $tabPolicies.Controls.Add($btnExport)
    $btnImport = New-AGButton 'Importar perfil' 172 490 140 34
    $tabPolicies.Controls.Add($btnImport)
    $btnReset = New-AGButton 'Retirar políticas' 822 490 160 34
    $btnReset.ForeColor = [System.Drawing.Color]::DarkRed
    $tabPolicies.Controls.Add($btnReset)

    $tabApps = New-Object System.Windows.Forms.TabPage
    $tabApps.Text = 'Programas'
    $tabApps.BackColor = [System.Drawing.Color]::White
    $tabs.TabPages.Add($tabApps)

    $tabApps.Controls.Add((New-AGLabel 'Programas autorizados' 22 18 13 $true))
    $tabApps.Controls.Add((New-AGLabel 'Lista preparada para el motor de control de aplicaciones.' 22 48 9 $false))

    $lstPrograms = New-Object System.Windows.Forms.ListBox
    $lstPrograms.Location = New-Object System.Drawing.Point(22,85)
    $lstPrograms.Size = New-Object System.Drawing.Size(850,450)
    $lstPrograms.Anchor = 'Top,Left,Right,Bottom'
    $tabApps.Controls.Add($lstPrograms)
    Add-ListItems $lstPrograms @($settings.allowedPrograms)

    $btnAddProgram = New-AGButton 'Agregar .EXE' 890 85 145 34
    $btnAddProgram.Anchor = 'Top,Right'
    $tabApps.Controls.Add($btnAddProgram)
    $btnRemoveProgram = New-AGButton 'Quitar' 890 129 145 34
    $btnRemoveProgram.Anchor = 'Top,Right'
    $tabApps.Controls.Add($btnRemoveProgram)

    $tabWeb = New-Object System.Windows.Forms.TabPage
    $tabWeb.Text = 'Internet'
    $tabWeb.BackColor = [System.Drawing.Color]::White
    $tabs.TabPages.Add($tabWeb)

    $tabWeb.Controls.Add((New-AGLabel 'Lista blanca de sitios web' 22 18 13 $true))
    $tabWeb.Controls.Add((New-AGLabel 'Compatible con políticas de Edge y Chrome por usuario.' 22 48 9 $false))

    $txtWebsite = New-Object System.Windows.Forms.TextBox
    $txtWebsite.Location = New-Object System.Drawing.Point(22,82)
    $txtWebsite.Size = New-Object System.Drawing.Size(720,28)
    $tabWeb.Controls.Add($txtWebsite)
    $btnAddWebsite = New-AGButton 'Agregar sitio' 758 78 135 34
    $tabWeb.Controls.Add($btnAddWebsite)

    $lstWebsites = New-Object System.Windows.Forms.ListBox
    $lstWebsites.Location = New-Object System.Drawing.Point(22,125)
    $lstWebsites.Size = New-Object System.Drawing.Size(870,410)
    $lstWebsites.Anchor = 'Top,Left,Right,Bottom'
    $tabWeb.Controls.Add($lstWebsites)
    Add-ListItems $lstWebsites @($settings.allowedWebsites)

    $btnRemoveWebsite = New-AGButton 'Quitar' 910 125 125 34
    $btnRemoveWebsite.Anchor = 'Top,Right'
    $tabWeb.Controls.Add($btnRemoveWebsite)

    $tabDesktop = New-Object System.Windows.Forms.TabPage
    $tabDesktop.Text = 'Escritorio'
    $tabDesktop.BackColor = [System.Drawing.Color]::White
    $tabs.TabPages.Add($tabDesktop)

    $tabDesktop.Controls.Add((New-AGLabel 'Accesos directos protegidos' 22 18 13 $true))
    $tabDesktop.Controls.Add((New-AGLabel 'Registra los accesos que deben conservarse en el escritorio de los estudiantes.' 22 48 9 $false))

    $lstShortcuts = New-Object System.Windows.Forms.ListBox
    $lstShortcuts.Location = New-Object System.Drawing.Point(22,85)
    $lstShortcuts.Size = New-Object System.Drawing.Size(850,450)
    $lstShortcuts.Anchor = 'Top,Left,Right,Bottom'
    $tabDesktop.Controls.Add($lstShortcuts)
    Add-ListItems $lstShortcuts @($settings.protectedShortcuts)

    $btnAddShortcut = New-AGButton 'Agregar acceso' 890 85 145 34
    $btnAddShortcut.Anchor = 'Top,Right'
    $tabDesktop.Controls.Add($btnAddShortcut)
    $btnRemoveShortcut = New-AGButton 'Quitar' 890 129 145 34
    $btnRemoveShortcut.Anchor = 'Top,Right'
    $tabDesktop.Controls.Add($btnRemoveShortcut)

    $tabAudit = New-Object System.Windows.Forms.TabPage
    $tabAudit.Text = 'Bitácora'
    $tabAudit.BackColor = [System.Drawing.Color]::White
    $tabs.TabPages.Add($tabAudit)

    $tabAudit.Controls.Add((New-AGLabel 'Registro de actividad de AulaGuard' 22 18 13 $true))
    $txtAudit = New-Object System.Windows.Forms.TextBox
    $txtAudit.Location = New-Object System.Drawing.Point(22,58)
    $txtAudit.Size = New-Object System.Drawing.Size(1010,470)
    $txtAudit.Anchor = 'Top,Left,Right,Bottom'
    $txtAudit.Multiline = $true
    $txtAudit.ReadOnly = $true
    $txtAudit.ScrollBars = 'Both'
    $txtAudit.Font = New-Object System.Drawing.Font('Consolas',9)
    $tabAudit.Controls.Add($txtAudit)
    $btnRefreshAudit = New-AGButton 'Actualizar' 22 544 120 34
    $btnRefreshAudit.Anchor = 'Left,Bottom'
    $tabAudit.Controls.Add($btnRefreshAudit)

    $loadAudit = {
        $lines = @()
        $auditFiles = Get-ChildItem (Join-Path $root 'logs') -Filter 'audit-*.jsonl' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 5
        foreach ($file in ($auditFiles | Sort-Object Name)) {
            foreach ($line in Get-Content $file.FullName -ErrorAction SilentlyContinue) {
                try {
                    $e = $line | ConvertFrom-Json
                    $lines += ('{0}  [{1}]  {2}  {3}' -f $e.timestamp,$e.level,$e.action,$e.detail)
                } catch {
                    $lines += $line
                }
            }
        }
        $txtAudit.Text = ($lines -join [Environment]::NewLine)
        $txtAudit.SelectionStart = $txtAudit.TextLength
        $txtAudit.ScrollToCaret()
    }

    $btnWallpaper.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Imágenes|*.jpg;*.jpeg;*.png;*.bmp'
        if ($dlg.ShowDialog() -eq 'OK') {
            $txtWallpaper.Text = $dlg.FileName
            Write-AulaGuardAudit -Action 'WALLPAPER_SELECTED' -Detail $dlg.FileName -Root $root
        }
    })

    $btnAddProgram.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Aplicaciones (*.exe)|*.exe'
        $dlg.Multiselect = $true
        if ($dlg.ShowDialog() -eq 'OK') {
            foreach ($f in $dlg.FileNames) {
                if ($lstPrograms.Items -notcontains $f) { [void]$lstPrograms.Items.Add($f) }
            }
        }
    })
    $btnRemoveProgram.Add_Click({ while ($lstPrograms.SelectedIndices.Count -gt 0) { $lstPrograms.Items.RemoveAt($lstPrograms.SelectedIndices[0]) } })

    $btnAddWebsite.Add_Click({
        $v = $txtWebsite.Text.Trim()
        if ($v -and $lstWebsites.Items -notcontains $v) {
            [void]$lstWebsites.Items.Add($v)
            $txtWebsite.Clear()
        }
    })
    $btnRemoveWebsite.Add_Click({ while ($lstWebsites.SelectedIndices.Count -gt 0) { $lstWebsites.Items.RemoveAt($lstWebsites.SelectedIndices[0]) } })

    $btnAddShortcut.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Accesos directos (*.lnk)|*.lnk'
        $dlg.Multiselect = $true
        if ($dlg.ShowDialog() -eq 'OK') {
            foreach ($f in $dlg.FileNames) {
                if ($lstShortcuts.Items -notcontains $f) { [void]$lstShortcuts.Items.Add($f) }
            }
        }
    })
    $btnRemoveShortcut.Add_Click({ while ($lstShortcuts.SelectedIndices.Count -gt 0) { $lstShortcuts.Items.RemoveAt($lstShortcuts.SelectedIndices[0]) } })

    $btnSave.Add_Click({
        Save-FromUi
        Refresh-Dashboard
    })

    $btnApply.Add_Click({
        Save-FromUi
        $simulation = -not $radEnforce.Checked
        $answer = if ($simulation) {
            'AulaGuard ejecutará una simulación y no modificará Windows. ¿Continuar?'
        } else {
            'Se aplicarán las protecciones a los perfiles de usuario estándar detectados. Las cuentas administradoras se excluyen. ¿Continuar?'
        }

        if ([System.Windows.Forms.MessageBox]::Show($answer,'AulaGuard','YesNo','Question') -ne 'Yes') { return }

        try {
            Set-Status 'Procesando políticas...'
            $result = @(Apply-AulaGuardPolicies -Settings $settings -WhatIfMode:$simulation)

            if (-not $simulation -and $settings.protections.protectPublicDesktop) {
                Protect-AulaGuardPublicDesktop
            }

            $ok = @($result | Where-Object {$_.Status -in @('OK','SIMULADO')}).Count
            $errors = @($result | Where-Object {$_.Status -eq 'ERROR'}).Count
            $settings.lastAppliedUtc = (Get-Date).ToUniversalTime().ToString('o')
            Save-AulaGuardSettings -Settings $settings -Root $root | Out-Null
            Write-AulaGuardAudit -Action 'POLICIES_APPLIED' -Level 'SECURITY' -Detail "Simulacion=$simulation; OK=$ok; Error=$errors" -Root $root

            $nl = [Environment]::NewLine
            $summary = "Proceso finalizado.$nl$nlPerfiles procesados: $($result.Count)$nlCorrectos: $ok$nlErrores: $errors"
            [System.Windows.Forms.MessageBox]::Show(
                $summary,'AulaGuard','OK',$(if ($errors -gt 0) {'Warning'} else {'Information'})
            ) | Out-Null
            Set-Status 'Políticas procesadas'
            Refresh-Dashboard
            & $loadAudit
        } catch {
            Write-AulaGuardAudit -Action 'POLICY_ERROR' -Level 'ERROR' -Detail $_.Exception.Message -Root $root
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard','OK','Error') | Out-Null
            Set-Status 'Error al aplicar políticas'
        }
    })

    $btnReset.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show(
            'Esto retirará las políticas que AulaGuard administra de los usuarios estándar. ¿Continuar?',
            'AulaGuard','YesNo','Warning'
        ) -ne 'Yes') { return }

        try {
            $r = @(Reset-AulaGuardPolicies)
            Protect-AulaGuardPublicDesktop -Restore
            Write-AulaGuardAudit -Action 'POLICIES_RESET' -Level 'SECURITY' -Detail "Perfiles=$($r.Count)" -Root $root
            [System.Windows.Forms.MessageBox]::Show('Las políticas administradas por AulaGuard fueron retiradas.','AulaGuard','OK','Information') | Out-Null
            & $loadAudit
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard','OK','Error') | Out-Null
        }
    })

    $btnExport.Add_Click({
        Save-FromUi
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = 'Perfil AulaGuard (*.json)|*.json'
        $dlg.FileName = 'AulaGuard-profile.json'
        if ($dlg.ShowDialog() -eq 'OK') {
            Export-AulaGuardProfile -Path $dlg.FileName -Root $root
            Set-Status 'Perfil exportado'
        }
    })

    $btnImport.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Perfil AulaGuard (*.json)|*.json'
        if ($dlg.ShowDialog() -eq 'OK') {
            Import-AulaGuardProfile -Path $dlg.FileName -Root $root | Out-Null
            [System.Windows.Forms.MessageBox]::Show(
                'Perfil importado. Reinicie AulaGuard para cargar todos sus valores en la interfaz.',
                'AulaGuard','OK','Information'
            ) | Out-Null
        }
    })

    $btnRefreshAudit.Add_Click($loadAudit)
    $radAudit.Add_CheckedChanged({ Refresh-Dashboard })
    $radEnforce.Add_CheckedChanged({ Refresh-Dashboard })

    Write-AulaGuardAudit -Action 'APP_STARTED' -Detail 'v0.2.0' -Root $root
    Refresh-Dashboard
    & $loadAudit

    $form.Add_FormClosed({
        try { Write-AulaGuardAudit -Action 'APP_CLOSED' -Root $root } catch {}
    })

    [void]$form.ShowDialog()
}
catch {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $msg = $_.Exception.ToString()
        $fallback = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { $env:TEMP }
        Set-Content -Path (Join-Path $fallback 'startup-error.txt') -Value $msg -Encoding UTF8
        $nl = [Environment]::NewLine
        [System.Windows.Forms.MessageBox]::Show(
            "AulaGuard no pudo iniciar.$nl$nl$($_.Exception.Message)$nl$nlRevise startup-error.txt.",
            'AulaGuard - Error','OK','Error'
        ) | Out-Null
    } catch {}
    exit 1
}
