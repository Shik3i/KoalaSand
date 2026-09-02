[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
& (Join-Path $PSScriptRoot 'godot.ps1') -MuteAudio --headless --path $RepositoryRoot --script res://tests/capture_p05_contact_sheets.gd
exit $LASTEXITCODE
