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

function Open-TokenMonitorConfigFile {
    $path = if (-not [string]::IsNullOrWhiteSpace($script:SettingsPath)) { $script:SettingsPath } else { Get-TokenMonitorSettingsPath }
    Invoke-Item -LiteralPath $path
}

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

# md2doc-style palette: native widgets on a soft gray background with state-tinted rows
$script:Colors = @{
    Background = [System.Drawing.ColorTranslator]::FromHtml('#f8f9fa')
    Text       = [System.Drawing.ColorTranslator]::FromHtml('#212529')
    TextDim    = [System.Drawing.ColorTranslator]::FromHtml('#666666')
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
    $Form.Icon = $script:AppIcon
    $Form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
}

function Style-FlatButton {
    param(
        [System.Windows.Forms.Button]$Button,
        [switch]$IsPrimary
    )
    # Native Windows buttons (standard visual styles)
}

function Style-DataGridView {
    param(
        [System.Windows.Forms.DataGridView]$Grid
    )

    # Native header rendering, white background, comfortable row height
    $Grid.EnableHeadersVisualStyles = $true
    $Grid.BackgroundColor = [System.Drawing.Color]::White
    $Grid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $Grid.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
    $Grid.GridColor = [System.Drawing.ColorTranslator]::FromHtml('#e9ecef')
    $Grid.ColumnHeadersHeight = Scale-UiValue 28
    $Grid.ColumnHeadersDefaultCellStyle.Alignment = 'MiddleCenter'
    $Grid.RowTemplate.Height = Scale-UiValue 28

    # Disable selection highlight (grid is read-only / for display only)
    $Grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::White
    $Grid.DefaultCellStyle.SelectionForeColor = $script:Colors.Text
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

function Format-GuiResetHours {
    param(
        $Value,
        $Snapshot,
        [switch]$IsWeekly
    )

    $formatted = Format-ResetHours $Value
    if ($null -eq $Value -or $Value -le 0.05) {
        return $formatted
    }

    $baseTime = [DateTime]::Now
    if ($null -ne $Snapshot -and $null -ne $Snapshot.GeneratedAtLocal) {
        $baseTime = $Snapshot.GeneratedAtLocal
    }

    $estTime = $baseTime.AddHours([double]$Value)
    if ($IsWeekly) {
        $days = [int][Math]::Floor([double]$Value / 24)
        $hours = [double]$Value % 24
        $estString = $estTime.ToString('MM-dd HH:mm')
        return ('{0}d {1:00.0}h ({2})' -f $days, $hours, $estString)
    } else {
        $estString = $estTime.ToString('HH:mm')
        return "$formatted ($estString)"
    }
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
        'empty' { return [System.Drawing.ColorTranslator]::FromHtml('#dc3545') }  # Red
        'low' { return [System.Drawing.ColorTranslator]::FromHtml('#ea580c') }    # Orange
        'medium' { return [System.Drawing.ColorTranslator]::FromHtml('#ca8a04') } # Yellow
        'good' { return [System.Drawing.ColorTranslator]::FromHtml('#16a34a') }   # Green
        'disabled' { return [System.Drawing.ColorTranslator]::FromHtml('#6c757d') }# Gray
        default { return [System.Drawing.ColorTranslator]::FromHtml('#475569') }  # Slate
    }
}

function Get-HealthStateBackColor {
    param($HealthState)

    switch ([string]$HealthState) {
        'empty' { return [System.Drawing.ColorTranslator]::FromHtml('#ffebee') }  # Light red
        'low' { return [System.Drawing.ColorTranslator]::FromHtml('#fff3e0') }    # Light orange
        'medium' { return [System.Drawing.ColorTranslator]::FromHtml('#fef3c7') } # Light yellow
        'good' { return [System.Drawing.ColorTranslator]::FromHtml('#e8f5e9') }   # Light green
        'disabled' { return [System.Drawing.ColorTranslator]::FromHtml('#f8f9fa') }# Light gray
        default { return [System.Drawing.ColorTranslator]::FromHtml('#f8f9fa') }  # Soft gray
    }
}

