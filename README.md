# POS Kantin — Fondasi Proyek

Paket ini adalah **overlay**: kode yang disalin ke project Laravel dan Flutter
hasil generate resmi. Isinya mencakup **tahap 1–20** (seluruh urutan AGENTS.md §30) dari urutan di `AGENTS.md` §30
(Laravel + database, autentikasi, kategori/produk, API produk, fondasi Flutter,
skema SQLite lokal, autentikasi Flutter, katalog produk + sinkronisasi pull,
keranjang, transaksi lokal, API transaksi, pengiriman transaksi dari Flutter, sinkronisasi otomatis, penanganan konflik, riwayat transaksi, dashboard Filament, laporan, statistik, pemolesan UI, pengujian akhir).
Seluruh tahap sudah selesai. Fitur baru di luar MVP (AGENTS.md §31) sengaja tidak ada.

> **Status verifikasi.** Backend: seluruh langkah setup selesai dan 13 tes lulus
> (sudah dijalankan di komputer pengembang). Mobile: project Flutter sudah
> diinisialisasi; perubahan baru (font Inter, HTTP debug, run di HP) ada di
> bagian B.

Struktur di komputer pengembang (satu repositori Git di `pos-kantin/`):
```
C:\DIL\pos-kantin\
├── README.md
├── backend\        ← project Laravel   (sumber overlay: folder backend/ di paket)
└── kasir_kantin\   ← project Flutter   (sumber overlay: folder mobile/ di paket)
```

---

## A. Backend (Laravel)

### 1. Buat project dan pasang paket
```bash
composer create-project laravel/laravel backend
cd backend
php artisan install:api                 # memasang Laravel Sanctum + routes/api.php
composer require filament/filament
php artisan filament:install --panels   # buat panel "admin"
```
Jika `install:api` menawarkan untuk menjalankan migrasi, pilih **no**. Database
MySQL dibuat dulu di langkah 2, dan migrasi dijalankan di langkah 6.

### 2. Buat database MySQL
Pastikan MySQL/MariaDB berjalan (XAMPP, Laragon, atau service sendiri). Buka
tab **SQL** di phpMyAdmin, atau masuk lewat terminal dengan `mysql -u root`
(tambahkan `-p` bila root punya password). Jalankan:

