[CmdletBinding()]
param(
    [switch] $Clean
)

$ErrorActionPreference = 'Stop'

$RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$DependencyRoot = Join-Path $RepositoryRoot '.deps\godot-cpp'
$NativeRoot = Join-Path $RepositoryRoot 'native'
$BuildRoot = Join-Path $NativeRoot 'build'
$PinnedCommit = '5ed72a0dc2517a8082598a950895c6b24e8aa282'
$GodotCppRepository = 'https://github.com/godotengine/godot-cpp.git'

if ($Clean -and (Test-Path -LiteralPath $BuildRoot)) {
    $ResolvedNativeRoot = [System.IO.Path]::GetFullPath($NativeRoot)
    $ResolvedBuildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
    if (-not $ResolvedBuildRoot.StartsWith($ResolvedNativeRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe native build target: $ResolvedBuildRoot"
    }
    Remove-Item -LiteralPath $ResolvedBuildRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
New-Item -ItemType File -Force -Path (Join-Path $BuildRoot '.gdignore') | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $DependencyRoot '.git'))) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DependencyRoot) | Out-Null
    git clone --filter=blob:none $GodotCppRepository $DependencyRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to clone godot-cpp.'
    }
}

git -c core.excludesFile=NUL -C $DependencyRoot cat-file -e "$PinnedCommit`^{commit}"
if ($LASTEXITCODE -ne 0) {
    git -c core.excludesFile=NUL -C $DependencyRoot fetch origin $PinnedCommit
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to fetch pinned godot-cpp commit $PinnedCommit."
    }
}
git -c core.excludesFile=NUL -C $DependencyRoot checkout --detach $PinnedCommit
if ($LASTEXITCODE -ne 0) {
    throw "Failed to check out pinned godot-cpp commit $PinnedCommit."
}

$ConfigureArguments = @(
    '-S', $NativeRoot,
    '-B', $BuildRoot,
    '-G', 'MinGW Makefiles',
    '-DCMAKE_BUILD_TYPE=Release',
    "-DGODOT_CPP_DIR=$DependencyRoot",
    '-DGODOTCPP_API_VERSION=4.7',
    '-DGODOTCPP_TARGET=template_release'
)
& cmake @ConfigureArguments
if ($LASTEXITCODE -ne 0) {
    throw 'Native CMake configuration failed.'
}

cmake --build $BuildRoot --parallel ([Environment]::ProcessorCount)
if ($LASTEXITCODE -ne 0) {
    throw 'Native release build failed.'
}

ctest --test-dir $BuildRoot --output-on-failure
if ($LASTEXITCODE -ne 0) {
    throw 'Native CTest verification failed.'
}
