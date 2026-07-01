param(
    [switch]$Dump,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $compiledScriptRoot = Get-Variable -Name ScriptRoot -ErrorAction SilentlyContinue
    if ($null -ne $compiledScriptRoot -and -not [string]::IsNullOrWhiteSpace([string]$compiledScriptRoot.Value)) {
        $scriptRoot = [string]$compiledScriptRoot.Value
    }
}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\')
}

$modulePath = Join-Path $scriptRoot 'TokenUsage.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    $modulePath = Join-Path (Join-Path $scriptRoot 'src') 'TokenUsage.psm1'
}
Import-Module $modulePath -Force

$script:SettingsPath = Get-TokenMonitorSettingsPath
$script:Settings = Read-TokenMonitorSettings -Path $script:SettingsPath

function Format-ProviderHealthCell {
    param($Provider)

    if (-not (Get-Member -InputObject $Provider -Name HealthText -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        return 'n/a'
    }

    $text = [string]$Provider.HealthText
    if (Get-Member -InputObject $Provider -Name HealthWindow -MemberType NoteProperty -ErrorAction SilentlyContinue) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Provider.HealthWindow) -and
            $null -ne $Provider.HealthPercent) {
            $text += (' ({0} {1})' -f $Provider.HealthWindow, (Format-Percent $Provider.HealthPercent))
        }
    }
    return $text
}

