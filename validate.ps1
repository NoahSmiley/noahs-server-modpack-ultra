# Packwiz Modpack Validator
# Run this BEFORE pushing to ensure no conflicts
# Usage: .\validate.ps1

$ErrorActionPreference = "Stop"
$script:hasErrors = $false

function Write-Error-Custom($msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
    $script:hasErrors = $true
}

function Write-OK($msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

Write-Host "`n=== Packwiz Modpack Validator ===" -ForegroundColor Cyan
Write-Host ""

# 1. Check for duplicate mod IDs in packwiz
Write-Host "Checking for duplicate Modrinth IDs..." -ForegroundColor White
$modIds = @{}
$pwtomlFiles = Get-ChildItem -Path ".\mods" -Filter "*.pw.toml"

foreach ($file in $pwtomlFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match 'mod-id = "([^"]+)"') {
        $modId = $matches[1]
        if ($modIds.ContainsKey($modId)) {
            Write-Error-Custom "Duplicate mod-id '$modId' in $($file.Name) and $($modIds[$modId])"
        } else {
            $modIds[$modId] = $file.Name
        }
    }
}
if (-not $script:hasErrors) {
    Write-OK "No duplicate Modrinth IDs found ($($pwtomlFiles.Count) mods)"
}

# 2. Check for duplicate filenames
Write-Host "`nChecking for duplicate filenames..." -ForegroundColor White
$filenames = @{}
foreach ($file in $pwtomlFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match 'filename = "([^"]+)"') {
        $filename = $matches[1]
        if ($filenames.ContainsKey($filename)) {
            Write-Error-Custom "Duplicate filename '$filename' in $($file.Name) and $($filenames[$filename])"
        } else {
            $filenames[$filename] = $file.Name
        }
    }
}
if (-not $script:hasErrors) {
    Write-OK "No duplicate filenames"
}

# 3. Refresh packwiz index and check for errors
Write-Host "`nRefreshing packwiz index..." -ForegroundColor White
$refreshOutput = & .\packwiz.exe refresh 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Packwiz refresh failed: $refreshOutput"
} else {
    Write-OK "Packwiz index refreshed successfully"
}

# 4. Check index.toml matches mods folder
Write-Host "`nValidating index.toml..." -ForegroundColor White
$indexContent = Get-Content ".\index.toml" -Raw
$indexPwtomlCount = ([regex]::Matches($indexContent, 'file = "mods/[^"]+\.pw\.toml"')).Count
$indexJarCount = ([regex]::Matches($indexContent, 'file = "mods/[^"]+\.jar"')).Count
$actualPwtomlCount = $pwtomlFiles.Count

# Also check for actual JAR files in mods folder
$jarFiles = Get-ChildItem -Path ".\mods" -Filter "*.jar" -ErrorAction SilentlyContinue
$actualJarCount = if ($jarFiles) { $jarFiles.Count } else { 0 }

if ($indexPwtomlCount -ne $actualPwtomlCount) {
    Write-Error-Custom "Index has $indexPwtomlCount .pw.toml refs but mods/ folder has $actualPwtomlCount .pw.toml files"
} elseif ($indexJarCount -ne $actualJarCount) {
    Write-Error-Custom "Index has $indexJarCount .jar refs but mods/ folder has $actualJarCount .jar files"
} else {
    $totalMods = $actualPwtomlCount + $actualJarCount
    Write-OK "Index matches mods folder ($actualPwtomlCount .pw.toml + $actualJarCount .jar = $totalMods mods)"
}

# 5. Check for known incompatible mod combinations
Write-Host "`nChecking for known incompatibilities..." -ForegroundColor White
$incompatiblePairs = @(
    @("lambdabettergrass", "octo-lib"),  # TrailProvider conflict
    @("optifine", "sodium"),              # Renderer conflict
    @("optifine", "iris")                 # Renderer conflict
)

$modNames = $pwtomlFiles | ForEach-Object { $_.BaseName.ToLower() }

foreach ($pair in $incompatiblePairs) {
    $mod1 = $pair[0]
    $mod2 = $pair[1]
    $has1 = $modNames -contains $mod1
    $has2 = $modNames -contains $mod2

    if ($has1 -and $has2) {
        Write-Warn "Potentially incompatible: $mod1 + $mod2"
    }
}
Write-OK "Incompatibility check complete"

# 6. Check all download URLs are accessible (sample check)
Write-Host "`nValidating download URLs (sampling 3 random mods)..." -ForegroundColor White
$sampleMods = $pwtomlFiles | Get-Random -Count 3

foreach ($file in $sampleMods) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match 'url = "([^"]+)"') {
        $url = $matches[1]
        try {
            $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 5 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-OK "$($file.BaseName) URL accessible"
            }
        } catch {
            Write-Error-Custom "$($file.BaseName) URL not accessible: $url"
        }
    }
}

# 7. Summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
if ($script:hasErrors) {
    Write-Host "FAILED - Fix errors before pushing!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "PASSED - Safe to push!" -ForegroundColor Green
    Write-Host "`nNext steps:"
    Write-Host "  git add . && git commit -m 'Update mods' && git push"
    exit 0
}
