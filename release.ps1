# release.ps1
# PowerShell script to automate the release process by bumping version, tagging, and pushing to GitHub.

$ErrorActionPreference = 'Stop'

# 1. Check if git workspace is clean (excluding release.ps1 if it is new/uncommitted)
Write-Host "Checking git status..."
$status = git status --porcelain
if ($status) {
    $dirtyLines = $status | Where-Object { $_ -notmatch 'release\.ps1$' }
    if ($dirtyLines) {
        Write-Error "Git working directory is not clean. Please commit or stash your changes first.`n$status"
        exit 1
    }
}

# 2. Read current version from build.ps1
$buildScriptPath = Join-Path $PSScriptRoot 'build.ps1'
if (-not (Test-Path $buildScriptPath)) {
    Write-Error "build.ps1 not found in $PSScriptRoot"
    exit 1
}

$buildContent = Get-Content -LiteralPath $buildScriptPath -Raw
if ($buildContent -match "version\s*=\s*'([^']+)'") {
    $currentVersion = $Matches[1]
} else {
    Write-Error "Could not locate version assignment in build.ps1."
    exit 1
}

# 3. Parse and auto-increment version number (patch version)
$parts = $currentVersion.Split('.')
if ($parts.Count -lt 3) {
    Write-Error "Invalid version format in build.ps1: $currentVersion"
    exit 1
}

$major = [int]$parts[0]
$minor = [int]$parts[1]
$patch = [int]$parts[2]
$patch++
$newVersion = "$major.$minor.$patch"

Write-Host "Current version: v$currentVersion"
Write-Host "Auto-incrementing version to: v$newVersion"

# 4. Update build.ps1
$newBuildContent = $buildContent -replace "version\s*=\s*'$currentVersion'", "version = '$newVersion'"
$newBuildContent | Set-Content -LiteralPath $buildScriptPath -Encoding UTF8
Write-Host "Updated build.ps1 with version $newVersion"

# 5. Update README.md version reference
$readmePath = Join-Path $PSScriptRoot 'README.md'
if (Test-Path $readmePath) {
    $readmeContent = Get-Content -LiteralPath $readmePath -Raw
    $newReadmeContent = $readmeContent -replace "-version \d+\.\d+\.\d+", "-version $newVersion"
    $newReadmeContent | Set-Content -LiteralPath $readmePath -Encoding UTF8
    Write-Host "Updated README.md version references."
}

# 6. Commit version bump, tag, and push
Write-Host "Staging build.ps1 and README.md in git..."
git add build.ps1 README.md

# If release.ps1 itself is untracked, add it to git so it's tracked in the repo
if ($status -match 'release\.ps1$') {
    git add release.ps1
}

Write-Host "Committing version bump..."
git commit -m "chore(release): bump version to v$newVersion"

Write-Host "Creating tag v$newVersion..."
git tag "v$newVersion"

Write-Host "Pushing changes and tag to origin..."
git push origin main
git push origin "v$newVersion"

Write-Host "Successfully released v$newVersion! Check GitHub Actions for build status." -ForegroundColor Green
