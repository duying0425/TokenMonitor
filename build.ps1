# TokenMonitor Build Script
# This script combines TokenUsage.psm1 and TokenMonitor.ps1 into a single standalone 
# script, then compiles it using ps2exe with the custom icon to prevent any file extraction.

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$srcDir = Join-Path $repoRoot 'src'
$binDir = Join-Path $repoRoot 'bin'

if (-not (Test-Path -LiteralPath $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

# 1. Ensure ps2exe is installed
Write-Host "Checking for ps2exe..."
if (-not (Get-Command ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "ps2exe not found. Installing ps2exe module..."
    Install-Module ps2exe -Scope CurrentUser -Force -SkipPublisherCheck
}

# 2. Ensure Icon exists
$iconPath = Join-Path $srcDir 'token-monitor.ico'
if (-not (Test-Path -LiteralPath $iconPath)) {
    Write-Host "Icon file not found. Attempting to convert using Python converter..."
    $pngPath = Join-Path $repoRoot 'token_monitor_logo.png'
    # Look for any png logo in appdata/brain first if missing
    if (-not (Test-Path -LiteralPath $pngPath)) {
        $logoCandidates = Get-ChildItem -Path "$env:APPDATA\..\Local\Temp", "$env:APPDATA\Antigravity-IDE\brain\*" -Filter "token_monitor_logo*.png" -Recurse -ErrorAction SilentlyContinue
        if ($logoCandidates) {
            $pngPath = $logoCandidates[0].FullName
        }
    }
    
    if (Test-Path -LiteralPath $pngPath) {
        py "$repoRoot\tests\convert_ico.py" $pngPath $iconPath
    } else {
        Write-Warning "Could not find logo image. Build will continue without custom icon."
        $iconPath = $null
    }
}

# 3. Read source files
Write-Host "Reading source files..."
$monitorScriptPath = Join-Path $srcDir 'TokenMonitor.ps1'
$usageModulePath = Join-Path $srcDir 'TokenUsage.psm1'

$monitorContent = Get-Content -LiteralPath $monitorScriptPath -Raw
$usageContent = Get-Content -LiteralPath $usageModulePath -Raw

# 4. Merge content
Write-Host "Merging TokenUsage.psm1 into TokenMonitor.ps1..."
$cleanUsageContent = $usageContent -replace '(?s)(?m)^[ \t]*Export-ModuleMember.*$', ''


# Find the block where Import-Module is performed and replace it with the module content
$importPattern = '(?s)\$modulePath = Join-Path \$scriptRoot ''TokenUsage\.psm1''.*?Import-Module \$modulePath -Force'

if ($monitorContent -match $importPattern) {
    # Escape $ signs in the replacement string to prevent regex group expansion corruption
    $escapedUsageContent = $cleanUsageContent.Replace('$', '$$')
    $mergedContent = [regex]::Replace($monitorContent, $importPattern, $escapedUsageContent)
} else {
    Write-Warning "Could not locate module import pattern in TokenMonitor.ps1. Appending module contents to top instead."
    $mergedContent = $cleanUsageContent + "`n`n" + $monitorContent
}

$tempMergedPath = Join-Path $srcDir 'TokenMonitor.merged.ps1'
$mergedContent | Set-Content -LiteralPath $tempMergedPath -Encoding UTF8

# 5. Compile using ps2exe
Write-Host "Compiling standalone executable using ps2exe..."
$outputExe = Join-Path $binDir 'TokenMonitor.exe'
$compileArgs = @{
    inputFile = $tempMergedPath
    outputFile = $outputExe
    STA = $true
    noConsole = $true
    title = 'TokenMonitor'
    product = 'TokenMonitor'
    version = '1.4.0'
}

if ($null -ne $iconPath -and (Test-Path -LiteralPath $iconPath)) {
    $compileArgs.Add('iconFile', $iconPath)
}

# Execute Invoke-ps2exe (cmdlet of ps2exe module)
Invoke-ps2exe @compileArgs

# 6. Clean up temporary files
Write-Host "Cleaning up temporary merged script..."
if (Test-Path -LiteralPath $tempMergedPath) {
    Remove-Item -LiteralPath $tempMergedPath -Force
}

Write-Host "Successfully compiled and updated TokenMonitor.exe!" -ForegroundColor Green
