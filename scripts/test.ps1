[CmdletBinding()]
param(
    [switch] $Quick
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$Godot = Join-Path $PSScriptRoot 'godot.ps1'
$Tests = @(
    'tests/test_runner.gd',
    'tests/native_correctness.gd',
    'tests/phase2_correctness.gd',
    'tests/phase3_correctness.gd',
    'tests/phase4_correctness.gd',
    'tests/phase5_correctness.gd',
    'tests/phase6_correctness.gd',
    'tests/phase65_correctness.gd',
    'tests/phase675_correctness.gd',
    'tests/phase7_correctness.gd',
    'tests/phase8_correctness.gd',
    'tests/phase85_correctness.gd',
    'tests/phase875_correctness.gd',
    'tests/phase9_correctness.gd',
    'tests/phase95_correctness.gd',
    'tests/phase10_correctness.gd',
    'tests/phase11_correctness.gd',
    'tests/phase115_correctness.gd',
    'tests/phase12_correctness.gd',
    'tests/phase13_correctness.gd',
    'tests/phase13_persistence.gd',
    'tests/phase135_correctness.gd',
    'tests/phase135_save_abuse.gd',
    'tests/phase136_correctness.gd',
    'tests/phase137_hardening.gd',
    'tests/phase138_polish.gd',
    'tests/phase139_ftue.gd',
    'tests/phase139b_layout.gd',
    'tests/p0_recovery_correctness.gd',
    'tests/p05_world_quality.gd',
    'tests/v5_worldgen.gd',
    'tests/brush_stroke.gd',
    'tests/new_world_state.gd',
    'tests/granular_movement.gd',
    'tests/build_flow.gd'
)
if ($Quick) {
    $Tests = @('tests/test_runner.gd', 'tests/native_correctness.gd', 'tests/phase13_correctness.gd', 'tests/phase13_persistence.gd', 'tests/phase137_hardening.gd')
}

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
$Started = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($Test in $Tests) {
    $Resource = 'res://' + $Test.Replace('\', '/')
    Write-Output "TEST_START $Resource"
    $Run = Invoke-GodotScript -Wrapper $Godot -Arguments @('-MuteAudio', '--headless', '--path', $RepositoryRoot, '--script', $Resource)
    $Output = $Run.Lines
    $ExitCode = $Run.ExitCode
    $Output | ForEach-Object { Write-Output $_ }
    $Text = $Output -join "`n"
    $FatalDiagnostic = $Text -match '(?m)^(SCRIPT ERROR|ERROR: Failed to load script|ERROR: Cannot open file|Parse Error)'
    if ($ExitCode -ne 0 -or $FatalDiagnostic) {
        $Failures += "$Resource exit=$ExitCode fatal_diagnostic=$FatalDiagnostic"
    }
    else {
        Write-Output "TEST_PASS $Resource"
    }
}
$Started.Stop()
if ($Failures.Count -gt 0) {
    $Failures | ForEach-Object { Write-Error "TEST_FAIL $_" }
    exit 1
}
Write-Output "TEST_SUITE_PASS scripts=$($Tests.Count) elapsed_seconds=$([Math]::Round($Started.Elapsed.TotalSeconds, 3))"
exit 0
