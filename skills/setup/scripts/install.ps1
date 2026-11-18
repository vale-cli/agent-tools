<#
.SYNOPSIS
Install Vale on Windows and make sure it is on PATH.

.DESCRIPTION
Uses winget, Scoop or Chocolatey when one is installed, because a package
manager keeps Vale up to date. Otherwise downloads the release zip, verifies
it against the release's published SHA-256 checksums, and unpacks vale.exe
into a per-user directory.

Works in Windows PowerShell 5.1 and PowerShell 7. Needs no administrator
rights for the release-binary route.

.PARAMETER Binary
Skip package managers and install the release binary.

.PARAMETER AddToPath
If the install directory is not on PATH, add it to the user's PATH. Without
this switch the command to do so is printed, not run.

.PARAMETER Version
Release to install, for example 3.27.0. Default: the latest. Implies -Binary,
since package managers install their own version.

.PARAMETER InstallDir
Where vale.exe goes. Default: %LOCALAPPDATA%\Programs\vale.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File install.ps1
#>
[CmdletBinding()]
param(
    [switch]$Binary,
    [switch]$AddToPath,
    [string]$Version = $env:VALE_VERSION,
    [string]$InstallDir = $env:VALE_INSTALL_DIR
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Find-Vale {
    $cmd = Get-Command vale -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# A package manager updates the machine's PATH, not this process's copy of it.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

$existing = Find-Vale
if ($existing) {
    Write-Output "vale is already installed: $(& $existing --version) ($existing)"
    exit 0
}

if ($Version) { $Binary = $true }

if (-not $Binary) {
    $managers = @(
        @{ Name = 'winget'; Args = @('install', '-e', '--id', 'errata-ai.Vale', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity') },
        @{ Name = 'scoop'; Args = @('install', 'vale') },
        @{ Name = 'choco'; Args = @('install', 'vale', '-y') }
    )
    foreach ($m in $managers) {
        if (-not (Get-Command $m.Name -ErrorAction SilentlyContinue)) { continue }
        Write-Output "Installing Vale with $($m.Name)..."
        try {
            & $m.Name @($m.Args)
        } catch {
            Write-Warning "$($m.Name) failed: $_"
        }
        Update-SessionPath
        $found = Find-Vale
        if ($found) {
            Write-Output "Installed $(& $found --version) with $($m.Name)"
            exit 0
        }
        Write-Warning "$($m.Name) did not provide vale; trying the next option."
    }
}

$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
switch ($arch) {
    'AMD64' { $archName = '64-bit' }
    'ARM64' { $archName = 'arm64' }
    default { throw "Unsupported architecture '$arch'. See https://docs.vale.sh/topics/installation" }
}

$repo = 'https://github.com/vale-cli/vale'
if (-not $Version) {
    # The "latest" page redirects to the release's tag, which carries the version.
    $request = [Net.WebRequest]::Create("$repo/releases/latest")
    $request.Method = 'HEAD'
    $response = $request.GetResponse()
    $final = $response.ResponseUri.AbsoluteUri
    $response.Close()
    if ($final -notmatch '/v(\d+\.\d+\.\d+)$') {
        throw "Could not read a version from $final. Pass -Version (see $repo/releases)."
    }
    $Version = $Matches[1]
}
$Version = $Version.TrimStart('v')

if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\vale' }

$asset = "vale_${Version}_Windows_${archName}.zip"
$base = "$repo/releases/download/v$Version"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("vale-install-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    $zip = Join-Path $tmp $asset
    $sums = Join-Path $tmp 'checksums.txt'
    $ProgressPreference = 'SilentlyContinue'
    Write-Output "Downloading Vale $Version (Windows, $archName)..."
    Invoke-WebRequest -Uri "$base/$asset" -OutFile $zip -UseBasicParsing
    Invoke-WebRequest -Uri "$base/vale_${Version}_checksums.txt" -OutFile $sums -UseBasicParsing

    $want = $null
    foreach ($line in Get-Content $sums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2 -and $parts[1].Trim() -eq $asset) { $want = $parts[0].Trim() }
    }
    if (-not $want) { throw "The release checksums do not list $asset." }
    $got = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash
    if ($got -ne $want) { throw "Checksum mismatch for $asset; not installing." }

    $unpacked = Join-Path $tmp 'unpacked'
    Expand-Archive -Path $zip -DestinationPath $unpacked -Force
    $exe = Get-ChildItem -Path $unpacked -Filter 'vale.exe' -Recurse | Select-Object -First 1
    if (-not $exe) { throw "$asset did not contain vale.exe." }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $target = Join-Path $InstallDir 'vale.exe'
    Copy-Item -Path $exe.FullName -Destination $target -Force
    Write-Output "Installed $(& $target --version) to $target (checksum verified)"
} finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$onPath = ($env:Path -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $InstallDir.TrimEnd('\')) })
if ($onPath) { exit 0 }

# This process can use it straight away either way.
$env:Path = "$InstallDir;$env:Path"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$inUserPath = ($userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $InstallDir.TrimEnd('\')) })
if ($AddToPath) {
    if ($inUserPath) {
        Write-Output "$InstallDir is already in your user PATH; open a new terminal to pick it up."
    } else {
        $newPath = (@($userPath, $InstallDir) | Where-Object { $_ }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Output "Added $InstallDir to your user PATH. New terminals will find vale."
    }
} else {
    Write-Output "$InstallDir is not on PATH. To add it for your user, run:"
    Write-Output "  [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';$InstallDir', 'User')"
    Write-Output "Or re-run with -AddToPath. Until then, run: $target"
}
