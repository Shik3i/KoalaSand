[CmdletBinding()]
param(
    [switch]$SkipExisting
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $repoRoot 'artifacts\phase136\final'
$logRoot = Join-Path $repoRoot 'artifacts\phase136\capture-logs'
New-Item -ItemType Directory -Path $outputRoot,$logRoot -Force | Out-Null

$views = @(
    'main-menu','main-menu-continue','new-game','mode-factory','mode-character','mode-creative',
    'character-spawn','character-exploration','character-jetpack','character-hover-build','character-factory',
    'factory-start','factory-midgame','factory-powered','creative',
    'quickbar','build-catalog','build-ghosts','component-world',
    'research','codex-material','codex-component','inspector-screen','inspector-furnace','inspector-power',
    'blueprints','custom-blueprint','current-goal','experiments',
    'map-character','map-factory','temperature','production-flow','power-overlay',
    'tree-world','fire','water','steam','physical-furnace','wet-separation',
    'planning-pause','pause-menu','settings','save-browser','diagnostics',
    'full-game-character','full-game-factory','full-game-megafactory'
)

$failures = @()
foreach ($view in $views) {
    $capture = Join-Path $outputRoot ("phase136-$view.png")
    if ($SkipExisting -and (Test-Path -LiteralPath $capture -PathType Leaf)) { continue }
	$log = Join-Path $logRoot ("phase136-$view.log")
	$captureTick = if ($view -in @('planning-pause','pause-menu','settings')) { 0 } else { 45 }
	& (Join-Path $repoRoot 'scripts\godot.ps1') --path $repoRoot --user-args "--phase136-view=$view" "--capture-showcase=$capture" "--capture-tick=$captureTick" --capture-1080p *>&1 | Set-Content -LiteralPath $log -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $capture -PathType Leaf)) {
        $failures += "$view exit=$LASTEXITCODE"
    }
}

$representatives = @(
    @{ Name='phase136-resolution-2560x1440.png'; Size='2560x1440' },
    @{ Name='phase136-resolution-1600x900.png'; Size='1600x900' }
)
foreach ($item in $representatives) {
    $capture = Join-Path $outputRoot $item.Name
    if ($SkipExisting -and (Test-Path -LiteralPath $capture -PathType Leaf)) { continue }
    $log = Join-Path $logRoot ($item.Name.Replace('.png','.log'))
    & (Join-Path $repoRoot 'scripts\godot.ps1') --path $repoRoot --user-args --phase136-view=full-game-factory "--capture-showcase=$capture" --capture-tick=45 "--capture-size=$($item.Size)" *>&1 | Set-Content -LiteralPath $log -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $capture -PathType Leaf)) {
        $failures += "$($item.Name) exit=$LASTEXITCODE"
    }
}

if ($failures.Count -gt 0) { throw "Phase 13.6 capture failures: $($failures -join ', ')" }
Get-ChildItem -LiteralPath $outputRoot -Filter 'phase136-*.png' | Sort-Object Name | Select-Object Name,Length
