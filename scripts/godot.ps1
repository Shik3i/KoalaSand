[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $GodotExecutable = $env:KOALASAND_GODOT,
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
        & $GodotExecutable @EngineArguments '--' @UserArguments
    }
    else {
        & $GodotExecutable @GodotArguments
    }
    $GodotExitCode = $LASTEXITCODE
}
finally {
    $env:APPDATA = $PreviousAppData
    $env:LOCALAPPDATA = $PreviousLocalAppData
}

exit $GodotExitCode
