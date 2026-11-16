# ikon-olustur.ps1 - Homemade Uninstaller ikonunu cizer (asci sapkali, gulumseyen cop kutusu)
# Cikti: homemade.ico (16-256 px) + homemade-onizleme.png
param([string]$Hedef = (Join-Path $PSScriptRoot 'homemade.ico'))

Add-Type -AssemblyName System.Drawing

function Yuvarlak-Dikdortgen([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $yol = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $yol.AddArc($x, $y, $d, $d, 180, 90)
    $yol.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $yol.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $yol.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $yol.CloseFigure()
    return $yol
}

function Yildiz([float]$cx, [float]$cy, [float]$r) {
    $yol = New-Object Drawing.Drawing2D.GraphicsPath
    $ic = $r * 0.28
    $noktalar = @(
        (New-Object Drawing.PointF($cx, ($cy - $r))), (New-Object Drawing.PointF(($cx + $ic), ($cy - $ic))),
        (New-Object Drawing.PointF(($cx + $r), $cy)), (New-Object Drawing.PointF(($cx + $ic), ($cy + $ic))),
        (New-Object Drawing.PointF($cx, ($cy + $r))), (New-Object Drawing.PointF(($cx - $ic), ($cy + $ic))),
        (New-Object Drawing.PointF(($cx - $r), $cy)), (New-Object Drawing.PointF(($cx - $ic), ($cy - $ic))))
    $yol.AddPolygon([Drawing.PointF[]]$noktalar)
    return $yol
}

function Ciz([int]$boyut) {
    $bmp = New-Object Drawing.Bitmap($boyut, $boyut, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    $g.ScaleTransform($boyut / 256.0, $boyut / 256.0)

    $koyu = [Drawing.Color]::FromArgb(255, 74, 36, 28)
    $beyaz = [Drawing.Color]::FromArgb(255, 255, 250, 242)
    $cizgi = New-Object Drawing.Pen($koyu, 9)
    $cizgi.LineJoin = 'Round'
    $koyuFirca = New-Object Drawing.SolidBrush($koyu)
    $beyazFirca = New-Object Drawing.SolidBrush($beyaz)

    # arka plan: turuncu -> pembe
    $bg = Yuvarlak-Dikdortgen 6 6 244 244 58
    $bgFirca = New-Object Drawing.Drawing2D.LinearGradientBrush(
        (New-Object Drawing.Point(0, 0)), (New-Object Drawing.Point(256, 256)),
        [Drawing.Color]::FromArgb(255, 255, 178, 64), [Drawing.Color]::FromArgb(255, 238, 72, 128))
    $g.FillPath($bgFirca, $bg)

    # cop kutusunun govdesi
    $govde = New-Object Drawing.Drawing2D.GraphicsPath
    $govde.AddPolygon([Drawing.PointF[]]@(
        (New-Object Drawing.PointF(70, 128)), (New-Object Drawing.PointF(186, 128)),
        (New-Object Drawing.PointF(174, 226)), (New-Object Drawing.PointF(82, 226))))
    $g.DrawPath($cizgi, $govde); $g.FillPath($beyazFirca, $govde)

    # kapak
    $kapak = Yuvarlak-Dikdortgen 56 108 144 22 10
    $g.DrawPath($cizgi, $kapak); $g.FillPath($beyazFirca, $kapak)

    # asci sapkasi: once koyu kenarlik (biraz buyuk), sonra beyaz ust uste
    $puflar = @(@(98, 66, 26), @(128, 50, 31), @(158, 66, 26))
    $bant = Yuvarlak-Dikdortgen 88 72 80 34 6
    foreach ($p in $puflar) { $r = $p[2] + 4.5; $g.FillEllipse($koyuFirca, $p[0] - $r, $p[1] - $r, 2 * $r, 2 * $r) }
    $g.DrawPath($cizgi, $bant)
    foreach ($p in $puflar) { $r = $p[2]; $g.FillEllipse($beyazFirca, $p[0] - $r, $p[1] - $r, 2 * $r, 2 * $r) }
    $g.FillPath($beyazFirca, $bant)
    $ince = New-Object Drawing.Pen($koyu, 5)
    $g.DrawLine($ince, 92, 84, 164, 84)

    # surat
    $g.FillEllipse($koyuFirca, 101, 152, 15, 20)
    $g.FillEllipse($koyuFirca, 140, 152, 15, 20)
    $gulus = New-Object Drawing.Pen($koyu, 8); $gulus.StartCap = 'Round'; $gulus.EndCap = 'Round'
    $g.DrawArc($gulus, 106, 160, 44, 34, 25, 130)
    $yanak = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(150, 255, 120, 150))
    $g.FillEllipse($yanak, 88, 176, 18, 11)
    $g.FillEllipse($yanak, 150, 176, 18, 11)

    # pirilti (temizlik!)
    if ($boyut -ge 32) {
        $g.FillPath($beyazFirca, (Yildiz 212 70 20))
        $g.FillPath($beyazFirca, (Yildiz 42 104 12))
        $g.FillPath($beyazFirca, (Yildiz 210 196 10))
    }

    $g.Dispose()
    return $bmp
}

$boyutlar = 16, 24, 32, 48, 64, 128, 256
$pngler = foreach ($b in $boyutlar) {
    $bmp = Ciz $b
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    if ($b -eq 256) { $bmp.Save((Join-Path $PSScriptRoot 'homemade-onizleme.png'), [Drawing.Imaging.ImageFormat]::Png) }
    $bmp.Dispose()
    , $ms.ToArray()
}

# .ico dosyasi (PNG gomulu)
$fs = [IO.File]::Create($Hedef)
$w = New-Object IO.BinaryWriter($fs)
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$boyutlar.Count)
$ofset = 6 + 16 * $boyutlar.Count
for ($i = 0; $i -lt $boyutlar.Count; $i++) {
    $b = $boyutlar[$i]; $veri = $pngler[$i]
    $w.Write([byte]($b % 256)); $w.Write([byte]($b % 256)); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$veri.Length); $w.Write([uint32]$ofset)
    $ofset += $veri.Length
}
foreach ($veri in $pngler) { $w.Write($veri) }
$w.Close()
"Ikon yazildi: $Hedef"