function Update-DynamicTrayIcon {
    param(
        [object]$Snapshot
    )

    if ($null -eq $script:NotifyIcon) {
        return
    }

    # Find all enabled providers (matches Format-TokenUsageTooltip ordering)
    $enabledProviders = @()
    if ($null -ne $Snapshot) {
        $enabledProviders = @($Snapshot.Providers) | Where-Object { $_.Enabled }
    }

    # Scale the bitmap size according to UI scaling to prevent blurry icons on high DPI
    $targetSize = 16
    try {
        $targetSize = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
    } catch {}
    $scaledSize = [int][Math]::Round(16 * $script:UiScale)
    $size = [Math]::Max(16, [Math]::Max($targetSize, $scaledSize))

    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $g.Clear([System.Drawing.Color]::Transparent)

    if ($enabledProviders.Count -eq 0) {
        # If no providers or loading, draw application icon or neutral placeholder
        if ($null -ne $script:AppIcon -and $script:AppIcon -ne [System.Drawing.SystemIcons]::Information) {
            $g.DrawIcon($script:AppIcon, 0, 0)
        } else {
            $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120, 120, 120))
            $g.FillRectangle($brush, 2, 2, 5, 5)
            $g.FillRectangle($brush, 9, 2, 5, 5)
            $g.FillRectangle($brush, 2, 9, 5, 5)
            $g.FillRectangle($brush, 9, 9, 5, 5)
            $brush.Dispose()
        }
    }
    else {
        # Two-row grid: Row 0 is 5h, Row 1 is 7d
        # Columns correspond to enabled providers in tooltip order
        $rows = 2
        $cols = $enabledProviders.Count
        $scaleRatio = $size / 16.0

        # Vertical layout (2 rows separated by gapY)
        $gapY = [Math]::Max(1, [int][Math]::Round(2.0 * $scaleRatio))
        $availH = $size - $gapY
        $blockH = [Math]::Max(2, [int][Math]::Floor(($availH - [int][Math]::Round(3.0 * $scaleRatio)) / $rows))
        $totalH = ($rows * $blockH) + $gapY
        $startY = [int][Math]::Floor(($size - $totalH) / 2.0)

        # Horizontal layout (N columns separated by gapX)
        $baseGapX = if ($cols -eq 2) { 2.0 } else { 1.0 }
        $gapX = if ($cols -gt 1) { [Math]::Max(1, [int][Math]::Round($baseGapX * $scaleRatio)) } else { 0 }
        $totalGapsX = ($cols - 1) * $gapX

        $targetMarginX = if ($cols -ge 4) { 0 } else { [Math]::Max(1, [int][Math]::Round(1.0 * $scaleRatio)) }
        $availW = $size - $totalGapsX - (2 * $targetMarginX)
        $blockW = [Math]::Max(2, [int][Math]::Floor($availW / $cols))
        if ($cols -eq 1) {
            $blockW = [Math]::Min($blockW, [int][Math]::Round(10.0 * $scaleRatio))
        }
        $totalW = ($cols * $blockW) + $totalGapsX
        $startX = [int][Math]::Floor(($size - $totalW) / 2.0)

        for ($c = 0; $c -lt $cols; $c++) {
            $provider = $enabledProviders[$c]
            $x = $startX + $c * ($blockW + $gapX)

            # Row 0: 5h health state
            $state5h = Get-WindowHealthState -Provider $provider -Window '5h'
            $color5h = Get-HealthStateColor -HealthState $state5h
            $brush5h = New-Object System.Drawing.SolidBrush $color5h
            $y0 = $startY
            $g.FillRectangle($brush5h, $x, $y0, $blockW, $blockH)
            $brush5h.Dispose()

            # Row 1: 7d health state
            $state7d = Get-WindowHealthState -Provider $provider -Window '7d'
            $color7d = Get-HealthStateColor -HealthState $state7d
            $brush7d = New-Object System.Drawing.SolidBrush $color7d
            $y1 = $startY + $blockH + $gapY
            $g.FillRectangle($brush7d, $x, $y1, $blockW, $blockH)
            $brush7d.Dispose()
        }
    }

    # Convert to Icon
    $hIcon = $bmp.GetHicon()
    $tempIcon = [System.Drawing.Icon]::FromHandle($hIcon)
    $newIcon = [System.Drawing.Icon]$tempIcon.Clone()
    $tempIcon.Dispose()
    if ($null -ne $script:User32) {
        [void]$script:User32::DestroyIcon($hIcon)
    }

    $oldIcon = $script:NotifyIcon.Icon
    $script:NotifyIcon.Icon = $newIcon

    # Clean up old icon and bitmaps
    if ($null -ne $oldIcon -and $oldIcon -ne $script:AppIcon) {
        $oldIcon.Dispose()
    }
    $g.Dispose()
    $bmp.Dispose()
}

