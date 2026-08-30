[CmdletBinding()]
param([ValidateSet('first','final')][string]$Pass = 'final')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = Join-Path $repoRoot "artifacts\phase139\$Pass"
$files = @(Get-ChildItem -LiteralPath $sourceRoot -Filter 'phase139-*.png' -File |
    Where-Object { $_.Name -notlike '*-contact-sheet.png' } |
    Sort-Object Name)
if ($files.Count -eq 0) { throw "No Phase 13.9 captures found in $sourceRoot" }
$thumbWidth = 480; $thumbHeight = 270; $captionHeight = 34; $columns = 3
$rows = [Math]::Ceiling($files.Count / $columns)
$sheet = New-Object System.Drawing.Bitmap ($columns * $thumbWidth),($rows * ($thumbHeight + $captionHeight))
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(8,16,21))
    $font = New-Object System.Drawing.Font 'Segoe UI',10
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(232,229,220))
    try {
        for ($index = 0; $index -lt $files.Count; $index++) {
            $x = ($index % $columns) * $thumbWidth; $y = [Math]::Floor($index / $columns) * ($thumbHeight + $captionHeight)
            $image = [System.Drawing.Image]::FromFile($files[$index].FullName)
            try { $graphics.DrawImage($image,$x,$y,$thumbWidth,$thumbHeight) } finally { $image.Dispose() }
            $graphics.DrawString($files[$index].BaseName,$font,$brush,$x + 8,$y + $thumbHeight + 7)
        }
        $output = Join-Path $sourceRoot "phase139-$Pass-contact-sheet.png"
        $sheet.Save($output,[System.Drawing.Imaging.ImageFormat]::Png)
        Get-Item -LiteralPath $output | Select-Object FullName,Length
    } finally { $font.Dispose(); $brush.Dispose() }
} finally { $graphics.Dispose(); $sheet.Dispose() }
