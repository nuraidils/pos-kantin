# POS Kantin — Fondasi Proyek

Paket ini adalah **overlay**: kode yang disalin ke project Laravel dan Flutter
hasil generate resmi. Isinya mencakup **tahap 1–6** dari urutan di `AGENTS.md` §30
(Laravel + database, autentikasi, kategori/produk, API produk, fondasi Flutter,
skema SQLite lokal). Tahap berikutnya sengaja belum dibuat; stabilkan tiap
lapisan sebelum menambah lapisan baru.

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
4. Matikan server Laravel (atau mode pesawat) lalu masuk → banner menyebut koneksi internet.
5. Masuk dengan akun kasir → tampil kerangka aplikasi. Tab **Pengaturan** menampilkan nama, email, dan "Kasir".
6. **Uji offline:** tutup aplikasi sepenuhnya (swipe dari recent apps), aktifkan mode pesawat, buka lagi → langsung masuk, tanpa halaman login.
7. Pengaturan → **Keluar** → dialog konfirmasi → kembali ke halaman login. Cek di MySQL
   (`SELECT COUNT(*) FROM personal_access_tokens;`) token berkurang bila saat itu online.
8. Ulangi Keluar dalam mode pesawat → tetap berhasil keluar.

Jalur "sesi berakhir" belum bisa diuji manual karena belum ada fitur yang memakai
token selain login; jalur itu diuji lewat tes otomatis dan baru terlihat nyata di tahap 8.

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
- `app/app_shell.dart`: navigasi bawah Kasir · Riwayat · Pengaturan, dengan
  keadaan kosong berbahasa Indonesia.

Folder `features/*` belum dibuat; tiap fitur membuatnya saat dikerjakan.

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
7. Autentikasi Flutter (`AuthBloc`, token, sesi offline) →
8. Katalog produk + sinkronisasi pull dari `/api/catalog` →
9. Keranjang → 10. Transaksi lokal → 11. API transaksi (`local_uuid` idempoten,
`DB::transaction`, `lockForUpdate`, respons 409 untuk stok kurang) →
12–15. Offline, sync engine, konflik, riwayat → 16–18. Filament, laporan, statistik.

Catatan untuk tahap sync: saat aplikasi mulai, transaksi berstatus `syncing`
yang tertinggal (aplikasi tertutup mendadak) harus dikembalikan ke `pending`;
dan **logout tidak boleh menghapus database lokal** selama masih ada transaksi
yang belum tersinkron (AGENTS.md Rule 6).
