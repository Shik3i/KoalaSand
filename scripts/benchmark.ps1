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
    'tests/benchmark_phase135.gd',
    'tests/benchmark_p0_recovery.gd',
    'tests/benchmark_p05_world_quality.gd',
    'tests/benchmark_v5_worldgen.gd',
    'tests/benchmark_brush_input.gd'
)
$RenderedBenchmarks = @(
    'tests/benchmark_phase6_wire_render.gd',
    'tests/benchmark_phase675_render.gd'
)

# Windows PowerShell 5.1 wraps every stderr line from a native executable in an ErrorRecord.
# With $ErrorActionPreference = 'Stop' that is a terminating error, so the first script that
# writes anything to stderr -- which is what a failing script does -- aborted the whole run and
# reported itself as a crash of the harness. The remaining scripts never ran and the summary
# never printed. Collect the streams with the preference relaxed for the duration of the call,
# and let the exit code decide what failed.
function Invoke-GodotScript {
    param(
        [Parameter(Mandatory = $true)] [string] $Wrapper,
        [Parameter(Mandatory = $true)] [string[]] $Arguments
    )
    $Previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $Lines = @(& $Wrapper @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $Code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $Previous
    }
    return [pscustomobject]@{ Lines = $Lines; ExitCode = $Code }
}

$Failures = @()
foreach ($Benchmark in $Benchmarks) {
    $Resource = 'res://' + $Benchmark.Replace('\', '/')
    Write-Output "BENCHMARK_START $Resource"
    $Run = Invoke-GodotScript -Wrapper $Godot -Arguments @('-MuteAudio', '--headless', '--path', $RepositoryRoot, '--script', $Resource)
    $Output = $Run.Lines
    $ExitCode = $Run.ExitCode
    $Output | ForEach-Object { Write-Output $_ }
    $Text = $Output -join "`n"
    if ($ExitCode -ne 0 -or $Text -match '(?m)^(SCRIPT ERROR|ERROR: Failed to load script|ERROR: Cannot open file|Parse Error)') {
        $Failures += "$Resource exit=$ExitCode"
    }
}

foreach ($Benchmark in $RenderedBenchmarks) {
    $Resource = 'res://' + $Benchmark.Replace('\', '/')
    Write-Output "RENDER_BENCHMARK_START $Resource"
    $Run = Invoke-GodotScript -Wrapper $Godot -Arguments @('-MuteAudio', '--path', $RepositoryRoot, '--script', $Resource)
    $Output = $Run.Lines
    $ExitCode = $Run.ExitCode
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
        $Run = Invoke-GodotScript -Wrapper $Godot -Arguments (@('-MuteAudio', '--path', $RepositoryRoot, '--user-args') + $Case + @('--benchmark-runtime-ticks=300', '--capture-1080p'))
        $Run.Lines | ForEach-Object { Write-Output $_ }
        if ($Run.ExitCode -ne 0) { $Failures += "runtime $($Case -join ' ') exit=$($Run.ExitCode)" }
    }
}

if ($Failures.Count -gt 0) {
    $Failures | ForEach-Object { Write-Error "BENCHMARK_FAIL $_" }
    exit 1
}
Write-Output "BENCHMARK_SUITE_PASS scripts=$($Benchmarks.Count + $RenderedBenchmarks.Count) runtime=$IncludeRuntime"
exit 0
