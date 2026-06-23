Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'src\TokenUsage.psm1') -Force

$settings = [ordered]@{
    RefreshSeconds = 60
    MaxFileSizeMB = 20
    Providers = @(
        [ordered]@{
            Id = 'codex'
            Name = 'Codex sample'
            Enabled = $true
            FiveHourLimit = 0
            WeeklyLimit = 0
            ScanRoots = @((Join-Path $PSScriptRoot 'sample-codex.jsonl'))
            FilePatterns = @('*.jsonl')
            Command = ''
            CommandTimeoutSeconds = 15
        }
    )
}

$snapshot = Get-TokenUsageSnapshot -Settings $settings
$provider = $snapshot.Providers | Select-Object -First 1

if ($provider.Events -ne 1) {
    throw "Expected 1 event, got $($provider.Events)"
}
if ($provider.FiveHourUsed -ne 1234) {
    throw "Expected 1234 5h tokens, got $($provider.FiveHourUsed)"
}
if ($provider.FiveHourRemainingPercent -ne 88.0) {
    throw "Expected 88.0 5h remaining, got $($provider.FiveHourRemainingPercent)"
}
if ($provider.WeeklyRemainingPercent -ne 66.0) {
    throw "Expected 66.0 weekly remaining, got $($provider.WeeklyRemainingPercent)"
}

Write-Output 'Parser test passed'
