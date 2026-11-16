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
# Arayuz Turkce ve Ingilizce (sag ustteki dugme).
#
# Deneme (pencere acmadan, hicbir sey silmeden):  .\Kaldir.ps1 -Deneme -DenemeAd "Steam"
# Demo (sahte verilerle, hicbir sey silmez):       .\Kaldir.ps1 -Demo -Dil en

param(
    [switch]$Deneme,
    [string]$DenemeAd,
    [switch]$Demo,
    [ValidateSet('', 'tr', 'en')][string]$Dil = '',
    [string]$EkranGoruntusu
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- yonetici
if (-not $Deneme -and -not $Demo) {
    $kimlik = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $kimlik.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
        } catch { }
        exit
    }
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace HomemadeUninstaller {
    public static class Yerel {
        [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
        static extern int SHLoadIndirectString(string src, StringBuilder buf, int cch, IntPtr reserved);
        public static string Coz(string src) {
            var sb = new StringBuilder(1024);
            return SHLoadIndirectString(src, sb, sb.Capacity, IntPtr.Zero) == 0 ? sb.ToString() : null;
        }
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
        public static int[] Cerceve(IntPtr h) {
            RECT r;
            if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) return null;
            return new int[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top };
        }
        public static void KoseleriDuzYap(IntPtr h) { int v = 1; DwmSetWindowAttribute(h, 33, ref v, 4); }
    }
}
'@

