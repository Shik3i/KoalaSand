[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $GodotExecutable = $env:KOALASAND_GODOT,
    [switch] $NativeBacktrace,
    [switch] $MuteAudio,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $GodotArguments
)

$ErrorActionPreference = 'Stop'

$RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$RequiredExecutableName = 'Godot_v4.7.1-stable_win64_console.exe'
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    $SiblingCandidate = Join-Path (Split-Path -Parent $RepositoryRoot) "Godot\$RequiredExecutableName"
    $PathCandidate = Get-Command $RequiredExecutableName -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $SiblingCandidate -PathType Leaf) {
        $GodotExecutable = $SiblingCandidate
    }
    elseif ($null -ne $PathCandidate) {
        $GodotExecutable = $PathCandidate.Source
    }
}
$RuntimeRoot = Join-Path $RepositoryRoot '.godot-runtime'
$RepoAppData = Join-Path $RuntimeRoot 'Roaming'
$RepoLocalAppData = Join-Path $RuntimeRoot 'Local'

if ([string]::IsNullOrWhiteSpace($GodotExecutable) -or -not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    throw "Required Godot 4.7.1 executable not found. Set KOALASAND_GODOT or pass -GodotExecutable with $RequiredExecutableName."
}
if ([System.IO.Path]::GetFileName($GodotExecutable) -ne $RequiredExecutableName) {
    throw "Unsupported Godot executable: $GodotExecutable. Required: $RequiredExecutableName"
}

New-Item -ItemType Directory -Force -Path $RepoAppData, $RepoLocalAppData | Out-Null

$PreviousAppData = $env:APPDATA
$PreviousLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = $RepoAppData
    $env:LOCALAPPDATA = $RepoLocalAppData
    $UserArgumentSeparator = [Array]::IndexOf($GodotArguments, '--user-args')
    if ($UserArgumentSeparator -ge 0) {
        [string[]] $EngineArguments = if ($UserArgumentSeparator -gt 0) {
            [string[]] @($GodotArguments[0..($UserArgumentSeparator - 1)])
        }
        else {
            @()
        }
        [string[]] $UserArguments = if ($UserArgumentSeparator + 1 -lt $GodotArguments.Count) {
            [string[]] @($GodotArguments[($UserArgumentSeparator + 1)..($GodotArguments.Count - 1)])
        }
        else {
            @()
        }
        $AutomatedRun = $MuteAudio -or ($UserArguments | Where-Object {
            $_ -match '^--(benchmark-|capture-|validate-seeds|owner-package-smoke|dense-|realistic-max)'
        }).Count -gt 0
        if ($AutomatedRun -and [Array]::IndexOf($EngineArguments, '--audio-driver') -lt 0) {
            $EngineArguments = @($EngineArguments) + @('--audio-driver', 'Dummy')
        }
        [string[]] $LaunchArguments = @($EngineArguments) + @('--') + @($UserArguments)
    }
    else {
        [string[]] $LaunchArguments = @($GodotArguments)
        if ($MuteAudio -and [Array]::IndexOf($LaunchArguments, '--audio-driver') -lt 0) {
            $LaunchArguments = @($LaunchArguments) + @('--audio-driver', 'Dummy')
        }
    }
    if ($NativeBacktrace) {
        $Debugger = Get-Command gdb.exe -ErrorAction SilentlyContinue
        if ($null -eq $Debugger) {
            throw 'Native backtrace requested but gdb.exe was not found on PATH.'
        }
        $DebugExecutable = Join-Path (Split-Path -Parent $GodotExecutable) 'Godot_v4.7.1-stable_win64.exe'
        if (-not (Test-Path -LiteralPath $DebugExecutable -PathType Leaf)) {
            throw "Native backtrace target not found: $DebugExecutable"
        }
        & $Debugger.Source --batch -ex 'set pagination off' -ex run -ex 'thread apply all bt' --args $DebugExecutable @LaunchArguments
    }
    else {
        & $GodotExecutable @LaunchArguments
    }
    $GodotExitCode = $LASTEXITCODE
}
finally {
    $env:APPDATA = $PreviousAppData
    $env:LOCALAPPDATA = $PreviousLocalAppData
}

exit $GodotExitCode
