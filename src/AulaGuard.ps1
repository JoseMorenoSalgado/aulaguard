# AulaGuard v0.5.1
# Friendly educational administration console for Windows classrooms.

$ErrorActionPreference = 'Stop'

# Command-line self-tests survive UAC elevation, unlike process environment variables.
$script:AulaGuardCommandLine = @([Environment]::GetCommandLineArgs()) + @($args)
$script:AulaGuardBootstrapTest = (($script:AulaGuardCommandLine -contains '--aulaguard-selftest-bootstrap') -or ($env:AULAGUARD_EXE_SELFTEST -eq '1'))
$script:AulaGuardUiTest = (($script:AulaGuardCommandLine -contains '--aulaguard-selftest-ui') -or ($env:AULAGUARD_UI_SELFTEST -eq '1'))

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # PS2EXE does not reliably populate $PSScriptRoot when running the compiled EXE.
    # Use the executable's actual directory, never the current working directory.
    $script:AulaGuardSourceDir = if (
        -not [string]::IsNullOrWhiteSpace($PSScriptRoot) -and
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'AulaGuard.Security.psm1') -PathType Leaf)
    ) {
        [IO.Path]::GetFullPath($PSScriptRoot)
    } else {
        [IO.Path]::GetDirectoryName([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    }
    if ([string]::IsNullOrWhiteSpace($script:AulaGuardSourceDir)) {
        throw 'No se pudo determinar la carpeta del ejecutable AulaGuard.'
    }

    foreach ($moduleName in @(
        'AulaGuard.Security.psm1',
        'AulaGuard.Core.psm1',
        'AulaGuard.Policy.psm1',
        'AulaGuard.Diagnostics.psm1',
        'AulaGuard.AppControl.psm1',
        'AulaGuard.USB.psm1',
        'AulaGuard.InstalledApps.psm1',
        'AulaGuard.Wallpaper.psm1',
        'AulaGuard.Maintenance.psm1'
    )) {
        $modulePath = Join-Path $script:AulaGuardSourceDir $moduleName
        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            throw "No se encontró el módulo requerido: $modulePath"
        }
        Import-Module -Name $modulePath -Force -ErrorAction Stop
    }

    if (-not (Test-AulaGuardAdministrator)) {
        [System.Windows.Forms.MessageBox]::Show(
            'AulaGuard necesita permisos de administrador para proteger el aula.',
            'AulaGuard','OK','Warning'
        ) | Out-Null
        exit 1
    }

    $root = Get-AulaGuardRoot
    Initialize-AulaGuardSecurity -Root $root
    $settings = Read-AulaGuardSettings -Root $root
    $script:originalWallpaperPath = [string]$settings.wallpaper

    # Diagnostic mode verifies module imports, integrity checks and protected settings
    # before exiting; it never skips a security validation.
    if ($script:AulaGuardBootstrapTest) {
        Write-AulaGuardAudit -Action 'EXE_BOOTSTRAP_VERIFIED' -Level 'SECURITY' -Root $root
        exit 0
    }

    $Primary = [System.Drawing.Color]::FromArgb(22,163,74)
    $PrimaryDark = [System.Drawing.Color]::FromArgb(20,83,45)
    $Success = [System.Drawing.Color]::FromArgb(22,163,74)
    $Warning = [System.Drawing.Color]::FromArgb(217,119,6)
    $Danger = [System.Drawing.Color]::FromArgb(220,38,38)
    $Bg = [System.Drawing.Color]::FromArgb(246,248,250)
    $Card = [System.Drawing.Color]::White
    $Text = [System.Drawing.Color]::FromArgb(15,23,42)
    $Muted = [System.Drawing.Color]::FromArgb(100,116,139)
    $Border = [System.Drawing.Color]::FromArgb(226,232,240)
    $BorderStrong = [System.Drawing.Color]::FromArgb(203,213,225)
    $SoftBlue = [System.Drawing.Color]::FromArgb(236,253,245)
    $SoftGreen = [System.Drawing.Color]::FromArgb(240,253,244)
    $SoftAmber = [System.Drawing.Color]::FromArgb(255,251,235)
    $SoftRed = [System.Drawing.Color]::FromArgb(254,242,242)
    $SlateSoft = [System.Drawing.Color]::FromArgb(248,250,252)

    function New-Label {
        param(
            [string]$TextValue,
            [int]$X,
            [int]$Y,
            [int]$Size = 9,
            [bool]$Bold = $false,
            [System.Drawing.Color]$Color = $Text
        )
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $TextValue
        $l.AutoSize = $true
        $l.Location = New-Object System.Drawing.Point($X,$Y)
        $l.ForeColor = $Color
        $l.Font = New-Object System.Drawing.Font($(if ($Bold) {'Segoe UI Semibold'} else {'Segoe UI'}),$Size)
        return $l
    }

    function New-Button {
        param(
            [string]$TextValue,
            [int]$X,
            [int]$Y,
            [int]$W = 150,
            [int]$H = 38,
            [ValidateSet('Primary','Secondary','Success','Danger','Neutral')][string]$Style = 'Neutral'
        )
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $TextValue
        $b.Location = New-Object System.Drawing.Point($X,$Y)
        $b.Size = New-Object System.Drawing.Size($W,$H)
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize = 1
        $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(220,252,231)
        $b.Cursor = 'Hand'
        $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
        $b.UseVisualStyleBackColor = $false

        switch ($Style) {
            'Primary' {
                $b.BackColor = $Primary
                $b.ForeColor = [System.Drawing.Color]::White
                $b.FlatAppearance.BorderColor = $Primary
            }
            'Success' {
                $b.BackColor = $Success
                $b.ForeColor = [System.Drawing.Color]::White
                $b.FlatAppearance.BorderColor = $Success
            }
            'Secondary' {
                $b.BackColor = $SoftBlue
                $b.ForeColor = $PrimaryDark
                $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(187,247,208)
            }
            'Danger' {
                $b.BackColor = [System.Drawing.Color]::White
                $b.ForeColor = $Danger
                $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(254,202,202)
            }
            default {
                $b.BackColor = [System.Drawing.Color]::White
                $b.ForeColor = $Text
                $b.FlatAppearance.BorderColor = $Border
            }
        }
        return $b
    }

    function New-NavButton {
        param([string]$TextValue,[int]$Y)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $TextValue
        $b.Location = New-Object System.Drawing.Point(12,$Y)
        $b.Size = New-Object System.Drawing.Size(184,42)
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = $SlateSoft
        $b.TextAlign = 'MiddleLeft'
        $b.Padding = New-Object System.Windows.Forms.Padding(16,0,0,0)
        $b.Cursor = 'Hand'
        $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
        $b.BackColor = [System.Drawing.Color]::White
        $b.ForeColor = $Muted
        return $b
    }

    function New-Card {
        param(
            [int]$X,[int]$Y,[int]$W,[int]$H,
            [System.Drawing.Color]$BackColor = $Card
        )
        $p = New-Object System.Windows.Forms.Panel
        $p.Location = New-Object System.Drawing.Point($X,$Y)
        $p.Size = New-Object System.Drawing.Size($W,$H)
        $p.BackColor = $BackColor
        $p.BorderStyle = 'FixedSingle'
        return $p
    }

    function New-Surface {
        param(
            [System.Drawing.Color]$BackColor = $Card,
            [int]$Padding = 16
        )
        $p = New-Object System.Windows.Forms.Panel
        $p.Dock = 'Fill'
        $p.BackColor = $BackColor
        $p.BorderStyle = 'FixedSingle'
        $p.Padding = New-Object System.Windows.Forms.Padding($Padding)
        $p.Margin = New-Object System.Windows.Forms.Padding(0,0,12,12)
        return $p
    }

    function Style-Input {
        param([System.Windows.Forms.Control]$Control)
        $Control.Font = New-Object System.Drawing.Font('Segoe UI',10)
        $Control.BackColor = [System.Drawing.Color]::White
        $Control.ForeColor = $Text
        $Control.Margin = New-Object System.Windows.Forms.Padding(0,5,0,5)
    }

    function Style-Check {
        param([System.Windows.Forms.CheckBox]$Control)
        $Control.FlatStyle = 'Flat'
        $Control.Font = New-Object System.Drawing.Font('Segoe UI',9)
        $Control.ForeColor = $Text
        $Control.Cursor = 'Hand'
    }

    function New-MetricSurface {
        param(
            [string]$Caption,
            [string]$InitialValue,
            [string]$Hint,
            [System.Drawing.Color]$Accent = $Primary
        )
        $panel = New-Surface -BackColor $Card -Padding 0
        $panel.Margin = New-Object System.Windows.Forms.Padding(0,0,12,0)

        $accentPanel = New-Object System.Windows.Forms.Panel
        $accentPanel.Dock = 'Left'
        $accentPanel.Width = 4
        $accentPanel.BackColor = $Accent
        $panel.Controls.Add($accentPanel)

        $captionLabel = New-Label $Caption 18 14 8 $true $Muted
        $valueLabel = New-Label $InitialValue 18 40 15 $true $Text
        $hintLabel = New-Label $Hint 18 77 8 $false $Muted
        $hintLabel.MaximumSize = New-Object System.Drawing.Size(230,34)
        $panel.Controls.Add($captionLabel)
        $panel.Controls.Add($valueLabel)
        $panel.Controls.Add($hintLabel)
        return [pscustomobject]@{ Panel=$panel; Value=$valueLabel; Hint=$hintLabel }
    }

    function Style-Grid {
        param([System.Windows.Forms.DataGridView]$Grid)
        $Grid.BackgroundColor = [System.Drawing.Color]::White
        $Grid.BorderStyle = 'None'
        $Grid.CellBorderStyle = 'SingleHorizontal'
        $Grid.GridColor = $Border
        $Grid.RowHeadersVisible = $false
        $Grid.AllowUserToAddRows = $false
        $Grid.AllowUserToDeleteRows = $false
        $Grid.ReadOnly = $true
        $Grid.SelectionMode = 'FullRowSelect'
        $Grid.MultiSelect = $false
        $Grid.AutoSizeColumnsMode = 'Fill'
        $Grid.EnableHeadersVisualStyles = $false
        $Grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(248,250,252)
        $Grid.ColumnHeadersDefaultCellStyle.ForeColor = $Text
        $Grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
        $Grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(220,252,231)
        $Grid.DefaultCellStyle.SelectionForeColor = $Text
        $Grid.DefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI',9)
        $Grid.RowTemplate.Height = 30
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
        $items = @()
        foreach ($item in $List.Items) {
            $items += [string]$item
        }
        return $items
    }

    function Set-Status {
        param([string]$Message,[string]$Type='Info')
        $prefix = '●'
        $status.Text = "$prefix  $Message"
        switch ($Type) {
            'Success' {$status.ForeColor = $Success}
            'Warning' {$status.ForeColor = $Warning}
            'Error' {$status.ForeColor = $Danger}
            default {$status.ForeColor = $Muted}
        }
    }

    function Get-UiSettings {
        $protections = [pscustomobject]@{
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
            version = '0.5.1'
            profileName = $txtProfileName.Text.Trim()
            policyMode = if ($radEnforce.Checked) {'Enforce'} else {'Audit'}
            wallpaper = $txtWallpaper.Text.Trim()
            allowedPrograms = @(Get-ListItems $lstPrograms)
            allowedWebsites = @(Get-ListItems $lstWebsites)
            protectedShortcuts = @(Get-ListItems $lstShortcuts)
            protections = $protections
            usb = [pscustomobject]@{
                blockStorage = [bool]$toggleUsb.Checked
            }
            maintenance = $settings.maintenance
            premium = $settings.premium
            appControl = [pscustomobject]@{
                mode = [string]$settings.appControl.mode
                enabled = [bool]$settings.appControl.enabled
                lastAppliedUtc = $settings.appControl.lastAppliedUtc
                lastBackup = $settings.appControl.lastBackup
            }
            auditEnabled = $true
            lastAppliedUtc = $settings.lastAppliedUtc
        }
    }

    function Save-FromUi {
        $newSettings = Get-UiSettings
        # Publish the file into a managed read-only student-accessible directory.
        # Never store an administrator-only Downloads path as a student wallpaper.
        if (-not [string]::IsNullOrWhiteSpace([string]$newSettings.wallpaper)) {
            $newSettings.wallpaper = Publish-AulaGuardWallpaper -SourcePath $newSettings.wallpaper
            $txtWallpaper.Text = $newSettings.wallpaper
        }
        $script:settings = $newSettings
        Backup-AulaGuardConfiguration -Root $root | Out-Null
        Save-AulaGuardSettings -Settings $script:settings -Root $root | Out-Null
        Write-AulaGuardAudit -Action 'CONFIG_SAVED' -Detail "Profile=$($settings.profileName)" -Root $root
        Set-Status "Cambios guardados a las $(Get-Date -Format 'HH:mm:ss')" 'Success'
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'AulaGuard · Centro de control del aula'
    $form.StartPosition = 'CenterScreen'
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $formWidth = [Math]::Min(1320, [Math]::Max(1120, $workingArea.Width - 40))
    $formHeight = [Math]::Min(820, [Math]::Max(700, $workingArea.Height - 40))
    $form.Size = New-Object System.Drawing.Size($formWidth,$formHeight)
    $form.MinimumSize = New-Object System.Drawing.Size(1080,680)
    $form.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $form.AutoScaleMode = 'Dpi'
    $form.BackColor = $Bg

    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.AutoPopDelay = 9000
    $toolTip.InitialDelay = 300

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 82
    $header.BackColor = $PrimaryDark
    $form.Controls.Add($header)

    $logo = New-Object System.Windows.Forms.Label
    $logo.Text = 'AG'
    $logo.TextAlign = 'MiddleCenter'
    $logo.Location = New-Object System.Drawing.Point(22,14)
    $logo.Size = New-Object System.Drawing.Size(52,52)
    $logo.BackColor = [System.Drawing.Color]::White
    $logo.ForeColor = $PrimaryDark
    $logo.Font = New-Object System.Drawing.Font('Segoe UI Semibold',15)
    $header.Controls.Add($logo)

    $header.Controls.Add((New-Label 'AulaGuard' 92 12 20 $true ([System.Drawing.Color]::White)))
    $header.Controls.Add((New-Label 'Administración segura para aulas Windows' 94 43 9 $false ([System.Drawing.Color]::FromArgb(220,252,231))))

    $version = New-Object System.Windows.Forms.Label
    $version.Text = 'v0.5.1'
    $version.TextAlign = 'MiddleCenter'
    $version.Location = New-Object System.Drawing.Point(1060,22)
    $version.Size = New-Object System.Drawing.Size(82,30)
    $version.Anchor = 'Top,Right'
    $version.BackColor = [System.Drawing.Color]::FromArgb(21,128,61)
    $version.ForeColor = [System.Drawing.Color]::White
    $version.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $header.Controls.Add($version)
    $header.Add_Resize({ $version.Left = [Math]::Max(240,$header.ClientSize.Width - $version.Width - 22) })

    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = 'Bottom'
    $footer.Height = 62
    $footer.BackColor = [System.Drawing.Color]::White
    $form.Controls.Add($footer)

    $status = New-Label '●  AulaGuard listo' 18 21 9 $false $Muted
    $footer.Controls.Add($status)

    $btnSave = New-Button 'Guardar cambios' 850 11 135 38 'Secondary'
    $btnSave.Anchor = 'Top,Right'
    $footer.Controls.Add($btnSave)

    $btnApply = New-Button 'Aplicar protección' 995 11 155 38 'Success'
    $btnApply.Anchor = 'Top,Right'
    $footer.Controls.Add($btnApply)
    $footer.Add_Resize({
        $btnApply.Left = [Math]::Max(180,$footer.ClientSize.Width - $btnApply.Width - 22)
        $btnSave.Left = $btnApply.Left - $btnSave.Width - 12
        $status.MaximumSize = New-Object System.Drawing.Size([Math]::Max(120,$btnSave.Left - 32),0)
    })

    $workspace = New-Object System.Windows.Forms.Panel
    $workspace.Dock = 'Fill'
    $workspace.BackColor = $Bg
    $form.Controls.Add($workspace)
    $workspace.BringToFront()

    # Explicit columns prevent a docked sidebar from painting over the content.
    $shell = New-Object System.Windows.Forms.TableLayoutPanel
    $shell.Dock = 'Fill'
    $shell.ColumnCount = 2
    $shell.RowCount = 1
    $shell.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$shell.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',220)))
    [void]$shell.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    $workspace.Controls.Add($shell)

    $sidebar = New-Object System.Windows.Forms.Panel
    $sidebar.Dock = 'Fill'
    $sidebar.Margin = New-Object System.Windows.Forms.Padding(0)
    $sidebar.BackColor = [System.Drawing.Color]::White
    $shell.Controls.Add($sidebar,0,0)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    $tabs.Margin = New-Object System.Windows.Forms.Padding(0)
    $tabs.Appearance = 'FlatButtons'
    $tabs.SizeMode = 'Fixed'
    $tabs.ItemSize = New-Object System.Drawing.Size(0,1)
    $tabs.Padding = New-Object System.Drawing.Point(0,0)
    $tabs.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $shell.Controls.Add($tabs,1,0)

    $sidebar.Controls.Add((New-Label 'NAVEGACIÓN' 22 18 8 $true $Muted))

    $navHome = New-NavButton 'Inicio' 46
    $navHealth = New-NavButton 'Estado del sistema' 92
    $navProtection = New-NavButton 'Protección' 138
    $navPrograms = New-NavButton 'Programas' 184
    $navAppControl = New-NavButton 'Control de apps' 230
    $navInternet = New-NavButton 'Internet' 276
    $navDesktop = New-NavButton 'Escritorio' 322
    $navUsb = New-NavButton 'Memorias USB' 368
    $navPremium = New-NavButton 'Servidor · Premium' 414
    $navLog = New-NavButton 'Registro' 460

    foreach ($nav in @($navHome,$navHealth,$navProtection,$navPrograms,$navAppControl,$navInternet,$navDesktop,$navUsb,$navPremium,$navLog)) {
        $sidebar.Controls.Add($nav)
    }

    $sideInfo = New-Card 12 530 194 110 $SoftGreen
    $sideInfo.Controls.Add((New-Label 'Consejo de despliegue' 12 12 9 $true $PrimaryDark))
    $sideInfo.Controls.Add((New-Label 'Prueba primero en' 12 42 8 $false $Muted))
    $sideInfo.Controls.Add((New-Label 'auditoría y luego' 12 62 8 $false $Muted))
    $sideInfo.Controls.Add((New-Label 'activa restricciones.' 12 82 8 $false $Muted))
    $sidebar.Controls.Add($sideInfo)
    $sidebar.Add_Resize({
        $sideInfo.Visible = ($sidebar.ClientSize.Height -gt 690)
        $sideInfo.Top = [Math]::Max(520,$sidebar.ClientSize.Height - $sideInfo.Height - 12)
    })

    function Set-NavActive {
        param($Active)
        foreach ($nav in @($navHome,$navHealth,$navProtection,$navPrograms,$navAppControl,$navInternet,$navDesktop,$navUsb,$navPremium,$navLog)) {
            $nav.BackColor = [System.Drawing.Color]::White
            $nav.ForeColor = $Muted
            $nav.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
        }
        $Active.BackColor = $SoftGreen
        $Active.ForeColor = $PrimaryDark
        $Active.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9.5)
    }

    # HOME — responsive executive overview.
    $tabHome = New-Object System.Windows.Forms.TabPage
    $tabHome.Text = 'Inicio'
    $tabHome.BackColor = $Bg
    $tabs.TabPages.Add($tabHome)

    $homeLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $homeLayout.Dock = 'Fill'
    $homeLayout.Padding = New-Object System.Windows.Forms.Padding(24,18,24,18)
    $homeLayout.ColumnCount = 1
    $homeLayout.RowCount = 5
    [void]$homeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',68)))
    [void]$homeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',88)))
    [void]$homeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',126)))
    [void]$homeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',148)))
    [void]$homeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $tabHome.Controls.Add($homeLayout)

    $homeHeader = New-Object System.Windows.Forms.Panel
    $homeHeader.Dock = 'Fill'
    $homeHeader.Controls.Add((New-Label 'Centro de control del aula' 0 0 18 $true $Text))
    $homeHeader.Controls.Add((New-Label 'Supervisa el equipo, prepara la configuración y aplica cambios con seguridad.' 0 36 9 $false $Muted))
    $homeLayout.Controls.Add($homeHeader,0,0)

    $homeState = New-Surface -BackColor $SoftGreen -Padding 0
    $homeState.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    $lblHomeStateTitle = New-Label 'Comprobando el equipo...' 18 14 11 $true $PrimaryDark
    $lblHomeStateDetail = New-Label 'AulaGuard validará Windows antes de aplicar restricciones.' 18 43 9 $false $Muted
    $btnGoHealth = New-Button 'Ver estado' 0 0 125 34 'Secondary'
    $btnGoHealth.Anchor = 'Top,Right'
    $btnGoHealth.Location = New-Object System.Drawing.Point(900,19)
    $homeState.Controls.Add($lblHomeStateTitle)
    $homeState.Controls.Add($lblHomeStateDetail)
    $homeState.Controls.Add($btnGoHealth)
    $homeState.Add_Resize({ $btnGoHealth.Left = [Math]::Max(540,$homeState.ClientSize.Width - $btnGoHealth.Width - 18) })
    $homeLayout.Controls.Add($homeState,0,1)

    $metrics = New-Object System.Windows.Forms.TableLayoutPanel
    $metrics.Dock = 'Fill'
    $metrics.ColumnCount = 4
    $metrics.RowCount = 1
    $metrics.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    foreach ($i in 1..4) { [void]$metrics.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',25))) }
    $homeLayout.Controls.Add($metrics,0,2)

    $metricPc = New-MetricSurface 'EQUIPO' '-' 'Nombre y edición de Windows' $Primary
    $metricUsers = New-MetricSurface 'ESTUDIANTES' '-' 'Administradores excluidos' $Success
    $metricMode = New-MetricSurface 'PROTECCIÓN' '-' 'Estado general del equipo' $Warning
    $metricApps = New-MetricSurface 'APPS PERMITIDAS' '0' 'Selección para AppLocker' $PrimaryDark
    $metrics.Controls.Add($metricPc.Panel,0,0)
    $metrics.Controls.Add($metricUsers.Panel,1,0)
    $metrics.Controls.Add($metricMode.Panel,2,0)
    $metrics.Controls.Add($metricApps.Panel,3,0)
    $lblPcValue = $metricPc.Value
    $lblWindowsValue = $metricPc.Hint
    $lblUsersValue = $metricUsers.Value
    $lblModeValue = $metricMode.Value
    $lblAppsValue = $metricApps.Value

    $quick = New-Object System.Windows.Forms.TableLayoutPanel
    $quick.Dock = 'Fill'
    $quick.ColumnCount = 3
    $quick.RowCount = 1
    $quick.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    foreach ($i in 1..3) { [void]$quick.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',33.333))) }
    $homeLayout.Controls.Add($quick,0,3)

    $quickProtect = New-Surface -BackColor $Card -Padding 0
    $quickProtect.Controls.Add((New-Label '1 · Preparar políticas' 18 16 11 $true $Text))
    $quickProtect.Controls.Add((New-Label 'Fondo, herramientas del sistema, Internet y USB.' 18 48 9 $false $Muted))
    $btnGoProtect = New-Button 'Configurar protección' 18 86 165 34 'Secondary'
    $quickProtect.Controls.Add($btnGoProtect)
    $quick.Controls.Add($quickProtect,0,0)

    $quickPrograms = New-Surface -BackColor $Card -Padding 0
    $quickPrograms.Controls.Add((New-Label '2 · Elegir aplicaciones' 18 16 11 $true $Text))
    $quickPrograms.Controls.Add((New-Label 'Detecta software instalado y decide qué necesita el aula.' 18 48 9 $false $Muted))
    $btnGoApps = New-Button 'Revisar programas' 18 86 158 34 'Secondary'
    $quickPrograms.Controls.Add($btnGoApps)
    $quick.Controls.Add($quickPrograms,1,0)

    $quickAudit = New-Surface -BackColor $SoftGreen -Padding 0
    $quickAudit.Controls.Add((New-Label '3 · Validar antes de bloquear' 18 16 11 $true $PrimaryDark))
    $quickAudit.Controls.Add((New-Label 'Usa auditoría, revisa eventos y activa bloqueo al final.' 18 48 9 $false $Muted))
    $lblQuickAudit = New-Label 'Recomendado: Auditoría' 18 90 9 $true $Success
    $quickAudit.Controls.Add($lblQuickAudit)
    $quick.Controls.Add($quickAudit,2,0)

    $usersSurface = New-Surface -BackColor $Card -Padding 0
    $usersSurface.Margin = New-Object System.Windows.Forms.Padding(0)
    $usersHeader = New-Object System.Windows.Forms.Panel
    $usersHeader.Dock = 'Top'
    $usersHeader.Height = 48
    $usersHeader.BackColor = $Card
    $usersHeader.Controls.Add((New-Label 'Usuarios detectados' 16 13 11 $true $Text))
    $usersSurface.Controls.Add($usersHeader)

    $gridUsers = New-Object System.Windows.Forms.DataGridView
    $gridUsers.Dock = 'Fill'
    $gridUsers.Margin = New-Object System.Windows.Forms.Padding(0)
    Style-Grid $gridUsers
    $gridUsers.RowTemplate.Height = 34
    [void]$gridUsers.Columns.Add('User','Usuario')
    [void]$gridUsers.Columns.Add('Role','Tipo de cuenta')
    [void]$gridUsers.Columns.Add('State','Estado')
    [void]$gridUsers.Columns.Add('SID','Identificador')
    $gridUsers.Columns['SID'].FillWeight = 160
    $usersSurface.Controls.Add($gridUsers)
    $gridUsers.BringToFront()
    $homeLayout.Controls.Add($usersSurface,0,4)

    # SYSTEM STATUS — professional preflight view.
    $tabHealth = New-Object System.Windows.Forms.TabPage
    $tabHealth.Text = 'Estado del sistema'
    $tabHealth.BackColor = $Bg
    $tabs.TabPages.Add($tabHealth)

    $healthLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $healthLayout.Dock = 'Fill'
    $healthLayout.Padding = New-Object System.Windows.Forms.Padding(22,16,22,14)
    $healthLayout.ColumnCount = 1
    $healthLayout.RowCount = 4
    [void]$healthLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',70)))
    [void]$healthLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',76)))
    [void]$healthLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    [void]$healthLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',52)))
    $tabHealth.Controls.Add($healthLayout)

    $healthHeader = New-Object System.Windows.Forms.Panel
    $healthHeader.Dock = 'Fill'
    $healthHeader.Controls.Add((New-Label 'Estado del sistema' 0 0 17 $true $Text))
    $healthHeader.Controls.Add((New-Label 'Comprueba si Windows está listo antes de aplicar restricciones.' 0 35 9 $false $Muted))
    $healthLayout.Controls.Add($healthHeader,0,0)

    $healthSummaryCard = New-Object System.Windows.Forms.Panel
    $healthSummaryCard.Dock = 'Fill'
    $healthSummaryCard.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    $healthSummaryCard.BackColor = $SoftGreen
    $lblHealthTitle = New-Label 'Comprobación pendiente' 15 10 11 $true $PrimaryDark
    $lblHealthDetail = New-Label 'Pulsa Actualizar diagnóstico para comprobar este equipo.' 15 38 9 $false $Muted
    $healthSummaryCard.Controls.Add($lblHealthTitle)
    $healthSummaryCard.Controls.Add($lblHealthDetail)
    $healthLayout.Controls.Add($healthSummaryCard,0,1)

    $gridHealth = New-Object System.Windows.Forms.DataGridView
    $gridHealth.Dock = 'Fill'
    $gridHealth.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
    Style-Grid $gridHealth
    [void]$gridHealth.Columns.Add('HealthStatus','Estado')
    [void]$gridHealth.Columns.Add('HealthCheck','Comprobación')
    [void]$gridHealth.Columns.Add('HealthDetail','Detalle')
    $gridHealth.Columns['HealthStatus'].FillWeight = 70
    $gridHealth.Columns['HealthCheck'].FillWeight = 135
    $gridHealth.Columns['HealthDetail'].FillWeight = 260
    $healthLayout.Controls.Add($gridHealth,0,2)

    $healthActions = New-Object System.Windows.Forms.FlowLayoutPanel
    $healthActions.Dock = 'Fill'
    $healthActions.FlowDirection = 'LeftToRight'
    $healthActions.WrapContents = $false
    $btnHealthRefresh = New-Button 'Actualizar diagnóstico' 0 0 190 38 'Primary'
    $btnHealthExport = New-Button 'Exportar diagnóstico' 0 0 185 38 'Secondary'
    $btnMaintenanceStart = New-Button 'Mantenimiento 30 min' 0 0 180 38 'Secondary'
    $btnMaintenanceStop = New-Button 'Finalizar mantenimiento' 0 0 180 38 'Danger'
    $btnHealthRefresh.Margin = New-Object System.Windows.Forms.Padding(0,5,10,4)
    $btnHealthExport.Margin = New-Object System.Windows.Forms.Padding(0,5,10,4)
    $btnMaintenanceStart.Margin = New-Object System.Windows.Forms.Padding(0,5,10,4)
    $btnMaintenanceStop.Margin = New-Object System.Windows.Forms.Padding(0,5,10,4)
    $healthActions.Controls.Add($btnHealthRefresh)
    $healthActions.Controls.Add($btnHealthExport)
    $healthActions.Controls.Add($btnMaintenanceStart)
    $healthActions.Controls.Add($btnMaintenanceStop)
    $healthLayout.Controls.Add($healthActions,0,3)

    $script:lastReadinessChecks = @()
    $loadReadiness = {
        try {
            $candidateSettings = Get-UiSettings
            $checks = @(Test-AulaGuardReadiness -Root $root -Settings $candidateSettings)
            $summary = Get-AulaGuardReadinessSummary -Checks $checks
            $script:lastReadinessChecks = $checks
            $gridHealth.Rows.Clear()
            foreach ($check in $checks) {
                $state = if ($check.Passed) {'Correcto'} elseif ($check.Severity -eq 'Critical') {'Bloquea'} else {'Atención'}
                $rowIndex = $gridHealth.Rows.Add($state,[string]$check.Name,[string]$check.Detail)
                $row = $gridHealth.Rows[$rowIndex]
                if (-not $check.Passed -and $check.Severity -eq 'Critical') {
                    $row.DefaultCellStyle.ForeColor = $Danger
                } elseif (-not $check.Passed) {
                    $row.DefaultCellStyle.ForeColor = $Warning
                }
            }
            if ($summary.Ready) {
                $healthSummaryCard.BackColor = $SoftGreen
                $lblHealthTitle.Text = 'Equipo listo'
                $lblHealthTitle.ForeColor = $Success
                $homeState.BackColor = $SoftGreen
                $lblHomeStateTitle.Text = 'Equipo listo para trabajar'
                $lblHomeStateTitle.ForeColor = $Success
                $lblHomeStateDetail.Text = "Diagnóstico correcto · $($summary.Passed)/$($summary.Total) comprobaciones"
            } else {
                $healthSummaryCard.BackColor = $SoftAmber
                $lblHealthTitle.Text = "Requiere atención · $($summary.Critical) bloqueo(s)"
                $lblHealthTitle.ForeColor = $Danger
                $homeState.BackColor = $(if ($summary.Critical -gt 0) {$SoftRed} else {$SoftAmber})
                $lblHomeStateTitle.Text = $(if ($summary.Critical -gt 0) {"Requiere atención · $($summary.Critical) bloqueo(s)"} else {'Hay advertencias por revisar'})
                $lblHomeStateTitle.ForeColor = $(if ($summary.Critical -gt 0) {$Danger} else {$Warning})
                $lblHomeStateDetail.Text = "Correctos: $($summary.Passed)/$($summary.Total) · Advertencias: $($summary.Warnings)"
            }
            $maintenanceState = Get-AulaGuardMaintenanceStatus -Settings $settings
            if ($maintenanceState.Enabled) {
                $btnMaintenanceStart.Enabled = $false
                $btnMaintenanceStop.Enabled = $true
                $btnMaintenanceStop.Text = "Finalizar · $($maintenanceState.RemainingMinutes) min"
                $healthSummaryCard.BackColor = $SoftAmber
                $lblHealthTitle.Text = 'Modo mantenimiento activo'
                $lblHealthTitle.ForeColor = $Warning
                $lblHealthDetail.Text = "Las restricciones de AulaGuard están suspendidas temporalmente. Se restaurarán automáticamente."
            } else {
                $btnMaintenanceStart.Enabled = $true
                $btnMaintenanceStop.Enabled = $false
                $btnMaintenanceStop.Text = 'Finalizar mantenimiento'
            }
            return $summary
        } catch {
            $gridHealth.Rows.Clear()
            [void]$gridHealth.Rows.Add('Error','Diagnóstico', $_.Exception.Message)
            $lblHealthTitle.Text = 'No se pudo completar el diagnóstico'
            $lblHealthTitle.ForeColor = $Danger
            $lblHealthDetail.Text = $_.Exception.Message
            $homeState.BackColor = $SoftRed
            $lblHomeStateTitle.Text = 'No se pudo validar el equipo'
            $lblHomeStateTitle.ForeColor = $Danger
            $lblHomeStateDetail.Text = 'Abre Estado del sistema para revisar el detalle.'
            return $null
        }
    }

    # PROTECTION
    $tabProtection = New-Object System.Windows.Forms.TabPage
    $tabProtection.Text = 'Protección'
    $tabProtection.BackColor = $Bg
    $tabs.TabPages.Add($tabProtection)

    $tabProtection.Controls.Add((New-Label 'Protección general del aula' 24 20 15 $true $Text))
    $tabProtection.Controls.Add((New-Label 'Activa solamente las restricciones que necesitas. Las cuentas administradoras quedan fuera.' 24 52 9 $false $Muted))

    $modeCard = New-Card 24 90 1094 94 $SoftBlue
    $modeCard.Controls.Add((New-Label 'Modo de trabajo' 16 14 10 $true $PrimaryDark))

    $radAudit = New-Object System.Windows.Forms.RadioButton
    $radAudit.Text = 'Auditoría / simulación'
    $radAudit.Location = New-Object System.Drawing.Point(18,50)
    $radAudit.AutoSize = $true
    $modeCard.Controls.Add($radAudit)
    $toolTip.SetToolTip($radAudit,'Auditoría: NO bloquea juegos, páginas ni el fondo de Windows.')

    $radEnforce = New-Object System.Windows.Forms.RadioButton
    $radEnforce.Text = 'Protección activa'
    $radEnforce.Location = New-Object System.Drawing.Point(210,50)
    $radEnforce.AutoSize = $true
    $modeCard.Controls.Add($radEnforce)
    $toolTip.SetToolTip($radEnforce,'Protección activa: aplica el fondo, sitios, restricciones de Windows y USB; los juegos/programas se activan por separado en Control de apps.')

    if ($settings.policyMode -eq 'Enforce') {$radEnforce.Checked = $true} else {$radAudit.Checked = $true}
    $btnApply.Text = if ($radEnforce.Checked) { 'Aplicar protección' } else { 'Simular (no bloquea)' }
    $radAudit.Add_CheckedChanged({
        if ($radAudit.Checked) { $btnApply.Text = 'Simular (no bloquea)' }
    })
    $radEnforce.Add_CheckedChanged({
        if ($radEnforce.Checked) { $btnApply.Text = 'Aplicar protección' }
    })
    $radAudit.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $radEnforce.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $radAudit.ForeColor = $PrimaryDark
    $radEnforce.ForeColor = $Danger
    $tabProtection.Controls.Add($modeCard)

    $left = New-Card 24 204 535 292 $Card
    $left.Controls.Add((New-Label 'Escritorio y apariencia' 18 16 11 $true $Text))

    $chkLockWallpaper = New-Object System.Windows.Forms.CheckBox
    $chkLockWallpaper.Text = 'Evitar que los estudiantes cambien el fondo'
    $chkLockWallpaper.Location = New-Object System.Drawing.Point(18,55)
    $chkLockWallpaper.AutoSize = $true
    $chkLockWallpaper.Checked = [bool]$settings.protections.lockWallpaper
    Style-Check $chkLockWallpaper
    $left.Controls.Add($chkLockWallpaper)

    $chkPersonalization = New-Object System.Windows.Forms.CheckBox
    $chkPersonalization.Text = 'Ocultar opciones de personalización'
    $chkPersonalization.Location = New-Object System.Drawing.Point(18,88)
    $chkPersonalization.AutoSize = $true
    $chkPersonalization.Checked = [bool]$settings.protections.disablePersonalization
    Style-Check $chkPersonalization
    $left.Controls.Add($chkPersonalization)

    $chkProtectDesktop = New-Object System.Windows.Forms.CheckBox
    $chkProtectDesktop.Text = 'Proteger accesos directos del escritorio público'
    $chkProtectDesktop.Location = New-Object System.Drawing.Point(18,121)
    $chkProtectDesktop.AutoSize = $true
    $chkProtectDesktop.Checked = [bool]$settings.protections.protectPublicDesktop
    Style-Check $chkProtectDesktop
    $left.Controls.Add($chkProtectDesktop)

    $left.Controls.Add((New-Label 'Fondo institucional' 18 170 9 $true $Text))
    $txtWallpaper = New-Object System.Windows.Forms.TextBox
    $txtWallpaper.Location = New-Object System.Drawing.Point(18,201)
    $txtWallpaper.Size = New-Object System.Drawing.Size(360,28)
    $txtWallpaper.ReadOnly = $true
    $txtWallpaper.Text = [string]$settings.wallpaper
    Style-Input $txtWallpaper
    $left.Controls.Add($txtWallpaper)

    $btnWallpaper = New-Button 'Elegir imagen' 390 198 120 32 'Secondary'
    $left.Controls.Add($btnWallpaper)
    $tabProtection.Controls.Add($left)

    $right = New-Card 583 204 535 292 $Card
    $right.Controls.Add((New-Label 'Herramientas del sistema' 18 16 11 $true $Text))
    $right.Controls.Add((New-Label 'Ayudan a mantener estable el equipo durante la clase.' 18 42 8 $false $Muted))

    $chkControlPanel = New-Object System.Windows.Forms.CheckBox
    $chkControlPanel.Text = 'Bloquear Panel de control y Configuración'
    $chkControlPanel.Location = New-Object System.Drawing.Point(18,80)
    $chkControlPanel.AutoSize = $true
    $chkControlPanel.Checked = [bool]$settings.protections.blockControlPanel
    Style-Check $chkControlPanel
    $right.Controls.Add($chkControlPanel)

    $chkRegistry = New-Object System.Windows.Forms.CheckBox
    $chkRegistry.Text = 'Bloquear Editor del Registro'
    $chkRegistry.Location = New-Object System.Drawing.Point(18,113)
    $chkRegistry.AutoSize = $true
    $chkRegistry.Checked = [bool]$settings.protections.blockRegistryTools
    Style-Check $chkRegistry
    $right.Controls.Add($chkRegistry)

    $chkTaskMgr = New-Object System.Windows.Forms.CheckBox
    $chkTaskMgr.Text = 'Bloquear Administrador de tareas'
    $chkTaskMgr.Location = New-Object System.Drawing.Point(18,146)
    $chkTaskMgr.AutoSize = $true
    $chkTaskMgr.Checked = [bool]$settings.protections.blockTaskManager
    Style-Check $chkTaskMgr
    $right.Controls.Add($chkTaskMgr)

    $chkBrowserWhitelist = New-Object System.Windows.Forms.CheckBox
    $chkBrowserWhitelist.Text = 'Permitir solo los sitios web definidos en AulaGuard'
    $chkBrowserWhitelist.Location = New-Object System.Drawing.Point(18,179)
    $chkBrowserWhitelist.AutoSize = $true
    $chkBrowserWhitelist.Checked = [bool]$settings.protections.browserWhitelist
    Style-Check $chkBrowserWhitelist
    $right.Controls.Add($chkBrowserWhitelist)

    $tabProtection.Controls.Add($right)

    $profileCard = New-Card 24 518 1094 100 $Card
    $profileCard.Controls.Add((New-Label 'Perfil del aula' 18 12 10 $true $Text))
    $profileCard.Controls.Add((New-Label 'Nombre' 18 50 9 $true $Muted))

    $txtProfileName = New-Object System.Windows.Forms.TextBox
    $txtProfileName.Location = New-Object System.Drawing.Point(78,46)
    $txtProfileName.Size = New-Object System.Drawing.Size(260,28)
    $txtProfileName.Text = [string]$settings.profileName
    Style-Input $txtProfileName
    $profileCard.Controls.Add($txtProfileName)

    $btnExport = New-Button 'Exportar perfil' 570 42 140 34 'Neutral'
    $profileCard.Controls.Add($btnExport)

    $btnImport = New-Button 'Importar perfil' 720 42 140 34 'Neutral'
    $profileCard.Controls.Add($btnImport)

    $btnReset = New-Button 'Retirar políticas' 870 42 160 34 'Danger'
    $profileCard.Controls.Add($btnReset)

    $tabProtection.Controls.Add($profileCard)
    # Reflow protection cards instead of clipping at fixed 1,100px width.
    $resizeProtection = {
        $usable = [Math]::Max(600,$tabProtection.ClientSize.Width - 52)
        $modeCard.Width = $usable
        $profileCard.Width = $usable
        if ($usable -lt 940) {
            $left.Size = New-Object System.Drawing.Size($usable,280)
            $right.Location = New-Object System.Drawing.Point(24,505)
            $right.Size = New-Object System.Drawing.Size($usable,244)
            $profileCard.Top = 765
        } else {
            $half = [int](($usable - 18)/2)
            $left.Size = New-Object System.Drawing.Size($half,292)
            $right.Location = New-Object System.Drawing.Point((24 + $half + 18),204)
            $right.Size = New-Object System.Drawing.Size($half,292)
            $profileCard.Top = 518
        }
        $btnWallpaper.Left = [Math]::Max(340,$left.ClientSize.Width - $btnWallpaper.Width - 18)
        $txtWallpaper.Width = [Math]::Max(240,$btnWallpaper.Left - 28)
        $btnReset.Left = [Math]::Max(490,$profileCard.ClientSize.Width - 178)
        $btnImport.Left = $btnReset.Left - 150
        $btnExport.Left = $btnImport.Left - 150
    }
    $tabProtection.Add_Resize($resizeProtection)

    # PROGRAMS — read-only installed-app inventory; switches edit an allow list,
    # not an AppLocker rule until the administrator explicitly applies it.
    $tabPrograms = New-Object System.Windows.Forms.TabPage
    $tabPrograms.Text = 'Programas'
    $tabPrograms.BackColor = $Bg
    $tabs.TabPages.Add($tabPrograms)

    $lstPrograms = New-Object System.Windows.Forms.ListBox
    $script:allowedProgramMap = @{}
    foreach ($stored in @($settings.allowedPrograms)) {
        if ($stored -and -not [string]::IsNullOrWhiteSpace([string]$stored)) {
            $script:allowedProgramMap[[string]$stored] = [string]$stored
        }
    }
    Add-ListItems $lstPrograms @($script:allowedProgramMap.Values)

    $programLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $programLayout.Dock = 'Fill'
    $programLayout.Padding = New-Object System.Windows.Forms.Padding(22,16,22,14)
    $programLayout.ColumnCount = 1
    $programLayout.RowCount = 5
    [void]$programLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',66)))
    [void]$programLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',74)))
    [void]$programLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',62)))
    [void]$programLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    [void]$programLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',50)))
    $tabPrograms.Controls.Add($programLayout)

    $programTitlePanel = New-Object System.Windows.Forms.Panel
    $programTitlePanel.Dock = 'Fill'
    $programTitlePanel.Controls.Add((New-Label 'Aplicaciones del aula' 0 0 17 $true $Text))
    $programTitlePanel.Controls.Add((New-Label 'Activa únicamente los programas que necesitan los estudiantes.' 0 35 9 $false $Muted))
    $programLayout.Controls.Add($programTitlePanel,0,0)

    $programNotice = New-Object System.Windows.Forms.Panel
    $programNotice.Dock = 'Fill'
    $programNotice.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    $programNotice.BackColor = $SoftGreen
    $programNotice.Padding = New-Object System.Windows.Forms.Padding(12)
    $programNotice.Controls.Add((New-Label 'Selección segura de aplicaciones' 14 8 10 $true $PrimaryDark))
    $programNotice.Controls.Add((New-Label 'Los interruptores preparan la lista. Windows no bloquea nada hasta que lo confirmas en Control de apps.' 14 34 9 $false $Text))
    $programLayout.Controls.Add($programNotice,0,1)

    $programToolbar = New-Object System.Windows.Forms.TableLayoutPanel
    $programToolbar.Dock = 'Fill'
    $programToolbar.ColumnCount = 4
    $programToolbar.RowCount = 1
    [void]$programToolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    [void]$programToolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',140)))
    [void]$programToolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',145)))
    [void]$programToolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',145)))
    $programLayout.Controls.Add($programToolbar,0,2)

    $txtProgramSearch = New-Object System.Windows.Forms.TextBox
    $txtProgramSearch.Dock = 'Fill'
    $txtProgramSearch.Margin = New-Object System.Windows.Forms.Padding(0,8,12,13)
    $txtProgramSearch.Font = New-Object System.Drawing.Font('Segoe UI',10)
    Style-Input $txtProgramSearch
    $programToolbar.Controls.Add($txtProgramSearch,0,0)
    $toolTip.SetToolTip($txtProgramSearch,'Buscar por nombre, editor o ruta del ejecutable')

    $cmbPrograms = New-Object System.Windows.Forms.ComboBox
    $cmbPrograms.DropDownStyle = 'DropDownList'
    $cmbPrograms.Dock = 'Fill'
    $cmbPrograms.Margin = New-Object System.Windows.Forms.Padding(0,8,10,13)
    [void]$cmbPrograms.Items.AddRange([object[]]@('Todas','Permitidas','Sin permitir','No compatibles'))
    $cmbPrograms.SelectedIndex = 0
    $programToolbar.Controls.Add($cmbPrograms,1,0)

    $btnAddProgram = New-Button 'Agregar EXE' 0 0 140 36 'Secondary'
    $btnAddProgram.Dock = 'Fill'
    $btnAddProgram.Margin = New-Object System.Windows.Forms.Padding(0,8,10,13)
    $programToolbar.Controls.Add($btnAddProgram,2,0)

    $btnRefreshPrograms = New-Button 'Detectar apps' 0 0 140 36 'Primary'
    $btnRefreshPrograms.Dock = 'Fill'
    $btnRefreshPrograms.Margin = New-Object System.Windows.Forms.Padding(0,8,0,13)
    $programToolbar.Controls.Add($btnRefreshPrograms,3,0)

    $gridPrograms = New-Object System.Windows.Forms.DataGridView
    $gridPrograms.Dock = 'Fill'
    $gridPrograms.Margin = New-Object System.Windows.Forms.Padding(0,8,0,6)
    Style-Grid $gridPrograms
    $gridPrograms.AllowUserToResizeRows = $false
    $gridPrograms.AllowUserToOrderColumns = $false
    $gridPrograms.RowTemplate.Height = 43
    $gridPrograms.ColumnHeadersHeight = 38
    $gridPrograms.AutoSizeRowsMode = 'None'
    $gridPrograms.AutoSizeColumnsMode = 'Fill'
    $gridPrograms.ShowCellToolTips = $true
    $gridPrograms.EditMode = 'EditProgrammatically'
    [void]$gridPrograms.Columns.Add('Toggle','Permitir')
    [void]$gridPrograms.Columns.Add('AppName','Aplicación')
    [void]$gridPrograms.Columns.Add('Publisher','Editor')
    [void]$gridPrograms.Columns.Add('AppKind','Tipo')
    [void]$gridPrograms.Columns.Add('ExePath','Ubicación / motivo')
    $gridPrograms.Columns['Toggle'].FillWeight = 75
    $gridPrograms.Columns['AppName'].FillWeight = 180
    $gridPrograms.Columns['Publisher'].FillWeight = 100
    $gridPrograms.Columns['AppKind'].FillWeight = 75
    $gridPrograms.Columns['ExePath'].FillWeight = 220
    $gridPrograms.Columns['Toggle'].SortMode = 'NotSortable'
    $programLayout.Controls.Add($gridPrograms,0,3)

    $programFooter = New-Object System.Windows.Forms.TableLayoutPanel
    $programFooter.Dock = 'Fill'
    $programFooter.ColumnCount = 2
    $programFooter.RowCount = 1
    [void]$programFooter.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    [void]$programFooter.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',188)))
    $programLayout.Controls.Add($programFooter,0,4)
    $lblProgramStats = New-Label 'Pulsa Detectar apps para consultar los programas de Windows.' 0 12 9 $false $Muted
    $lblProgramStats.Dock = 'Fill'
    $lblProgramStats.TextAlign = 'MiddleLeft'
    $programFooter.Controls.Add($lblProgramStats,0,0)
    $btnRemoveProgram = New-Button 'Quitar selección' 0 0 175 35 'Danger'
    $btnRemoveProgram.Dock = 'Fill'
    $btnRemoveProgram.Margin = New-Object System.Windows.Forms.Padding(0,5,0,3)
    $programFooter.Controls.Add($btnRemoveProgram,1,0)

    $script:programCatalog = @()
    $script:inventoryLoaded = $false
    $syncProgramSelection = {
        Add-ListItems $lstPrograms @($script:allowedProgramMap.Values | Sort-Object)
    }
    $renderPrograms = {
        $query = $txtProgramSearch.Text.Trim()
        $filter = [string]$cmbPrograms.SelectedItem
        $gridPrograms.Rows.Clear()
        foreach ($app in @($script:programCatalog)) {
            $allowed = ($app.ExecutablePath -and $script:allowedProgramMap.ContainsKey([string]$app.ExecutablePath))
            if ($query -and -not (
                ($app.Name.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                ($app.Publisher.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                ($app.ExecutablePath.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0)
            )) { continue }
            if ($filter -eq 'Permitidas' -and -not $allowed) { continue }
            if ($filter -eq 'Sin permitir' -and ($allowed -or -not $app.CanAllow)) { continue }
            if ($filter -eq 'No compatibles' -and $app.CanAllow) { continue }
            $toggleText = if (-not $app.CanAllow) { 'N/D' } elseif ($allowed) { 'ON' } else { 'OFF' }
            $position = $gridPrograms.Rows.Add($toggleText,[string]$app.Name,[string]$app.Publisher,
                [string]$app.Type, $(if ($app.ExecutablePath) {$app.ExecutablePath} else {$app.Reason}))
            $row = $gridPrograms.Rows[$position]
            $row.Tag = $app
            if (-not $app.CanAllow) {
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(135,148,165)
            }
        }
        $allowedCount = @($script:allowedProgramMap.Keys).Count
        $lblProgramStats.Text = "Detectadas: $(@($script:programCatalog).Count)   ·   Permitidas: $allowedCount   ·   Mostradas: $($gridPrograms.Rows.Count)"
    }
    $loadPrograms = {
        try {
            Set-Status 'Detectando programas de Windows...' 'Warning'
            $tabPrograms.UseWaitCursor = $true
            $catalog = @(Get-AulaGuardInstalledApplications)
            foreach ($path in @($script:allowedProgramMap.Values)) {
                if (@($catalog | Where-Object { $_.ExecutablePath -eq $path }).Count -eq 0) {
                    $catalog += (New-Object psobject -Property @{
                        Name=[IO.Path]::GetFileNameWithoutExtension($path)
                        Publisher='Agregado manualmente'
                        Version=''
                        Type='Win32'
                        ExecutablePath=[string]$path
                        CanAllow=(Test-Path -LiteralPath $path -PathType Leaf)
                        Reason='Ejecutable ya no disponible o movido.'
                        Source='Manual'
                    })
                }
            }
            $script:programCatalog = @($catalog | Sort-Object Name)
            $script:inventoryLoaded = $true
            & $renderPrograms
            Set-Status "Inventario actualizado: $($script:programCatalog.Count) aplicaciones" 'Success'
        } catch {
            Set-Status 'No se pudo consultar el inventario de aplicaciones' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · Detección','OK','Error') | Out-Null
        } finally { $tabPrograms.UseWaitCursor = $false }
    }
    $gridPrograms.Add_CellPainting({
        param($sender,$e)
        if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 0) { return }
        $e.PaintBackground($e.CellBounds,$true)
        $state = [string]$e.Value
        $x = $e.CellBounds.X + [Math]::Max(8,[int](($e.CellBounds.Width - 66)/2))
        $y = $e.CellBounds.Y + [int](($e.CellBounds.Height - 28)/2)
        $color = if ($state -eq 'ON') { $Primary } elseif ($state -eq 'OFF') {
            [System.Drawing.Color]::FromArgb(148,163,184)
        } else { [System.Drawing.Color]::FromArgb(226,232,240) }
        $brush = New-Object System.Drawing.SolidBrush($color)
        $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        try {
            $e.Graphics.FillRectangle($brush,$x+14,$y,38,28)
            $e.Graphics.FillEllipse($brush,$x,$y,28,28)
            $e.Graphics.FillEllipse($brush,$x+38,$y,28,28)
            if ($state -eq 'ON') {
                $e.Graphics.FillEllipse($white,$x+40,$y+4,20,20)
            } elseif ($state -eq 'OFF') {
                $e.Graphics.FillEllipse($white,$x+6,$y+4,20,20)
            } else {
                [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics,'—',
                    (New-Object System.Drawing.Font('Segoe UI',12)),([System.Drawing.Rectangle]::new($x+20,$y,26,28)),$Muted)
            }
        } finally { $brush.Dispose(); $white.Dispose() }
        $e.Handled = $true
    })

    # APP CONTROL — all panels docked to a responsive grid rather than absolute sizes.
    $tabAppControl = New-Object System.Windows.Forms.TabPage
    $tabAppControl.Text = 'Control de apps'
    $tabAppControl.BackColor = $Bg
    $tabs.TabPages.Add($tabAppControl)
    $appLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $appLayout.Dock = 'Fill'
    $appLayout.Padding = New-Object System.Windows.Forms.Padding(22,16,22,14)
    $appLayout.ColumnCount = 1
    $appLayout.RowCount = 5
    [void]$appLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',66)))
    [void]$appLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',76)))
    [void]$appLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',128)))
    [void]$appLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',65)))
    [void]$appLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $tabAppControl.Controls.Add($appLayout)
    $appHeader = New-Object System.Windows.Forms.Panel
    $appHeader.Dock = 'Fill'
    $appHeader.Controls.Add((New-Label 'Control de aplicaciones' 0 0 17 $true $Text))
    $appHeader.Controls.Add((New-Label 'Paso 1: elegir programas. Paso 2: auditar. Paso 3: activar bloqueo si todo funciona.' 0 34 9 $false $Muted))
    $appLayout.Controls.Add($appHeader,0,0)

    $appSupport = Test-AulaGuardAppLockerSupport
    $supportCard = New-Object System.Windows.Forms.Panel
    $supportCard.Dock = 'Fill'
    $supportCard.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    $supportCard.BackColor = if ($appSupport.Supported) {$SoftGreen} else {$SoftAmber}
    $supportText = if ($appSupport.Supported) {"AppLocker disponible · Servicio: $($appSupport.ServiceStatus)"} else {'AppLocker no está disponible en este equipo'}
    $supportColor = if ($appSupport.Supported) {$Success} else {$Danger}
    $supportCard.Controls.Add((New-Label $supportText 15 10 10 $true $supportColor))
    $supportCard.Controls.Add((New-Label 'La lista permitida no bloquea nada hasta aplicar expresamente una política.' 15 38 9 $false $Muted))
    $appLayout.Controls.Add($supportCard,0,1)

    $appModeLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $appModeLayout.Dock = 'Fill'
    $appModeLayout.ColumnCount = 2
    $appModeLayout.RowCount = 1
    [void]$appModeLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',50)))
    [void]$appModeLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',50)))
    $appLayout.Controls.Add($appModeLayout,0,2)

    $auditCard = New-Object System.Windows.Forms.Panel
    $auditCard.Dock = 'Fill'
    $auditCard.Margin = New-Object System.Windows.Forms.Padding(0,0,9,10)
    $auditCard.BackColor = $SoftGreen
    $radAppAudit = New-Object System.Windows.Forms.RadioButton
    $radAppAudit.Text = 'Auditoría · recomendado'
    $radAppAudit.Location = New-Object System.Drawing.Point(16,17)
    $radAppAudit.AutoSize = $true
    $radAppAudit.Font = New-Object System.Drawing.Font('Segoe UI Semibold',10)
    $auditCard.Controls.Add($radAppAudit)
    $auditCard.Controls.Add((New-Label 'Observa eventos sin bloquear las herramientas del aula.' 18 56 9 $false $Muted))
    $appModeLayout.Controls.Add($auditCard,0,0)

    $blockCard = New-Object System.Windows.Forms.Panel
    $blockCard.Dock = 'Fill'
    $blockCard.Margin = New-Object System.Windows.Forms.Padding(9,0,0,10)
    $blockCard.BackColor = $SoftAmber
    $radAppEnforce = New-Object System.Windows.Forms.RadioButton
    $radAppEnforce.Text = 'Bloqueo activo · avanzado'
    $radAppEnforce.Location = New-Object System.Drawing.Point(16,17)
    $radAppEnforce.AutoSize = $true
    $radAppEnforce.Font = New-Object System.Drawing.Font('Segoe UI Semibold',10)
    $blockCard.Controls.Add($radAppEnforce)
    $blockCard.Controls.Add((New-Label 'Úsalo únicamente después de verificar la auditoría.' 18 56 9 $false $Warning))
    $appModeLayout.Controls.Add($blockCard,1,0)
    if ($settings.appControl.mode -eq 'Enabled') {$radAppEnforce.Checked = $true} else {$radAppAudit.Checked = $true}

    $appToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
    $appToolbar.Dock = 'Fill'
    $appToolbar.FlowDirection = 'LeftToRight'
    $appToolbar.WrapContents = $true
    $appLayout.Controls.Add($appToolbar,0,3)
    $btnAppPreview = New-Button 'Validar lista' 0 0 145 36 'Secondary'
    $btnAppApply = New-Button 'Aplicar control' 0 0 146 36 'Primary'
    $btnAppRestore = New-Button 'Restaurar anterior' 0 0 157 36 'Neutral'
    $btnAppRefresh = New-Button 'Actualizar registro' 0 0 158 36 'Neutral'
    foreach ($btn in @($btnAppPreview,$btnAppApply,$btnAppRestore,$btnAppRefresh)) {
        $btn.Margin = New-Object System.Windows.Forms.Padding(0,5,10,4)
        $appToolbar.Controls.Add($btn)
    }
    $gridAppEvents = New-Object System.Windows.Forms.DataGridView
    $gridAppEvents.Dock = 'Fill'
    $gridAppEvents.Margin = New-Object System.Windows.Forms.Padding(0,5,0,0)
    Style-Grid $gridAppEvents
    [void]$gridAppEvents.Columns.Add('Time','Fecha y hora')
    [void]$gridAppEvents.Columns.Add('Id','Evento')
    [void]$gridAppEvents.Columns.Add('File','Programa')
    [void]$gridAppEvents.Columns.Add('Message','Descripción del evento')
    $gridAppEvents.Columns['Message'].FillWeight = 220
    $appLayout.Controls.Add($gridAppEvents,0,4)

    # INTERNET — responsive allow-list workspace.
    $tabWeb = New-Object System.Windows.Forms.TabPage
    $tabWeb.Text = 'Internet'
    $tabWeb.BackColor = $Bg
    $tabs.TabPages.Add($tabWeb)

    $webLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $webLayout.Dock = 'Fill'
    $webLayout.Padding = New-Object System.Windows.Forms.Padding(24,18,24,18)
    $webLayout.ColumnCount = 1
    $webLayout.RowCount = 4
    [void]$webLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',68)))
    [void]$webLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',72)))
    [void]$webLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',58)))
    [void]$webLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $tabWeb.Controls.Add($webLayout)

    $webHeader = New-Object System.Windows.Forms.Panel
    $webHeader.Dock = 'Fill'
    $webHeader.Controls.Add((New-Label 'Internet permitido' 0 0 17 $true $Text))
    $webHeader.Controls.Add((New-Label 'Define los sitios necesarios para la clase cuando uses la lista blanca del navegador.' 0 35 9 $false $Muted))
    $webLayout.Controls.Add($webHeader,0,0)

    $webNotice = New-Surface -BackColor $SoftAmber -Padding 0
    $webNotice.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    $webNotice.Controls.Add((New-Label 'Lista blanca del navegador' 15 10 10 $true $Warning))
    $webNotice.Controls.Add((New-Label 'Si la activas en Protección, Edge y Chrome permitirán únicamente los dominios definidos aquí.' 15 36 9 $false $Text))
    $webLayout.Controls.Add($webNotice,0,1)

    $webAdd = New-Object System.Windows.Forms.TableLayoutPanel
    $webAdd.Dock = 'Fill'
    $webAdd.ColumnCount = 2
    $webAdd.RowCount = 1
    [void]$webAdd.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    [void]$webAdd.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',165)))
    $webLayout.Controls.Add($webAdd,0,2)

    $txtWebsite = New-Object System.Windows.Forms.TextBox
    $txtWebsite.Dock = 'Fill'
    $txtWebsite.Margin = New-Object System.Windows.Forms.Padding(0,6,12,10)
    Style-Input $txtWebsite
    $webAdd.Controls.Add($txtWebsite,0,0)
    $toolTip.SetToolTip($txtWebsite,'Ejemplo: classroom.google.com o *.example.edu')

    $btnAddWebsite = New-Button 'Agregar sitio' 0 0 150 36 'Primary'
    $btnAddWebsite.Dock = 'Fill'
    $btnAddWebsite.Margin = New-Object System.Windows.Forms.Padding(0,5,0,10)
    $webAdd.Controls.Add($btnAddWebsite,1,0)

    $webContent = New-Object System.Windows.Forms.TableLayoutPanel
    $webContent.Dock = 'Fill'
    $webContent.ColumnCount = 2
    $webContent.RowCount = 1
    [void]$webContent.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    [void]$webContent.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',190)))
    $webLayout.Controls.Add($webContent,0,3)

    $webListSurface = New-Surface -BackColor $Card -Padding 12
    $webListSurface.Margin = New-Object System.Windows.Forms.Padding(0,0,12,0)
    $lstWebsites = New-Object System.Windows.Forms.ListBox
    $lstWebsites.Dock = 'Fill'
    $lstWebsites.BorderStyle = 'None'
    $lstWebsites.Font = New-Object System.Drawing.Font('Segoe UI',10)
    $lstWebsites.BackColor = $Card
    $webListSurface.Controls.Add($lstWebsites)
    Add-ListItems $lstWebsites @($settings.allowedWebsites)
    $webContent.Controls.Add($webListSurface,0,0)

    $webActions = New-Object System.Windows.Forms.FlowLayoutPanel
    $webActions.Dock = 'Fill'
    $webActions.FlowDirection = 'TopDown'
    $webActions.WrapContents = $false
    $webContent.Controls.Add($webActions,1,0)
    $btnRemoveWebsite = New-Button 'Quitar seleccionado' 0 0 178 38 'Danger'
    $btnRemoveWebsite.Margin = New-Object System.Windows.Forms.Padding(0,0,0,8)
    $webActions.Controls.Add($btnRemoveWebsite)

    # DESKTOP — responsive shortcuts workspace.
    $tabDesktop = New-Object System.Windows.Forms.TabPage
    $tabDesktop.Text = 'Escritorio'
    $tabDesktop.BackColor = $Bg
    $tabs.TabPages.Add($tabDesktop)

    $desktopLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $desktopLayout.Dock = 'Fill'
    $desktopLayout.Padding = New-Object System.Windows.Forms.Padding(24,18,24,18)
    $desktopLayout.ColumnCount = 1
    $desktopLayout.RowCount = 3
    [void]$desktopLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',68)))
    [void]$desktopLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',72)))
    [void]$desktopLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $tabDesktop.Controls.Add($desktopLayout)

    $desktopHeader = New-Object System.Windows.Forms.Panel
    $desktopHeader.Dock = 'Fill'
    $desktopHeader.Controls.Add((New-Label 'Accesos del aula' 0 0 17 $true $Text))
    $desktopHeader.Controls.Add((New-Label 'Conserva únicamente los accesos directos que deben permanecer disponibles para estudiantes.' 0 35 9 $false $Muted))
    $desktopLayout.Controls.Add($desktopHeader,0,0)

    $desktopNotice = New-Surface -BackColor $SoftGreen -Padding 0
    $desktopNotice.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    $desktopNotice.Controls.Add((New-Label 'Escritorio administrado' 15 10 10 $true $PrimaryDark))
    $desktopNotice.Controls.Add((New-Label 'La protección se aplica al escritorio público; las cuentas administradoras siguen excluidas.' 15 36 9 $false $Text))
    $desktopLayout.Controls.Add($desktopNotice,0,1)

    $desktopContent = New-Object System.Windows.Forms.TableLayoutPanel
    $desktopContent.Dock = 'Fill'
    $desktopContent.ColumnCount = 2
    $desktopContent.RowCount = 1
    [void]$desktopContent.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    [void]$desktopContent.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',190)))
    $desktopLayout.Controls.Add($desktopContent,0,2)

    $desktopListSurface = New-Surface -BackColor $Card -Padding 12
    $desktopListSurface.Margin = New-Object System.Windows.Forms.Padding(0,0,12,0)
    $lstShortcuts = New-Object System.Windows.Forms.ListBox
    $lstShortcuts.Dock = 'Fill'
    $lstShortcuts.BorderStyle = 'None'
    $lstShortcuts.Font = New-Object System.Drawing.Font('Segoe UI',10)
    $desktopListSurface.Controls.Add($lstShortcuts)
    Add-ListItems $lstShortcuts @($settings.protectedShortcuts)
    $desktopContent.Controls.Add($desktopListSurface,0,0)

    $desktopActions = New-Object System.Windows.Forms.FlowLayoutPanel
    $desktopActions.Dock = 'Fill'
    $desktopActions.FlowDirection = 'TopDown'
    $desktopActions.WrapContents = $false
    $desktopContent.Controls.Add($desktopActions,1,0)
    $btnAddShortcut = New-Button 'Agregar acceso' 0 0 178 38 'Primary'
    $btnRemoveShortcut = New-Button 'Quitar seleccionado' 0 0 178 38 'Danger'
    $btnAddShortcut.Margin = New-Object System.Windows.Forms.Padding(0,0,0,8)
    $desktopActions.Controls.Add($btnAddShortcut)
    $desktopActions.Controls.Add($btnRemoveShortcut)

    # USB REMOVABLE STORAGE CONTROL — per-user, never the entire USB controller.
    $tabUsb = New-Object System.Windows.Forms.TabPage
    $tabUsb.Text = 'Memorias USB'
    $tabUsb.BackColor = $Bg
    $tabs.TabPages.Add($tabUsb)

    $usbView = New-Object System.Windows.Forms.TableLayoutPanel
    $usbView.Dock = 'Fill'
    $usbView.Padding = New-Object System.Windows.Forms.Padding(24,18,24,18)
    $usbView.ColumnCount = 1
    $usbView.RowCount = 4
    [void]$usbView.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',70)))
    [void]$usbView.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',184)))
    [void]$usbView.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',70)))
    [void]$usbView.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $tabUsb.Controls.Add($usbView)

    $usbTitle = New-Object System.Windows.Forms.Panel
    $usbTitle.Dock = 'Fill'
    $usbTitle.Controls.Add((New-Label 'Control de memorias USB' 0 0 16 $true $Text))
    $usbTitle.Controls.Add((New-Label 'Restringe lectura y escritura de discos extraíbles SOLO a las cuentas estándar.' 0 32 9 $false $Muted))
    $usbView.Controls.Add($usbTitle,0,0)

    $usbCard = New-Object System.Windows.Forms.Panel
    $usbCard.Dock = 'Fill'
    $usbCard.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    $usbCard.Padding = New-Object System.Windows.Forms.Padding(16)
    $usbCard.BackColor = [System.Drawing.Color]::White
    $usbCard.BorderStyle = 'FixedSingle'
    $usbView.Controls.Add($usbCard,0,1)
    $usbCard.Controls.Add((New-Label 'Permitir / restringir memorias externas' 18 16 12 $true $Text))
    $usbCard.Controls.Add((New-Label 'Bloquear el acceso a discos USB extraíbles para estudiantes' 18 50 10 $false $Text))
    $toggleUsb = New-Object System.Windows.Forms.CheckBox
    $toggleUsb.Appearance = 'Button'
    $toggleUsb.FlatStyle = 'Flat'
    $toggleUsb.FlatAppearance.BorderSize = 0
    $toggleUsb.Size = New-Object System.Drawing.Size(120,38)
    $toggleUsb.Location = New-Object System.Drawing.Point(18,82)
    $toggleUsb.Font = New-Object System.Drawing.Font('Segoe UI Semibold',10)
    $toggleUsb.TextAlign = 'MiddleCenter'
    $toggleUsb.Cursor = 'Hand'
    $toggleUsb.Checked = [bool]$settings.usb.blockStorage
    $usbCard.Controls.Add($toggleUsb)
    $updateUsbVisual = {
        if ($toggleUsb.Checked) {
            $toggleUsb.Text = 'BLOQUEAR USB'
            $toggleUsb.BackColor = $Danger
            $toggleUsb.ForeColor = [System.Drawing.Color]::White
            $usbCard.BackColor = $SoftRed
        } else {
            $toggleUsb.Text = 'PERMITIR USB'
            $toggleUsb.BackColor = $SoftGreen
            $toggleUsb.ForeColor = $PrimaryDark
            $usbCard.BackColor = [System.Drawing.Color]::White
        }
    }
    $toggleUsb.Add_CheckedChanged({ & $updateUsbVisual })
    & $updateUsbVisual
    $usbHint = New-Label 'Este ajuste afecta solo almacenamiento extraíble de estudiantes. Guarda y aplica Protección para hacerlo efectivo.' 158 92 9 $false $Muted
    $usbHint.MaximumSize = New-Object System.Drawing.Size(680,0)
    $usbCard.Controls.Add($usbHint)

    $usbActions = New-Object System.Windows.Forms.FlowLayoutPanel
    $usbActions.Dock = 'Fill'
    $usbActions.FlowDirection = 'LeftToRight'
    $usbActions.WrapContents = $true
    $usbActions.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    $usbView.Controls.Add($usbActions,0,2)
    $btnUsbRestore = New-Button 'Restaurar acceso USB' 0 0 188 40 'Secondary'
    $btnUsbRefresh = New-Button 'Actualizar dispositivos' 0 0 190 40 'Primary'
    $usbActions.Controls.Add($btnUsbRestore)
    $usbActions.Controls.Add($btnUsbRefresh)

    $usbListCard = New-Object System.Windows.Forms.Panel
    $usbListCard.Dock = 'Fill'
    $usbListCard.BackColor = [System.Drawing.Color]::White
    $usbListCard.BorderStyle = 'FixedSingle'
    $usbListCard.Padding = New-Object System.Windows.Forms.Padding(12,42,12,12)
    $usbView.Controls.Add($usbListCard,0,3)
    $usbListCard.Controls.Add((New-Label 'Unidades extraíbles detectadas en este equipo' 16 12 11 $true $Text))
    $usbGrid = New-Object System.Windows.Forms.ListView
    $usbGrid.Dock = 'Fill'
    $usbGrid.View = 'Details'
    $usbGrid.FullRowSelect = $true
    $usbGrid.GridLines = $false
    $usbGrid.HeaderStyle = 'Nonclickable'
    [void]$usbGrid.Columns.Add('Unidad',90)
    [void]$usbGrid.Columns.Add('Etiqueta',260)
    [void]$usbGrid.Columns.Add('Sistema de archivos',180)
    $usbListCard.Controls.Add($usbGrid)
    $usbGrid.BringToFront()
    $refreshUsb = {
        $usbGrid.Items.Clear()
        foreach ($device in @(Get-AulaGuardRemovableDrives)) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$device.Letter)
            [void]$item.SubItems.Add([string]$device.Name)
            [void]$item.SubItems.Add([string]$device.FileSystem)
            [void]$usbGrid.Items.Add($item)
        }
    }

    # PREMIUM / CENTRAL SERVER — informational only, no invented live connectivity.
    $tabPremium = New-Object System.Windows.Forms.TabPage
    $tabPremium.Text = 'Servidor Premium'
    $tabPremium.BackColor = $Bg
    $tabs.TabPages.Add($tabPremium)
    $premiumPage = New-Object System.Windows.Forms.TableLayoutPanel
    $premiumPage.Dock = 'Fill'
    $premiumPage.Padding = New-Object System.Windows.Forms.Padding(24,18,24,18)
    $premiumPage.ColumnCount = 1
    $premiumPage.RowCount = 3
    [void]$premiumPage.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',86)))
    [void]$premiumPage.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',200)))
    [void]$premiumPage.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $tabPremium.Controls.Add($premiumPage)

    $premiumHeader = New-Object System.Windows.Forms.Panel
    $premiumHeader.Dock = 'Fill'
    $premiumHeader.Controls.Add((New-Label 'Servidor de monitoreo · Premium' 0 0 16 $true $Text))
    $premiumHeader.Controls.Add((New-Label 'Preparamos AulaGuard para administrar varios equipos desde una PC central.' 0 35 9 $false $Muted))
    $premiumPage.Controls.Add($premiumHeader,0,0)
    $premiumInfo = New-Object System.Windows.Forms.Panel
    $premiumInfo.Dock = 'Fill'
    $premiumInfo.Margin = New-Object System.Windows.Forms.Padding(0,0,0,14)
    $premiumInfo.BackColor = $SoftGreen
    $premiumPage.Controls.Add($premiumInfo,0,1)
    $premiumInfo.Controls.Add((New-Label 'ESTADO ACTUAL · VERSIÓN LOCAL' 18 16 10 $true $PrimaryDark))
    $premiumInfo.Controls.Add((New-Label 'Sin conexión a servidores. No se envían datos de alumnos ni del equipo.' 18 55 11 $true $Text))
    $premiumInfo.Controls.Add((New-Label 'El enlace con un servidor Premium todavía no está disponible.' 18 90 9 $false $Muted))
    $premiumInfo.Controls.Add((New-Label 'En una versión futura habrá inscripción segura, estado online/offline y políticas centralizadas.' 18 116 9 $false $Muted))
    $premiumInfo.Controls.Add((New-Label 'No se solicitan claves o contraseñas hasta disponer de un servicio verificado.' 18 142 9 $false $Muted))
    $premiumCapabilities = New-Object System.Windows.Forms.TextBox
    $premiumCapabilities.Multiline = $true
    $premiumCapabilities.ReadOnly = $true
    $premiumCapabilities.Dock = 'Fill'
    $premiumCapabilities.ScrollBars = 'Vertical'
    $premiumCapabilities.Font = New-Object System.Drawing.Font('Segoe UI',10)
    $premiumCapabilities.BackColor = [System.Drawing.Color]::White
    $premiumCapabilities.Text = "Funcionalidades previstas para Premium:$([Environment]::NewLine)$([Environment]::NewLine)• Panel central de laboratorios, equipos y estado de conexión.$([Environment]::NewLine)• Alertas de acciones bloqueadas y dispositivos de almacenamiento.$([Environment]::NewLine)• Asignación de políticas por aula y por grupo de computadoras.$([Environment]::NewLine)• Historial de auditoría con permisos y retención configurables.$([Environment]::NewLine)• Comunicación cifrada TLS y registro de dispositivos autorizado.$([Environment]::NewLine)$([Environment]::NewLine)Esta pantalla es informativa: las conexiones remotas no están implementadas."
    $premiumPage.Controls.Add($premiumCapabilities,0,2)

    # LOG — responsive technical activity view.
    $tabAudit = New-Object System.Windows.Forms.TabPage
    $tabAudit.Text = 'Registro'
    $tabAudit.BackColor = $Bg
    $tabs.TabPages.Add($tabAudit)

    $auditLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $auditLayout.Dock = 'Fill'
    $auditLayout.Padding = New-Object System.Windows.Forms.Padding(24,18,24,18)
    $auditLayout.ColumnCount = 1
    $auditLayout.RowCount = 4
    [void]$auditLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',68)))
    [void]$auditLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',68)))
    [void]$auditLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    [void]$auditLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',52)))
    $tabAudit.Controls.Add($auditLayout)

    $auditHeader = New-Object System.Windows.Forms.Panel
    $auditHeader.Dock = 'Fill'
    $auditHeader.Controls.Add((New-Label 'Actividad y auditoría' 0 0 17 $true $Text))
    $auditHeader.Controls.Add((New-Label 'Revisa cambios administrativos, aplicaciones de políticas, errores e integridad de registros.' 0 35 9 $false $Muted))
    $auditLayout.Controls.Add($auditHeader,0,0)

    $auditNotice = New-Surface -BackColor $SlateSoft -Padding 0
    $auditNotice.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
    $auditNotice.Controls.Add((New-Label 'Registro protegido' 15 10 10 $true $Text))
    $auditNotice.Controls.Add((New-Label 'AulaGuard valida la cadena HMAC antes de mostrar cada archivo de auditoría.' 15 36 9 $false $Muted))
    $auditLayout.Controls.Add($auditNotice,0,1)

    $auditSurface = New-Surface -BackColor $Card -Padding 12
    $auditSurface.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
    $txtAudit = New-Object System.Windows.Forms.TextBox
    $txtAudit.Dock = 'Fill'
    $txtAudit.Multiline = $true
    $txtAudit.ReadOnly = $true
    $txtAudit.ScrollBars = 'Both'
    $txtAudit.Font = New-Object System.Drawing.Font('Consolas',9)
    $txtAudit.BackColor = [System.Drawing.Color]::White
    $txtAudit.ForeColor = $Text
    $txtAudit.BorderStyle = 'None'
    $auditSurface.Controls.Add($txtAudit)
    $auditLayout.Controls.Add($auditSurface,0,2)

    $auditActions = New-Object System.Windows.Forms.FlowLayoutPanel
    $auditActions.Dock = 'Fill'
    $auditActions.FlowDirection = 'LeftToRight'
    $auditActions.WrapContents = $false
    $btnRefreshAudit = New-Button 'Actualizar registro' 0 0 165 36 'Secondary'
    $btnRefreshAudit.Margin = New-Object System.Windows.Forms.Padding(0,5,10,4)
    $auditActions.Controls.Add($btnRefreshAudit)
    $auditLayout.Controls.Add($auditActions,0,3)

    $loadAudit = {
        $lines = @()
        $files = Get-ChildItem (Join-Path $root 'logs') -Filter 'secure-audit-*.jsonl' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 5

        foreach ($file in ($files | Sort-Object Name)) {
            $result = Test-AulaGuardAuditLog -Path $file.FullName -Root $root
            if (-not $result.Valid) {
                $lines += "[ALERTA DE INTEGRIDAD] $($file.Name): $($result.Detail)"
                continue
            }
            $lines += "[INTEGRIDAD VERIFICADA] $($file.Name) - $($result.Count) entradas"
            foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
                try {
                    $e = $line | ConvertFrom-Json -ErrorAction Stop
                    $lines += ('{0} [{1}] {2} {3}' -f $e.timestamp,$e.level,$e.action,$e.detail)
                } catch {
                    $lines += '[ALERTA] No se pudo interpretar una entrada.'
                }
            }
        }

        $legacyFiles = @(Get-ChildItem (Join-Path $root 'logs') -Filter 'audit-*.jsonl' -ErrorAction SilentlyContinue)
        if ($legacyFiles.Count -gt 0) {
            $lines += '[HISTÓRICO] Existen registros anteriores sin autenticación criptográfica.'
        }
        $txtAudit.Text = ($lines -join [Environment]::NewLine)
        $txtAudit.SelectionStart = $txtAudit.TextLength
        $txtAudit.ScrollToCaret()
    }

    $loadAppEvents = {
        $gridAppEvents.Rows.Clear()
        foreach ($e in @(Get-AulaGuardAppLockerEvents -MaxEvents 100)) {
            $detail = [string]$e.Message
            if ($detail.Length -gt 180) {
                $detail = $detail.Substring(0,180) + '...'
            }
            [void]$gridAppEvents.Rows.Add(
                $(if ($e.TimeCreated) {$e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')} else {''}),
                $e.EventId,
                $(if ($e.File) {$e.File} else {''}),
                $detail
            )
        }
    }

    function Refresh-Dashboard {
        try {
            $info = Get-AulaGuardSystemInfo
            $lblPcValue.Text = $info.ComputerName
            $lblWindowsValue.Text = "$($info.Windows) · build $($info.Build)"
        } catch {
            $lblPcValue.Text = $env:COMPUTERNAME
            $lblWindowsValue.Text = 'No se pudo consultar Windows'
            Set-Status 'Hay información del sistema que requiere revisión' 'Warning'
        }

        $gridUsers.Rows.Clear()
        try {
            $users = @(Get-AulaGuardLocalUsers)
            $standard = @($users | Where-Object {-not $_.IsAdministrator})
            $lblUsersValue.Text = "$($standard.Count) estudiante(s)"
            foreach ($u in $users) {
                [void]$gridUsers.Rows.Add(
                    $u.User,
                    $(if ($u.IsAdministrator) {'Administrador'} else {'Estudiante / estándar'}),
                    $(if ($u.Loaded) {'Sesión iniciada'} else {'Sin sesión'}),
                    $u.SID
                )
            }
        } catch {
            $lblUsersValue.Text = 'Requiere atención'
            [void]$gridUsers.Rows.Add('No disponible','Diagnóstico','No se pudieron enumerar los perfiles', $_.Exception.Message)
            Set-Status 'No se pudieron validar los usuarios; revisa Estado del sistema' 'Warning'
        }

        $lblModeValue.Text = if ($radEnforce.Checked) {'Activa'} else {'Auditoría'}
        $lblAppsValue.Text = [string]$lstPrograms.Items.Count
        $lblQuickAudit.Text = if ($radEnforce.Checked) {'Revisa auditoría antes de mantener bloqueo'} else {'Recomendado: Auditoría'}
        $lblQuickAudit.ForeColor = if ($radEnforce.Checked) {$Warning} else {$Success}
    }

    $btnGoProtect.Add_Click({$tabs.SelectedTab = $tabProtection})
    $btnGoApps.Add_Click({$tabs.SelectedTab = $tabPrograms})

    $navHome.Add_Click({$tabs.SelectedTab = $tabHome})
    $btnGoHealth.Add_Click({$tabs.SelectedTab = $tabHealth})
    $navHealth.Add_Click({$tabs.SelectedTab = $tabHealth})
    $navProtection.Add_Click({$tabs.SelectedTab = $tabProtection})
    $navPrograms.Add_Click({$tabs.SelectedTab = $tabPrograms})
    $navAppControl.Add_Click({$tabs.SelectedTab = $tabAppControl})
    $navInternet.Add_Click({$tabs.SelectedTab = $tabWeb})
    $navDesktop.Add_Click({$tabs.SelectedTab = $tabDesktop})
    $navUsb.Add_Click({$tabs.SelectedTab = $tabUsb})
    $navPremium.Add_Click({$tabs.SelectedTab = $tabPremium})
    $navLog.Add_Click({$tabs.SelectedTab = $tabAudit})

    $tabs.Add_SelectedIndexChanged({
        if ($tabs.SelectedTab -eq $tabHome) {Set-NavActive $navHome}
        elseif ($tabs.SelectedTab -eq $tabHealth) { Set-NavActive $navHealth; & $loadReadiness | Out-Null }
        elseif ($tabs.SelectedTab -eq $tabProtection) {Set-NavActive $navProtection}
        elseif ($tabs.SelectedTab -eq $tabPrograms) {
            Set-NavActive $navPrograms
            if (-not $script:inventoryLoaded) { & $loadPrograms }
        }
        elseif ($tabs.SelectedTab -eq $tabAppControl) {Set-NavActive $navAppControl}
        elseif ($tabs.SelectedTab -eq $tabWeb) {Set-NavActive $navInternet}
        elseif ($tabs.SelectedTab -eq $tabDesktop) {Set-NavActive $navDesktop}
        elseif ($tabs.SelectedTab -eq $tabUsb) {Set-NavActive $navUsb}
        elseif ($tabs.SelectedTab -eq $tabPremium) {Set-NavActive $navPremium}
        elseif ($tabs.SelectedTab -eq $tabAudit) {Set-NavActive $navLog}
    })

    $btnHealthRefresh.Add_Click({ & $loadReadiness | Out-Null })
    $btnMaintenanceStart.Add_Click({
        try {
            if ([System.Windows.Forms.MessageBox]::Show(
                'AulaGuard suspenderá temporalmente sus restricciones durante 30 minutos. Al vencer el tiempo, intentará restaurarlas automáticamente. ¿Continuar?',
                'AulaGuard · Modo mantenimiento','YesNo','Warning'
            ) -ne 'Yes') { return }

            Save-FromUi
            Start-AulaGuardMaintenanceMode -DurationMinutes 30 -Root $root | Out-Null
            $settings = Read-AulaGuardSettings -Root $root
            $script:settings = $settings
            $radAudit.Checked = $true
            $radAppAudit.Checked = $true
            Set-Status 'Modo mantenimiento activo durante 30 minutos' 'Warning'
            & $loadReadiness | Out-Null
        } catch {
            Write-AulaGuardAudit -Action 'MAINTENANCE_START_ERROR' -Level 'ERROR' -Detail $_.Exception.Message -Root $root
            Set-Status 'No se pudo iniciar el modo mantenimiento' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · Mantenimiento','OK','Error') | Out-Null
        }
    })
    $btnMaintenanceStop.Add_Click({
        try {
            Stop-AulaGuardMaintenanceMode -Reason 'Manual' -Root $root | Out-Null
            $settings = Read-AulaGuardSettings -Root $root
            $script:settings = $settings
            $radEnforce.Checked = ($settings.policyMode -eq 'Enforce')
            $radAudit.Checked = -not $radEnforce.Checked
            $radAppEnforce.Checked = ($settings.appControl.mode -eq 'Enabled')
            $radAppAudit.Checked = -not $radAppEnforce.Checked
            Set-Status 'Modo mantenimiento finalizado y protección restaurada' 'Success'
            & $loadReadiness | Out-Null
        } catch {
            Write-AulaGuardAudit -Action 'MAINTENANCE_STOP_ERROR' -Level 'ERROR' -Detail $_.Exception.Message -Root $root
            Set-Status 'No se pudo finalizar el mantenimiento' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · Mantenimiento','OK','Error') | Out-Null
        }
    })
    $btnHealthExport.Add_Click({
        try {
            $d = New-Object System.Windows.Forms.SaveFileDialog
            $d.Filter = 'Diagnóstico AulaGuard (*.json)|*.json'
            $d.FileName = "AulaGuard-diagnostico-$($env:COMPUTERNAME)-$(Get-Date -Format 'yyyyMMdd-HHmm').json"
            if ($d.ShowDialog() -ne 'OK') { return }
            $candidateSettings = Get-UiSettings
            $saved = Export-AulaGuardDiagnosticReport -Path $d.FileName -Root $root -Settings $candidateSettings
            Set-Status 'Diagnóstico exportado' 'Success'
            [System.Windows.Forms.MessageBox]::Show("Diagnóstico guardado en:$([Environment]::NewLine)$saved",'AulaGuard · Diagnóstico','OK','Information') | Out-Null
        } catch {
            Set-Status 'No se pudo exportar el diagnóstico' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · Diagnóstico','OK','Error') | Out-Null
        }
    })


    $btnWallpaper.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = 'Imágenes|*.jpg;*.jpeg;*.png;*.bmp'
        if ($d.ShowDialog() -eq 'OK') {
            $txtWallpaper.Text = $d.FileName
            Write-AulaGuardAudit -Action 'WALLPAPER_SELECTED' -Detail $d.FileName -Root $root
            Set-Status 'Fondo seleccionado' 'Success'
        }
    })

    # Clicking a green switch only changes the local allow list. Windows remains
    # unchanged until the administrator explicitly uses Aplicar control.
    $toggleProgramRow = {
        param([int]$Index)
        if ($Index -lt 0 -or $Index -ge $gridPrograms.Rows.Count) { return }
        $row = $gridPrograms.Rows[$Index]
        $app = $row.Tag
        if (-not $app -or -not $app.CanAllow) {
            Set-Status 'Esta aplicación necesita una regla Store o un EXE verificable; no se aplicó ningún cambio.' 'Warning'
            return
        }
        $path = [string]$app.ExecutablePath
        if ($script:allowedProgramMap.ContainsKey($path)) {
            [void]$script:allowedProgramMap.Remove($path)
        } else {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Set-Status 'No se encontró el ejecutable; vuelve a detectar programas.' 'Warning'
                return
            }
            $script:allowedProgramMap[$path] = $path
        }
        & $syncProgramSelection
        & $renderPrograms
        Set-Status 'Selección modificada. Guarda y valida antes de aplicar restricciones.' 'Warning'
        Refresh-Dashboard
    }
    $gridPrograms.Add_CellClick({
        param($sender,$e)
        if ($e.ColumnIndex -eq 0 -and $e.RowIndex -ge 0) {
            & $toggleProgramRow $e.RowIndex
        }
    })
    $gridPrograms.Add_KeyDown({
        param($sender,$e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Space -and
            $gridPrograms.CurrentCell -and $gridPrograms.CurrentCell.ColumnIndex -eq 0) {
            & $toggleProgramRow $gridPrograms.CurrentCell.RowIndex
            $e.Handled = $true
            $e.SuppressKeyPress = $true
        }
    })
    $txtProgramSearch.Add_TextChanged({ & $renderPrograms })
    $cmbPrograms.Add_SelectedIndexChanged({ & $renderPrograms })
    $btnRefreshPrograms.Add_Click({ & $loadPrograms })

    $btnAddProgram.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = 'Programas de Windows (*.exe)|*.exe'
        $d.Multiselect = $true
        if ($d.ShowDialog() -eq 'OK') {
            foreach ($file in $d.FileNames) {
                $path = Resolve-AulaGuardExecutablePath -Candidate $file
                if (-not $path) { continue }
                $script:allowedProgramMap[$path] = $path
                if (@($script:programCatalog | Where-Object { $_.ExecutablePath -eq $path }).Count -eq 0) {
                    $script:programCatalog += [pscustomobject]@{
                        Name=[IO.Path]::GetFileNameWithoutExtension($path)
                        Publisher='Seleccionado por administrador'
                        Version=''
                        Type='Win32'
                        ExecutablePath=$path
                        CanAllow=$true
                        Reason=''
                        Source='Manual'
                    }
                }
            }
            & $syncProgramSelection
            & $renderPrograms
            Set-Status 'Programa agregado; guarda la selección para conservarla.' 'Success'
            Refresh-Dashboard
        }
    })
    $btnRemoveProgram.Add_Click({
        if ($gridPrograms.SelectedRows.Count -eq 0) {
            Set-Status 'Selecciona una aplicación de la tabla.' 'Warning'
            return
        }
        $record = $gridPrograms.SelectedRows[0].Tag
        if ($record -and $record.ExecutablePath) {
            [void]$script:allowedProgramMap.Remove([string]$record.ExecutablePath)
            & $syncProgramSelection
            & $renderPrograms
            Set-Status 'Programa retirado de la selección. Guarda los cambios.' 'Warning'
            Refresh-Dashboard
        }
    })

    # Radio buttons are in separate visual cards: enforce mutual exclusion.
    $radAppAudit.Add_CheckedChanged({
        if ($radAppAudit.Checked) { $radAppEnforce.Checked = $false }
    })
    $radAppEnforce.Add_CheckedChanged({
        if ($radAppEnforce.Checked) { $radAppAudit.Checked = $false }
    })

    $btnAddWebsite.Add_Click({
        $v = $txtWebsite.Text.Trim()
        if ($v -and $lstWebsites.Items -notcontains $v) {
            [void]$lstWebsites.Items.Add($v)
            $txtWebsite.Clear()
            Set-Status 'Sitio agregado' 'Success'
        }
    })

    $btnRemoveWebsite.Add_Click({
        while ($lstWebsites.SelectedIndices.Count -gt 0) {
            $lstWebsites.Items.RemoveAt($lstWebsites.SelectedIndices[0])
        }
    })

    $btnAddShortcut.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = 'Accesos directos (*.lnk)|*.lnk'
        $d.Multiselect = $true
        if ($d.ShowDialog() -eq 'OK') {
            foreach ($f in $d.FileNames) {
                if ($lstShortcuts.Items -notcontains $f) {
                    [void]$lstShortcuts.Items.Add($f)
                }
            }
            Set-Status 'Accesos agregados' 'Success'
        }
    })

    $btnRemoveShortcut.Add_Click({
        while ($lstShortcuts.SelectedIndices.Count -gt 0) {
            $lstShortcuts.Items.RemoveAt($lstShortcuts.SelectedIndices[0])
        }
    })

    $btnUsbRefresh.Add_Click({
        & $refreshUsb
    & $loadReadiness | Out-Null
        Set-Status 'Discos extraíbles actualizados' 'Success'
    })
    $btnUsbRestore.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show(
            'Se restaurarán las restricciones USB administradas por AulaGuard en las cuentas estándar. ¿Continuar?',
            'AulaGuard · USB','YesNo','Question') -ne 'Yes') { return }
        try {
            $result = @(Sync-AulaGuardUsbPolicy -BlockStorage $false -Root $root)
            $errors = @($result | Where-Object { $_.Status -eq 'ERROR' })
            if ($errors.Count -gt 0) { throw "No se pudo restaurar en $($errors.Count) perfil(es): $($errors[0].Detail)" }
            $toggleUsb.Checked = $false
            Save-FromUi
            Write-AulaGuardAudit -Action 'USB_POLICY_RESTORED' -Level 'SECURITY' -Detail "Profiles=$($result.Count)" -Root $root
            Set-Status 'Acceso USB administrado restaurado; cierra y abre la sesión del estudiante.' 'Success'
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · USB','OK','Error') | Out-Null
        }
    })

    $btnSave.Add_Click({
        try {
            Save-FromUi
            Refresh-Dashboard
        } catch {
            Set-Status 'No se pudo guardar el fondo o la configuración' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · Fondo institucional','OK','Error') | Out-Null
        }
    })

    $btnApply.Add_Click({
        $simulation = -not $radEnforce.Checked
        $message = if ($simulation) {
            'MODO AUDITORÍA: esta acción NO bloquea nada en Windows. Para aplicar restricciones reales, selecciona Protección activa en la pestaña Protección. ¿Deseas ejecutar solamente la simulación?'
        } else {
            'Se aplicarán las restricciones de Windows y USB a estudiantes estándar. IMPORTANTE: el bloqueo de juegos y aplicaciones se configura aparte en Control de apps → Bloqueo activo. ¿Continuar?'
        }

        if ([System.Windows.Forms.MessageBox]::Show($message,'AulaGuard','YesNo','Question') -ne 'Yes') {
            return
        }

        try {
            Save-FromUi
            if (-not $simulation) {
                $checks = @(Test-AulaGuardReadiness -Root $root -Settings $settings)
                $blocking = @($checks | Where-Object { -not $_.Passed -and $_.BlocksPolicies })
                if ($blocking.Count -gt 0) {
                    $tabs.SelectedTab = $tabHealth
                    & $loadReadiness | Out-Null
                    $detail = ($blocking | Select-Object -First 3 | ForEach-Object { "• $($_.Name): $($_.Detail)" }) -join [Environment]::NewLine
                    throw "El equipo no está listo para aplicar políticas.$([Environment]::NewLine)$([Environment]::NewLine)$detail"
                }
            }
            if (-not $simulation -and $settings.policyMode -eq 'Enforce') {
                $labResult = Test-AulaGuardPolicyEngine -Settings $settings
                if (-not $labResult.Passed) {
                    $failedCodes = @($labResult.Checks | Where-Object { -not $_.Passed } | ForEach-Object { $_.Code }) -join ', '
                    throw "La validación aislada del motor de políticas falló: $failedCodes"
                }
                Write-AulaGuardAudit -Action 'POLICY_LAB_PASSED' -Level 'SECURITY' -Detail 'Motor de políticas validado antes de Enforcement.' -Root $root
            }
            Set-Status 'Aplicando protección...' 'Warning'
            $result = @(Set-AulaGuardPolicies -Settings $settings -WhatIfMode:$simulation)
            $usbResults = @(Sync-AulaGuardUsbPolicy -BlockStorage ([bool]$settings.usb.blockStorage) -Root $root -WhatIfMode:$simulation)
            $result += $usbResults

            if (-not $simulation -and $result.Count -eq 0) {
                throw 'No se pudo aplicar protección: no hay cuentas estándar de estudiantes a las que dirigir las restricciones.'
            }

            if (-not $simulation -and $settings.protections.protectPublicDesktop) {
                Protect-AulaGuardPublicDesktop
            }

            $ok = @($result | Where-Object {$_.Status -in @('OK','SIMULADO')}).Count
            $errors = @($result | Where-Object {$_.Status -eq 'ERROR'}).Count

            if (-not $simulation -and $errors -eq 0) {
                $settings.lastAppliedUtc = (Get-Date).ToUniversalTime().ToString('o')
            }
            Save-AulaGuardSettings -Settings $settings -Root $root | Out-Null
            Write-AulaGuardAudit -Action 'POLICIES_APPLIED' -Level $(if ($errors -gt 0) {'ERROR'} else {'SECURITY'}) -Detail "Simulation=$simulation;OK=$ok;Errors=$errors" -Root $root

            if ($errors -gt 0) {
                Set-Status "Protección incompleta: $errors error(es)" 'Warning'
            } elseif ($simulation) {
                Set-Status "Simulación terminada: no se bloquearon cuentas" 'Warning'
            } else {
                Set-Status "Registro de $ok operaciones verificado; reinicia sesión del estudiante" 'Success'
            }
            Refresh-Dashboard
            & $loadAudit

            $details = @($result | Where-Object { $_.Status -eq 'ERROR' } |
                Select-Object -First 3 | ForEach-Object { "$($_.User): $($_.Detail)" }) -join [Environment]::NewLine
            $explanation = if ($simulation) {
                'Solo simulación: NO existen bloqueos nuevos. Ve a Protección y selecciona Protección activa.'
            } elseif ($errors -gt 0) {
                "La protección NO está completa. Corrige los errores: $details"
            } else {
                'Directivas comprobadas en el Registro del estudiante. Cierra su sesión y vuelve a entrar para probar el bloqueo real. Juegos y aplicaciones se bloquean desde Control de apps.'
            }
            [System.Windows.Forms.MessageBox]::Show(
                "$explanation$([Environment]::NewLine)$([Environment]::NewLine)Operaciones procesadas: $($result.Count)$([Environment]::NewLine)Verificadas: $ok$([Environment]::NewLine)Errores: $errors",
                'AulaGuard','OK',$(if ($errors -gt 0) {'Warning'} else {'Information'})
            ) | Out-Null
        }
        catch {
            Write-AulaGuardAudit -Action 'POLICY_ERROR' -Level 'ERROR' -Detail $_.Exception.Message -Root $root
            Set-Status 'Error al aplicar protección' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard','OK','Error') | Out-Null
        }
    })

    $btnReset.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show(
            'Se retirarán las políticas generales y USB de los estudiantes. AppLocker se restaura aparte desde Control de apps. ¿Continuar?',
            'AulaGuard','YesNo','Warning'
        ) -ne 'Yes') {
            return
        }

        try {
            $r = @(Reset-AulaGuardPolicies -ManagedWallpapers @([string]$settings.wallpaper,[string]$script:originalWallpaperPath))
            $policyErrors = @($r | Where-Object { $_.Status -eq 'ERROR' })
            if ($policyErrors.Count -gt 0) { throw "Error retirando políticas: $($policyErrors[0].Detail)" }
            $radAudit.Checked = $true
            # A reset must not fail while trying to re-import the very image path
            # that caused the black background. Re-select it deliberately later.
            $txtWallpaper.Clear()
            $chkLockWallpaper.Checked = $false
            $usbRestored = @(Sync-AulaGuardUsbPolicy -BlockStorage $false -Root $root)
            $usbErrors = @($usbRestored | Where-Object {$_.Status -eq 'ERROR'})
            if ($usbErrors.Count -gt 0) { throw "Error restaurando USB: $($usbErrors[0].Detail)" }
            $toggleUsb.Checked = $false
            Save-FromUi
            Protect-AulaGuardPublicDesktop -Restore
            Write-AulaGuardAudit -Action 'POLICIES_RESET' -Level 'SECURITY' -Detail "Profiles=$($r.Count)" -Root $root
            Set-Status 'Políticas retiradas' 'Success'
            & $loadAudit
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard','OK','Error') | Out-Null
        }
    })

    $btnExport.Add_Click({
        Save-FromUi
        $d = New-Object System.Windows.Forms.SaveFileDialog
        $d.Filter = 'Perfil AulaGuard (*.json)|*.json'
        $d.FileName = 'AulaGuard-profile.json'
        if ($d.ShowDialog() -eq 'OK') {
            Export-AulaGuardProfile -Path $d.FileName -Root $root
            Set-Status 'Perfil exportado' 'Success'
        }
    })

    $btnImport.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = 'Perfil AulaGuard (*.json)|*.json'
        if ($d.ShowDialog() -ne 'OK') { return }
        try {
            Import-AulaGuardProfile -Path $d.FileName -Root $root | Out-Null
            $script:settings = Read-AulaGuardSettings -Root $root
            $txtProfileName.Text = [string]$settings.profileName
            $radAudit.Checked = $true
            $txtWallpaper.Text = [string]$settings.wallpaper
            $chkLockWallpaper.Checked = [bool]$settings.protections.lockWallpaper
            $chkPersonalization.Checked = [bool]$settings.protections.disablePersonalization
            $chkProtectDesktop.Checked = [bool]$settings.protections.protectPublicDesktop
            $chkControlPanel.Checked = [bool]$settings.protections.blockControlPanel
            $chkRegistry.Checked = [bool]$settings.protections.blockRegistryTools
            $chkTaskMgr.Checked = [bool]$settings.protections.blockTaskManager
            $chkBrowserWhitelist.Checked = [bool]$settings.protections.browserWhitelist
            $toggleUsb.Checked = [bool]$settings.usb.blockStorage
            Add-ListItems $lstWebsites @($settings.allowedWebsites)
            Add-ListItems $lstShortcuts @($settings.protectedShortcuts)
            $script:allowedProgramMap = @{}
            foreach ($path in @($settings.allowedPrograms)) {
                if ($path -and -not [string]::IsNullOrWhiteSpace([string]$path)) {
                    $script:allowedProgramMap[[string]$path] = [string]$path
                }
            }
            & $syncProgramSelection
            $script:inventoryLoaded = $false
            & $loadPrograms
            $radAppEnforce.Checked = ($settings.appControl.mode -eq 'Enabled')
            $radAppAudit.Checked = -not $radAppEnforce.Checked
            Refresh-Dashboard
            Set-Status 'Perfil importado y controles actualizados (modo Auditoría)' 'Success'
            [System.Windows.Forms.MessageBox]::Show(
                'Perfil cargado correctamente en modo Auditoría. El fondo y el USB se deben configurar de nuevo. Las reglas AppLocker actuales del equipo no se modificaron.',
                'AulaGuard · Importación segura','OK','Information'
            ) | Out-Null
        } catch {
            Set-Status 'No se pudo importar el perfil' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · Importación','OK','Error') | Out-Null
        }
    })

    $btnAppPreview.Add_Click({
        try {
            $mode = if ($radAppEnforce.Checked) {'Enabled'} else {'AuditOnly'}
            $xml = New-AulaGuardAppLockerPolicyXml -AllowedPrograms @(Get-ListItems $lstPrograms) -Mode $mode
            [xml]$doc = $xml
            $collections = @($doc.AppLockerPolicy.RuleCollection).Count
            $rules = 0
            foreach ($collection in @($doc.AppLockerPolicy.RuleCollection)) {
                $rules += @($collection.ChildNodes | Where-Object {$_.Name -match 'Rule$'}).Count
            }

            [System.Windows.Forms.MessageBox]::Show(
                "La configuración es válida.$([Environment]::NewLine)$([Environment]::NewLine)Modo: $mode$([Environment]::NewLine)Colecciones: $collections$([Environment]::NewLine)Reglas: $rules$([Environment]::NewLine)Programas registrados: $($lstPrograms.Items.Count)",
                'AulaGuard · Validación','OK','Information'
            ) | Out-Null
            Set-Status 'Configuración AppLocker válida' 'Success'
        }
        catch {
            Set-Status 'La configuración necesita revisión' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · Validación','OK','Error') | Out-Null
        }
    })

    $btnAppApply.Add_Click({
        try {
            $mode = if ($radAppEnforce.Checked) {'Enabled'} else {'AuditOnly'}

            if ($mode -eq 'Enabled') {
                $warningText = "Vas a activar el bloqueo real de aplicaciones.$([Environment]::NewLine)$([Environment]::NewLine)Hazlo solo si ya probaste la misma lista en auditoría.$([Environment]::NewLine)$([Environment]::NewLine)¿Continuar?"
                if ([System.Windows.Forms.MessageBox]::Show($warningText,'AulaGuard · Activar bloqueo','YesNo','Warning') -ne 'Yes') {
                    return
                }
            } else {
                if ([System.Windows.Forms.MessageBox]::Show(
                    'Se activará la auditoría. Los programas seguirán abriendo y AulaGuard registrará cuáles podrían bloquearse. ¿Continuar?',
                    'AulaGuard · Auditoría','YesNo','Question'
                ) -ne 'Yes') {
                    return
                }
            }

            $appChecks = @(Test-AulaGuardReadiness -Root $root -Settings $settings)
            $appBlocking = @($appChecks | Where-Object { -not $_.Passed -and $_.BlocksAppControl })
            if ($appBlocking.Count -gt 0) {
                $tabs.SelectedTab = $tabHealth
                & $loadReadiness | Out-Null
                $detail = ($appBlocking | Select-Object -First 3 | ForEach-Object { "• $($_.Name): $($_.Detail)" }) -join [Environment]::NewLine
                throw "El equipo no está listo para AppLocker.$([Environment]::NewLine)$([Environment]::NewLine)$detail"
            }

            Set-Status 'Configurando control de aplicaciones...' 'Warning'
            $selectedPrograms = @(Get-ListItems $lstPrograms)
            $parameters = @{
                AllowedPrograms = $selectedPrograms
                Mode = $mode
                BackupDirectory = (Join-Path $root 'backup')
            }
            $result = Set-AulaGuardAppControlPolicy @parameters
            $settings.allowedPrograms = $selectedPrograms

            $settings.appControl.mode = $mode
            $settings.appControl.enabled = $true
            $settings.appControl.lastAppliedUtc = (Get-Date).ToUniversalTime().ToString('o')
            $settings.appControl.lastBackup = $result.Backup

            Save-AulaGuardSettings -Settings $settings -Root $root | Out-Null
            Write-AulaGuardAudit -Action 'APPLOCKER_APPLIED' -Level 'SECURITY' -Detail "Mode=$mode;Allowed=$($lstPrograms.Items.Count)" -Root $root
            & $loadAppEvents
            Set-Status "Control de aplicaciones activo: $mode" 'Success'
        }
        catch {
            Write-AulaGuardAudit -Action 'APPLOCKER_ERROR' -Level 'ERROR' -Detail $_.Exception.Message -Root $root
            Set-Status 'Error al configurar aplicaciones' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · Aplicaciones','OK','Error') | Out-Null
        }
    })

    $btnAppRestore.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show(
            'Se restaurará la copia anterior de AppLocker. ¿Continuar?',
            'AulaGuard','YesNo','Warning'
        ) -ne 'Yes') {
            return
        }

        try {
            $restored = Restore-AulaGuardAppLockerPolicy -BackupDirectory (Join-Path $root 'backup')
            $settings.appControl.enabled = $false
            $settings.appControl.mode = 'AuditOnly'
            $settings.appControl.lastAppliedUtc = $null
            $settings.appControl.lastBackup = $null
            $radAppAudit.Checked = $true
            Save-AulaGuardSettings -Settings $settings -Root $root | Out-Null
            Write-AulaGuardAudit -Action 'APPLOCKER_RESTORED' -Level 'SECURITY' -Detail $restored.RestoredFrom -Root $root
            Set-Status 'Política anterior restaurada' 'Success'
            & $loadAppEvents
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard','OK','Error') | Out-Null
        }
    })

    $btnAppRefresh.Add_Click($loadAppEvents)
    $btnRefreshAudit.Add_Click($loadAudit)
    $radAudit.Add_CheckedChanged({Refresh-Dashboard})
    $radEnforce.Add_CheckedChanged({Refresh-Dashboard})

    foreach ($page in $tabs.TabPages) {
        $page.AutoScroll = $true
    }

    & $resizeProtection
    Set-NavActive $navHome
    Write-AulaGuardAudit -Action 'APP_STARTED' -Detail 'v0.5.1' -Root $root
    Refresh-Dashboard
    & $loadAudit
    & $loadAppEvents
    & $refreshUsb

    $form.Add_FormClosed({
        try {
            Write-AulaGuardAudit -Action 'APP_CLOSED' -Root $root
        } catch {}
    })

    # Optional WinForms construction self-test; do not show a blocking dialog.
    if ($script:AulaGuardUiTest) {
        # Exercise the complete responsive screen tree before testing actions.
        foreach ($layout in @($homeLayout,$healthLayout,$programLayout,$appLayout,$webLayout,$desktopLayout,$usbView,$auditLayout)) {
            if ($layout.Dock -ne [System.Windows.Forms.DockStyle]::Fill) {
                throw "Una pantalla profesional no ocupa el área disponible: $($layout.Name)"
            }
        }
        if ($metrics.ColumnCount -ne 4 -or $quick.ColumnCount -ne 3) {
            throw 'El panel de Inicio perdió su estructura adaptable.'
        }
        foreach ($page in @($tabHome,$tabHealth,$tabProtection,$tabPrograms,$tabAppControl,$tabWeb,$tabDesktop,$tabUsb,$tabAudit)) {
            $tabs.SelectedTab = $page
            $page.PerformLayout()
        }

        # Exercise the actual inventory navigation and toggle event binding,
        # not merely the construction of otherwise inert WinForms controls.
        $tabs.SelectedTab = $tabPrograms
        if (-not $script:inventoryLoaded) { & $loadPrograms }
        if (-not $script:inventoryLoaded -or $script:programCatalog.Count -lt 1 -or $gridPrograms.Rows.Count -lt 1) {
            throw 'La pestaña Programas no pudo detectar o mostrar las aplicaciones de Windows.'
        }
        $firstCompatible = @($script:programCatalog | Where-Object {
            $_.CanAllow -and $_.ExecutablePath
        } | Select-Object -First 1)
        if ($firstCompatible.Count -gt 0) {
            $candidate = [string]$firstCompatible[0].ExecutablePath
            $previous = $script:allowedProgramMap.ContainsKey($candidate)
            $targetRow = -1
            foreach ($visibleRow in $gridPrograms.Rows) {
                if ($visibleRow.Tag -and $visibleRow.Tag.ExecutablePath -eq $candidate) {
                    $targetRow = $visibleRow.Index
                    break
                }
            }
            if ($targetRow -lt 0) { throw 'El catálogo no vinculó la aplicación compatible con su interruptor.' }
            & $toggleProgramRow $targetRow
            if ($script:allowedProgramMap.ContainsKey($candidate) -eq $previous) {
                throw 'El interruptor de Programas no modificó la lista de aplicaciones.'
            }
            & $toggleProgramRow $targetRow
            if ($script:allowedProgramMap.ContainsKey($candidate) -ne $previous) {
                throw 'El interruptor no restauró el estado inicial.'
            }
        }
        $tabs.SelectedTab = $tabAppControl
        $radAppAudit.Checked = $true
        $radAppEnforce.Checked = $true
        if ($radAppAudit.Checked -or -not $radAppEnforce.Checked) {
            throw 'Los modos Auditoría y Bloqueo de apps no son excluyentes.'
        }
        $radAppAudit.Checked = $true
        if (-not $radAppAudit.Checked -or $radAppEnforce.Checked) {
            throw 'No se puede volver a Auditoría desde Bloqueo.'
        }
        $form.Dispose()
        exit 0
    }

    [void]$form.ShowDialog()
}
catch {
    try {
        $message = $_.Exception.ToString()
        $logPath = Join-Path $env:TEMP 'AulaGuard-startup-error.txt'
        Set-Content -LiteralPath $logPath -Value $message -Encoding UTF8 -ErrorAction Stop

        if ($env:AULAGUARD_EXE_SELFTEST -eq '1' -or $env:AULAGUARD_UI_SELFTEST -eq '1') {
            Write-Host "AULAGUARD_SELFTEST_ERROR: $message"
        } else {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show(
                "AulaGuard no pudo iniciar.$([Environment]::NewLine)$([Environment]::NewLine)$($_.Exception.Message)$([Environment]::NewLine)$([Environment]::NewLine)Registro: $logPath",
                'AulaGuard · Error','OK','Error'
            ) | Out-Null
        }
    } catch {}
    exit 1
}
