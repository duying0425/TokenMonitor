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

function Get-TokenMonitorQuotaCachePath {
    return (Join-Path (Get-TokenMonitorAppDir) 'quota-cache.json')
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

function Get-DefaultAntigravityCommand {
    return @'
# TokenMonitorAntigravityQuotaCommandVersion=3
try {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $candidates = New-Object System.Collections.Generic.List[object]

    $hubLog = Join-Path $env:APPDATA "Antigravity\logs\main.log"
    if (Test-Path -LiteralPath $hubLog) {
        $log = Get-Content -LiteralPath $hubLog -Raw -ErrorAction Stop
        $matches = [regex]::Matches($log, "--csrf_token\s+(?<csrf>[0-9a-fA-F-]+)[\s\S]*?Local:\s+https://127\.0\.0\.1:(?<port>\d+)/")
        $added = 0
        for ($i = $matches.Count - 1; $i -ge 0 -and $added -lt 4; $i--) {
            [void]$candidates.Add([pscustomobject]@{
                Source = "Antigravity"
                Port = $matches[$i].Groups["port"].Value
                Csrf = $matches[$i].Groups["csrf"].Value
            })
            $added++
        }
    }

    $ideLogsRoot = Join-Path $env:APPDATA "Antigravity IDE\logs"
    if (Test-Path -LiteralPath $ideLogsRoot) {
        $ideLogs = Get-ChildItem -LiteralPath $ideLogsRoot -Recurse -File -Filter "ls-main.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 8
        foreach ($ideLog in $ideLogs) {
            if ($candidates.Count -ge 12) {
                break
            }
            $log = Get-Content -LiteralPath $ideLog.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($log)) {
                continue
            }
            $matches = [regex]::Matches($log, "--csrf_token\s+(?<csrf>[0-9a-fA-F-]+)[\s\S]*?Language server listening on random port at (?<port>\d+) for HTTPS")
            for ($i = $matches.Count - 1; $i -ge 0 -and $candidates.Count -lt 12; $i--) {
                [void]$candidates.Add([pscustomobject]@{
                    Source = "Antigravity IDE"
                    Port = $matches[$i].Groups["port"].Value
                    Csrf = $matches[$i].Groups["csrf"].Value
                })
            }
        }
    }

    if ($candidates.Count -eq 0) {
        [PSCustomObject]@{ Error = "No Antigravity local service logs found; start Antigravity or Antigravity IDE first" } | ConvertTo-Json -Compress
        exit
    }

    $uniqueCandidates = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($candidate in $candidates) {
        $key = "$($candidate.Port)|$($candidate.Csrf)"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$uniqueCandidates.Add($candidate)
        }
    }
    $candidates = $uniqueCandidates

    $resp = $null
    $lastError = $null
    foreach ($candidate in $candidates) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connect = $tcp.BeginConnect("127.0.0.1", [int]$candidate.Port, $null, $null)
            if (-not $connect.AsyncWaitHandle.WaitOne(750, $false)) {
                $tcp.Close()
                continue
            }
            try {
                $tcp.EndConnect($connect)
            }
            finally {
                $connect.AsyncWaitHandle.Close()
                $tcp.Close()
            }

            $url = "https://127.0.0.1:$($candidate.Port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
            $headers = @{ "x-codeium-csrf-token" = $candidate.Csrf }
            $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body "{}" -ContentType "application/json" -TimeoutSec 3 -ErrorAction Stop
            break
        }
        catch {
            $lastError = $_.Exception.Message
            $resp = $null
        }
    }

    if (-not $resp) {
        [PSCustomObject]@{ Error = "Antigravity local service is not running; start Antigravity or Antigravity IDE first" } | ConvertTo-Json -Compress
        exit
    }

    $groups = @($resp.response.groups)
    $geminiGroup = $groups | Where-Object { $_.displayName -eq "Gemini Models" } | Select-Object -First 1
    if (-not $geminiGroup) {
        [PSCustomObject]@{ Error = "Gemini Models quota group not found in Antigravity response" } | ConvertTo-Json -Compress
        exit
    }

    $weekly = @($geminiGroup.buckets) | Where-Object { $_.window -eq "weekly" -or $_.bucketId -eq "gemini-weekly" } | Select-Object -First 1
    $five = @($geminiGroup.buckets) | Where-Object { $_.window -eq "5h" -or $_.bucketId -eq "gemini-5h" } | Select-Object -First 1

    $weeklyRemaining = $null
    $fiveRemaining = $null
    if ($weekly -and $null -ne $weekly.remainingFraction) {
        $weeklyRemaining = [Math]::Max(0.0, [Math]::Min(100.0, [Math]::Round([double]$weekly.remainingFraction * 100.0, 1)))
    }
    if ($five -and $null -ne $five.remainingFraction) {
        $fiveRemaining = [Math]::Max(0.0, [Math]::Min(100.0, [Math]::Round([double]$five.remainingFraction * 100.0, 1)))
        if ($five.disabled) {
            $fiveRemaining = 0.0
        }
    }

    [PSCustomObject]@{
        fiveHourRemainingPercent = $fiveRemaining
        weeklyRemainingPercent = $weeklyRemaining
        fiveHourResetAt = $five.resetTime
        weeklyResetAt = $weekly.resetTime
    } | ConvertTo-Json -Compress
}
catch {
    [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress
}
'@
}

