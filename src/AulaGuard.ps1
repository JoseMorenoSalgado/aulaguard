# AulaGuard v0.3.5
# Friendly educational administration console for Windows classrooms.

$ErrorActionPreference = 'Stop'

# Command-line self-tests survive UAC elevation, unlike process environment variables.
$script:AulaGuardCommandLine = @([Environment]::GetCommandLineArgs())
$script:AulaGuardBootstrapTest = ($script:AulaGuardCommandLine -contains '--aulaguard-selftest-bootstrap')
$script:AulaGuardUiTest = ($script:AulaGuardCommandLine -contains '--aulaguard-selftest-ui')

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
        'AulaGuard.AppControl.psm1'
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

    # GitHub Actions executes the actual compiled EXE to check bootstrap, imports
    # and settings; never suppress security checks in the self-test.
    if ($script:AulaGuardBootstrapTest) {
        Write-AulaGuardAudit -Action 'EXE_BOOTSTRAP_VERIFIED' -Level 'SECURITY' -Root $root
        exit 0
    }

    $Primary = [System.Drawing.Color]::FromArgb(37,99,235)
    $PrimaryDark = [System.Drawing.Color]::FromArgb(30,64,175)
    $Success = [System.Drawing.Color]::FromArgb(22,163,74)
    $Warning = [System.Drawing.Color]::FromArgb(217,119,6)
    $Danger = [System.Drawing.Color]::FromArgb(220,38,38)
    $Bg = [System.Drawing.Color]::FromArgb(245,247,250)
    $Card = [System.Drawing.Color]::White
    $Text = [System.Drawing.Color]::FromArgb(30,41,59)
    $Muted = [System.Drawing.Color]::FromArgb(100,116,139)
    $Border = [System.Drawing.Color]::FromArgb(226,232,240)
    $SoftBlue = [System.Drawing.Color]::FromArgb(239,246,255)
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
                $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(191,219,254)
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
        $Grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(219,234,254)
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
            version = '0.3.5'
            profileName = $txtProfileName.Text.Trim()
            policyMode = if ($radEnforce.Checked) {'Enforce'} else {'Audit'}
            wallpaper = $txtWallpaper.Text.Trim()
            allowedPrograms = @(Get-ListItems $lstPrograms)
            allowedWebsites = @(Get-ListItems $lstWebsites)
            protectedShortcuts = @(Get-ListItems $lstShortcuts)
            protections = $protections
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
        $script:settings = Get-UiSettings
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
    $version.Text = 'v0.3.5'
    $version.TextAlign = 'MiddleCenter'
    $version.Location = New-Object System.Drawing.Point(1060,26)
    $version.Size = New-Object System.Drawing.Size(82,30)
    $version.Anchor = 'Top,Right'
    $version.BackColor = [System.Drawing.Color]::FromArgb(30,58,138)
    $version.ForeColor = [System.Drawing.Color]::White
    $version.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $header.Controls.Add($version)

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

    $workspace = New-Object System.Windows.Forms.Panel
    $workspace.Dock = 'Fill'
    $workspace.BackColor = $Bg
    $form.Controls.Add($workspace)
    $workspace.BringToFront()

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    $tabs.Appearance = 'FlatButtons'
    $tabs.SizeMode = 'Fixed'
    $tabs.ItemSize = New-Object System.Drawing.Size(0,1)
    $tabs.Padding = New-Object System.Drawing.Point(0,0)
    $tabs.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $workspace.Controls.Add($tabs)

    $sidebar = New-Object System.Windows.Forms.Panel
    $sidebar.Dock = 'Left'
    $sidebar.Width = 185
    $sidebar.BackColor = [System.Drawing.Color]::White
    $workspace.Controls.Add($sidebar)
    $sidebar.BringToFront()

    $sidebar.Controls.Add((New-Label 'NAVEGACIÓN' 24 18 8 $true $Muted))

    $navHome = New-NavButton 'Inicio' 46
    $navProtection = New-NavButton 'Protección' 92
    $navPrograms = New-NavButton 'Programas' 138
    $navAppControl = New-NavButton 'Control de apps' 184
    $navInternet = New-NavButton 'Internet' 230
    $navDesktop = New-NavButton 'Escritorio' 276
    $navLog = New-NavButton 'Registro' 322

    foreach ($nav in @($navHome,$navProtection,$navPrograms,$navAppControl,$navInternet,$navDesktop,$navLog)) {
        $sidebar.Controls.Add($nav)
    }

    $sideInfo = New-Card 12 392 160 120 $SoftBlue
    $sideInfo.Controls.Add((New-Label 'Aula protegida' 12 12 9 $true $PrimaryDark))
    $sideInfo.Controls.Add((New-Label 'Configura primero' 12 42 8 $false $Muted))
    $sideInfo.Controls.Add((New-Label 'en auditoría y luego' 12 62 8 $false $Muted))
    $sideInfo.Controls.Add((New-Label 'activa la protección.' 12 82 8 $false $Muted))
    $sidebar.Controls.Add($sideInfo)

    function Set-NavActive {
        param($Active)
        foreach ($nav in @($navHome,$navProtection,$navPrograms,$navAppControl,$navInternet,$navDesktop,$navLog)) {
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

    # PROGRAMS
    $tabPrograms = New-Object System.Windows.Forms.TabPage
    $tabPrograms.Text = 'Programas'
    $tabPrograms.BackColor = $Bg
    $tabs.TabPages.Add($tabPrograms)

    $tabPrograms.Controls.Add((New-Label 'Programas permitidos' 24 20 15 $true $Text))
    $tabPrograms.Controls.Add((New-Label 'Agrega únicamente los programas que los estudiantes necesitan para estudiar y trabajar.' 24 52 9 $false $Muted))

    $tipCard = New-Card 24 88 1094 72 $SoftBlue
    $tipCard.Controls.Add((New-Label 'Consejo para el docente' 16 12 9 $true $PrimaryDark))
    $tipCard.Controls.Add((New-Label 'Incluye navegadores, Office, Scratch, Arduino IDE y las aplicaciones educativas utilizadas en clase.' 16 38 9 $false $Text))
    $tabPrograms.Controls.Add($tipCard)

    $lstPrograms = New-Object System.Windows.Forms.ListBox
    $lstPrograms.Location = New-Object System.Drawing.Point(24,184)
    $lstPrograms.Size = New-Object System.Drawing.Size(884,405)
    $lstPrograms.Anchor = 'Top,Left,Right,Bottom'
    $lstPrograms.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $tabPrograms.Controls.Add($lstPrograms)
    Add-ListItems $lstPrograms @($settings.allowedPrograms)

    $btnAddProgram = New-Button 'Agregar programa' 930 184 168 38 'Primary'
    $btnAddProgram.Anchor = 'Top,Right'
    $tabPrograms.Controls.Add($btnAddProgram)

    $btnRemoveProgram = New-Button 'Quitar seleccionado' 930 232 168 38 'Danger'
    $btnRemoveProgram.Anchor = 'Top,Right'
    $tabPrograms.Controls.Add($btnRemoveProgram)

    # APP CONTROL
    $tabAppControl = New-Object System.Windows.Forms.TabPage
    $tabAppControl.Text = 'Control de apps'
    $tabAppControl.BackColor = $Bg
    $tabs.TabPages.Add($tabAppControl)

    $tabAppControl.Controls.Add((New-Label 'Control avanzado de aplicaciones' 24 20 15 $true $Text))
    $tabAppControl.Controls.Add((New-Label 'Primero observa lo que ocurriría. Cuando estés seguro, activa el bloqueo.' 24 52 9 $false $Muted))

    $appSupport = Test-AulaGuardAppLockerSupport
    $supportCard = New-Card 24 88 1094 72 $(if ($appSupport.Supported) {$SoftGreen} else {[System.Drawing.Color]::FromArgb(254,242,242)})
    $supportText = if ($appSupport.Supported) {"AppLocker disponible · Servicio: $($appSupport.ServiceStatus)"} else {'AppLocker no está disponible en este equipo'}
    $supportColor = if ($appSupport.Supported) {$Success} else {$Danger}
    $supportCard.Controls.Add((New-Label $supportText 16 16 10 $true $supportColor))
    $supportCard.Controls.Add((New-Label 'AulaGuard usa este componente de Windows para auditar o bloquear programas.' 16 42 8 $false $Muted))
    $tabAppControl.Controls.Add($supportCard)

    $auditCard = New-Card 24 184 535 118 $SoftBlue
    $radAppAudit = New-Object System.Windows.Forms.RadioButton
    $radAppAudit.Text = 'Modo auditoría'
    $radAppAudit.Location = New-Object System.Drawing.Point(18,18)
    $radAppAudit.AutoSize = $true
    $radAppAudit.Font = New-Object System.Drawing.Font('Segoe UI Semibold',10)
    $auditCard.Controls.Add($radAppAudit)
    $auditCard.Controls.Add((New-Label 'Recomendado para comenzar. No bloquea programas.' 18 50 9 $false $Muted))
    $auditCard.Controls.Add((New-Label 'Registra lo que sería bloqueado.' 18 78 8 $true $PrimaryDark))
    $tabAppControl.Controls.Add($auditCard)

    $blockCard = New-Card 583 184 535 118 $SoftAmber
    $radAppEnforce = New-Object System.Windows.Forms.RadioButton
    $radAppEnforce.Text = 'Modo bloqueo'
    $radAppEnforce.Location = New-Object System.Drawing.Point(18,18)
    $radAppEnforce.AutoSize = $true
    $radAppEnforce.Font = New-Object System.Drawing.Font('Segoe UI Semibold',10)
    $blockCard.Controls.Add($radAppEnforce)
    $blockCard.Controls.Add((New-Label 'Utilízalo solo después de revisar la auditoría.' 18 50 9 $false $Muted))
    $blockCard.Controls.Add((New-Label 'Puede impedir abrir programas no autorizados.' 18 78 8 $true $Warning))
    $tabAppControl.Controls.Add($blockCard)

    if ($settings.appControl.mode -eq 'Enabled') {$radAppEnforce.Checked = $true} else {$radAppAudit.Checked = $true}

    $btnAppPreview = New-Button 'Validar configuración' 24 326 160 36 'Secondary'
    $tabAppControl.Controls.Add($btnAppPreview)

    $btnAppApply = New-Button 'Aplicar control' 194 326 150 36 'Primary'
    $tabAppControl.Controls.Add($btnAppApply)

    $btnAppRestore = New-Button 'Restaurar anterior' 354 326 150 36 'Neutral'
    $tabAppControl.Controls.Add($btnAppRestore)

    $btnAppRefresh = New-Button 'Actualizar eventos' 514 326 150 36 'Neutral'
    $tabAppControl.Controls.Add($btnAppRefresh)

    $tabAppControl.Controls.Add((New-Label 'Actividad reciente' 24 390 11 $true $Text))

    $gridAppEvents = New-Object System.Windows.Forms.DataGridView
    $gridAppEvents.Location = New-Object System.Drawing.Point(24,422)
    $gridAppEvents.Size = New-Object System.Drawing.Size(1094,195)
    $gridAppEvents.Anchor = 'Top,Left,Right,Bottom'
    Style-Grid $gridAppEvents
    [void]$gridAppEvents.Columns.Add('Time','Fecha y hora')
    [void]$gridAppEvents.Columns.Add('Id','Evento')
    [void]$gridAppEvents.Columns.Add('File','Programa')
    [void]$gridAppEvents.Columns.Add('Message','Detalle')
    $gridAppEvents.Columns['Message'].FillWeight = 220
    $tabAppControl.Controls.Add($gridAppEvents)

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
    $navPrograms.Add_Click({$tabs.SelectedTab = $tabPrograms})
    $navAppControl.Add_Click({$tabs.SelectedTab = $tabAppControl})
    $navInternet.Add_Click({$tabs.SelectedTab = $tabWeb})
    $navDesktop.Add_Click({$tabs.SelectedTab = $tabDesktop})
    $navLog.Add_Click({$tabs.SelectedTab = $tabAudit})

    $tabs.Add_SelectedIndexChanged({
        if ($tabs.SelectedTab -eq $tabHome) {Set-NavActive $navHome}
        elseif ($tabs.SelectedTab -eq $tabProtection) {Set-NavActive $navProtection}
        elseif ($tabs.SelectedTab -eq $tabPrograms) {Set-NavActive $navPrograms}
        elseif ($tabs.SelectedTab -eq $tabAppControl) {Set-NavActive $navAppControl}
        elseif ($tabs.SelectedTab -eq $tabWeb) {Set-NavActive $navInternet}
        elseif ($tabs.SelectedTab -eq $tabDesktop) {Set-NavActive $navDesktop}
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

    $btnAddProgram.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = 'Aplicaciones (*.exe)|*.exe'
        $d.Multiselect = $true
        if ($d.ShowDialog() -eq 'OK') {
            foreach ($f in $d.FileNames) {
                if ($lstPrograms.Items -notcontains $f) {
                    [void]$lstPrograms.Items.Add($f)
                }
            }
            Refresh-Dashboard
            Set-Status 'Programas agregados' 'Success'
        }
    })

    $btnRemoveProgram.Add_Click({
        while ($lstPrograms.SelectedIndices.Count -gt 0) {
            $lstPrograms.Items.RemoveAt($lstPrograms.SelectedIndices[0])
        }
        Refresh-Dashboard
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

    $btnSave.Add_Click({
        Save-FromUi
        Refresh-Dashboard
    })

    $btnApply.Add_Click({
        Save-FromUi
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
            $r = @(Reset-AulaGuardPolicies)
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

    Set-NavActive $navHome
    Write-AulaGuardAudit -Action 'APP_STARTED' -Detail 'v0.3.5' -Root $root
    Refresh-Dashboard
    & $loadAudit
    & $loadAppEvents

    $form.Add_FormClosed({
        try {
            Write-AulaGuardAudit -Action 'APP_CLOSED' -Root $root
        } catch {}
    })

    # Exercise full WinForms construction in CI without requiring a human to close it.
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
