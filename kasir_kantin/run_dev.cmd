@echo off
REM Menjalankan aplikasi di HP Android via USB, terhubung ke Laravel lokal.
REM Prasyarat: "php artisan serve" sudah berjalan di folder backend.
REM Pakai dari folder kasir_kantin (PowerShell): .\run_dev.cmd
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api %*
