[CmdletBinding(PositionalBinding = $false)]
param(
    # Render one category only, e.g. -Only caves
    [string] $Only,
    # Render full-resolution single-seed inspection frames instead of the contact sheets.
    [int] $Detail = -1
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$UserArguments = @()
if (-not [string]::IsNullOrWhiteSpace($Only)) { $UserArguments += "--only=$Only" }
if ($Detail -ge 0) { $UserArguments += "--detail=$Detail" }

$Arguments = @('-MuteAudio', '--headless', '--path', $RepositoryRoot, '--script', 'res://tests/capture_v5_contact_sheets.gd')
if ($UserArguments.Count -gt 0) { $Arguments += @('--user-args') + $UserArguments }

& (Join-Path $PSScriptRoot 'godot.ps1') @Arguments
exit $LASTEXITCODE
