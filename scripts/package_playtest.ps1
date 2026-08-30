[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $repoRoot 'artifacts\playtest'
$projectConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'project.godot') -Raw
$versionMatch = [regex]::Match($projectConfig, '(?m)^config/version="([^"]+)"$')
if (-not $versionMatch.Success) { throw 'application/config/version is missing from project.godot' }
$version = $versionMatch.Groups[1].Value
if ($version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$') { throw "Unsafe package version: $version" }
$packageName = "KoalaSand-$version-windows-x64"
$packageRoot = Join-Path $artifactRoot $packageName
$archivePath = Join-Path $artifactRoot ($packageName + '.zip')
$templateVersion = '4.7.1.stable'
$installedTemplateRoot = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion"
$runtimeTemplateRoot = Join-Path $repoRoot ".godot-runtime\Roaming\Godot\export_templates\$templateVersion"
$resolvedArtifactRoot = [System.IO.Path]::GetFullPath($artifactRoot)
$resolvedPackageRoot = [System.IO.Path]::GetFullPath($packageRoot)
if (-not $resolvedPackageRoot.StartsWith($resolvedArtifactRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe package target: $resolvedPackageRoot"
}

$requiredTemplates = @('windows_debug_x86_64.exe', 'windows_release_x86_64.exe', 'version.txt')
if (-not (Test-Path -LiteralPath (Join-Path $runtimeTemplateRoot 'windows_release_x86_64.exe') -PathType Leaf)) {
    foreach ($template in $requiredTemplates) {
        $source = Join-Path $installedTemplateRoot $template
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Required installed Godot $templateVersion export template not found: $source"
        }
    }
    New-Item -ItemType Directory -Path $runtimeTemplateRoot -Force | Out-Null
    foreach ($template in $requiredTemplates) {
        Copy-Item -LiteralPath (Join-Path $installedTemplateRoot $template) -Destination $runtimeTemplateRoot -Force
    }
}

$sourceExtensions = @('.gd', '.uid', '.tscn', '.tres', '.godot', '.gdextension', '.json', '.cfg', '.cpp', '.hpp', '.h', '.ps1', '.md', '.txt')
$sourceFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object {
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/')
    $_.Extension -in $sourceExtensions -and
    -not $relative.StartsWith('.godot/') -and
    -not $relative.StartsWith('.godot-runtime/') -and
    -not $relative.StartsWith('.runtime-captures/') -and
    -not $relative.StartsWith('.deps/') -and
    -not $relative.StartsWith('.safety-snapshots/') -and
    -not $relative.StartsWith('artifacts/') -and
    -not $relative.StartsWith('native/build/') -and
    -not $relative.StartsWith('native/bin/') -and
    $relative -ne 'BUILD_MANIFEST.json'
} | Sort-Object FullName
$manifestLines = foreach ($file in $sourceFiles) {
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName).Replace('\', '/')
    "$relative $((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)"
}
$manifestHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($manifestLines -join "`n")))).ToLowerInvariant()
$buildId = 'local-' + $manifestHash.Substring(0, 12)
$manifest = [ordered]@{
    version = $version
    build_id = $buildId
    source_manifest_sha256 = $manifestHash
    build_timestamp_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    source_file_count = $sourceFiles.Count
    method = 'SHA-256 of sorted relative-path plus per-file SHA-256 records; Git not required.'
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repoRoot 'BUILD_MANIFEST.json') -Encoding utf8NoBOM

New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
if (Test-Path -LiteralPath $packageRoot) { Remove-Item -LiteralPath $packageRoot -Recurse -Force }
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

& (Join-Path $repoRoot 'scripts\godot.ps1') -MuteAudio --headless --path $repoRoot --export-release 'Windows Desktop' (Join-Path $packageRoot 'KoalaSand.exe')
if ($LASTEXITCODE -ne 0) { throw "Godot export failed: $LASTEXITCODE" }

Copy-Item -LiteralPath (Join-Path $repoRoot 'README-PLAYTEST.txt') -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.txt') -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $repoRoot 'PLAYTEST_CHECKLIST.md') -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $repoRoot 'BUILD_MANIFEST.json') -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $packageRoot 'LICENSE-KOALASAND.txt')
Copy-Item -LiteralPath (Join-Path $repoRoot 'licenses\GODOT_LICENSE.txt') -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $repoRoot 'licenses\GODOT_CPP_LICENSE.txt') -Destination $packageRoot
Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal
$archive = Get-Item -LiteralPath $archivePath
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
$files = Get-ChildItem -LiteralPath $packageRoot -File | Sort-Object Name | Select-Object Name,Length
[pscustomobject]@{ Version=$manifest.version; BuildId=$buildId; SourceManifest=$manifestHash; Folder=$packageRoot; Archive=$archivePath; ArchiveBytes=$archive.Length; ArchiveSHA256=$hash; Files=$files } | Format-List
