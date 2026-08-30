[CmdletBinding()]
param(
    [ValidateSet('first','final')]
    [string]$Pass = 'final'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = Join-Path $repoRoot "artifacts\phase139b\$Pass"
$groups = [ordered]@{
    'ui-all' = @('factory-clean','character-clean','creative-clean','bottom-hud','top-hud','current-goal','catalog-100','catalog-125','catalog-150','catalog-1600x900','catalog-2560x1440','catalog-tooltip','tooltip-bottom-edge','tooltip-right-edge','quickbar-full','action-tools','research','research-150','codex','inspector','blueprints','map','stats','first-build-highlight','first-research-highlight','first-inspector-highlight','new-game','save-browser','settings','pause')
    'ftue' = @('character-clean','current-goal','catalog-tooltip','first-build-highlight','first-research-highlight','first-inspector-highlight','new-game','research','inspector','blueprints')
    'responsive' = @('catalog-100','catalog-125','catalog-150','catalog-1600x900','catalog-2560x1440','tooltip-bottom-edge','tooltip-right-edge','bottom-hud','top-hud')
}
foreach ($group in $groups.GetEnumerator()) {
    $tileWidth = 480; $tileHeight = 292; $columns = if ($group.Key -eq 'ui-all') { 5 } else { 3 }
    $rows = [Math]::Ceiling($group.Value.Count / $columns)
    $sheet = New-Object System.Drawing.Bitmap ($columns * $tileWidth),([int]$rows * $tileHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($sheet)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(8,16,21)); $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold); $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(242,194,100))
        try {
            for ($index = 0; $index -lt $group.Value.Count; $index++) {
                $name = $group.Value[$index]; $path = Join-Path $sourceRoot "phase139b-$name.png"
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing capture: $path" }
                $source = [System.Drawing.Image]::FromFile($path)
                try {
                    $x = ($index % $columns) * $tileWidth; $y = [Math]::Floor($index / $columns) * $tileHeight
                    $graphics.DrawImage($source,$x,$y,$tileWidth,270); $graphics.DrawString($name,$font,$brush,$x + 8,$y + 272)
                } finally { $source.Dispose() }
            }
            $sheet.Save((Join-Path $sourceRoot "phase139b-$($group.Key).png"),[System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $font.Dispose(); $brush.Dispose() }
    } finally { $graphics.Dispose(); $sheet.Dispose() }
}
Get-ChildItem -LiteralPath $sourceRoot -Filter 'phase139b-*.png' | Sort-Object Name | Select-Object Name,Length
