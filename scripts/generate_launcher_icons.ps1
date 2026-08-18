Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$res = 'c:\Users\DRazumovskij\Downloads\product_boards_ozon_share_fixed\product_boards\android\app\src\main\res'
$sizes = @{ 'mipmap-mdpi'=48; 'mipmap-hdpi'=72; 'mipmap-xhdpi'=96; 'mipmap-xxhdpi'=144; 'mipmap-xxxhdpi'=192 }

foreach ($k in $sizes.Keys) {
    New-Item -ItemType Directory -Force -Path (Join-Path $res $k) | Out-Null
    $size = $sizes[$k]
    $path = Join-Path $res "$k\ic_launcher.png"
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#F6F6F4'))
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 15, 15, 15))
    $s = $size / 108.0
    $d = 2 * (6 * $s)
    $bx = 34 * $s; $by = 20 * $s; $bw = 48 * $s; $bh = 48 * $s

    $path2 = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path2.AddArc($bx, $by, $d, $d, 180, 90)
    $path2.AddArc($bx + $bw - $d, $by, $d, $d, 270, 90)
    $path2.AddArc($bx + $bw - $d, $by + $bh - $d, $d, $d, 0, 90)
    $path2.AddArc($bx, $by + $bh - $d, $d, $d, 90, 90)
    $path2.CloseFigure()
    $g.FillPath($brush, $path2)
    $path2.Dispose()

    $pts = New-Object 'System.Drawing.PointF[]' 3
    $pts[0] = New-Object System.Drawing.PointF -ArgumentList @([single]$bx, [single]($by + $bh))
    $pts[1] = New-Object System.Drawing.PointF -ArgumentList @([single]($bx + $bw), [single]($by + $bh))
    $pts[2] = New-Object System.Drawing.PointF -ArgumentList @([single]($bx + ($bw / 2)), [single]($by + $bh + (16 * $s)))
    $g.FillPolygon($brush, $pts)

    $g.Dispose(); $brush.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "OK $k -> $path"
}
