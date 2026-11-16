# Homemade Uninstaller (Kaldir.ps1) - reklamsiz, basit program kaldirici + geride kalan temizleyici
#
# Ne yapar:
#   1) Kurulu programlari listeler (klasik programlar + Microsoft Store uygulamalari).
#   2) Sectigin programin KENDI kaldiricisini calistirir, bitmesini bekler.
#   3) Geride kalan klasorleri, kayit defteri anahtarlarini, kisayollari, acilis kayitlarini,
#      zamanlanmis gorevleri ve servisleri bulur ve sana gosterir.
#   4) Isaretlediklerini siler: klasor/dosyalar Geri Donusum Kutusu'na gider,
#      kayit defteri / gorev / servisler silinmeden once yedek\ klasorune yedeklenir.
#
# Internete baglanmaz, hicbir sey indirmez, hicbir yere veri gondermez.
#
# Deneme (pencere acmadan, hicbir sey silmeden):  .\Kaldir.ps1 -Deneme -DenemeAd "Steam"

param(
    [switch]$Deneme,
    [string]$DenemeAd
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- yonetici
if (-not $Deneme) {
    $kimlik = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $kimlik.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
        } catch { }
        exit
    }
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

$UygulamaKlasoru = (Split-Path -Parent $PSCommandPath).TrimEnd('\')
$YedekKoku = Join-Path $UygulamaKlasoru 'yedek'
$UygulamaAdi = 'Homemade Uninstaller'
$IkonYolu = Join-Path $UygulamaKlasoru 'homemade.ico'

# ---------------------------------------------------------------- guvenlik listeleri
# Bu kelimeler tek basina "bu programa ait" demeye yetmez.
$Genel = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
@(
    'microsoft','windows','corporation','corp','inc','llc','ltd','limited','gmbh','company','software',
    'systems','technologies','technology','the','team','app','apps','application','applications','update',
    'updater','common','commonfiles','program','programs','programfiles','programdata','files','data','user',
    'users','temp','tmp','cache','caches','local','roaming','locallow','packages','package','setup','installer',
    'install','uninstall','tools','tool','driver','drivers','service','services','client','desktop','launcher',
    'helper','runtime','for','and','edition','version','free','pro','plus','lite','studio','visual','code',
    'game','games','player','manager','center','centre','online','cloud','web','network','security','media',
    'audio','video','sound','support','plugin','plugins','extension','extensions','framework','library','sdk',
    'redistributable','documents','downloads','music','pictures','videos','public','default','all','new',
    'appdata','onedrive','settings','config','logs','log','backup','crashdumps','crashreports','bin','lib',
    'google','apple','intel','nvidia','amd','realtek','adobe','oracle','java','python','node','nodejs','git',
    'store','shared','home','system','x64','x86','win32','win64','assets','resources','profile','profiles',
    'host','agent','core','components','component','tasks','task','start','startmenu','menu'
) | ForEach-Object { [void]$Genel.Add($_) }

# Bu klasorlere (ve bunlari iceren ust klasorlere) asla dokunulmaz.
$KorunanYollar = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$kisiselKlasorler = 'Desktop','MyDocuments','MyMusic','MyPictures','MyVideos','Favorites','CommonDesktopDirectory',
                    'CommonDocuments','CommonMusic','CommonPictures','CommonVideos','Startup','CommonStartup',
                    'StartMenu','CommonStartMenu','Programs','CommonPrograms'
$liste0 = @(
    $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData, $env:APPDATA,
    $env:LOCALAPPDATA, "$env:LOCALAPPDATA\Programs", "$env:LOCALAPPDATA\Packages", "$env:LOCALAPPDATA\Temp",
    "$(Split-Path $env:LOCALAPPDATA)\LocalLow", $env:USERPROFILE, (Split-Path $env:USERPROFILE), $env:PUBLIC,
    "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Saved Games", "$env:USERPROFILE\Contacts", "$env:USERPROFILE\Links",
    "$env:USERPROFILE\Searches", "$env:USERPROFILE\source", "$env:USERPROFILE\.config",
    $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial, $env:TEMP,
    "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files", "$env:ProgramFiles\WindowsApps",
    "$env:APPDATA\Microsoft", "$env:LOCALAPPDATA\Microsoft", "$env:ProgramData\Microsoft",
    "$env:ProgramData\Package Cache", "$env:ProgramData\Packages", "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch",
    $UygulamaKlasoru, (Split-Path $UygulamaKlasoru)
)
foreach ($ad0 in $kisiselKlasorler) { $liste0 += [Environment]::GetFolderPath($ad0) }
$liste0 | Where-Object { $_ } | ForEach-Object { [void]$KorunanYollar.Add($_.TrimEnd('\')) }

$KorunanKayitAdlari = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
@('Microsoft','Classes','Policies','WOW6432Node','Clients','RegisteredApplications','ODBC','Intel',
  'DefaultUserEnvironment','Partner','Setup','Windows','AppDataLow','Wow6432Node','Software','System',
  'Uninstall','Run','RunOnce','CurrentVersion') | ForEach-Object { [void]$KorunanKayitAdlari.Add($_) }

# ---------------------------------------------------------------- yardimcilar
function Duzlestir([string]$metin) {
    if (-not $metin) { return '' }
    return ($metin.ToLowerInvariant() -replace '[^\p{L}\p{N}]', '')
}

function Adi-Temizle([string]$ad) {
    $s = $ad -replace '\(.*?\)', ' ' -replace '\[.*?\]', ' ' -replace '[®™©]', ' '
    $s = $s -replace '(?i)\b(x64|x86|amd64|arm64|win64|win32|64-bit|32-bit|64 bit|32 bit)\b', ' '
    $s = $s -replace '(?i)(^|\s)v?\d+(\.\d+)+\S*', ' '     # 1.2.3 gibi surum numaralari
    $s = $s -replace '\s\d+\s*$', ' '                      # sondaki tek sayi
    $s = $s -replace '(?i)\s(version|sürüm|surum)\s*$', ' '
    return ($s -replace '\s+', ' ').Trim([char[]]' -_.,:')
}

function Yayinci-Temizle([string]$y) {
    if (-not $y) { return '' }
    $y = $y -replace '\(.*?\)', ' '
    $y = $y -replace '(?i)[,.]?\s*\b(inc|incorporated|corp|corporation|co|company|llc|l\.l\.c|ltd|limited|gmbh|ag|s\.a|sa|s\.r\.l|srl|b\.v|bv|ab|oy|pty|plc|a\.s|as)\b\.?', ' '
    return ($y -replace '\s+', ' ').Trim([char[]]' -_.,')
}

function Komutu-Ayir([string]$s) {
    $s = "$s".Trim()
    if ($s -match '^"([^"]+)"\s*(.*)$') { return @($Matches[1], $Matches[2]) }
    if ($s -match '^(.+?\.exe)(?:\s+(.*))?$') { return @($Matches[1], "$($Matches[2])") }
    return @($s, '')
}

function Korumali([string]$yol) {
    if (-not $yol) { return $true }
    $y = $yol.TrimEnd('\')
    if ($y.Length -lt 6) { return $true }                                  # C:\ , D:\Oyun gibi kokler
    if ($KorunanYollar.Contains($y)) { return $true }
    foreach ($kr in $KorunanYollar) {                                       # korunan bir yeri iceren ust klasor
        if ($kr.StartsWith($y + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $win = $env:windir.TrimEnd('\')
    if ($y.Equals($win, [StringComparison]::OrdinalIgnoreCase) -or
        $y.StartsWith($win + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($y.IndexOf('\WindowsApps\', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($y.StartsWith($UygulamaKlasoru, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

function Kayit-Korumali([string]$yol) {
    $parcalar = $yol.Split('\')
    if ($parcalar.Count -lt 3) { return $true }
    if ($KorunanKayitAdlari.Contains($parcalar[-1])) { return $true }
    return $false
}

# Baska (hala kurulu) bir programin klasorunu ya da onu iceren bir klasoru asla silme
function Baska-Programin([string]$yol) {
    $y = $yol.TrimEnd('\')
    foreach ($d in $script:DigerKonumlar) {
        if ($d.Equals($y, [StringComparison]::OrdinalIgnoreCase) -or
            $d.StartsWith($y + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Konumda([string]$metin, $konumlar) {
    if (-not $metin) { return $false }
    $metin = [Environment]::ExpandEnvironmentVariables($metin)
    foreach ($kn in $konumlar) {
        if ($metin.IndexOf($kn + '\', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        if ($metin.Trim('"', ' ').Equals($kn, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Exe-Var-Mi([string]$komut) {
    $exe = [Environment]::ExpandEnvironmentVariables((Komutu-Ayir $komut)[0]).Trim('"')
    if ($exe -notmatch '^[A-Za-z]:\\') { return $true }    # yol degil, bilemeyiz: var say
    return (Test-Path -LiteralPath $exe)
}

# ---------------------------------------------------------------- program listesi
function Yeni-Program {
    param($Tur = 'Masaüstü', $Ad = '', $Yayinci = '', $Surum = '', $BoyutMB = $null, $Tarih = $null,
          $Kaldirma = '', $SessizKaldirma = '', $Konum = '', $Ikon = '', $AnahtarYolu = '', $AnahtarAdi = '',
          $Paket = '', $PaketAile = '', $PaketAdi = '')
    [pscustomobject]@{
        Tur = $Tur; Ad = $Ad; Yayinci = $Yayinci; Surum = $Surum; BoyutMB = $BoyutMB; Tarih = $Tarih
        Kaldirma = $Kaldirma; SessizKaldirma = $SessizKaldirma; Konum = $Konum; Ikon = $Ikon
        AnahtarYolu = $AnahtarYolu; AnahtarAdi = $AnahtarAdi; Paket = $Paket; PaketAile = $PaketAile; PaketAdi = $PaketAdi
    }
}

function Programlari-Getir {
    $liste = New-Object System.Collections.Generic.List[object]
    $gorulen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $kokler = @(
        'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($kok in $kokler) {
        foreach ($an in (Get-ChildItem -LiteralPath "Registry::$kok" -ErrorAction SilentlyContinue)) {
            $ad = "$($an.GetValue('DisplayName'))".Trim()
            if (-not $ad) { continue }
            if ($an.GetValue('SystemComponent') -eq 1) { continue }
            if ($an.GetValue('ParentKeyName')) { continue }
            if ("$($an.GetValue('ReleaseType'))" -match 'Update|Hotfix') { continue }
            $kaldirma = "$($an.GetValue('UninstallString'))".Trim()
            $sessiz = "$($an.GetValue('QuietUninstallString'))".Trim()
            if (-not $kaldirma -and -not $sessiz) { continue }
            $surum = "$($an.GetValue('DisplayVersion'))".Trim()
            if (-not $gorulen.Add("$ad|$surum")) { continue }
            $boyut = $an.GetValue('EstimatedSize')
            $tarih = $null
            $t = "$($an.GetValue('InstallDate'))"
            if ($t -match '^\d{8}$') { try { $tarih = [datetime]::ParseExact($t, 'yyyyMMdd', $null) } catch { } }
            $mb = $null
            if ($boyut -is [int] -and $boyut -gt 0) { $mb = [math]::Round($boyut / 1024, 1) }
            $liste.Add((Yeni-Program -Ad $ad -Yayinci "$($an.GetValue('Publisher'))".Trim() -Surum $surum -BoyutMB $mb `
                -Tarih $tarih -Kaldirma $kaldirma -SessizKaldirma $sessiz `
                -Konum ("$($an.GetValue('InstallLocation'))".Trim('"', ' ').TrimEnd('\')) `
                -Ikon "$($an.GetValue('DisplayIcon'))".Trim() -AnahtarYolu $an.Name -AnahtarAdi $an.PSChildName))
        }
    }
    try {
        $paketler = Get-AppxPackage -ErrorAction Stop | Where-Object {
            -not $_.IsFramework -and -not $_.IsResourcePackage -and -not $_.NonRemovable -and
            ($_.SignatureKind -eq 'Store' -or $_.SignatureKind -eq 'Developer') }
        foreach ($pk in $paketler) {
            $gorunen = ''
            try { $gorunen = "$((Get-AppxPackageManifest -Package $pk.PackageFullName).Package.Properties.DisplayName)" } catch { }
            if (-not $gorunen -or $gorunen -like 'ms-resource:*') { $gorunen = $pk.Name -replace '^[^.]*\.', '' }
            $yayinci = "$($pk.Publisher)" -replace '^CN=([^,]+).*$', '$1'
            $liste.Add((Yeni-Program -Tur 'Store' -Ad $gorunen -Yayinci $yayinci -Surum "$($pk.Version)" `
                -Paket $pk.PackageFullName -PaketAile $pk.PackageFamilyName -PaketAdi $pk.Name))
        }
    } catch { }
    return $liste
}

# ---------------------------------------------------------------- anahtar kelimeler
function Anahtar-Kelimeler($prog) {
    $sozluk = [ordered]@{}
    $ekleK = {
        param([string]$metin, [bool]$kesin, [string]$kaynak)
        $n = Duzlestir $metin
        if ($n.Length -lt 3 -or $Genel.Contains($n) -or $n -match '^\d+$') { return }
        if ($sozluk.Contains($n)) {
            if ($kesin -and -not $sozluk[$n].Kesin) { $sozluk[$n] = [pscustomobject]@{ K = $n; Kesin = $true; Kaynak = $kaynak } }
            return
        }
        $sozluk[$n] = [pscustomobject]@{ K = $n; Kesin = $kesin; Kaynak = $kaynak }
    }

    $temiz = Adi-Temizle $prog.Ad
    & $ekleK $temiz $true 'program adı'

    # "Mozilla Firefox" -> "Firefox" (bastaki yayinci adini at)
    $yayinciKelimeleri = @((Yayinci-Temizle $prog.Yayinci) -split '\s+' | Where-Object { $_ })
    $kelimeler = @($temiz -split '[\s\-_.]+' | Where-Object { $_ })
    $kisa = $kelimeler
    while ($kisa.Count -gt 1 -and ($yayinciKelimeleri -contains $kisa[0])) { $kisa = @($kisa[1..($kisa.Count - 1)]) }
    if ($kisa.Count -lt $kelimeler.Count) { & $ekleK ($kisa -join ' ') $true 'program adı' }

    # tek tek kelimeler: sadece "muhtemel"
    foreach ($w in $kelimeler) {
        if ($w.Length -ge 4 -and $yayinciKelimeleri -notcontains $w) { & $ekleK $w $false 'addaki bir kelime' }
    }

    # kaldirma kaydinin adi (GUID degilse): "Steam", "Discord", "Foo_is1"
    if ($prog.AnahtarAdi) {
        $an = $prog.AnahtarAdi -replace '_is1$', ''
        if ($an -notmatch '^\{.*\}$') { & $ekleK (Adi-Temizle $an) $true 'kaldırma kaydı adı' }
    }

    # programin kendi exe'sinin adi (ikonundan): "Code", "Chrome" -> muhtemel
    if ($prog.Ikon) {
        $exe = (Komutu-Ayir ($prog.Ikon -replace ',\s*-?\d+\s*$', ''))[0]
        $b = [IO.Path]::GetFileNameWithoutExtension($exe)
        if ($b -and $b -notmatch '^(?i)(unins\d*|uninst(all)?|uninstaller|setup|install(er)?|update|helper|launcher|app|icon|main|msiexec|rundll32|shell32|imageres)$') {
            $n = Duzlestir $b
            if ($n.Length -ge 3 -and $n -notmatch '^\d+$' -and -not $sozluk.Contains($n)) {
                $sozluk[$n] = [pscustomobject]@{ K = $n; Kesin = $false; Kaynak = 'program dosyası adı' }
            }
        }
    }

    if ($prog.PaketAdi) { & $ekleK ($prog.PaketAdi -replace '^[^.]*\.', '') $true 'Store paket adı' }

    return @($sozluk.Values | Sort-Object { -not $_.Kesin })
}

function Eslesme([string]$ad, $anahtarlar) {
    $n = Duzlestir $ad
    if ($n.Length -lt 3) { return $null }
    foreach ($a in $anahtarlar) { if ($n -eq $a.K) { return $a } }
    foreach ($a in $anahtarlar) {
        if ($a.Kesin -and $a.K.Length -ge 5 -and $n.StartsWith($a.K)) {
            return [pscustomobject]@{ K = $a.K; Kesin = $false; Kaynak = "$($a.Kaynak) ile başlıyor" }
        }
    }
    return $null
}

# ---------------------------------------------------------------- tarama
function Aday-Ekle([string]$tur, [string]$yol, [string]$neden, [bool]$kesin, $ek = $null) {
    if (-not $yol) { return }
    if ($tur -eq 'Klasör' -or $tur -eq 'Kısayol') {
        if (Korumali $yol) { return }
        if ($tur -eq 'Klasör' -and (Baska-Programin $yol)) { return }
    }
    if ($tur -eq 'Kayıt defteri' -and (Kayit-Korumali $yol)) { return }
    foreach ($x in $script:Adaylar) {
        if ($x.Tur -eq $tur -and $x.Yol -eq $yol) {
            if ($kesin -and -not $x.Kesin) { $x.Kesin = $true; $x.Neden = $neden }
            return
        }
    }
    $script:Adaylar.Add([pscustomobject]@{ Tur = $tur; Yol = $yol; Neden = $neden; Kesin = $kesin; Ek = $ek })
}

function Cocuklar([string]$yol, [string]$mod) {
    if ($mod -eq 'dosya') {
        if (-not (Test-Path -LiteralPath $yol)) { return }
        Get-ChildItem -LiteralPath $yol -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
            ForEach-Object { [pscustomobject]@{ Ad = $_.Name; Yol = $_.FullName; Tur = 'Klasör' } }
    } else {
        Get-ChildItem -LiteralPath "Registry::$yol" -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ Ad = $_.PSChildName; Yol = $_.Name; Tur = 'Kayıt defteri' } }
    }
}

function Tara-Agac([string]$kok, [string]$mod, $anahtarlar, [string]$yayinciK, [bool]$hepsiMuhtemel) {
    foreach ($c in @(Cocuklar $kok $mod)) {
        $m = Eslesme $c.Ad $anahtarlar
        if ($m) {
            Aday-Ekle $c.Tur $c.Yol "Adı eşleşiyor ($($m.Kaynak))" ([bool]($m.Kesin -and -not $hepsiMuhtemel))
            continue
        }
        if ($yayinciK -and (Duzlestir $c.Ad) -eq $yayinciK) {
            $alt = @(Cocuklar $c.Yol $mod)
            $esl = 0
            foreach ($a in $alt) {
                $m2 = Eslesme $a.Ad $anahtarlar
                if ($m2) {
                    Aday-Ekle $a.Tur $a.Yol "Yayıncı klasöründe, adı eşleşiyor ($($m2.Kaynak))" ([bool]($m2.Kesin -and -not $hepsiMuhtemel))
                    $esl++
                }
            }
            if (-not $Genel.Contains($yayinciK) -and ($alt.Count -eq 0 -or $esl -eq $alt.Count)) {
                Aday-Ekle $c.Tur $c.Yol "Yayıncı klasörü ($($c.Ad)); içinde bu programdan başka bir şey yok" $false
            }
        }
    }
}

function Konum-Adaylari($prog) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if ($prog.Konum) { [void]$set.Add([Environment]::ExpandEnvironmentVariables($prog.Konum).Trim('"', ' ').TrimEnd('\')) }
    foreach ($s in @($prog.Kaldirma, $prog.SessizKaldirma, $prog.Ikon)) {
        if (-not $s) { continue }
        $exe = [Environment]::ExpandEnvironmentVariables((Komutu-Ayir ($s -replace ',\s*-?\d+\s*$', ''))[0]).Trim('"')
        if ($exe -notmatch '^[A-Za-z]:\\') { continue }
        $d = Split-Path -Parent $exe
        if (-not $d) { continue }
        if ((Split-Path -Leaf $d) -match '^(?i)(_?uninst(all)?(er)?|bin|x64|x86|setup|_uninst|uninstaller)$') { $d = Split-Path -Parent $d }
        if ($d) { [void]$set.Add($d.TrimEnd('\')) }
    }
    return @($set)
}

function Artiklari-Tara($prog) {
    $script:Adaylar = New-Object System.Collections.Generic.List[object]
    $anahtarlar = @(Anahtar-Kelimeler $prog)
    $yayinciK = Duzlestir (Yayinci-Temizle $prog.Yayinci)
    if ($yayinciK.Length -lt 3) { $yayinciK = '' }
    $script:DigerKonumlar = @($script:Programlar | Where-Object { $_ -ne $prog -and $_.Konum -and $_.Ad -ne $prog.Ad } |
        ForEach-Object { $_.Konum.TrimEnd('\') } | Where-Object { $_.Length -gt 6 })

    # 1) kurulum klasorleri (InstallLocation, kaldiricinin ve ikonun klasoru)
    $adAnahtarlari = @($anahtarlar | Where-Object { $_.Kaynak -ne 'program dosyası adı' })
    $kesinKonumlar = New-Object System.Collections.Generic.List[string]
    foreach ($d in (Konum-Adaylari $prog)) {
        if (Korumali $d) { continue }
        $lm = Eslesme (Split-Path -Leaf $d) $adAnahtarlari
        $kesin = [bool]($lm -and $lm.Kesin)
        if ($kesin -and -not (Baska-Programin $d)) { $kesinKonumlar.Add($d) }
        if (Test-Path -LiteralPath $d) { Aday-Ekle 'Klasör' $d 'Programın kurulum klasörü' $kesin }
    }
    if ($prog.Tur -eq 'Store' -and $prog.PaketAile) {
        $pd = Join-Path $env:LOCALAPPDATA "Packages\$($prog.PaketAile)"
        if (Test-Path -LiteralPath $pd) { Aday-Ekle 'Klasör' $pd 'Store uygulamasının veri klasörü' $true }
    }

    # 2) bilinen klasorlerde adi eslesenler
    $kokler = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA,
        "$env:LOCALAPPDATA\Programs", "$(Split-Path $env:LOCALAPPDATA)\LocalLow",
        "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs") |
        Where-Object { $_ } | Select-Object -Unique
    foreach ($kok in $kokler) { Tara-Agac $kok 'dosya' $anahtarlar $yayinciK $false }
    # kullanici klasorleri: kendi dosyalarin olabilir, hepsi "muhtemel"
    foreach ($kok in @($env:USERPROFILE, [Environment]::GetFolderPath('MyDocuments'))) { Tara-Agac $kok 'dosya' $anahtarlar '' $true }

    # 3) kayit defteri
    foreach ($kok in @('HKEY_CURRENT_USER\Software', 'HKEY_LOCAL_MACHINE\SOFTWARE', 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node')) {
        Tara-Agac $kok 'kayit' $anahtarlar $yayinciK $false
    }
    if ($prog.AnahtarYolu -and (Test-Path -LiteralPath "Registry::$($prog.AnahtarYolu)")) {
        Aday-Ekle 'Kayıt defteri' $prog.AnahtarYolu 'Programlar listesindeki kaldırma kaydı' $true
    }

    # 4) acilista calisanlar
    foreach ($rk in @('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run',
                      'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce',
                      'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                      'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
                      'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
        $key = Get-Item -LiteralPath "Registry::$rk" -ErrorAction SilentlyContinue
        if (-not $key) { continue }
        foreach ($vn in $key.GetValueNames()) {
            if (-not $vn) { continue }
            $vd = "$($key.GetValue($vn))"
            $ek = @{ Anahtar = $rk; Deger = $vn }
            if (Konumda $vd $kesinKonumlar) { Aday-Ekle 'Başlangıç kaydı' "$rk\$vn" "Açılışta çalışıyor: $vd" $true $ek; continue }
            $m = Eslesme $vn $anahtarlar
            if ($m) {
                $yok = -not (Exe-Var-Mi $vd)
                $neden = if ($yok) { "Adı eşleşiyor, çalıştırdığı dosya artık yok: $vd" } else { "Adı eşleşiyor: $vd" }
                Aday-Ekle 'Başlangıç kaydı' "$rk\$vn" $neden ([bool]($m.Kesin -and $yok)) $ek
            }
        }
    }

    # 5) zamanlanmis gorevler
    try {
        foreach ($g in (Get-ScheduledTask -ErrorAction Stop)) {
            if ($g.TaskPath -like '\Microsoft\*') { continue }
            $eylem = (@($g.Actions) | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join ' | '
            $ek = @{ Ad = $g.TaskName; Yol = $g.TaskPath }
            $tam = "$($g.TaskPath)$($g.TaskName)"
            if (Konumda $eylem $kesinKonumlar) { Aday-Ekle 'Zamanlanmış görev' $tam "Çalıştırdığı: $eylem" $true $ek; continue }
            $n = Duzlestir $g.TaskName
            $m = $anahtarlar | Where-Object { $_.Kesin -and $_.K.Length -ge 5 -and $n.Contains($_.K) } | Select-Object -First 1
            if ($m) { Aday-Ekle 'Zamanlanmış görev' $tam "Görev adında '$($m.K)' geçiyor: $eylem" $false $ek }
        }
    } catch { }

    # 6) servisler
    try {
        foreach ($sv in (Get-CimInstance Win32_Service -ErrorAction Stop)) {
            $pn = "$($sv.PathName)"
            if ($pn -and $pn.IndexOf($env:windir, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
            $ek = @{ Ad = $sv.Name }
            if (Konumda $pn $kesinKonumlar) { Aday-Ekle 'Servis' $sv.Name "$($sv.DisplayName) — $pn" $true $ek; continue }
            $m = Eslesme $sv.Name $anahtarlar
            if (-not $m) { $m = Eslesme $sv.DisplayName $anahtarlar }
            if ($m) { Aday-Ekle 'Servis' $sv.Name "Adı eşleşiyor: $($sv.DisplayName) — $pn" $false $ek }
        }
    } catch { }

    # 7) kisayollar (Baslat menusu, masaustu, gorev cubuguna sabitlenenler)
    $wsh = New-Object -ComObject WScript.Shell
    foreach ($kok in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
                       [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
                       "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch")) {
        if (-not $kok -or -not (Test-Path -LiteralPath $kok)) { continue }
        $derin = ($kok -like '*Start Menu*') -or ($kok -like '*Quick Launch*')
        $lnkler = if ($derin) { Get-ChildItem -LiteralPath $kok -Filter *.lnk -Recurse -Force -ErrorAction SilentlyContinue }
                  else { Get-ChildItem -LiteralPath $kok -Filter *.lnk -Force -ErrorAction SilentlyContinue }
        foreach ($l in $lnkler) {
            $hedef = ''
            try { $hedef = $wsh.CreateShortcut($l.FullName).TargetPath } catch { }
            $hedefYok = [bool]($hedef -and -not (Test-Path -LiteralPath $hedef))
            if ($hedef -and (Konumda $hedef $kesinKonumlar)) { Aday-Ekle 'Kısayol' $l.FullName "Kurulum klasörüne gidiyor: $hedef" $true; continue }
            $m = Eslesme $l.BaseName $anahtarlar
            if ($m) {
                $neden = if ($hedefYok) { "Adı eşleşiyor, gittiği dosya artık yok: $hedef" } else { "Adı eşleşiyor: $hedef" }
                Aday-Ekle 'Kısayol' $l.FullName $neden ([bool]($m.Kesin -and ($hedefYok -or -not $hedef)))
            }
        }
    }
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)

    # ic ice olanlari sadele: ust klasor "kesin" ise icindekileri ayrica gosterme
    $sirali = @($script:Adaylar | Sort-Object { $_.Yol.Length })
    $son = New-Object System.Collections.Generic.List[object]
    foreach ($a in $sirali) {
        $ust = $son | Where-Object { $_.Kesin -and $a.Yol.StartsWith($_.Yol + '\', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if (-not $ust) { $son.Add($a) }
    }
    $sira = @{ 'Klasör' = 1; 'Kısayol' = 2; 'Kayıt defteri' = 3; 'Başlangıç kaydı' = 4; 'Zamanlanmış görev' = 5; 'Servis' = 6 }
    return @($son | Sort-Object @{ e = { -not $_.Kesin } }, @{ e = { $sira[$_.Tur] } }, Yol)
}

# ---------------------------------------------------------------- silme
function Artiklari-Sil($prog, $secili) {
    $guvenliAd = ($prog.Ad -replace '[\\/:*?"<>|]', '_')
    if ($guvenliAd.Length -gt 40) { $guvenliAd = $guvenliAd.Substring(0, 40) }
    $klasor = Join-Path $YedekKoku ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $guvenliAd.Trim())
    New-Item -ItemType Directory -Path $klasor -Force | Out-Null
    $gunluk = Join-Path $klasor 'gunluk.txt'
    Add-Content -LiteralPath $gunluk -Encoding UTF8 -Value "Program: $($prog.Ad)  ($(Get-Date))"
    $basarili = 0
    $hatalar = New-Object System.Collections.Generic.List[string]
    $i = 0
    $ui = [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs
    $cop = [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    foreach ($a in $secili) {
        $i++
        try {
            switch ($a.Tur) {
                'Klasör' {
                    if (Korumali $a.Yol) { throw 'Korunan bir konum, silinmedi.' }
                    if (Test-Path -LiteralPath $a.Yol) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($a.Yol, $ui, $cop) }
                }
                'Kısayol' {
                    if (Test-Path -LiteralPath $a.Yol) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($a.Yol, $ui, $cop) }
                }
                'Kayıt defteri' {
                    if (Test-Path -LiteralPath "Registry::$($a.Yol)") {
                        & reg.exe export $a.Yol (Join-Path $klasor "kayit-$i.reg") /y 2>&1 | Out-Null
                        if ($LASTEXITCODE -ne 0) { throw 'Yedek alınamadı, bu yüzden silinmedi.' }
                        Remove-Item -LiteralPath "Registry::$($a.Yol)" -Recurse -Force -ErrorAction Stop
                    }
                }
                'Başlangıç kaydı' {
                    & reg.exe export $a.Ek.Anahtar (Join-Path $klasor "baslangic-$i.reg") /y 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw 'Yedek alınamadı, bu yüzden silinmedi.' }
                    Remove-ItemProperty -LiteralPath "Registry::$($a.Ek.Anahtar)" -Name $a.Ek.Deger -ErrorAction Stop
                }
                'Zamanlanmış görev' {
                    Export-ScheduledTask -TaskName $a.Ek.Ad -TaskPath $a.Ek.Yol -ErrorAction Stop |
                        Set-Content -LiteralPath (Join-Path $klasor "gorev-$i.xml") -Encoding Unicode
                    Unregister-ScheduledTask -TaskName $a.Ek.Ad -TaskPath $a.Ek.Yol -Confirm:$false -ErrorAction Stop
                }
                'Servis' {
                    & reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$($a.Ek.Ad)" (Join-Path $klasor "servis-$i.reg") /y 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw 'Yedek alınamadı, bu yüzden silinmedi.' }
                    Stop-Service -Name $a.Ek.Ad -Force -ErrorAction SilentlyContinue
                    & sc.exe delete $a.Ek.Ad 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "sc delete başarısız (kod $LASTEXITCODE)" }
                }
            }
            $basarili++
            Add-Content -LiteralPath $gunluk -Encoding UTF8 -Value "SİLİNDİ  [$($a.Tur)] $($a.Yol)"
        } catch {
            $hatalar.Add("$($a.Yol)  —  $($_.Exception.Message)")
            Add-Content -LiteralPath $gunluk -Encoding UTF8 -Value "HATA     [$($a.Tur)] $($a.Yol)  —  $($_.Exception.Message)"
        }
    }
    return [pscustomobject]@{ Basarili = $basarili; Hatalar = $hatalar; Klasor = $klasor }
}

# ---------------------------------------------------------------- deneme modu (pencere yok, silme yok)
if ($Deneme) {
    $script:Programlar = Programlari-Getir
    "Bulunan program: $($script:Programlar.Count)  (Store: $(@($script:Programlar | Where-Object Tur -eq 'Store').Count))"
    if ($DenemeAd) {
        $prog = $script:Programlar | Where-Object { $_.Ad -like "*$DenemeAd*" } | Select-Object -First 1
        if (-not $prog) { $prog = Yeni-Program -Ad $DenemeAd; "(kurulu degil, sadece isimle aranıyor)" } else { "Program: $($prog.Ad) | $($prog.Yayinci) | $($prog.Konum)" }
        "Anahtar kelimeler:"; Anahtar-Kelimeler $prog | ForEach-Object { "  $($_.K)  kesin=$($_.Kesin)  ($($_.Kaynak))" }
        $sure = Measure-Command { $bulunan = Artiklari-Tara $prog }
        "Tarama: $([math]::Round($sure.TotalSeconds,1)) sn, $($bulunan.Count) aday"
        $bulunan | ForEach-Object { "  [{0}] {1,-18} {2}   <- {3}" -f $(if ($_.Kesin) { 'KESIN' } else { 'muht.' }), $_.Tur, $_.Yol, $_.Neden }
    }
    return
}

# ---------------------------------------------------------------- arayuz
Add-Type -Name Dpi -Namespace KaldirUI -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][KaldirUI.Dpi]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

$yazi = New-Object Drawing.Font('Segoe UI', 10)
$kalin = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$turuncu = [Drawing.Color]::FromArgb(176, 96, 0)

$form = New-Object Windows.Forms.Form
$form.Text = "$UygulamaAdi — programı ve geride kalanlarını sil"
$form.Size = New-Object Drawing.Size(1150, 720)
$form.StartPosition = 'CenterScreen'
$form.Font = $yazi
$form.AutoScaleMode = 'Dpi'
try { $form.Icon = New-Object Drawing.Icon($IkonYolu) } catch { }

$ust = New-Object Windows.Forms.FlowLayoutPanel
$ust.Dock = 'Top'; $ust.AutoSize = $true; $ust.Padding = '8,8,8,4'; $ust.WrapContents = $false
$etiket = New-Object Windows.Forms.Label; $etiket.Text = 'Ara:'; $etiket.AutoSize = $true; $etiket.Margin = '3,7,3,3'
$arama = New-Object Windows.Forms.TextBox; $arama.Width = 380
$btnYenile = New-Object Windows.Forms.Button; $btnYenile.Text = 'Yenile'; $btnYenile.AutoSize = $true
$btnIsimle = New-Object Windows.Forms.Button; $btnIsimle.Text = 'Daha önce sildiğim bir programın artıklarını ara…'; $btnIsimle.AutoSize = $true
$ust.Controls.AddRange(@($etiket, $arama, $btnYenile, $btnIsimle))

$lv = New-Object Windows.Forms.ListView
$lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false
$Kolonlar = @('Ad', 'Yayinci', 'Surum', 'BoyutMB', 'Tarih', 'Tur')
foreach ($kol in @(@('Program', 400), @('Yayıncı', 240), @('Sürüm', 130), @('Boyut', 90), @('Kurulum', 100), @('Tür', 100))) {
    [void]$lv.Columns.Add($kol[0], $kol[1])
}

$alt = New-Object Windows.Forms.FlowLayoutPanel
$alt.Dock = 'Bottom'; $alt.AutoSize = $true; $alt.Padding = '8,4,8,8'; $alt.WrapContents = $false
$btnKaldir = New-Object Windows.Forms.Button; $btnKaldir.Text = 'Seçileni kaldır'; $btnKaldir.Font = $kalin; $btnKaldir.AutoSize = $true; $btnKaldir.Padding = '10,4,10,4'
$durumEtiket = New-Object Windows.Forms.Label; $durumEtiket.AutoSize = $true; $durumEtiket.Margin = '12,12,3,3'
$alt.Controls.AddRange(@($btnKaldir, $durumEtiket))

$menu = New-Object Windows.Forms.ContextMenuStrip
$miKaldir = $menu.Items.Add('Kaldır')
$miTara = $menu.Items.Add('Kaldırmadan sadece artıkları tara (kaldırıcısı bozuksa)')
$miKlasor = $menu.Items.Add('Kurulum klasörünü aç')
$lv.ContextMenuStrip = $menu

$form.Controls.AddRange(@($lv, $ust, $alt))
$lv.BringToFront()

$script:Programlar = @()
$script:SiraKolon = 'Ad'
$script:SiraTers = $false

function Durum([string]$m) { $durumEtiket.Text = $m; [Windows.Forms.Application]::DoEvents() }
function Bilgi([string]$m, [string]$ikon = 'Information') { [void][Windows.Forms.MessageBox]::Show($form, $m, $UygulamaAdi, 'OK', $ikon) }
function Sor([string]$m, [string]$butonlar = 'YesNo') { return [Windows.Forms.MessageBox]::Show($form, $m, $UygulamaAdi, $butonlar, 'Question') }

function Listeyi-Doldur {
    $f = $arama.Text.Trim()
    $goster = @($script:Programlar | Where-Object {
        -not $f -or $_.Ad.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        ($_.Yayinci -and $_.Yayinci.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0) })
    $goster = @($goster | Sort-Object -Property $script:SiraKolon -Descending:$script:SiraTers)
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($p in $goster) {
        $it = New-Object Windows.Forms.ListViewItem($p.Ad)
        [void]$it.SubItems.Add($p.Yayinci)
        [void]$it.SubItems.Add($p.Surum)
        [void]$it.SubItems.Add($(if ($p.BoyutMB) { '{0:N1} MB' -f $p.BoyutMB } else { '' }))
        [void]$it.SubItems.Add($(if ($p.Tarih) { $p.Tarih.ToString('dd.MM.yyyy') } else { '' }))
        [void]$it.SubItems.Add($p.Tur)
        $it.Tag = $p
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate()
    Durum "$($goster.Count) program"
}

function Programlari-Yenile {
    $form.Cursor = 'WaitCursor'
    Durum 'Programlar okunuyor…'
    $script:Programlar = @(Programlari-Getir)
    $form.Cursor = 'Default'
    Listeyi-Doldur
}

function Bekle([scriptblock]$kosul) {
    while (& $kosul) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 300
    }
}

# 'tamam' | 'hala' (hala kurulu gorunuyor) | 'yok' (kaldirici bulunamadi) | 'iptal'
function Kaldiriciyi-Calistir($prog) {
    $komut = if ($prog.Kaldirma) { $prog.Kaldirma } else { $prog.SessizKaldirma }
    $parca = Komutu-Ayir $komut
    $exe = [Environment]::ExpandEnvironmentVariables($parca[0])
    $arg = $parca[1]
    if ($exe -match '(?i)(^|\\)msiexec(\.exe)?$') {
        $guid = [regex]::Match($komut, '\{[0-9A-Fa-f-]{36}\}').Value
        if ($guid) { $arg = "/X$guid" }
        $exe = 'msiexec.exe'
    }
    $var = (Test-Path -LiteralPath $exe) -or [bool](Get-Command $exe -ErrorAction SilentlyContinue)
    if (-not $var) {
        $c = Sor "Bu programın kaldırıcısı bulunamadı (program zaten silinmiş olabilir):`n$exe`n`nGeride kalanları tarayayım mı?"
        if ($c -eq 'Yes') { return 'yok' } else { return 'iptal' }
    }
    Durum "Kaldırıcı çalışıyor: $($prog.Ad) — bitmesini bekliyorum…"
    $basla = Get-Date
    try {
        if ($arg) { $proc = Start-Process -FilePath $exe -ArgumentList $arg -PassThru -ErrorAction Stop }
        else { $proc = Start-Process -FilePath $exe -PassThru -ErrorAction Stop }
    } catch {
        Bilgi "Kaldırıcı başlatılamadı:`n$($_.Exception.Message)" 'Error'
        return 'iptal'
    }
    Bekle { -not $proc.HasExited }
    # Bircok kaldirici (NSIS, Inno) kendini Temp'e kopyalayip oradan devam eder: onlari da bekle
    $temp = [IO.Path]::GetTempPath().TrimEnd('\')
    Bekle {
        [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object {
            try { $_.StartTime -ge $basla -and $_.Path -and $_.Path.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) } catch { $false } })
    }
    $kayitli = { $prog.AnahtarYolu -and (Test-Path -LiteralPath "Registry::$($prog.AnahtarYolu)") }
    if (& $kayitli) {
        $c = Sor "$($prog.Ad) hâlâ kurulu görünüyor.`n`n• Kaldırıcı penceresi hâlâ açıksa işini bitir, sonra EVET'e bas.`n• Kaldırmayı iptal ettiysen HAYIR'a bas."
        if ($c -ne 'Yes') { return 'iptal' }
        if (& $kayitli) { return 'hala' }
    }
    return 'tamam'
}

function Artiklari-Goster($prog, [bool]$hala) {
    $form.Cursor = 'WaitCursor'
    Durum "Geride kalanlar taranıyor: $($prog.Ad)…"
    $adaylar = @(Artiklari-Tara $prog)
    $form.Cursor = 'Default'
    Durum ''
    if ($adaylar.Count -eq 0) { Bilgi "Geride hiçbir şey kalmamış. $($prog.Ad) tertemiz gitti."; return }

    $f2 = New-Object Windows.Forms.Form
    $f2.Text = "Geride kalanlar — $($prog.Ad)"
    $f2.Size = New-Object Drawing.Size(1200, 640)
    $f2.StartPosition = 'CenterParent'
    $f2.Font = $yazi
    $f2.Icon = $form.Icon

    $bilgiEt = New-Object Windows.Forms.Label
    $bilgiEt.Dock = 'Top'; $bilgiEt.Height = 70; $bilgiEt.Padding = '8,8,8,0'
    $metin = "İşaretli olanlar silinecek. KESİN olanlar bu programa ait. MUHTEMEL olanlara bir bak — emin değilsen işaretleme.`n" +
             "Klasör ve kısayollar Geri Dönüşüm Kutusu'na gider; kayıt defteri, görev ve servisler silinmeden önce yedeklenir."
    if ($hala) { $metin = "⚠ Program hâlâ kurulu görünüyor, bu yüzden hiçbir şey otomatik işaretlenmedi.`n" + $metin; $bilgiEt.ForeColor = $turuncu }
    $bilgiEt.Text = $metin

    $lv2 = New-Object Windows.Forms.ListView
    $lv2.Dock = 'Fill'; $lv2.View = 'Details'; $lv2.CheckBoxes = $true; $lv2.FullRowSelect = $true; $lv2.MultiSelect = $false
    foreach ($kol in @(@('Güven', 95), @('Tür', 140), @('Konum', 620), @('Neden', 380))) { [void]$lv2.Columns.Add($kol[0], $kol[1]) }
    foreach ($a in $adaylar) {
        $it = New-Object Windows.Forms.ListViewItem($(if ($a.Kesin) { 'Kesin' } else { 'Muhtemel' }))
        [void]$it.SubItems.Add($a.Tur)
        [void]$it.SubItems.Add($a.Yol)
        [void]$it.SubItems.Add($a.Neden)
        $it.Checked = [bool]($a.Kesin -and -not $hala)
        if (-not $a.Kesin) { $it.ForeColor = $turuncu }
        $it.Tag = $a
        [void]$lv2.Items.Add($it)
    }

    $alt2 = New-Object Windows.Forms.FlowLayoutPanel
    $alt2.Dock = 'Bottom'; $alt2.AutoSize = $true; $alt2.Padding = '8,4,8,8'; $alt2.WrapContents = $false
    $btnSil = New-Object Windows.Forms.Button; $btnSil.Text = 'İşaretlileri sil'; $btnSil.Font = $kalin; $btnSil.AutoSize = $true; $btnSil.Padding = '10,4,10,4'
    $btnKesin = New-Object Windows.Forms.Button; $btnKesin.Text = 'Sadece kesinleri işaretle'; $btnKesin.AutoSize = $true
    $btnHepsi = New-Object Windows.Forms.Button; $btnHepsi.Text = 'Hepsini işaretle'; $btnHepsi.AutoSize = $true
    $btnHic = New-Object Windows.Forms.Button; $btnHic.Text = 'Hiçbirini'; $btnHic.AutoSize = $true
    $btnAc = New-Object Windows.Forms.Button; $btnAc.Text = 'Seçilenin yerini aç'; $btnAc.AutoSize = $true
    $btnKapat = New-Object Windows.Forms.Button; $btnKapat.Text = 'Kapat'; $btnKapat.AutoSize = $true
    $alt2.Controls.AddRange(@($btnSil, $btnKesin, $btnHepsi, $btnHic, $btnAc, $btnKapat))

    $f2.Controls.AddRange(@($lv2, $bilgiEt, $alt2))
    $lv2.BringToFront()

    $btnKesin.add_Click({ foreach ($it in $lv2.Items) { $it.Checked = [bool]$it.Tag.Kesin } })
    $btnHepsi.add_Click({ foreach ($it in $lv2.Items) { $it.Checked = $true } })
    $btnHic.add_Click({ foreach ($it in $lv2.Items) { $it.Checked = $false } })
    $btnKapat.add_Click({ $f2.Close() })
    $btnAc.add_Click({
        if ($lv2.SelectedItems.Count -eq 0) { return }
        $a = $lv2.SelectedItems[0].Tag
        switch ($a.Tur) {
            'Klasör' { if (Test-Path -LiteralPath $a.Yol) { Start-Process explorer.exe "`"$($a.Yol)`"" } }
            'Kısayol' { Start-Process explorer.exe "/select,`"$($a.Yol)`"" }
            { $_ -eq 'Kayıt defteri' -or $_ -eq 'Başlangıç kaydı' } {
                $hedef = if ($a.Tur -eq 'Kayıt defteri') { $a.Yol } else { $a.Ek.Anahtar }
                $rk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit'
                if (-not (Test-Path $rk)) { New-Item -Path $rk -Force | Out-Null }
                Set-ItemProperty -Path $rk -Name LastKey -Value "Computer\$hedef"
                Start-Process regedit.exe
            }
            'Zamanlanmış görev' { Start-Process taskschd.msc }
            'Servis' { Start-Process services.msc }
        }
    })
    $btnSil.add_Click({
        $secili = @($lv2.CheckedItems | ForEach-Object { $_.Tag })
        if ($secili.Count -eq 0) { [void][Windows.Forms.MessageBox]::Show($f2, 'Hiçbir şey işaretli değil.', $UygulamaAdi); return }
        $c = [Windows.Forms.MessageBox]::Show($f2, "$($secili.Count) öğe silinsin mi?", $UygulamaAdi, 'YesNo', 'Question')
        if ($c -ne 'Yes') { return }
        $f2.Cursor = 'WaitCursor'
        $sonuc = Artiklari-Sil $prog $secili
        $f2.Cursor = 'Default'
        $mesaj = "$($sonuc.Basarili) öğe silindi.`n`nKlasörler Geri Dönüşüm Kutusu'nda. Kayıt defteri yedekleri ve günlük:`n$($sonuc.Klasor)"
        if ($sonuc.Hatalar.Count -gt 0) {
            $ilk = ($sonuc.Hatalar | Select-Object -First 8) -join "`n• "
            $mesaj += "`n`nSilinemeyenler ($($sonuc.Hatalar.Count)):`n• $ilk`n`nProgram hâlâ açıksa kapat ya da bilgisayarı yeniden başlat, sonra 'Daha önce sildiğim bir programın artıklarını ara' ile tekrar tara."
        }
        [void][Windows.Forms.MessageBox]::Show($f2, $mesaj, $UygulamaAdi, 'OK', $(if ($sonuc.Hatalar.Count) { 'Warning' } else { 'Information' }))
        $f2.Close()
    })

    [void]$f2.ShowDialog($form)
    $f2.Dispose()
}

function Secili-Program {
    if ($lv.SelectedItems.Count -eq 0) { Bilgi 'Önce listeden bir program seç.'; return $null }
    return $lv.SelectedItems[0].Tag
}

function Kaldir-Secili {
    $prog = Secili-Program
    if (-not $prog) { return }
    $c = Sor "$($prog.Ad) kaldırılsın mı?`n`nÖnce programın kendi kaldırıcısı açılacak. Bitince geride kalanları tarayıp sana göstereceğim."
    if ($c -ne 'Yes') { return }
    $form.Enabled = $false
    try {
        $hala = $false
        if ($prog.Tur -eq 'Store') {
            Durum "Kaldırılıyor: $($prog.Ad)…"
            try { Remove-AppxPackage -Package $prog.Paket -ErrorAction Stop }
            catch { Bilgi "Kaldırılamadı:`n$($_.Exception.Message)" 'Error'; return }
        } else {
            $r = Kaldiriciyi-Calistir $prog
            if ($r -eq 'iptal') { return }
            $hala = ($r -eq 'hala')
        }
        $form.Enabled = $true
        Artiklari-Goster $prog $hala
    } finally {
        $form.Enabled = $true
        Programlari-Yenile
    }
}

$btnKaldir.add_Click({ Kaldir-Secili })
$miKaldir.add_Click({ Kaldir-Secili })
$lv.add_DoubleClick({ Kaldir-Secili })
$miTara.add_Click({ $prog = Secili-Program; if ($prog) { Artiklari-Goster $prog $true } })
$miKlasor.add_Click({
    $prog = Secili-Program
    if (-not $prog) { return }
    $d = Konum-Adaylari $prog | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($d) { Start-Process explorer.exe "`"$d`"" } else { Bilgi 'Kurulum klasörü bulunamadı.' }
})
$btnYenile.add_Click({ Programlari-Yenile })
$arama.add_TextChanged({ Listeyi-Doldur })
$lv.add_ColumnClick({
    param($kaynak, $olay)
    $kol = $Kolonlar[$olay.Column]
    if ($script:SiraKolon -eq $kol) { $script:SiraTers = -not $script:SiraTers } else { $script:SiraKolon = $kol; $script:SiraTers = $false }
    Listeyi-Doldur
})
$btnIsimle.add_Click({
    $ad = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Daha önce sildiğin bir programın adını yaz (ör. Steam, Spotify, Epic Games).`nGeride kalanlarını arayacağım.",
        'Artık ara', '')
    $ad = "$ad".Trim()
    if ($ad.Length -lt 3) { return }
    $kurulu = $script:Programlar | Where-Object { $_.Ad.IndexOf($ad, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1
    if ($kurulu) {
        Bilgi "Uyarı: '$($kurulu.Ad)' hâlâ kurulu görünüyor. Hiçbir şey otomatik işaretlenmeyecek." 'Warning'
        Artiklari-Goster (Yeni-Program -Ad $ad) $true
    } else {
        Artiklari-Goster (Yeni-Program -Ad $ad) $false
    }
})
$form.add_Shown({ Programlari-Yenile })

[void]$form.ShowDialog()
