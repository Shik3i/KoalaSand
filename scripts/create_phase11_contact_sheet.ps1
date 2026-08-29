param(
    [string]$InputDirectory = (Join-Path $PSScriptRoot '..\artifacts\phase11'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\phase11\phase11-contact-sheet.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$files = Get-ChildItem -LiteralPath $InputDirectory -Filter '*.png' |
    Where-Object { $_.Name -notmatch 'contact-sheet' } |
    Sort-Object Name
if ($files.Count -eq 0) { throw "No PNG captures found in $InputDirectory" }

$columns = 4
$tileWidth = 480
$imageHeight = 270
$labelHeight = 24
$rows = [int][Math]::Ceiling($files.Count / $columns)
$sheet = [System.Drawing.Bitmap]::new($columns * $tileWidth, $rows * ($imageHeight + $labelHeight))
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
$font = [System.Drawing.Font]::new('Segoe UI', 9)
$brush = [System.Drawing.Brushes]::White
try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(7, 14, 19))
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    for ($index = 0; $index -lt $files.Count; $index++) {
        $x = ($index % $columns) * $tileWidth
        $y = [int]($index / $columns) * ($imageHeight + $labelHeight)
        $image = [System.Drawing.Image]::FromFile($files[$index].FullName)
        try {
            $graphics.DrawImage($image, $x, $y, $tileWidth, $imageHeight)
            $graphics.DrawString($files[$index].BaseName, $font, $brush, $x + 6, $y + $imageHeight + 3)
        } finally {
            $image.Dispose()
        }
    }
    $sheet.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $font.Dispose()
    $graphics.Dispose()
    $sheet.Dispose()
}

Get-Item -LiteralPath $OutputPath | Select-Object FullName, Length
