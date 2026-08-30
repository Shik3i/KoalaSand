[CmdletBinding()]
param(
    [ValidateSet('first','final')]
    [string]$Pass = 'final',
    [switch]$SkipExisting
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $repoRoot "artifacts\phase138\$Pass"
$logRoot = Join-Path $repoRoot "artifacts\phase138\capture-logs\$Pass"
New-Item -ItemType Directory -Path $outputRoot,$logRoot -Force | Out-Null

$views = [ordered]@{
    'main-menu'='main-menu'; 'new-game'='new-game'
    'character'='character-spawn'; 'character-jetpack'='character-jetpack'; 'character-hover'='character-hover-build'; 'character-cave'='character-exploration'; 'character-factory'='character-factory'
    'factory'='factory-midgame'; 'factory-powered'='factory-powered'; 'creative'='creative'
    'quickbar'='quickbar'; 'build-catalog'='build-catalog'; 'build-ghost'='build-ghosts'; 'components'='component-world'
    'research'='research'; 'codex-material'='codex-material'; 'codex-component'='codex-component'
    'inspector-screen'='inspector-screen'; 'inspector-sluice'='inspector-sluice'; 'inspector-furnace'='inspector-furnace'; 'inspector-power'='inspector-power'
    'blueprints'='blueprints'; 'custom-blueprint'='custom-blueprint'; 'current-goal'='current-goal'; 'experiments'='experiments'
    'map-character'='map-character'; 'overview-factory'='map-factory'
    'temperature-overlay'='temperature'; 'production-overlay'='production-flow'; 'power-overlay'='power-overlay'; 'planning-pause'='planning-pause'
    'tree'='tree-world'; 'fire'='fire'; 'water'='water'; 'steam'='steam'
    'save-browser'='save-browser'; 'settings'='settings'; 'pause'='pause-menu'
    'full-game-character'='full-game-character'; 'full-game-factory'='full-game-factory'; 'realistic-max-factory'='full-game-megafactory'
}

$failures = @()
foreach ($item in $views.GetEnumerator()) {
    $capture = Join-Path $outputRoot ("phase138-$($item.Key).png")
    if ($SkipExisting -and (Test-Path -LiteralPath $capture -PathType Leaf)) { continue }
    $log = Join-Path $logRoot ("phase138-$($item.Key).log")
    $captureTick = if ($item.Key -in @('planning-pause','pause','settings')) { 0 } elseif ($item.Key -in @('steam','fire','tree')) { 180 } else { 45 }
    & (Join-Path $repoRoot 'scripts\godot.ps1') -MuteAudio --path $repoRoot --user-args "--phase136-view=$($item.Value)" "--capture-showcase=$capture" "--capture-tick=$captureTick" --capture-1080p *>&1 | Set-Content -LiteralPath $log -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $capture -PathType Leaf)) { $failures += "$($item.Key) exit=$LASTEXITCODE" }
}

foreach ($size in @('1600x900','2560x1440')) {
    $capture = Join-Path $outputRoot "phase138-resolution-$size.png"
    $log = Join-Path $logRoot "phase138-resolution-$size.log"
    & (Join-Path $repoRoot 'scripts\godot.ps1') -MuteAudio --path $repoRoot --user-args --phase136-view=full-game-factory "--capture-showcase=$capture" --capture-tick=45 "--capture-size=$size" *>&1 | Set-Content -LiteralPath $log -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $capture -PathType Leaf)) { $failures += "resolution-$size exit=$LASTEXITCODE" }
}

if ($failures.Count -gt 0) { throw "Phase 13.8 capture failures: $($failures -join ', ')" }
$captured = Get-ChildItem -LiteralPath $outputRoot -Filter 'phase138-*.png' -File
Write-Output "PHASE138_CAPTURE_PASS pass=$Pass files=$($captured.Count) audio=Dummy concurrent_processes=1"
$captured | Sort-Object Name | Select-Object Name,Length