```sql
-- Database pengembangan dan database khusus tes
CREATE DATABASE IF NOT EXISTS pos_kantin      CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS pos_kantin_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

Lalu ubah `.env` di root project Laravel (bagian `DB_*` bawaan memakai SQLite,
ganti seluruhnya). Untuk pengembangan lokal, bawaan XAMPP/Laragon adalah `root`
tanpa password:
```
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=pos_kantin
DB_USERNAME=root
DB_PASSWORD=
```
Jangan commit `.env` ke Git (sudah ada di `.gitignore` bawaan Laravel).

> **Keamanan.** `root` tanpa password hanya untuk komputer pribadi saat
> pengembangan. Pastikan MySQL hanya mendengarkan di `127.0.0.1` (bawaan XAMPP)
> dan port 3306 tidak dibuka ke jaringan. **Jangan** dibawa ke hosting/server:
> di sana wajib memakai user khusus dengan password kuat yang hanya ada di
> `.env` server.

**Opsional: user khusus aplikasi** (membiasakan alur yang sama dengan production).
Jalankan di tab SQL sebagai root, ganti `GANTI-PASSWORD-INI` dan jangan dikosongkan:
```sql
-- DROP USER membuat perintah ini aman diulang (menghindari error #1396 bila user sudah ada).
DROP USER IF EXISTS 'pos_kantin'@'localhost';
CREATE USER 'pos_kantin'@'localhost' IDENTIFIED BY 'GANTI-PASSWORD-INI';
GRANT ALL PRIVILEGES ON pos_kantin.*      TO 'pos_kantin'@'localhost';
GRANT ALL PRIVILEGES ON pos_kantin_test.* TO 'pos_kantin'@'localhost';
FLUSH PRIVILEGES;
```
Lalu di `.env` ganti `DB_USERNAME=pos_kantin` dan `DB_PASSWORD=` dengan password
yang sama persis.

**Database untuk tes.** `RefreshDatabase` menghapus seluruh tabel sebelum tes
berjalan, jadi tes tidak boleh menunjuk ke `pos_kantin` (berlaku juga bila
memakai root). Buka `phpunit.xml`:
- Jika baris `DB_CONNECTION` = `sqlite` dan `DB_DATABASE` = `:memory:` **aktif**
  (tidak dalam komentar `<!-- -->`), tes memakai SQLite di memori dan aman;
  `pos_kantin_test` tidak terpakai.
- Jika baris itu **dikomentari**, buat file `.env.testing` di root project
  (samakan `DB_USERNAME`/`DB_PASSWORD` dengan `.env`):
```
APP_ENV=testing
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=pos_kantin_test
DB_USERNAME=root
DB_PASSWORD=
```

Verifikasi koneksi:
```bash
php artisan config:clear
php artisan db:show
```
Perintah kedua harus menampilkan `MySQL`/`MariaDB` dan database `pos_kantin`.
Jika muncul `Access denied`, periksa username/password di `.env`.

### 3. Salin overlay
Salin isi folder `backend/` di paket ini ke root project (timpa `app/Models/User.php`
dan `routes/api.php`). Pasang Filament **sebelum** menyalin, karena `User`
mengimplementasikan `FilamentUser`.

### 4. Daftarkan middleware `role` dan paksa respons JSON untuk `/api/*`
Di `bootstrap/app.php`:
```php
->withMiddleware(function (Middleware $middleware): void {
    $middleware->alias([
        'role' => \App\Http\Middleware\EnsureUserHasRole::class,
    ]);
})
->withExceptions(function (Exceptions $exceptions): void {
    // Tanpa ini, request tanpa header Accept: application/json ke rute
    // terproteksi akan dialihkan ke halaman login yang tidak ada.
    $exceptions->shouldRenderJsonWhen(
        fn ($request, $e) => $request->is('api/*') || $request->expectsJson()
    );
})
```

### 5. Terapkan warna DESIGN.md ke panel Filament
Di `app/Providers/Filament/AdminPanelProvider.php`, dalam `panel()`:
```php
use Filament\Support\Colors\Color;

->brandName('Kasir Kantin')
->colors([
    'primary' => Color::hex('#287B72'),   // secondary teal: aksi utama
    'warning' => Color::hex('#F47C48'),   // coral: peringatan
])
```
Sidebar deep teal (`#0F4540`) dan font perlu tema Filament kustom; itu masuk
tahap 16 (dashboard), bukan sekarang.

### 6. Migrasi dan storage
```bash
php artisan migrate
php artisan storage:link        # untuk gambar produk (disk public)
```

### 7. Buat akun secara manual
`role` sengaja tidak bisa diisi lewat mass-assignment. Tetapkan lewat tinker
(`php artisan tinker`):
```php
use App\Models\User;
use App\Enums\UserRole;

$owner = new User(['name' => 'Pemilik', 'email' => 'owner@kantin.test', 'password' => 'GANTI-INI']);
$owner->role = UserRole::Owner;
$owner->save();

$kasir = new User(['name' => 'Kasir', 'email' => 'kasir@kantin.test', 'password' => 'GANTI-INI']);
$kasir->role = UserRole::Cashier;
$kasir->save();
```
Password otomatis di-hash. Owner masuk ke `/admin`; kasir masuk lewat aplikasi Flutter.

### 8. Jalankan tes
```bash
php artisan test
```

### Kontrak API tahap ini
| Method | Path | Akses | Keterangan |
|---|---|---|---|
| POST | `/api/auth/login` | publik (throttle 10/menit) | Hanya role `cashier`. 401 salah kredensial, 403 bukan kasir, 422 input tidak valid |
| POST | `/api/auth/logout` | token | Menghapus token saat ini (204) |
| GET | `/api/auth/me` | token | Profil pengguna |
| GET | `/api/catalog?updated_since=` | token + `cashier` | Kategori & produk. Tanpa parameter = sinkronisasi penuh (tanpa data terhapus). Dengan parameter = semua perubahan sejak waktu itu, **termasuk** yang `deleted_at`-nya terisi. Simpan `meta.server_time` sebagai `updated_since` berikutnya |
| POST | `/api/transactions` | token + `cashier` | Menerima satu transaksi, **idempoten lewat `local_uuid`**. 201 = baru tersimpan, 200 = `local_uuid` sudah pernah diterima (hasil lama dikembalikan, `meta.duplicate: true`), 409 = stok server kurang (`code: insufficient_stock`, tidak ada yang tersimpan), 422 = payload tidak valid. Lihat bagian *Tahap 11* di bawah |

### Tahap 11 — API transaksi

Tanpa migrasi baru: tabel `transactions` dan `transaction_items` sudah dibuat di
tahap 1–6. Yang baru: `TransactionController`, `StoreTransactionRequest`,
`TransactionService`, `TransactionResource`, `InsufficientStockException`, rute
`POST /api/transactions`, dan tes `TransactionApiTest` + `TransactionAccessTest`.

**Salin overlay** seperti biasa (folder `backend/` di paket ke `backend\`). Satu
file yang sudah ada ikut berubah: `routes/api.php` (menambah rute transaksi).
Satu file baru di luar `app/`: `coba-transaksi.ps1` (skrip uji manual, lihat di bawah;
file ini ada di paket Tahap 12, salin ke `backend\`).
Setelah itu jalankan `php artisan test`.

**Permintaan** (`POST /api/transactions`, header `Authorization: Bearer <token>`):
```json
{
  "local_uuid": "c0a8b2e4-5d3f-4f6a-9c1e-2b7d8e9f0a1b",
  "invoice_number": "INV-20261011-C0A8B2",
  "payment_method": "cash",
  "total_amount": 20000,
  "created_at": "2026-10-11T08:30:00Z",
  "items": [{ "product_id": 1, "quantity": 2, "price": 10000, "subtotal": 20000 }]
}
```
`invoice_number` boleh dikosongkan; server membuat sendiri. Respons sukses:
`{ "data": { id, local_uuid, invoice_number, total_amount, payment_method,
sync_status, created_at, synced_at, items: [...] }, "meta": { "duplicate": false } }`.

**Respons galat** untuk Tahap 13/14 di Flutter (AGENTS.md §17):
| Kode | Arti bagi perangkat |
|---|---|
| 201 / 200 | Sudah ada di server → `synced` (200 berarti kiriman ulang, bukan galat) |
| 409 `insufficient_stock` | Konflik bisnis → `conflict`. Isi `shortages[]`: `product_id`, `product_name`, `requested`, `available` |
| 422 | Payload tidak valid → jangan dicoba ulang terus-menerus |
| 401 / 403 | Sesi berakhir / bukan kasir |
| 5xx / jaringan | Dapat dicoba ulang → `failed` |

**Cara kerjanya**, dalam satu `DB::transaction`:
1. Kunci baris produk (`lockForUpdate`, urut `id` agar tidak saling kunci melingkar).
2. Cek `local_uuid` yang sudah ada → kembalikan hasil lama (tanpa mengurangi stok lagi).
   Pengecekan ini sengaja **setelah** kunci produk didapat, supaya dua request kembar
   yang berbarengan tidak salah dijawab 409.
3. Cek stok semua item; bila ada yang kurang → 409 dan semuanya dibatalkan.
4. Tulis transaksi + item (snapshot nama dan harga), kurangi stok lewat Eloquent
   `decrement` sehingga `updated_at` berubah dan sinkronisasi inkremental katalog
   membawa stok baru ke perangkat.

**Uji manual (2 menit, tanpa mengetik JSON).** Pakai skrip `backend/coba-transaksi.ps1`
yang ikut di paket (sudah ada di folder `backend\` setelah overlay disalin).

1. Terminal 1, di folder `backend\`: jalankan server.
   ```powershell
   php artisan serve
   ```
2. Terminal 2, di folder `backend\`: jalankan skrip dengan akun **kasir** yang
   kamu buat lewat tinker (bukan akun owner).
   ```powershell
   .\coba-transaksi.ps1 -Email EMAIL_KASIR -Password KATA_SANDI
   ```
   Bila PowerShell menolak menjalankan skrip, jalankan sekali:
   `Set-ExecutionPolicy -Scope Process Bypass`, lalu ulangi perintah di atas.
3. Hasil yang benar: semua baris berawalan `[LULUS]` hijau dan akhirnya
   `Semua pemeriksaan LULUS`. Skrip memeriksa tiga hal: transaksi baru (201),
   kiriman yang sama dua kali (200, stok tidak berkurang lagi), dan jumlah melebihi
   stok (409, tidak ada yang tersimpan).
4. Bila ada `[GAGAL]`, salin seluruh keluaran terminal ke chat.

Skrip mengurangi stok satu produk sebanyak 1 dan menambah 1 transaksi di database
pengembangan. Aman; stok bisa dikembalikan dengan perintah yang dicetak di akhir skrip.

Tahap 11 hanya backend. Sisi Flutter untuk memanggil endpoint ini ada di Tahap 12.

---

## B. Mobile (Flutter)

### 1. Buat project dan pasang paket
```bash
flutter create --org id.sch.kantin kasir_kantin
cd kasir_kantin
flutter pub add flutter_bloc equatable sqflite path http flutter_secure_storage uuid
flutter pub add intl:any
flutter pub add flutter_localizations --sdk=flutter
flutter pub add --dev bloc_test mocktail sqflite_common_ffi
```
`intl:any` wajib sebelum `flutter_localizations`: SDK Flutter mengunci versi
`intl`, dan constraint `^x.y.z` hasil `flutter pub add intl` akan bentrok
(`version solving failed`). Jika sudah terlanjur, ubah `intl: ^...` di
`pubspec.yaml` menjadi `intl: any`, lalu jalankan ulang perintah di atas.
Salin isi folder `mobile/` di paket ini ke root `kasir_kantin` (`lib/`, `test/`,
dan `android/app/src/debug/AndroidManifest.xml`). Hapus `test/widget_test.dart`
bawaan karena merujuk `MyApp` yang sudah tidak ada.

### 2. Font Inter
`AppTheme.fontFamily = 'Inter'` sudah diatur; tinggal menyediakan file fontnya.
Font di-bundle ke dalam aplikasi (bukan diunduh saat runtime) agar tampilan
tetap konsisten saat offline.

1. Unduh **Inter** (lisensi SIL OFL, bebas dipakai) dari Google Fonts atau
   https://rsms.me/inter, lalu ambil **file statis** (bukan variable font) berikut:
   `Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf`, `Inter-Bold.ttf`.
   Pada unduhan Google Fonts, file statis ada di folder `static/`
   (namanya bisa `Inter_18pt-Regular.ttf` atau `Inter_24pt-...`; pilih satu
   keluarga ukuran optis yang sama dan **ganti namanya** sesuai daftar di atas
   atau sesuaikan path di `pubspec.yaml`).
2. Taruh di `kasir_kantin/assets/fonts/`.
3. Tambahkan di `pubspec.yaml` pada bagian `flutter:` (indentasi 2 spasi, jangan tab):
```yaml
flutter:
  uses-material-design: true

  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```
4. `flutter pub get`, lalu jalankan ulang aplikasi. Font baru butuh **restart penuh**
   (`R` di terminal `flutter run`), hot reload saja tidak cukup.

### 3. Izinkan HTTP untuk build debug
Android 9+ memblokir HTTP polos secara bawaan, sedangkan `php artisan serve`
tidak memakai HTTPS. File `android/app/src/debug/AndroidManifest.xml` dari paket
ini menambahkan `usesCleartextTraffic="true"` **hanya untuk build debug**.
Tanpa itu, aplikasi akan gagal terhubung dengan pesan
`Cleartext HTTP traffic not permitted`.

> Sebelum membuat APK **release**: tambahkan
> `<uses-permission android:name="android.permission.INTERNET"/>` di
> `android/app/src/main/AndroidManifest.xml` (izin ini bawaan hanya di build
> debug), dan pakai server HTTPS.

### 4. Jalankan di HP Android (tanpa Android Studio)
Cukup Android SDK command line (`platform-tools`, `build-tools`, `platforms`);
emulator tidak diperlukan. Cek dulu `flutter doctor -v`: bagian *Android
toolchain* harus tanpa tanda silang (lisensi: `flutter doctor --android-licenses`).

**a. Aktifkan USB debugging di HP**
1. *Pengaturan → Tentang ponsel*, ketuk **Nomor build** 7 kali.
2. *Pengaturan → Opsi pengembang → Debugging USB* = aktif.
3. Sambungkan kabel USB (gunakan kabel data, bukan kabel khusus charge), pilih
   mode **Transfer file**, dan setujui dialog *Izinkan debugging USB?*.
4. Pastikan HP terdeteksi:
```powershell
adb devices
flutter devices
```
`adb devices` harus menampilkan status `device`. Jika `unauthorized`, cabut-colok
dan setujui dialog di HP. Jika daftar kosong, pasang driver USB dari pabrikan
HP (mis. Xiaomi, Samsung, Oppo) atau coba kabel/port lain.

**b. Hubungkan HP ke server Laravel** (pilih salah satu)

*Opsi 1 — via kabel USB dengan `adb reverse` (disarankan).* Tidak perlu IP maupun
pengaturan firewall:
```powershell
# terminal 1: server Laravel (cukup di 127.0.0.1)
cd C:\DIL\pos-kantin\backend
php artisan serve

# terminal 2: teruskan port 8000 HP -> laptop, lalu jalankan aplikasi
adb reverse tcp:8000 tcp:8000
cd C:\DIL\pos-kantin\kasir_kantin
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```
`adb reverse` hilang setiap kali kabel dicabut atau `adb` dimulai ulang; jalankan
lagi bila aplikasi tiba-tiba tidak bisa terhubung.

Agar tidak ada langkah yang terlewat, salin `run_dev.cmd` dari paket ke root
`kasir_kantin`, lalu cukup jalankan (setelah `php artisan serve` aktif):
```powershell
.\run_dev.cmd
```
Skrip ini menjalankan `adb reverse` **dan** `flutter run` dengan `API_BASE_URL` yang benar.
Argumen tambahan diteruskan ke `flutter run`, mis. `.\run_dev.cmd -d <id>`.

*Opsi 2 — via Wi-Fi yang sama.* HP dan laptop harus di jaringan yang sama:
```powershell
ipconfig        # catat "IPv4 Address" adapter Wi-Fi, mis. 192.168.1.10
cd C:\DIL\pos-kantin\backend
php artisan serve --host=0.0.0.0 --port=8000

cd C:\DIL\pos-kantin\kasir_kantin
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000/api
```
Saat pertama `serve` dengan `--host=0.0.0.0`, Windows Firewall akan bertanya:
izinkan untuk **jaringan privat**. Jaringan kampus/umum sering memblokir
komunikasi antarperangkat (*client isolation*); bila begitu, pakai Opsi 1.

**c. Tanpa kabel (Android 11+, opsional).** *Opsi pengembang → Debugging nirkabel*
→ *Pasangkan perangkat dengan kode*, lalu:
```powershell
adb pair 192.168.1.20:PORT_PAIRING      # masukkan kode 6 digit
adb connect 192.168.1.20:PORT_UTAMA     # port berbeda, ada di layar Debugging nirkabel
```
Setelah itu `flutter devices` menampilkan HP. Karena tidak ada kabel, `adb reverse`
tidak dipakai; gunakan Opsi 2.

**d. Selama `flutter run` berjalan:** `r` = hot reload, `R` = restart penuh,
`q` = berhenti. Bila ada lebih dari satu perangkat, tambahkan `-d <id>` dari
`flutter devices`.

**e. Banner "Tidak dapat terhubung ke internet" padahal internet lancar.**
Banner ini muncul untuk **semua** kegagalan menjangkau server, bukan hanya internet
mati. Periksa berurutan:
1. Terminal `php artisan serve` masih berjalan?
2. `adb reverse --list` harus menampilkan `tcp:8000 tcp:8000`. Jika kosong (mis. kabel
   sempat tercabut), jalankan `adb reverse tcp:8000 tcp:8000`.
3. Aplikasi dijalankan dengan `--dart-define=API_BASE_URL=http://127.0.0.1:8000/api`?
   Tanpa itu, alamat bawaan `10.0.2.2` hanya berlaku untuk emulator dan **selalu gagal**
   di HP fisik. Setiap `flutter run` baru harus menyertakannya; `run_dev.cmd` melakukannya otomatis.
4. Uji dari HP: buka Chrome di HP, kunjungi `http://127.0.0.1:8000/up`. Jika halaman
   tidak tampil, masalahnya di langkah 1-2, bukan di aplikasi.
5. `adb devices` harus menampilkan `device` (bukan `unauthorized` atau kosong).

> **Simulasi offline.** Selama memakai `adb reverse`, **mode pesawat tidak memutus**
> koneksi ke server, karena lalu lintas lewat kabel USB. Untuk menguji kondisi
> offline, hentikan `php artisan serve` (Ctrl+C) atau jalankan `adb reverse --remove-all`.

**Laptop terbatas:** build pertama lama (Gradle mengunduh dependensi); build
berikutnya jauh lebih cepat. Tutup aplikasi berat saat build. Jika build berhenti
dengan `OutOfMemoryError` atau proses Gradle terbunuh, turunkan memori Gradle di
`android/gradle.properties` (mis. `org.gradle.jvmargs=-Xmx2G`) lalu
`flutter clean` dan ulangi. Gunakan mode debug bawaan (`flutter run`) selama
pengembangan.

### 5. Tes otomatis (di laptop, bukan di HP)
```powershell
flutter test
```
Tes database memakai `sqflite_common_ffi` dan butuh pustaka SQLite di mesin host
(Windows: `sqlite3.dll` di `PATH`; Linux: `libsqlite3-dev`). Tes `api_client` dan
`currency_formatter` tidak membutuhkannya.

### 6. Tahap 7 — Autentikasi Flutter
Tidak ada paket baru. Salin ulang folder `lib/` dan `test/` dari `mobile/` ke
`kasir_kantin` (timpa file yang sama).

**File yang berubah (timpa):** `lib/main.dart`, `lib/app/app.dart`,
`lib/app/app_shell.dart`, `lib/core/network/api_client.dart` (stream
`unauthorized` + parameter `reportUnauthorized`), `lib/core/storage/session_storage.dart`
(menyimpan token **dan** profil), `lib/core/theme/app_colors.dart` (dua warna lembut untuk banner).

**File baru:** `lib/app/auth_gate.dart`, `lib/app/settings_page.dart`, dan seluruh
`lib/features/auth/` (`domain/`, `data/`, `presentation/bloc/`, `presentation/pages/`),
beserta tesnya di `test/features/auth/`, `test/app/`, dan
`test/core/network/api_client_unauthorized_test.dart`.

**Perilaku yang dibangun:**
- **Sesi bertahan offline.** Saat aplikasi dibuka, sesi dipulihkan dari penyimpanan
  aman **tanpa** menunggu server. Hanya login pertama yang butuh internet.
- **Keluar tidak menghapus data lokal.** `logout` mencabut token di server bila
  bisa (maks. 3 detik), lalu selalu menghapus token + profil dari perangkat. Database
  SQLite (termasuk transaksi yang belum tersinkron) tidak disentuh (AGENTS.md Rule 6).
  Jika pencabutan di server gagal (offline), token itu tetap valid di server sampai
  dihapus; tidak berbahaya karena token sudah hilang dari HP.
- **Sesi berakhir (401).** Respons 401 pada permintaan bertoken (mis. katalog di
  tahap 8) membuat `AuthBloc` menghapus sesi lokal dan menampilkan pesan
  "Sesi berakhir. Silakan masuk kembali." 401 pada login **bukan** sesi berakhir
  (artinya kredensial salah).
- **Kirim ganda dicegah** di dua lapis: tombol nonaktif saat memproses, dan
  `AuthBloc` mengabaikan login saat sudah `AuthInProgress`.

**Verifikasi otomatis:** `cd kasir_kantin; flutter test`

**Verifikasi manual di HP.** Siapkan: server Laravel berjalan, `adb reverse`
aktif (bagian B.4), akun kasir **dan** owner sudah dibuat (bagian A.7).
1. Kolom kosong → "Email wajib diisi." / "Kata sandi wajib diisi."; email tanpa `@` → "Format email tidak valid."
2. Kata sandi salah → banner "Email atau kata sandi salah."
3. Masuk dengan akun **owner** → banner penolakan "...Gunakan dashboard web."
4. **Simulasi offline:** hentikan `php artisan serve` (mode pesawat tidak memutus koneksi saat memakai `adb reverse`), lalu masuk → banner koneksi internet. Nyalakan server lagi sesudahnya.
5. Masuk dengan akun kasir → tampil kerangka aplikasi. Tab **Pengaturan** menampilkan nama, email, dan "Kasir".
6. **Uji sesi offline:** setelah masuk, hentikan `php artisan serve`, tutup aplikasi sepenuhnya (swipe dari recent apps), lalu buka lagi → langsung masuk ke kerangka aplikasi, tanpa halaman login.
7. Pengaturan → **Keluar** → dialog konfirmasi → kembali ke halaman login. Cek di MySQL
   (`SELECT COUNT(*) FROM personal_access_tokens;`) token berkurang bila saat itu online.
8. Masuk dulu (server hidup), lalu hentikan `php artisan serve` dan tekan **Keluar** → tetap berhasil keluar (bisa tertahan beberapa detik).

Jalur "sesi berakhir" belum bisa diuji manual karena belum ada fitur yang memakai
token selain login; jalur itu diuji lewat tes otomatis dan baru terlihat nyata di tahap 8.

### 7. Tahap 8 — Katalog produk + sinkronisasi pull

Tidak ada paket baru, tidak ada migrasi (skema SQLite v1 dan skema MySQL sudah
cukup), dan tidak ada perubahan kontrak API. Salin ulang folder `backend/` dan
`mobile/` dari paket ke `backend` dan `kasir_kantin` (timpa file yang sama).

**Backend (baru):** `database/seeders/CatalogSeeder.php` dan
`tests/Feature/CatalogSeederTest.php`.

**Mobile — file baru:** seluruh `lib/features/products/`
(`domain/`, `data/`, `presentation/bloc|pages|widgets/`) dan tesnya di
`test/features/products/`.

**Mobile — file berubah (timpa):** `lib/main.dart` (merangkai
`CatalogRepositoryImpl`), `lib/app/app.dart` (menyediakan `CatalogRepository`),
`lib/app/app_shell.dart` (tab Kasir = `CatalogPage`, membuat `CatalogBloc`),
`lib/core/widgets/empty_state.dart` (parameter opsional `action`),
`test/app/auth_gate_test.dart` (menyediakan `CatalogRepository` palsu).

**Data uji.** Katalog masih kosong, dan Filament resource baru dibuat di tahap 16,
jadi isi lewat seeder (sengaja **tidak** masuk `DatabaseSeeder`):
```powershell
cd C:\DIL\pos-kantin\backend
php artisan db:seed --class=CatalogSeeder
```
Aman dijalankan berulang (tidak menduplikasi, tidak mengembalikan stok yang sudah
berubah). Isinya 3 kategori dan 12 produk (10 tampil di kasir), termasuk: stok menipis (Ayam Geprek 4,
Kopi Susu 3), stok habis (Batagor), satu produk **nonaktif** (Es Campur) dan satu
produk **terhapus** (Produk Dihapus (uji)).

**Perilaku yang dibangun:**
- **Lokal dulu.** Membuka tab Kasir langsung menampilkan isi SQLite; sinkronisasi
  berjalan di belakang (DESIGN.md §39). Tanpa internet, katalog tetap tampil
  dengan status "Offline · Data lokal digunakan" — bukan pesan galat.
- **Tarik inkremental.** Sinkronisasi pertama penuh (tanpa `updated_since`);
  berikutnya memakai `meta.server_time` terakhir (disimpan di
  `sync_metadata.products_last_sync`, apa adanya tanpa di-parse). Satu kursor untuk
  kategori dan produk karena keduanya datang dalam satu respons.
- **Atomik.** Upsert, penghapusan, dan kursor ditulis dalam satu transaksi SQLite.
  Jika satu baris gagal, semuanya batal dan kursor tidak maju, sehingga perubahan
  tidak pernah terlewat.
- **Penghapusan.** Data dengan `deleted_at` terisi dihapus dari SQLite.
  Sinkronisasi **penuh** membuang semua data lokal yang tidak ada di respons.
  Riwayat transaksi tetap aman karena `transaction_items` menyimpan snapshot.
- **Hanya produk aktif** yang tampil. Produk habis tampil redup dengan ikon +
  teks "Habis" dan tidak bisa dipilih; stok ≤ 5 menampilkan "Stok tersisa N".
- **Cari + kategori.** Pencarian nama (tidak peka huruf besar/kecil) dan chip
  kategori bekerja di data lokal. Kategori tanpa produk aktif tidak ditampilkan.
- **401 kini nyata.** Token yang dicabut membuat `AuthBloc` mengakhiri sesi
  (pesan "Sesi berakhir. Silakan masuk kembali."); katalog tidak menampilkan
  galat ganda.

**⚠ Perubahan aturan stok (AGENTS.md Rule 10).** Stok di SQLite adalah *proyeksi*.
Saat menarik katalog, stok produk disimpan sebagai **stok server dikurangi penjualan
lokal yang belum diterima server** (transaksi `pending`, `syncing`, `failed`).
Transaksi `conflict` tidak dihitung (server menolaknya), dan `synced` tidak dihitung
(server sudah mengurangi). Tanpa ini, menarik katalog akan "mengembalikan" stok
barang yang sudah terjual offline. Saat ini belum ada transaksi, jadi efeknya baru
terlihat di tahap 10–13; logikanya sudah diuji.

**Catatan untuk tahap berikutnya:**
- **Tahap 11 (API transaksi):** kurangi stok dengan Eloquent (`$product->decrement('stock', $qty)`)
  atau `save()`, **bukan** `DB::table('products')->decrement(...)`. Hanya jalur
  Eloquent yang menaikkan `updated_at`, dan sinkronisasi inkremental bergantung
  padanya agar perubahan stok sampai ke perangkat.
- **Tahap 13:** sinkronisasi saat ini hanya berjalan ketika tab Kasir dibuka dan
  saat ditarik manual. Pemicu otomatis (koneksi kembali, berkala) dan `SyncBloc`
  menyusul di tahap 13.
- Produk belum bisa diketuk (keranjang = tahap 9); `ProductCard` sudah menerima `onTap`.

**Verifikasi otomatis:**
```powershell
cd C:\DIL\pos-kantin\backend;     php artisan test      # sebelumnya 13 tes; kini 17
cd C:\DIL\pos-kantin\kasir_kantin; dart format lib test; flutter analyze; flutter test
```

**Verifikasi manual di HP.** Siapkan: `php artisan serve` berjalan, seeder sudah
dijalankan, lalu `.\run_dev.cmd`.
1. Masuk sebagai kasir → kerangka abu-abu sebentar, "Menyinkronkan...", lalu grid
   **10 produk**. Chip: Semua · Camilan · Makanan · Minuman.
2. Ayam Geprek "Stok tersisa 4", Kopi Susu "Stok tersisa 3", Batagor "Habis"
   (redup). **Tidak ada** Es Campur dan Produk Dihapus (uji).
3. Cari `kopi` → hanya Kopi Susu. Hapus pencarian (ikon ✕). Pilih chip Minuman →
   4 produk. Cari `zzz` → "Produk tidak ditemukan".
4. **Offline:** hentikan `php artisan serve`, tutup aplikasi sepenuhnya, buka lagi →
   produk langsung tampil dan status "Offline · Data lokal digunakan". Tarik layar
   ke bawah → tetap offline, produk tidak hilang.
5. **Inkremental:** di `php artisan tinker`:
   ```php
   use App\Models\Product;
   Product::where('name', 'Es Teh Manis')->first()->update(['price' => 6000, 'stock' => 2]);
   Product::where('name', 'Pisang Goreng')->first()->delete();
   ```
   Nyalakan server, tarik layar ke bawah → Es Teh Manis "Rp6.000" dan "Stok tersisa 2",
   Pisang Goreng hilang, status "Online · Diperbarui HH:mm".
6. **Sesi berakhir:** di tinker jalankan
   `\Illuminate\Support\Facades\DB::table('personal_access_tokens')->delete();`
   lalu tarik layar → kembali ke halaman masuk dengan "Sesi berakhir. Silakan masuk kembali."
   Masuk lagi → produk langsung tampil (data lokal tidak dihapus).

**Batasan yang disengaja:**
- Gambar produk dimuat dari jaringan tanpa cache disk; saat offline tampil ikon
  pengganti. Upload gambar baru ada di Filament (tahap 16); `image_url` memakai
  `APP_URL`, jadi di HP via `adb reverse` pastikan `APP_URL=http://127.0.0.1:8000`.
- Jika kamu menjalankan `php artisan migrate:fresh` saat sudah pernah menarik katalog,
  kursor lama di HP tidak cocok dengan database baru. Hapus data aplikasi
  (Setelan Android → Aplikasi → Kasir Kantin → Penyimpanan → Hapus data) lalu masuk lagi.

### 8. Tahap 9 — Keranjang

Tidak ada paket baru, tidak ada perubahan backend, skema SQLite/MySQL, maupun
kontrak API. Salin ulang folder `mobile/` ke `kasir_kantin` (timpa file yang sama).

**Sekaligus merapikan 9 info `flutter analyze`:** konstruktor memakai
*private named parameter* (`required this._repository`), `'sync_status': ?syncStatus`
pada tes database, dan dua import yang tidak perlu dihapus. Tidak ada perubahan
perilaku. Setelah ini `flutter analyze` seharusnya bersih.

**File baru:** seluruh `lib/features/cart/` (`domain/cart_item.dart`,
`presentation/bloc/`, `presentation/widgets/` berisi `QuantityControl`, `CartBar`,
`CartSheet`) dan tesnya di `test/features/cart/`.

**File berubah (timpa):** `lib/app/app_shell.dart` (menyediakan `CartBloc` dan
menghubungkan katalog → keranjang), `lib/features/products/presentation/pages/catalog_page.dart`
(ketuk produk, bar keranjang), `lib/features/products/presentation/widgets/product_card.dart`
(lencana jumlah), `test/features/products/presentation/catalog_page_test.dart`, serta
file lint: `auth_repository_impl.dart`, `auth_bloc.dart`, `login_page.dart`,
`catalog_repository_impl.dart`, `catalog_bloc.dart`, `app_database_test.dart`,
`api_client_unauthorized_test.dart`.

**Perilaku yang dibangun (AGENTS.md §19, DESIGN.md §16):**
- **Ketuk produk = tambah satu.** Produk yang sama menambah jumlah, bukan baris baru.
  Kartu menampilkan lencana jumlah di keranjang (ikon + angka).
- **Batas stok.** Jumlah tidak pernah melebihi stok lokal. Di katalog, ketukan yang
  melewati batas menampilkan pesan "Stok X hanya N."; di daftar keranjang tombol **+**
  nonaktif dengan keterangan "Mencapai batas stok (N)". Produk habis/nonaktif tidak
  bisa ditambahkan.
- **Bar keranjang** di bawah katalog (jumlah item + total) hanya muncul bila keranjang
  berisi; mengetuknya membuka daftar item: nama, harga satuan, `[-] n [+]`, subtotal,
  hapus per baris, total, dan Kosongkan (dengan konfirmasi). Jumlah diubah tanpa pindah halaman.
- **Jumlah tidak pernah 0:** `-` pada jumlah 1 menghapus baris.
- **Selaras dengan katalog.** Saat sinkronisasi mengubah katalog, isi keranjang
  disamakan: harga baru dipakai, jumlah dipotong ke stok baru, produk yang habis/nonaktif/
  terhapus dikeluarkan. Setiap penyesuaian diberitahukan lewat snackbar, tidak diam-diam.
- Keranjang hanya di memori selama sesi masuk (hilang bila aplikasi ditutup atau keluar).
  Belum ada tombol bayar; itu tahap 10.

**Catatan untuk tahap 10 (transaksi lokal):** harga, nama, dan stok di keranjang adalah
tampilan. Saat membuat transaksi, baca ulang produk dari SQLite **di dalam transaksi
database yang sama** dengan penulisan transaksi, validasi jumlah ≤ stok lokal saat itu,
lalu simpan snapshot nama/harga ke `transaction_items`. Keranjang dikosongkan hanya
setelah transaksi lokal berhasil tersimpan.

**Verifikasi otomatis:**
```powershell
cd C:\DIL\pos-kantin\kasir_kantin; dart format lib test; flutter analyze; flutter test
```

**Verifikasi manual di HP** (server berjalan, seeder sudah dijalankan, `.\run_dev.cmd`):
1. Ketuk **Nasi Goreng** → bar "Keranjang · 1 item · Rp15.000" muncul, kartu berlencana 1. Ketuk lagi → 2 item, Rp30.000.
2. Ketuk **Batagor** (habis) → tidak terjadi apa-apa. Ketuk **Kopi Susu** 4 kali (stok 3) → jumlah berhenti di 3 dan muncul "Stok Kopi Susu hanya 3."
3. Ketuk bar keranjang → daftar item. Tekan **+** pada Kopi Susu di batasnya → nonaktif, tampil "Mencapai batas stok (3)". Tekan **-** sampai 1, lalu sekali lagi → baris hilang.
4. Ikon tempat sampah menghapus satu baris; **Kosongkan** → konfirmasi → keranjang kosong ("Keranjang masih kosong"), bar hilang.
5. **Keranjang vs sinkronisasi.** Isi keranjang dengan 3 Es Teh Manis. Di `php artisan tinker`:
   `App\Models\Product::where('name','Es Teh Manis')->first()->update(['price'=>6000,'stock'=>2]);`
   Tarik layar katalog ke bawah → snackbar menyebut harga baru dan jumlah disesuaikan ke 2; total mengikuti Rp6.000.
6. Isi keranjang dengan Pisang Goreng, lalu `...where('name','Pisang Goreng')->first()->delete();` dan tarik layar → barisnya dikeluarkan dengan pemberitahuan.
7. Pindah ke tab Pengaturan lalu kembali → isi keranjang dan filter pencarian tetap.

### 9. Tahap 10 — Transaksi lokal (Bayar)

Tidak ada paket baru (`uuid` sudah terpasang), tidak ada perubahan backend, skema
SQLite/MySQL, maupun kontrak API. Salin ulang folder `mobile/` ke `kasir_kantin`
(timpa file yang sama) dan `README.md` ke akar repositori.

**File baru:** seluruh `lib/features/transactions/` (`domain/` berisi `PaymentMethod`,
`SyncStatus`, `CheckoutLine`, `LocalTransaction`, `CheckoutException`,
`TransactionRepository`; `data/transaction_local_data_source.dart` dan
`transaction_repository_impl.dart`; `presentation/bloc/checkout_*.dart`;
`presentation/widgets/checkout_sheet.dart`) dan tesnya di `test/features/transactions/`.

**File berubah (timpa):** `lib/main.dart` dan `lib/app/app.dart` (menyediakan
`TransactionRepository`), `cart_sheet.dart` (tombol **Bayar**, dan CatalogBloc ikut
diteruskan ke sheet), `catalog_bloc.dart` + `catalog_event.dart` (event
`CatalogLocalReloaded`), serta `cart_widgets_test.dart` dan `catalog_bloc_test.dart`.

**Alur (AGENTS.md §12, DESIGN.md §17–18):** Keranjang → **Bayar** → sheet *Pembayaran*
(Total Pembayaran, metode **Tunai | QRIS**, ringkasan) → **Bayar Sekarang** → *Transaksi
berhasil disimpan · Belum tersinkron* + nomor invoice → **Selesai**.

**Yang terjadi saat Bayar Sekarang** — semuanya di SATU transaksi SQLite, jadi berhasil
bersama atau batal bersama:
1. Setiap produk dibaca ULANG dari SQLite (bukan dipercaya dari keranjang).
2. Ditolak bila produk hilang/nonaktif, harga di SQLite berbeda dari yang dilihat kasir,
   atau jumlah melebihi stok lokal saat itu. Pesan ditampilkan di sheet dan keranjang
   tidak berubah.
3. Baris `transactions` (`pending`), baris `transaction_items` (snapshot nama dan harga),
   dan pengurangan stok lokal ditulis bersama.
4. Baru setelah itu keranjang dikosongkan dan katalog membaca ulang stok dari SQLite.

**Keputusan:**
- **Tanpa server.** Tahap ini tidak memanggil API sama sekali; sukses berarti sudah di
  SQLite. Karena belum ada pengiriman, hasilnya selalu "Belum tersinkron" sampai tahap
  11–13. Ini bukan galat dan tidak ditampilkan sebagai gagal.
- **Ketuk ganda aman.** Tombol nonaktif saat menyimpan, dan BLoC mengabaikan pengiriman
  kedua; sheet tidak bisa ditutup di tengah penyimpanan.
- **Nomor invoice** `INV-yyyyMMdd-XXXXXX` (tanggal lokal + 6 karakter pertama UUID).
  Kolom `invoice_number` UNIQUE; bila bertabrakan dicoba lagi dengan UUID baru (maks. 3
  kali). Invoice hanya rujukan manusia; idempotensi tetap memakai `local_uuid`.
- **Stok tidak "kembali" saat sinkronisasi katalog.** Server belum tahu penjualan ini,
  jadi stok lokal = stok server − transaksi `pending/syncing/failed` (aturan dari tahap 8).
- **QRIS** hanya pencatatan metode; tidak ada gerbang pembayaran (AGENTS.md §20). Sheet
  mengingatkan kasir memastikan pembayaran diterima dulu.
- Belum ada kolom uang diterima/kembalian: skema transaksi (AGENTS.md §9) tidak memilikinya.

**Catatan untuk tahap 11 (API transaksi):** `invoice_number` di server juga UNIQUE. Bila
dua perangkat menghasilkan invoice yang sama, server tidak boleh menolak transaksi yang
sah; tentukan perilakunya (mis. server memberi akhiran) sebelum menulis endpoint.
Pengurangan stok di server memakai Eloquent (`decrement`/`save`), bukan `DB::table`,
agar `updated_at` berubah dan sinkronisasi inkremental katalog mengambilnya.

**Verifikasi otomatis:**
```powershell
cd C:\DIL\pos-kantin\kasir_kantin; dart format lib test; flutter analyze; flutter test
```

**Verifikasi manual di HP** (server berjalan, seeder sudah dijalankan, `.\run_dev.cmd`):
1. Catat stok awal (mis. Nasi Goreng 20, Es Teh Manis 50). Tambahkan 2 Nasi Goreng + 1 Es Teh Manis → ketuk bar keranjang → **Bayar**.
2. Sheet *Pembayaran*: Total Rp35.000, **Tunai** terpilih, ringkasan "2 × Nasi Goreng", "1 × Es Teh Manis". Tombol **Bayar Sekarang** terlihat penuh, tidak tertutup tombol navigasi.
3. Pilih **QRIS** → muncul pengingat; pilih lagi **Tunai**. Ketuk **Bayar Sekarang** → "Transaksi berhasil disimpan", "Belum tersinkron", nomor `INV-…`, Rp35.000, Tunai.
4. **Selesai** → kembali ke katalog, keranjang kosong, kartu menampilkan **Stok 18** dan **Stok 49**.
5. **Restart.** Tutup aplikasi sepenuhnya (geser dari daftar aplikasi) dan buka lagi. Setelah sinkronisasi selesai, stok TETAP 18 dan 49 walau server masih 20 dan 50.
6. **Offline.** Matikan server (atau mode pesawat), bayar satu produk dengan **QRIS** → tetap berhasil dan stok berkurang.
7. **Stok habis.** Tambahkan Kopi Susu (stok 3) sebanyak 3 dan bayar → stok menjadi 0 dan kartu menampilkan "Habis".

### 10. Tahap 12 — Kirim transaksi dan status sinkronisasi (lapisan data)

Tahap ini **belum mengubah tampilan** dan **belum mengirim apa pun otomatis**.
Isinya fondasi yang dipakai mesin sinkronisasi di Tahap 13: cara membaca transaksi
lokal, cara memindahkan statusnya dengan aman, dan cara mengirim satu transaksi ke
`POST /api/transactions`.

**Salin overlay:** folder `mobile/` di paket ke `kasir_kantin\` (timpa file yang sama).
File baru: `sync_outcome.dart`, `transaction_remote_data_source.dart`, dan tiga file
tes. File lama yang berubah: `local_transaction.dart`, `transaction_repository.dart`,
`transaction_local_data_source.dart`, `transaction_repository_impl.dart`, `main.dart`.

**Tes otomatis** (di `kasir_kantin\`):
```powershell
dart format lib test; flutter analyze; flutter test
```

**Yang ditambahkan**
- `TransactionRemoteDataSource.submit`: memanggil `POST /api/transactions`; 201 dan
  200 sama-sama berarti "sudah ada di server".
- `TransactionLocalDataSource`: baca transaksi, hitung yang belum tersinkron, dan
  pindah status `pending → syncing → synced / failed / conflict`. Setiap perpindahan
  dijaga di SQL sehingga dua pemanggil yang berbarengan tidak bisa mengirim transaksi
  yang sama (Rule 5). Tidak ada fungsi yang menghapus transaksi (Rule 6).
- `TransactionRepository.syncTransaction(uuid)`: mengirim satu transaksi dan mencatat
  hasilnya. Pemetaan galat mengikuti AGENTS.md §17:

  | Jawaban server | Status lokal | Keterangan |
  |---|---|---|
  | 201 / 200 | `synced` | `server_id` dan nomor invoice server disimpan |
  | tanpa internet, timeout, 5xx | `failed` | Pesan tersimpan; boleh dicoba lagi |
  | 409 stok kurang | `conflict` | Pesan: "Transaksi tidak dapat disinkronkan karena stok di server tidak mencukupi." + rincian produk. Stok lokal dikembalikan |
  | 422 | `conflict` | Tidak dicoba ulang terus-menerus |
  | 401 / 403 | `pending` | Bukan salah transaksi; pengirim diberi tahu `sessionExpired` |

- `recoverInterruptedSyncs()`: transaksi yang tertinggal `syncing` (aplikasi tertutup
  saat mengirim) dikembalikan ke `pending`. Dipanggil saat aplikasi mulai di Tahap 13.

**Uji manual.** Karena belum ada yang memicu pengiriman dan tab Riwayat masih kosong,
yang diuji manual hanyalah bahwa **tidak ada yang rusak** dan data bertahan:
1. `.\run_dev.cmd`, masuk, bayar satu produk (stok berkurang).
2. Tutup aplikasi sepenuhnya (geser dari daftar aplikasi), buka lagi.
3. Stok produk itu tetap berkurang, dan kasir/keranjang/pembayaran tetap berjalan
   seperti Tahap 10.

Bukti bahwa transaksi sendiri bertahan setelah aplikasi ditutup ada di tes otomatis
(`transaction_sync_status_test.dart`, grup *bertahan setelah aplikasi ditutup*), yang
memakai file database sungguhan lalu membukanya kembali.

### 11. Tahap 13 — Sinkronisasi otomatis (kirim transaksi ke server)

Mulai tahap ini transaksi yang tersimpan di HP **terkirim sendiri** ke server, dan
kasir melihat statusnya. Pembayaran tetap selesai di HP lebih dulu; kasir tidak
pernah menunggu server (AGENTS.md §12).

**Salin overlay:** folder `mobile/` di paket ke `kasir_kantin\` (timpa file yang
sama). Tidak ada perubahan backend, jadi `backend\` tidak disentuh.

**Tes otomatis** (di `kasir_kantin\`):
```powershell
dart format lib test; flutter analyze; flutter test
```
Tes baru ada di `test/features/sync/` dan `test/support/`; tiga tes lama
(`auth_gate_test`, `settings_page_test`, `checkout_sheet_test`) ikut diperbarui
karena kerangka aplikasi sekarang memiliki `SyncBloc`.

**Kapan transaksi dikirim**
- Saat kasir selesai membayar (langsung, di belakang layar).
- Saat aplikasi baru dibuka setelah masuk. Transaksi yang tertinggal `syncing`
  (aplikasi tertutup saat mengirim) dipulihkan ke `pending` dulu.
- Tiap 30 detik, dan saat aplikasi dibuka kembali dari latar belakang.
  Aplikasi tidak memantau koneksi: begitu internet kembali, transaksi terkirim
  paling lambat 30 detik kemudian.
- Tombol **Coba Lagi** di banner.

**Aturan pengiriman**
- Satu putaran pada satu waktu, dari transaksi terlama. Pengiriman ulang aman
  karena server idempoten lewat `local_uuid` (tidak ada transaksi ganda).
- Bila satu transaksi gagal karena jaringan atau server, putaran berhenti dan
  sisanya dicoba lagi di pemicu berikutnya. Tidak ada yang dihapus.
- Bila server menolak karena stok kurang (409), transaksi menjadi `conflict` dan
  **tidak** dikirim ulang. Putaran tetap lanjut ke transaksi lain.
- Setelah ada transaksi yang tersinkron atau menjadi konflik, katalog dibaca ulang
  dan ditarik dari server supaya stok di layar akurat.

**Banner status** (muncul di atas semua tab, hilang saat semuanya beres):
| Keadaan | Teks |
|---|---|
| Menunggu dikirim | `2 transaksi menunggu sinkronisasi` |
| Sedang dikirim | `Menyinkronkan 2 transaksi...` |
| Gagal dikirim | `2 transaksi belum tersinkron. Akan dicoba lagi otomatis.` + tombol Coba Lagi |
| Konflik | `1 transaksi perlu perhatian` |

Rincian konflik ada di Tahap 14 (halaman Perlu Perhatian), dan daftar transaksi
menyusul di Tahap 15. Dialog **Keluar** di Pengaturan kini memberi tahu bila masih ada
transaksi belum tersinkron; transaksinya tetap tersimpan dan terkirim setelah
masuk kembali.

#### Uji manual (±10 menit)

**Persiapan**
1. Buka terminal PowerShell di folder `backend\` dan jalankan `php artisan serve`.
   Biarkan terbuka (ini "terminal server").
2. Buka terminal PowerShell kedua di folder `backend\` (ini "terminal cek"). Perintah
   untuk melihat jumlah transaksi di server:
   ```powershell
   php artisan tinker --execute="echo App\Models\Transaction::count();"
   ```
   Jalankan, **catat angkanya** (sebut saja `N`).
3. Jalankan aplikasi di HP seperti biasa (`.\run_dev.cmd` di `kasir_kantin\`) dan masuk
   sebagai kasir.

**Skenario 1 — Online, terkirim otomatis**
1. Bayar satu produk (Tunai).
2. Hasil yang benar: banner `Menyinkronkan 1 transaksi...` sebentar (bisa terlalu
   cepat untuk terlihat), lalu **tidak ada banner**.
3. Jalankan perintah di terminal cek. Hasil yang benar: `N + 1`. Catat sebagai `N`.

**Skenario 2 — Offline lalu online (inti Tahap 13)**
1. Di terminal server tekan `Ctrl+C` untuk mematikan server.
2. Di HP bayar **dua** transaksi (produk bebas, stok cukup). Pembayaran tetap
   berhasil dengan "Transaksi berhasil disimpan".
3. Hasil yang benar: banner `2 transaksi belum tersinkron. Akan dicoba lagi otomatis.`
   (boleh sempat tampil `menunggu sinkronisasi` dulu).
4. Nyalakan server lagi: `php artisan serve` di terminal server.
5. Tunggu **sampai 30 detik** (atau ketuk **Coba Lagi**). Hasil yang benar: banner
   hilang.
6. Terminal cek. Hasil yang benar: **tepat** `N + 2` (bukan lebih, tidak ada ganda).

**Skenario 3 — Aplikasi ditutup saat ada transaksi tertunda**
1. Matikan server (`Ctrl+C`), bayar satu transaksi di HP. Banner `belum tersinkron`.
2. Tutup aplikasi sepenuhnya (geser dari daftar aplikasi).
3. Nyalakan server, buka aplikasi lagi, masuk bila diminta.
4. Hasil yang benar: banner (`1 transaksi menunggu sinkronisasi` atau
   `Menyinkronkan 1 transaksi...`) hilang dalam beberapa detik, dan terminal cek
   menunjukkan jumlah naik tepat 1.

**Skenario 4 — Peringatan saat keluar**
1. Matikan server, bayar satu transaksi (banner `belum tersinkron`).
2. Pengaturan → **Keluar**. Hasil yang benar: dialog menyebut
   `Masih ada 1 transaksi yang belum tersinkron...`. Ketuk **Batal**.
3. Nyalakan server, tunggu banner hilang.

**Skenario 5 — Konflik stok (opsional, tapi menguji aturan terpenting)**
Setelah skenario ini banner `perlu perhatian` akan tetap ada. Di Tahap 14 ia
bisa dibersihkan lewat Kirim Ulang; cara lama (hapus data) ada di akhir.
1. Matikan server. Di HP bayar **3** buah Nasi Goreng (id 1) lewat tab Kasir.
2. Di terminal cek, jadikan stok server habis:
   ```powershell
   php artisan tinker --execute="App\Models\Product::find(1)->update(['stock'=>0]);"
   ```
3. Nyalakan server dan tunggu sampai 30 detik.
4. Hasil yang benar: banner `1 transaksi perlu perhatian`, tidak ada `menunggu`,
   dan Nasi Goreng tampil **Habis**. Jumlah transaksi di server tidak bertambah.
5. Kembalikan stok server:
   ```powershell
   php artisan tinker --execute="App\Models\Product::find(1)->update(['stock'=>20]);"
   ```
6. Bersihkan data konflik di HP: Pengaturan Android → Aplikasi → Kasir Kantin →
   Penyimpanan → **Hapus data**, lalu buka aplikasi dan masuk lagi.

Bila ada hasil yang berbeda dari "hasil yang benar", salin deskripsinya (dan
teks banner yang muncul) ke chat.

### 12. Tahap 14 — Penanganan konflik

Transaksi yang ditolak server (mis. stok di server tidak cukup) berstatus
`conflict`. Mulai tahap ini kasir bisa **melihat alasannya** dan **mengirim
ulang**. Tidak ada tombol hapus atau ubah jumlah (AGENTS.md §13.4): data
transaksi selalu utuh.

**Salin overlay:** folder `mobile/` di paket ke `kasir_kantin\` (timpa). Tidak ada
perubahan backend.

**Tes otomatis** (di `kasir_kantin\`):
```powershell
dart format lib test; flutter analyze; flutter test
```
Tes baru: `conflict_bloc_test`, `conflict_page_test`, `transaction_conflict_test`.

**Yang berubah**
- Banner `1 transaksi perlu perhatian` kini bisa diketuk (ada tulisan **Lihat**).
  Ketukan membuka halaman **Perlu Perhatian**.
- Halaman itu menampilkan tiap transaksi konflik: nomor invoice, waktu, metode,
  **alasan** (mis. `... stok di server tidak mencukupi. Nasi Goreng (diminta 3,
  tersedia 0).`), daftar produk, total, dan tombol **Kirim Ulang**.
- **Kirim Ulang** mengembalikan transaksi ke `pending` (isinya tidak berubah) dan
  langsung dikirim. Bila server masih menolak, ia kembali menjadi konflik dengan
  alasan terbaru. Bila diterima, ia `synced` dan hilang dari daftar.
- Saat Kirim Ulang, stok di HP dikurangi lagi (kebalikan dari saat konflik), lalu
  katalog ditarik dari server.

#### Uji manual (±10 menit)

**Persiapan** (sama seperti Tahap 13)
1. Terminal server di `backend\`: `php artisan serve` (biarkan terbuka).
2. Terminal cek di `backend\`. Hitung transaksi di server:
   ```powershell
   php artisan tinker --execute="echo App\Models\Transaction::count();"
   ```
   Catat angkanya sebagai `N`.
3. Jalankan aplikasi di HP (`.\run_dev.cmd`) dan masuk sebagai kasir.

**Skenario 1 — Membuat konflik dan melihat alasannya**
1. Matikan server (`Ctrl+C` di terminal server).
2. Di HP, tab Kasir: bayar **3** buah Nasi Goreng (Tunai).
3. Di terminal cek, habiskan stok server:
   ```powershell
   php artisan tinker --execute="App\Models\Product::find(1)->update(['stock'=>0]);"
   ```
4. Nyalakan server (`php artisan serve`). Tunggu sampai 30 detik.
5. Hasil yang benar: banner `1 transaksi perlu perhatian` dengan tulisan **Lihat**.
6. Ketuk banner. Hasil yang benar: halaman **Perlu Perhatian** berisi satu kartu
   dengan alasan `Transaksi tidak dapat disinkronkan karena stok di server tidak
   mencukupi. Nasi Goreng (diminta 3, tersedia 0).`, item `3 × Nasi Goreng`, dan
   tombol **Kirim Ulang**.
7. Hitung transaksi di server. Hasil yang benar: tetap `N` (belum bertambah).

**Skenario 2 — Kirim Ulang saat stok masih kurang**
1. Di halaman itu ketuk **Kirim Ulang**.
2. Hasil yang benar: dalam beberapa detik kartu muncul lagi dengan alasan yang sama
   (stok server masih 0). Transaksi tidak hilang. Server tetap `N`.

**Skenario 3 — Kirim Ulang setelah stok diperbaiki**
1. Kembalikan stok server:
   ```powershell
   php artisan tinker --execute="App\Models\Product::find(1)->update(['stock'=>20]);"
   ```
2. Di halaman Perlu Perhatian ketuk **Kirim Ulang**.
3. Hasil yang benar: dalam beberapa detik kartu hilang dan halaman berisi
   `Tidak ada transaksi yang perlu perhatian`.
4. Tekan tombol kembali. Hasil yang benar: tidak ada banner sama sekali.
5. Hitung transaksi di server. Hasil yang benar: `N + 1`. Stok Nasi Goreng di
   tab Kasir menjadi **17**.

**Skenario 3b — Konflik bertahan setelah aplikasi ditutup** (bisa dilakukan sebelum
skenario 3)
1. Dari kondisi akhir skenario 2, tutup aplikasi sepenuhnya lalu buka lagi dan masuk.
2. Hasil yang benar: banner `1 transaksi perlu perhatian` masih ada dan kartunya
   tetap berisi alasan yang sama.

Bila ada hasil yang berbeda dari "hasil yang benar", salin deskripsinya (dan teks
yang muncul) ke chat.

### 13. Tahap 15 — Riwayat transaksi dan struk yang jujur

Tab **Riwayat** kini berisi semua transaksi di HP (apa pun statusnya), terbaru di
atas, dan bisa dibuka tanpa internet. Layar struk setelah pembayaran tidak lagi
selalu bertuliskan "Belum tersinkron": statusnya **mengikuti keadaan sebenarnya**.

**Salin overlay:** folder `mobile/` di paket ke `kasir_kantin\` (timpa). Tidak ada
perubahan backend.

**Tes otomatis** (di `kasir_kantin\`):
```powershell
dart format lib test; flutter analyze; flutter test
```
Tes baru: `history_bloc_test`, `history_page_test`. Tes yang diperluas:
`checkout_bloc_test`, `checkout_sheet_test`, `transaction_conflict_test`.

**Yang berubah**
- Tab **Riwayat**: satu kartu per transaksi berisi nomor invoice, **status**, waktu,
  metode, ringkasan produk, dan total. Ketuk kartu untuk membuka **Detail Transaksi**.
- Label status (DESIGN.md §20), selalu ikon + teks:
  `Menunggu sinkronisasi` · `Menyinkronkan...` · `Tersinkron` ·
  `Gagal disinkronkan` · `Perlu perhatian`.
- Struk setelah **Bayar Sekarang** tetap berjudul `Transaksi berhasil disimpan`,
  lalu status di bawahnya berubah sendiri selagi struk terbuka. Transaksi yang
  gagal terkirim atau konflik menampilkan alasannya.
- Riwayat dan detail ikut berubah otomatis saat sinkronisasi berjalan.
- Hanya membaca: tidak ada tombol hapus atau ubah (AGENTS.md Rule 6). Mengirim ulang
  konflik tetap lewat banner `perlu perhatian` di bagian atas layar (Tahap 14).

#### Uji manual (±15 menit)

**Persiapan**
1. Terminal server di `backend\`: `php artisan serve` (biarkan terbuka).
2. Terminal cek di `backend\`. Hitung transaksi di server dan catat angkanya
   sebagai `N`:
   ```powershell
   php artisan tinker --execute="echo App\Models\Transaction::count();"
   ```
3. Jalankan aplikasi di HP (`.\run_dev.cmd`) dan masuk sebagai kasir.

**Skenario 1 — Riwayat terisi dan bisa dibuka**
1. Ketuk tab **Riwayat**.
2. Hasil yang benar: daftar transaksi dari tahap-tahap sebelumnya, yang terbaru di
   paling atas. Di bawah judul ada tulisan `X transaksi`. Tiap kartu punya
   status (kebanyakan `Tersinkron`).
3. Ketuk satu kartu. Hasil yang benar: muncul **Detail Transaksi** berisi invoice,
   waktu, metode, produk, dan total. Ketuk ✕ untuk menutup.

**Skenario 2 — Bayar saat server mati: status di struk**
1. Matikan server (`Ctrl+C` di terminal server).
2. Tab **Kasir**: bayar 1 buah Nasi Goreng (Tunai).
3. Hasil yang benar di struk: tulisan `Transaksi berhasil disimpan`. Dalam beberapa
   detik status berubah menjadi `Gagal disinkronkan` dan ada kalimat `... Akan
   dicoba lagi otomatis.` (Sebentar sebelumnya boleh tampil `Menunggu
   sinkronisasi` atau `Menyinkronkan...`.) Transaksi tidak dinyatakan gagal.
4. Ketuk **Selesai**, lalu buka tab **Riwayat**.
5. Hasil yang benar: transaksi tadi ada paling atas dengan status yang sama.

**Skenario 3 — Server hidup lagi: status berubah sendiri**
1. Tetap di tab **Riwayat**. Nyalakan server (`php artisan serve`).
2. Tunggu sampai 30 detik tanpa menyentuh apa pun.
3. Hasil yang benar: status kartu berubah menjadi `Tersinkron`, dan banner
   `transaksi belum tersinkron` di atas layar hilang.
4. Hitung transaksi di server. Hasil yang benar: `N + 1`.

**Skenario 4 — Struk berubah saat masih terbuka**
1. Server hidup. Tab **Kasir**: bayar 1 produk apa saja (mis. Es Teh).
2. Jangan tekan apa pun. Hasil yang benar: dalam beberapa detik status di struk
   berubah menjadi `Tersinkron`.
3. Ketuk **Selesai**. Hitung transaksi di server. Hasil yang benar: `N + 2`.

**Skenario 5 — Konflik terlihat di Riwayat**
1. Matikan server. Tab **Kasir**: bayar **3** buah Nasi Goreng (Tunai). Ketuk
   **Selesai**.
2. Di terminal cek, habiskan stok server:
   ```powershell
   php artisan tinker --execute="App\Models\Product::find(1)->update(['stock'=>0]);"
   ```
3. Nyalakan server. Tunggu sampai 30 detik.
4. Buka tab **Riwayat**. Hasil yang benar: kartu 3 Nasi Goreng berstatus `Perlu
   perhatian`.
5. Ketuk kartunya. Hasil yang benar: Detail Transaksi menampilkan alasan
   `... stok di server tidak mencukupi. Nasi Goreng (diminta 3, tersedia 0).`
   dan `Transaksi tetap tersimpan`.
6. Kembalikan stok server, lalu tutup detail:
   ```powershell
   php artisan tinker --execute="App\Models\Product::find(1)->update(['stock'=>20]);"
   ```
7. Ketuk banner `1 transaksi perlu perhatian` di atas layar, lalu **Kirim Ulang**.
8. Kembali ke tab **Riwayat**. Hasil yang benar (dalam beberapa detik): kartu
   itu berstatus `Tersinkron`. Server `N + 3`.

**Skenario 6 — Riwayat bertahan setelah aplikasi ditutup**
1. Tutup aplikasi sepenuhnya, buka lagi, masuk.
2. Ketuk tab **Riwayat**. Hasil yang benar: semua transaksi tadi masih ada dengan
   status yang sama.

Bila ada hasil yang berbeda dari "hasil yang benar", salin deskripsinya (dan teks
yang muncul) ke chat.

### 14. Tahap 16 — Dashboard Filament untuk owner

Owner kini bisa mengelola **kategori** dan **produk (termasuk stok)** serta melihat
**transaksi** dari dashboard web. Tahap ini hanya menyentuh `backend\`.
Laporan dan statistik **bukan** bagian tahap ini (Tahap 17 dan 18).

**Salin overlay:** isi folder `backend/` di paket ke `backend\` (timpa). Tidak ada
paket Composer baru dan tidak ada migrasi. Lalu bersihkan cache:
```powershell
cd C:\DIL\pos-kantin\backend
php artisan optimize:clear
```

**Tes otomatis** (di `backend\`):
```powershell
php artisan test
```
Tes baru ada di `tests/Feature/Admin/` (27 tes): akses, kategori, produk, transaksi,
service stok, dan ringkasan dashboard.

**Yang berubah**
- Menu dashboard: **Dashboard · Produk · Kategori · Transaksi**, semuanya berbahasa
  Indonesia. Waktu tampil dalam WIB.
- **Dashboard:** tiga kartu "Hari Ini" (Omzet, Jumlah Transaksi, Stok Perlu Perhatian).
  Widget bawaan Filament yang berbahasa Inggris dihapus.
- **Kategori:** tambah, ubah nama, hapus (soft delete), pulihkan. Kategori yang
  masih punya produk **tidak bisa dihapus**.
- **Produk:** tambah (dengan foto dan stok awal), ubah nama/harga/kategori/foto/status
  aktif, hapus (soft delete), pulihkan, filter, dan aksi **Ubah Stok**.
  Stok **tidak** ada di formulir ubah. Ubah Stok memakai selisih (lihat Keputusan 26).
- **Transaksi:** daftar dan detail, **hanya baca**. Tidak ada tombol tambah, ubah,
  atau hapus. Filter metode pembayaran dan rentang tanggal.

#### Uji manual (±20 menit)

**Persiapan**
1. Terminal server di `backend\`: `php artisan serve` (biarkan terbuka).
2. Pastikan katalog ada. Bila masih kosong:
   ```powershell
   php artisan db:seed --class=CatalogSeeder
   ```
3. Pastikan `php artisan storage:link` pernah dijalankan (supaya foto produk tampil).
4. Jalankan aplikasi di HP (`.\run_dev.cmd`) dan masuk sebagai kasir.

**Skenario 1 — Masuk sebagai owner**
1. Di browser laptop buka `http://127.0.0.1:8000/admin`.
2. Masuk dengan akun owner (`owner@kantin.test`).
3. Hasil yang benar: menu kiri berisi **Dashboard, Produk, Kategori, Transaksi**.
   Dashboard menampilkan judul **Hari Ini** dengan tiga kartu: **Omzet**,
   **Jumlah Transaksi**, **Stok Perlu Perhatian**. Tidak ada teks berbahasa Inggris
   kecuali nama merek.
4. Keluar, lalu coba masuk dengan akun kasir (`kasir@kantin.test`).
   Hasil yang benar: tidak bisa masuk. Filament menampilkan pesan umum
   **Kredensial yang diberikan tidak dapat ditemukan.** (sengaja tidak membedakan
   "akun tidak ada" dan "bukan owner", supaya tidak membocorkan akun mana yang valid).
   Masuk lagi sebagai owner untuk skenario berikutnya.

**Skenario 2 — Kategori**
1. Buka **Kategori** → **Tambah Kategori**. Isi `Kategori Uji` → simpan.
   Hasil yang benar: muncul di daftar dengan **Jumlah Produk = 0**.
2. Ketuk **Ubah** pada `Kategori Uji`, ganti nama menjadi `Kategori Uji 2` → simpan.
   Hasil yang benar: nama berubah.
3. Ketuk **Hapus** pada `Makanan`. Hasil yang benar: muncul peringatan
   **Kategori tidak dapat dihapus** dan `Makanan` tetap ada.
4. Ketuk **Hapus** pada `Kategori Uji 2` lalu konfirmasi **Hapus Kategori**.
   Hasil yang benar: kategori hilang dari daftar.
5. Buka filter **Kategori terhapus**, pilih tampilkan terhapus. Hasil yang benar:
   `Kategori Uji 2` ada di sana dengan tombol **Pulihkan**.

**Skenario 3 — Tambah produk dan lihat di HP**
1. Buka **Produk** → **Tambah Produk**. Isi: kategori `Minuman`, nama `Teh Tarik Uji`,
   harga `7000`, stok awal `4`, unggah satu foto, status aktif → simpan.
2. Hasil yang benar: produk muncul di daftar dengan stok **Menipis (4)**.
3. Di HP, **tutup aplikasi sepenuhnya lalu buka lagi** dan masuk.
4. Hasil yang benar: tab Kasir menampilkan `Teh Tarik Uji` Rp7.000, dengan tulisan
   `Stok tersisa 4`.

**Skenario 4 — Ubah Stok**
1. Di daftar Produk, ketuk **Ubah Stok** pada `Teh Tarik Uji`. Isi `10` → simpan.
   Hasil yang benar: stok menjadi **14** (angka stok sebelumnya ditambah 10) dan
   badge berubah menjadi hijau.
2. Ketuk **Ubah Stok** lagi, isi `-20` → simpan.
   Hasil yang benar: muncul **Stok tidak diubah** dengan alasan stok tidak boleh
   kurang dari 0. Stok tetap 14.
3. Ketuk **Ubah Stok**, isi `0`. Hasil yang benar: formulir menolak angka 0.
4. Ketuk **Ubah** pada produk yang sama. Hasil yang benar: formulir **tidak**
   punya kolom stok.

**Skenario 5 — Hapus dan filter produk**
1. Aktifkan filter **Stok menipis atau habis**. Hasil yang benar: hanya produk
   dengan stok 5 atau kurang yang tampil (mis. Batagor **Habis**, Kopi Susu).
2. Matikan filter. Ketuk **Hapus** pada `Teh Tarik Uji`.
   Hasil yang benar: ada konfirmasi **Hapus Produk?** dengan tulisan
   `Riwayat transaksi lama tetap aman`. Setelah konfirmasi, produk hilang dari daftar.
3. Di HP, tutup aplikasi lalu buka lagi. Hasil yang benar: `Teh Tarik Uji` tidak
   tampil lagi di tab Kasir.

**Skenario 6 — Transaksi dari HP muncul di dashboard**
1. Di HP, tab Kasir: bayar 2 buah `Es Teh Manis` dengan **Tunai**. Tunggu status
   `Tersinkron` di tab Riwayat (maksimal 30 detik).
2. Di dashboard buka **Transaksi**. Hasil yang benar: transaksi tadi paling atas,
   dengan nomor invoice yang **sama** seperti di HP, kasir, metode **Tunai**, dan
   total Rp10.000. Jam sesuai jam di HP (WIB).
3. Ketuk **Lihat**. Hasil yang benar: rincian menampilkan `Es Teh Manis`,
   jumlah 2, harga Rp5.000, subtotal Rp10.000. Tidak ada tombol ubah atau hapus.
4. Buka filter **Metode Pembayaran** → **QRIS**. Hasil yang benar: transaksi tunai
   tadi tidak tampil. Kembalikan filter ke semua.
5. Buka **Dashboard**. Hasil yang benar: **Omzet** dan **Jumlah Transaksi** hari ini
   sudah bertambah sesuai transaksi tadi.

**Skenario 7 — Harga lama tidak berubah (snapshot)**
1. Di **Produk**, ubah harga `Es Teh Manis` dari 5000 menjadi `6000` → simpan.
2. Buka lagi detail transaksi dari Skenario 6.
3. Hasil yang benar: harga di rincian transaksi tetap **Rp5.000** (bukan Rp6.000).
4. Kembalikan harga `Es Teh Manis` ke `5000`.

Bila ada hasil yang berbeda dari "hasil yang benar", salin deskripsinya (dan teks
yang muncul) ke chat.

### 15. Tahap 17 — Laporan penjualan untuk owner

Halaman **Laporan** di dashboard: owner memilih rentang tanggal, lalu melihat omzet,
jumlah transaksi, rata-rata per transaksi, daftar transaksi, dan rincian per metode
pembayaran (AGENTS.md §25). Tahap ini hanya menyentuh `backend\`. Grafik, tren, dan
produk terlaris **bukan** bagian tahap ini (Tahap 18, Statistik).

**Salin overlay:** isi folder `backend/` di paket ke `backend\` (timpa). Tidak ada
paket Composer baru dan tidak ada migrasi. Lalu:
```powershell
cd C:\DIL\pos-kantin\backend
php artisan optimize:clear
```

**Tes otomatis** (di `backend\`):
```powershell
php artisan test
```
Tes baru: `tests/Feature/Admin/LaporanTest.php` (7 tes: total, rata-rata, rincian metode,
periode kosong, batas tanggal WIB, tanggal terbalik/tidak valid, akses owner/kasir) dan
`AdminAccessTest` diperluas dengan `/admin/laporan`.

**Yang berubah**
- Menu baru **Laporan** (urutan: Dashboard · Produk · Kategori · Transaksi · Laporan).
- Filter **Dari tanggal** dan **Sampai tanggal**. Bawaan: tanggal 1 bulan ini sampai
  hari ini (WIB). Kedua tanggal ikut dihitung penuh.
- Isi halaman berurutan: Ringkasan (Total Omzet, Jumlah Transaksi, Rata-rata per
  Transaksi) → Daftar Transaksi → Rincian Metode Pembayaran (Tunai dan QRIS: total,
  jumlah transaksi, persen dari omzet).
- Hanya transaksi yang **sudah diterima server** yang dihitung.

#### Uji manual (±15 menit)

**Persiapan**
1. Terminal server di `backend\`: `php artisan serve`.
2. Jalankan aplikasi di HP (`.\run_dev.cmd`), masuk sebagai kasir.
3. Di HP buat 2 transaksi hari ini: satu **Tunai** dan satu **QRIS** (barang bebas).
   Tunggu keduanya `Tersinkron` di tab Riwayat.
4. Di browser buka `http://127.0.0.1:8000/admin` dan masuk sebagai owner.

**Skenario 1 — Halaman Laporan dan nilai bawaan**
1. Klik menu **Laporan**.
2. Hasil yang benar: ada kotak **Filter Tanggal** (Dari tanggal = tanggal 1 bulan ini,
   Sampai tanggal = hari ini), judul **Ringkasan: 1 ... - ...** sesuai rentang itu,
   tiga kartu ringkasan, tabel **Daftar Transaksi**, lalu **Rincian Metode Pembayaran**.
   Tidak ada teks berbahasa Inggris.

**Skenario 2 — Angka cocok dengan Dashboard**
1. Ubah **Dari tanggal** dan **Sampai tanggal** keduanya menjadi hari ini.
2. Hasil yang benar: **Total Omzet** dan **Jumlah Transaksi** sama dengan kartu
   **Omzet** dan **Jumlah Transaksi** di halaman Dashboard (Hari Ini).
3. **Rata-rata per Transaksi** = Total Omzet dibagi Jumlah Transaksi (dibulatkan).
4. Tabel hanya berisi transaksi hari ini, yang terbaru di atas.

**Skenario 3 — Rincian metode pembayaran**
1. Masih rentang hari ini, lihat **Rincian Metode Pembayaran**.
2. Hasil yang benar: kartu **Tunai** dan **QRIS** masing-masing menampilkan total
   dan teks seperti `1 transaksi · 40% dari omzet`. Total Tunai + total QRIS =
   Total Omzet, dan jumlah transaksinya juga cocok.

**Skenario 4 — Periode tanpa transaksi**
1. Pilih rentang yang pasti kosong, mis. `1/1/2020` sampai `31/1/2020`.
2. Hasil yang benar: semua kartu menampilkan **Rp0** / **0**, rata-rata Rp0, persen
   0%, dan tabel berisi **Tidak ada transaksi pada periode ini**. Tidak ada error.

**Skenario 5 — Buka detail dari daftar**
1. Kembalikan rentang ke hari ini. Ketuk satu baris transaksi di tabel.
2. Hasil yang benar: terbuka halaman detail transaksi yang sama seperti di menu
   **Transaksi** (hanya baca), dengan nomor invoice yang sama seperti di HP.

**Skenario 6 — Transaksi konflik diselesaikan lewat Ubah Stok → Kirim Ulang**
Ini menunjukkan jalan keluar konflik yang disepakati (Keputusan 17 dan 33): owner
menambah stok, kasir mengirim ulang.
1. Catat **Jumlah Transaksi** hari ini di Laporan (`J`).
2. Matikan server (`Ctrl+C`). Di HP bayar **3** buah `Nasi Goreng` (Tunai).
3. Di terminal `backend\`, habiskan stok server:
   ```powershell
   php artisan tinker --execute="App\Models\Product::where('name','Nasi Goreng')->update(['stock'=>0]);"
   ```
4. Nyalakan server lagi. Tunggu sampai 30 detik. Hasil yang benar: banner
   `1 transaksi perlu perhatian` di HP.
5. Di dashboard buka **Laporan**, muat ulang halaman. Hasil yang benar: Jumlah
   Transaksi masih `J` (transaksi konflik belum ada di server).
6. Di dashboard buka **Produk**, ketuk **Ubah Stok** pada `Nasi Goreng`, isi
   **Perubahan Stok** `20`, **Simpan**. Hasil yang benar: stok menjadi 20.
7. Di HP buka banner → **Perlu Perhatian** → **Kirim Ulang**. Hasil yang benar:
   kartu hilang dalam beberapa detik.
8. Muat ulang **Laporan**. Hasil yang benar: Jumlah Transaksi menjadi `J + 1`, dan
   transaksi Nasi Goreng tadi muncul di tabel.

**Skenario 7 — Tanggal terbalik tidak merusak laporan**
1. Isi **Dari tanggal** = hari ini dan **Sampai tanggal** = tanggal 1 bulan ini.
2. Hasil yang benar: halaman tidak error; rentang otomatis dibaca dari yang lebih
   awal ke yang lebih akhir (judul Ringkasan menampilkan rentang yang benar).

Bila ada hasil yang berbeda dari "hasil yang benar", salin deskripsinya (dan teks
yang muncul) ke chat.

### 16. Tahap 18 — Statistik untuk owner

Halaman **Statistik** di dashboard menjawab tiga pertanyaan (DESIGN.md §30): *apa yang
paling laku*, *bagaimana performa akhir-akhir ini*, dan *produk apa yang perlu
diperhatikan*. Tahap ini hanya menyentuh `backend\`. Statistik **tidak** memakai
rentang tanggal bebas: itu tugas Laporan (AGENTS.md §25), jadi isinya tidak dobel.

**Salin overlay:** isi folder `backend/` di paket ke `backend\` (timpa). Tidak ada
paket Composer baru, tidak ada migrasi. Lalu:
```powershell
cd C:\DIL\pos-kantin\backend
php artisan optimize:clear
```

**Tes otomatis** (di `backend\`):
```powershell
php artisan test
```
Tes baru: `tests/Feature/Admin/StatistikTest.php` (11 tes: periode, tren dan hari kosong,
perbandingan, hari/jam tersibuk, produk terlaris, produk terhapus, stok perhatian,
akses, render halaman) dan `AdminAccessTest` diperluas dengan `/admin/statistik`.

**Yang berubah**
- Menu baru **Statistik** (urutan: Dashboard · Produk · Kategori · Transaksi · Laporan · Statistik).
- Pilihan **Periode**: 7 hari terakhir (bawaan) atau 30 hari terakhir, dihitung mundur
  dari hari ini (WIB).
- **Performa:** Omzet N hari terakhir beserta perbandingan dengan N hari sebelumnya
  (naik/turun dalam persen), **Hari Tersibuk**, dan **Jam Tersibuk**.
- **Tren Omzet Harian:** grafik garis omzet per hari. Hari tanpa penjualan tampil Rp0.
- **Produk Terlaris:** 5 produk dengan jumlah terjual terbanyak, beserta omzetnya.
- **Stok Perlu Perhatian:** daftar produk aktif yang **Habis** atau **Menipis** (stok 5
  ke bawah).
- Hanya transaksi yang **sudah diterima server** yang dihitung.

#### Uji manual (±20 menit)

**Persiapan**
1. Terminal server di `backend\`: `php artisan serve`.
2. Jalankan aplikasi di HP (`.\run_dev.cmd`), masuk sebagai kasir.
3. Di browser buka `http://127.0.0.1:8000/admin`, masuk sebagai owner, lalu klik
   **Statistik**. Catat dua angka untuk Skenario 2: nilai **Terjual** untuk
   `Nasi Goreng` di tabel **Produk Terlaris** (`A`; bila `Nasi Goreng` belum ada di
   tabel, `A = 0`).

**Skenario 1 — Tampilan halaman**
1. Di halaman **Statistik** lihat urutan isi.
2. Hasil yang benar: kotak **Periode** (pilihan `7 hari terakhir`), judul
   **Performa: ... - ...** (rentang 7 hari sampai hari ini), tiga kartu
   (**Omzet 7 Hari Terakhir**, **Hari Tersibuk**, **Jam Tersibuk**), grafik
   **Tren Omzet Harian** dengan 7 titik, lalu dua tabel berdampingan
   **Produk Terlaris** dan **Stok Perlu Perhatian**. Tidak ada teks berbahasa Inggris.
3. Hasil yang benar: **Jam Tersibuk** berformat seperti `12.00 - 13.00`, dan
   **Hari Tersibuk** berupa nama hari (mis. `Kamis`).

**Skenario 2 — Produk terlaris mengikuti penjualan**
1. Di HP, tab Kasir: bayar **2** buah `Nasi Goreng` dengan **Tunai**. Tunggu status
   `Tersinkron` di tab Riwayat (maksimal 30 detik).
2. Di dashboard, muat ulang halaman **Statistik**.
3. Hasil yang benar: **Terjual** untuk `Nasi Goreng` menjadi `A + 2`. Titik hari ini
   di grafik tren dan **Omzet 7 Hari Terakhir** ikut naik sesuai penjualan tadi
   (2 × harga Nasi Goreng).

**Skenario 3 — Ganti periode**
1. Ubah **Tampilkan** menjadi `30 hari terakhir`.
2. Hasil yang benar: judul **Performa** menampilkan rentang 30 hari, kartu berubah
   menjadi **Omzet 30 Hari Terakhir**, grafik tren berisi 30 titik, dan omzet 30 hari
   tidak lebih kecil dari omzet 7 hari tadi.
3. Kembalikan ke `7 hari terakhir`. Hasil yang benar: tampilan kembali seperti
   Skenario 1.

**Skenario 4 — Stok perlu perhatian**
1. Di terminal `backend\`, buat stok menipis:
   ```powershell
   php artisan tinker --execute="App\Models\Product::where('name','Nasi Goreng')->update(['stock'=>3]);"
   ```
2. Muat ulang **Statistik**. Hasil yang benar: `Nasi Goreng` ada di **Stok Perlu
   Perhatian** dengan stok `3` dan status **Menipis** (kuning).
3. Habiskan stok:
   ```powershell
   php artisan tinker --execute="App\Models\Product::where('name','Nasi Goreng')->update(['stock'=>0]);"
   ```
   Muat ulang. Hasil yang benar: stok `0`, status **Habis** (merah), dan `Nasi Goreng`
   berada di atas produk yang hanya menipis.
4. Kembalikan stok:
   ```powershell
   php artisan tinker --execute="App\Models\Product::where('name','Nasi Goreng')->update(['stock'=>20]);"
   ```
   Muat ulang. Hasil yang benar: `Nasi Goreng` hilang dari daftar. Bila tidak ada produk
   lain yang menipis, tabel menampilkan **Semua stok aman**.
5. Buka **Dashboard**. Hasil yang benar: kartu **Stok Perlu Perhatian** menghitung
   produk yang sama dengan tabel tadi (jumlah habis + menipis).

**Skenario 5 — Statistik berbeda dari Laporan**
1. Buka **Laporan**. Hasil yang benar: ada filter **Dari tanggal / Sampai tanggal**,
   daftar transaksi, dan rincian Tunai/QRIS; **tidak** ada grafik atau produk terlaris.
2. Buka **Statistik**. Hasil yang benar: ada grafik tren, produk terlaris, dan stok;
   **tidak** ada filter tanggal bebas dan tidak ada daftar transaksi.

Bila ada hasil yang berbeda dari "hasil yang benar", salin deskripsinya (dan teks
yang muncul) ke chat.

### 17. Tahap 19 — Pemolesan UI

Dua bagian: **dashboard** (tema teal sesuai DESIGN.md) dan **aplikasi kasir** (hasil
audit terhadap DESIGN.md, lalu perbaikan gerak dan aksesibilitas). Tidak ada fitur
baru, tidak ada perubahan alur, API, atau database.

**Hasil audit Flutter.** Sudah sesuai DESIGN.md dan tidak diubah: seluruh teks
berbahasa Indonesia, area sentuh minimal 44–48, status stok berupa ikon + teks
(bukan warna saja), tombol bayar tidak bisa diketuk dua kali, katalog memakai skeleton,
dan produk habis tidak bisa dipilih. Yang kurang dan diperbaiki: **gerak** (§38) dan
**aksesibilitas** (§37).

**Salin overlay:** isi folder `backend/` ke `backend\` dan isi folder `mobile/` ke
`kasir_kantin\` (timpa).

**Langkah backend** (satu kali, butuh Node.js dan internet):
```powershell
cd C:\DIL\pos-kantin\backend
npm install
npm run build
php artisan optimize:clear
```
`npm install` menambah paket font Inter dan membuat `package-lock.json` (ikut di-commit).
Hasil build ada di `public\build` dan **tidak** masuk Git, jadi `npm run build` harus
diulang di setiap komputer baru atau setelah `theme.css` berubah.

**Tes otomatis**
```powershell
cd C:\DIL\pos-kantin\backend
php artisan test

cd C:\DIL\pos-kantin\kasir_kantin
flutter analyze
flutter test
```
Tes baru: `test/core/widgets/value_pulse_test.dart` (4 tes) dan
`test/features/products/presentation/product_card_test.dart` (3 tes). Tes Laravel
sekarang mematikan Vite di `tests/TestCase.php`, jadi tidak bergantung pada hasil build.

**Yang berubah**
- Dashboard: bilah atas dan sidebar teal tua (`#0F4540`), menu aktif teal sekunder
  (`#287B72`) dengan garis coral kecil di kiri, latar halaman `#F7F8F5`, judul halaman
  teal tua, grafik tren berwarna teal, font **Inter** (disimpan lokal, tanpa internet).
  Mode gelap dimatikan.
- Aplikasi kasir: bilah Keranjang muncul dan hilang dengan transisi singkat; total
  keranjang dan angka jumlah (+/-) membesar sebentar saat berubah; ikon centang pada
  layar sukses membesar sekali; kartu produk dibacakan sebagai tombol (nonaktif bila
  habis) oleh pembaca layar.

#### Uji manual (±20 menit)

**Persiapan**
1. Selesaikan "Langkah backend" di atas, lalu jalankan `php artisan serve`.
2. Jalankan aplikasi di HP (`.\run_dev.cmd`), masuk sebagai kasir.

**Skenario 1 — Halaman masuk dashboard**
1. Buka `http://127.0.0.1:8000/admin/login` (bila sudah masuk, keluar dulu).
2. Hasil yang benar: latar krem muda, tulisan **Kasir Kantin** berwarna teal tua,
   kartu masuk berbentuk membulat, tombol **Masuk** berwarna teal. Huruf tampil dengan
   font Inter (bentuk huruf bersih dan seragam, bukan font sistem).

**Skenario 2 — Sidebar dan menu aktif**
1. Masuk sebagai owner.
2. Hasil yang benar: bilah atas dan sidebar sama-sama **teal tua**; nama menu
   (Dashboard, Produk, Kategori, Transaksi, Laporan, Statistik) berwarna putih redup;
   menu yang sedang dibuka berlatar teal lebih terang dengan teks putih tebal dan
   garis oranye kecil di sisi kiri.
3. Klik **Laporan**, lalu **Statistik**. Hasil yang benar: penanda menu aktif ikut
   berpindah. Arahkan kursor ke menu lain: latarnya menyala tipis.

**Skenario 3 — Isi halaman**
1. Buka **Statistik** dan **Dashboard**.
2. Hasil yang benar: judul halaman teal tua; kartu putih di atas latar krem; garis
   grafik **Tren Omzet Harian** berwarna teal; tombol aksi utama berwarna teal (bukan
   oranye); tidak ada tombol pengganti mode gelap.

**Skenario 4 — Layar sempit**
1. Kecilkan lebar jendela browser sampai di bawah ±1000 piksel.
2. Hasil yang benar: sidebar tersembunyi dan tombol menu (☰) putih muncul di bilah atas.
   Klik tombol itu: sidebar teal tua terbuka dan semua menu terbaca.

**Skenario 5 — Bilah Keranjang dan umpan balik jumlah (HP)**
1. Tab **Kasir**: ketuk `Nasi Goreng`.
2. Hasil yang benar: bilah **Keranjang** muncul dari bawah dengan transisi singkat
   (±0,2 detik), bukan tiba-tiba.
3. Ketuk `Nasi Goreng` lagi beberapa kali. Hasil yang benar: tiap kali, total rupiah
   di bilah membesar sedikit lalu kembali normal. Tidak memantul dan tidak menunda.
4. Buka bilah Keranjang, ketuk **+** dan **−**. Hasil yang benar: angka jumlah
   membesar sebentar tiap berubah.
5. Ketuk **Kosongkan** → **Kosongkan**. Hasil yang benar: bilah Keranjang
   menghilang dengan transisi singkat.

**Skenario 6 — Layar sukses**
1. Isi keranjang, ketuk **Bayar**, pilih **Tunai**, **Bayar Sekarang**.
2. Hasil yang benar: ikon centang hijau membesar sekali (±0,2 detik) lalu diam;
   tombol **Selesai** langsung bisa diketuk. Alur bayar tidak terasa lebih lambat.

**Skenario 7 — Produk habis dan pembaca layar (opsional)**
1. Habiskan stok satu produk (mis. lewat Ubah Stok di dashboard), lalu tarik layar
   katalog ke bawah. Hasil yang benar: kartunya bertulisan **Habis** dan tidak bereaksi
   saat diketuk.
2. (Opsional) Nyalakan TalkBack di HP dan sentuh kartu produk. Hasil yang benar:
   dibacakan sebagai tombol beserta nama, harga, dan stok; kartu produk habis
   dibacakan sebagai tidak aktif. Matikan TalkBack setelahnya.

Bila ada hasil yang berbeda dari "hasil yang benar", salin deskripsinya (dan teks
yang muncul) ke chat. Bila `npm run build` gagal, salin seluruh pesan galatnya.

### 18. Tahap 20 — Pengujian akhir dan integrasi

Tahap penutup: memastikan semua lapisan bekerja **bersama**, sesuai daftar uji
AGENTS.md §27. Tidak ada fitur baru dan **tidak ada kode aplikasi yang berubah**;
overlay hanya berisi dua tes alur lengkap.

**Salin overlay:** isi folder `backend/` ke `backend\` dan isi folder `mobile/` ke
`kasir_kantin\`.

**Tes otomatis**
```powershell
cd C:\DIL\pos-kantin\backend
php artisan test

cd C:\DIL\pos-kantin\kasir_kantin
flutter analyze
flutter test
```
Tes baru:
- `backend/tests/Feature/EndToEndFlowTest.php`: kasir masuk → baca katalog → kirim
  transaksi (kiriman ulang dan stok kurang) → angka di Laporan, Dashboard, dan
  Statistik cocok → owner menambah stok → kasir kirim ulang diterima.
- `kasir_kantin/test/integration/offline_sync_flow_test.dart` (3 tes): SQLite berkas
  sungguhan + SyncBloc sungguhan melawan server palsu yang idempoten. Mencakup
  *transaksi offline → tutup dan buka aplikasi → online → sinkron → server berisi tepat
  satu per penjualan*, *balasan server hilang lalu kirim ulang*, dan *konflik stok →
  stok ditambah → Kirim Ulang*.

**Peta AGENTS.md §27 ke tes otomatis**

| Butir §27 | Dicek oleh |
|---|---|
| Login benar/salah, keluar, peran tidak sah | `AuthApiTest`, `AdminAccessTest`, `auth_bloc_test`, `login_page_test` |
| Produk: ambil, tampil lokal, cari/filter, nonaktif/terhapus | `CatalogApiTest`, `catalog_local_data_source_test`, `catalog_bloc_test`, `catalog_page_test` |
| Keranjang: tambah, hapus, +/-, kosongkan, batas stok | `cart_bloc_test`, `cart_widgets_test` |
| Transaksi online/offline, tersimpan lokal, restart, riwayat | `TransactionApiTest`, `transaction_local_data_source_test`, `transaction_sync_status_test`, `history_*_test`, `offline_sync_flow_test` |
| Sinkron: berhasil, UUID sama, jaringan/server gagal, konflik stok, coba lagi | `TransactionApiTest`, `sync_bloc_test`, `transaction_repository_impl_test`, `transaction_conflict_test`, `offline_sync_flow_test` |
| Persistensi: buat → tutup/buka → masih ada; offline → sinkron → tepat satu di server | `transaction_sync_status_test`, `offline_sync_flow_test`, `EndToEndFlowTest` |

#### Uji manual akhir (±30 menit, di HP dan browser)

Bagian yang tidak bisa dibuktikan tes otomatis: HP sungguhan, server sungguhan,
dan tampilan dashboard.

**Persiapan**
1. Pastikan katalog ada: `php artisan db:seed --class=CatalogSeeder` di `backend\`
   (aman dijalankan berulang). Data lama dibiarkan; akun owner dan kasir tidak diubah.
2. Terminal 1: `php artisan serve`. Pastikan `npm run build` pernah dijalankan.
3. HP: `.\run_dev.cmd` di `kasir_kantin\`. Browser: `http://127.0.0.1:8000/admin`
   masuk sebagai owner.
4. Terminal 2 (`backend\`), catat jumlah transaksi awal `N`:
   ```powershell
   php artisan tinker --execute="echo App\Models\Transaction::count();"
   ```

**Skenario 1 — Akun dan peran**
1. Di HP, masuk dengan kata sandi **salah**. Hasil yang benar: pesan galat dalam
   bahasa Indonesia, tetap di halaman masuk.
2. Masuk dengan akun **owner** di HP. Hasil yang benar: ditolak (owner memakai
   dashboard web).
3. Masuk dengan akun **kasir**. Hasil yang benar: masuk ke tab Kasir.
4. Di browser, buka `/admin/login` dengan akun kasir. Hasil yang benar: ditolak
   (pesan Kredensial yang diberikan tidak dapat ditemukan.).

**Skenario 2 — Katalog**
1. Di HP, cari `nasi`, lalu pilih kategori. Hasil yang benar: daftar menyempit sesuai.
2. Di dashboard, nonaktifkan satu produk (Produk → Ubah → matikan **Aktif**), lalu
   di HP tarik layar katalog ke bawah. Hasil yang benar: produk itu hilang dari katalog.
   Aktifkan kembali dan tarik ulang: muncul lagi.
3. Matikan Wi-Fi/data HP. Hasil yang benar: katalog tetap tampil ("Data lokal digunakan"),
   tanpa pesan galat. Nyalakan kembali.

**Skenario 3 — Keranjang**
1. Ketuk `Nasi Goreng` tiga kali, ketuk `Es Teh Manis` sekali. Hasil yang benar: bilah
   Keranjang menampilkan 4 item dan total yang benar.
2. Buka keranjang: **+**, **−**, ikon hapus, lalu **Kosongkan**. Hasil yang benar: tiap
   aksi bekerja; jumlah tidak pernah menjadi 0 (baris hilang); **+** nonaktif di batas stok.

**Skenario 4 — Transaksi online**
1. Isi keranjang, **Bayar** → **Tunai** → **Bayar Sekarang**.
2. Hasil yang benar: struk "Transaksi berhasil disimpan"; dalam ≤30 detik tab Riwayat
   menunjukkan **Tersinkron**. Jumlah transaksi di server menjadi `N + 1`.

**Skenario 5 — Offline, tutup aplikasi, lalu sinkron**
1. Hentikan server (`Ctrl+C` di Terminal 1).
2. Di HP buat **2** transaksi (satu Tunai, satu QRIS). Hasil yang benar: keduanya
   berhasil disimpan tanpa menunggu; Riwayat menampilkan status belum tersinkron.
3. **Tutup paksa** aplikasi (geser dari daftar aplikasi) lalu buka lagi. Hasil yang
   benar: tetap masuk, kedua transaksi masih ada di Riwayat, stok produk tetap berkurang.
4. Nyalakan server (`php artisan serve`). Tunggu sampai 30 detik. Hasil yang benar:
   keduanya menjadi **Tersinkron**; jumlah transaksi di server `N + 3`, **tepat 2
   tambahan**, tidak lebih.
5. Tunggu 1 menit lagi dan hitung ulang. Hasil yang benar: tetap `N + 3`.

**Skenario 6 — Kiriman ganda dan server bermasalah**
1. Di `backend\`: `.\coba-transaksi.ps1 -Email kasir@kantin.test -Password <kata sandi>`.
   Hasil yang benar: tiga langkah berhasil (201, lalu 200 untuk UUID yang sama dengan stok
   tidak berkurang lagi, lalu 409 untuk stok kurang).
2. Simulasi server rusak: `php artisan down`. Di HP bayar 1 transaksi. Hasil yang benar:
   transaksi tersimpan, status gagal/menunggu dengan pesan yang tenang, tidak hilang.
3. `php artisan up`, tunggu ≤30 detik. Hasil yang benar: transaksi tadi menjadi
   **Tersinkron** (tepat sekali).

**Skenario 7 — Konflik stok**
Ulangi **Skenario 6 dari Uji Manual Tahap 17** (konflik diselesaikan lewat Ubah Stok →
Kirim Ulang). Hasil yang benar: sama persis dengan yang tertulis di sana.

**Skenario 8 — Dashboard cocok dengan perangkat**
1. Di dashboard buka **Laporan** dengan rentang hari ini. Laporan menghitung **semua**
   transaksi di server, termasuk yang dibuat `.\coba-transaksi.ps1` (Skenario 6) atau dari
   HP/database lain. Jadi bandingkan **selisihnya**: Jumlah Transaksi Laporan =
   (transaksi Tersinkron hari ini di Riwayat HP) + (jumlah transaksi yang dibuat skrip,
   biasanya 1). Hasil yang benar: selisih persis sebanyak transaksi yang bukan dari HP ini.
   Untuk angka yang sama persis, jalankan Skenario 8 pada database server yang baru
   dikosongkan sebelum membuat transaksi dari HP.
2. Total Tunai + total QRIS = Total Omzet.
3. Buka **Statistik** (7 hari). Hasil yang benar: produk terlaris sesuai yang tadi dijual;
   **Stok Perlu Perhatian** menampilkan produk yang stoknya ≤5.

**Skenario 9 — Keluar akun**
1. Di HP, buat 1 transaksi saat server mati, lalu Pengaturan → **Keluar**. Hasil yang
   benar: kamu diberi tahu ada transaksi belum tersinkron, dan setelah keluar lalu masuk
   lagi, transaksinya masih ada dan tersinkron setelah server menyala.

#### Panduan demo untuk presentasi (±10 menit)

Urutan yang menceritakan inti proyek:
1. **Masalah dan tujuan** (1 menit): kantin sering kehilangan sinyal; kasir tidak boleh
   berhenti berjualan.
2. **Kasir online** (2 menit): pilih produk → Bayar Tunai → Tersinkron → muncul di
   dashboard (Laporan dan Dashboard).
3. **Offline-first** (3 menit): matikan server → 2 transaksi → tutup paksa aplikasi → buka
   → data masih ada → nyalakan server → tersinkron, jumlah di server tepat.
4. **Konflik stok** (2 menit): stok server habis → transaksi "perlu perhatian" → owner
   Ubah Stok → Kirim Ulang → diterima.
5. **Owner** (2 menit): Produk/Kategori, Laporan (filter tanggal), Statistik (tren, terlaris).

Siapkan sebelum tampil: Persiapan di atas sudah dijalankan, baterai HP cukup, dan satu
terminal untuk mematikan/menyalakan server dengan cepat.

#### Daftar periksa serah-terima
- [ ] `php artisan test` hijau, `flutter analyze` tanpa isu, `flutter test` hijau.
- [ ] `npm run build` berhasil; `git status` bersih setelah commit.
- [ ] `.env` dan `public\build` tidak ada di Git (sudah di `.gitignore`).
- [ ] README ini dan `AGENTS.md`/`DESIGN.md` ada di repositori.
- [ ] (Opsional) tandai rilis: `git tag v1.0.0` lalu `git push --tags`.

#### Batasan yang diketahui (sengaja, sesuai lingkup tugas)
- Transaksi `conflict` tidak pernah sampai ke server, jadi tidak terlihat di dashboard
  (Keputusan 17 dan 33). Penyelesaiannya: owner Ubah Stok, kasir Kirim Ulang.
- Satu kasir aktif; tanpa pajak, diskon, cetak struk, pemindai barcode, atau gateway
  QRIS (QRIS hanya penanda metode bayar). Semua di luar MVP (AGENTS.md §31).
- Laporan dan Statistik hanya menghitung transaksi yang sudah sampai ke server.
- Dashboard hanya terang (tanpa mode gelap); aplikasi kasir tidak memakai mode gelap.
- Tes Laravel/Flutter di repositori ini dijalankan di komputer pengembang; tidak ada
  CI otomatis.

Bila ada hasil yang berbeda dari "hasil yang benar", salin deskripsinya (dan teks
yang muncul) ke chat.

### Yang sudah ada
- `core/theme`: token warna/spasi/radius + `ThemeData` dari DESIGN.md.
- `core/database/app_database.dart`: skema SQLite v1 (kategori, produk,
  transaksi, item transaksi, metadata sinkronisasi) dengan constraint untuk
  lima status sinkronisasi, metode pembayaran `cash|qris`, `local_uuid`
  unik, dan item berformat snapshot. Migrasi eksplisit, tidak pernah drop-recreate.
- `core/network/api_client.dart` + `core/error/api_exceptions.dart`: galat
  dipisah sesuai AGENTS.md §17 (jaringan / 401 / 403 / 422 / 409 / 5xx).
- `core/storage/session_storage.dart`: token dan profil pengguna di secure storage.
- `features/auth/`: `AuthBloc` (pulihkan sesi, masuk, keluar, sesi berakhir),
  `AuthRepository` + remote data source, halaman masuk berbahasa Indonesia, dan
  `AuthGate` yang memilih layar berdasarkan status sesi.
- `app/settings_page.dart`: kartu akun dan tombol Keluar (dengan konfirmasi).
- `app/app_shell.dart`: navigasi bawah Kasir · Riwayat · Pengaturan; tab Kasir
  berisi katalog + keranjang, tab Riwayat berisi semua transaksi lokal (Tahap 15).
- `features/products/`: `CatalogBloc` (muat lokal → sinkronisasi di belakang,
  cari, filter kategori), `CatalogRepository`, remote data source (`/api/catalog`)
  dan local data source (upsert atomik, kursor, proyeksi stok), `CatalogPage`,
  `ProductCard`, chip kategori, dan status sinkronisasi.

- `features/cart/`: `CartBloc` (tambah, ubah jumlah, hapus, kosongkan, selaraskan
  dengan katalog), `CartBar`, `CartSheet`, `QuantityControl`.
- `features/transactions/`: `CheckoutBloc`, `TransactionRepository` + local data
  source (satu transaksi SQLite: validasi ulang, tulis transaksi + item + stok),
  dan sheet pembayaran (Tunai/QRIS, status berhasil disimpan).

- Tahap 12: `TransactionRemoteDataSource`, perpindahan status sinkronisasi di SQLite,
  dan `syncTransaction` di repository.
- Tahap 14: `ConflictBloc`, `ConflictPage` (daftar "Perlu Perhatian" + Kirim Ulang), banner konflik dapat diketuk; `getConflictTransactions` dan `retryConflict` di repository.
- Tahap 13: `features/sync/` berisi `SyncBloc` (kirim berurutan, satu putaran pada
  satu waktu, berhenti di kegagalan pertama), `SyncScheduler` (timer 30 detik dan
  saat aplikasi dibuka kembali), dan `SyncStatusBanner`. `AppShell` merangkainya;
  sheet pembayaran memicu pengiriman begitu transaksi tersimpan.
- Tahap 16: dashboard Filament di `backend/app/Filament/` (Resource Kategori, Produk,
  Transaksi, widget `RingkasanHariIni`), `ProductService` (ubah stok dengan selisih),
  `CategoryService` (slug unik), `DashboardSummaryService`, dan `SetAdminLocale`.
- Tahap 20: `backend/tests/Feature/EndToEndFlowTest.php` dan
  `kasir_kantin/test/integration/offline_sync_flow_test.dart` (alur lengkap lintas lapisan).
- Tahap 19: tema dashboard `resources/css/filament/admin/theme.css` (didaftarkan lewat
  `viteTheme` di `AdminPanelProvider`, font Inter lokal) dan di Flutter `ValuePulse`
  (`core/widgets/`), transisi bilah Keranjang, animasi ikon sukses, dan semantik
  `ProductCard`.
- Tahap 18: halaman `Statistik` (`app/Filament/Pages/`), widget `StatistikPerforma`,
  `StatistikTren` (grafik), `StatistikProdukTerlaris`, `StatistikStokPerhatian`, dan
  `StatistikService` (jendela N hari WIB, tren, perbandingan, jam/hari tersibuk,
  produk terlaris, stok perhatian).
- Tahap 17: halaman `Laporan` (`app/Filament/Pages/`), tiga widget `LaporanRingkasan`,
  `LaporanDaftarTransaksi`, `LaporanMetodePembayaran`, dan `ReportService`
  (rentang tanggal WIB → UTC, ringkasan, rincian metode). `DisplayTimezone::startOfDayUtc`
  kini dipakai bersama oleh filter Transaksi dan Laporan.
- Tahap 15: `HistoryBloc` + `HistoryPage` (tab Riwayat dan Detail Transaksi),
  `SyncStatusChip` (label status), `TransactionReceipt` (rincian yang dipakai
  struk dan detail), `getAllTransactions` di repository, dan `CheckoutReceiptRefreshed`
  agar struk mengikuti status sinkronisasi.

---

## C. Git: alur commit

Satu repositori di `C:\DIL\pos-kantin` (monorepo). `backend/` dan `kasir_kantin/`
sudah punya `.gitignore` bawaan masing-masing yang mengecualikan `.env`,
`vendor/`, `build/`, dan sejenisnya. Salin `README.md` ini ke `C:\DIL\pos-kantin\`.

**Setup sekali:**
```powershell
cd C:\DIL\pos-kantin
git init -b main
git config user.name "Nama Kamu"
git config user.email "emailmu@contoh.com"

# Pengaman: HARUS menampilkan baris aturan .gitignore. Jika kosong, .env
# belum diabaikan: jangan commit dulu.
git check-ignore -v backend/.env
```

**Aturan commit:**
- Satu commit = satu hal yang sudah berhasil (tes lulus atau aplikasi berjalan).
  Jangan commit kode yang masih error.
- Format pesan (Conventional Commits): `tipe(lingkup): deskripsi singkat`.
  Tipe: `feat` (fitur), `fix` (perbaikan), `test`, `docs`, `chore` (konfigurasi/
  dependensi), `refactor`. Lingkup: `backend` atau `mobile`.
- Selalu tinjau dulu sebelum commit: `git status` dan `git diff --staged --stat`.
- Rahasia (password, token) tidak boleh masuk repo. `.env.testing` tidak diabaikan
  bawaan Laravel; jika kamu menaruh password sungguhan di sana, tambahkan ke
  `backend/.gitignore`.
- Cadangan opsional ke GitHub (repositori privat):
  `git remote add origin <url>` lalu `git push -u origin main`.

**Commit untuk yang sudah selesai:**
```powershell
cd C:\DIL\pos-kantin

git add backend
git commit -m "feat(backend): fondasi Laravel dengan auth Sanctum, katalog API, dan skema database" -m "13 tes lulus."

cd kasir_kantin; flutter test; cd ..    # pastikan lulus sebelum commit
git add kasir_kantin
git commit -m "feat(mobile): fondasi Flutter dengan tema, SQLite lokal, API client, dan app shell"

git add README.md
git commit -m "docs: tambah README panduan setup backend dan mobile"
```
Perubahan berikutnya (Inter, HTTP debug, run di HP) dijadikan commit terpisah:
```powershell
git add kasir_kantin
git commit -m "feat(mobile): pakai font Inter dan izinkan HTTP untuk build debug"
git add README.md
git commit -m "docs: panduan run di HP Android dan alur git"
```

---

### Push ke GitHub
1. Di github.com: **New repository** → nama mis. `pos-kantin` → pilih **Private** →
   **jangan** centang README / .gitignore / license (repositori harus kosong) → *Create*.
2. Pastikan tidak ada rahasia yang terlacak Git:
```powershell
cd C:\DIL\pos-kantin
git ls-files | Select-String "\.env"
git status
```
   Hasil pertama hanya boleh `backend/.env.example` (dan `backend/.env.testing` hanya
   bila isinya tanpa password). Jika `backend/.env` muncul: **berhenti**, jangan push.
   `git status` harus bersih (`nothing to commit`).
3. Hubungkan dan push:
```powershell
git remote add origin https://github.com/USERNAME/pos-kantin.git
git branch -M main
git push -u origin main
```
   Git for Windows akan membuka jendela login di browser (Git Credential Manager).
   Password akun GitHub tidak diterima lagi di terminal; gunakan login browser atau
   Personal Access Token.
4. Seterusnya, setelah tiap `git commit`, jalankan `git push`.

Jika rahasia (mis. isi `.env`) terlanjur ter-push, menghapus filenya tidak cukup karena
tetap ada di riwayat: ganti rahasianya (password database, `APP_KEY`) dan minta bantuan
membersihkan riwayatnya.

**Commit tahap 7** (setelah `flutter test` lulus dan uji manual di HP berhasil):
```powershell
cd C:\DIL\pos-kantin
git add kasir_kantin
git commit -m "feat(mobile): autentikasi Flutter dengan AuthBloc, sesi offline, dan halaman masuk"
git add README.md
git commit -m "docs: panduan tahap 7 dan push ke GitHub"
git push
```

### Pesan commit per tahap
Format: `jenis(lingkup): ringkasan singkat`, huruf kecil, bahasa Indonesia, tanpa titik
di akhir. Jenis: `feat` (fitur), `fix` (perbaikan bug), `docs` (dokumentasi), `test`, `refactor`.
Lingkup: `backend` atau `mobile`. Satu tahap = satu commit.

| Tahap | Pesan commit |
|---|---|
| 10 | `feat(mobile): transaksi lokal dan pembayaran` (sudah dipakai) |
| 11 | `feat(backend): api transaksi idempoten dengan validasi stok` (sudah dipakai) |
| 12 | `feat(mobile): kirim transaksi dan status sinkronisasi lokal` (sudah dipakai) |
| 13 | `feat(mobile): sinkronisasi otomatis transaksi ke server` (sudah dipakai) |
| 14 | `feat(mobile): halaman konflik transaksi dan kirim ulang` (sudah dipakai) |
| 15 | `feat(mobile): riwayat transaksi dan struk mengikuti status sinkronisasi` (sudah dipakai) |
| 16 | `feat(backend): dashboard filament untuk kategori, produk, dan transaksi` (sudah dipakai) |
| 17 | `feat(backend): halaman laporan penjualan dengan filter tanggal` (sudah dipakai) |
| 18 | `feat(backend): halaman statistik tren, produk terlaris, dan stok` (sudah dipakai) |
| 19 | `feat: pemolesan ui dashboard teal dan gerak aplikasi kasir` (sudah dipakai) |
| 20 | `test: alur lengkap offline ke sinkron dan dashboard, panduan uji akhir` |

Perintahnya (PowerShell, dari `C:\DIL\pos-kantin`):
```powershell
git status
git add -A
git commit -m "test: alur lengkap offline ke sinkron dan dashboard, panduan uji akhir"
git push
```
Pesan untuk tahap berikutnya selalu diberikan di akhir tiap tahap.

---

## Keputusan yang perlu kamu ketahui

1. **Login mobile hanya untuk `cashier`.** Owner ditolak (403) di API dan hanya
   masuk lewat Filament. Ini sesuai AGENTS.md §8; ubah di `AuthService` bila
   kamu ingin owner juga bisa memakai aplikasi.
2. **`users.role` default `cashier`** (hak akses terkecil) dan tidak mass-assignable.
3. **Slug kategori `UNIQUE` + soft delete**: slug milik kategori yang sudah
   dihapus tetap terpakai. Tangani saat membuat form kategori di Filament.
4. **Stok lokal tanpa `CHECK >= 0`** karena itu proyeksi optimistik; server yang
   memutuskan lewat status `conflict`.
5. **Skema server `unsignedInteger` untuk stok**: database juga menolak stok negatif.
6. **Nomor invoice yang bertabrakan** diberi akhiran `-2`, `-3`, … oleh server
   (transaksi sah tidak pernah ditolak karena nomor). Perangkat membaca
   `invoice_number` dari respons dan memperbarui nomor lokalnya (Tahap 12).
7. **Harga dari perangkat diterima sebagai snapshot saat penjualan**, setelah
   dicek konsisten (subtotal = harga × jumlah, total = jumlah subtotal). Server
   tidak menolak bila harga produk di server sudah berubah, karena pelanggan
   sudah membayar harga lama. Nama produk diambil dari server.
8. **Produk nonaktif atau terhapus sejak sinkronisasi terakhir tetap diterima**
   selama stoknya cukup, karena barangnya memang sudah terjual. Hanya `product_id`
   yang sama sekali tidak ada yang ditolak (422).
9. **422 dari server menjadi `conflict`, bukan `failed`.** `failed` berarti "coba lagi
   nanti"; kiriman yang tidak valid akan ditolak lagi, jadi ia harus terlihat
   sebagai "perlu perhatian" dan tidak diulang otomatis.
10. **Stok lokal dikembalikan saat `conflict`.** Aturan proyeksi stok tidak
    mengurangkan `conflict`, dan stok server tidak berubah karena penolakan,
    sehingga pull katalog tidak akan mengoreksinya sendiri.
11. **Nomor invoice server menggantikan nomor lokal** setelah `synced` (bisa berakhiran `-2`).
12. **Tanpa pemantau koneksi.** Tidak ada paket baru: internet yang kembali terdeteksi
    lewat timer 30 detik atau saat aplikasi dibuka kembali. Cukup untuk MVP; pemantau
    koneksi bisa ditambahkan nanti bila 30 detik terasa lama.
13. **Putaran berhenti di kegagalan pertama** (jaringan/server), supaya server yang
    sedang bermasalah tidak ditembak berulang kali. `conflict` tidak menghentikan putaran.
14. **Katalog ditarik setelah pengiriman** yang mengubah data lokal. Ini juga
    membetulkan proyeksi stok bila tarikan katalog sempat bertepatan dengan transaksi
    yang sedang dikirim (server sudah mengurangi stok, tetapi transaksi masih
    dihitung belum tersinkron).
15. **Akses ditolak 403** membuat transaksi kembali `pending` dan dicoba lagi tiap
    30 detik. Untuk 401, `ApiClient` sudah mengakhiri sesi lewat `AuthBloc`.
16. **Peringatan di dialog Keluar** bila ada transaksi belum tersinkron atau konflik.
    Database lokal tetap tidak pernah dihapus saat keluar (Rule 6).

## Tahap berikutnya (AGENTS.md §30)
7. Autentikasi Flutter ✔ → 8. Katalog produk + sinkronisasi pull ✔ →
9. Keranjang ✔ → 10. Transaksi lokal ✔ → 11. API transaksi ✔ → 12. Kirim transaksi
(lapisan data) ✔ → 13. Sinkronisasi otomatis ✔ →
14. Penanganan konflik ✔ → 15. Riwayat transaksi ✔ → 16. Dashboard Filament ✔ →
17. Laporan ✔ → 18. Statistik ✔ → 19. Pemolesan UI ✔ → 20. Pengujian dan integrasi akhir ✔.

Seluruh urutan AGENTS.md §30 selesai. Pengembangan lanjutan (di luar MVP, AGENTS.md §31)
sebaiknya dimulai dari "Batasan yang diketahui" di bagian Tahap 20, satu per satu,
dengan aturan yang sama: satu tahap, uji otomatis dan manual, lalu commit.

## Keputusan Tahap 14
17. **Satu-satunya tindakan kasir pada konflik adalah Kirim Ulang.** Tidak ada hapus
    atau ubah jumlah (AGENTS.md §13.4). Pengurangan jumlah dan pembatalan sebaiknya
    dilakukan owner/dashboard (Tahap 16), karena uang sudah diterima dari pelanggan.
18. **Kirim Ulang tidak mengecek stok lokal.** Stok server yang memutuskan; stok lokal
    boleh sementara negatif sampai tarikan katalog berikutnya.
19. **Konflik tidak pernah dikirim ulang otomatis**, hanya lewat tombol, supaya tidak
    menembak server yang jelas menolak tiap 30 detik.

## Keputusan Tahap 15
20. **Riwayat membaca SQLite, bukan server.** Riwayat tampil tanpa internet dan
    mencakup semua status, termasuk `conflict`, sesuai AGENTS.md §4.1 dan Rule 6.
    Transaksi yang dibuat di perangkat lain tidak tampil (MVP satu kasir).
21. **Riwayat dibaca ulang setiap SyncBloc berubah** dan saat tab dibuka, sehingga
    status di kartu dan detail selalu terbaru tanpa timer tambahan.
22. **Struk memakai label status yang sama dengan Riwayat** (DESIGN.md §20).
    Tulisan statis "Belum tersinkron" diganti `Menunggu sinkronisasi` untuk
    transaksi yang baru dibuat; judul `Transaksi berhasil disimpan` tetap.
23. **Tidak ada tombol tindakan di Riwayat.** Kirim Ulang konflik tetap di halaman
    Perlu Perhatian (satu tempat), supaya aturan Tahap 14 tidak terpecah dua.
24. **Semua transaksi dimuat sekaligus.** Cukup untuk volume kantin; bila daftar
    kelak terasa lambat, tambahkan pemuatan bertahap atau filter tanggal.

## Keputusan Tahap 16
25. **Transaksi di dashboard hanya baca.** Transaksi lahir di perangkat kasir dan masuk
    lewat API yang idempoten dan atomik dengan stok. Mengubah atau menghapusnya dari
    dashboard akan merusak jejak penjualan dan stok (AGENTS.md §9, §13).
26. **Stok diubah dengan selisih, bukan ditimpa.** Stok server juga berubah oleh
    transaksi kasir. Formulir ubah yang dibiarkan terbuka lalu disimpan akan menimpa
    penjualan yang terjadi di sela-selanya. Stok hanya diisi saat produk dibuat
    ("Stok Awal"); sesudahnya lewat aksi **Ubah Stok** (+/-) yang mengunci baris dan
    menolak hasil di bawah 0.
27. **Kategori yang masih punya produk tidak bisa dihapus.** Produk dengan kategori
    terhapus akan membingungkan katalog di HP. Produk juga tidak bisa dipulihkan
    selama kategorinya masih terhapus.
28. **Slug kategori dibuat server** dan tidak berubah saat nama diganti. Bila bentrok
    (termasuk dengan kategori terhapus, karena kolom UNIQUE mencakupnya) diberi akhiran
    `-2`, `-3`.
29. **Tidak ada hapus permanen** dari dashboard (tanpa Force Delete), sesuai soft delete
    di AGENTS.md §14.
30. **Waktu tampil WIB, penyimpanan tetap UTC.** "Hari ini" di dashboard adalah hari
    kalender WIB.
31. **Batas "stok menipis" = 5**, sama dengan `Product.lowStockThreshold` di Flutter.
    Ada di dua tempat (`Product::LOW_STOCK_THRESHOLD`); ubah keduanya bersamaan.
32. **Perubahan owner sampai ke HP lewat sinkronisasi katalog** (saat aplikasi dibuka,
    dan setelah ada transaksi yang tersinkron), bukan seketika.
33. **Ditunda:** sidebar teal tua dan font kustom (butuh tema Filament dan build npm)
    masuk Tahap 19 (pemolesan UI). Pembatalan atau pengurangan jumlah transaksi
    `conflict` (Keputusan 17) belum ada: server tidak pernah menerima transaksi konflik,
    jadi owner belum melihatnya di dashboard.

## Keputusan Tahap 17
34. **Laporan = data historis pada rentang tanggal; Statistik = tren dan peringkat.**
    Laporan tidak memuat grafik atau produk terlaris, supaya tidak menduplikasi Tahap 18.
35. **Tanggal adalah hari kalender WIB**, dikonversi ke batas UTC (awal hari dari
    tanggal, akhir eksklusif). Transaksi pukul 23.59 WIB masuk hari itu, 00.00 WIB hari
    berikutnya. Logika konversi satu tempat: `DisplayTimezone::startOfDayUtc`.
36. **Hanya transaksi yang sudah diterima server yang dihitung.** Transaksi `conflict`
    atau belum tersinkron hanya ada di HP, jadi belum masuk omzet (Keputusan 33). Ini
    dinyatakan di kartu Total Omzet.
37. **Rata-rata = omzet dibagi jumlah transaksi, dibulatkan ke rupiah;** 0 bila tidak ada
    transaksi. Persen metode dibulatkan, jadi jumlahnya bisa 99% atau 101%.
38. **Input tanggal dibuat tahan salah:** kosong atau tidak valid memakai bawaan (awal
    bulan sampai hari ini), terbalik ditukar. Laporan tidak pernah error karena filter.
39. **Filter tidak diingat antar kunjungan;** selalu mulai dari bulan berjalan.
40. **Pesan gagal masuk kasir di `/admin` tetap bawaan Filament** ("Kredensial yang
    diberikan tidak dapat ditemukan."). Sengaja umum agar tidak membocorkan akun; README
    Tahap 16 diperbaiki mengikuti ini.

## Keputusan Tahap 18
41. **Statistik memakai "N hari terakhir" (7 atau 30), bukan rentang tanggal bebas.**
    Rentang bebas adalah milik Laporan; dengan begitu dua halaman tidak menampilkan hal
    yang sama (AGENTS.md §25). Pilihan tak dikenal jatuh ke 7 hari.
42. **Omzet dibandingkan dengan N hari tepat sebelumnya**, dalam persen yang dibulatkan.
    Bila periode pembanding kosong, tidak ada persen (bukan "naik tak terhingga").
43. **Hari dan jam tersibuk dihitung dari jumlah transaksi**, memakai jam WIB. Bila seri,
    yang lebih awal dipilih (Senin sebelum Selasa, jam lebih pagi).
44. **Produk terlaris menurut jumlah terjual** (5 teratas; seri: omzet, lalu nama). Nama
    diambil dari snapshot item transaksi, jadi produk yang sudah dihapus tetap tampil
    (konsisten dengan AGENTS.md §9).
45. **Stok perlu perhatian = produk aktif dengan stok 5 ke bawah** (`Product::LOW_STOCK_THRESHOLD`).
    Kartu hitungan di Dashboard tetap ada; tabel di Statistik menunjukkan produk mana.
    Stok tetap diubah lewat menu Produk (Keputusan 26), bukan dari Statistik.
46. **Pengelompokan per hari dan jam dikerjakan di PHP**, bukan SQL, supaya tidak
    bergantung fungsi zona waktu database (SQLite di tes, MySQL di produksi). Volume
    kantin kecil, jadi aman.
47. **Hanya satu grafik (tren omzet).** DESIGN.md §28 melarang grafik dekoratif; jam dan
    hari tersibuk cukup berupa kartu.
48. **Properti trait Filament tidak ditimpa dengan nilai lain.** Bug Tahap 17
    (`$persistsFiltersInSession`) diperbaiki dengan menimpa method-nya; halaman Statistik
    memakai cara yang sama.

## Keputusan Tahap 19
49. **Tema dashboard dibangun dengan Vite (tema Filament), bukan CSS statis.** Sidebar
    teal tua butuh menimpa gaya bawaan Filament; tema resmi adalah cara yang tidak
    rapuh saat Filament diperbarui. Konsekuensinya `npm run build` perlu dijalankan
    (hasilnya di `public/build`, tidak masuk Git).
50. **Font Inter dipaketkan lokal** (`@fontsource-variable/inter`) dan didaftarkan
    dengan `LocalFontProvider`, jadi dashboard tidak bergantung CDN. Satu keluarga font
    yang sama dengan aplikasi kasir (DESIGN.md §6).
51. **Mode gelap dashboard dimatikan.** DESIGN.md hanya mendefinisikan palet terang;
    mode gelap setengah jadi lebih buruk daripada tidak ada.
52. **Teal tua untuk navigasi, teal sekunder untuk aksi dan menu aktif, coral hanya
    penanda kecil** (garis menu aktif dan peringatan), sesuai DESIGN.md §4 ("jangan
    pakai aksen untuk semua tombol").
53. **Tes mematikan Vite** (`withoutVite()` di `tests/TestCase.php`) agar `php artisan test`
    tidak gagal hanya karena build belum dijalankan.
54. **Audit Flutter: tidak ada perombakan.** Bahasa, area sentuh, status stok, anti
    ketuk ganda, dan skeleton katalog sudah sesuai; yang ditambah hanya gerak (§38) dan
    semantik pembaca layar (§37). Alur kasir tidak berubah.
55. **Gerak seminimal mungkin:** denyut 160 ms pada total/jumlah keranjang, transisi
    tinggi 180 ms pada bilah Keranjang, ikon sukses 220 ms. Tanpa memantul dan tanpa
    menunda kasir; denyut dimatikan bila sistem meminta animasi dikurangi.
56. **Sengaja tidak dikerjakan:** skeleton untuk tab Riwayat dan halaman Perlu
    Perhatian (data lokal SQLite muncul seketika, spinner singkat sudah cukup), dan
    mode gelap di Flutter.

## Keputusan Tahap 20
57. **Tidak ada kode aplikasi yang diubah.** Tahap penutup hanya menambah tes dan
    dokumentasi; bug yang ditemukan di sini harus diperbaiki sebagai commit terpisah
    agar jejaknya jelas.
58. **Tes integrasi memakai server palsu yang meniru kontrak Laravel** (201 baru, 200
    duplikat, 409 `insufficient_stock`), bukan server sungguhan. Kontraknya sudah dijaga
    `TransactionApiTest` di sisi Laravel; tes ini membuktikan sisi Flutter memakainya
    dengan benar, tanpa bergantung pada jaringan atau MySQL.
59. **Tes alur Flutter memakai SQLite berkas dan menutup lalu membuka database lagi**
    untuk mewakili "aplikasi ditutup dan dibuka", satu-satunya cara mensimulasikan
    persistensi yang jujur (basis data memori tidak selamat dari penutupan).
60. **Simulasi "server bermasalah" di uji manual memakai `php artisan down`** (503):
    cara paling aman dan dapat dibatalkan dengan `php artisan up`.
