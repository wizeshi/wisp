[CmdletBinding()]
param(
    [switch]$SkipAppBuild,
    [string]$Version = "0.0.0"
)

$ErrorActionPreference = 'Stop'

$repoRoot        = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$installerDir    = Join-Path $repoRoot "apps\wisp_installer"
$appPayloadDir   = Join-Path $repoRoot "dist\windows\app"
$installerBuildRoot = Join-Path $installerDir "build\windows\x64\runner\Release"
$distDir         = Join-Path $repoRoot "dist"
$evbConsole      = "${env:ProgramFiles(x86)}\Enigma Virtual Box\enigmavbconsole.exe"

& (Join-Path $PSScriptRoot "setup.ps1")

if (-not $SkipAppBuild) {
    & (Join-Path $PSScriptRoot "build_app.ps1") -SkipSetup
}

if (-not (Test-Path $appPayloadDir)) {
    Write-Error "No app build found at $appPayloadDir. Run build_app.ps1 first, or omit -SkipAppBuild."
    exit 1
}

# --- Build the installer app itself ------------------------------------
Write-Host "Building wisp_installer for Windows (release)..."
Push-Location $repoRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
} finally {
    Pop-Location
}

Push-Location $installerDir
try {
    try {
        cider bump build;
    } catch {
        Write-Warning "cider bump build failed. Continuing with flutter build..."
    }
    flutter build windows --release --build-name="$Version"
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows (installer) failed" }
} finally {
    Pop-Location
}

if (-not (Test-Path $installerBuildRoot)) {
    Write-Error "Expected installer build output at $installerBuildRoot but it wasn't found."
    exit 1
}

Write-Host "Copying VC++ runtime DLLs into the installer build output..."
$vcRuntimeDlls = @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
foreach ($dll in $vcRuntimeDlls) {
    Copy-Item -Path (Join-Path "$env:SystemRoot\System32" $dll) -Destination $installerBuildRoot -Force
}

# --- Stage the app payload next to the raw installer exe ----------------
$payloadTarget = Join-Path $installerBuildRoot "payload"
Write-Host "Staging app payload into $payloadTarget..."
if (Test-Path $payloadTarget) { Remove-Item $payloadTarget -Recurse -Force }
Copy-Item -Path $appPayloadDir -Destination $payloadTarget -Recurse -Force

# --- Generate the .evb file
. (Join-Path (Join-Path $PSScriptRoot "extras") "generate_evb.ps1")
$installerExe = Join-Path $installerBuildRoot "wisp_installer.exe"
$outputExe    = Join-Path $distDir "wisp_installer-windows.exe"

$projectXml = New-EvbProjectXml `
    -SourceDir $installerBuildRoot `
    -InputExe  (Join-Path $installerBuildRoot "wisp_installer.exe") `
    -OutputExe $outputExe

# Write outside $installerBuildRoot — generating the project *inside* the
# tree it's scanning would embed the project file into itself on the next run.
$generatedEvb = Join-Path $distDir "wisp_installer.evb"
[System.IO.File]::WriteAllText($generatedEvb, $projectXml, [System.Text.UTF8Encoding]::new($true))

# --- Pack ------------------------------------------------------------------
if (-not (Test-Path $evbConsole)) {
    Write-Error "enigmavbconsole.exe not found. Run setup.ps1 first."
    exit 1
}

Write-Host "Packing self-contained installer..."
& $evbConsole $generatedEvb
if ($LASTEXITCODE -ne 0) { throw "enigmavbconsole failed" }

if (-not (Test-Path $outputExe)) {
    Write-Error "Packing reported success but $outputExe wasn't produced."
    exit 1
}

Write-Host "`nSelf-contained installer built: $outputExe"