Set-StrictMode -Version Latest

$script:TimestampFields = @(
    'timestamp',
    'created_at',
    'createdAt',
    'started_at',
    'startedAt',
    'updated_at',
    'updatedAt',
    'time',
    'date'
)

$script:TotalTokenFields = @(
    'total_tokens',
    'totalTokens'
)

$script:PartTokenFields = @(
    'input_tokens',
    'inputTokens',
    'output_tokens',
    'outputTokens',
    'cached_input_tokens',
    'cachedInputTokens',
    'prompt_tokens',
    'promptTokens',
    'completion_tokens',
    'completionTokens',
    'cache_creation_input_tokens',
    'cacheCreationInputTokens',
    'cache_read_input_tokens',
    'cacheReadInputTokens',
    'cached_tokens',
    'cachedTokens',
    'reasoning_tokens',
    'reasoningTokens',
    'reasoning_output_tokens',
    'reasoningOutputTokens'
)

function Get-TokenMonitorAppDir {
    $path = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'TokenMonitor'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    return $path
}

function Get-TokenMonitorSettingsPath {
    return (Join-Path (Get-TokenMonitorAppDir) 'settings.json')
}

function New-ProviderConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$ScanRoots,
        [long]$FiveHourLimit = 0,
        [long]$WeeklyLimit = 0,
        [bool]$Enabled = $true,
        [string]$Command = ''
    )

    return [ordered]@{
        Id = $Id
        Name = $Name
        Enabled = $Enabled
        FiveHourLimit = $FiveHourLimit
        WeeklyLimit = $WeeklyLimit
        ScanRoots = $ScanRoots
        FilePatterns = @('*.jsonl', '*.json')
        Command = $Command
        CommandTimeoutSeconds = 15
    }
}