function Update-DashboardGrid {
    if ($null -eq $script:Grid -or $null -eq $script:Snapshot) {
        return
    }

    $script:Grid.Rows.Clear()
    foreach ($provider in @($script:Snapshot.Providers)) {
        [void]$script:Grid.Rows.Add(
            $provider.Name,
            (Format-Percent $provider.FiveHourRemainingPercent),
            (Format-GuiResetHours -Value $provider.FiveHourResetHours -Snapshot $script:Snapshot),
            (Format-Percent $provider.WeeklyRemainingPercent),
            (Format-GuiResetHours -Value $provider.WeeklyResetHours -Snapshot $script:Snapshot -IsWeekly),
            (Format-DateCell $provider.LastEventLocal),
            $provider.Status
        )

        $row = $script:Grid.Rows[$script:Grid.Rows.Count - 1]
        $row.DefaultCellStyle.ForeColor = Get-HealthStateColor -HealthState $provider.HealthState
        $row.DefaultCellStyle.BackColor = Get-HealthStateBackColor -HealthState $provider.HealthState
        $row.DefaultCellStyle.SelectionBackColor = Get-HealthStateBackColor -HealthState $provider.HealthState
        $row.DefaultCellStyle.SelectionForeColor = Get-HealthStateColor -HealthState $provider.HealthState
    }

    if ($null -ne $script:StatusLabel) {
        $script:StatusLabel.Text = 'Updated: ' + $script:Snapshot.GeneratedAtLocal.ToString('yyyy-MM-dd HH:mm:ss')
    }
}

$script:IsRefreshing = $false
$script:WorkerPool = $null
$script:AsyncWorker = $null
$script:AsyncResult = $null
$script:AsyncCheckTimer = $null
$script:DashboardRefreshButton = $null

function Get-TokenMonitorAllUsageFunctions {
    $mod = Get-Module TokenUsage
    if ($null -ne $mod) {
        return @(& $mod { Get-ChildItem Function:\ })
    }
    return @(Get-ChildItem Function:\*)
}

function New-TokenMonitorWorkerPool {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($fn in (Get-TokenMonitorAllUsageFunctions)) {
        if ($fn.CommandType -eq 'Function' -and $fn.Name.Length -gt 2 -and -not ($fn.Name -match '^[A-Z]:$')) {
            try {
                $entry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fn.Name, $fn.Definition)
                $iss.Commands.Add($entry)
            } catch {}
        }
    }

    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 1, $iss, $Host)
    $pool.Open()
    return $pool
}

function Refresh-Usage {
    if ($script:IsRefreshing) {
        return
    }

    $script:IsRefreshing = $true

    if ($null -ne $script:StatusLabel) {
        $script:StatusLabel.Text = 'Refreshing...'
    }
    if ($null -ne $script:DashboardRefreshButton -and -not $script:DashboardRefreshButton.IsDisposed) {
        $script:DashboardRefreshButton.Enabled = $false
    }

    try {
        if ([string]::IsNullOrWhiteSpace($script:SettingsPath)) {
            $script:SettingsPath = Get-TokenMonitorSettingsPath
        }
        $script:Settings = Read-TokenMonitorSettings -Path $script:SettingsPath

        if ($null -eq $script:WorkerPool) {
            $script:WorkerPool = New-TokenMonitorWorkerPool
        }

        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $script:WorkerPool
        [void]$ps.AddCommand('Get-TokenUsageSnapshot').AddParameter('Settings', $script:Settings)

        $script:AsyncWorker = $ps
        $script:AsyncResult = $ps.BeginInvoke()
        if ($null -ne $script:AsyncCheckTimer) {
            $script:AsyncCheckTimer.Start()
        }
    }
    catch {
        $script:IsRefreshing = $false
        if ($null -ne $script:DashboardRefreshButton -and -not $script:DashboardRefreshButton.IsDisposed) {
            $script:DashboardRefreshButton.Enabled = $true
        }
        if ($null -ne $script:NotifyIcon) {
            $script:NotifyIcon.Text = 'TokenMonitor refresh failed'
            $script:NotifyIcon.ShowBalloonTip(3000, 'TokenMonitor', $_.Exception.Message, [System.Windows.Forms.ToolTipIcon]::Warning)
        }
        if ($null -ne $script:StatusLabel) {
            $script:StatusLabel.Text = 'Refresh failed: ' + $_.Exception.Message
        }
    }
}

