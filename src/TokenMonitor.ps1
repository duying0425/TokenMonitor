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

        $line = '{0}: 5h {1}/{2} ({3} left), 7d {4}/{5} ({6} left), files {7}, events {8}, {9}' -f `
            $provider.Name,
            $fiveHourUsed,
            (Format-TokenCount $provider.FiveHourLimit),
            (Format-Percent $provider.FiveHourRemainingPercent),
            $weeklyUsed,
            (Format-TokenCount $provider.WeeklyLimit),
            (Format-Percent $provider.WeeklyRemainingPercent),
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

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Snapshot = $null
$script:DashboardForm = $null
$script:SettingsForm = $null
$script:Grid = $null
$script:StatusLabel = $null
$script:NotifyIcon = $null
$script:ContextMenu = $null
$script:AppContext = New-Object System.Windows.Forms.ApplicationContext

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

function Get-ProviderRemainingPercent {
    param($Provider)

    if ($null -ne $Provider.FiveHourRemainingPercent -and $null -ne $Provider.WeeklyRemainingPercent) {
        return [Math]::Min([double]$Provider.FiveHourRemainingPercent, [double]$Provider.WeeklyRemainingPercent)
    }
    if ($null -ne $Provider.FiveHourRemainingPercent) {
        return [double]$Provider.FiveHourRemainingPercent
    }
    if ($null -ne $Provider.WeeklyRemainingPercent) {
        return [double]$Provider.WeeklyRemainingPercent
    }
    return $null
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
            'antigravity' { 'Gemini' }
            'codex' { 'Codex' }
            'claude' { 'Claude' }
            default { $provider.Name }
        }

        $parts.Add(('{0} 5h {1}' -f $name, (Format-Percent $provider.FiveHourRemainingPercent)))
        $parts.Add(('{0} 7d {1}' -f $name, (Format-Percent $provider.WeeklyRemainingPercent)))
    }

    if ($parts.Count -eq 0) {
        return 'TokenMonitor n/a'
    }
    return ($parts -join [Environment]::NewLine)
}

function Get-WorstRemainingPercent {
    param($Snapshot)

    $worst = $null
    if ($null -eq $Snapshot) {
        return $worst
    }

    foreach ($provider in @($Snapshot.Providers)) {
        $percent = Get-ProviderRemainingPercent -Provider $provider
        if ($null -eq $percent) {
            continue
        }
        if ($null -eq $worst -or [double]$percent -lt [double]$worst) {
            $worst = [double]$percent
        }
    }
    return $worst
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

    # Create a 16x16 bitmap
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    if ($enabledProviders.Count -eq 0) {
        # If no providers or loading, draw a default gray circle
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(100, 100, 100)), 2.5
        $g.DrawEllipse($pen, 2, 2, 12, 12)
        $pen.Dispose()
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
            # Determine color based on provider's remaining percent
            $percent = Get-ProviderRemainingPercent -Provider $provider
            $color = [System.Drawing.Color]::FromArgb(100, 100, 100) # Gray if n/a
            
            if ($provider.Status -ne 'OK') {
                $color = [System.Drawing.Color]::FromArgb(200, 100, 0) # Warning Orange/Brown if error
            }
            elseif ($null -ne $percent) {
                if ($percent -le 15) {
                    $color = [System.Drawing.Color]::FromArgb(220, 40, 40) # Red
                }
                elseif ($percent -le 30) {
                    $color = [System.Drawing.Color]::FromArgb(230, 130, 20) # Orange
                }
                else {
                    $color = [System.Drawing.Color]::FromArgb(40, 180, 100) # Green
                }
            }

            # Draw the segment
            $pen = New-Object System.Drawing.Pen $color, 2.5
            $g.DrawArc($pen, 2, 2, 12, 12, $startAngle, $sweepAngle)
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
    if ($null -ne $oldIcon) {
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
        $fiveHourUsed = Format-TokenCount $provider.FiveHourUsed
        $weeklyUsed = Format-TokenCount $provider.WeeklyUsed
        if (Get-Member -InputObject $provider -Name FiveHourUsedDisplay -MemberType NoteProperty -ErrorAction SilentlyContinue) {
            $fiveHourUsed = $provider.FiveHourUsedDisplay
        }
        if (Get-Member -InputObject $provider -Name WeeklyUsedDisplay -MemberType NoteProperty -ErrorAction SilentlyContinue) {
            $weeklyUsed = $provider.WeeklyUsedDisplay
        }

        [void]$script:Grid.Rows.Add(
            $provider.Name,
            $fiveHourUsed,
            (Format-TokenCount $provider.FiveHourLimit),
            (Format-Percent $provider.FiveHourRemainingPercent),
            $weeklyUsed,
            (Format-TokenCount $provider.WeeklyLimit),
            (Format-Percent $provider.WeeklyRemainingPercent),
            (Format-DateCell $provider.LastEventLocal),
            [string]$provider.Files,
            [string]$provider.Events,
            $provider.Status
        )

        $row = $script:Grid.Rows[$script:Grid.Rows.Count - 1]
        if ($provider.Status -ne 'OK') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        elseif (($null -ne $provider.FiveHourRemainingPercent -and [double]$provider.FiveHourRemainingPercent -le 15) -or
            ($null -ne $provider.WeeklyRemainingPercent -and [double]$provider.WeeklyRemainingPercent -le 15)) {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Firebrick
        }
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

function Show-Dashboard {
    if ($null -ne $script:DashboardForm -and -not $script:DashboardForm.IsDisposed) {
        $script:DashboardForm.Show()
        $script:DashboardForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $script:DashboardForm.Activate()
        Refresh-Usage
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'TokenMonitor'
    $form.Size = New-Object System.Drawing.Size(980, 420)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object System.Drawing.Size(820, 320)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Top'
    $panel.Height = 44

    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = 'Refresh'
    $refreshButton.Width = 90
    $refreshButton.Height = 28
    $refreshButton.Left = 12
    $refreshButton.Top = 8
    $refreshButton.Add_Click({ Refresh-Usage })
    $panel.Controls.Add($refreshButton)

    $settingsButton = New-Object System.Windows.Forms.Button
    $settingsButton.Text = 'Settings'
    $settingsButton.Width = 90
    $settingsButton.Height = 28
    $settingsButton.Left = 112
    $settingsButton.Top = 8
    $settingsButton.Add_Click({ Show-Settings })
    $panel.Controls.Add($settingsButton)

    $openConfigButton = New-Object System.Windows.Forms.Button
    $openConfigButton.Text = 'Open config'
    $openConfigButton.Width = 100
    $openConfigButton.Height = 28
    $openConfigButton.Left = 212
    $openConfigButton.Top = 8
    $openConfigButton.Add_Click({ Invoke-Item -LiteralPath $script:SettingsPath })
    $panel.Controls.Add($openConfigButton)

    $status = New-Object System.Windows.Forms.Label
    $status.AutoSize = $true
    $status.Left = 330
    $status.Top = 14
    $status.Text = 'Updated: never'
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
    $grid.BackgroundColor = [System.Drawing.SystemColors]::Window

    foreach ($column in @(
        @('Provider', 'Provider'),
        @('FiveHourUsed', '5h used'),
        @('FiveHourLimit', '5h quota'),
        @('FiveHourLeft', '5h left'),
        @('WeeklyUsed', '7d used'),
        @('WeeklyLimit', '7d quota'),
        @('WeeklyLeft', '7d left'),
        @('LastEvent', 'Last event'),
        @('Files', 'Files'),
        @('Events', 'Events'),
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
    Refresh-Usage
    $form.Show()
    $form.Activate()
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
    $form.Size = New-Object System.Drawing.Size(1040, 420)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object System.Drawing.Size(900, 320)

    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = 'Top'
    $top.Height = 42

    $refreshLabel = New-Object System.Windows.Forms.Label
    $refreshLabel.Text = 'Refresh seconds'
    $refreshLabel.AutoSize = $true
    $refreshLabel.Left = 12
    $refreshLabel.Top = 13
    $top.Controls.Add($refreshLabel)

    $refreshInput = New-Object System.Windows.Forms.NumericUpDown
    $refreshInput.Minimum = 10
    $refreshInput.Maximum = 3600
    $refreshInput.Value = [decimal]([Math]::Max(10, [int]$settings.RefreshSeconds))
    $refreshInput.Left = 118
    $refreshInput.Top = 9
    $refreshInput.Width = 80
    $top.Controls.Add($refreshInput)

    $maxFileLabel = New-Object System.Windows.Forms.Label
    $maxFileLabel.Text = 'Max file MB'
    $maxFileLabel.AutoSize = $true
    $maxFileLabel.Left = 218
    $maxFileLabel.Top = 13
    $top.Controls.Add($maxFileLabel)

    $maxFileInput = New-Object System.Windows.Forms.NumericUpDown
    $maxFileInput.Minimum = 1
    $maxFileInput.Maximum = 2048
    $maxFileInput.Value = [decimal]([Math]::Max(1, [int]$settings.MaxFileSizeMB))
    $maxFileInput.Left = 298
    $maxFileInput.Top = 9
    $maxFileInput.Width = 70
    $top.Controls.Add($maxFileInput)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Use semicolon-separated roots. Quotas are token counts; 0 means unknown.'
    $hint.AutoSize = $true
    $hint.Left = 388
    $hint.Top = 13
    $top.Controls.Add($hint)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.BackgroundColor = [System.Drawing.SystemColors]::Window

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
    $bottom.Height = 48

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = 'Save'
    $saveButton.Width = 90
    $saveButton.Height = 28
    $saveButton.Left = 12
    $saveButton.Top = 10
    $saveButton.Add_Click({
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
            ShowStatusStrip = $false
            Providers = @($providers)
        }

        Save-TokenMonitorSettings -Settings $newSettings -Path $script:SettingsPath
        $script:Settings = Read-TokenMonitorSettings -Path $script:SettingsPath
        Refresh-Usage
        $form.Hide()
    })
    $bottom.Controls.Add($saveButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Cancel'
    $cancelButton.Width = 90
    $cancelButton.Height = 28
    $cancelButton.Left = 112
    $cancelButton.Top = 10
    $cancelButton.Add_Click({ $form.Hide() })
    $bottom.Controls.Add($cancelButton)

    $openButton = New-Object System.Windows.Forms.Button
    $openButton.Text = 'Open config'
    $openButton.Width = 100
    $openButton.Height = 28
    $openButton.Left = 212
    $openButton.Top = 10
    $openButton.Add_Click({ Invoke-Item -LiteralPath $script:SettingsPath })
    $bottom.Controls.Add($openButton)

    $form.Controls.Add($grid)
    $form.Controls.Add($top)
    $form.Controls.Add($bottom)
    $form.Add_FormClosing({
        if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $_.Cancel = $true
            $this.Hide()
        }
    })

    $script:SettingsForm = $form
    $form.Show()
    $form.Activate()
}

function Exit-TokenMonitor {
    if ($null -ne $script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
    }
    $script:AppContext.ExitThread()
}

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Dashboard' -OnClick { Show-Dashboard }))
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Refresh now' -OnClick { Refresh-Usage }))
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Settings' -OnClick { Show-Settings }))
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Open config' -OnClick { Invoke-Item -LiteralPath $script:SettingsPath }))
[void]$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$contextMenu.Items.Add((New-MenuItem -Text 'Exit' -OnClick { Exit-TokenMonitor }))
$script:ContextMenu = $contextMenu

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
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

Refresh-Usage
[System.Windows.Forms.Application]::Run($script:AppContext)
