[CmdletBinding()]
param(
    [ValidateSet('first','final')]
    [string]$Pass = 'final',
    [switch]$SkipExisting
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $repoRoot "artifacts\phase139\$Pass"
$logRoot = Join-Path $repoRoot "artifacts\phase139\capture-logs\$Pass"
New-Item -ItemType Directory -Path $outputRoot,$logRoot -Force | Out-Null

$views = @(
    'new-game','mode-cards',
    'character-first-move','character-jetpack-hint','character-dig-hint','character-build-highlight',
    'factory-camera-hint','factory-build-highlight',
    'component-tooltip','material-tooltip','disabled-tooltip',
    'build-catalog-first-open','research-first-open','research-ready',
    'blueprint-example-help','basic-screen-guidance','sluice-guidance','furnace-guidance',
    'inspector-first-use','inspector-blocker','planning-pause-hint',
    'current-goal','goal-help','experiments','codex-help','controls-help',
    'empty-blueprints','empty-saves'
)

$failures = @()
foreach ($view in $views) {
    $capture = Join-Path $outputRoot "phase139-$view.png"
    if ($SkipExisting -and (Test-Path -LiteralPath $capture -PathType Leaf)) { continue }
    $log = Join-Path $logRoot "phase139-$view.log"
    $tick = if ($view -in @('planning-pause-hint','controls-help')) { 0 } else { 45 }
    & (Join-Path $repoRoot 'scripts\godot.ps1') -MuteAudio --path $repoRoot --user-args "--phase139-view=$view" "--capture-showcase=$capture" "--capture-tick=$tick" --capture-1080p *>&1 | Set-Content -LiteralPath $log -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $capture -PathType Leaf)) { $failures += "$view exit=$LASTEXITCODE" }
}

foreach ($size in @('1600x900','2560x1440')) {
    $view = "tooltip-$size"
    $capture = Join-Path $outputRoot "phase139-$view.png"
    $log = Join-Path $logRoot "phase139-$view.log"
    & (Join-Path $repoRoot 'scripts\godot.ps1') -MuteAudio --path $repoRoot --user-args "--phase139-view=$view" "--capture-showcase=$capture" --capture-tick=45 "--capture-size=$size" *>&1 | Set-Content -LiteralPath $log -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $capture -PathType Leaf)) { $failures += "$view exit=$LASTEXITCODE" }
}

if ($failures.Count -gt 0) { throw "Phase 13.9 capture failures: $($failures -join ', ')" }
$captured = Get-ChildItem -LiteralPath $outputRoot -Filter 'phase139-*.png' -File
Write-Output "PHASE139_CAPTURE_PASS pass=$Pass files=$($captured.Count) audio=Dummy concurrent_processes=1"
$captured | Sort-Object Name | Select-Object Name,Length
