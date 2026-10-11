# Uji manual API transaksi (Tahap 11). Jalankan dari folder backend\ saat
# server Laravel menyala (php artisan serve):
#
#   .\coba-transaksi.ps1 -Email kasir@contoh.com -Password rahasia
#
# Skrip ini login sebagai kasir, memilih satu produk, lalu mengirim:
#   1) transaksi baru                      -> harus 201
#   2) transaksi yang SAMA lagi (local_uuid sama) -> harus 200, stok TIDAK berkurang lagi
#   3) transaksi dengan jumlah melebihi stok     -> harus 409, tidak ada yang tersimpan
# Efek ke database pengembangan: stok satu produk berkurang 1 dan ada 1 transaksi baru.

param(
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$BaseUrl = "http://127.0.0.1:8000/api"
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 dan PowerShell 7 menyimpan isi respons galat (409, 422, ...)
# di tempat yang berbeda; baca dari keduanya.
function BacaIsiGalat($Galat) {
    if ($Galat.ErrorDetails -and $Galat.ErrorDetails.Message) {
        return $Galat.ErrorDetails.Message
    }
    $respons = $Galat.Exception.Response
    try {
        if ($respons -is [System.Net.HttpWebResponse]) {
            $pembaca = New-Object System.IO.StreamReader($respons.GetResponseStream())
            return $pembaca.ReadToEnd()
        }
        if ($null -ne $respons -and $null -ne $respons.Content) {
            return $respons.Content.ReadAsStringAsync().Result
        }
    }
    catch { }
    return $null
}

function Panggil([string]$Method, [string]$Path, $Body, [string]$Token) {
    $headers = @{ Accept = "application/json" }
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    $params = @{ Method = $Method; Uri = "$BaseUrl$Path"; Headers = $headers; UseBasicParsing = $true }
    if ($null -ne $Body) {
        $params["Body"] = ($Body | ConvertTo-Json -Depth 6)
        $params["ContentType"] = "application/json"
    }
    try {
        $response = Invoke-WebRequest @params
        return @{ Status = [int]$response.StatusCode; Body = ($response.Content | ConvertFrom-Json) }
    }
    catch {
        if ($null -eq $_.Exception.Response) {
            throw "Tidak bisa terhubung ke $BaseUrl. Pastikan server Laravel menyala (php artisan serve)."
        }
        $status = [int]$_.Exception.Response.StatusCode
        $isi = BacaIsiGalat $_
        $parsed = $null
        if ($isi) {
            try { $parsed = $isi | ConvertFrom-Json } catch { }
        }
        return @{ Status = $status; Body = $parsed; Mentah = $isi }
    }
}

function Cek([bool]$Lulus, [string]$Teks) {
    if ($Lulus) { Write-Host "  [LULUS] $Teks" -ForegroundColor Green }
    else { Write-Host "  [GAGAL] $Teks" -ForegroundColor Red; $script:ada_gagal = $true }
}

function Stok([string]$Token, [int]$ProductId) {
    $katalog = Panggil "GET" "/catalog" $null $Token
    return ($katalog.Body.data.products | Where-Object { $_.id -eq $ProductId }).stock
}

$script:ada_gagal = $false

Write-Host "1. Masuk sebagai kasir..."
$login = Panggil "POST" "/auth/login" @{ email = $Email; password = $Password; device_name = "coba-skrip" } $null
if ($login.Status -ne 200) {
    throw "Login gagal (status $($login.Status)). Periksa email/kata sandi; akun harus berperan 'cashier'."
}
$token = $login.Body.data.token

Write-Host "2. Memilih produk aktif dengan stok minimal 2..."
$katalog = Panggil "GET" "/catalog" $null $token
$produk = $katalog.Body.data.products | Where-Object { $_.is_active -and $_.stock -ge 2 } | Select-Object -First 1
if ($null -eq $produk) {
    throw "Tidak ada produk aktif dengan stok >= 2. Jalankan: php artisan db:seed --class=CatalogSeeder"
}
$stokAwal = [int]$produk.stock
Write-Host "   Produk: $($produk.name) (id $($produk.id)), harga $($produk.price), stok awal $stokAwal"

$uuid = [guid]::NewGuid().ToString()
$transaksi = @{
    local_uuid     = $uuid
    payment_method = "cash"
    total_amount   = [int]$produk.price
    created_at     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    items          = [object[]]@(@{
            product_id = [int]$produk.id
            quantity   = 1
            price      = [int]$produk.price
            subtotal   = [int]$produk.price
        })
}

Write-Host "3. Kirim transaksi baru..."
$pertama = Panggil "POST" "/transactions" $transaksi $token
Cek ($pertama.Status -eq 201) "status 201 (didapat: $($pertama.Status))"
Cek ($pertama.Body.meta.duplicate -eq $false) "meta.duplicate = false"
Write-Host "   Invoice dari server: $($pertama.Body.data.invoice_number)"
$stokSetelahPertama = [int](Stok $token $produk.id)
Cek ($stokSetelahPertama -eq ($stokAwal - 1)) "stok berkurang 1 ($stokAwal -> $stokSetelahPertama)"

Write-Host "4. Kirim transaksi yang SAMA lagi (local_uuid sama)..."
$kedua = Panggil "POST" "/transactions" $transaksi $token
Cek ($kedua.Status -eq 200) "status 200 (didapat: $($kedua.Status))"
Cek ($kedua.Body.meta.duplicate -eq $true) "meta.duplicate = true"
Cek ($kedua.Body.data.id -eq $pertama.Body.data.id) "id transaksi sama, tidak ada transaksi kedua"
$stokSetelahKedua = [int](Stok $token $produk.id)
Cek ($stokSetelahKedua -eq $stokSetelahPertama) "stok TIDAK berkurang lagi (tetap $stokSetelahKedua)"

Write-Host "5. Kirim transaksi dengan jumlah melebihi stok..."
$berlebih = $stokSetelahKedua + 100
$konflik = @{
    local_uuid     = [guid]::NewGuid().ToString()
    payment_method = "cash"
    total_amount   = [int]$produk.price * $berlebih
    created_at     = $transaksi.created_at
    items          = [object[]]@(@{
            product_id = [int]$produk.id
            quantity   = $berlebih
            price      = [int]$produk.price
            subtotal   = [int]$produk.price * $berlebih
        })
}
$ditolak = Panggil "POST" "/transactions" $konflik $token
Cek ($ditolak.Status -eq 409) "status 409 (didapat: $($ditolak.Status))"
if ($null -eq $ditolak.Body) {
    Write-Host "   Isi respons tidak terbaca. Mentah: $($ditolak.Mentah)" -ForegroundColor Yellow
}
else {
    Write-Host "   Pesan server: $($ditolak.Body.message)"
}
Cek ($ditolak.Body.code -eq "insufficient_stock") "code = insufficient_stock"
Cek (([int](Stok $token $produk.id)) -eq $stokSetelahKedua) "stok tidak berubah oleh transaksi yang ditolak"

Write-Host ""
if ($script:ada_gagal) {
    Write-Host "Ada pemeriksaan yang GAGAL. Salin seluruh keluaran ini ke chat." -ForegroundColor Red
    exit 1
}
Write-Host "Semua pemeriksaan LULUS. Tahap 11 berfungsi." -ForegroundColor Green
Write-Host "Mengembalikan stok produk ini (opsional):"
Write-Host "  php artisan tinker --execute=`"App\Models\Product::find($($produk.id))->increment('stock');`""
