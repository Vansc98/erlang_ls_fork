<#
.SYNOPSIS
    Copy the built erlang_ls escript into the Erlang OTP bin directory.

.DESCRIPTION
    Writing to "Program Files" requires administrator rights, so unless
    -Elevated is given the script relaunches itself through UAC.

.PARAMETER Destination
    Target directory. Defaults to the local Erlang OTP installation.

.PARAMETER Elevated
    Internal. Set when the script is already running with the rights needed
    to write to the destination.
#>
param(
    [switch]$Elevated,
    [string]$Destination = 'D:\Program Files\Erlang OTP\bin'
)

$ErrorActionPreference = 'Stop'

if (-not $Elevated) {
    $Arguments = @(
        '-NoProfile',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Elevated',
        '-Destination', ('"{0}"' -f $Destination)
    )
    $Process = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
        -ArgumentList $Arguments -Wait -PassThru
    exit $Process.ExitCode
}

$SourceDir = Join-Path (Split-Path -Parent $PSScriptRoot) '_build\default\bin'
$Files = @('erlang_ls', 'erlang_ls.cmd') | ForEach-Object {
    Join-Path $SourceDir $_
}

foreach ($File in $Files) {
    if (-not (Test-Path -LiteralPath $File)) {
        throw "Missing build artifact: $File (run the '生成bin(windows)' task first)"
    }
}

if (-not (Test-Path -LiteralPath $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

Copy-Item -LiteralPath $Files -Destination $Destination -Force
Write-Host "Copied erlang_ls binaries to $Destination"
