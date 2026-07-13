$modulePath = Resolve-Path (Join-Path $PSScriptRoot "..\src\TokenUsage.psm1")
Import-Module $modulePath -Force

InModuleScope TokenUsage {
    Describe "TokenUsage Path Expansion" {
        It "Expands environment variables" {
            # windir is always defined on Windows
            $expanded = Expand-TokenMonitorPath -Path "%windir%\system32"
            $expanded | Should Be "C:\Windows\system32"
        }
        It "Expands ~ to home directory" {
            $expanded = Expand-TokenMonitorPath -Path "~"
            $expanded | Should Be $HOME
        }
        It "Expands ~/ or ~\ paths relative to home" {
            $expanded1 = Expand-TokenMonitorPath -Path "~\testdir"
            $expanded1 | Should Be (Join-Path $HOME "testdir")
            
            $expanded2 = Expand-TokenMonitorPath -Path "~/testdir"
            $expanded2 | Should Be (Join-Path $HOME "testdir")
        }
        It "Returns original path if no expansions apply" {
            $expanded = Expand-TokenMonitorPath -Path "C:\MyFolder"
            $expanded | Should Be "C:\MyFolder"
        }
    }

    Describe "TokenUsage Date and Time Converters" {
        It "Returns null for null value" {
            ConvertTo-TokenDateTime -Value $null | Should Be $null
            ConvertTo-TokenIsoDateTimeString -Value $null | Should Be $null
        }
        It "Converts DateTime object to Utc" {
            $localDate = [DateTime]::SpecifyKind((Get-Date), [System.DateTimeKind]::Local)
            $res = ConvertTo-TokenDateTime -Value $localDate
            $res.Kind | Should Be "Utc"
        }
        It "Converts Unix millisecond numeric string" {
            # 1783115480000 -> 2026-07-04T21:51:20Z (approx)
            $res = ConvertTo-TokenDateTime -Value "1783115480000"
            $res | Should Not Be $null
            $res.Year | Should Be 2026
        }
        It "Converts Unix second numeric string" {
            $res = ConvertTo-TokenDateTime -Value "1783115480"
            $res | Should Not Be $null
            $res.Year | Should Be 2026
        }
        It "Converts ASP.NET JSON date format" {
            $res = ConvertTo-TokenDateTime -Value "/Date(1783115480000)/"
            $res | Should Not Be $null
            $res.Year | Should Be 2026
        }
        It "Converts ISO 8601 string" {
            $res = ConvertTo-TokenDateTime -Value "2026-07-04T08:31:55Z"
            $res | Should Not Be $null
            $res.Year | Should Be 2026
            $res.Month | Should Be 7
            $res.Day | Should Be 4
            $res.Hour | Should Be 8
            $res.Minute | Should Be 31
        }
        It "Converts to ISO 8601 format string" {
            $resStr = ConvertTo-TokenIsoDateTimeString -Value "2026-07-04T08:31:55Z"
            $resStr | Should Match "2026-07-04T08:31:55.0000000"
        }
    }

    Describe "TokenUsage Properties Helpers" {
        It "Gets properties from pscustomobject" {
            $obj = [pscustomobject]@{
                PropA = "ValueA"
                PropB = 123
            }
            $props = Get-ObjectProperties -Value $obj
            $props.Count | Should Be 2
            $props[0].Name | Should Be "PropA"
            $props[0].Value | Should Be "ValueA"
        }
        It "Gets properties from Hashtable / IDictionary" {
            $dict = @{
                KeyA = "ValA"
                KeyB = 456
            }
            $props = Get-ObjectProperties -Value $dict
            $props.Count | Should Be 2
            $names = $props | Select-Object -ExpandProperty Name
            ($names -contains "KeyA") | Should Be $true
            ($names -contains "KeyB") | Should Be $true
        }
        It "Gets property by priority names (case sensitive/insensitive)" {
            $obj = [pscustomobject]@{
                myProp = "Value1"
                otherProp = "Value2"
            }
            $val1 = Get-PropertyByNames -Object $obj -Names @("myProp")
            $val1 | Should Be "Value1"

            $val2 = Get-PropertyByNames -Object $obj -Names @("MYPROP")
            $val2 | Should Be "Value1"

            $val3 = Get-PropertyByNames -Object $obj -Names @("nonexistent", "otherProp")
            $val3 | Should Be "Value2"
        }
    }

    Describe "TokenUsage Numeric and Reset Converters" {
        It "Converts values to token count (long)" {
            ConvertTo-TokenNumber -Value 123 | Should Be 123L
            ConvertTo-TokenNumber -Value "456.7" | Should Be 457L
            ConvertTo-TokenNumber -Value "-10" | Should Be 0L
            ConvertTo-TokenNumber -Value $null | Should Be 0L
            ConvertTo-TokenNumber -Value "abc" | Should Be 0L
        }
        It "Converts values to double or null" {
            ConvertTo-TokenDoubleOrNull -Value "12.34" | Should Be 12.34
            ConvertTo-TokenDoubleOrNull -Value "abc" | Should Be $null
            ConvertTo-TokenDoubleOrNull -Value $null | Should Be $null
        }
        It "Converts value to relative reset hours" {
            $now = [DateTime]::SpecifyKind([DateTime]"2026-07-04T08:00:00", [System.DateTimeKind]::Utc)
            
            # Numeric hours input
            ConvertTo-ResetHoursOrNull -Value 2.5 -NowUtc $now | Should Be 2.5
            ConvertTo-ResetHoursOrNull -Value -1 -NowUtc $now | Should Be 0.0

            # Date string input (1 hour later than $now)
            $resetAt = "2026-07-04T09:00:00Z"
            ConvertTo-ResetHoursOrNull -Value $resetAt -NowUtc $now | Should Be 1.0
        }
        It "Gets reset hours from at date" {
            $now = [DateTime]::SpecifyKind([DateTime]"2026-07-04T08:00:00", [System.DateTimeKind]::Utc)
            Get-ResetHoursFromAt -Value "2026-07-04T10:00:00Z" -NowUtc $now | Should Be 2.0
            Get-ResetHoursFromAt -Value "invalid" -NowUtc $now | Should Be $null
        }
    }

    Describe "TokenUsage JSON Log Line Parsing" {
        It "Extracts JSON field values directly" {
            $line = '{"name":"test", "val": 123, "text": "hello"}'
            $vals = Get-JsonLineFieldValues -Line $line -Names @("val", "text")
            ($vals -contains "123") | Should Be $true
            ($vals -contains "hello") | Should Be $true
        }
        It "Identifies if log line might contain token usage" {
            Test-JsonLineMightContainUsage -Line 'some log text' | Should Be $false
            Test-JsonLineMightContainUsage -Line 'last_token_usage' | Should Be $true
            Test-JsonLineMightContainUsage -Line 'total_tokens' | Should Be $true
        }
        It "Parses event from json log line (last_token_usage format)" {
            $line = '{"timestamp":"2026-07-04T08:00:00Z","last_token_usage":{"total_tokens":150}}'
            $event = Read-TokenEventFromJsonLineFast -Line $line -ProviderId "test" -SourcePath "log.txt"
            $event | Should Not Be $null
            $event.ProviderId | Should Be "test"
            $event.Tokens | Should Be 150
            $event.TimestampUtc.Year | Should Be 2026
        }
        It "Parses event from json log line (total_token_usage format)" {
            # Needs either Tokens > 0 or a rate limit present to not be ignored as empty event
            $line = '{"timestamp":"2026-07-04T08:00:00Z","total_token_usage":{"total_tokens":200},"primary":{"used_percent":85.0,"window_minutes":300,"resets_at":"2026-07-04T09:00:00Z"}}'
            $event = Read-TokenEventFromJsonLineFast -Line $line -ProviderId "test" -SourcePath "log.txt"
            $event | Should Not Be $null
            $event.CumulativeTokens | Should Be 200
        }
        It "Parses rate limit windows correctly" {
            # window_minutes = 300 (5h)
            $line = '{"timestamp":"2026-07-04T08:00:00Z","primary":{"used_percent":85.0,"window_minutes":300,"resets_at":"2026-07-04T09:00:00Z"}}'
            $event = Read-TokenEventFromJsonLineFast -Line $line -ProviderId "test" -SourcePath "log.txt"
            $event | Should Not Be $null
            $event.FiveHourUsedPercent | Should Be 85.0
            $event.FiveHourResetAtUtc | Should Not Be $null
        }
        It "Gets usage token count from object properties" {
            $obj = [pscustomobject]@{
                total_tokens = 100
            }
            Get-UsageTokenCount -Object $obj | Should Be 100L

            $objParts = [pscustomobject]@{
                input_tokens = 40
                output_tokens = 60
            }
            Get-UsageTokenCount -Object $objParts | Should Be 100L
        }
        It "Gets local timestamp from object properties" {
            $obj = [pscustomobject]@{
                timestamp = "2026-07-04T08:00:00Z"
            }
            $dt = Get-LocalTimestamp -Object $obj
            $dt | Should Not Be $null
            $dt.Hour | Should Be 8
        }
    }

    Describe "TokenUsage Health Calculations" {
        It "Gets percentage from used and limit" {
            Get-RemainingPercent -Used 20 -Limit 100 | Should Be 80.0
            Get-RemainingPercent -Used 120 -Limit 100 | Should Be 0.0
            Get-RemainingPercent -Used 20 -Limit 0 | Should Be $null
        }
        It "Gets remaining percentage from rate limit used percent" {
            $now = [DateTime]::SpecifyKind([DateTime]"2026-07-04T08:00:00", [System.DateTimeKind]::Utc)
            $resetPassed = [DateTime]::SpecifyKind([DateTime]"2026-07-04T07:59:00", [System.DateTimeKind]::Utc)
            $resetFuture = [DateTime]::SpecifyKind([DateTime]"2026-07-04T08:05:00", [System.DateTimeKind]::Utc)

            # Reset already passed -> 100% remaining
            Get-RemainingPercentFromRateLimit -UsedPercent 50.0 -ResetAtUtc $resetPassed -NowUtc $now | Should Be 100.0
            # Reset in future -> 100 - UsedPercent
            Get-RemainingPercentFromRateLimit -UsedPercent 35.5 -ResetAtUtc $resetFuture -NowUtc $now | Should Be 64.5
            # Null input
            Get-RemainingPercentFromRateLimit -UsedPercent $null -ResetAtUtc $resetFuture -NowUtc $now | Should Be $null
        }
        It "Calculates disabled provider health" {
            $health = Get-ProviderTokenHealth -Enabled $false -Status "OK" -FiveHourRemainingPercent 100.0 -WeeklyRemainingPercent 100.0
            $health.State | Should Be "disabled"
            $health.Reason | Should Be "Disabled"
        }
        It "Calculates empty provider health" {
            $health = Get-ProviderTokenHealth -Enabled $true -Status "OK" -FiveHourRemainingPercent 0.0 -WeeklyRemainingPercent 50.0
            $health.State | Should Be "empty"
        }
        It "Calculates low weekly health" {
            $health = Get-ProviderTokenHealth -Enabled $true -Status "OK" -FiveHourRemainingPercent 50.0 -WeeklyRemainingPercent 8.0
            $health.State | Should Be "low"
            $health.Window | Should Be "7d"
        }
        It "Calculates low hourly health" {
            $health = Get-ProviderTokenHealth -Enabled $true -Status "OK" -FiveHourRemainingPercent 12.0 -WeeklyRemainingPercent 50.0
            $health.State | Should Be "low"
            $health.Window | Should Be "5h"
        }
        It "Calculates medium health" {
            $health = Get-ProviderTokenHealth -Enabled $true -Status "OK" -FiveHourRemainingPercent 40.0 -WeeklyRemainingPercent 80.0
            $health.State | Should Be "medium"
            $health.Window | Should Be "5h"
        }
        It "Calculates good health" {
            $health = Get-ProviderTokenHealth -Enabled $true -Status "OK" -FiveHourRemainingPercent 90.0 -WeeklyRemainingPercent 95.0
            $health.State | Should Be "good"
        }
        It "Calculates health when fiveHour limit is null" {
            # Good weekly health when fiveHour is null
            $health = Get-ProviderTokenHealth -Enabled $true -Status "OK" -FiveHourRemainingPercent $null -WeeklyRemainingPercent 95.0
            $health.State | Should Be "good"
            $health.Window | Should Be "7d"

            # Medium weekly health when fiveHour is null
            $health = Get-ProviderTokenHealth -Enabled $true -Status "OK" -FiveHourRemainingPercent $null -WeeklyRemainingPercent 35.0
            $health.State | Should Be "medium"
            $health.Window | Should Be "7d"

            # Low weekly health when fiveHour is null
            $health = Get-ProviderTokenHealth -Enabled $true -Status "OK" -FiveHourRemainingPercent $null -WeeklyRemainingPercent 8.0
            $health.State | Should Be "low"
            $health.Window | Should Be "7d"
        }
        It "Tests provider status OK helper" {
            Test-TokenProviderStatusOk -Status "OK" | Should Be $true
            Test-TokenProviderStatusOk -Status "Command OK" | Should Be $true
            Test-TokenProviderStatusOk -Status "Error 500" | Should Be $false
        }
    }

    Describe "TokenUsage Window Usage Aggregation" {
        It "Aggregates non-cumulative tokens in window" {
            $cutoff = [DateTime]::SpecifyKind([DateTime]"2026-07-04T08:00:00", [System.DateTimeKind]::Utc)
            $events = @(
                [pscustomobject]@{ TimestampUtc = $cutoff.AddMinutes(-5); Tokens = 100 },
                [pscustomobject]@{ TimestampUtc = $cutoff.AddMinutes(5); Tokens = 200 },
                [pscustomobject]@{ TimestampUtc = $cutoff.AddMinutes(10); Tokens = 300 }
            )
            Get-TokenWindowUsage -Events $events -CutoffUtc $cutoff -PreferCumulative $false | Should Be 500L
        }
        It "Aggregates cumulative tokens in window" {
            $cutoff = [DateTime]::SpecifyKind([DateTime]"2026-07-04T08:00:00", [System.DateTimeKind]::Utc)
            $events = @(
                # File A: cumulative increases
                [pscustomobject]@{ SourcePath = "A"; TimestampUtc = $cutoff.AddMinutes(-5); CumulativeTokens = 100; Tokens = 100 },
                [pscustomobject]@{ SourcePath = "A"; TimestampUtc = $cutoff.AddMinutes(5); CumulativeTokens = 250; Tokens = 150 },
                [pscustomobject]@{ SourcePath = "A"; TimestampUtc = $cutoff.AddMinutes(10); CumulativeTokens = 350; Tokens = 100 },
                
                # File B: starts inside window
                [pscustomobject]@{ SourcePath = "B"; TimestampUtc = $cutoff.AddMinutes(2); CumulativeTokens = 50; Tokens = 50 }
            )
            # For File A: delta inside window is 350 - 100 = 250.
            # For File B: starts inside window, cumulative is 50 (since no previous, falls back to Tokens = 50).
            # Total should be 250 + 50 = 300.
            Get-TokenWindowUsage -Events $events -CutoffUtc $cutoff -PreferCumulative $true | Should Be 300L
        }
    }

    Describe "TokenUsage Formatters" {
        It "Formats token counts with suffixes" {
            Format-TokenCount -Value 500 | Should Be "500"
            Format-TokenCount -Value 1500 | Should Be "1.5K"
            Format-TokenCount -Value 1500000 | Should Be "1.5M"
            Format-TokenCount -Value 1500000000 | Should Be "1.5B"
        }
        It "Formats percentages" {
            Format-Percent -Value $null | Should Be "n/a"
            Format-Percent -Value 85.4 | Should Be "85%"
        }
        It "Formats reset hours" {
            Format-ResetHours -Value $null | Should Be "n/a"
            Format-ResetHours -Value 0.02 | Should Be "now"
            Format-ResetHours -Value 0.5 | Should Be "30m"
            Format-ResetHours -Value 2.5 | Should Be "2.5h"
        }
        It "Formats tooltip percentages" {
            Format-TooltipPercentNumber -Value $null | Should Be "--"
            Format-TooltipPercentNumber -Value 85.4 | Should Be "85"
            Format-TooltipPercentNumber -Value 100 | Should Be "99"
            
            # Format-TooltipTimeNumber
            Format-TooltipTimeNumber -Value $null | Should Be "--"
            Format-TooltipTimeNumber -Value 5.2 | Should Be "5"
        }
    }

    Describe "TokenUsage Settings Configuration" {
        It "Generates default token settings" {
            $settings = New-DefaultTokenSettings
            $settings | Should Not Be $null
            $settings.RefreshSeconds | Should Be 60
            $agProvider = $settings.Providers | Where-Object { $_.Id -eq 'antigravity' }
            $agProvider.Enabled | Should Be $true
        }
        It "Saves and reads token settings" {
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                $settings = New-DefaultTokenSettings
                $settings.RefreshSeconds = 120
                
                Save-TokenMonitorSettings -Settings $settings -Path $tempFile
                
                $loaded = Read-TokenMonitorSettings -Path $tempFile
                $loaded.RefreshSeconds | Should Be 120
                $agProvider = $loaded.Providers | Where-Object { $_.Id -eq 'antigravity' }
                $agProvider.Enabled | Should Be $true
            }
            finally {
                if (Test-Path -LiteralPath $tempFile) {
                    Remove-Item -LiteralPath $tempFile -Force
                }
            }
        }
        It "Reads and writes cache using Provider functions" {
            $cache = [pscustomobject]@{}
            Set-TokenMonitorCacheProvider -Cache $cache -ProviderId "antigravity" -Value "custom"
            $val = Get-TokenMonitorCacheProvider -Cache $cache -ProviderId "antigravity"
            $val | Should Be "custom"
        }
    }
}
