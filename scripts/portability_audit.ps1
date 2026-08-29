[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$CoreRoot = Join-Path $RepositoryRoot 'native\core'

$Forbidden = @('Windows.h', 'CreateThread', 'QueryPerformanceCounter', 'GetTickCount', 'rand(', 'random_device', 'filesystem::path')
$Hits = @()
foreach ($Pattern in $Forbidden) {
    $Matches = & rg -n --fixed-strings $Pattern $CoreRoot 2>$null
    if ($LASTEXITCODE -eq 0) { $Hits += $Matches }
}
if ($Hits.Count -gt 0) {
    $Hits | ForEach-Object { Write-Error "portability blocker: $_" }
    exit 1
}

$BuildDirectory = Join-Path $RepositoryRoot 'native\build'
& cmake --build $BuildDirectory --config Release --target koalasand_core_probe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Probe = Join-Path $BuildDirectory 'Release\koalasand_core_probe.exe'
if (-not (Test-Path -LiteralPath $Probe)) { $Probe = Join-Path $BuildDirectory 'koalasand_core_probe.exe' }
& $Probe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Emcc = Get-Command emcc -ErrorAction SilentlyContinue
if ($null -eq $Emcc) {
    Write-Output 'portability_audit core_native=PASS wasm_probe=NOT_RUN blocker=Emscripten_emcc_not_installed'
    exit 0
}

$WasmOutput = Join-Path $env:TEMP 'koalasand_core_probe.js'
& $Emcc.Source '-std=c++20' '-O3' (Join-Path $CoreRoot 'physical_traits.cpp') (Join-Path $CoreRoot 'fluid_prototype.cpp') (Join-Path $CoreRoot 'portability_probe.cpp') '-o' $WasmOutput
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output "portability_audit core_native=PASS wasm_probe=PASS artifact=$WasmOutput"