$UygulamaKlasoru = (Split-Path -Parent $PSCommandPath).TrimEnd('\')
$YedekKoku = Join-Path $UygulamaKlasoru 'yedek'
$AyarDosyasi = Join-Path $UygulamaKlasoru 'ayarlar.json'
$UygulamaAdi = 'Homemade Uninstaller'
$IkonYolu = Join-Path $UygulamaKlasoru 'homemade.ico'

# ---------------------------------------------------------------- dil
$Metinler = @{
    tr = @{
        'baslik'            = "{0} — programı ve geride kalanlarını sil"
        'ara'               = "Ara:"
        'yenile'            = "Yenile"
        'isimle'            = "Daha önce sildiğim bir programın artıklarını ara…"
        'dilDugme'          = "English"
        'kol.ad'            = "Program"
        'kol.yayinci'       = "Yayıncı"
        'kol.surum'         = "Sürüm"
        'kol.boyut'         = "Boyut"
        'kol.tarih'         = "Kurulum"
        'kol.tur'           = "Tür"
        'kaldirDugme'       = "Seçileni kaldır"
        'menu.kaldir'       = "Kaldır"
        'menu.tara'         = "Kaldırmadan sadece artıkları tara (kaldırıcısı bozuksa)"
        'menu.klasor'       = "Kurulum klasörünü aç"
        'durum.sayi'        = "{0} program"
        'durum.okunuyor'    = "Programlar okunuyor…"
        'durum.kaldiriliyor'= "Kaldırılıyor: {0}…"
        'durum.bekliyor'    = "Kaldırıcı çalışıyor: {0} — bitmesini bekliyorum…"
        'durum.taraniyor'   = "Geride kalanlar taranıyor: {0}…"
        'durum.demo'        = "DEMO — örnek veriler, hiçbir şey silinmez"
        'msg.sec'           = "Önce listeden bir program seç."
        'msg.onay'          = "{0} kaldırılsın mı?`n`nÖnce programın kendi kaldırıcısı açılacak. Bitince geride kalanları tarayıp sana göstereceğim."
        'msg.kaldiriciYok'  = "Bu programın kaldırıcısı bulunamadı (program zaten silinmiş olabilir):`n{0}`n`nGeride kalanları tarayayım mı?"
        'msg.baslatilamadi' = "Kaldırıcı başlatılamadı:`n{0}"
        'msg.hala'          = "{0} hâlâ kurulu görünüyor.`n`n• Kaldırıcı penceresi hâlâ açıksa işini bitir, sonra EVET'e bas.`n• Kaldırmayı iptal ettiysen HAYIR'a bas."
        'msg.storeHata'     = "Kaldırılamadı:`n{0}"
        'msg.temiz'         = "Geride hiçbir şey kalmamış. {0} tertemiz gitti."
        'msg.klasorYok'     = "Kurulum klasörü bulunamadı."
        'isim.baslik'       = "Artık ara"
        'isim.metin'        = "Daha önce sildiğin bir programın adını yaz (ör. Steam, Spotify, Epic Games).`nGeride kalanlarını arayacağım."
        'isim.kurulu'       = "Uyarı: '{0}' hâlâ kurulu görünüyor. Hiçbir şey otomatik işaretlenmeyecek."
        'art.baslik'        = "Geride kalanlar — {0}"
        'art.bilgi'         = "İşaretli olanlar silinecek. KESİN olanlar bu programa ait. MUHTEMEL olanlara bir bak — emin değilsen işaretleme.`nKlasör ve kısayollar Geri Dönüşüm Kutusu'na gider; kayıt defteri, görev ve servisler silinmeden önce yedeklenir."
        'art.hala'          = "⚠ Program hâlâ kurulu görünüyor, bu yüzden hiçbir şey otomatik işaretlenmedi."
        'art.kol.guven'     = "Güven"
        'art.kol.tur'       = "Tür"
        'art.kol.konum'     = "Konum"
        'art.kol.neden'     = "Neden"
        'guven.kesin'       = "Kesin"
        'guven.muhtemel'    = "Muhtemel"
        'art.sil'           = "İşaretlileri sil"
        'art.kesinler'      = "Sadece kesinleri işaretle"
        'art.hepsi'         = "Hepsini işaretle"
        'art.hic'           = "Hiçbirini"
        'art.ac'            = "Seçilenin yerini aç"
        'art.kapat'         = "Kapat"
        'art.bos'           = "Hiçbir şey işaretli değil."
        'art.onay'          = "{0} öğe silinsin mi?"
        'art.sonuc'         = "{0} öğe silindi.`n`nKlasörler Geri Dönüşüm Kutusu'nda. Kayıt defteri yedekleri ve günlük:`n{1}"
        'art.hatalar'       = "`n`nSilinemeyenler ({0}):`n• {1}`n`nProgram hâlâ açıksa kapat ya da bilgisayarı yeniden başlat, sonra tekrar tara."
        'demo.sil'          = "Demo modu: hiçbir şey silinmedi."
        'tur.Masaüstü'      = "Masaüstü"
        'tur.Store'         = "Store"
        'tur.Klasör'        = "Klasör"
        'tur.Kısayol'       = "Kısayol"
        'tur.Kayıt defteri' = "Kayıt defteri"
        'tur.Başlangıç kaydı' = "Başlangıç kaydı"
        'tur.Zamanlanmış görev' = "Zamanlanmış görev"
        'tur.Servis'        = "Servis"
        'kaynak.ad'         = "program adı"
        'kaynak.kayit'      = "kaldırma kaydı adı"
        'kaynak.exe'        = "program dosyası adı"
        'kaynak.paket'      = "Store paket adı"
        'kaynak.kelime'     = "addaki bir kelime"
        'neden.onek'        = "{0} ile başlıyor"
        'neden.ad'          = "Adı eşleşiyor ({0})"
        'neden.yayinciIci'  = "Yayıncı klasöründe, adı eşleşiyor ({0})"
        'neden.yayinci'     = "Yayıncı klasörü ({0}); içinde bu programdan başka bir şey yok"
        'neden.kurulum'     = "Programın kurulum klasörü"
        'neden.storeVeri'   = "Store uygulamasının veri klasörü"
        'neden.kaldirmaKaydi' = "Programlar listesindeki kaldırma kaydı"
        'neden.acilis'      = "Açılışta çalışıyor: {0}"
        'neden.acilisYok'   = "Adı eşleşiyor, çalıştırdığı dosya artık yok: {0}"
        'neden.adHedef'     = "Adı eşleşiyor: {0}"
        'neden.gorev'       = "Çalıştırdığı: {0}"
        'neden.gorevAd'     = "Görev adında '{0}' geçiyor: {1}"
        'neden.servisAd'    = "Adı eşleşiyor: {0}"
        'neden.kisayol'     = "Kurulum klasörüne gidiyor: {0}"
        'neden.kisayolYok'  = "Adı eşleşiyor, gittiği dosya artık yok: {0}"
        'hata.korunan'      = "Korunan bir konum, silinmedi."
        'hata.yedek'        = "Yedek alınamadı, bu yüzden silinmedi."
        'hata.sc'           = "sc delete başarısız (kod {0})"
    }
    en = @{
        'baslik'            = "{0} — remove a program and everything it leaves behind"
        'ara'               = "Search:"
        'yenile'            = "Refresh"
        'isimle'            = "Find leftovers of an app I already removed…"
        'dilDugme'          = "Türkçe"
        'kol.ad'            = "Program"
        'kol.yayinci'       = "Publisher"
        'kol.surum'         = "Version"
        'kol.boyut'         = "Size"
        'kol.tarih'         = "Installed"
        'kol.tur'           = "Type"
        'kaldirDugme'       = "Uninstall selected"
        'menu.kaldir'       = "Uninstall"
        'menu.tara'         = "Scan for leftovers only (if its uninstaller is broken)"
        'menu.klasor'       = "Open install folder"
        'durum.sayi'        = "{0} programs"
        'durum.okunuyor'    = "Reading installed programs…"
        'durum.kaldiriliyor'= "Uninstalling {0}…"
        'durum.bekliyor'    = "Uninstaller running for {0} — waiting for it to finish…"
        'durum.taraniyor'   = "Scanning for leftovers of {0}…"
        'durum.demo'        = "DEMO — sample data, nothing is removed"
        'msg.sec'           = "Select a program from the list first."
        'msg.onay'          = "Uninstall {0}?`n`nThe program's own uninstaller will open first. When it finishes, I'll scan for leftovers and show you what I find."
        'msg.kaldiriciYok'  = "This program's uninstaller wasn't found (it may already be removed):`n{0}`n`nScan for leftovers?"
        'msg.baslatilamadi' = "Couldn't start the uninstaller:`n{0}"
        'msg.hala'          = "{0} still appears to be installed.`n`n• If the uninstaller window is still open, finish it, then click YES.`n• If you cancelled the uninstall, click NO."
        'msg.storeHata'     = "Couldn't uninstall:`n{0}"
        'msg.temiz'         = "Nothing left behind. {0} is completely gone."
        'msg.klasorYok'     = "Install folder not found."
        'isim.baslik'       = "Find leftovers"
        'isim.metin'        = "Type the name of an app you've already removed (e.g. Steam, Spotify, Epic Games).`nI'll look for anything it left behind."
        'isim.kurulu'       = "Note: '{0}' still appears to be installed. Nothing will be pre-checked."
        'art.baslik'        = "Leftovers — {0}"
        'art.bilgi'         = "Checked items will be removed. CERTAIN items belong to this program. Take a look at POSSIBLE ones and leave them unchecked if you're not sure.`nFolders and shortcuts go to the Recycle Bin; registry keys, tasks and services are backed up before removal."
        'art.hala'          = "⚠ The program still appears to be installed, so nothing was pre-checked."
        'art.kol.guven'     = "Confidence"
        'art.kol.tur'       = "Type"
        'art.kol.konum'     = "Location"
        'art.kol.neden'     = "Reason"
        'guven.kesin'       = "Certain"
        'guven.muhtemel'    = "Possible"
        'art.sil'           = "Remove checked"
        'art.kesinler'      = "Check certain only"
        'art.hepsi'         = "Check all"
        'art.hic'           = "Check none"
        'art.ac'            = "Open location"
        'art.kapat'         = "Close"
        'art.bos'           = "Nothing is checked."
        'art.onay'          = "Remove {0} items?"
        'art.sonuc'         = "{0} items removed.`n`nFolders are in the Recycle Bin. Registry backups and log:`n{1}"
        'art.hatalar'       = "`n`nCouldn't remove ({0}):`n• {1}`n`nIf the program is still running, close it or restart your PC, then scan again."
        'demo.sil'          = "Demo mode: nothing was removed."
        'tur.Masaüstü'      = "Desktop"
        'tur.Store'         = "Store"
        'tur.Klasör'        = "Folder"
        'tur.Kısayol'       = "Shortcut"
        'tur.Kayıt defteri' = "Registry key"
        'tur.Başlangıç kaydı' = "Startup entry"
        'tur.Zamanlanmış görev' = "Scheduled task"
        'tur.Servis'        = "Service"
        'kaynak.ad'         = "program name"
        'kaynak.kayit'      = "uninstall entry name"
        'kaynak.exe'        = "executable name"
        'kaynak.paket'      = "Store package name"
        'kaynak.kelime'     = "a word in the name"
        'neden.onek'        = "starts with {0}"
        'neden.ad'          = "Name matches ({0})"
        'neden.yayinciIci'  = "In the publisher folder, name matches ({0})"
        'neden.yayinci'     = "Publisher folder ({0}); nothing else inside"
        'neden.kurulum'     = "The program's install folder"
        'neden.storeVeri'   = "The Store app's data folder"
        'neden.kaldirmaKaydi' = "Its entry in the installed programs list"
        'neden.acilis'      = "Runs at startup: {0}"
        'neden.acilisYok'   = "Name matches, its target no longer exists: {0}"
        'neden.adHedef'     = "Name matches: {0}"
        'neden.gorev'       = "Runs: {0}"
        'neden.gorevAd'     = "Task name contains '{0}': {1}"
        'neden.servisAd'    = "Name matches: {0}"
        'neden.kisayol'     = "Points into the install folder: {0}"
        'neden.kisayolYok'  = "Name matches, its target no longer exists: {0}"
        'hata.korunan'      = "Protected location, not removed."
        'hata.yedek'        = "Backup failed, so it wasn't removed."
        'hata.sc'           = "sc delete failed (code {0})"
    }
}

function T([string]$anahtar) {
    $v = $Metinler[$script:Dil][$anahtar]
    if ($null -eq $v) { $v = $Metinler['tr'][$anahtar] }
    if ($null -eq $v) { return $anahtar }
    return $v
}

function Ayar-Oku {
    try { return (Get-Content -LiteralPath $AyarDosyasi -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { return $null }
}
function Ayar-Yaz {
    if ($Demo) { return }   # demo, kullanicinin secimini degistirmesin
    try { @{ Dil = $script:Dil } | ConvertTo-Json | Set-Content -LiteralPath $AyarDosyasi -Encoding UTF8 } catch { }
}

if ($Dil) { $script:Dil = $Dil }
else {
    $kayitli = Ayar-Oku
    if ($kayitli -and ($kayitli.Dil -eq 'tr' -or $kayitli.Dil -eq 'en')) { $script:Dil = $kayitli.Dil }
    elseif ((Get-Culture).TwoLetterISOLanguageName -eq 'tr' -or (Get-UICulture).TwoLetterISOLanguageName -eq 'tr') { $script:Dil = 'tr' }
    else { $script:Dil = 'en' }
}

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
  'DefaultUserEnvironment','Partner','Setup','Windows','AppDataLow','Software','System',
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

# "ms-resource:AppName" gibi Store metinlerini gercek (yerellestirilmis) metne cevir
function Paket-Metni($pk, [string]$deger) {
    if (-not $deger) { return '' }
    if ($deger -notlike 'ms-resource:*') { return $deger }
    $kalan = $deger.Substring(12)
    $denenecek = @()
    if ($kalan.StartsWith('//')) { $denenecek += "ms-resource:$kalan" }
    elseif ($kalan.StartsWith('/')) { $denenecek += "ms-resource://$($pk.Name)$kalan" }
    else { $denenecek += "ms-resource://$($pk.Name)/Resources/$kalan"; $denenecek += "ms-resource://$($pk.Name)/$kalan" }
    foreach ($kaynak in $denenecek) {
        $s = [HomemadeUninstaller.Yerel]::Coz('@{' + $pk.PackageFullName + '?' + $kaynak + '}')
        if ($s -and $s -notlike 'ms-resource:*') { return $s }
    }
    return ''
}

# "CN=\"Anthropic, PBC\", O=..." -> "Anthropic, PBC"
function Sertifika-Adi([string]$s) {
    if ($s -match 'CN=(?:"([^"]+)"|([^,]+))') {
        $ad = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
        if ($ad -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}$') { return '' }   # GUID, okunur bir ad degil
        return $ad.Trim()
    }
    return ''
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
            $liste.Add((Yeni-Program -Ad $ad -Yayinci "$($an.GetValue('Publisher'))".Trim(' ', '"') -Surum $surum -BoyutMB $mb `
                -Tarih $tarih -Kaldirma $kaldirma -SessizKaldirma $sessiz `
                -Konum ("$($an.GetValue('InstallLocation'))".Trim('"', ' ').TrimEnd('\')) `
                -Ikon "$($an.GetValue('DisplayIcon'))".Trim() -AnahtarYolu $an.Name -AnahtarAdi $an.PSChildName))
        }
    }
    try {
        $paketler = @(Get-AppxPackage -ErrorAction Stop | Where-Object {
            -not $_.IsFramework -and -not $_.IsResourcePackage -and -not $_.NonRemovable -and
            ($_.SignatureKind -eq 'Store' -or $_.SignatureKind -eq 'Developer') })
        # ayni uygulamanin birden fazla surumu kayitliysa sadece en yenisi
        $enYeni = @{}
        foreach ($pk in $paketler) {
            $onceki = $enYeni[$pk.PackageFamilyName]
            if (-not $onceki -or [version]$pk.Version -gt [version]$onceki.Version) { $enYeni[$pk.PackageFamilyName] = $pk }
        }
        foreach ($pk in $enYeni.Values) {
            $gorunen = ''; $yayinci = ''
            try {
                $man = Get-AppxPackageManifest -Package $pk.PackageFullName
                $gorunen = Paket-Metni $pk "$($man.Package.Properties.DisplayName)"
                $yayinci = Paket-Metni $pk "$($man.Package.Properties.PublisherDisplayName)"
            } catch { }
            if (-not $gorunen) { $gorunen = $pk.Name -replace '^[^.]*\.', '' }
            if (-not $yayinci) { $yayinci = Sertifika-Adi $pk.Publisher }
            $liste.Add((Yeni-Program -Tur 'Store' -Ad $gorunen.Trim() -Yayinci $yayinci.Trim() -Surum "$($pk.Version)" `
                -Paket $pk.PackageFullName -PaketAile $pk.PackageFamilyName -PaketAdi $pk.Name))
        }
    } catch { }
    return $liste
}

# ---------------------------------------------------------------- anahtar kelimeler
# Kaynak kodlari: ad, kayit, exe, paket, kelime
function Anahtar-Kelimeler($prog) {
    $sozluk = [ordered]@{}
    $ekleK = {
        param([string]$metin, [bool]$kesin, [string]$kaynak)
        $n = Duzlestir $metin
        if ($n.Length -lt 3 -or $Genel.Contains($n) -or $n -match '^\d+$') { return }
        if ($sozluk.Contains($n)) {
            if ($kesin -and -not $sozluk[$n].Kesin) { $sozluk[$n] = [pscustomobject]@{ K = $n; Kesin = $true; Kaynak = $kaynak; Onek = $false } }
            return
        }
        $sozluk[$n] = [pscustomobject]@{ K = $n; Kesin = $kesin; Kaynak = $kaynak; Onek = $false }
    }

    $temiz = Adi-Temizle $prog.Ad
    & $ekleK $temiz $true 'ad'

    # "Mozilla Firefox" -> "Firefox" (bastaki yayinci adini at)
    $yayinciKelimeleri = @((Yayinci-Temizle $prog.Yayinci) -split '\s+' | Where-Object { $_ })
    $kelimeler = @($temiz -split '[\s\-_.]+' | Where-Object { $_ })
    $kisa = $kelimeler
    while ($kisa.Count -gt 1 -and ($yayinciKelimeleri -contains $kisa[0])) { $kisa = @($kisa[1..($kisa.Count - 1)]) }
    if ($kisa.Count -lt $kelimeler.Count) { & $ekleK ($kisa -join ' ') $true 'ad' }

    # tek tek kelimeler: sadece "muhtemel"
    foreach ($w in $kelimeler) {
        if ($w.Length -ge 4 -and $yayinciKelimeleri -notcontains $w) { & $ekleK $w $false 'kelime' }
    }

    # kaldirma kaydinin adi (GUID degilse): "Steam", "Discord", "Foo_is1"
    if ($prog.AnahtarAdi) {
        $an = $prog.AnahtarAdi -replace '_is1$', ''
        if ($an -notmatch '^\{.*\}$') { & $ekleK (Adi-Temizle $an) $true 'kayit' }
    }

    # programin kendi exe'sinin adi (ikonundan): "Code", "Chrome" -> muhtemel
    if ($prog.Ikon) {
        $exe = (Komutu-Ayir ($prog.Ikon -replace ',\s*-?\d+\s*$', ''))[0]
        $b = [IO.Path]::GetFileNameWithoutExtension($exe)
        if ($b -and $b -notmatch '^(?i)(unins\d*|uninst(all)?|uninstaller|setup|install(er)?|update|helper|launcher|app|icon|main|msiexec|rundll32|shell32|imageres)$') {
            $n = Duzlestir $b
            if ($n.Length -ge 3 -and $n -notmatch '^\d+$' -and -not $sozluk.Contains($n)) {
                $sozluk[$n] = [pscustomobject]@{ K = $n; Kesin = $false; Kaynak = 'exe'; Onek = $false }
            }
        }
    }

    if ($prog.PaketAdi) { & $ekleK ($prog.PaketAdi -replace '^[^.]*\.', '') $true 'paket' }

    return @($sozluk.Values | Sort-Object { -not $_.Kesin })
}

function Eslesme([string]$ad, $anahtarlar) {
    $n = Duzlestir $ad
    if ($n.Length -lt 3) { return $null }
    foreach ($a in $anahtarlar) { if ($n -eq $a.K) { return $a } }
    foreach ($a in $anahtarlar) {
        if ($a.Kesin -and $a.K.Length -ge 5 -and $n.StartsWith($a.K)) {
            return [pscustomobject]@{ K = $a.K; Kesin = $false; Kaynak = $a.Kaynak; Onek = $true }
        }
    }
    return $null
}

function Kaynak-Metni($m) {
    $s = T "kaynak.$($m.Kaynak)"
    if ($m.Onek) { $s = (T 'neden.onek') -f $s }
    return $s
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
            Aday-Ekle $c.Tur $c.Yol ((T 'neden.ad') -f (Kaynak-Metni $m)) ([bool]($m.Kesin -and -not $hepsiMuhtemel))
            continue
        }
        if ($yayinciK -and (Duzlestir $c.Ad) -eq $yayinciK) {
            $alt = @(Cocuklar $c.Yol $mod)
            $esl = 0
            foreach ($a in $alt) {
                $m2 = Eslesme $a.Ad $anahtarlar
                if ($m2) {
                    Aday-Ekle $a.Tur $a.Yol ((T 'neden.yayinciIci') -f (Kaynak-Metni $m2)) ([bool]($m2.Kesin -and -not $hepsiMuhtemel))
                    $esl++
                }
            }
            if (-not $Genel.Contains($yayinciK) -and ($alt.Count -eq 0 -or $esl -eq $alt.Count)) {
                Aday-Ekle $c.Tur $c.Yol ((T 'neden.yayinci') -f $c.Ad) $false
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
    $adAnahtarlari = @($anahtarlar | Where-Object { $_.Kaynak -ne 'exe' })
    $kesinKonumlar = New-Object System.Collections.Generic.List[string]
    foreach ($d in (Konum-Adaylari $prog)) {
        if (Korumali $d) { continue }
        $lm = Eslesme (Split-Path -Leaf $d) $adAnahtarlari
        $kesin = [bool]($lm -and $lm.Kesin)
        if ($kesin -and -not (Baska-Programin $d)) { $kesinKonumlar.Add($d) }
        if (Test-Path -LiteralPath $d) { Aday-Ekle 'Klasör' $d (T 'neden.kurulum') $kesin }
    }
    if ($prog.Tur -eq 'Store' -and $prog.PaketAile) {
        $pd = Join-Path $env:LOCALAPPDATA "Packages\$($prog.PaketAile)"
        if (Test-Path -LiteralPath $pd) { Aday-Ekle 'Klasör' $pd (T 'neden.storeVeri') $true }
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
        Aday-Ekle 'Kayıt defteri' $prog.AnahtarYolu (T 'neden.kaldirmaKaydi') $true
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
            if (Konumda $vd $kesinKonumlar) { Aday-Ekle 'Başlangıç kaydı' "$rk\$vn" ((T 'neden.acilis') -f $vd) $true $ek; continue }
            $m = Eslesme $vn $anahtarlar
            if ($m) {
                $yok = -not (Exe-Var-Mi $vd)
                $neden = if ($yok) { (T 'neden.acilisYok') -f $vd } else { (T 'neden.adHedef') -f $vd }
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
            if (Konumda $eylem $kesinKonumlar) { Aday-Ekle 'Zamanlanmış görev' $tam ((T 'neden.gorev') -f $eylem) $true $ek; continue }
            $n = Duzlestir $g.TaskName
            $m = $anahtarlar | Where-Object { $_.Kesin -and $_.K.Length -ge 5 -and $n.Contains($_.K) } | Select-Object -First 1
            if ($m) { Aday-Ekle 'Zamanlanmış görev' $tam ((T 'neden.gorevAd') -f $m.K, $eylem) $false $ek }
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
            if ($m) { Aday-Ekle 'Servis' $sv.Name ((T 'neden.servisAd') -f "$($sv.DisplayName) — $pn") $false $ek }
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
            if ($hedef -and (Konumda $hedef $kesinKonumlar)) { Aday-Ekle 'Kısayol' $l.FullName ((T 'neden.kisayol') -f $hedef) $true; continue }
            $m = Eslesme $l.BaseName $anahtarlar
            if ($m) {
                $neden = if ($hedefYok) { (T 'neden.kisayolYok') -f $hedef } else { (T 'neden.adHedef') -f $hedef }
                Aday-Ekle 'Kısayol' $l.FullName $neden ([bool]($m.Kesin -and ($hedefYok -or -not $hedef)))
            }
        }
    }
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)

    return @(Adaylari-Sirala $script:Adaylar)
}

# ic ice olanlari sadele (ust klasor "kesin" ise icindekileri ayrica gosterme) ve sirala
function Adaylari-Sirala($liste) {
    $sirali = @($liste | Sort-Object { $_.Yol.Length })
    $son = New-Object System.Collections.Generic.List[object]
    foreach ($a in $sirali) {
        $ust = $son | Where-Object { $_.Kesin -and $a.Yol.StartsWith($_.Yol + '\', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if (-not $ust) { $son.Add($a) }
    }
    $sira = @{ 'Klasör' = 1; 'Kısayol' = 2; 'Kayıt defteri' = 3; 'Başlangıç kaydı' = 4; 'Zamanlanmış görev' = 5; 'Servis' = 6 }
    return @($son | Sort-Object @{ e = { -not $_.Kesin } }, @{ e = { $sira[$_.Tur] } }, Yol)
}

# ---------------------------------------------------------------- demo verileri (ekran goruntusu icin, gercek veri yok)
function Demo-Programlar {
    $g = { param($ad, $yay, $sur, $mb, $tarih, $tur = 'Masaüstü')
        Yeni-Program -Tur $tur -Ad $ad -Yayinci $yay -Surum $sur -BoyutMB $mb -Tarih $(if ($tarih) { [datetime]$tarih } else { $null }) }
    @(
        (& $g '7-Zip 24.08 (x64)' 'Igor Pavlov' '24.08' 5.7 '2026-09-02'),
        (& $g 'Audacity 3.7.1' 'Audacity Team' '3.7.1' 98.4 '2026-10-11'),
        (& $g 'Blender' 'Blender Foundation' '4.2.3' 1104.6 '2026-08-19'),
        (& $g 'Discord' 'Discord Inc.' '1.0.9170' 152.3 '2026-07-30'),
        (& $g 'GIMP 2.10.38' 'The GIMP Team' '2.10.38' 412.0 '2026-06-14'),
        (& $g 'Git' 'The Git Development Community' '2.47.0' 336.5 '2026-10-05'),
        (& $g 'Mozilla Firefox (x64 en-US)' 'Mozilla' '132.0.2' 248.9 '2026-11-03'),
        (& $g 'Notepad++ (64-bit x64)' 'Notepad++ Team' '8.7.1' 15.2 '2026-09-21'),
        (& $g 'OBS Studio' 'OBS Project' '30.2.3' 487.1 '2026-08-02'),
        (& $g 'Python 3.12.7 (64-bit)' 'Python Software Foundation' '3.12.7' 103.0 '2026-10-18'),
        (& $g 'Spotify' 'Spotify AB' '1.2.48.405' $null $null 'Store'),
        (& $g 'Steam' 'Valve Corporation' '2.10.91.91' 690.2 '2026-05-27'),
        (& $g 'VLC media player' 'VideoLAN' '3.0.21' 172.4 '2026-07-08'),
        (& $g 'Visual Studio Code' 'Microsoft Corporation' '1.95.3' 382.6 '2026-11-12'),
        (& $g 'WhatsApp' 'WhatsApp Inc.' '2.2446.4.0' $null $null 'Store'),
        (& $g 'Windows Terminal' 'Microsoft Corporation' '1.21.3231.0' $null $null 'Store'),
        (& $g 'Zoom Workplace' 'Zoom Video Communications, Inc.' '6.2.10' 291.8 '2026-09-30')
    )
}

function Demo-Artiklar {
    $k = { param($tur, $yol, $neden, $kesin) [pscustomobject]@{ Tur = $tur; Yol = $yol; Neden = $neden; Kesin = $kesin; Ek = $null } }
    $ad = (T 'neden.ad') -f (T 'kaynak.ad')
    $kur = 'C:\Program Files (x86)\Steam'
    $liste = @(
        (& $k 'Klasör' $kur (T 'neden.kurulum') $true),
        (& $k 'Klasör' 'C:\Users\demo\AppData\Local\Steam' $ad $true),
        (& $k 'Kısayol' 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Steam\Steam.lnk' ((T 'neden.kisayol') -f "$kur\steam.exe") $true),
        (& $k 'Kısayol' 'C:\Users\Public\Desktop\Steam.lnk' ((T 'neden.kisayol') -f "$kur\steam.exe") $true),
        (& $k 'Kayıt defteri' 'HKEY_CURRENT_USER\Software\Valve\Steam' ((T 'neden.yayinciIci') -f (T 'kaynak.ad')) $true),
        (& $k 'Kayıt defteri' 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam' ((T 'neden.yayinciIci') -f (T 'kaynak.ad')) $true),
        (& $k 'Kayıt defteri' 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam' (T 'neden.kaldirmaKaydi') $true),
        (& $k 'Başlangıç kaydı' 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run\Steam' ((T 'neden.acilis') -f "`"$kur\steam.exe`" -silent") $true),
        (& $k 'Servis' 'Steam Client Service' "Steam Client Service — `"C:\Program Files (x86)\Common Files\Steam\steamservice.exe`" /RunAsService" $true),
        (& $k 'Klasör' 'D:\SteamLibrary' ((T 'neden.ad') -f ((T 'neden.onek') -f (T 'kaynak.ad'))) $false),
        (& $k 'Kayıt defteri' 'HKEY_CURRENT_USER\Software\Valve' ((T 'neden.yayinci') -f 'Valve') $false)
    )
    return @(Adaylari-Sirala $liste)
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
                    if (Korumali $a.Yol) { throw (T 'hata.korunan') }
                    if (Test-Path -LiteralPath $a.Yol) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($a.Yol, $ui, $cop) }
                }
                'Kısayol' {
                    if (Test-Path -LiteralPath $a.Yol) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($a.Yol, $ui, $cop) }
                }
                'Kayıt defteri' {
                    if (Test-Path -LiteralPath "Registry::$($a.Yol)") {
                        & reg.exe export $a.Yol (Join-Path $klasor "kayit-$i.reg") /y 2>&1 | Out-Null
                        if ($LASTEXITCODE -ne 0) { throw (T 'hata.yedek') }
                        Remove-Item -LiteralPath "Registry::$($a.Yol)" -Recurse -Force -ErrorAction Stop
                    }
                }
                'Başlangıç kaydı' {
                    & reg.exe export $a.Ek.Anahtar (Join-Path $klasor "baslangic-$i.reg") /y 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw (T 'hata.yedek') }
                    Remove-ItemProperty -LiteralPath "Registry::$($a.Ek.Anahtar)" -Name $a.Ek.Deger -ErrorAction Stop
                }
                'Zamanlanmış görev' {
                    Export-ScheduledTask -TaskName $a.Ek.Ad -TaskPath $a.Ek.Yol -ErrorAction Stop |
                        Set-Content -LiteralPath (Join-Path $klasor "gorev-$i.xml") -Encoding Unicode
                    Unregister-ScheduledTask -TaskName $a.Ek.Ad -TaskPath $a.Ek.Yol -Confirm:$false -ErrorAction Stop
                }
                'Servis' {
                    & reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$($a.Ek.Ad)" (Join-Path $klasor "servis-$i.reg") /y 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw (T 'hata.yedek') }
                    Stop-Service -Name $a.Ek.Ad -Force -ErrorAction SilentlyContinue
                    & sc.exe delete $a.Ek.Ad 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw ((T 'hata.sc') -f $LASTEXITCODE) }
                }
            }
            $basarili++
            Add-Content -LiteralPath $gunluk -Encoding UTF8 -Value "OK     [$($a.Tur)] $($a.Yol)"
        } catch {
            $hatalar.Add("$($a.Yol)  —  $($_.Exception.Message)")
            Add-Content -LiteralPath $gunluk -Encoding UTF8 -Value "HATA   [$($a.Tur)] $($a.Yol)  —  $($_.Exception.Message)"
        }
    }
    return [pscustomobject]@{ Basarili = $basarili; Hatalar = $hatalar; Klasor = $klasor }
}

# ---------------------------------------------------------------- deneme modu (pencere yok, silme yok)
if ($Deneme) {
    $sure0 = Measure-Command { $script:Programlar = Programlari-Getir }
    "Bulunan program: $($script:Programlar.Count)  (Store: $(@($script:Programlar | Where-Object Tur -eq 'Store').Count)), $([math]::Round($sure0.TotalSeconds,1)) sn"
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
[void][HomemadeUninstaller.Yerel]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

$yazi = New-Object Drawing.Font('Segoe UI', 10)
$kalin = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$turuncu = [Drawing.Color]::FromArgb(176, 96, 0)

$form = New-Object Windows.Forms.Form
$form.Size = New-Object Drawing.Size(1150, 720)
$form.StartPosition = 'CenterScreen'
$form.Font = $yazi
$form.AutoScaleMode = 'Dpi'
try { $form.Icon = New-Object Drawing.Icon($IkonYolu) } catch { }

$ust = New-Object Windows.Forms.TableLayoutPanel
$ust.Dock = 'Top'; $ust.AutoSize = $true; $ust.Padding = '8,8,8,4'; $ust.ColumnCount = 6; $ust.RowCount = 1
foreach ($i0 in 1..6) { [void]$ust.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize'))) }
$ust.ColumnStyles[4].SizeType = 'Percent'; $ust.ColumnStyles[4].Width = 100
$etiket = New-Object Windows.Forms.Label; $etiket.AutoSize = $true; $etiket.Margin = '3,7,3,3'
$arama = New-Object Windows.Forms.TextBox; $arama.Width = 340
$btnYenile = New-Object Windows.Forms.Button; $btnYenile.AutoSize = $true
$btnIsimle = New-Object Windows.Forms.Button; $btnIsimle.AutoSize = $true
$bosluk = New-Object Windows.Forms.Label; $bosluk.AutoSize = $true
$btnDil = New-Object Windows.Forms.Button; $btnDil.AutoSize = $true; $btnDil.Anchor = 'Right'
$ust.Controls.Add($etiket, 0, 0); $ust.Controls.Add($arama, 1, 0); $ust.Controls.Add($btnYenile, 2, 0)
$ust.Controls.Add($btnIsimle, 3, 0); $ust.Controls.Add($bosluk, 4, 0); $ust.Controls.Add($btnDil, 5, 0)

$lv = New-Object Windows.Forms.ListView
$lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false
$Kolonlar = @('Ad', 'Yayinci', 'Surum', 'BoyutMB', 'Tarih', 'Tur')
foreach ($gen in @(380, 240, 130, 110, 100, 100)) { [void]$lv.Columns.Add('', $gen) }

$alt = New-Object Windows.Forms.FlowLayoutPanel
$alt.Dock = 'Bottom'; $alt.AutoSize = $true; $alt.Padding = '8,4,8,8'; $alt.WrapContents = $false
$btnKaldir = New-Object Windows.Forms.Button; $btnKaldir.Font = $kalin; $btnKaldir.AutoSize = $true; $btnKaldir.Padding = '10,4,10,4'
$durumEtiket = New-Object Windows.Forms.Label; $durumEtiket.AutoSize = $true; $durumEtiket.Margin = '12,12,3,3'
$alt.Controls.AddRange(@($btnKaldir, $durumEtiket))

$menu = New-Object Windows.Forms.ContextMenuStrip
$miKaldir = $menu.Items.Add('')
$miTara = $menu.Items.Add('')
$miKlasor = $menu.Items.Add('')
$lv.ContextMenuStrip = $menu

$form.Controls.AddRange(@($lv, $ust, $alt))
$lv.BringToFront()

$script:Programlar = @()
$script:SiraKolon = 'Ad'
$script:SiraTers = $false

function Durum([string]$m) {
    if ($Demo -and -not $m) { $m = '' }
    $durumEtiket.Text = $m
    [Windows.Forms.Application]::DoEvents()
}
function Bilgi([string]$m, [string]$ikon = 'Information') { [void][Windows.Forms.MessageBox]::Show($form, $m, $UygulamaAdi, 'OK', $ikon) }
function Sor([string]$m, [string]$butonlar = 'YesNo') { return [Windows.Forms.MessageBox]::Show($form, $m, $UygulamaAdi, $butonlar, 'Question') }

function Dil-Uygula {
    $form.Text = (T 'baslik') -f $UygulamaAdi
    $etiket.Text = T 'ara'
    $btnYenile.Text = T 'yenile'
    $btnIsimle.Text = T 'isimle'
    $btnDil.Text = T 'dilDugme'
    $btnKaldir.Text = T 'kaldirDugme'
    $miKaldir.Text = T 'menu.kaldir'
    $miTara.Text = T 'menu.tara'
    $miKlasor.Text = T 'menu.klasor'
    $basliklar = 'kol.ad', 'kol.yayinci', 'kol.surum', 'kol.boyut', 'kol.tarih', 'kol.tur'
    for ($j = 0; $j -lt $basliklar.Count; $j++) { $lv.Columns[$j].Text = T $basliklar[$j] }
}

function Listeyi-Doldur {
    $f = $arama.Text.Trim()
    $goster = @($script:Programlar | Where-Object {
        -not $f -or $_.Ad.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        ($_.Yayinci -and $_.Yayinci.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0) })
    $goster = @($goster | Sort-Object -Property $script:SiraKolon -Descending:$script:SiraTers)
    $seciliAd = if ($lv.SelectedItems.Count) { $lv.SelectedItems[0].Tag.Ad } else { $null }
    $lv.BeginUpdate()
    $lv.Items.Clear()
    $tarihBicimi = if ($script:Dil -eq 'tr') { 'dd.MM.yyyy' } else { 'yyyy-MM-dd' }
    foreach ($p in $goster) {
        $it = New-Object Windows.Forms.ListViewItem($p.Ad)
        [void]$it.SubItems.Add($p.Yayinci)
        [void]$it.SubItems.Add($p.Surum)
        [void]$it.SubItems.Add($(if ($p.BoyutMB) { '{0:N1} MB' -f $p.BoyutMB } else { '' }))
        [void]$it.SubItems.Add($(if ($p.Tarih) { $p.Tarih.ToString($tarihBicimi) } else { '' }))
        [void]$it.SubItems.Add((T "tur.$($p.Tur)"))
        $it.Tag = $p
        [void]$lv.Items.Add($it)
        if ($seciliAd -and $p.Ad -eq $seciliAd) { $it.Selected = $true }
    }
    $lv.EndUpdate()
    $m = (T 'durum.sayi') -f $goster.Count
    if ($Demo) { $m += "   ·   " + (T 'durum.demo') }
    Durum $m
}

function Programlari-Yenile {
    $form.Cursor = 'WaitCursor'
    Durum (T 'durum.okunuyor')
    $script:Programlar = if ($Demo) { @(Demo-Programlar) } else { @(Programlari-Getir) }
    $form.Cursor = 'Default'
    Listeyi-Doldur
}

function Bekle([scriptblock]$kosul) {
    while (& $kosul) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 300
    }
}

# Pencerenin sadece kendisinin goruntusu (cevresindeki masaustu girmez)
function Pencere-Goruntusu($frm, [string]$dosya) {
    [HomemadeUninstaller.Yerel]::KoseleriDuzYap($frm.Handle)
    $frm.TopMost = $true; $frm.Activate()
    for ($j = 0; $j -lt 10; $j++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
    $r = [HomemadeUninstaller.Yerel]::Cerceve($frm.Handle)
    if (-not $r) { $r = @($frm.Left, $frm.Top, $frm.Width, $frm.Height) }
    $bmp = New-Object Drawing.Bitmap($r[2], $r[3])
    $gr = [Drawing.Graphics]::FromImage($bmp)
    $gr.CopyFromScreen($r[0], $r[1], 0, 0, $bmp.Size)
    $gr.Dispose()
    $bmp.Save($dosya, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $frm.TopMost = $false
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
        $c = Sor ((T 'msg.kaldiriciYok') -f $exe)
        if ($c -eq 'Yes') { return 'yok' } else { return 'iptal' }
    }
    Durum ((T 'durum.bekliyor') -f $prog.Ad)
    $basla = Get-Date
    try {
        if ($arg) { $proc = Start-Process -FilePath $exe -ArgumentList $arg -PassThru -ErrorAction Stop }
        else { $proc = Start-Process -FilePath $exe -PassThru -ErrorAction Stop }
    } catch {
        Bilgi ((T 'msg.baslatilamadi') -f $_.Exception.Message) 'Error'
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
        $c = Sor ((T 'msg.hala') -f $prog.Ad)
        if ($c -ne 'Yes') { return 'iptal' }
        if (& $kayitli) { return 'hala' }
    }
    return 'tamam'
}

function Artiklari-Goster($prog, [bool]$hala) {
    $form.Cursor = 'WaitCursor'
    Durum ((T 'durum.taraniyor') -f $prog.Ad)
    $adaylar = if ($Demo) { @(Demo-Artiklar) } else { @(Artiklari-Tara $prog) }
    $form.Cursor = 'Default'
    Listeyi-Doldur
    if ($adaylar.Count -eq 0) { Bilgi ((T 'msg.temiz') -f $prog.Ad); return }

    $f2 = New-Object Windows.Forms.Form
    $f2.Text = (T 'art.baslik') -f $prog.Ad
    $f2.Size = New-Object Drawing.Size(1200, 600)
    $f2.StartPosition = 'CenterParent'
    $f2.Font = $yazi
    $f2.Icon = $form.Icon

    $bilgiEt = New-Object Windows.Forms.Label
    $bilgiEt.Dock = 'Top'; $bilgiEt.Height = 70; $bilgiEt.Padding = '8,8,8,0'
    $metin = T 'art.bilgi'
    if ($hala) { $metin = (T 'art.hala') + "`n" + $metin; $bilgiEt.ForeColor = $turuncu }
    $bilgiEt.Text = $metin

    $lv2 = New-Object Windows.Forms.ListView
    $lv2.Dock = 'Fill'; $lv2.View = 'Details'; $lv2.CheckBoxes = $true; $lv2.FullRowSelect = $true; $lv2.MultiSelect = $false
    foreach ($kol in @(@('art.kol.guven', 125), @('art.kol.tur', 145), @('art.kol.konum', 540), @('art.kol.neden', 420))) {
        [void]$lv2.Columns.Add((T $kol[0]), $kol[1])
    }
    foreach ($a in $adaylar) {
        $it = New-Object Windows.Forms.ListViewItem($(if ($a.Kesin) { T 'guven.kesin' } else { T 'guven.muhtemel' }))
        [void]$it.SubItems.Add((T "tur.$($a.Tur)"))
        [void]$it.SubItems.Add($a.Yol)
        [void]$it.SubItems.Add($a.Neden)
        $it.Checked = [bool]($a.Kesin -and -not $hala)
        if (-not $a.Kesin) { $it.ForeColor = $turuncu }
        $it.Tag = $a
        [void]$lv2.Items.Add($it)
    }

    $alt2 = New-Object Windows.Forms.FlowLayoutPanel
    $alt2.Dock = 'Bottom'; $alt2.AutoSize = $true; $alt2.Padding = '8,4,8,8'; $alt2.WrapContents = $false
    $btnSil = New-Object Windows.Forms.Button; $btnSil.Text = T 'art.sil'; $btnSil.Font = $kalin; $btnSil.AutoSize = $true; $btnSil.Padding = '10,4,10,4'
    $btnKesin = New-Object Windows.Forms.Button; $btnKesin.Text = T 'art.kesinler'; $btnKesin.AutoSize = $true
    $btnHepsi = New-Object Windows.Forms.Button; $btnHepsi.Text = T 'art.hepsi'; $btnHepsi.AutoSize = $true
    $btnHic = New-Object Windows.Forms.Button; $btnHic.Text = T 'art.hic'; $btnHic.AutoSize = $true
    $btnAc = New-Object Windows.Forms.Button; $btnAc.Text = T 'art.ac'; $btnAc.AutoSize = $true
    $btnKapat = New-Object Windows.Forms.Button; $btnKapat.Text = T 'art.kapat'; $btnKapat.AutoSize = $true
    $alt2.Controls.AddRange(@($btnSil, $btnKesin, $btnHepsi, $btnHic, $btnAc, $btnKapat))

    $f2.Controls.AddRange(@($lv2, $bilgiEt, $alt2))
    $lv2.BringToFront()

    $btnKesin.add_Click({ foreach ($it in $lv2.Items) { $it.Checked = [bool]$it.Tag.Kesin } })
    $btnHepsi.add_Click({ foreach ($it in $lv2.Items) { $it.Checked = $true } })
    $btnHic.add_Click({ foreach ($it in $lv2.Items) { $it.Checked = $false } })
    $btnKapat.add_Click({ $f2.Close() })
    $btnAc.add_Click({
        if ($Demo -or $lv2.SelectedItems.Count -eq 0) { return }
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
        if ($secili.Count -eq 0) { [void][Windows.Forms.MessageBox]::Show($f2, (T 'art.bos'), $UygulamaAdi); return }
        if ($Demo) { [void][Windows.Forms.MessageBox]::Show($f2, (T 'demo.sil'), $UygulamaAdi); return }
        $c = [Windows.Forms.MessageBox]::Show($f2, ((T 'art.onay') -f $secili.Count), $UygulamaAdi, 'YesNo', 'Question')
        if ($c -ne 'Yes') { return }
        $f2.Cursor = 'WaitCursor'
        $sonuc = Artiklari-Sil $prog $secili
        $f2.Cursor = 'Default'
        $mesaj = (T 'art.sonuc') -f $sonuc.Basarili, $sonuc.Klasor
        if ($sonuc.Hatalar.Count -gt 0) {
            $ilk = ($sonuc.Hatalar | Select-Object -First 8) -join "`n• "
            $mesaj += (T 'art.hatalar') -f $sonuc.Hatalar.Count, $ilk
        }
        [void][Windows.Forms.MessageBox]::Show($f2, $mesaj, $UygulamaAdi, 'OK', $(if ($sonuc.Hatalar.Count) { 'Warning' } else { 'Information' }))
        $f2.Close()
    })

    if ($EkranGoruntusu) {
        $f2.add_Shown({
            $script:z2 = New-Object Windows.Forms.Timer; $script:z2.Interval = 700
            $script:z2.add_Tick({
                $script:z2.Stop()
                $lv2.Items[1].Selected = $true
                Pencere-Goruntusu $f2 (Join-Path $EkranGoruntusu "leftovers-$($script:Dil).png")
                $f2.Close()
            })
            $script:z2.Start()
        })
    }

    [void]$f2.ShowDialog($form)
    $f2.Dispose()
}

function Secili-Program {
    if ($lv.SelectedItems.Count -eq 0) { Bilgi (T 'msg.sec'); return $null }
    return $lv.SelectedItems[0].Tag
}

function Kaldir-Secili {
    $prog = Secili-Program
    if (-not $prog) { return }
    $c = Sor ((T 'msg.onay') -f $prog.Ad)
    if ($c -ne 'Yes') { return }
    if ($Demo) { Artiklari-Goster $prog $false; return }
    $form.Enabled = $false
    try {
        $hala = $false
        if ($prog.Tur -eq 'Store') {
            Durum ((T 'durum.kaldiriliyor') -f $prog.Ad)
            try { Remove-AppxPackage -Package $prog.Paket -ErrorAction Stop }
            catch { Bilgi ((T 'msg.storeHata') -f $_.Exception.Message) 'Error'; return }
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
    if (-not $prog -or $Demo) { return }
    $d = Konum-Adaylari $prog | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($d) { Start-Process explorer.exe "`"$d`"" } else { Bilgi (T 'msg.klasorYok') }
})
$btnYenile.add_Click({ Programlari-Yenile })
$btnDil.add_Click({
    $script:Dil = if ($script:Dil -eq 'tr') { 'en' } else { 'tr' }
    Ayar-Yaz
    Dil-Uygula
    Listeyi-Doldur
})
$arama.add_TextChanged({ Listeyi-Doldur })
$lv.add_ColumnClick({
    param($kaynak, $olay)
    $kol = $Kolonlar[$olay.Column]
    if ($script:SiraKolon -eq $kol) { $script:SiraTers = -not $script:SiraTers } else { $script:SiraKolon = $kol; $script:SiraTers = $false }
    Listeyi-Doldur
})
$btnIsimle.add_Click({
    $ad = [Microsoft.VisualBasic.Interaction]::InputBox((T 'isim.metin'), (T 'isim.baslik'), '')
    $ad = "$ad".Trim()
    if ($ad.Length -lt 3) { return }
    $kurulu = $script:Programlar | Where-Object { $_.Ad.IndexOf($ad, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1
    if ($kurulu) {
        Bilgi ((T 'isim.kurulu') -f $kurulu.Ad) 'Warning'
        Artiklari-Goster (Yeni-Program -Ad $ad) $true
    } else {
        Artiklari-Goster (Yeni-Program -Ad $ad) $false
    }
})
$form.add_Shown({
    Programlari-Yenile
    if ($EkranGoruntusu) {
        # otomatik ekran goruntusu: Steam'i sec, ana pencereyi cek, artiklar penceresini ac ve cek, kapat
        foreach ($it in $lv.Items) { if ($it.Text -eq 'Steam') { $it.Selected = $true; $it.EnsureVisible() } }
        $lv.Focus()
        $script:z1 = New-Object Windows.Forms.Timer; $script:z1.Interval = 700
        $script:z1.add_Tick({
            $script:z1.Stop()
            Pencere-Goruntusu $form (Join-Path $EkranGoruntusu "main-$($script:Dil).png")
            Artiklari-Goster $lv.SelectedItems[0].Tag $false
            $form.Close()
        })
        $script:z1.Start()
    }
})

Dil-Uygula
[void]$form.ShowDialog()
