# scripts/windows/setup.ps1
$ErrorActionPreference = 'Stop'

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Error "This script needs to run elevated (VS Build Tools requires it). Re-run from an admin PowerShell."
    exit 1
}

# ---------------------------------------------------------------------------
# VS Build Tools: "Desktop development with C++" workload, MSVC v142, ATL
# ---------------------------------------------------------------------------
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

$vcToolsWorkloadId = "Microsoft.VisualStudio.Workload.VCTools"
$msvcV142Id        = "Microsoft.VisualStudio.ComponentGroup.VC.Tools.142.x86.x64"
$atlId             = "Microsoft.VisualStudio.Component.VC.ATL"

function Test-VCToolsInstalled {
    if (-not (Test-Path $vswhere)) { return $false }

    foreach ($id in @($vcToolsWorkloadId, $msvcV142Id, $atlId)) {
        # -products * checks every installed VS year — 2022, 2026, anything else present
        $result = & $vswhere -latest -products * -requires $id -property installationPath
        if ([string]::IsNullOrWhiteSpace($result)) {
            Write-Host "Missing VS component: $id"
            return $false
        }
    }
    return $true
}

if (Test-VCToolsInstalled) {
    Write-Host "A suitable VS install (any year) already has everything needed. Skipping download."
} else {
    Write-Host "No existing VS install satisfies the requirements. Installing VS2022 Build Tools (confirmed to carry MSVC v142)..."
    $override = "--passive --wait --norestart " +
                "--add $vcToolsWorkloadId --add $msvcV142Id --add $atlId --includeRecommended"

    winget install --id Microsoft.VisualStudio.2022.BuildTools --exact `
        --accept-package-agreements --accept-source-agreements --override $override

    if (-not (Test-VCToolsInstalled)) {
        Write-Error "Install finished but the expected components still aren't detected."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# NuGet CLI
# ---------------------------------------------------------------------------
$toolsDir = Join-Path $PSScriptRoot "tools"
$nugetExe = Join-Path $toolsDir "nuget.exe"

$existingNuget = Get-Command nuget.exe -ErrorAction SilentlyContinue

if ($existingNuget) {
    Write-Host "NuGet already on PATH at $($existingNuget.Source). Skipping."
} elseif (Test-Path $nugetExe) {
    Write-Host "NuGet already downloaded at $nugetExe. Skipping download."
} else {
    Write-Host "Downloading NuGet CLI..."
    New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
    Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $nugetExe
}

if (-not $existingNuget) {
    # Make it available for the rest of this session immediately...
    $env:Path = "$toolsDir;$env:Path"
    # ...and persist it for future sessions/terminals.
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$toolsDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$toolsDir;$userPath", "User")
    }
}

# ---------------------------------------------------------------------------
# Enigma Virtual Box
# ---------------------------------------------------------------------------
$evbConsole = "${env:ProgramFiles(x86)}\Enigma Virtual Box\enigmavbconsole.exe"

if (Test-Path $evbConsole) {
    Write-Host "Enigma Virtual Box already installed. Skipping."
} else {
    Write-Host "Installing Enigma Virtual Box..."
    winget install --id Enigma.VirtualBox --exact `
        --accept-package-agreements --accept-source-agreements --silent

    if (-not (Test-Path $evbConsole)) {
        Write-Error "Enigma Virtual Box install finished but enigmavbconsole.exe wasn't found at the expected path."
        exit 1
    }
}

Write-Host "`nSetup complete."