function Show-Dashboard {
    if ($null -ne $script:DashboardForm -and -not $script:DashboardForm.IsDisposed) {
        $script:DashboardForm.Show()
        $script:DashboardForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $script:DashboardForm.Activate()
        $script:DashboardForm.Refresh()
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'TokenMonitor'
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.Size = New-UiSize 1150 420
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-UiSize 950 320
    Style-ModernForm -Form $form

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Top'
    $panel.Height = Scale-UiValue 44

    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = 'Refresh'
    $refreshButton.Width = Scale-UiValue 90
    $refreshButton.Height = Scale-UiValue 28
    $refreshButton.Left = Scale-UiValue 12
    $refreshButton.Top = Scale-UiValue 8
    $refreshButton.Add_Click({ Refresh-Usage })
    $refreshButton.Enabled = -not $script:IsRefreshing
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
    $openConfigButton.Add_Click({ Open-TokenMonitorConfigFile })
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
    $grid.AllowUserToResizeRows = $false
    Style-DataGridView -Grid $grid

    foreach ($column in @(
        @('Provider', 'Provider', 'AllCells', 'MiddleLeft'),
        @('FiveHour', '5h quota', 'AllCells', 'MiddleRight'),
        @('FiveHourReset', '5h reset', 'AllCells', 'MiddleRight'),
        @('Weekly', '7d quota', 'AllCells', 'MiddleRight'),
        @('WeeklyReset', '7d reset', 'AllCells', 'MiddleRight'),
        @('LastEvent', 'Last update', 'AllCells', 'MiddleCenter'),
        @('Status', 'Status', 'Fill', 'MiddleLeft')
    )) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $column[0]
        $col.HeaderText = $column[1]
        $col.AutoSizeMode = $column[2]
        $col.DefaultCellStyle.Alignment = $column[3]
        $col.HeaderCell.Style.Alignment = 'MiddleCenter'
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
    $script:DashboardRefreshButton = $refreshButton
    $form.Show()
    $form.Activate()
    $form.Refresh()
    Update-DashboardGrid
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
    $settingsPath = $script:SettingsPath
    if ([string]::IsNullOrWhiteSpace($settingsPath)) {
        $settingsPath = Get-TokenMonitorSettingsPath
    }

    $settings = Read-TokenMonitorSettings -Path $settingsPath

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

    $refreshLabel = New-Object System.Windows.Forms.Label
    $refreshLabel.Text = 'Refresh seconds'
    $refreshLabel.AutoSize = $true
    $refreshLabel.Left = Scale-UiValue 12
    $refreshLabel.Top = Scale-UiValue 13
    $top.Controls.Add($refreshLabel)

    $refreshInput = New-Object System.Windows.Forms.NumericUpDown
    $refreshInput.Minimum = 10
    $refreshInput.Maximum = 3600
    $refreshInput.Value = [decimal]([Math]::Max(10, [int]$settings.RefreshSeconds))
    $refreshInput.Left = Scale-UiValue 118
    $refreshInput.Top = Scale-UiValue 9
    $refreshInput.Width = Scale-UiValue 80
    $top.Controls.Add($refreshInput)

    $maxFileLabel = New-Object System.Windows.Forms.Label
    $maxFileLabel.Text = 'Max file MB'
    $maxFileLabel.AutoSize = $true
    $maxFileLabel.Left = Scale-UiValue 218
    $maxFileLabel.Top = Scale-UiValue 13
    $top.Controls.Add($maxFileLabel)

    $maxFileInput = New-Object System.Windows.Forms.NumericUpDown
    $maxFileInput.Minimum = 1
    $maxFileInput.Maximum = 2048
    $maxFileInput.Value = [decimal]([Math]::Max(1, [int]$settings.MaxFileSizeMB))
    $maxFileInput.Left = Scale-UiValue 298
    $maxFileInput.Top = Scale-UiValue 9
    $maxFileInput.Width = Scale-UiValue 70
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
    $grid.AllowUserToResizeRows = $false
    Style-DataGridView -Grid $grid

    $grid.Add_CurrentCellDirtyStateChanged({
        if ($this.IsCurrentCellDirty) {
            [void]$this.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
        }
    })

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

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = 'Save'
    $saveButton.Width = Scale-UiValue 90
    $saveButton.Height = Scale-UiValue 28
    $saveButton.Left = Scale-UiValue 12
    $saveButton.Top = Scale-UiValue 10
    $saveButton.Add_Click({
        try {
            [void]$grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
            $grid.EndEdit()

            $providers = New-Object System.Collections.Generic.List[object]
            foreach ($row in $grid.Rows) {
                if ($row.IsNewRow) {
                    continue
                }
                $enabledVal = $row.Cells['Enabled'].Value
                $isEnabled = if ($null -eq $enabledVal) { $false } else { [bool]$enabledVal }

                $providers.Add([ordered]@{
                    Id = [string]$row.Cells['Id'].Value
                    Name = [string]$row.Cells['Name'].Value
                    Enabled = $isEnabled
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

            Save-TokenMonitorSettings -Settings $newSettings -Path $settingsPath
            Refresh-Usage
            $form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'TokenMonitor Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
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
    $openButton.Add_Click({ Open-TokenMonitorConfigFile })
    Style-FlatButton -Button $openButton
    $bottom.Controls.Add($openButton)

    $form.Controls.Add($grid)
    $form.Controls.Add($top)
    $form.Controls.Add($bottom)
    $form.Add_FormClosed({
        $script:SettingsForm = $null
    })

    $script:SettingsForm = $form
    $form.Show()
    $form.Activate()
}

function Dispose-TokenMonitorResources {
    if ($null -ne $script:AsyncCheckTimer) {
        try { $script:AsyncCheckTimer.Stop() } catch {}
        try { $script:AsyncCheckTimer.Dispose() } catch {}
        $script:AsyncCheckTimer = $null
    }
    if ($null -ne $script:AsyncWorker) {
        try { $script:AsyncWorker.Dispose() } catch {}
        $script:AsyncWorker = $null
    }
    if ($null -ne $script:WorkerPool) {
        try { $script:WorkerPool.Close() } catch {}
        try { $script:WorkerPool.Dispose() } catch {}
        $script:WorkerPool = $null
    }
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
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Open config' -OnClick { Open-TokenMonitorConfigFile }))
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

$asyncCheckTimer = New-Object System.Windows.Forms.Timer
$asyncCheckTimer.Interval = 100
$asyncCheckTimer.Add_Tick({
    if ($null -eq $script:AsyncResult) {
        $script:AsyncCheckTimer.Stop()
        return
    }

    if ($script:AsyncResult.IsCompleted) {
        $script:AsyncCheckTimer.Stop()
        try {
            $results = $script:AsyncWorker.EndInvoke($script:AsyncResult)
            if ($null -ne $results -and $results.Count -gt 0) {
                $script:Snapshot = $results[0]
                if ($null -ne $script:NotifyIcon) {
                    $script:NotifyIcon.Text = Format-TokenUsageTooltip -Snapshot $script:Snapshot
                    Update-DynamicTrayIcon -Snapshot $script:Snapshot
                }
                Update-DashboardGrid
            }
        }
        catch {
            if ($null -ne $script:NotifyIcon) {
                $script:NotifyIcon.Text = 'TokenMonitor refresh failed'
                $script:NotifyIcon.ShowBalloonTip(3000, 'TokenMonitor', $_.Exception.Message, [System.Windows.Forms.ToolTipIcon]::Warning)
            }
            if ($null -ne $script:StatusLabel) {
                $script:StatusLabel.Text = 'Refresh failed: ' + $_.Exception.Message
            }
        }
        finally {
            if ($null -ne $script:AsyncWorker) {
                try { $script:AsyncWorker.Dispose() } catch {}
                $script:AsyncWorker = $null
            }
            $script:AsyncResult = $null
            $script:IsRefreshing = $false
            if ($null -ne $script:DashboardRefreshButton -and -not $script:DashboardRefreshButton.IsDisposed) {
                $script:DashboardRefreshButton.Enabled = $true
            }
        }
    }
})
$script:AsyncCheckTimer = $asyncCheckTimer

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
