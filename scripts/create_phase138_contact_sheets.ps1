[CmdletBinding()]
param(
    [ValidateSet('first','final')]
    [string]$Pass = 'final'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = Join-Path $repoRoot "artifacts\phase138\$Pass"
$outputRoot = Join-Path $repoRoot 'artifacts\phase138'
$groups = [ordered]@{
    'ui' = @('main-menu','new-game','quickbar','build-catalog','research','codex-material','codex-component','inspector-screen','inspector-sluice','inspector-furnace','inspector-power','blueprints','custom-blueprint','current-goal','experiments','save-browser','settings','pause')
    'gameplay' = @('character','character-jetpack','character-hover','character-cave','character-factory','factory','factory-powered','creative','build-ghost','components','map-character','overview-factory','planning-pause','full-game-character','full-game-factory','realistic-max-factory')
    'world-physics' = @('temperature-overlay','production-overlay','power-overlay','tree','fire','water','steam','components','factory-powered')
}

foreach ($group in $groups.GetEnumerator()) {
    $tileWidth = 480; $tileHeight = 292; $columns = 4
    $rows = [Math]::Ceiling($group.Value.Count / $columns)
    $sheet = New-Object System.Drawing.Bitmap ($columns * $tileWidth),([int]$rows * $tileHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($sheet)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(8,16,21))
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(242,194,100))
        try {
            for ($index = 0; $index -lt $group.Value.Count; $index++) {
                $name = $group.Value[$index]
                $path = Join-Path $sourceRoot "phase138-$name.png"
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing capture: $path" }
                $source = [System.Drawing.Image]::FromFile($path)
                try {
                    $x = ($index % $columns) * $tileWidth; $y = [Math]::Floor($index / $columns) * $tileHeight
                    $graphics.DrawImage($source,$x,$y,$tileWidth,270)
                    $graphics.DrawString($name,$font,$brush,$x + 8,$y + 272)
                } finally { $source.Dispose() }
            }
            $sheet.Save((Join-Path $outputRoot "phase138-$Pass-$($group.Key)-contact-sheet.png"),[System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $font.Dispose(); $brush.Dispose() }
    } finally { $graphics.Dispose(); $sheet.Dispose() }
}

Get-ChildItem -LiteralPath $outputRoot -Filter "phase138-$Pass-*-contact-sheet.png" | Sort-Object Name | Select-Object Name,Length
