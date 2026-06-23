$scriptPath = Join-Path $PSScriptRoot 'src\TokenMonitor.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $scriptPath
