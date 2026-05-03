# Install Cats Blender Plugin into user Blender extensions folder.
# Targets Blender 5.0+ (uses blender_manifest.toml extension format).
# Usage:
#   .\install.ps1                    # installs to all detected Blender 5.x versions
#   .\install.ps1 -Version 5.0       # installs to a specific version only
#   .\install.ps1 -Link              # symlink instead of copy (live dev install)

[CmdletBinding()]
param(
    [string]$Version,
    [switch]$Link,
    [string]$BlenderConfigRoot = (Join-Path $env:APPDATA 'Blender Foundation\Blender')
)

$ErrorActionPreference = 'Stop'

$ExtensionId = 'cats_blender_plugin'
$RepoRoot    = $PSScriptRoot

if (-not (Test-Path (Join-Path $RepoRoot 'blender_manifest.toml'))) {
    throw "blender_manifest.toml not found in $RepoRoot - run this script from the repo root."
}

if (-not (Test-Path $BlenderConfigRoot)) {
    throw "Blender config root not found: $BlenderConfigRoot"
}

# Items NOT copied into the installed extension folder.
$ExcludePatterns = @(
    '.git', '.github', '.gitignore', '.gitmodules',
    'tests', '__pycache__', '*.pyc',
    'install.ps1', 'install.py'
)

function Should-Exclude($name) {
    foreach ($p in $ExcludePatterns) { if ($name -like $p) { return $true } }
    return $false
}

function Copy-Extension($sourceDir, $destDir) {
    if (Test-Path $destDir) {
        Write-Host "  Removing existing: $destDir"
        Remove-Item -Recurse -Force $destDir
    }
    New-Item -ItemType Directory -Path $destDir | Out-Null
    Get-ChildItem -Path $sourceDir -Force | Where-Object { -not (Should-Exclude $_.Name) } | ForEach-Object {
        $target = Join-Path $destDir $_.Name
        if ($_.PSIsContainer) {
            Copy-Item -Path $_.FullName -Destination $target -Recurse -Force -Exclude '__pycache__','*.pyc'
            Get-ChildItem -Path $target -Recurse -Force -Include '__pycache__' -Directory -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Copy-Item -Path $_.FullName -Destination $target -Force
        }
    }
}

function New-ExtensionLink($sourceDir, $destDir) {
    if (Test-Path $destDir) {
        Write-Host "  Removing existing: $destDir"
        # Remove a junction/symlink without recursing into the target.
        $item = Get-Item $destDir -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            [IO.Directory]::Delete($destDir, $false)
        } else {
            Remove-Item -Recurse -Force $destDir
        }
    }
    New-Item -ItemType Junction -Path $destDir -Target $sourceDir | Out-Null
}

# Discover target Blender versions (5.x with an extensions folder).
$versionDirs = Get-ChildItem -Path $BlenderConfigRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match '^\d+\.\d+$' -and
        [version]$_.Name -ge [version]'5.0' -and
        (Test-Path (Join-Path $_.FullName 'extensions'))
    }

if ($Version) {
    $versionDirs = $versionDirs | Where-Object { $_.Name -eq $Version }
    if (-not $versionDirs) { throw "No Blender install found at version $Version under $BlenderConfigRoot" }
}

if (-not $versionDirs) { throw "No Blender 5.x installations found under $BlenderConfigRoot" }

Write-Host "Source: $RepoRoot"
Write-Host "Mode:   $(if ($Link) { 'symlink (junction)' } else { 'copy' })"
Write-Host ""

foreach ($v in $versionDirs) {
    $userDefault = Join-Path $v.FullName 'extensions\user_default'
    if (-not (Test-Path $userDefault)) {
        New-Item -ItemType Directory -Path $userDefault | Out-Null
    }
    $dest = Join-Path $userDefault $ExtensionId
    Write-Host "[Blender $($v.Name)] -> $dest"
    if ($Link) { New-ExtensionLink $RepoRoot $dest } else { Copy-Extension $RepoRoot $dest }
    Write-Host "  OK"
}

Write-Host ""
Write-Host "Done. In Blender: Edit > Preferences > Get Extensions > enable 'Unoffical Cats Blender Plugin'."
Write-Host "If Blender is running, restart it (or disable/enable the extension) to pick up changes."
