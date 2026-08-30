[CmdletBinding()]
param(
    [ValidateSet('first','final')]
    [string]$Pass = 'final',
    [switch]$SkipExisting
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $repoRoot "artifacts\phase139b\$Pass"
$logRoot = Join-Path $repoRoot "artifacts\phase139b\capture-logs\$Pass"
New-Item -ItemType Directory -Path $outputRoot,$logRoot -Force | Out-Null

$captures = @(
    @{Name='factory-clean'; View='factory-clean'}, @{Name='character-clean'; View='character-clean'}, @{Name='creative-clean'; View='creative-clean'},
    @{Name='bottom-hud'; View='bottom-hud'}, @{Name='top-hud'; View='top-hud'}, @{Name='current-goal'; View='current-goal'},
    @{Name='catalog-100'; View='catalog-100'; Scale='1.0'}, @{Name='catalog-125'; View='catalog-125'; Scale='1.25'}, @{Name='catalog-150'; View='catalog-150'; Scale='1.5'; Size='1600x900'; Long=$true},
    @{Name='catalog-1600x900'; View='catalog-1600x900'; Size='1600x900'}, @{Name='catalog-2560x1440'; View='catalog-2560x1440'; Size='2560x1440'},
    @{Name='catalog-tooltip'; View='catalog-tooltip'}, @{Name='tooltip-bottom-edge'; View='tooltip-bottom-edge'; Scale='1.5'; Size='1600x900'}, @{Name='tooltip-right-edge'; View='tooltip-right-edge'; Size='1600x900'},
    @{Name='quickbar-full'; View='quickbar-full'}, @{Name='action-tools'; View='action-tools'},
    @{Name='research'; View='research'}, @{Name='research-150'; View='research-150'; Scale='1.5'; Size='1600x900'},
    @{Name='codex'; View='codex'}, @{Name='inspector'; View='inspector'}, @{Name='blueprints'; View='blueprints'}, @{Name='map'; View='map'}, @{Name='stats'; View='stats'},
    @{Name='first-build-highlight'; View='first-build-highlight'}, @{Name='first-research-highlight'; View='first-research-highlight'}, @{Name='first-inspector-highlight'; View='first-inspector-highlight'},
    @{Name='new-game'; View='new-game'}, @{Name='save-browser'; View='save-browser'}, @{Name='settings'; View='settings'; Tick='0'}, @{Name='pause'; View='pause'; Tick='0'}
)

$failures = @()
foreach ($item in $captures) {
    $capture = Join-Path $outputRoot "phase139b-$($item.Name).png"
    if ($SkipExisting -and (Test-Path -LiteralPath $capture -PathType Leaf)) { continue }
    $log = Join-Path $logRoot "phase139b-$($item.Name).log"
    $size = if ($item.ContainsKey('Size')) { $item.Size } else { '1920x1080' }
    $scale = if ($item.ContainsKey('Scale')) { $item.Scale } else { '1.0' }
    $tick = if ($item.ContainsKey('Tick')) { $item.Tick } else { '45' }
    $arguments = @("--phase139-view=$($item.View)","--phase139b-ui-scale=$scale","--capture-showcase=$capture","--capture-tick=$tick","--capture-size=$size")
    if ($item.ContainsKey('Long') -and $item.Long) { $arguments += '--phase139b-long-fixture' }
    & (Join-Path $repoRoot 'scripts\godot.ps1') -MuteAudio --path $repoRoot --user-args @arguments *>&1 | Set-Content -LiteralPath $log -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $capture -PathType Leaf)) { $failures += "$($item.Name) exit=$LASTEXITCODE" }
}
if ($failures.Count -gt 0) { throw "Phase 13.9B capture failures: $($failures -join ', ')" }
$captured = @(Get-ChildItem -LiteralPath $outputRoot -Filter 'phase139b-*.png' -File)
if ($captured.Count -ne 30) { throw "Expected 30 Phase 13.9B captures, found $($captured.Count)" }
Write-Output "PHASE139B_CAPTURE_PASS pass=$Pass files=$($captured.Count) audio=Dummy concurrent_processes=1"
$captured | Sort-Object Name | Select-Object Name,Length
