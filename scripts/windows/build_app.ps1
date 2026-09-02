# scripts/windows/build_app.ps1
[CmdletBinding()]
param(
    [switch]$SkipSetup,
    [string]$BuildName,
    [string]$BuildNumber
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$appDir   = Join-Path $repoRoot "apps\wisp_app"
$distDir  = Join-Path $repoRoot "dist\windows\app"

if (-not $SkipSetup) {
    & (Join-Path $PSScriptRoot "setup.ps1")
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "flutter not found on PATH. Install it or run from a shell where it's available."
    exit 1
}

Write-Host "Resolving workspace dependencies..."
Push-Location $repoRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
} finally {
    Pop-Location
}

Write-Host "Building wisp_app for Windows (release)..."
Push-Location $appDir
try {
    $buildArgs = @("build", "windows", "--release")
    if ($BuildName)   { $buildArgs += @("--build-name=$BuildName") }
    if ($BuildNumber) { $buildArgs += @("--build-number=$BuildNumber") }

    flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
} finally {
    Pop-Location
}

# Locate the runner output rather than hardcoding "x64" — future-proofs
# against an arm64 Windows target down the line.
$releaseDir = Get-ChildItem -Path (Join-Path $appDir "build\windows") -Recurse -Directory -Filter "Release" |
    Where-Object { $_.FullName -like "*\runner\Release" } |
    Select-Object -First 1

if (-not $releaseDir) {
    Write-Error "Couldn't find the built runner\Release output under $appDir\build\windows."
    exit 1
}

Write-Host "Staging build output to $distDir..."
if (Test-Path $distDir) { Remove-Item $distDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
Copy-Item -Path (Join-Path $releaseDir.FullName "*") -Destination $distDir -Recurse -Force

Write-Host "`nApp build complete: $distDir"
