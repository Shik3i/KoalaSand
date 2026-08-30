[CmdletBinding()]
param(
    [switch] $IncludeRuntime
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$Godot = Join-Path $PSScriptRoot 'godot.ps1'
$Benchmarks = @(
    'tests/benchmark.gd',
    'tests/benchmark_phase15.gd',
    'tests/benchmark_phase2.gd',
    'tests/benchmark_phase3.gd',
    'tests/benchmark_phase4.gd',
    'tests/benchmark_phase5.gd',
    'tests/benchmark_phase6.gd',
    'tests/benchmark_phase6_research.gd',
    'tests/benchmark_phase65.gd',
    'tests/benchmark_phase675_mixed.gd',
    'tests/benchmark_phase7_render.gd',
    'tests/benchmark_phase7.gd',
    'tests/benchmark_phase7_streaming.gd',
    'tests/benchmark_phase8.gd',
    'tests/benchmark_phase8_wet.gd',
    'tests/benchmark_phase875.gd',
    'tests/benchmark_phase9.gd',
    'tests/benchmark_phase95.gd',
    'tests/benchmark_phase10.gd',
    'tests/benchmark_phase11.gd',
    'tests/benchmark_phase115.gd',
    'tests/benchmark_phase12.gd',
    'tests/benchmark_phase13.gd',
    'tests/benchmark_phase135.gd'
)
$RenderedBenchmarks = @(
    'tests/benchmark_phase6_wire_render.gd',
    'tests/benchmark_phase675_render.gd'
)

$Failures = @()
foreach ($Benchmark in $Benchmarks) {
    $Resource = 'res://' + $Benchmark.Replace('\', '/')
    Write-Output "BENCHMARK_START $Resource"
    $Output = @(& $Godot -MuteAudio --headless --path $RepositoryRoot --script $Resource 2>&1)
    $ExitCode = $LASTEXITCODE
    $Output | ForEach-Object { Write-Output $_ }
    $Text = $Output -join "`n"
    if ($ExitCode -ne 0 -or $Text -match '(?m)^(SCRIPT ERROR|ERROR: Failed to load script|ERROR: Cannot open file|Parse Error)') {
        $Failures += "$Resource exit=$ExitCode"
    }
}

foreach ($Benchmark in $RenderedBenchmarks) {
    $Resource = 'res://' + $Benchmark.Replace('\', '/')
    Write-Output "RENDER_BENCHMARK_START $Resource"
    $Output = @(& $Godot -MuteAudio --path $RepositoryRoot --script $Resource 2>&1)
    $ExitCode = $LASTEXITCODE
    $Output | ForEach-Object { Write-Output $_ }
    $Text = $Output -join "`n"
    if ($ExitCode -ne 0 -or $Text -match '(?m)^(SCRIPT ERROR|ERROR: Failed to load script|ERROR: Cannot open file|Parse Error)') {
        $Failures += "$Resource exit=$ExitCode"
    }
}

if ($IncludeRuntime) {
    $RuntimeCases = @(
        @('--phase11-view=character-factory'),
        @('--phase13-view=full-game-factory'),
        @('--creative-fixture'),
        @('--realistic-max-factory'),
        @('--dense-factory')
    )
    foreach ($Case in $RuntimeCases) {
        Write-Output "RUNTIME_BENCHMARK_START $($Case -join ' ')"
        & $Godot -MuteAudio --path $RepositoryRoot --user-args @Case --benchmark-runtime-ticks=300 --capture-1080p
        if ($LASTEXITCODE -ne 0) { $Failures += "runtime $($Case -join ' ') exit=$LASTEXITCODE" }
    }
}

if ($Failures.Count -gt 0) {
    $Failures | ForEach-Object { Write-Error "BENCHMARK_FAIL $_" }
    exit 1
}
Write-Output "BENCHMARK_SUITE_PASS scripts=$($Benchmarks.Count + $RenderedBenchmarks.Count) runtime=$IncludeRuntime"
exit 0