function New-DefaultTokenSettings {
    $defaultGeminiCommand = '$authPath = "$env:APPDATA\TokenMonitor\gemini_auth.json"; if (-not (Test-Path -LiteralPath $authPath)) { [PSCustomObject]@{ Error = "No gemini_auth.json" } | ConvertTo-Json -Compress; exit }; try { $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json; $sapisid = $auth.SAPISID; $psid1 = $auth."__Secure-1PSID"; if (-not $sapisid -or -not $psid1) { [PSCustomObject]@{ Error = "Missing credentials in gemini_auth.json" } | ConvertTo-Json -Compress; exit }; $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession; $uri = New-Object System.Uri("https://gemini.google.com"); foreach ($prop in $auth.PSObject.Properties) { if ($prop.Value -and $prop.Value -is [string]) { try { $session.Cookies.Add($uri, (New-Object System.Net.Cookie($prop.Name, $prop.Value))) } catch {} } }; $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $mkHash = { param($key) $bytes = [System.Security.Cryptography.HashAlgorithm]::Create("SHA1").ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$now $key https://gemini.google.com")); [System.BitConverter]::ToString($bytes).Replace("-","").ToLower() }; $h = & $mkHash $sapisid; $authHeader = "SAPISIDHASH ${now}_${h}"; $h1 = $auth."__Secure-1PAPISID"; if ($h1) { $h1hash = & $mkHash $h1; $authHeader += " SAPISID1PHASH ${now}_${h1hash}" }; $h3 = $auth."__Secure-3PAPISID"; if ($h3) { $h3hash = & $mkHash $h3; $authHeader += " SAPISID3PHASH ${now}_${h3hash}" }; $hdrs = @{ Authorization = $authHeader; "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"; "x-same-domain" = "1"; Origin = "https://gemini.google.com"; Referer = "https://gemini.google.com/usage" }; $html = Invoke-RestMethod -Uri "https://gemini.google.com/usage" -Headers $hdrs -WebSession $session -Method Get -ErrorAction Stop; $at = $null; $bl = $null; $fsid = $null; $idx = $html.IndexOf("WIZ_global_data ="); if ($idx -ge 0) { $s = $idx + "WIZ_global_data =".Length; $e = $html.IndexOf("};", $s); if ($e -ge 0) { $d = ConvertFrom-Json $html.Substring($s, $e - $s + 1); $at = $d.SNlM0e; if (-not $at) { foreach ($p in $d.PSObject.Properties) { if ($p.Value -is [string] -and $p.Value.StartsWith("AD1_")) { $at = $p.Value; break } } }; $bl = $d.cfb2h; $fsid = $d.FdrFJe } }; if (-not $at -and ($html -match ''"SNlM0e"\s*:\s*"([^"]+)"'')) { $at = $Matches[1] }; if (-not $at -and ($html -match ''"(AD1_[A-Za-z0-9\-_:%]+)"'')) { $at = $Matches[1] }; if (-not $at) { [PSCustomObject]@{ Error = "Could not extract CSRF token from Gemini usage page" } | ConvertTo-Json -Compress; exit }; $reqStr = ''[[["jSf9Qc","[]",null,"generic"]]]''; $bodyStr = "f.req=" + [Uri]::EscapeDataString($reqStr) + "&at=" + [Uri]::EscapeDataString($at); $postUrl = "https://gemini.google.com/_/BardChatUi/data/batchexecute?rpcids=jSf9Qc&source-path=%2Fusage"; if ($bl) { $postUrl += "&bl=" + [Uri]::EscapeDataString($bl) }; if ($fsid) { $postUrl += "&f.sid=" + [Uri]::EscapeDataString($fsid) }; $postUrl += "&hl=en&_reqid=$(Get-Random -Min 1000000 -Max 9999999)&rt=c"; $resp = Invoke-RestMethod -Uri $postUrl -Headers $hdrs -WebSession $session -Method Post -Body $bodyStr -ContentType "application/x-www-form-urlencoded;charset=UTF-8" -ErrorAction Stop; if ($resp -match ''"jSf9Qc","(\[.*?\])"'') { $payload = ConvertFrom-Json $Matches[1]; $items = $payload[1]; $fivePercent = $null; $weekPercent = $null; foreach ($item in $items) { $rem = [Math]::Max(0.0, [Math]::Min(100.0, [Math]::Round((1.0 - [double]$item[1]) * 100.0, 1))); if ($item[2] -eq 1) { $fivePercent = $rem } elseif ($item[2] -eq 2) { $weekPercent = $rem } }; [PSCustomObject]@{ fiveHourRemainingPercent = $fivePercent; weeklyRemainingPercent = $weekPercent } | ConvertTo-Json -Compress } else { [PSCustomObject]@{ Error = "Unexpected API response" } | ConvertTo-Json -Compress } } catch { [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress }'
    $defaultCodexCommand = '$authPath = "$env:USERPROFILE\.codex\auth.json"; if (-not (Test-Path -LiteralPath $authPath)) { [PSCustomObject]@{ Error = "No auth.json" } | ConvertTo-Json -Compress; exit }; try { $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json; $token = $auth.tokens.access_token; if (-not $token) { [PSCustomObject]@{ Error = "Not logged in" } | ConvertTo-Json -Compress; exit }; $headers = @{ Authorization = "Bearer $token"; "User-Agent" = "Mozilla/5.0" }; $resp = Invoke-RestMethod -Uri "https://chatgpt.com/backend-api/wham/usage" -Headers $headers -ErrorAction Stop; if ($resp) { [PSCustomObject]@{ fiveHourUsedPercent = $resp.rate_limit.primary_window.used_percent; weeklyUsedPercent = $resp.rate_limit.secondary_window.used_percent } | ConvertTo-Json -Compress } else { [PSCustomObject]@{ Error = "Empty API response" } | ConvertTo-Json -Compress } } catch { [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress }'
    $defaultClaudeCommand = '$credsPath = "$env:USERPROFILE\.claude\.credentials.json"; if (-not (Test-Path -LiteralPath $credsPath)) { [PSCustomObject]@{ Error = "No .credentials.json" } | ConvertTo-Json -Compress; exit }; try { $creds = Get-Content -LiteralPath $credsPath -Raw | ConvertFrom-Json; $token = $creds.claudeAiOauth.accessToken; if (-not $token) { [PSCustomObject]@{ Error = "Not logged in" } | ConvertTo-Json -Compress; exit }; $headers = @{ Authorization = "Bearer $token"; "User-Agent" = "claude-code/2.1.186"; "anthropic-beta" = "oauth-2025-04-20" }; $resp = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" -Headers $headers -ErrorAction Stop; if ($resp) { [PSCustomObject]@{ fiveHourUsedPercent = $resp.five_hour.utilization; weeklyUsedPercent = $resp.seven_day.utilization } | ConvertTo-Json -Compress } else { [PSCustomObject]@{ Error = "Empty API response" } | ConvertTo-Json -Compress } } catch { [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress }'

    return [ordered]@{
        RefreshSeconds = 60
        MaxFileSizeMB = 20
        ShowStatusStrip = $true
        Providers = @(
            (New-ProviderConfig `
                -Id 'antigravity' `
                -Name 'Antigravity / Gemini' `
                -Enabled $true `
                -ScanRoots @(
                    '%APPDATA%\Google\Antigravity',
                    '%LOCALAPPDATA%\Google\Antigravity',
                    '%APPDATA%\Antigravity'
                ) `
                -Command $defaultGeminiCommand),
            (New-ProviderConfig `
                -Id 'codex' `
                -Name 'Codex / ChatGPT' `
                -Enabled $true `
                -ScanRoots @(
                    '%USERPROFILE%\.codex\sessions',
                    '%USERPROFILE%\.codex\session_index.jsonl'
                ) `
                -Command $defaultCodexCommand),
            (New-ProviderConfig `
                -Id 'claude' `
                -Name 'Claude Code' `
                -Enabled $true `
                -ScanRoots @(
                    '%USERPROFILE%\.claude\projects',
                    '%USERPROFILE%\.claude\sessions'
                ) `
                -Command $defaultClaudeCommand)
        )
    }
}

function Save-TokenMonitorSettings {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [string]$Path = (Get-TokenMonitorSettingsPath)
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $Settings | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Read-TokenMonitorSettings {
    param([string]$Path = (Get-TokenMonitorSettingsPath))

    $defaultGeminiCommand = '$authPath = "$env:APPDATA\TokenMonitor\gemini_auth.json"; if (-not (Test-Path -LiteralPath $authPath)) { [PSCustomObject]@{ Error = "No gemini_auth.json" } | ConvertTo-Json -Compress; exit }; try { $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json; $sapisid = $auth.SAPISID; $psid1 = $auth."__Secure-1PSID"; if (-not $sapisid -or -not $psid1) { [PSCustomObject]@{ Error = "Missing credentials in gemini_auth.json" } | ConvertTo-Json -Compress; exit }; $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession; $uri = New-Object System.Uri("https://gemini.google.com"); foreach ($prop in $auth.PSObject.Properties) { if ($prop.Value -and $prop.Value -is [string]) { try { $session.Cookies.Add($uri, (New-Object System.Net.Cookie($prop.Name, $prop.Value))) } catch {} } }; $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $mkHash = { param($key) $bytes = [System.Security.Cryptography.HashAlgorithm]::Create("SHA1").ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$now $key https://gemini.google.com")); [System.BitConverter]::ToString($bytes).Replace("-","").ToLower() }; $h = & $mkHash $sapisid; $authHeader = "SAPISIDHASH ${now}_${h}"; $h1 = $auth."__Secure-1PAPISID"; if ($h1) { $h1hash = & $mkHash $h1; $authHeader += " SAPISID1PHASH ${now}_${h1hash}" }; $h3 = $auth."__Secure-3PAPISID"; if ($h3) { $h3hash = & $mkHash $h3; $authHeader += " SAPISID3PHASH ${now}_${h3hash}" }; $hdrs = @{ Authorization = $authHeader; "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"; "x-same-domain" = "1"; Origin = "https://gemini.google.com"; Referer = "https://gemini.google.com/usage" }; $html = Invoke-RestMethod -Uri "https://gemini.google.com/usage" -Headers $hdrs -WebSession $session -Method Get -ErrorAction Stop; $at = $null; $bl = $null; $fsid = $null; $idx = $html.IndexOf("WIZ_global_data ="); if ($idx -ge 0) { $s = $idx + "WIZ_global_data =".Length; $e = $html.IndexOf("};", $s); if ($e -ge 0) { $d = ConvertFrom-Json $html.Substring($s, $e - $s + 1); $at = $d.SNlM0e; if (-not $at) { foreach ($p in $d.PSObject.Properties) { if ($p.Value -is [string] -and $p.Value.StartsWith("AD1_")) { $at = $p.Value; break } } }; $bl = $d.cfb2h; $fsid = $d.FdrFJe } }; if (-not $at -and ($html -match ''"SNlM0e"\s*:\s*"([^"]+)"'')) { $at = $Matches[1] }; if (-not $at -and ($html -match ''"(AD1_[A-Za-z0-9\-_:%]+)"'')) { $at = $Matches[1] }; if (-not $at) { [PSCustomObject]@{ Error = "Could not extract CSRF token from Gemini usage page" } | ConvertTo-Json -Compress; exit }; $reqStr = ''[[["jSf9Qc","[]",null,"generic"]]]''; $bodyStr = "f.req=" + [Uri]::EscapeDataString($reqStr) + "&at=" + [Uri]::EscapeDataString($at); $postUrl = "https://gemini.google.com/_/BardChatUi/data/batchexecute?rpcids=jSf9Qc&source-path=%2Fusage"; if ($bl) { $postUrl += "&bl=" + [Uri]::EscapeDataString($bl) }; if ($fsid) { $postUrl += "&f.sid=" + [Uri]::EscapeDataString($fsid) }; $postUrl += "&hl=en&_reqid=$(Get-Random -Min 1000000 -Max 9999999)&rt=c"; $resp = Invoke-RestMethod -Uri $postUrl -Headers $hdrs -WebSession $session -Method Post -Body $bodyStr -ContentType "application/x-www-form-urlencoded;charset=UTF-8" -ErrorAction Stop; if ($resp -match ''"jSf9Qc","(\[.*?\])"'') { $payload = ConvertFrom-Json $Matches[1]; $items = $payload[1]; $fivePercent = $null; $weekPercent = $null; foreach ($item in $items) { $rem = [Math]::Max(0.0, [Math]::Min(100.0, [Math]::Round((1.0 - [double]$item[1]) * 100.0, 1))); if ($item[2] -eq 1) { $fivePercent = $rem } elseif ($item[2] -eq 2) { $weekPercent = $rem } }; [PSCustomObject]@{ fiveHourRemainingPercent = $fivePercent; weeklyRemainingPercent = $weekPercent } | ConvertTo-Json -Compress } else { [PSCustomObject]@{ Error = "Unexpected API response" } | ConvertTo-Json -Compress } } catch { [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress }'
    $defaultCodexCommand = '$authPath = "$env:USERPROFILE\.codex\auth.json"; if (-not (Test-Path -LiteralPath $authPath)) { [PSCustomObject]@{ Error = "No auth.json" } | ConvertTo-Json -Compress; exit }; try { $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json; $token = $auth.tokens.access_token; if (-not $token) { [PSCustomObject]@{ Error = "Not logged in" } | ConvertTo-Json -Compress; exit }; $headers = @{ Authorization = "Bearer $token"; "User-Agent" = "Mozilla/5.0" }; $resp = Invoke-RestMethod -Uri "https://chatgpt.com/backend-api/wham/usage" -Headers $headers -ErrorAction Stop; if ($resp) { [PSCustomObject]@{ fiveHourUsedPercent = $resp.rate_limit.primary_window.used_percent; weeklyUsedPercent = $resp.rate_limit.secondary_window.used_percent } | ConvertTo-Json -Compress } else { [PSCustomObject]@{ Error = "Empty API response" } | ConvertTo-Json -Compress } } catch { [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress }'
    $defaultClaudeCommand = '$credsPath = "$env:USERPROFILE\.claude\.credentials.json"; if (-not (Test-Path -LiteralPath $credsPath)) { [PSCustomObject]@{ Error = "No .credentials.json" } | ConvertTo-Json -Compress; exit }; try { $creds = Get-Content -LiteralPath $credsPath -Raw | ConvertFrom-Json; $token = $creds.claudeAiOauth.accessToken; if (-not $token) { [PSCustomObject]@{ Error = "Not logged in" } | ConvertTo-Json -Compress; exit }; $headers = @{ Authorization = "Bearer $token"; "User-Agent" = "claude-code/2.1.186"; "anthropic-beta" = "oauth-2025-04-20" }; $resp = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" -Headers $headers -ErrorAction Stop; if ($resp) { [PSCustomObject]@{ fiveHourUsedPercent = $resp.five_hour.utilization; weeklyUsedPercent = $resp.seven_day.utilization } | ConvertTo-Json -Compress } else { [PSCustomObject]@{ Error = "Empty API response" } | ConvertTo-Json -Compress } } catch { [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress }'

    if (-not (Test-Path -LiteralPath $Path)) {
        $settings = New-DefaultTokenSettings
        Save-TokenMonitorSettings -Settings $settings -Path $Path
        return $settings
    }

    try {
        $settings = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $backup = "$Path.broken-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        $settings = New-DefaultTokenSettings
        Save-TokenMonitorSettings -Settings $settings -Path $Path
        return $settings
    }

    if (-not (Get-Member -InputObject $settings -Name RefreshSeconds -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        $settings | Add-Member -NotePropertyName RefreshSeconds -NotePropertyValue 60
    }
    if (-not (Get-Member -InputObject $settings -Name MaxFileSizeMB -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        $settings | Add-Member -NotePropertyName MaxFileSizeMB -NotePropertyValue 20
    }
    if (-not (Get-Member -InputObject $settings -Name ShowStatusStrip -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        $settings | Add-Member -NotePropertyName ShowStatusStrip -NotePropertyValue $true
    }

    $migrated = $false
    foreach ($provider in $settings.Providers) {
        if (-not (Get-Member -InputObject $provider -Name FilePatterns -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
            $provider | Add-Member -NotePropertyName FilePatterns -NotePropertyValue @('*.jsonl', '*.json')
            $migrated = $true
        }
        if (-not (Get-Member -InputObject $provider -Name Enabled -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
            $provider | Add-Member -NotePropertyName Enabled -NotePropertyValue $true
            $migrated = $true
        }
        if (-not (Get-Member -InputObject $provider -Name Command -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
            $defaultCmd = if ($provider.Id -eq 'antigravity') { $defaultGeminiCommand } elseif ($provider.Id -eq 'codex') { $defaultCodexCommand } elseif ($provider.Id -eq 'claude') { $defaultClaudeCommand } else { '' }
            $provider | Add-Member -NotePropertyName Command -NotePropertyValue $defaultCmd
            $migrated = $true
        }
        else {
            if ($provider.Id -eq 'antigravity' -and [string]::IsNullOrWhiteSpace($provider.Command)) {
                $provider.Command = $defaultGeminiCommand
                $migrated = $true
            }
            elseif ($provider.Id -eq 'codex' -and [string]::IsNullOrWhiteSpace($provider.Command)) {
                $provider.Command = $defaultCodexCommand
                $migrated = $true
            }
            elseif ($provider.Id -eq 'claude' -and [string]::IsNullOrWhiteSpace($provider.Command)) {
                $provider.Command = $defaultClaudeCommand
                $migrated = $true
            }
        }
        if (-not (Get-Member -InputObject $provider -Name CommandTimeoutSeconds -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
            $provider | Add-Member -NotePropertyName CommandTimeoutSeconds -NotePropertyValue 15
            $migrated = $true
        }
    }

    if ($migrated) {
        Save-TokenMonitorSettings -Settings $settings -Path $Path
    }

    return $settings
}

function Expand-TokenMonitorPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if ($expanded -eq '~') {
        return $HOME
    }
    if ($expanded.StartsWith('~\') -or $expanded.StartsWith('~/')) {
        return (Join-Path $HOME $expanded.Substring(2))
    }
    return $expanded
}

function ConvertTo-TokenDateTime {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [DateTime]) {
        return $Value.ToUniversalTime()
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $number = 0.0
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        try {
            if ($number -gt 999999999999) {
                return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$number).UtcDateTime
            }
            if ($number -gt 999999999) {
                return [DateTimeOffset]::FromUnixTimeSeconds([int64]$number).UtcDateTime
            }
        }
        catch {
            return $null
        }
    }

    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) {
        return $parsed.UtcDateTime
    }

    return $null
}

function Get-ObjectProperties {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = @()
        foreach ($key in $Value.Keys) {
            $pairs += [pscustomobject]@{ Name = [string]$key; Value = $Value[$key] }
        }
        return $pairs
    }

    if ($Value -is [pscustomobject]) {
        return @($Value.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
    }

    return @()
}

function Get-PropertyByNames {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    $props = Get-ObjectProperties -Value $Object
    foreach ($name in $Names) {
        $prop = $props | Where-Object { $_.Name -ceq $name } | Select-Object -First 1
        if ($null -ne $prop) {
            return $prop.Value
        }
    }

    foreach ($name in $Names) {
        $prop = $props | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($null -ne $prop) {
            return $prop.Value
        }
    }

    return $null
}

function ConvertTo-TokenNumber {
    param($Value)

    if ($null -eq $Value) {
        return 0L
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 0L
    }

    $number = 0.0
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        if ($number -lt 0) {
            return 0L
        }
        return [int64][Math]::Round($number)
    }

    return 0L
}

function ConvertTo-TokenDoubleOrNull {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $number = 0.0
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return $number
    }

    return $null
}

function Get-JsonLineFieldValues {
    param(
        [Parameter(Mandatory = $true)][string]$Line,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    $values = New-Object System.Collections.Generic.List[object]
    foreach ($name in $Names) {
        $escaped = [regex]::Escape($name)
        $pattern = '(?<!\\)"' + $escaped + '"\s*:\s*(?:"([^"]*)"|(-?\d+(?:\.\d+)?))'
        foreach ($match in [regex]::Matches($Line, $pattern)) {
            if ($match.Groups[1].Success) {
                $values.Add($match.Groups[1].Value)
            }
            elseif ($match.Groups[2].Success) {
                $values.Add($match.Groups[2].Value)
            }
        }
    }
    return @($values.ToArray())
}

function Read-TokenEventFromJsonLineFast {
    param(
        [Parameter(Mandatory = $true)][string]$Line,
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    $timestamp = $null
    foreach ($rawTimestamp in (Get-JsonLineFieldValues -Line $Line -Names $script:TimestampFields)) {
        $timestamp = ConvertTo-TokenDateTime -Value $rawTimestamp
        if ($null -ne $timestamp) {
            break
        }
    }

    if ($null -eq $timestamp) {
        return $null
    }

    $tokens = 0L
    $cumulativeTokens = 0L
    $totalUsageMatch = [regex]::Match($Line, '(?<!\\)"total_token_usage"\s*:\s*\{(?<body>[^{}]*)\}')
    if ($totalUsageMatch.Success) {
        $totalUsageBody = $totalUsageMatch.Groups['body'].Value
        foreach ($value in (Get-JsonLineFieldValues -Line $totalUsageBody -Names $script:TotalTokenFields)) {
            $cumulativeTokens += ConvertTo-TokenNumber -Value $value
        }
        if ($cumulativeTokens -le 0) {
            foreach ($value in (Get-JsonLineFieldValues -Line $totalUsageBody -Names $script:PartTokenFields)) {
                $cumulativeTokens += ConvertTo-TokenNumber -Value $value
            }
        }
    }

    $lastUsageMatch = [regex]::Match($Line, '(?<!\\)"last_token_usage"\s*:\s*\{(?<body>[^{}]*)\}')
    if ($lastUsageMatch.Success) {
        $lastUsageBody = $lastUsageMatch.Groups['body'].Value
        foreach ($value in (Get-JsonLineFieldValues -Line $lastUsageBody -Names $script:TotalTokenFields)) {
            $tokens += ConvertTo-TokenNumber -Value $value
        }
        if ($tokens -le 0) {
            foreach ($value in (Get-JsonLineFieldValues -Line $lastUsageBody -Names $script:PartTokenFields)) {
                $tokens += ConvertTo-TokenNumber -Value $value
            }
        }
    }

    if ($tokens -le 0 -and -not $lastUsageMatch.Success -and -not $totalUsageMatch.Success) {
        foreach ($value in (Get-JsonLineFieldValues -Line $Line -Names $script:TotalTokenFields)) {
            $tokens += ConvertTo-TokenNumber -Value $value
        }
        if ($tokens -le 0) {
            foreach ($value in (Get-JsonLineFieldValues -Line $Line -Names $script:PartTokenFields)) {
                $tokens += ConvertTo-TokenNumber -Value $value
            }
        }
    }

    $fiveHourUsedPercent = $null
    $weeklyUsedPercent = $null
    $fiveHourResetAtUtc = $null
    $weeklyResetAtUtc = $null
    foreach ($limitMatch in [regex]::Matches($Line, '(?<!\\)"(primary|secondary)"\s*:\s*\{(?<body>[^{}]*)\}')) {
        $body = $limitMatch.Groups['body'].Value
        $usedValue = Get-JsonLineFieldValues -Line $body -Names @('used_percent', 'usedPercent') | Select-Object -First 1
        $windowValue = Get-JsonLineFieldValues -Line $body -Names @('window_minutes', 'windowMinutes') | Select-Object -First 1
        if ($null -eq $usedValue -or $null -eq $windowValue) {
            continue
        }

        $usedPercentNumber = ConvertTo-TokenDoubleOrNull -Value $usedValue
        if ($null -eq $usedPercentNumber) {
            continue
        }
        $windowMinutes = [int](ConvertTo-TokenNumber -Value $windowValue)
        $resetAtValue = Get-JsonLineFieldValues -Line $body -Names @('resets_at', 'resetsAt') | Select-Object -First 1
        $resetAtUtc = ConvertTo-TokenDateTime -Value $resetAtValue
        if ($windowMinutes -eq 300) {
            $fiveHourUsedPercent = $usedPercentNumber
            $fiveHourResetAtUtc = $resetAtUtc
        }
        elseif ($windowMinutes -eq 10080) {
            $weeklyUsedPercent = $usedPercentNumber
            $weeklyResetAtUtc = $resetAtUtc
        }
    }

    if ($tokens -le 0 -and $null -eq $fiveHourUsedPercent -and $null -eq $weeklyUsedPercent) {
        return $null
    }

    return [pscustomobject]@{
        ProviderId = $ProviderId
        TimestampUtc = $timestamp
        Tokens = $tokens
        CumulativeTokens = $cumulativeTokens
        SourcePath = $SourcePath
        FiveHourUsedPercent = $fiveHourUsedPercent
        WeeklyUsedPercent = $weeklyUsedPercent
        FiveHourResetAtUtc = $fiveHourResetAtUtc
        WeeklyResetAtUtc = $weeklyResetAtUtc
    }
}

function Test-JsonLineMightContainUsage {
    param([Parameter(Mandatory = $true)][string]$Line)

    return (
        $Line.IndexOf('last_token_usage', [StringComparison]::Ordinal) -ge 0 -or
        $Line.IndexOf('total_token_usage', [StringComparison]::Ordinal) -ge 0 -or
        $Line.IndexOf('rate_limits', [StringComparison]::Ordinal) -ge 0 -or
        $Line.IndexOf('"usage"', [StringComparison]::Ordinal) -ge 0 -or
        $Line.IndexOf('total_tokens', [StringComparison]::Ordinal) -ge 0 -or
        $Line.IndexOf('totalTokens', [StringComparison]::Ordinal) -ge 0 -or
        $Line.IndexOf('input_tokens', [StringComparison]::Ordinal) -ge 0 -or
        $Line.IndexOf('inputTokens', [StringComparison]::Ordinal) -ge 0 -or
        $Line.IndexOf('output_tokens', [StringComparison]::Ordinal) -ge 0 -or
        $Line.IndexOf('outputTokens', [StringComparison]::Ordinal) -ge 0
    )
}

function Get-UsageTokenCount {
    param($Object)

    if ($null -eq $Object) {
        return 0L
    }

    $total = ConvertTo-TokenNumber (Get-PropertyByNames -Object $Object -Names $script:TotalTokenFields)
    if ($total -gt 0) {
        return $total
    }

    $sum = 0L
    foreach ($name in $script:PartTokenFields) {
        $sum += ConvertTo-TokenNumber (Get-PropertyByNames -Object $Object -Names @($name))
    }

    return $sum
}

function Get-LocalTimestamp {
    param($Object)

    $raw = Get-PropertyByNames -Object $Object -Names $script:TimestampFields
    return (ConvertTo-TokenDateTime -Value $raw)
}

function Read-TokenEventsFromNode {
    param(
        [Parameter(Mandatory = $true)]$Node,
        [AllowNull()]$InheritedTimestamp,
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    $events = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Node) {
        return @($events.ToArray())
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string]) -and -not ($Node -is [pscustomobject]) -and -not ($Node -is [System.Collections.IDictionary])) {
        foreach ($item in $Node) {
            foreach ($event in (Read-TokenEventsFromNode -Node $item -InheritedTimestamp $InheritedTimestamp -ProviderId $ProviderId -SourcePath $SourcePath)) {
                $events.Add($event)
            }
        }
        return @($events.ToArray())
    }

    $props = Get-ObjectProperties -Value $Node
    if ($props.Count -eq 0) {
        return @($events.ToArray())
    }

    $timestamp = Get-LocalTimestamp -Object $Node
    if ($null -eq $timestamp) {
        $timestamp = $InheritedTimestamp
    }

    $tokenCount = Get-UsageTokenCount -Object $Node
    if ($tokenCount -gt 0 -and $null -ne $timestamp) {
        $events.Add([pscustomobject]@{
            ProviderId = $ProviderId
            TimestampUtc = $timestamp
            Tokens = $tokenCount
            CumulativeTokens = 0L
            SourcePath = $SourcePath
            FiveHourUsedPercent = $null
            WeeklyUsedPercent = $null
            FiveHourResetAtUtc = $null
            WeeklyResetAtUtc = $null
        })
        return @($events.ToArray())
    }

    foreach ($prop in $props) {
        $value = $prop.Value
        if ($null -eq $value) {
            continue
        }

        if ($value -is [pscustomobject] -or $value -is [System.Collections.IDictionary] -or ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string]))) {
            foreach ($event in (Read-TokenEventsFromNode -Node $value -InheritedTimestamp $timestamp -ProviderId $ProviderId -SourcePath $SourcePath)) {
                $events.Add($event)
            }
        }
    }

    return @($events.ToArray())
}

function Get-CandidateUsageFiles {
    param(
        [Parameter(Mandatory = $true)]$Provider,
        [Parameter(Mandatory = $true)][DateTime]$SinceUtc,
        [Parameter(Mandatory = $true)][long]$MaxFileBytes
    )

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $patterns = @($Provider.FilePatterns)
    if ($patterns.Count -eq 0) {
        $patterns = @('*.jsonl', '*.json')
    }

    foreach ($root in @($Provider.ScanRoots)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) {
            continue
        }

        $expanded = Expand-TokenMonitorPath -Path ([string]$root)
        if (-not (Test-Path -LiteralPath $expanded)) {
            continue
        }

        $item = Get-Item -LiteralPath $expanded -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            continue
        }

        if (-not $item.PSIsContainer) {
            if ($item.LastWriteTimeUtc -ge $SinceUtc -and $item.Length -le $MaxFileBytes) {
                $files.Add([System.IO.FileInfo]$item)
            }
            continue
        }

        foreach ($pattern in $patterns) {
            Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTimeUtc -ge $SinceUtc -and $_.Length -le $MaxFileBytes } |
                ForEach-Object { $files.Add([System.IO.FileInfo]$_) }
        }
    }

    return @($files | Sort-Object FullName -Unique)
}

function Read-TokenEventsFromFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][DateTime]$SinceUtc
    )

    $events = New-Object System.Collections.Generic.List[object]
    $extension = $File.Extension.ToLowerInvariant()

    try {
        if ($extension -eq '.json') {
            $json = [System.IO.File]::ReadAllText($File.FullName)
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $root = $json | ConvertFrom-Json
                foreach ($event in (Read-TokenEventsFromNode -Node $root -InheritedTimestamp $null -ProviderId $ProviderId -SourcePath $File.FullName)) {
                    if ($event.TimestampUtc -ge $SinceUtc) {
                        $events.Add($event)
                    }
                }
            }
            return @($events.ToArray())
        }

        foreach ($line in [System.IO.File]::ReadLines($File.FullName)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            if (-not (Test-JsonLineMightContainUsage -Line $line)) {
                continue
            }

            $event = Read-TokenEventFromJsonLineFast -Line $line -ProviderId $ProviderId -SourcePath $File.FullName
            if ($null -ne $event) {
                if ($event.TimestampUtc -ge $SinceUtc) {
                    $events.Add($event)
                }
            }
        }
    }
    catch {
        return @($events.ToArray())
    }

    return @($events.ToArray())
}

function Get-RemainingPercent {
    param(
        [long]$Used,
        [long]$Limit
    )

    if ($Limit -le 0) {
        return $null
    }

    $remaining = [Math]::Max(0, $Limit - $Used)
    return [Math]::Round(($remaining / [double]$Limit) * 100, 1)
}

function Get-RemainingPercentFromRateLimit {
    param(
        $UsedPercent,
        $ResetAtUtc,
        [Parameter(Mandatory = $true)][DateTime]$NowUtc
    )

    if ($null -eq $UsedPercent) {
        return $null
    }

    if ($null -ne $ResetAtUtc -and ([DateTime]$ResetAtUtc) -le $NowUtc) {
        return 100.0
    }

    return [Math]::Max(0, [Math]::Min(100, [Math]::Round(100.0 - [double]$UsedPercent, 1)))
}

function Get-TokenWindowUsage {
    param(
        [Parameter(Mandatory = $true)]$Events,
        [Parameter(Mandatory = $true)][DateTime]$CutoffUtc,
        [bool]$PreferCumulative = $false
    )

    if (-not $PreferCumulative) {
        $sum = 0L
        foreach ($event in $Events) {
            if ($event.TimestampUtc -ge $CutoffUtc) {
                $sum += [int64]$event.Tokens
            }
        }
        return $sum
    }

    $total = 0L
    foreach ($group in ($Events | Group-Object SourcePath)) {
        $previousCumulative = $null
        foreach ($event in ($group.Group | Sort-Object TimestampUtc)) {
            $currentCumulative = 0L
            if (Get-Member -InputObject $event -Name CumulativeTokens -MemberType NoteProperty -ErrorAction SilentlyContinue) {
                $currentCumulative = [int64]$event.CumulativeTokens
            }

            if ($event.TimestampUtc -lt $CutoffUtc) {
                if ($currentCumulative -gt 0) {
                    $previousCumulative = $currentCumulative
                }
                continue
            }

            if ($currentCumulative -gt 0) {
                $delta = 0L
                if ($null -ne $previousCumulative -and $currentCumulative -ge [int64]$previousCumulative) {
                    $delta = $currentCumulative - [int64]$previousCumulative
                }
                elseif ([int64]$event.Tokens -gt 0) {
                    $delta = [int64]$event.Tokens
                }
                $total += [Math]::Max(0, $delta)
                $previousCumulative = $currentCumulative
            }
            elseif ([int64]$event.Tokens -gt 0) {
                $total += [int64]$event.Tokens
            }
        }
    }

    return $total
}

function Invoke-TokenProviderCommand {
    param($Provider)

    if (-not (Get-Member -InputObject $Provider -Name Command -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        return $null
    }

    $command = [string]$Provider.Command
    if ([string]::IsNullOrWhiteSpace($command)) {
        return $null
    }

    $timeoutSeconds = 15
    if (Get-Member -InputObject $Provider -Name CommandTimeoutSeconds -MemberType NoteProperty -ErrorAction SilentlyContinue) {
        $timeoutSeconds = [Math]::Max(1, [int]$Provider.CommandTimeoutSeconds)
    }

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            return [pscustomobject]@{ Error = "Command timed out after $timeoutSeconds seconds" }
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) {
            return [pscustomobject]@{ Error = "Command failed with exit code $($process.ExitCode): $stderr" }
        }
        if ([string]::IsNullOrWhiteSpace($stdout)) {
            return [pscustomobject]@{ Error = 'Command produced no JSON output' }
        }

        return ($stdout | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{ Error = $_.Exception.Message }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Get-TokenUsageSnapshot {
    param($Settings)

    $nowUtc = [DateTime]::UtcNow
    $fiveHourCutoff = $nowUtc.AddHours(-5)
    $weeklyCutoff = $nowUtc.AddDays(-7)
    $maxFileSizeMB = 20
    if (Get-Member -InputObject $Settings -Name MaxFileSizeMB -MemberType NoteProperty -ErrorAction SilentlyContinue) {
        $maxFileSizeMB = [Math]::Max(1, [int]$Settings.MaxFileSizeMB)
    }
    $maxFileBytes = [int64]$maxFileSizeMB * 1024L * 1024L
    $providers = New-Object System.Collections.Generic.List[object]

    foreach ($provider in @($Settings.Providers)) {
        $enabled = $true
        if (Get-Member -InputObject $provider -Name Enabled -MemberType NoteProperty -ErrorAction SilentlyContinue) {
            $enabled = [bool]$provider.Enabled
        }

        if (-not $enabled) {
            $providers.Add([pscustomobject]@{
                Id = $provider.Id
                Name = $provider.Name
                Enabled = $false
                FiveHourLimit = [int64]$provider.FiveHourLimit
                WeeklyLimit = [int64]$provider.WeeklyLimit
                FiveHourUsed = 0L
                WeeklyUsed = 0L
                FiveHourRemainingPercent = $null
                WeeklyRemainingPercent = $null
                Events = 0
                Files = 0
                LastEventLocal = $null
                Status = 'Disabled'
            })
            continue
        }

        $hasCommand = $false
        if (Get-Member -InputObject $provider -Name Command -MemberType NoteProperty -ErrorAction SilentlyContinue) {
            $hasCommand = -not [string]::IsNullOrWhiteSpace($provider.Command)
        }

        if ($hasCommand) {
            $fiveLimit = [int64]$provider.FiveHourLimit
            $weekLimit = [int64]$provider.WeeklyLimit
            $fiveHourUsed = 0L
            $weeklyUsed = 0L
            $fiveHourRemainingPercent = Get-RemainingPercent -Used $fiveHourUsed -Limit $fiveLimit
            $weeklyRemainingPercent = Get-RemainingPercent -Used $weeklyUsed -Limit $weekLimit
            $fiveHourUsedDisplay = Format-TokenCount -Value $fiveHourUsed
            $weeklyUsedDisplay = Format-TokenCount -Value $weeklyUsed
            
            $commandStatus = 'Command OK'
            $commandData = Invoke-TokenProviderCommand -Provider $provider
            if ($null -ne $commandData) {
                if (Get-Member -InputObject $commandData -Name Error -MemberType NoteProperty -ErrorAction SilentlyContinue) {
                    $commandStatus = $commandData.Error
                }
                else {
                    $commandFiveUsed = ConvertTo-TokenNumber (Get-PropertyByNames -Object $commandData -Names @('fiveHourUsed', 'five_hour_used', 'tokens5h', 'used5h'))
                    $commandWeekUsed = ConvertTo-TokenNumber (Get-PropertyByNames -Object $commandData -Names @('weeklyUsed', 'weekUsed', 'sevenDayUsed', 'seven_day_used', 'tokens7d', 'used7d'))
                    if ($commandFiveUsed -gt 0) {
                        $fiveHourUsed = $commandFiveUsed
                        $fiveHourRemainingPercent = Get-RemainingPercent -Used $fiveHourUsed -Limit $fiveLimit
                        $fiveHourUsedDisplay = Format-TokenCount -Value $fiveHourUsed
                    }
                    if ($commandWeekUsed -gt 0) {
                        $weeklyUsed = $commandWeekUsed
                        $weeklyRemainingPercent = Get-RemainingPercent -Used $weeklyUsed -Limit $weekLimit
                        $weeklyUsedDisplay = Format-TokenCount -Value $weeklyUsed
                    }

                    $commandFiveRemaining = ConvertTo-TokenDoubleOrNull (Get-PropertyByNames -Object $commandData -Names @('fiveHourRemainingPercent', 'five_hour_remaining_percent', 'remaining5hPercent'))
                    $commandWeekRemaining = ConvertTo-TokenDoubleOrNull (Get-PropertyByNames -Object $commandData -Names @('weeklyRemainingPercent', 'weekRemainingPercent', 'sevenDayRemainingPercent', 'remaining7dPercent'))
                    $commandFiveUsedPercent = ConvertTo-TokenDoubleOrNull (Get-PropertyByNames -Object $commandData -Names @('fiveHourUsedPercent', 'five_hour_used_percent', 'used5hPercent'))
                    $commandWeekUsedPercent = ConvertTo-TokenDoubleOrNull (Get-PropertyByNames -Object $commandData -Names @('weeklyUsedPercent', 'weekUsedPercent', 'sevenDayUsedPercent', 'used7dPercent'))

                    if ($null -ne $commandFiveRemaining) {
                        $fiveHourRemainingPercent = [Math]::Max(0, [Math]::Min(100, [Math]::Round([double]$commandFiveRemaining, 1)))
                        $fiveHourUsedDisplay = ('{0:N0}% used' -f (100.0 - $fiveHourRemainingPercent))
                    }
                    elseif ($null -ne $commandFiveUsedPercent) {
                        $fiveHourRemainingPercent = [Math]::Max(0, [Math]::Round(100.0 - [double]$commandFiveUsedPercent, 1))
                        $fiveHourUsedDisplay = ('{0:N0}% used' -f [double]$commandFiveUsedPercent)
                    }

                    if ($null -ne $commandWeekRemaining) {
                        $weeklyRemainingPercent = [Math]::Max(0, [Math]::Min(100, [Math]::Round([double]$commandWeekRemaining, 1)))
                        $weeklyUsedDisplay = ('{0:N0}% used' -f (100.0 - $weeklyRemainingPercent))
                    }
                    elseif ($null -ne $commandWeekUsedPercent) {
                        $weeklyRemainingPercent = [Math]::Max(0, [Math]::Round(100.0 - [double]$commandWeekUsedPercent, 1))
                        $weeklyUsedDisplay = ('{0:N0}% used' -f [double]$commandWeekUsedPercent)
                    }
                }
            }
            else {
                $commandStatus = 'Command produced no output'
            }

            $providers.Add([pscustomobject]@{
                Id = $provider.Id
                Name = $provider.Name
                Enabled = $true
                FiveHourLimit = $fiveLimit
                WeeklyLimit = $weekLimit
                FiveHourUsed = $fiveHourUsed
                WeeklyUsed = $weeklyUsed
                FiveHourUsedDisplay = $fiveHourUsedDisplay
                WeeklyUsedDisplay = $weeklyUsedDisplay
                FiveHourRemainingPercent = $fiveHourRemainingPercent
                WeeklyRemainingPercent = $weeklyRemainingPercent
                Events = 0
                Files = 0
                LastEventLocal = $null
                Status = $commandStatus
            })
            continue
        }

        $files = @(Get-CandidateUsageFiles -Provider $provider -SinceUtc $weeklyCutoff -MaxFileBytes $maxFileBytes)
        $events = New-Object System.Collections.Generic.List[object]
        foreach ($file in $files) {
            foreach ($event in (Read-TokenEventsFromFile -File $file -ProviderId $provider.Id -SinceUtc $weeklyCutoff)) {
                $events.Add($event)
            }
        }

        $preferCumulative = ([string]$provider.Id -ieq 'codex')
        $weeklyUsed = Get-TokenWindowUsage -Events @($events.ToArray()) -CutoffUtc $weeklyCutoff -PreferCumulative $preferCumulative
        $fiveHourUsed = Get-TokenWindowUsage -Events @($events.ToArray()) -CutoffUtc $fiveHourCutoff -PreferCumulative $preferCumulative
        $lastEvent = $events | Sort-Object TimestampUtc -Descending | Select-Object -First 1
        $lastLocal = $null
        if ($null -ne $lastEvent) {
            $lastLocal = ([DateTime]$lastEvent.TimestampUtc).ToLocalTime()
        }

        $fiveLimit = [int64]$provider.FiveHourLimit
        $weekLimit = [int64]$provider.WeeklyLimit
        $fiveHourRemainingPercent = Get-RemainingPercent -Used $fiveHourUsed -Limit $fiveLimit
        $weeklyRemainingPercent = Get-RemainingPercent -Used $weeklyUsed -Limit $weekLimit
        $fiveHourUsedDisplay = Format-TokenCount -Value $fiveHourUsed
        $weeklyUsedDisplay = Format-TokenCount -Value $weeklyUsed
        $latestFiveHourLimitEvent = $events |
            Where-Object { $null -ne $_.FiveHourUsedPercent } |
            Sort-Object TimestampUtc -Descending |
            Select-Object -First 1
        $latestWeeklyLimitEvent = $events |
            Where-Object { $null -ne $_.WeeklyUsedPercent } |
            Sort-Object TimestampUtc -Descending |
            Select-Object -First 1
        if ($fiveLimit -le 0 -and $null -ne $latestFiveHourLimitEvent -and $null -ne $latestFiveHourLimitEvent.FiveHourUsedPercent) {
            $fiveHourRemainingPercent = Get-RemainingPercentFromRateLimit `
                -UsedPercent $latestFiveHourLimitEvent.FiveHourUsedPercent `
                -ResetAtUtc $latestFiveHourLimitEvent.FiveHourResetAtUtc `
                -NowUtc $nowUtc
            if ($null -ne $fiveHourRemainingPercent) {
                $fiveHourUsedDisplay = ('{0:N0}% used' -f (100.0 - [double]$fiveHourRemainingPercent))
            }
        }
        if ($weekLimit -le 0 -and $null -ne $latestWeeklyLimitEvent -and $null -ne $latestWeeklyLimitEvent.WeeklyUsedPercent) {
            $weeklyRemainingPercent = Get-RemainingPercentFromRateLimit `
                -UsedPercent $latestWeeklyLimitEvent.WeeklyUsedPercent `
                -ResetAtUtc $latestWeeklyLimitEvent.WeeklyResetAtUtc `
                -NowUtc $nowUtc
            if ($null -ne $weeklyRemainingPercent) {
                $weeklyUsedDisplay = ('{0:N0}% used' -f (100.0 - [double]$weeklyRemainingPercent))
            }
        }

        $status = 'OK'
        if ($files.Count -eq 0) {
            $status = 'No files'
        }
        elseif ($events.Count -eq 0) {
            $status = 'No usage events'
        }
        elseif (($fiveLimit -le 0 -and $null -eq $fiveHourRemainingPercent) -or ($weekLimit -le 0 -and $null -eq $weeklyRemainingPercent)) {
            $status = 'Set quota'
        }

        $providers.Add([pscustomobject]@{
            Id = $provider.Id
            Name = $provider.Name
            Enabled = $true
            FiveHourLimit = $fiveLimit
            WeeklyLimit = $weekLimit
            FiveHourUsed = $fiveHourUsed
            WeeklyUsed = $weeklyUsed
            FiveHourUsedDisplay = $fiveHourUsedDisplay
            WeeklyUsedDisplay = $weeklyUsedDisplay
            FiveHourRemainingPercent = $fiveHourRemainingPercent
            WeeklyRemainingPercent = $weeklyRemainingPercent
            Events = $events.Count
            Files = $files.Count
            LastEventLocal = $lastLocal
            Status = $status
        })
    }

    return [pscustomobject]@{
        GeneratedAtLocal = (Get-Date)
        Providers = @($providers.ToArray())
    }
}

function Format-TokenCount {
    param([long]$Value)

    if ($Value -ge 1000000000) {
        return ('{0:N1}B' -f ($Value / 1000000000.0))
    }
    if ($Value -ge 1000000) {
        return ('{0:N1}M' -f ($Value / 1000000.0))
    }
    if ($Value -ge 1000) {
        return ('{0:N1}K' -f ($Value / 1000.0))
    }
    return [string]$Value
}

function Format-Percent {
    param($Value)

    if ($null -eq $Value) {
        return 'n/a'
    }
    return ('{0:N0}%' -f [double]$Value)
}

function Format-ProviderWindowPercent {
    param(
        $Provider,
        [string]$Window
    )

    if ($Window -eq '5h') {
        return (Format-Percent -Value $Provider.FiveHourRemainingPercent)
    }
    if ($Window -eq '7d') {
        return (Format-Percent -Value $Provider.WeeklyRemainingPercent)
    }
    return 'n/a'
}

function Format-TokenUsageTooltip {
    param($Snapshot)

    $fiveHourParts = New-Object System.Collections.Generic.List[string]
    $weeklyParts = New-Object System.Collections.Generic.List[string]
    foreach ($provider in @($Snapshot.Providers)) {
        if (-not $provider.Enabled) {
            continue
        }

        $shortName = switch ($provider.Id) {
            'antigravity' { 'G' }
            'codex' { 'C' }
            'claude' { 'Cl' }
            default { $provider.Name }
        }

        $fiveHourParts.Add(('{0}:{1}' -f $shortName, (Format-ProviderWindowPercent -Provider $provider -Window '5h')))
        $weeklyParts.Add(('{0}:{1}' -f $shortName, (Format-ProviderWindowPercent -Provider $provider -Window '7d')))
    }

    $text = 'TokenMonitor'
    if ($fiveHourParts.Count -gt 0 -or $weeklyParts.Count -gt 0) {
        $text = ('5h {0}' -f ($fiveHourParts -join ' '))
        if ($weeklyParts.Count -gt 0) {
            $text += ("`n7d {0}" -f ($weeklyParts -join ' '))
        }
    }

    if ($text.Length -gt 63) {
        return $text.Substring(0, 63)
    }
    return $text
}

Export-ModuleMember -Function `
    Get-TokenMonitorAppDir, `
    Get-TokenMonitorSettingsPath, `
    New-DefaultTokenSettings, `
    Read-TokenMonitorSettings, `
    Save-TokenMonitorSettings, `
    Get-TokenUsageSnapshot, `
    Format-TokenCount, `
    Format-Percent, `
    Format-TokenUsageTooltip
