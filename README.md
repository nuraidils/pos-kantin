# POS Kantin — Fondasi Proyek

Paket ini adalah **overlay**: kode yang disalin ke project Laravel dan Flutter
hasil generate resmi. Isinya mencakup **tahap 1–9** dari urutan di `AGENTS.md` §30
(Laravel + database, autentikasi, kategori/produk, API produk, fondasi Flutter,
skema SQLite lokal, autentikasi Flutter, katalog produk + sinkronisasi pull,
keranjang).
Tahap berikutnya sengaja belum dibuat; stabilkan tiap lapisan sebelum menambah
lapisan baru.

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
  berisi katalog + keranjang, tab Riwayat masih keadaan kosong.
- `features/products/`: `CatalogBloc` (muat lokal → sinkronisasi di belakang,
  cari, filter kategori), `CatalogRepository`, remote data source (`/api/catalog`)
  dan local data source (upsert atomik, kursor, proyeksi stok), `CatalogPage`,
  `ProductCard`, chip kategori, dan status sinkronisasi.

- `features/cart/`: `CartBloc` (tambah, ubah jumlah, hapus, kosongkan, selaraskan
  dengan katalog), `CartBar`, `CartSheet`, `QuantityControl`.

Folder `features/transactions` dan `features/sync` dibuat saat dikerjakan.

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

## Tahap berikutnya (AGENTS.md §30)
7. Autentikasi Flutter ✔ → 8. Katalog produk + sinkronisasi pull ✔ →
9. Keranjang ✔ → 10. Transaksi lokal → 11. API transaksi (`local_uuid` idempoten,
`DB::transaction`, `lockForUpdate`, respons 409 untuk stok kurang) →
12–15. Offline, sync engine, konflik, riwayat → 16–18. Filament, laporan, statistik.

Catatan untuk tahap sync: saat aplikasi mulai, transaksi berstatus `syncing`
yang tertinggal (aplikasi tertutup mendadak) harus dikembalikan ke `pending`;
dan **logout tidak boleh menghapus database lokal** selama masih ada transaksi
yang belum tersinkron (AGENTS.md Rule 6).
