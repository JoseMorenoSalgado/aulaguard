# AulaGuard v0.4.3
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
        'AulaGuard.Wallpaper.psm1'
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
    $Bg = [System.Drawing.Color]::FromArgb(245,247,250)
    $Card = [System.Drawing.Color]::White
    $Text = [System.Drawing.Color]::FromArgb(30,41,59)
    $Muted = [System.Drawing.Color]::FromArgb(100,116,139)
    $Border = [System.Drawing.Color]::FromArgb(226,232,240)
    $SoftBlue = [System.Drawing.Color]::FromArgb(236,253,245)
    $SoftGreen = [System.Drawing.Color]::FromArgb(240,253,244)
    $SoftAmber = [System.Drawing.Color]::FromArgb(255,251,235)

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
        $b.Cursor = 'Hand'
        $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)

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
        $b.Size = New-Object System.Drawing.Size(160,44)
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize = 0
        $b.TextAlign = 'MiddleLeft'
        $b.Padding = New-Object System.Windows.Forms.Padding(14,0,0,0)
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
        $status.Text = $Message
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
            version = '0.4.3'
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
            premium = $settings.premium
            appControl = [pscustomobject]@{
                mode = if ($radAppEnforce.Checked) {'Enabled'} else {'AuditOnly'}
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
    $header.Height = 92
    $header.BackColor = $PrimaryDark
    $form.Controls.Add($header)

    $logo = New-Object System.Windows.Forms.Label
    $logo.Text = 'AG'
    $logo.TextAlign = 'MiddleCenter'
    $logo.Location = New-Object System.Drawing.Point(22,18)
    $logo.Size = New-Object System.Drawing.Size(54,54)
    $logo.BackColor = [System.Drawing.Color]::White
    $logo.ForeColor = $PrimaryDark
    $logo.Font = New-Object System.Drawing.Font('Segoe UI Semibold',15)
    $header.Controls.Add($logo)

    $header.Controls.Add((New-Label 'AulaGuard' 92 15 21 $true ([System.Drawing.Color]::White)))
    $header.Controls.Add((New-Label 'Protege el aula sin complicaciones' 94 48 10 $false ([System.Drawing.Color]::FromArgb(219,234,254))))

    $version = New-Object System.Windows.Forms.Label
    $version.Text = 'v0.4.3'
    $version.TextAlign = 'MiddleCenter'
    $version.Location = New-Object System.Drawing.Point(1060,26)
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

    $status = New-Label 'AulaGuard listo' 18 21 9 $false $Muted
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
    [void]$shell.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',202)))
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

    $sidebar.Controls.Add((New-Label 'NAVEGACIÓN' 24 18 8 $true $Muted))

    $navHome = New-NavButton 'Inicio' 46
    $navProtection = New-NavButton 'Protección' 92
    $navPrograms = New-NavButton 'Programas' 138
    $navAppControl = New-NavButton 'Control de apps' 184
    $navInternet = New-NavButton 'Internet' 230
    $navDesktop = New-NavButton 'Escritorio' 276
    $navUsb = New-NavButton 'Memorias USB' 322
    $navPremium = New-NavButton 'Servidor · Premium' 368
    $navLog = New-NavButton 'Registro' 414

    foreach ($nav in @($navHome,$navProtection,$navPrograms,$navAppControl,$navInternet,$navDesktop,$navUsb,$navPremium,$navLog)) {
        $sidebar.Controls.Add($nav)
    }

    $sideInfo = New-Card 12 480 178 110 $SoftGreen
    $sideInfo.Controls.Add((New-Label 'Aula protegida' 12 12 9 $true $PrimaryDark))
    $sideInfo.Controls.Add((New-Label 'Configura primero' 12 42 8 $false $Muted))
    $sideInfo.Controls.Add((New-Label 'en auditoría y luego' 12 62 8 $false $Muted))
    $sideInfo.Controls.Add((New-Label 'activa la protección.' 12 82 8 $false $Muted))
    $sidebar.Controls.Add($sideInfo)
    $sidebar.Add_Resize({
        $sideInfo.Visible = ($sidebar.ClientSize.Height -gt 610)
        $sideInfo.Top = [Math]::Max(475,$sidebar.ClientSize.Height - $sideInfo.Height - 12)
    })

    function Set-NavActive {
        param($Active)
        foreach ($nav in @($navHome,$navProtection,$navPrograms,$navAppControl,$navInternet,$navDesktop,$navUsb,$navPremium,$navLog)) {
            $nav.BackColor = [System.Drawing.Color]::White
            $nav.ForeColor = $Muted
        }
        $Active.BackColor = $SoftBlue
        $Active.ForeColor = $PrimaryDark
    }

    # HOME
    $tabHome = New-Object System.Windows.Forms.TabPage
    $tabHome.Text = 'Inicio'
    $tabHome.BackColor = $Bg
    $tabs.TabPages.Add($tabHome)

    $tabHome.Controls.Add((New-Label 'Bienvenido al centro de control del aula' 24 20 16 $true $Text))
    $tabHome.Controls.Add((New-Label 'Revisa el estado del equipo y sigue la guía en orden para configurar la protección.' 24 52 9 $false $Muted))

    $cardPc = New-Card 24 92 250 115 $Card
    $cardPc.Controls.Add((New-Label 'EQUIPO' 16 14 8 $true $Muted))
    $lblPcValue = New-Label '-' 16 42 12 $true $Text
    $cardPc.Controls.Add($lblPcValue)
    $lblWindowsValue = New-Label '-' 16 72 8 $false $Muted
    $cardPc.Controls.Add($lblWindowsValue)
    $tabHome.Controls.Add($cardPc)

    $cardUsers = New-Card 292 92 250 115 $SoftBlue
    $cardUsers.Controls.Add((New-Label 'USUARIOS DEL AULA' 16 14 8 $true $PrimaryDark))
    $lblUsersValue = New-Label '-' 16 42 12 $true $PrimaryDark
    $cardUsers.Controls.Add($lblUsersValue)
    $cardUsers.Controls.Add((New-Label 'Administradores excluidos automáticamente.' 16 72 8 $false $Muted))
    $tabHome.Controls.Add($cardUsers)

    $cardMode = New-Card 560 92 250 115 $SoftGreen
    $cardMode.Controls.Add((New-Label 'MODO DE PROTECCIÓN' 16 14 8 $true $Success))
    $lblModeValue = New-Label '-' 16 42 12 $true $Success
    $cardMode.Controls.Add($lblModeValue)
    $cardMode.Controls.Add((New-Label 'Empieza siempre en auditoría.' 16 72 8 $false $Muted))
    $tabHome.Controls.Add($cardMode)

    $cardApps = New-Card 828 92 290 115 $SoftAmber
    $cardApps.Controls.Add((New-Label 'PROGRAMAS AUTORIZADOS' 16 14 8 $true $Warning))
    $lblAppsValue = New-Label '0' 16 40 15 $true $Warning
    $cardApps.Controls.Add($lblAppsValue)
    $cardApps.Controls.Add((New-Label 'Solo agrega software usado en clase.' 16 74 8 $false $Muted))
    $tabHome.Controls.Add($cardApps)

    $tabHome.Controls.Add((New-Label 'Guía rápida' 24 238 13 $true $Text))
    $tabHome.Controls.Add((New-Label 'Tres pasos simples para preparar un equipo de forma segura.' 24 267 9 $false $Muted))

    $step1 = New-Card 24 306 340 110 $Card
    $step1.Controls.Add((New-Label '1' 16 18 15 $true $Primary))
    $step1.Controls.Add((New-Label 'Configura el aula' 52 18 11 $true $Text))
    $step1.Controls.Add((New-Label 'Elige fondo, programas, sitios y accesos.' 52 49 9 $false $Muted))
    $btnGoProtect = New-Button 'Ir a protección' 52 70 140 28 'Secondary'
    $step1.Controls.Add($btnGoProtect)
    $tabHome.Controls.Add($step1)

    $step2 = New-Card 386 306 340 110 $Card
    $step2.Controls.Add((New-Label '2' 16 18 15 $true $Primary))
    $step2.Controls.Add((New-Label 'Prueba en auditoría' 52 18 11 $true $Text))
    $step2.Controls.Add((New-Label 'Observa qué pasaría sin bloquear.' 52 49 9 $false $Muted))
    $btnGoApps = New-Button 'Revisar programas' 52 70 150 28 'Secondary'
    $step2.Controls.Add($btnGoApps)
    $tabHome.Controls.Add($step2)

    $step3 = New-Card 748 306 370 110 $Card
    $step3.Controls.Add((New-Label '3' 16 18 15 $true $Success))
    $step3.Controls.Add((New-Label 'Activa la protección' 52 18 11 $true $Text))
    $step3.Controls.Add((New-Label 'Hazlo solo después de revisar la auditoría.' 52 49 9 $false $Muted))
    $step3.Controls.Add((New-Label 'Administradores protegidos' 52 76 8 $true $Success))
    $tabHome.Controls.Add($step3)

    $tabHome.Controls.Add((New-Label 'Usuarios detectados' 24 446 12 $true $Text))
    $gridUsers = New-Object System.Windows.Forms.DataGridView
    $gridUsers.Location = New-Object System.Drawing.Point(24,480)
    $gridUsers.Size = New-Object System.Drawing.Size(1094,145)
    $gridUsers.Anchor = 'Top,Left,Right,Bottom'
    Style-Grid $gridUsers
    [void]$gridUsers.Columns.Add('User','Usuario')
    [void]$gridUsers.Columns.Add('Role','Tipo de cuenta')
    [void]$gridUsers.Columns.Add('State','Estado')
    [void]$gridUsers.Columns.Add('SID','Identificador')
    $tabHome.Controls.Add($gridUsers)

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
    $toolTip.SetToolTip($radAudit,'Recomendado para comenzar. No realiza cambios reales.')

    $radEnforce = New-Object System.Windows.Forms.RadioButton
    $radEnforce.Text = 'Protección activa'
    $radEnforce.Location = New-Object System.Drawing.Point(210,50)
    $radEnforce.AutoSize = $true
    $modeCard.Controls.Add($radEnforce)
    $toolTip.SetToolTip($radEnforce,'Aplica las restricciones reales a las cuentas estándar.')

    if ($settings.policyMode -eq 'Enforce') {$radEnforce.Checked = $true} else {$radAudit.Checked = $true}
    $tabProtection.Controls.Add($modeCard)

    $left = New-Card 24 204 535 292 $Card
    $left.Controls.Add((New-Label 'Escritorio y apariencia' 18 16 11 $true $Text))

    $chkLockWallpaper = New-Object System.Windows.Forms.CheckBox
    $chkLockWallpaper.Text = 'Evitar que los estudiantes cambien el fondo'
    $chkLockWallpaper.Location = New-Object System.Drawing.Point(18,55)
    $chkLockWallpaper.AutoSize = $true
    $chkLockWallpaper.Checked = [bool]$settings.protections.lockWallpaper
    $left.Controls.Add($chkLockWallpaper)

    $chkPersonalization = New-Object System.Windows.Forms.CheckBox
    $chkPersonalization.Text = 'Ocultar opciones de personalización'
    $chkPersonalization.Location = New-Object System.Drawing.Point(18,88)
    $chkPersonalization.AutoSize = $true
    $chkPersonalization.Checked = [bool]$settings.protections.disablePersonalization
    $left.Controls.Add($chkPersonalization)

    $chkProtectDesktop = New-Object System.Windows.Forms.CheckBox
    $chkProtectDesktop.Text = 'Proteger accesos directos del escritorio público'
    $chkProtectDesktop.Location = New-Object System.Drawing.Point(18,121)
    $chkProtectDesktop.AutoSize = $true
    $chkProtectDesktop.Checked = [bool]$settings.protections.protectPublicDesktop
    $left.Controls.Add($chkProtectDesktop)

    $left.Controls.Add((New-Label 'Fondo institucional' 18 170 9 $true $Text))
    $txtWallpaper = New-Object System.Windows.Forms.TextBox
    $txtWallpaper.Location = New-Object System.Drawing.Point(18,201)
    $txtWallpaper.Size = New-Object System.Drawing.Size(360,28)
    $txtWallpaper.ReadOnly = $true
    $txtWallpaper.Text = [string]$settings.wallpaper
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
    $right.Controls.Add($chkControlPanel)

    $chkRegistry = New-Object System.Windows.Forms.CheckBox
    $chkRegistry.Text = 'Bloquear Editor del Registro'
    $chkRegistry.Location = New-Object System.Drawing.Point(18,113)
    $chkRegistry.AutoSize = $true
    $chkRegistry.Checked = [bool]$settings.protections.blockRegistryTools
    $right.Controls.Add($chkRegistry)

    $chkTaskMgr = New-Object System.Windows.Forms.CheckBox
    $chkTaskMgr.Text = 'Bloquear Administrador de tareas'
    $chkTaskMgr.Location = New-Object System.Drawing.Point(18,146)
    $chkTaskMgr.AutoSize = $true
    $chkTaskMgr.Checked = [bool]$settings.protections.blockTaskManager
    $right.Controls.Add($chkTaskMgr)

    $chkBrowserWhitelist = New-Object System.Windows.Forms.CheckBox
    $chkBrowserWhitelist.Text = 'Permitir solo los sitios web definidos en AulaGuard'
    $chkBrowserWhitelist.Location = New-Object System.Drawing.Point(18,179)
    $chkBrowserWhitelist.AutoSize = $true
    $chkBrowserWhitelist.Checked = [bool]$settings.protections.browserWhitelist
    $right.Controls.Add($chkBrowserWhitelist)

    $tabProtection.Controls.Add($right)

    $profileCard = New-Card 24 518 1094 100 $Card
    $profileCard.Controls.Add((New-Label 'Perfil del aula' 18 12 10 $true $Text))
    $profileCard.Controls.Add((New-Label 'Nombre' 18 50 9 $true $Muted))

    $txtProfileName = New-Object System.Windows.Forms.TextBox
    $txtProfileName.Location = New-Object System.Drawing.Point(78,46)
    $txtProfileName.Size = New-Object System.Drawing.Size(260,28)
    $txtProfileName.Text = [string]$settings.profileName
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
    $programNotice.Controls.Add((New-Label 'Cómo funciona' 14 8 10 $true $PrimaryDark))
    $programNotice.Controls.Add((New-Label 'Los interruptores modifican la selección. Guarda y valida en Control de apps antes de activar el bloqueo.' 14 34 9 $false $Text))
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
    $txtProgramSearch.Font = New-Object System.Drawing.Font('Segoe UI',11)
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

    # INTERNET
    $tabWeb = New-Object System.Windows.Forms.TabPage
    $tabWeb.Text = 'Internet'
    $tabWeb.BackColor = $Bg
    $tabs.TabPages.Add($tabWeb)

    $tabWeb.Controls.Add((New-Label 'Sitios web permitidos' 24 20 15 $true $Text))
    $tabWeb.Controls.Add((New-Label 'Si activas la lista blanca, Edge y Chrome permitirán únicamente los sitios definidos aquí.' 24 52 9 $false $Muted))

    $txtWebsite = New-Object System.Windows.Forms.TextBox
    $txtWebsite.Location = New-Object System.Drawing.Point(24,94)
    $txtWebsite.Size = New-Object System.Drawing.Size(720,30)
    $txtWebsite.Font = New-Object System.Drawing.Font('Segoe UI',10)
    $tabWeb.Controls.Add($txtWebsite)

    $btnAddWebsite = New-Button 'Agregar sitio' 760 90 150 36 'Primary'
    $tabWeb.Controls.Add($btnAddWebsite)

    $lstWebsites = New-Object System.Windows.Forms.ListBox
    $lstWebsites.Location = New-Object System.Drawing.Point(24,150)
    $lstWebsites.Size = New-Object System.Drawing.Size(884,430)
    $lstWebsites.Anchor = 'Top,Left,Right,Bottom'
    $lstWebsites.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $tabWeb.Controls.Add($lstWebsites)
    Add-ListItems $lstWebsites @($settings.allowedWebsites)

    $btnRemoveWebsite = New-Button 'Quitar seleccionado' 930 150 168 38 'Danger'
    $btnRemoveWebsite.Anchor = 'Top,Right'
    $tabWeb.Controls.Add($btnRemoveWebsite)

    # DESKTOP
    $tabDesktop = New-Object System.Windows.Forms.TabPage
    $tabDesktop.Text = 'Escritorio'
    $tabDesktop.BackColor = $Bg
    $tabs.TabPages.Add($tabDesktop)

    $tabDesktop.Controls.Add((New-Label 'Accesos directos del aula' 24 20 15 $true $Text))
    $tabDesktop.Controls.Add((New-Label 'Selecciona los accesos que quieres conservar y proteger para los estudiantes.' 24 52 9 $false $Muted))

    $lstShortcuts = New-Object System.Windows.Forms.ListBox
    $lstShortcuts.Location = New-Object System.Drawing.Point(24,96)
    $lstShortcuts.Size = New-Object System.Drawing.Size(884,480)
    $lstShortcuts.Anchor = 'Top,Left,Right,Bottom'
    $lstShortcuts.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $tabDesktop.Controls.Add($lstShortcuts)
    Add-ListItems $lstShortcuts @($settings.protectedShortcuts)

    $btnAddShortcut = New-Button 'Agregar acceso' 930 96 168 38 'Primary'
    $btnAddShortcut.Anchor = 'Top,Right'
    $tabDesktop.Controls.Add($btnAddShortcut)

    $btnRemoveShortcut = New-Button 'Quitar seleccionado' 930 144 168 38 'Danger'
    $btnRemoveShortcut.Anchor = 'Top,Right'
    $tabDesktop.Controls.Add($btnRemoveShortcut)

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
    $toggleUsb.Add_CheckedChanged({
        if ($toggleUsb.Checked) {
            $toggleUsb.Text = '● BLOQUEAR'
            $toggleUsb.BackColor = $Primary
            $toggleUsb.ForeColor = [System.Drawing.Color]::White
        } else {
            $toggleUsb.Text = '○ PERMITIR'
            $toggleUsb.BackColor = [System.Drawing.Color]::FromArgb(226,232,240)
            $toggleUsb.ForeColor = $Text
        }
    })
    if ($toggleUsb.Checked) {
        $toggleUsb.Text = '● BLOQUEAR'
        $toggleUsb.BackColor = $Primary
        $toggleUsb.ForeColor = [System.Drawing.Color]::White
    } else {
        $toggleUsb.Text = '○ PERMITIR'
        $toggleUsb.BackColor = [System.Drawing.Color]::FromArgb(226,232,240)
        $toggleUsb.ForeColor = $Text
    }
    $usbHint = New-Label 'Guarda y aplica en modo Protección. No desactiva puertos, teclados, ratones ni el acceso del administrador.' 158 92 9 $false $Muted
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

    # LOG
    $tabAudit = New-Object System.Windows.Forms.TabPage
    $tabAudit.Text = 'Registro'
    $tabAudit.BackColor = $Bg
    $tabs.TabPages.Add($tabAudit)

    $tabAudit.Controls.Add((New-Label 'Actividad de AulaGuard' 24 20 15 $true $Text))
    $tabAudit.Controls.Add((New-Label 'Aquí puedes revisar cambios, aplicaciones de políticas y errores.' 24 52 9 $false $Muted))

    $txtAudit = New-Object System.Windows.Forms.TextBox
    $txtAudit.Location = New-Object System.Drawing.Point(24,92)
    $txtAudit.Size = New-Object System.Drawing.Size(1094,470)
    $txtAudit.Anchor = 'Top,Left,Right,Bottom'
    $txtAudit.Multiline = $true
    $txtAudit.ReadOnly = $true
    $txtAudit.ScrollBars = 'Both'
    $txtAudit.Font = New-Object System.Drawing.Font('Consolas',9)
    $txtAudit.BackColor = [System.Drawing.Color]::White
    $tabAudit.Controls.Add($txtAudit)

    $btnRefreshAudit = New-Button 'Actualizar registro' 24 580 150 34 'Secondary'
    $btnRefreshAudit.Anchor = 'Left,Bottom'
    $tabAudit.Controls.Add($btnRefreshAudit)

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
        $info = Get-AulaGuardSystemInfo
        $users = @(Get-AulaGuardLocalUsers)
        $standard = @($users | Where-Object {-not $_.IsAdministrator})

        $lblPcValue.Text = $info.ComputerName
        $lblWindowsValue.Text = "$($info.Windows) · build $($info.Build)"
        $lblUsersValue.Text = "$($standard.Count) estudiante(s)"
        $lblModeValue.Text = if ($radEnforce.Checked) {'Protección activa'} else {'Modo seguro: auditoría'}
        $lblAppsValue.Text = [string]$lstPrograms.Items.Count

        $gridUsers.Rows.Clear()
        foreach ($u in $users) {
            [void]$gridUsers.Rows.Add(
                $u.User,
                $(if ($u.IsAdministrator) {'Administrador'} else {'Estudiante / estándar'}),
                $(if ($u.Loaded) {'Sesión iniciada'} else {'Sin sesión'}),
                $u.SID
            )
        }
    }

    $btnGoProtect.Add_Click({$tabs.SelectedTab = $tabProtection})
    $btnGoApps.Add_Click({$tabs.SelectedTab = $tabPrograms})

    $navHome.Add_Click({$tabs.SelectedTab = $tabHome})
    $navProtection.Add_Click({$tabs.SelectedTab = $tabProtection})
    $navPrograms.Add_Click({
        $tabs.SelectedTab = $tabPrograms
        if (-not $script:inventoryLoaded) { & $loadPrograms }
    })
    $navAppControl.Add_Click({$tabs.SelectedTab = $tabAppControl})
    $navInternet.Add_Click({$tabs.SelectedTab = $tabWeb})
    $navDesktop.Add_Click({$tabs.SelectedTab = $tabDesktop})
    $navUsb.Add_Click({$tabs.SelectedTab = $tabUsb})
    $navPremium.Add_Click({$tabs.SelectedTab = $tabPremium})
    $navLog.Add_Click({$tabs.SelectedTab = $tabAudit})

    $tabs.Add_SelectedIndexChanged({
        if ($tabs.SelectedTab -eq $tabHome) {Set-NavActive $navHome}
        elseif ($tabs.SelectedTab -eq $tabProtection) {Set-NavActive $navProtection}
        elseif ($tabs.SelectedTab -eq $tabPrograms) {Set-NavActive $navPrograms}
        elseif ($tabs.SelectedTab -eq $tabAppControl) {Set-NavActive $navAppControl}
        elseif ($tabs.SelectedTab -eq $tabWeb) {Set-NavActive $navInternet}
        elseif ($tabs.SelectedTab -eq $tabDesktop) {Set-NavActive $navDesktop}
        elseif ($tabs.SelectedTab -eq $tabUsb) {Set-NavActive $navUsb}
        elseif ($tabs.SelectedTab -eq $tabPremium) {Set-NavActive $navPremium}
        elseif ($tabs.SelectedTab -eq $tabAudit) {Set-NavActive $navLog}
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
        try { Save-FromUi }
        catch {
            Set-Status 'No se pudo validar el fondo institucional' 'Error'
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'AulaGuard · Fondo institucional','OK','Error') | Out-Null
            return
        }
        $simulation = -not $radEnforce.Checked
        $message = if ($simulation) {
            'AulaGuard realizará una simulación y no hará cambios reales en Windows. ¿Continuar?'
        } else {
            'Se aplicarán las protecciones a las cuentas de estudiante. Las cuentas administradoras permanecerán excluidas. ¿Continuar?'
        }

        if ([System.Windows.Forms.MessageBox]::Show($message,'AulaGuard','YesNo','Question') -ne 'Yes') {
            return
        }

        try {
            Set-Status 'Aplicando protección...' 'Warning'
            $result = @(Apply-AulaGuardPolicies -Settings $settings -WhatIfMode:$simulation)
            $usbResults = @(Sync-AulaGuardUsbPolicy -BlockStorage ([bool]$settings.usb.blockStorage) -Root $root -WhatIfMode:$simulation)
            $result += $usbResults


            if (-not $simulation -and $settings.protections.protectPublicDesktop) {
                Protect-AulaGuardPublicDesktop
            }

            $ok = @($result | Where-Object {$_.Status -in @('OK','SIMULADO')}).Count
            $errors = @($result | Where-Object {$_.Status -eq 'ERROR'}).Count

            $settings.lastAppliedUtc = (Get-Date).ToUniversalTime().ToString('o')
            Save-AulaGuardSettings -Settings $settings -Root $root | Out-Null
            Write-AulaGuardAudit -Action 'POLICIES_APPLIED' -Level 'SECURITY' -Detail "Simulation=$simulation;OK=$ok;Errors=$errors" -Root $root

            Set-Status "Protección procesada: $ok correcto(s)" 'Success'
            Refresh-Dashboard
            & $loadAudit

            [System.Windows.Forms.MessageBox]::Show(
                "Proceso completado.$([Environment]::NewLine)$([Environment]::NewLine)Usuarios procesados: $($result.Count)$([Environment]::NewLine)Correctos: $ok$([Environment]::NewLine)Errores: $errors",
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
            'Se retirarán las políticas administradas por AulaGuard de las cuentas estándar. ¿Continuar?',
            'AulaGuard','YesNo','Warning'
        ) -ne 'Yes') {
            return
        }

        try {
            $r = @(Reset-AulaGuardPolicies -ManagedWallpapers @([string]$settings.wallpaper,[string]$script:originalWallpaperPath))
            $radAudit.Checked = $true
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
        if ($d.ShowDialog() -eq 'OK') {
            Import-AulaGuardProfile -Path $d.FileName -Root $root | Out-Null
            [System.Windows.Forms.MessageBox]::Show(
                'Perfil importado. Cierra y vuelve a abrir AulaGuard para cargar todos los valores.',
                'AulaGuard','OK','Information'
            ) | Out-Null
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
            Save-FromUi
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

            Set-Status 'Configurando control de aplicaciones...' 'Warning'

            $parameters = @{
                AllowedPrograms = @(Get-ListItems $lstPrograms)
                Mode = $mode
                BackupDirectory = (Join-Path $root 'backup')
            }
            $result = Set-AulaGuardAppControlPolicy @parameters

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
    Write-AulaGuardAudit -Action 'APP_STARTED' -Detail 'v0.4.3' -Root $root
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