function Write-Snapshot {
    param($Snapshot)

    foreach ($provider in @($Snapshot.Providers)) {
        $fiveHourUsed = Format-TokenCount $provider.FiveHourUsed
        $weeklyUsed = Format-TokenCount $provider.WeeklyUsed
        if (Get-Member -InputObject $provider -Name FiveHourUsedDisplay -MemberType NoteProperty -ErrorAction SilentlyContinue) {
            $fiveHourUsed = $provider.FiveHourUsedDisplay
        }
        if (Get-Member -InputObject $provider -Name WeeklyUsedDisplay -MemberType NoteProperty -ErrorAction SilentlyContinue) {
            $weeklyUsed = $provider.WeeklyUsedDisplay
        }

        $health = Format-ProviderHealthCell -Provider $provider
        $line = '{0}: {1}, 5h {2}/{3} ({4} left, reset {5}), 7d {6}/{7} ({8} left, reset {9}), files {10}, events {11}, {12}' -f `
            $provider.Name,
            $health,
            $fiveHourUsed,
            (Format-TokenCount $provider.FiveHourLimit),
            (Format-Percent $provider.FiveHourRemainingPercent),
            (Format-ResetHours $provider.FiveHourResetHours),
            $weeklyUsed,
            (Format-TokenCount $provider.WeeklyLimit),
            (Format-Percent $provider.WeeklyRemainingPercent),
            (Format-ResetHours $provider.WeeklyResetHours),
            $provider.Files,
            $provider.Events,
            $provider.Status
        Write-Output $line
    }
}

if ($SelfTest -or $Dump) {
    $snapshot = Get-TokenUsageSnapshot -Settings $script:Settings
    Write-Snapshot -Snapshot $snapshot
    if ($SelfTest) {
        Write-Output "Settings: $script:SettingsPath"
    }
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Enable-HighDpiSupport {
    try {
        $typeSuffix = Get-Random
        $signature = @"
[System.Runtime.InteropServices.DllImport("shcore.dll")]
public static extern int SetProcessDpiAwareness(int value);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
"@
        $dpi = Add-Type -MemberDefinition $signature -Name "DpiUtils_$typeSuffix" -Namespace "Win32" -PassThru
        try {
            # PROCESS_PER_MONITOR_DPI_AWARE keeps WinForms and ToolStrip menus crisp on scaled displays.
            [void]$dpi::SetProcessDpiAwareness(2)
        }
        catch {
            [void]$dpi::SetProcessDPIAware()
        }
    }
    catch {
        try {
            $loadedTypes = [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetTypes() } | Where-Object { $_.FullName -like 'Win32.DpiUtils_*' }
            if ($loadedTypes) {
                try { [void]$loadedTypes[0]::SetProcessDpiAwareness(2) } catch { [void]$loadedTypes[0]::SetProcessDPIAware() }
            }
        }
        catch {}
    }
}

$script:User32 = $null
try {
    $typeSuffix = Get-Random
    $signature = @"
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern bool DestroyIcon(IntPtr handle);
"@
    $script:User32 = Add-Type -MemberDefinition $signature -Name "User32Utils_$typeSuffix" -Namespace "Win32" -PassThru
}
catch {
    $loadedTypes = [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetTypes() } | Where-Object { $_.FullName -like 'Win32.User32Utils_*' }
    if ($loadedTypes) {
        $script:User32 = $loadedTypes[0]
    }
}

$script:DwmApi = $null
try {
    $typeSuffix = Get-Random
    $signature = @"
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@
    $script:DwmApi = Add-Type -MemberDefinition $signature -Name "DwmApiUtils_$typeSuffix" -Namespace "Win32" -PassThru
}
catch {
    $loadedTypes = [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetTypes() } | Where-Object { $_.FullName -like 'Win32.DwmApiUtils_*' }
    if ($loadedTypes) {
        $script:DwmApi = $loadedTypes[0]
    }
}

function Set-ImmersiveDarkMode {
    param([IntPtr]$Hwnd)

    if ($null -ne $script:DwmApi) {
        $trueValue = 1
        [void]$script:DwmApi::DwmSetWindowAttribute($Hwnd, 20, [ref]$trueValue, 4)
        [void]$script:DwmApi::DwmSetWindowAttribute($Hwnd, 19, [ref]$trueValue, 4)
    }
}

Enable-HighDpiSupport
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:UiScale = 1.0
try {
    $screenGraphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:UiScale = [Math]::Max(1.0, [double]$screenGraphics.DpiX / 96.0)
    $screenGraphics.Dispose()
}
catch {
    $script:UiScale = 1.0
}

# Sleek Modern Dark Theme Color Palette
$script:Colors = @{
    Background       = [System.Drawing.ColorTranslator]::FromHtml('#1e1e2e')
    PanelBackground  = [System.Drawing.ColorTranslator]::FromHtml('#181825')
    HeaderBackground = [System.Drawing.ColorTranslator]::FromHtml('#11111b')
    Text             = [System.Drawing.ColorTranslator]::FromHtml('#cdd6f4')
    TextDim          = [System.Drawing.ColorTranslator]::FromHtml('#a6adc8')
    Accent           = [System.Drawing.ColorTranslator]::FromHtml('#3572F6') # Vibrant Blue
    AccentHover      = [System.Drawing.ColorTranslator]::FromHtml('#4C8BF5')
    Border           = [System.Drawing.ColorTranslator]::FromHtml('#313244')
    GridLine         = [System.Drawing.ColorTranslator]::FromHtml('#313244')
    RowHover         = [System.Drawing.ColorTranslator]::FromHtml('#313244')
}

# Resolve and Load Icon
$script:AppIcon = $null
try {
    $currentExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($currentExePath -like '*TokenMonitor.exe') {
        $script:AppIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($currentExePath)
    } else {
        $devIco = Join-Path $scriptRoot 'token-monitor.ico'
        if (-not (Test-Path -LiteralPath $devIco)) {
            $devIco = Join-Path (Join-Path $scriptRoot 'src') 'token-monitor.ico'
        }
        if (Test-Path -LiteralPath $devIco) {
            $script:AppIcon = New-Object System.Drawing.Icon($devIco)
        }
    }
}
catch {}
if ($null -eq $script:AppIcon) {
    $script:AppIcon = [System.Drawing.SystemIcons]::Information
}

function Style-ModernForm {
    param(
        [System.Windows.Forms.Form]$Form
    )

    $Form.BackColor = $script:Colors.Background
    $Form.ForeColor = $script:Colors.Text
    $Form.Icon = $script:AppIcon
    $Form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $Form.Add_HandleCreated({
        Set-ImmersiveDarkMode -Hwnd $this.Handle
    })
}

function Style-FlatButton {
    param(
        [System.Windows.Forms.Button]$Button,
        [switch]$IsPrimary
    )

    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $Button.ForeColor = [System.Drawing.Color]::White

    if ($IsPrimary) {
        $Button.BackColor = $script:Colors.Accent
        $Button.Add_MouseEnter({ $this.BackColor = $script:Colors.AccentHover })
        $Button.Add_MouseLeave({ $this.BackColor = $script:Colors.Accent })
    } else {
        $Button.BackColor = $script:Colors.Border
        $Button.Add_MouseEnter({ $this.BackColor = $script:Colors.RowHover })
        $Button.Add_MouseLeave({ $this.BackColor = $script:Colors.Border })
    }
}

function Style-DataGridView {
    param(
        [System.Windows.Forms.DataGridView]$Grid
    )

    $Grid.BackgroundColor = $script:Colors.Background
    $Grid.ForeColor = $script:Colors.Text
    $Grid.GridColor = $script:Colors.GridLine
    $Grid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $Grid.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
    $Grid.ColumnHeadersBorderStyle = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::None
    $Grid.EnableHeadersVisualStyles = $false

    $Grid.ColumnHeadersDefaultCellStyle.BackColor = $script:Colors.HeaderBackground
    $Grid.ColumnHeadersDefaultCellStyle.ForeColor = $script:Colors.TextDim
    $Grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = $script:Colors.HeaderBackground
    $Grid.ColumnHeadersDefaultCellStyle.SelectionForeColor = $script:Colors.TextDim
    $Grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $Grid.ColumnHeadersHeight = Scale-UiValue 32

    $Grid.DefaultCellStyle.BackColor = $script:Colors.Background
    $Grid.DefaultCellStyle.ForeColor = $script:Colors.Text
    $Grid.DefaultCellStyle.SelectionBackColor = $script:Colors.RowHover
    $Grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $Grid.DefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $Grid.RowTemplate.Height = Scale-UiValue 30
}

function Scale-UiValue {
    param([double]$Value)

    return [int][Math]::Round($Value * $script:UiScale)
}

function New-UiSize {
    param(
        [double]$Width,
        [double]$Height
    )

    return (New-Object System.Drawing.Size((Scale-UiValue $Width), (Scale-UiValue $Height)))
}

$script:Snapshot = $null
$script:DashboardForm = $null
$script:SettingsForm = $null
$script:Grid = $null
$script:StatusLabel = $null
$script:NotifyIcon = $null
$script:ContextMenu = $null
$script:RefreshTimer = $null
$script:AppContext = New-Object System.Windows.Forms.ApplicationContext
$script:SingleInstanceMutex = $null
$script:SingleInstanceMutexHeld = $false

function Initialize-SingleInstance {
    $createdNew = $false
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $userKey = if ($null -ne $identity -and $null -ne $identity.User) {
        $identity.User.Value
    } else {
        [Environment]::UserName
    }
    $userKey = $userKey -replace '[^A-Za-z0-9]', '_'
    $mutexName = "Local\TokenMonitor_$userKey"

    $script:SingleInstanceMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
    $script:SingleInstanceMutexHeld = [bool]$createdNew
    if (-not $script:SingleInstanceMutexHeld) {
        exit 0
    }
}

function Release-SingleInstance {
    if ($script:SingleInstanceMutexHeld -and $null -ne $script:SingleInstanceMutex) {
        try { $script:SingleInstanceMutex.ReleaseMutex() } catch {}
        $script:SingleInstanceMutexHeld = $false
    }
    if ($null -ne $script:SingleInstanceMutex) {
        $script:SingleInstanceMutex.Dispose()
        $script:SingleInstanceMutex = $null
    }
}

Initialize-SingleInstance

function New-MenuItem {
    param(
        [string]$Text,
        [scriptblock]$OnClick
    )

    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = $Text
    $item.Add_Click($OnClick)
    return $item
}

function Format-DateCell {
    param($Value)

    if ($null -eq $Value) {
        return ''
    }
    return ([DateTime]$Value).ToString('yyyy-MM-dd HH:mm')
}

function Get-StatusStripText {
    param($Snapshot)

    if ($null -eq $Snapshot) {
        return 'TokenMonitor loading'
    }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($provider in @($Snapshot.Providers)) {
        if (-not $provider.Enabled) {
            continue
        }

        $name = switch ($provider.Id) {
            'antigravity' { 'Ag' }
            'codex' { 'Cdx' }
            'claude' { 'Claude' }
            default { $provider.Name }
        }

        $health = Format-ProviderHealthCell -Provider $provider
        $parts.Add(('{0} {1}' -f $name, $health))
        $parts.Add(('{0} 5h {1}, reset {2}' -f $name, (Format-Percent $provider.FiveHourRemainingPercent), (Format-ResetHours $provider.FiveHourResetHours)))
        $parts.Add(('{0} 7d {1}, reset {2}' -f $name, (Format-Percent $provider.WeeklyRemainingPercent), (Format-ResetHours $provider.WeeklyResetHours)))
        if ((Get-Member -InputObject $provider -Name IsEstimatedFromCache -MemberType NoteProperty -ErrorAction SilentlyContinue) -and
            $provider.IsEstimatedFromCache -and
            (Get-Member -InputObject $provider -Name LastVisibleLocal -MemberType NoteProperty -ErrorAction SilentlyContinue) -and
            $null -ne $provider.LastVisibleLocal) {
            $parts.Add(('{0} last seen {1}' -f $name, ([DateTime]$provider.LastVisibleLocal).ToString('HH:mm')))
        }
    }

    if ($parts.Count -eq 0) {
        return 'TokenMonitor n/a'
    }
    return ($parts -join [Environment]::NewLine)
}

function Get-HealthStateColor {
    param($HealthState)

    switch ([string]$HealthState) {
        'empty' { return [System.Drawing.ColorTranslator]::FromHtml('#f38ba8') }
        'low' { return [System.Drawing.ColorTranslator]::FromHtml('#fab387') }
        'medium' { return [System.Drawing.ColorTranslator]::FromHtml('#f9e2af') }
        'good' { return [System.Drawing.ColorTranslator]::FromHtml('#a6e3a1') }
        'disabled' { return [System.Drawing.ColorTranslator]::FromHtml('#585b70') }
        default { return [System.Drawing.ColorTranslator]::FromHtml('#a6adc8') }
    }
}

function Update-DynamicTrayIcon {
    param(
        [object]$Snapshot
    )

    if ($null -eq $script:NotifyIcon) {
        return
    }

    # Find all enabled providers
    $enabledProviders = @()
    if ($null -ne $Snapshot) {
        $enabledProviders = @($Snapshot.Providers) | Where-Object { $_.Enabled }
    }

    # Scale the bitmap size according to UI scaling to prevent blurry icons on high DPI
    $size = [int](16 * $script:UiScale)
    if ($size -lt 16) { $size = 16 }

    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $margin = 2.0 * $script:UiScale
    $penWidth = 2.2 * $script:UiScale
    $drawSize = $size - (2.0 * $margin)

    if ($enabledProviders.Count -eq 0) {
        # If no providers or loading, draw our beautiful default application icon or a scaled neutral gray ring
        if ($null -ne $script:AppIcon -and $script:AppIcon -ne [System.Drawing.SystemIcons]::Information) {
            $g.DrawIcon($script:AppIcon, 0, 0)
        } else {
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(100, 100, 100)), $penWidth
            $g.DrawEllipse($pen, $margin, $margin, $drawSize, $drawSize)
            $pen.Dispose()
        }
    }
    else {
        # Divide 360 degrees among enabled providers
        $count = $enabledProviders.Count
        $anglePerProvider = 360.0 / $count
        # Gap size between segments (in degrees)
        $gap = if ($count -gt 1) { 15.0 } else { 0.0 }
        $sweepAngle = $anglePerProvider - $gap

        # Start drawing from the top (270 degrees)
        $startAngle = 270.0

        foreach ($provider in $enabledProviders) {
            $color = Get-HealthStateColor -HealthState $provider.HealthState

            # Draw the segment
            $pen = New-Object System.Drawing.Pen $color, $penWidth
            $g.DrawArc($pen, $margin, $margin, $drawSize, $drawSize, $startAngle, $sweepAngle)
            $pen.Dispose()

            # Advance to the next provider segment
            $startAngle += $anglePerProvider
        }
    }

    # Convert to Icon
    $hIcon = $bmp.GetHicon()
    $newIcon = [System.Drawing.Icon]::FromHandle($hIcon)

    $oldIcon = $script:NotifyIcon.Icon
    $script:NotifyIcon.Icon = $newIcon

    # Clean up old icon and bitmaps
    if ($null -ne $oldIcon -and $oldIcon -ne $script:AppIcon) {
        $oldIcon.Dispose()
    }
    $g.Dispose()
    $bmp.Dispose()

    if ($null -ne $script:User32) {
        [void]$script:User32::DestroyIcon($hIcon)
    }
}

function Update-DashboardGrid {
    if ($null -eq $script:Grid -or $null -eq $script:Snapshot) {
        return
    }

    $script:Grid.Rows.Clear()
    foreach ($provider in @($script:Snapshot.Providers)) {
        [void]$script:Grid.Rows.Add(
            $provider.Name,
            (Format-ProviderHealthCell -Provider $provider),
            (Format-Percent $provider.FiveHourRemainingPercent),
            (Format-ResetHours $provider.FiveHourResetHours),
            (Format-Percent $provider.WeeklyRemainingPercent),
            (Format-ResetHours $provider.WeeklyResetHours),
            (Format-DateCell $provider.LastEventLocal),
            $provider.Status
        )

        $row = $script:Grid.Rows[$script:Grid.Rows.Count - 1]
        $row.DefaultCellStyle.ForeColor = Get-HealthStateColor -HealthState $provider.HealthState
    }

    if ($null -ne $script:StatusLabel) {
        $script:StatusLabel.Text = 'Updated: ' + $script:Snapshot.GeneratedAtLocal.ToString('yyyy-MM-dd HH:mm:ss')
    }
}

function Refresh-Usage {
    try {
        $script:Settings = Read-TokenMonitorSettings -Path $script:SettingsPath
        $script:Snapshot = Get-TokenUsageSnapshot -Settings $script:Settings
        if ($null -ne $script:NotifyIcon) {
            $script:NotifyIcon.Text = Format-TokenUsageTooltip -Snapshot $script:Snapshot
            Update-DynamicTrayIcon -Snapshot $script:Snapshot
        }
        Update-DashboardGrid
    }
    catch {
        if ($null -ne $script:NotifyIcon) {
            $script:NotifyIcon.Text = 'TokenMonitor refresh failed'
            $script:NotifyIcon.ShowBalloonTip(3000, 'TokenMonitor', $_.Exception.Message, [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    }
}

function Request-UsageRefresh {
    if ($null -ne $script:StatusLabel) {
        $script:StatusLabel.Text = 'Refreshing...'
    }

    if ($null -ne $script:DashboardForm -and -not $script:DashboardForm.IsDisposed) {
        [void]$script:DashboardForm.BeginInvoke([System.Action]{ Refresh-Usage })
        return
    }

    Refresh-Usage
}

function Show-Dashboard {
    if ($null -ne $script:DashboardForm -and -not $script:DashboardForm.IsDisposed) {
        $script:DashboardForm.Show()
        $script:DashboardForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $script:DashboardForm.Activate()
        $script:DashboardForm.Refresh()
        Request-UsageRefresh
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'TokenMonitor'
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.Size = New-UiSize 900 420
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-UiSize 760 320
    Style-ModernForm -Form $form

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Top'
    $panel.Height = Scale-UiValue 44
    $panel.BackColor = $script:Colors.PanelBackground

    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = 'Refresh'
    $refreshButton.Width = Scale-UiValue 90
    $refreshButton.Height = Scale-UiValue 28
    $refreshButton.Left = Scale-UiValue 12
    $refreshButton.Top = Scale-UiValue 8
    $refreshButton.Add_Click({ Refresh-Usage })
    Style-FlatButton -Button $refreshButton -IsPrimary
    $panel.Controls.Add($refreshButton)

    $settingsButton = New-Object System.Windows.Forms.Button
    $settingsButton.Text = 'Settings'
    $settingsButton.Width = Scale-UiValue 90
    $settingsButton.Height = Scale-UiValue 28
    $settingsButton.Left = Scale-UiValue 112
    $settingsButton.Top = Scale-UiValue 8
    $settingsButton.Add_Click({ Show-Settings })
    Style-FlatButton -Button $settingsButton
    $panel.Controls.Add($settingsButton)

    $openConfigButton = New-Object System.Windows.Forms.Button
    $openConfigButton.Text = 'Open config'
    $openConfigButton.Width = Scale-UiValue 100
    $openConfigButton.Height = Scale-UiValue 28
    $openConfigButton.Left = Scale-UiValue 212
    $openConfigButton.Top = Scale-UiValue 8
    $openConfigButton.Add_Click({ Invoke-Item -LiteralPath $script:SettingsPath })
    Style-FlatButton -Button $openConfigButton
    $panel.Controls.Add($openConfigButton)

    $status = New-Object System.Windows.Forms.Label
    $status.AutoSize = $true
    $status.Left = Scale-UiValue 330
    $status.Top = Scale-UiValue 14
    $status.Text = 'Updated: never'
    $status.ForeColor = $script:Colors.TextDim
    $panel.Controls.Add($status)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    Style-DataGridView -Grid $grid

    foreach ($column in @(
        @('Provider', 'Provider'),
        @('Health', 'Health'),
        @('FiveHour', '5h quota'),
        @('FiveHourReset', '5h reset'),
        @('Weekly', '7d quota'),
        @('WeeklyReset', '7d reset'),
        @('LastEvent', 'Last update'),
        @('Status', 'Status')
    )) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $column[0]
        $col.HeaderText = $column[1]
        [void]$grid.Columns.Add($col)
    }

    $form.Controls.Add($grid)
    $form.Controls.Add($panel)
    $form.Add_FormClosing({
        if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $_.Cancel = $true
            $this.Hide()
        }
    })

    $script:DashboardForm = $form
    $script:Grid = $grid
    $script:StatusLabel = $status
    $form.Show()
    $form.Activate()
    $form.Refresh()
    Request-UsageRefresh
}

function Parse-LongCell {
    param($Value)

    $text = [string]$Value
    $result = 0L
    if ([int64]::TryParse($text, [ref]$result)) {
        return $result
    }
    return 0L
}

function Split-CellList {
    param($Value)

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }
    return @($text -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Show-Settings {
    if ($null -ne $script:SettingsForm -and -not $script:SettingsForm.IsDisposed) {
        $script:SettingsForm.Show()
        $script:SettingsForm.Activate()
        return
    }

    $settings = Read-TokenMonitorSettings -Path $script:SettingsPath

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'TokenMonitor Settings'
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.Size = New-UiSize 1040 420
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-UiSize 900 320
    Style-ModernForm -Form $form

    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = 'Top'
    $top.Height = Scale-UiValue 42
    $top.BackColor = $script:Colors.PanelBackground

    $refreshLabel = New-Object System.Windows.Forms.Label
    $refreshLabel.Text = 'Refresh seconds'
    $refreshLabel.AutoSize = $true
    $refreshLabel.Left = Scale-UiValue 12
    $refreshLabel.Top = Scale-UiValue 13
    $refreshLabel.ForeColor = $script:Colors.Text
    $top.Controls.Add($refreshLabel)

    $refreshInput = New-Object System.Windows.Forms.NumericUpDown
    $refreshInput.Minimum = 10
    $refreshInput.Maximum = 3600
    $refreshInput.Value = [decimal]([Math]::Max(10, [int]$settings.RefreshSeconds))
    $refreshInput.Left = Scale-UiValue 118
    $refreshInput.Top = Scale-UiValue 9
    $refreshInput.Width = Scale-UiValue 80
    $refreshInput.BackColor = $script:Colors.Background
    $refreshInput.ForeColor = $script:Colors.Text
    $top.Controls.Add($refreshInput)

    $maxFileLabel = New-Object System.Windows.Forms.Label
    $maxFileLabel.Text = 'Max file MB'
    $maxFileLabel.AutoSize = $true
    $maxFileLabel.Left = Scale-UiValue 218
    $maxFileLabel.Top = Scale-UiValue 13
    $maxFileLabel.ForeColor = $script:Colors.Text
    $top.Controls.Add($maxFileLabel)

    $maxFileInput = New-Object System.Windows.Forms.NumericUpDown
    $maxFileInput.Minimum = 1
    $maxFileInput.Maximum = 2048
    $maxFileInput.Value = [decimal]([Math]::Max(1, [int]$settings.MaxFileSizeMB))
    $maxFileInput.Left = Scale-UiValue 298
    $maxFileInput.Top = Scale-UiValue 9
    $maxFileInput.Width = Scale-UiValue 70
    $maxFileInput.BackColor = $script:Colors.Background
    $maxFileInput.ForeColor = $script:Colors.Text
    $top.Controls.Add($maxFileInput)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Use semicolon-separated roots. Quotas are token counts; 0 means unknown.'
    $hint.AutoSize = $true
    $hint.Left = Scale-UiValue 388
    $hint.Top = Scale-UiValue 13
    $hint.ForeColor = $script:Colors.TextDim
    $top.Controls.Add($hint)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    Style-DataGridView -Grid $grid

    $enabledCol = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $enabledCol.Name = 'Enabled'
    $enabledCol.HeaderText = 'Enabled'
    $enabledCol.FillWeight = 45
    [void]$grid.Columns.Add($enabledCol)

    foreach ($column in @(
        @('Id', 'Id', 65, $true),
        @('Name', 'Name', 120, $false),
        @('FiveHourLimit', '5h quota', 80, $false),
        @('WeeklyLimit', '7d quota', 80, $false),
        @('ScanRoots', 'Scan roots', 260, $false),
        @('FilePatterns', 'File patterns', 90, $false),
        @('Command', 'Command JSON source', 190, $false),
        @('CommandTimeoutSeconds', 'Cmd timeout', 70, $false)
    )) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $column[0]
        $col.HeaderText = $column[1]
        $col.FillWeight = $column[2]
        $col.ReadOnly = [bool]$column[3]
        [void]$grid.Columns.Add($col)
    }

    foreach ($provider in @($settings.Providers)) {
        [void]$grid.Rows.Add(
            [bool]$provider.Enabled,
            [string]$provider.Id,
            [string]$provider.Name,
            [string]$provider.FiveHourLimit,
            [string]$provider.WeeklyLimit,
            (@($provider.ScanRoots) -join '; '),
            (@($provider.FilePatterns) -join '; '),
            [string]$provider.Command,
            [string]$provider.CommandTimeoutSeconds
        )
    }

    $bottom = New-Object System.Windows.Forms.Panel
    $bottom.Dock = 'Bottom'
    $bottom.Height = Scale-UiValue 48
    $bottom.BackColor = $script:Colors.PanelBackground

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = 'Save'
    $saveButton.Width = Scale-UiValue 90
    $saveButton.Height = Scale-UiValue 28
    $saveButton.Left = Scale-UiValue 12
    $saveButton.Top = Scale-UiValue 10
    $saveButton.Add_Click({
        $grid.EndEdit()

        $providers = New-Object System.Collections.Generic.List[object]
        foreach ($row in $grid.Rows) {
            if ($row.IsNewRow) {
                continue
            }
            $providers.Add([ordered]@{
                Id = [string]$row.Cells['Id'].Value
                Name = [string]$row.Cells['Name'].Value
                Enabled = [bool]$row.Cells['Enabled'].Value
                FiveHourLimit = (Parse-LongCell $row.Cells['FiveHourLimit'].Value)
                WeeklyLimit = (Parse-LongCell $row.Cells['WeeklyLimit'].Value)
                ScanRoots = @(Split-CellList $row.Cells['ScanRoots'].Value)
                FilePatterns = @(Split-CellList $row.Cells['FilePatterns'].Value)
                Command = [string]$row.Cells['Command'].Value
                CommandTimeoutSeconds = [int](Parse-LongCell $row.Cells['CommandTimeoutSeconds'].Value)
            })
        }

        $newSettings = [ordered]@{
            RefreshSeconds = [int]$refreshInput.Value
            MaxFileSizeMB = [int]$maxFileInput.Value
            ShowStatusStrip = [bool]$settings.ShowStatusStrip
            Providers = @($providers.ToArray())
        }

        Save-TokenMonitorSettings -Settings $newSettings -Path $script:SettingsPath
        $script:Settings = Read-TokenMonitorSettings -Path $script:SettingsPath
        Refresh-Usage
        $form.Close()
    }.GetNewClosure())
    Style-FlatButton -Button $saveButton -IsPrimary
    $bottom.Controls.Add($saveButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Cancel'
    $cancelButton.Width = Scale-UiValue 90
    $cancelButton.Height = Scale-UiValue 28
    $cancelButton.Left = Scale-UiValue 112
    $cancelButton.Top = Scale-UiValue 10
    $cancelButton.Add_Click({
        $this.FindForm().Close()
    })
    Style-FlatButton -Button $cancelButton
    $bottom.Controls.Add($cancelButton)

    $openButton = New-Object System.Windows.Forms.Button
    $openButton.Text = 'Open config'
    $openButton.Width = Scale-UiValue 100
    $openButton.Height = Scale-UiValue 28
    $openButton.Left = Scale-UiValue 212
    $openButton.Top = Scale-UiValue 10
    $openButton.Add_Click({ Invoke-Item -LiteralPath $script:SettingsPath })
    Style-FlatButton -Button $openButton
    $bottom.Controls.Add($openButton)

    $form.Controls.Add($grid)
    $form.Controls.Add($top)
    $form.Controls.Add($bottom)
    $form.Add_FormClosing({
        if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $script:SettingsForm = $null
        }
    })

    $script:SettingsForm = $form
    $form.Show()
    $form.Activate()
}

function Dispose-TokenMonitorResources {
    if ($null -ne $script:RefreshTimer) {
        try { $script:RefreshTimer.Stop() } catch {}
        try { $script:RefreshTimer.Dispose() } catch {}
        $script:RefreshTimer = $null
    }
    if ($null -ne $script:DashboardForm -and -not $script:DashboardForm.IsDisposed) {
        try { $script:DashboardForm.Dispose() } catch {}
    }
    if ($null -ne $script:SettingsForm -and -not $script:SettingsForm.IsDisposed) {
        try { $script:SettingsForm.Dispose() } catch {}
    }
    if ($null -ne $script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        try { $script:NotifyIcon.Dispose() } catch {}
        $script:NotifyIcon = $null
    }
    if ($null -ne $script:ContextMenu) {
        try { $script:ContextMenu.Dispose() } catch {}
        $script:ContextMenu = $null
    }
}

function Exit-TokenMonitor {
    Dispose-TokenMonitorResources
    $script:AppContext.ExitThread()
}

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$contextMenu.ImageScalingSize = New-UiSize 16 16
$contextMenu.Padding = New-Object System.Windows.Forms.Padding((Scale-UiValue 2))
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Dashboard' -OnClick { Show-Dashboard }))
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Refresh now' -OnClick { Refresh-Usage }))
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Settings' -OnClick { Show-Settings }))
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Open config' -OnClick { Invoke-Item -LiteralPath $script:SettingsPath }))
[void]$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Exit' -OnClick { Exit-TokenMonitor }))
$script:ContextMenu = $contextMenu

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = $script:AppIcon
$notify.Visible = $true
$notify.ContextMenuStrip = $contextMenu
$notify.Text = 'TokenMonitor'
$notify.Add_DoubleClick({ Show-Dashboard })
$script:NotifyIcon = $notify

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [Math]::Max(10, [int]$script:Settings.RefreshSeconds) * 1000
$timer.Add_Tick({
    $timer.Interval = [Math]::Max(10, [int]$script:Settings.RefreshSeconds) * 1000
    Refresh-Usage
})
$timer.Start()
$script:RefreshTimer = $timer

Refresh-Usage
try {
    [System.Windows.Forms.Application]::Run($script:AppContext)
}
finally {
    Dispose-TokenMonitorResources
    Release-SingleInstance
}
