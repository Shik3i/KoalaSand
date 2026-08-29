[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = Join-Path $repoRoot 'artifacts\phase136\final'
$outputRoot = Join-Path $repoRoot 'artifacts\phase136'

$groups = [ordered]@{
    'phase136-ui-contact-sheet.png' = @('main-menu','main-menu-continue','new-game','mode-factory','mode-character','mode-creative','quickbar','build-catalog','research','codex-material','codex-component','inspector-screen','inspector-furnace','inspector-power','blueprints','custom-blueprint','current-goal','experiments','pause-menu','settings','save-browser','diagnostics')
    'phase136-world-contact-sheet.png' = @('component-world','build-ghosts','temperature','production-flow','power-overlay','tree-world','fire','water','steam','physical-furnace','wet-separation','factory-powered')
    'phase136-gameplay-contact-sheet.png' = @('character-spawn','character-exploration','character-jetpack','character-hover-build','character-factory','factory-start','factory-midgame','factory-powered','creative','map-character','map-factory','planning-pause','full-game-character','full-game-factory','full-game-megafactory')
}

foreach ($entry in $groups.GetEnumerator()) {
    $tileWidth = 480
    $tileHeight = 292
    $columns = 4
    $rows = [Math]::Ceiling($entry.Value.Count / $columns)
    $sheet = New-Object System.Drawing.Bitmap ($columns * $tileWidth),([int]$rows * $tileHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($sheet)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(8,16,21))
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(242,194,100))
        try {
            for ($index = 0; $index -lt $entry.Value.Count; $index++) {
                $name = $entry.Value[$index]
                $path = Join-Path $sourceRoot ("phase136-$name.png")
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing capture: $path" }
                $image = [System.Drawing.Image]::FromFile($path)
                try {
                    $x = ($index % $columns) * $tileWidth
                    $y = [Math]::Floor($index / $columns) * $tileHeight
                    $graphics.DrawImage($image,$x,$y,$tileWidth,270)
                    $graphics.DrawString($name,$font,$brush,$x + 8,$y + 272)
                } finally { $image.Dispose() }
            }
            $sheet.Save((Join-Path $outputRoot $entry.Key),[System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $font.Dispose(); $brush.Dispose() }
    } finally { $graphics.Dispose(); $sheet.Dispose() }
}

Get-ChildItem -LiteralPath $outputRoot -Filter 'phase136-*-contact-sheet.png' | Sort-Object Name | Select-Object Name,Length
