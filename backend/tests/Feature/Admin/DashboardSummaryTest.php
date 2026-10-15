<?php

namespace Tests\Feature\Admin;

use App\Models\Category;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\User;
use App\Services\DashboardSummaryService;
use App\Support\Rupiah;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class DashboardSummaryTest extends TestCase
{
    use RefreshDatabase;

    private function transaksi(User $kasir, string $uuid, int $total, string $waktuUtc): void
    {
        Transaction::create([
            'local_uuid' => $uuid,
            'user_id' => $kasir->id,
            'invoice_number' => 'INV-'.substr($uuid, 0, 8),
            'total_amount' => $total,
            'payment_method' => 'cash',
            'sync_status' => 'synced',
            'created_at' => $waktuUtc,
            'synced_at' => $waktuUtc,
        ]);
    }

    public function test_hari_ini_mengikuti_hari_kalender_wib_bukan_utc(): void
    {
        $kasir = User::factory()->create(['role' => 'cashier']);

        // Sekarang: 15 Oktober 2026, 10.00 WIB. Hari ini WIB = 14 Okt 17.00 UTC s/d 15 Okt 16.59 UTC.
        $this->transaksi($kasir, 'aaaaaaaa-0000-4000-8000-000000000001', 10000, '2026-10-14T16:30:00Z'); // 14 Okt 23.30 WIB: kemarin
        $this->transaksi($kasir, 'bbbbbbbb-0000-4000-8000-000000000002', 20000, '2026-10-14T17:30:00Z'); // 15 Okt 00.30 WIB: hari ini
        $this->transaksi($kasir, 'cccccccc-0000-4000-8000-000000000003', 5000, '2026-10-15T09:00:00Z');  // 15 Okt 16.00 WIB: hari ini
        $this->transaksi($kasir, 'dddddddd-0000-4000-8000-000000000004', 7000, '2026-10-15T17:30:00Z');  // 16 Okt 00.30 WIB: besok

        $ringkasan = app(DashboardSummaryService::class)
            ->today(Carbon::parse('2026-10-15 10:00:00', 'Asia/Jakarta'));

        $this->assertSame(25000, $ringkasan['revenue']);
        $this->assertSame(2, $ringkasan['transactions']);
    }

    public function test_stok_perlu_perhatian_hanya_menghitung_produk_aktif(): void
    {
        $kategori = Category::create(['name' => 'Minuman', 'slug' => 'minuman']);
        $buat = fn (string $nama, int $stok, bool $aktif = true) => Product::create([
            'category_id' => $kategori->id, 'name' => $nama, 'price' => 1000, 'stock' => $stok, 'is_active' => $aktif,
        ]);

        $buat('Habis', 0);
        $buat('Menipis 3', 3);
        $buat('Menipis 5 (batas)', 5);
        $buat('Aman', 6);
        $buat('Nonaktif habis', 0, false);

        $ringkasan = app(DashboardSummaryService::class)->today();

        $this->assertSame(1, $ringkasan['out_of_stock']);
        $this->assertSame(2, $ringkasan['low_stock']);
    }

    public function test_format_rupiah(): void
    {
        $this->assertSame('Rp0', Rupiah::format(null));
        $this->assertSame('Rp10.000', Rupiah::format(10000));
        $this->assertSame('Rp1.250.000', Rupiah::format('1250000'));
    }
}
