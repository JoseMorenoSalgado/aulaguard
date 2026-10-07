# AulaGuard v0.1.1
# Administrative configuration console for Windows 10/11 Pro.

$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function Test-AulaGuardAdministrator {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Get-AulaGuardRoot {
        $installedRoot = Join-Path $env:ProgramData 'AulaGuard'
        if (Test-Path (Join-Path $installedRoot 'config')) {
            return $installedRoot
        }
        $scriptFolder = Split-Path -Parent $PSCommandPath
        return Split-Path -Parent $scriptFolder
    }

    $appRoot = Get-AulaGuardRoot
    $configDir = Join-Path $appRoot 'config'
    $logsDir = Join-Path $appRoot 'logs'
    $settingsPath = Join-Path $configDir 'settings.json'
    $defaultPath = Join-Path $configDir 'default.json'

    foreach ($folder in @($configDir, $logsDir)) {
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
    }

    if (-not (Test-AulaGuardAdministrator)) {
        [System.Windows.Forms.MessageBox]::Show(
            'AulaGuard debe ejecutarse con una cuenta de administrador.',
            'AulaGuard',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        exit 1
    }

    function Write-AulaGuardAudit {
        param(
            [Parameter(Mandatory = $true)][string]$Action,
            [string]$Detail = ''
        )
        $day = Get-Date -Format 'yyyy-MM-dd'
        $logPath = Join-Path $logsDir "audit-$day.log"
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $tab = [char]9
        $line = "$timestamp$tab$userName$tab$Action$tab$Detail"
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    }

    function New-DefaultSettings {
        [pscustomobject]@{
            version = '0.1.1'
            wallpaper = ''
            allowedPrograms = @()
            allowedWebsites = @()
            protectedShortcuts = @()
            auditEnabled = $true
        }
    }

    function Load-AulaGuardSettings {
        if (Test-Path $settingsPath) {
            try {
                return (Get-Content -Raw -Path $settingsPath -Encoding UTF8 | ConvertFrom-Json)
            } catch {
                Write-AulaGuardAudit -Action 'CONFIG_LOAD_ERROR' -Detail $_.Exception.Message
            }
        }
        if (Test-Path $defaultPath) {
            try {
                return (Get-Content -Raw -Path $defaultPath -Encoding UTF8 | ConvertFrom-Json)
            } catch {}
        }
        return New-DefaultSettings
    }

    function Save-AulaGuardSettings {
        param([Parameter(Mandatory = $true)]$Settings)
        $Settings | ConvertTo-Json -Depth 5 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-AulaGuardAudit -Action 'CONFIG_SAVED' -Detail $settingsPath
    }

    function Add-UniqueListItem {
        param(
            [System.Windows.Forms.ListBox]$ListBox,
            [string]$Value
        )
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        $trimmed = $Value.Trim()
        foreach ($item in $ListBox.Items) {
            if ($item.ToString().Equals($trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
                return
            }
        }
        [void]$ListBox.Items.Add($trimmed)
    }

    function Get-ListItems {
        param([System.Windows.Forms.ListBox]$ListBox)
        $result = @()
        foreach ($item in $ListBox.Items) {
            $result += $item.ToString()
        }
        return $result
    }

    $settings = Load-AulaGuardSettings

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'AulaGuard'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(930, 650)
    $form.MinimumSize = New-Object System.Drawing.Size(850, 580)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 72
    $header.BackColor = [System.Drawing.Color]::FromArgb(29, 78, 216)
    $form.Controls.Add($header)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'AulaGuard'
    $title.ForeColor = [System.Drawing.Color]::White
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 20)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(22, 10)
    $header.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Administración y protección de equipos del aula · v0.1.1'
    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(219, 234, 254)
    $subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $subtitle.AutoSize = $true
    $subtitle.Location = New-Object System.Drawing.Point(25, 45)
    $header.Controls.Add($subtitle)

    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = 'Bottom'
    $footer.Height = 58
    $footer.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $form.Controls.Add($footer)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    $tabs.Padding = New-Object System.Drawing.Point(14, 7)
    $form.Controls.Add($tabs)
    $tabs.BringToFront()

    function New-TabPage([string]$Text) {
        $page = New-Object System.Windows.Forms.TabPage
        $page.Text = $Text
        $page.BackColor = [System.Drawing.Color]::White
        return $page
    }

    $tabPrograms = New-TabPage 'Programas'
    $tabs.TabPages.Add($tabPrograms)

    $lblPrograms = New-Object System.Windows.Forms.Label
    $lblPrograms.Text = 'Programas permitidos para los usuarios del aula'
    $lblPrograms.AutoSize = $true
    $lblPrograms.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $lblPrograms.Location = New-Object System.Drawing.Point(18, 18)
    $tabPrograms.Controls.Add($lblPrograms)

    $lstPrograms = New-Object System.Windows.Forms.ListBox
    $lstPrograms.Location = New-Object System.Drawing.Point(20, 55)
    $lstPrograms.Size = New-Object System.Drawing.Size(730, 360)
    $lstPrograms.Anchor = 'Top,Left,Right,Bottom'
    $tabPrograms.Controls.Add($lstPrograms)
    foreach ($item in @($settings.allowedPrograms)) { Add-UniqueListItem $lstPrograms $item }

    $btnAddProgram = New-Object System.Windows.Forms.Button
    $btnAddProgram.Text = 'Agregar programa'
    $btnAddProgram.Location = New-Object System.Drawing.Point(765, 55)
    $btnAddProgram.Size = New-Object System.Drawing.Size(120, 34)
    $btnAddProgram.Anchor = 'Top,Right'
    $tabPrograms.Controls.Add($btnAddProgram)

    $btnRemoveProgram = New-Object System.Windows.Forms.Button
    $btnRemoveProgram.Text = 'Quitar'
    $btnRemoveProgram.Location = New-Object System.Drawing.Point(765, 98)
    $btnRemoveProgram.Size = New-Object System.Drawing.Size(120, 34)
    $btnRemoveProgram.Anchor = 'Top,Right'
    $tabPrograms.Controls.Add($btnRemoveProgram)

    $btnAddProgram.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Aplicaciones (*.exe)|*.exe|Todos los archivos (*.*)|*.*'
        $dlg.Multiselect = $true
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            foreach ($filePath in $dlg.FileNames) {
                Add-UniqueListItem $lstPrograms $filePath
                Write-AulaGuardAudit -Action 'PROGRAM_ADDED' -Detail $filePath
            }
        }
    })

    $btnRemoveProgram.Add_Click({
        while ($lstPrograms.SelectedIndices.Count -gt 0) {
            $index = $lstPrograms.SelectedIndices[0]
            $value = $lstPrograms.Items[$index].ToString()
            $lstPrograms.Items.RemoveAt($index)
            Write-AulaGuardAudit -Action 'PROGRAM_REMOVED' -Detail $value
        }
    })

    $tabWeb = New-TabPage 'Web'
    $tabs.TabPages.Add($tabWeb)

    $lblWeb = New-Object System.Windows.Forms.Label
    $lblWeb.Text = 'Sitios web permitidos'
    $lblWeb.AutoSize = $true
    $lblWeb.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $lblWeb.Location = New-Object System.Drawing.Point(18, 18)
    $tabWeb.Controls.Add($lblWeb)

    $txtWebsite = New-Object System.Windows.Forms.TextBox
    $txtWebsite.Location = New-Object System.Drawing.Point(20, 55)
    $txtWebsite.Size = New-Object System.Drawing.Size(620, 28)
    $txtWebsite.Anchor = 'Top,Left,Right'
    $tabWeb.Controls.Add($txtWebsite)

    $btnAddWebsite = New-Object System.Windows.Forms.Button
    $btnAddWebsite.Text = 'Agregar'
    $btnAddWebsite.Location = New-Object System.Drawing.Point(650, 52)
    $btnAddWebsite.Size = New-Object System.Drawing.Size(110, 32)
    $btnAddWebsite.Anchor = 'Top,Right'
    $tabWeb.Controls.Add($btnAddWebsite)

    $lstWebsites = New-Object System.Windows.Forms.ListBox
    $lstWebsites.Location = New-Object System.Drawing.Point(20, 100)
    $lstWebsites.Size = New-Object System.Drawing.Size(740, 315)
    $lstWebsites.Anchor = 'Top,Left,Right,Bottom'
    $tabWeb.Controls.Add($lstWebsites)
    foreach ($item in @($settings.allowedWebsites)) { Add-UniqueListItem $lstWebsites $item }

    $btnRemoveWebsite = New-Object System.Windows.Forms.Button
    $btnRemoveWebsite.Text = 'Quitar'
    $btnRemoveWebsite.Location = New-Object System.Drawing.Point(775, 100)
    $btnRemoveWebsite.Size = New-Object System.Drawing.Size(110, 32)
    $btnRemoveWebsite.Anchor = 'Top,Right'
    $tabWeb.Controls.Add($btnRemoveWebsite)

    $btnAddWebsite.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($txtWebsite.Text)) {
            Add-UniqueListItem $lstWebsites $txtWebsite.Text
            Write-AulaGuardAudit -Action 'WEBSITE_ADDED' -Detail $txtWebsite.Text.Trim()
            $txtWebsite.Clear()
        }
    })

    $btnRemoveWebsite.Add_Click({
        while ($lstWebsites.SelectedIndices.Count -gt 0) {
            $index = $lstWebsites.SelectedIndices[0]
            $value = $lstWebsites.Items[$index].ToString()
            $lstWebsites.Items.RemoveAt($index)
            Write-AulaGuardAudit -Action 'WEBSITE_REMOVED' -Detail $value
        }
    })

    $tabDesktop = New-TabPage 'Escritorio'
    $tabs.TabPages.Add($tabDesktop)

    $lblWallpaper = New-Object System.Windows.Forms.Label
    $lblWallpaper.Text = 'Fondo de escritorio institucional'
    $lblWallpaper.AutoSize = $true
    $lblWallpaper.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $lblWallpaper.Location = New-Object System.Drawing.Point(18, 18)
    $tabDesktop.Controls.Add($lblWallpaper)

    $txtWallpaper = New-Object System.Windows.Forms.TextBox
    $txtWallpaper.Location = New-Object System.Drawing.Point(20, 55)
    $txtWallpaper.Size = New-Object System.Drawing.Size(690, 28)
    $txtWallpaper.Anchor = 'Top,Left,Right'
    $txtWallpaper.ReadOnly = $true
    $txtWallpaper.Text = [string]$settings.wallpaper
    $tabDesktop.Controls.Add($txtWallpaper)

    $btnWallpaper = New-Object System.Windows.Forms.Button
    $btnWallpaper.Text = 'Seleccionar'
    $btnWallpaper.Location = New-Object System.Drawing.Point(725, 52)
    $btnWallpaper.Size = New-Object System.Drawing.Size(120, 32)
    $btnWallpaper.Anchor = 'Top,Right'
    $tabDesktop.Controls.Add($btnWallpaper)

    $btnWallpaper.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Imágenes|*.jpg;*.jpeg;*.png;*.bmp|Todos los archivos (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtWallpaper.Text = $dlg.FileName
            Write-AulaGuardAudit -Action 'WALLPAPER_SELECTED' -Detail $dlg.FileName
        }
    })

    $lblShortcuts = New-Object System.Windows.Forms.Label
    $lblShortcuts.Text = 'Accesos directos protegidos'
    $lblShortcuts.AutoSize = $true
    $lblShortcuts.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $lblShortcuts.Location = New-Object System.Drawing.Point(18, 115)
    $tabDesktop.Controls.Add($lblShortcuts)

    $lstShortcuts = New-Object System.Windows.Forms.ListBox
    $lstShortcuts.Location = New-Object System.Drawing.Point(20, 150)
    $lstShortcuts.Size = New-Object System.Drawing.Size(690, 255)
    $lstShortcuts.Anchor = 'Top,Left,Right,Bottom'
    $tabDesktop.Controls.Add($lstShortcuts)
    foreach ($item in @($settings.protectedShortcuts)) { Add-UniqueListItem $lstShortcuts $item }

    $btnAddShortcut = New-Object System.Windows.Forms.Button
    $btnAddShortcut.Text = 'Agregar acceso'
    $btnAddShortcut.Location = New-Object System.Drawing.Point(725, 150)
    $btnAddShortcut.Size = New-Object System.Drawing.Size(120, 32)
    $btnAddShortcut.Anchor = 'Top,Right'
    $tabDesktop.Controls.Add($btnAddShortcut)

    $btnRemoveShortcut = New-Object System.Windows.Forms.Button
    $btnRemoveShortcut.Text = 'Quitar'
    $btnRemoveShortcut.Location = New-Object System.Drawing.Point(725, 192)
    $btnRemoveShortcut.Size = New-Object System.Drawing.Size(120, 32)
    $btnRemoveShortcut.Anchor = 'Top,Right'
    $tabDesktop.Controls.Add($btnRemoveShortcut)

    $btnAddShortcut.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Accesos directos (*.lnk)|*.lnk|Todos los archivos (*.*)|*.*'
        $dlg.Multiselect = $true
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            foreach ($filePath in $dlg.FileNames) {
                Add-UniqueListItem $lstShortcuts $filePath
                Write-AulaGuardAudit -Action 'SHORTCUT_ADDED' -Detail $filePath
            }
        }
    })

    $btnRemoveShortcut.Add_Click({
        while ($lstShortcuts.SelectedIndices.Count -gt 0) {
            $index = $lstShortcuts.SelectedIndices[0]
            $value = $lstShortcuts.Items[$index].ToString()
            $lstShortcuts.Items.RemoveAt($index)
            Write-AulaGuardAudit -Action 'SHORTCUT_REMOVED' -Detail $value
        }
    })

    $tabAudit = New-TabPage 'Bitácora'
    $tabs.TabPages.Add($tabAudit)

    $lblAudit = New-Object System.Windows.Forms.Label
    $lblAudit.Text = 'Actividad registrada'
    $lblAudit.AutoSize = $true
    $lblAudit.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $lblAudit.Location = New-Object System.Drawing.Point(18, 18)
    $tabAudit.Controls.Add($lblAudit)

    $txtAudit = New-Object System.Windows.Forms.TextBox
    $txtAudit.Location = New-Object System.Drawing.Point(20, 55)
    $txtAudit.Size = New-Object System.Drawing.Size(825, 350)
    $txtAudit.Anchor = 'Top,Left,Right,Bottom'
    $txtAudit.Multiline = $true
    $txtAudit.ScrollBars = 'Both'
    $txtAudit.ReadOnly = $true
    $txtAudit.Font = New-Object System.Drawing.Font('Consolas', 9)
    $tabAudit.Controls.Add($txtAudit)

    $btnRefreshAudit = New-Object System.Windows.Forms.Button
    $btnRefreshAudit.Text = 'Actualizar'
    $btnRefreshAudit.Location = New-Object System.Drawing.Point(20, 420)
    $btnRefreshAudit.Size = New-Object System.Drawing.Size(110, 32)
    $btnRefreshAudit.Anchor = 'Left,Bottom'
    $tabAudit.Controls.Add($btnRefreshAudit)

    $loadAudit = {
        $auditFiles = Get-ChildItem -Path $logsDir -Filter 'audit-*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 5

        $lines = @()
        foreach ($auditFile in ($auditFiles | Sort-Object Name)) {
            $lines += "=== $($auditFile.Name) ==="
            $lines += Get-Content -Path $auditFile.FullName -ErrorAction SilentlyContinue
            $lines += ''
        }
        $txtAudit.Text = ($lines -join [Environment]::NewLine)
        $txtAudit.SelectionStart = $txtAudit.TextLength
        $txtAudit.ScrollToCaret()
    }

    $btnRefreshAudit.Add_Click($loadAudit)
    & $loadAudit

    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Configuración cargada'
    $status.AutoSize = $true
    $status.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $status.Location = New-Object System.Drawing.Point(20, 20)
    $footer.Controls.Add($status)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Guardar configuración'
    $btnSave.Size = New-Object System.Drawing.Size(165, 34)
    $btnSave.Location = New-Object System.Drawing.Point(735, 12)
    $btnSave.Anchor = 'Top,Right'
    $footer.Controls.Add($btnSave)

    $btnSave.Add_Click({
        $updated = [pscustomobject]@{
            version = '0.1.1'
            wallpaper = $txtWallpaper.Text.Trim()
            allowedPrograms = @(Get-ListItems $lstPrograms)
            allowedWebsites = @(Get-ListItems $lstWebsites)
            protectedShortcuts = @(Get-ListItems $lstShortcuts)
            auditEnabled = $true
        }
        Save-AulaGuardSettings -Settings $updated
        $status.Text = "Guardado: $(Get-Date -Format 'HH:mm:ss')"
        [System.Windows.Forms.MessageBox]::Show(
            'La configuración de AulaGuard fue guardada correctamente.',
            'AulaGuard',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        & $loadAudit
    })

    Write-AulaGuardAudit -Action 'APP_STARTED' -Detail "Root=$appRoot"

    $form.Add_FormClosed({
        try { Write-AulaGuardAudit -Action 'APP_CLOSED' } catch {}
    })

    [void]$form.ShowDialog()
}
catch {
    $newLine = [Environment]::NewLine
    $message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')$newLine$($_.Exception.ToString())"
    try {
        $fallbackRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { $env:TEMP }
        $errorFile = Join-Path $fallbackRoot 'startup-error.txt'
        Set-Content -Path $errorFile -Value $message -Encoding UTF8
    } catch {}

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $dialogMessage = "AulaGuard no pudo iniciar.$newLine$newLine$($_.Exception.Message)$newLine$newLineRevise startup-error.txt."
        [System.Windows.Forms.MessageBox]::Show(
            $dialogMessage,
            'AulaGuard - Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {}
    exit 1
}
