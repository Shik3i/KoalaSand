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
    'tests/v5_worldgen.gd'
)
if ($Quick) {
    $Tests = @('tests/test_runner.gd', 'tests/native_correctness.gd', 'tests/phase13_correctness.gd', 'tests/phase13_persistence.gd', 'tests/phase137_hardening.gd')
}

$Failures = @()
$Started = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($Test in $Tests) {
    $Resource = 'res://' + $Test.Replace('\', '/')
    Write-Output "TEST_START $Resource"
    $Output = @(& $Godot -MuteAudio --headless --path $RepositoryRoot --script $Resource 2>&1)
    $ExitCode = $LASTEXITCODE
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