function Get-DefaultClaudeCommand {
    return @'
$credsPath = if ($env:CLAUDE_CONFIG_DIR) {
    Join-Path $env:CLAUDE_CONFIG_DIR ".credentials.json"
} else {
    Join-Path $env:USERPROFILE ".claude\.credentials.json"
}

if (-not (Test-Path -LiteralPath $credsPath)) {
    [PSCustomObject]@{ Error = "No .credentials.json" } | ConvertTo-Json -Compress
    exit
}

function Save-ClaudeCredentials {
    param($Creds)
    $Creds | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $credsPath -Encoding UTF8
}

function Set-ClaudeOauthProperty {
    param($Oauth, [string]$Name, $Value)

    if (Get-Member -InputObject $Oauth -Name $Name -MemberType NoteProperty -ErrorAction SilentlyContinue) {
        $Oauth.$Name = $Value
    } else {
        $Oauth | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Update-ClaudeOauthToken {
    param($Creds)

    $oauth = $Creds.claudeAiOauth
    if (-not $oauth.refreshToken) {
        throw "OAuth token expired and no refreshToken is available; run claude /login again"
    }

    $rateLimitedUntil = [int64]0
    if ($oauth.refreshRateLimitedUntil) {
        [void][int64]::TryParse([string]$oauth.refreshRateLimitedUntil, [ref]$rateLimitedUntil)
    }
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if ($rateLimitedUntil -gt $nowMs) {
        $localUntil = [DateTimeOffset]::FromUnixTimeMilliseconds($rateLimitedUntil).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss zzz")
        throw "OAuth refresh is rate limited until $localUntil; stop TokenMonitor and run claude /login, or wait before retrying"
    }

    $clientId = $oauth.clientId
    if (-not $clientId) {
        $clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    }

    $body = @{
        grant_type = "refresh_token"
        refresh_token = $oauth.refreshToken
        client_id = $clientId
    }

    try {
        $refresh = Invoke-RestMethod `
            -Uri "https://platform.claude.com/v1/oauth/token" `
            -Method Post `
            -ContentType "application/x-www-form-urlencoded" `
            -Body $body `
            -ErrorAction Stop
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -eq 429) {
            $retryAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + (15 * 60 * 1000)
            Set-ClaudeOauthProperty -Oauth $oauth -Name "refreshRateLimitedUntil" -Value $retryAt
            Save-ClaudeCredentials -Creds $Creds
            $localRetryAt = [DateTimeOffset]::FromUnixTimeMilliseconds($retryAt).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss zzz")
            throw "OAuth refresh was rate limited; retry after $localRetryAt, or run claude /login to renew local credentials"
        }
        throw
    }

    $newAccessToken = $refresh.access_token
    if (-not $newAccessToken) {
        $newAccessToken = $refresh.accessToken
    }
    if (-not $newAccessToken) {
        throw "OAuth refresh response did not include an access token"
    }

    Set-ClaudeOauthProperty -Oauth $oauth -Name "accessToken" -Value $newAccessToken

    $newRefreshToken = $refresh.refresh_token
    if (-not $newRefreshToken) {
        $newRefreshToken = $refresh.refreshToken
    }
    if ($newRefreshToken) {
        Set-ClaudeOauthProperty -Oauth $oauth -Name "refreshToken" -Value $newRefreshToken
    }

    $expiresIn = $refresh.expires_in
    if (-not $expiresIn) {
        $expiresIn = $refresh.expiresIn
    }
    if ($expiresIn) {
        Set-ClaudeOauthProperty -Oauth $oauth -Name "expiresAt" -Value ([int64](([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) + ([double]$expiresIn * 1000)))
    }
    Set-ClaudeOauthProperty -Oauth $oauth -Name "refreshRateLimitedUntil" -Value 0

    Save-ClaudeCredentials -Creds $Creds
    return $oauth.accessToken
}

function Invoke-ClaudeUsage {
    param([string]$Token)

    $headers = @{
        Authorization = "Bearer $Token"
        "User-Agent" = "claude-code/2.1.186"
        "anthropic-beta" = "oauth-2025-04-20"
    }

    return Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" -Headers $headers -ErrorAction Stop
}

try {
    $creds = Get-Content -LiteralPath $credsPath -Raw | ConvertFrom-Json
    $oauth = $creds.claudeAiOauth
    if (-not $oauth) {
        [PSCustomObject]@{ Error = "No claudeAiOauth credentials" } | ConvertTo-Json -Compress
        exit
    }

    $token = $oauth.accessToken
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $expiresAt = [int64]0
    if ($oauth.expiresAt) {
        [void][int64]::TryParse([string]$oauth.expiresAt, [ref]$expiresAt)
    }

    if (-not $token -or ($expiresAt -gt 0 -and $expiresAt -lt ($nowMs + 120000))) {
        $token = Update-ClaudeOauthToken -Creds $creds
    }

    try {
        $resp = Invoke-ClaudeUsage -Token $token
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -ne 401) {
            throw
        }

        $creds = Get-Content -LiteralPath $credsPath -Raw | ConvertFrom-Json
        $token = Update-ClaudeOauthToken -Creds $creds
        $resp = Invoke-ClaudeUsage -Token $token
    }

    if ($resp) {
        $f = $resp.five_hour
        $w = $resp.seven_day
        $fReset = $f.resets_at
        if (-not $fReset) { $fReset = $f.reset_at }
        if (-not $fReset) { $fReset = $f.resetsAt }
        $wReset = $w.resets_at
        if (-not $wReset) { $wReset = $w.reset_at }
        if (-not $wReset) { $wReset = $w.resetsAt }
        [PSCustomObject]@{
            fiveHourUsedPercent = $f.utilization
            weeklyUsedPercent = $w.utilization
            fiveHourResetAt = $fReset
            weeklyResetAt = $wReset
        } | ConvertTo-Json -Compress
    } else {
        [PSCustomObject]@{ Error = "Empty API response" } | ConvertTo-Json -Compress
    }
}
catch {
    [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress
}
'@
}

function New-DefaultTokenSettings {
    $defaultGeminiCommand = Get-DefaultAntigravityCommand
    $defaultCodexCommand = '$authPath = "$env:USERPROFILE\.codex\auth.json"; if (-not (Test-Path -LiteralPath $authPath)) { [PSCustomObject]@{ Error = "No auth.json" } | ConvertTo-Json -Compress; exit }; try { $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json; $token = $auth.tokens.access_token; if (-not $token) { [PSCustomObject]@{ Error = "Not logged in" } | ConvertTo-Json -Compress; exit }; $headers = @{ Authorization = "Bearer $token"; "User-Agent" = "Mozilla/5.0" }; $resp = Invoke-RestMethod -Uri "https://chatgpt.com/backend-api/wham/usage" -Headers $headers -ErrorAction Stop; if ($resp) { $p = $resp.rate_limit.primary_window; $s = $resp.rate_limit.secondary_window; $pReset = $p.resets_at; if (-not $pReset) { $pReset = $p.reset_at }; if (-not $pReset) { $pReset = $p.resetsAt }; $sReset = $s.resets_at; if (-not $sReset) { $sReset = $s.reset_at }; if (-not $sReset) { $sReset = $s.resetsAt }; [PSCustomObject]@{ fiveHourUsedPercent = $p.used_percent; weeklyUsedPercent = $s.used_percent; fiveHourResetAt = $pReset; weeklyResetAt = $sReset } | ConvertTo-Json -Compress } else { [PSCustomObject]@{ Error = "Empty API response" } | ConvertTo-Json -Compress } } catch { [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress }'
    $defaultClaudeCommand = Get-DefaultClaudeCommand

    return [ordered]@{
        RefreshSeconds = 60
        MaxFileSizeMB = 20
        ShowStatusStrip = $true
        Providers = @(
            (New-ProviderConfig `
                -Id 'antigravity' `
                -Name 'Antigravity' `
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

    $defaultGeminiCommand = Get-DefaultAntigravityCommand
    $defaultCodexCommand = '$authPath = "$env:USERPROFILE\.codex\auth.json"; if (-not (Test-Path -LiteralPath $authPath)) { [PSCustomObject]@{ Error = "No auth.json" } | ConvertTo-Json -Compress; exit }; try { $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json; $token = $auth.tokens.access_token; if (-not $token) { [PSCustomObject]@{ Error = "Not logged in" } | ConvertTo-Json -Compress; exit }; $headers = @{ Authorization = "Bearer $token"; "User-Agent" = "Mozilla/5.0" }; $resp = Invoke-RestMethod -Uri "https://chatgpt.com/backend-api/wham/usage" -Headers $headers -ErrorAction Stop; if ($resp) { $p = $resp.rate_limit.primary_window; $s = $resp.rate_limit.secondary_window; $pReset = $p.resets_at; if (-not $pReset) { $pReset = $p.reset_at }; if (-not $pReset) { $pReset = $p.resetsAt }; $sReset = $s.resets_at; if (-not $sReset) { $sReset = $s.reset_at }; if (-not $sReset) { $sReset = $s.resetsAt }; [PSCustomObject]@{ fiveHourUsedPercent = $p.used_percent; weeklyUsedPercent = $s.used_percent; fiveHourResetAt = $pReset; weeklyResetAt = $sReset } | ConvertTo-Json -Compress } else { [PSCustomObject]@{ Error = "Empty API response" } | ConvertTo-Json -Compress } } catch { [PSCustomObject]@{ Error = $_.Exception.Message } | ConvertTo-Json -Compress }'
    $defaultClaudeCommand = Get-DefaultClaudeCommand

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

    $migrated = $false

    if (-not (Get-Member -InputObject $settings -Name RefreshSeconds -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        $settings | Add-Member -NotePropertyName RefreshSeconds -NotePropertyValue 60
        $migrated = $true
    }
    elseif ([int]$settings.RefreshSeconds -eq 600) {
        $settings.RefreshSeconds = 60
        $migrated = $true
    }
    if (-not (Get-Member -InputObject $settings -Name MaxFileSizeMB -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        $settings | Add-Member -NotePropertyName MaxFileSizeMB -NotePropertyValue 20
    }
    if (-not (Get-Member -InputObject $settings -Name ShowStatusStrip -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        $settings | Add-Member -NotePropertyName ShowStatusStrip -NotePropertyValue $true
    }

    # Remove the old antigravity-client provider if present (merging it back to antigravity)
    $filteredProviders = New-Object System.Collections.Generic.List[object]
    foreach ($p in $settings.Providers) {
        if ($p.Id -ne 'antigravity-client') {
            [void]$filteredProviders.Add($p)
        } else {
            $migrated = $true
        }
    }
    $settings.Providers = [object[]]($filteredProviders.ToArray())

    foreach ($provider in $settings.Providers) {
        if ($provider.Id -eq 'antigravity' -and $provider.Name -ne 'Antigravity') {
            $provider.Name = 'Antigravity'
            $migrated = $true
        }
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
            if ($provider.Id -eq 'antigravity' -and ([string]::IsNullOrWhiteSpace($provider.Command) -or ($provider.Command).IndexOf('gemini.google.com/usage', [StringComparison]::OrdinalIgnoreCase) -ge 0 -or ($provider.Command).IndexOf('v1internal:retrieveUserQuota', [StringComparison]::OrdinalIgnoreCase) -ge 0 -or ($provider.Command).IndexOf('RetrieveUserQuotaSummary', [StringComparison]::OrdinalIgnoreCase) -lt 0 -or ($provider.Command).IndexOf('TokenMonitorAntigravityQuotaCommandVersion=3', [StringComparison]::OrdinalIgnoreCase) -lt 0)) {
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
            elseif ($provider.Id -eq 'codex' -and
                ([string]$provider.Command).IndexOf('https://chatgpt.com/backend-api/wham/usage', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                ([string]$provider.Command).IndexOf('fiveHourResetAt', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                $provider.Command = $defaultCodexCommand
                $migrated = $true
            }
            elseif ($provider.Id -eq 'claude' -and
                ([string]$provider.Command).IndexOf('https://api.anthropic.com/api/oauth/usage', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                (([string]$provider.Command).IndexOf('fiveHourResetAt', [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
                ([string]$provider.Command).IndexOf('https://platform.claude.com/v1/oauth/token', [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
                ([string]$provider.Command).IndexOf('Set-ClaudeOauthProperty', [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
                ([string]$provider.Command).IndexOf('refreshRateLimitedUntil', [StringComparison]::OrdinalIgnoreCase) -lt 0)) {
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

    $jsonDateMatch = [regex]::Match($text, '^/Date\((?<ms>-?\d+)(?:[+-]\d+)?\)/$')
    if ($jsonDateMatch.Success) {
        try {
            return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$jsonDateMatch.Groups['ms'].Value).UtcDateTime
        }
        catch {
            return $null
        }
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

function ConvertTo-TokenIsoDateTimeString {
    param($Value)

    $dt = ConvertTo-TokenDateTime -Value $Value
    if ($null -eq $dt) {
        return $null
    }
    return ([DateTime]$dt).ToUniversalTime().ToString('o')
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

function ConvertTo-ResetHoursOrNull {
    param(
        $Value,
        [Parameter(Mandatory = $true)][DateTime]$NowUtc
    )

    if ($null -eq $Value) {
        return $null
    }

    $number = ConvertTo-TokenDoubleOrNull -Value $Value
    if ($null -ne $number) {
        return [Math]::Max(0.0, [double]$number)
    }

    $resetAtUtc = ConvertTo-TokenDateTime -Value $Value
    if ($null -eq $resetAtUtc) {
        return $null
    }

    return [Math]::Max(0.0, (([DateTime]$resetAtUtc) - $NowUtc).TotalHours)
}

function Get-ResetHoursFromAt {
    param(
        $Value,
        [Parameter(Mandatory = $true)][DateTime]$NowUtc
    )

    $resetAtUtc = ConvertTo-TokenDateTime -Value $Value
    if ($null -eq $resetAtUtc) {
        return $null
    }

    return [Math]::Max(0.0, (([DateTime]$resetAtUtc) - $NowUtc).TotalHours)
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

function Read-TokenMonitorQuotaCache {
    $path = Get-TokenMonitorQuotaCachePath
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{}
    }

    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{}
    }
}

function Save-TokenMonitorQuotaCache {
    param([Parameter(Mandatory = $true)]$Cache)

    $path = Get-TokenMonitorQuotaCachePath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $Cache | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function Get-TokenMonitorCacheProvider {
    param(
        [Parameter(Mandatory = $true)]$Cache,
        [Parameter(Mandatory = $true)][string]$ProviderId
    )

    $prop = Get-ObjectProperties -Value $Cache | Where-Object { $_.Name -ieq $ProviderId } | Select-Object -First 1
    if ($null -eq $prop) {
        return $null
    }
    return $prop.Value
}

function Set-TokenMonitorCacheProvider {
    param(
        [Parameter(Mandatory = $true)]$Cache,
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)]$Value
    )

    if (Get-Member -InputObject $Cache -Name $ProviderId -MemberType NoteProperty -ErrorAction SilentlyContinue) {
        $Cache.$ProviderId = $Value
    }
    else {
        $Cache | Add-Member -NotePropertyName $ProviderId -NotePropertyValue $Value
    }
}

function Get-CachedRemainingPercentFromLastVisible {
    param(
        $RemainingPercent,
        $ObservedAtUtc
    )

    $remaining = ConvertTo-TokenDoubleOrNull -Value $RemainingPercent
    if ($null -eq $remaining) {
        return $null
    }

    $observedUtc = ConvertTo-TokenDateTime -Value $ObservedAtUtc
    $remaining = [Math]::Max(0.0, [Math]::Min(100.0, [double]$remaining))

    if ($null -eq $observedUtc) {
        return $null
    }

    return [Math]::Round($remaining, 1)
}

function Get-EstimatedProviderQuotaFromCache {
    param(
        [Parameter(Mandatory = $true)]$Cache,
        [Parameter(Mandatory = $true)][DateTime]$NowUtc,
        [Parameter(Mandatory = $true)][string]$ProviderId
    )

    $cached = Get-TokenMonitorCacheProvider -Cache $Cache -ProviderId ${ProviderId}
    if ($null -eq $cached) {
        return $null
    }

    $observedAtUtc = ConvertTo-TokenDateTime -Value $cached.ObservedAtUtc
    if ($null -eq $observedAtUtc) {
        return $null
    }

    $fiveResetAtUtc = ConvertTo-TokenDateTime -Value $cached.FiveHourResetAtUtc
    $weeklyResetAtUtc = ConvertTo-TokenDateTime -Value $cached.WeeklyResetAtUtc
    $fiveRemaining = Get-CachedRemainingPercentFromLastVisible -RemainingPercent $cached.FiveHourRemainingPercent -ObservedAtUtc $observedAtUtc
    $weeklyRemaining = Get-CachedRemainingPercentFromLastVisible -RemainingPercent $cached.WeeklyRemainingPercent -ObservedAtUtc $observedAtUtc

    $fiveHourResetPassed = ($null -ne $fiveResetAtUtc -and ([DateTime]$fiveResetAtUtc) -le $NowUtc)
    $weeklyResetPassed = ($null -ne $weeklyResetAtUtc -and ([DateTime]$weeklyResetAtUtc) -le $NowUtc)

    if ($fiveHourResetPassed) {
        $fiveRemaining = 100.0
        $fiveResetAtUtc = $NowUtc.AddHours(5)
    }
    if ($weeklyResetPassed) {
        $weeklyRemaining = 100.0
        $weeklyResetAtUtc = $NowUtc.AddHours(168)
    }

    if ($null -eq $fiveRemaining -and $null -eq $weeklyRemaining) {
        return $null
    }

    return [pscustomobject]@{
        ObservedAtUtc = [DateTime]$observedAtUtc
        FiveHourRemainingPercent = $fiveRemaining
        WeeklyRemainingPercent = $weeklyRemaining
        FiveHourResetAtUtc = $fiveResetAtUtc
        WeeklyResetAtUtc = $weeklyResetAtUtc
        FiveHourResetHours = Get-ResetHoursFromAt -Value $fiveResetAtUtc -NowUtc $NowUtc
        WeeklyResetHours = Get-ResetHoursFromAt -Value $weeklyResetAtUtc -NowUtc $NowUtc
    }
}

function Update-ProviderQuotaCache {
    param(
        [Parameter(Mandatory = $true)]$Cache,
        [Parameter(Mandatory = $true)][DateTime]$NowUtc,
        [Parameter(Mandatory = $true)][string]$ProviderId,
        $FiveHourRemainingPercent,
        $WeeklyRemainingPercent,
        $FiveHourResetAt,
        $WeeklyResetAt
    )

    if ($null -eq $FiveHourRemainingPercent -and $null -eq $WeeklyRemainingPercent) {
        return
    }

    Set-TokenMonitorCacheProvider -Cache $Cache -ProviderId ${ProviderId} -Value ([pscustomobject]@{
        ObservedAtUtc = $NowUtc.ToString('o')
        FiveHourRemainingPercent = $FiveHourRemainingPercent
        WeeklyRemainingPercent = $WeeklyRemainingPercent
        FiveHourResetAtUtc = ConvertTo-TokenIsoDateTimeString -Value $FiveHourResetAt
        WeeklyResetAtUtc = ConvertTo-TokenIsoDateTimeString -Value $WeeklyResetAt
    })
    Save-TokenMonitorQuotaCache -Cache $Cache
}

function Test-TokenProviderStatusOk {
    param($Status)

    $text = [string]$Status
    return ([string]::IsNullOrWhiteSpace($text) -or $text -eq 'OK' -or $text -eq 'Command OK')
}

function New-TokenHealthText {
    param([string]$State)

    switch ($State) {
        'disabled' { return (-join ([char[]](24050, 20572, 29992))) }
        'empty' { return (-join ([char[]](27809, 26377, 20102))) }
        'low' { return (-join ([char[]](39532, 19978, 23601, 27809, 20102))) }
        'medium' { return (-join ([char[]](29992, 20102, 19981, 23569, 20102))) }
        'good' { return (-join ([char[]](36824, 21097, 24456, 22810))) }
        default { return (-join ([char[]](26080, 27861, 26816, 27979))) }
    }
}

function Get-ProviderTokenHealth {
    param(
        [bool]$Enabled = $true,
        $Status,
        $FiveHourRemainingPercent,
        $WeeklyRemainingPercent,
        $FiveHourResetHours,
        $WeeklyResetHours
    )

    $state = 'unknown'
    $text = New-TokenHealthText -State $state
    $percent = $null
    $window = $null
    $confidence = 'none'
    $reason = [string]$Status

    if (-not $Enabled) {
        return [pscustomobject]@{
            State = 'disabled'
            Text = (New-TokenHealthText -State 'disabled')
            Percent = $null
            Window = $null
            Confidence = 'none'
            Reason = 'Disabled'
        }
    }

    $hasFive = $null -ne $FiveHourRemainingPercent
    $hasWeek = $null -ne $WeeklyRemainingPercent
    if ($hasFive -and $hasWeek) {
        $confidence = 'high'
    }
    elseif ($hasFive -or $hasWeek) {
        $confidence = 'partial'
    }

    if (-not $hasFive -and -not $hasWeek) {
        return [pscustomobject]@{
            State = 'unknown'
            Text = (New-TokenHealthText -State 'unknown')
            Percent = $null
            Window = $null
            Confidence = $confidence
            Reason = $reason
        }
    }

    $five = $null
    $week = $null
    if ($hasFive) {
        $five = [Math]::Max(0, [Math]::Min(100, [double]$FiveHourRemainingPercent))
    }
    if ($hasWeek) {
        $week = [Math]::Max(0, [Math]::Min(100, [double]$WeeklyRemainingPercent))
    }

    if (($null -ne $five -and $five -le 0) -or ($null -ne $week -and $week -le 0)) {
        $state = 'empty'
        $text = New-TokenHealthText -State $state
        if ($null -ne $five -and ($null -eq $week -or $five -le $week)) {
            $percent = $five
            $window = '5h'
        }
        else {
            $percent = $week
            $window = '7d'
        }
    }
    elseif ($null -ne $week -and $week -le 10) {
        $state = 'low'
        $text = New-TokenHealthText -State $state
        $percent = $week
        $window = '7d'
    }
    elseif ($null -ne $five -and $five -le 15) {
        $state = 'low'
        $text = New-TokenHealthText -State $state
        $percent = $five
        $window = '5h'
    }
    elseif ($null -ne $five -and $five -le 50) {
        $state = 'medium'
        $text = New-TokenHealthText -State $state
        $percent = $five
        $window = '5h'
    }
    elseif ($null -ne $five) {
        $state = 'good'
        $text = New-TokenHealthText -State $state
        $percent = $five
        $window = '5h'
    }
    else {
        $state = 'unknown'
        $text = New-TokenHealthText -State $state
        $percent = $week
        $window = '7d'
    }

    if ($state -eq 'unknown' -and -not (Test-TokenProviderStatusOk -Status $Status)) {
        $reason = [string]$Status
    }

    return [pscustomobject]@{
        State = $state
        Text = $text
        Percent = $percent
        Window = $window
        Confidence = $confidence
        Reason = $reason
        FiveHourResetHours = $FiveHourResetHours
        WeeklyResetHours = $WeeklyResetHours
    }
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
    $quotaCache = Read-TokenMonitorQuotaCache

    foreach ($provider in @($Settings.Providers)) {
        $enabled = $true
        if (Get-Member -InputObject $provider -Name Enabled -MemberType NoteProperty -ErrorAction SilentlyContinue) {
            $enabled = [bool]$provider.Enabled
        }

        if (-not $enabled) {
            $health = Get-ProviderTokenHealth `
                -Enabled $false `
                -Status 'Disabled' `
                -FiveHourRemainingPercent $null `
                -WeeklyRemainingPercent $null `
                -FiveHourResetHours $null `
                -WeeklyResetHours $null
            if ($weekLimit -eq 0) { $fiveHourResetHours = 0 }
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
                FiveHourResetHours = $null
                WeeklyResetHours = $null
                Events = 0
                Files = 0
                LastEventLocal = $null
                Status = 'Disabled'
                HealthState = $health.State
                HealthText = $health.Text
                HealthPercent = $health.Percent
                HealthWindow = $health.Window
                HealthConfidence = $health.Confidence
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
            $fiveHourResetHours = $null
            $weeklyResetHours = $null
            $fiveHourResetAtUtc = $null
            $weeklyResetAtUtc = $null
            $lastVisibleLocal = $null
            $isEstimatedFromCache = $false
            
            $commandStatus = 'Command OK'
            $commandData = Invoke-TokenProviderCommand -Provider $provider
            if ($null -ne $commandData) {
                if (Get-Member -InputObject $commandData -Name Error -MemberType NoteProperty -ErrorAction SilentlyContinue) {
                    $commandStatus = $commandData.Error
                }
                else {
                    $lastVisibleLocal = $nowUtc.ToLocalTime()
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
                    $commandFiveResetAt = Get-PropertyByNames -Object $commandData -Names @('fiveHourResetAt', 'fiveHourResetAtUtc', 'five_hour_reset_at', 'five_hour_reset_at_utc', 'reset5hAt', 'resets5hAt')
                    $commandWeekResetAt = Get-PropertyByNames -Object $commandData -Names @('weeklyResetAt', 'weeklyResetAtUtc', 'weekResetAt', 'sevenDayResetAt', 'sevenDayResetAtUtc', 'weekly_reset_at', 'seven_day_reset_at', 'reset7dAt', 'resets7dAt')
                    $commandFiveResetHours = Get-PropertyByNames -Object $commandData -Names @('fiveHourResetHours', 'fiveHourResetsInHours', 'five_hour_reset_hours', 'reset5hHours', 'resets5hInHours')
                    $commandWeekResetHours = Get-PropertyByNames -Object $commandData -Names @('weeklyResetHours', 'weeklyResetsInHours', 'weekResetHours', 'sevenDayResetHours', 'sevenDayResetsInHours', 'weekly_reset_hours', 'seven_day_reset_hours', 'reset7dHours', 'resets7dInHours')

                    $fiveHourResetAtUtc = ConvertTo-TokenDateTime -Value $commandFiveResetAt
                    $weeklyResetAtUtc = ConvertTo-TokenDateTime -Value $commandWeekResetAt
                    $fiveHourResetHours = Get-ResetHoursFromAt -Value $fiveHourResetAtUtc -NowUtc $nowUtc
                    if ($null -eq $fiveHourResetHours) {
                        $fiveHourResetHours = ConvertTo-ResetHoursOrNull -Value $commandFiveResetHours -NowUtc $nowUtc
                    }
                    $weeklyResetHours = Get-ResetHoursFromAt -Value $weeklyResetAtUtc -NowUtc $nowUtc
                    if ($null -eq $weeklyResetHours) {
                        $weeklyResetHours = ConvertTo-ResetHoursOrNull -Value $commandWeekResetHours -NowUtc $nowUtc
                    }

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

                    Update-ProviderQuotaCache `
                            -Cache $quotaCache `
                            -NowUtc $nowUtc `
                            -ProviderId $provider.Id `
                            -FiveHourRemainingPercent $fiveHourRemainingPercent `
                            -WeeklyRemainingPercent $weeklyRemainingPercent `
                            -FiveHourResetAt $fiveHourResetAtUtc `
                            -WeeklyResetAt $weeklyResetAtUtc
                }
            }
            else {
                $commandStatus = 'Command produced no output'
            }

            if (-not (Test-TokenProviderStatusOk -Status $commandStatus)) {
                $cachedQuota = Get-EstimatedProviderQuotaFromCache -Cache $quotaCache -NowUtc $nowUtc -ProviderId $provider.Id
                if ($null -ne $cachedQuota) {
                    $fiveHourRemainingPercent = $cachedQuota.FiveHourRemainingPercent
                    $weeklyRemainingPercent = $cachedQuota.WeeklyRemainingPercent
                    $fiveHourResetHours = $cachedQuota.FiveHourResetHours
                    $weeklyResetHours = $cachedQuota.WeeklyResetHours
                    $fiveHourResetAtUtc = $cachedQuota.FiveHourResetAtUtc
                    $weeklyResetAtUtc = $cachedQuota.WeeklyResetAtUtc
                    if ($null -ne $fiveHourRemainingPercent) {
                        $fiveHourUsedDisplay = ('{0:N0}% used' -f (100.0 - [double]$fiveHourRemainingPercent))
                    }
                    if ($null -ne $weeklyRemainingPercent) {
                        $weeklyUsedDisplay = ('{0:N0}% used' -f (100.0 - [double]$weeklyRemainingPercent))
                    }
                    $lastVisibleLocal = ([DateTime]$cachedQuota.ObservedAtUtc).ToLocalTime()
                    $isEstimatedFromCache = $true
                    $commandStatus = ('Last visible {0}; cached while local service is offline' -f $lastVisibleLocal.ToString('yyyy-MM-dd HH:mm'))
                }
            }

            # If weekly quota is exhausted, force 5h to show as unavailable
            if ($null -ne $weeklyRemainingPercent -and $weeklyRemainingPercent -le 0) {
                $fiveHourRemainingPercent = $null
                $fiveHourResetHours = $null
                $fiveHourUsedDisplay = ''-''
            }

            $health = Get-ProviderTokenHealth `
                -Enabled $true `
                -Status $commandStatus `
                -FiveHourRemainingPercent $fiveHourRemainingPercent `
                -WeeklyRemainingPercent $weeklyRemainingPercent `
                -FiveHourResetHours $fiveHourResetHours `
                -WeeklyResetHours $weeklyResetHours

            if ($weekLimit -eq 0) { $fiveHourResetHours = 0 }
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
                FiveHourResetHours = $fiveHourResetHours
                WeeklyResetHours = $weeklyResetHours
                Events = 0
                Files = 0
                LastEventLocal = $lastVisibleLocal
                LastVisibleLocal = $lastVisibleLocal
                IsEstimatedFromCache = $isEstimatedFromCache
                Status = $commandStatus
                HealthState = $health.State
                HealthText = $health.Text
                HealthPercent = $health.Percent
                HealthWindow = $health.Window
                HealthConfidence = $health.Confidence
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
        $fiveHourResetHours = $null
        $weeklyResetHours = $null
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
            $fiveHourResetHours = Get-ResetHoursFromAt -Value $latestFiveHourLimitEvent.FiveHourResetAtUtc -NowUtc $nowUtc
        }
        if ($weekLimit -le 0 -and $null -ne $latestWeeklyLimitEvent -and $null -ne $latestWeeklyLimitEvent.WeeklyUsedPercent) {
            $weeklyRemainingPercent = Get-RemainingPercentFromRateLimit `
                -UsedPercent $latestWeeklyLimitEvent.WeeklyUsedPercent `
                -ResetAtUtc $latestWeeklyLimitEvent.WeeklyResetAtUtc `
                -NowUtc $nowUtc
            if ($null -ne $weeklyRemainingPercent) {
                $weeklyUsedDisplay = ('{0:N0}% used' -f (100.0 - [double]$weeklyRemainingPercent))
            }
            $weeklyResetHours = Get-ResetHoursFromAt -Value $latestWeeklyLimitEvent.WeeklyResetAtUtc -NowUtc $nowUtc
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

            # If weekly quota is exhausted, force 5h to show as unavailable
            if ($null -ne $weeklyRemainingPercent -and $weeklyRemainingPercent -le 0) {
                $fiveHourRemainingPercent = $null
                $fiveHourResetHours = $null
                $fiveHourUsedDisplay = ''-''
            }

        $health = Get-ProviderTokenHealth `
            -Enabled $true `
            -Status $status `
            -FiveHourRemainingPercent $fiveHourRemainingPercent `
            -WeeklyRemainingPercent $weeklyRemainingPercent `
            -FiveHourResetHours $fiveHourResetHours `
            -WeeklyResetHours $weeklyResetHours

        if ($weekLimit -eq 0) { $fiveHourResetHours = 0 }
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
            FiveHourResetHours = $fiveHourResetHours
            WeeklyResetHours = $weeklyResetHours
            Events = $events.Count
            Files = $files.Count
            LastEventLocal = $lastLocal
            Status = $status
            HealthState = $health.State
            HealthText = $health.Text
            HealthPercent = $health.Percent
            HealthWindow = $health.Window
            HealthConfidence = $health.Confidence
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

function Format-ResetHours {
    param($Value)

    if ($null -eq $Value) {
        return 'n/a'
    }

    $hours = [Math]::Max(0.0, [double]$Value)
    if ($hours -lt 0.05) {
        return 'now'
    }
    if ($hours -lt 1.0) {
        return ('{0:N0}m' -f [Math]::Max(1, [Math]::Round($hours * 60.0)))
    }
    return ('{0:N1}h' -f $hours)
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

function Format-TooltipPercentNumber {
    param($Value)

    if ($null -eq $Value) {
        return '-'
    }
    $number = [Math]::Max(0, [Math]::Min(100, [int][Math]::Round([double]$Value)))
    if ($number -eq 100) {
        $number = 99
    }
    return ('{0:00}' -f $number)
}

function Format-TooltipTimeNumber {
    param(
        $Value,
        [double]$Divisor = 1.0
    )

    if ($null -eq $Value) {
        return '-'
    }

    $number = [double]$Value
    if ($Divisor -gt 0) {
        $number = $number / $Divisor
    }
    return [string]([Math]::Max(0, [int][Math]::Round($number)))
}

function Format-TooltipHealthCode {
    param($Provider)

    $state = $null
    if (Get-Member -InputObject $Provider -Name HealthState -MemberType NoteProperty -ErrorAction SilentlyContinue) {
        $state = [string]$Provider.HealthState
    }

    switch ($state) {
        'empty' { return 'OUT' }
        'low' { return 'LOW' }
        'medium' { return 'MID' }
        'good' { return 'OK' }
        'disabled' { return 'OFF' }
        default { return 'n/a' }
    }
}

function Format-TooltipProviderName {
    param($Provider)

    $shortName = switch ($Provider.Id) {
        'antigravity' { 'Ag' }
        'codex' { 'Cdx' }
        'claude' { 'Claude' }
        default { $Provider.Name }
    }

    if (((Get-Member -InputObject $Provider -Name IsEstimatedFromCache -MemberType NoteProperty -ErrorAction SilentlyContinue) -and $Provider.IsEstimatedFromCache) -or
        (-not (Test-TokenProviderStatusOk -Status $Provider.Status))) {
        return ('{0}(E)' -f $shortName)
    }

    return $shortName
}

function Format-TokenUsageTooltip {
    param($Snapshot)

    $nameParts = New-Object System.Collections.Generic.List[string]
    $fiveHourPercentParts = New-Object System.Collections.Generic.List[string]
    $fiveHourResetParts = New-Object System.Collections.Generic.List[string]
    $weeklyPercentParts = New-Object System.Collections.Generic.List[string]
    $weeklyResetParts = New-Object System.Collections.Generic.List[string]
    foreach ($provider in @($Snapshot.Providers)) {
        if (-not $provider.Enabled) {
            continue
        }

        $nameParts.Add((Format-TooltipProviderName -Provider $provider))
        $fiveHourPercentParts.Add((Format-TooltipPercentNumber -Value $provider.FiveHourRemainingPercent))

        $fiveHourResetVal = $provider.FiveHourResetHours
        if ($null -ne $provider.FiveHourRemainingPercent -and $provider.FiveHourRemainingPercent -ge 100) {
            $fiveHourResetVal = 5.0
        }
        $fiveHourResetParts.Add((Format-TooltipTimeNumber -Value $fiveHourResetVal))

        $weeklyPercentParts.Add((Format-TooltipPercentNumber -Value $provider.WeeklyRemainingPercent))

        $weeklyResetVal = $provider.WeeklyResetHours
        if ($null -ne $provider.WeeklyRemainingPercent -and $provider.WeeklyRemainingPercent -ge 100) {
            $weeklyResetVal = 168.0
        }
        $weeklyResetParts.Add((Format-TooltipTimeNumber -Value $weeklyResetVal -Divisor 24.0))
    }

    $text = 'TokenMonitor'
    if ($nameParts.Count -gt 0) {
        $text = ($nameParts -join '/')
        $text += ("`n{0} - {1}" -f ($fiveHourPercentParts -join '/'), ($fiveHourResetParts -join '/'))
        $text += ("`n{0} - {1}" -f ($weeklyPercentParts -join '/'), ($weeklyResetParts -join '/'))
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
    Format-ResetHours, `
    Format-TokenUsageTooltip

