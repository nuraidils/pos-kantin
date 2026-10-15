<?php

namespace Tests\Feature\Admin;

use App\Filament\Pages\Laporan;
use App\Models\Transaction;
use App\Models\User;
use App\Services\ReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

class LaporanTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function transaksi(User $kasir, string $uuid, int $total, string $metode, string $waktuUtc, string $status = 'synced'): Transaction
    {
        return Transaction::create([
            'local_uuid' => $uuid,
            'user_id' => $kasir->id,
            'invoice_number' => 'INV-'.substr($uuid, 0, 8),
            'total_amount' => $total,
            'payment_method' => $metode,
            'sync_status' => $status,
            'created_at' => $waktuUtc,
            'synced_at' => $waktuUtc,
        ]);
    }

    public function test_ringkasan_total_rata_rata_dan_metode_pembayaran(): void
    {
        $kasir = User::factory()->create(['role' => 'cashier']);
        $this->transaksi($kasir, 'aaaaaaaa-0000-4000-8000-000000000001', 10000, 'cash', '2026-10-10T03:00:00Z');
        $this->transaksi($kasir, 'bbbbbbbb-0000-4000-8000-000000000002', 20000, 'cash', '2026-10-11T03:00:00Z');
        $this->transaksi($kasir, 'cccccccc-0000-4000-8000-000000000003', 30000, 'qris', '2026-10-12T03:00:00Z');

        $ringkasan = app(ReportService::class)->summary('2026-10-01', '2026-10-31');

        $this->assertSame(60000, $ringkasan['revenue']);
        $this->assertSame(3, $ringkasan['transactions']);
        $this->assertSame(20000, $ringkasan['average']);
        $this->assertSame(['count' => 2, 'total' => 30000, 'share' => 50], $ringkasan['by_method']['cash']);
        $this->assertSame(['count' => 1, 'total' => 30000, 'share' => 50], $ringkasan['by_method']['qris']);
    }

    public function test_periode_kosong_menghasilkan_nol_tanpa_error(): void
    {
        $ringkasan = app(ReportService::class)->summary('2026-10-01', '2026-10-31');

        $this->assertSame(0, $ringkasan['revenue']);
        $this->assertSame(0, $ringkasan['transactions']);
        $this->assertSame(0, $ringkasan['average']);
        $this->assertSame(0, $ringkasan['by_method']['cash']['share']);
        $this->assertSame(0, $ringkasan['by_method']['qris']['count']);
    }

    public function test_batas_tanggal_mengikuti_hari_wib_dan_kedua_ujung_ikut_dihitung(): void
    {
        $kasir = User::factory()->create(['role' => 'cashier']);
        // Rentang 10-11 Okt WIB = 9 Okt 17.00 UTC s/d 11 Okt 17.00 UTC (eksklusif).
        $this->transaksi($kasir, 'aaaaaaaa-0000-4000-8000-000000000001', 1000, 'cash', '2026-10-09T16:59:00Z'); // 9 Okt 23.59 WIB: luar
        $this->transaksi($kasir, 'bbbbbbbb-0000-4000-8000-000000000002', 2000, 'cash', '2026-10-09T17:00:00Z'); // 10 Okt 00.00 WIB: dalam
        $this->transaksi($kasir, 'cccccccc-0000-4000-8000-000000000003', 4000, 'cash', '2026-10-11T16:59:00Z'); // 11 Okt 23.59 WIB: dalam
        $this->transaksi($kasir, 'dddddddd-0000-4000-8000-000000000004', 8000, 'cash', '2026-10-11T17:00:00Z'); // 12 Okt 00.00 WIB: luar

        $ringkasan = app(ReportService::class)->summary('2026-10-10', '2026-10-11');

        $this->assertSame(6000, $ringkasan['revenue']);
        $this->assertSame(2, $ringkasan['transactions']);
    }

    public function test_tanggal_terbalik_ditukar_dan_tidak_valid_memakai_bawaan(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-10-15 10:00:00', 'Asia/Jakarta'));
        $kasir = User::factory()->create(['role' => 'cashier']);
        $this->transaksi($kasir, 'aaaaaaaa-0000-4000-8000-000000000001', 5000, 'qris', '2026-10-05T03:00:00Z');

        $service = app(ReportService::class);

        $this->assertSame(5000, $service->summary('2026-10-31', '2026-10-01')['revenue']);
        // Kosong atau sampah -> 1 Okt s/d 15 Okt 2026 (bulan berjalan).
        $this->assertSame(5000, $service->summary(null, null)['revenue']);
        $this->assertSame(5000, $service->summary('bukan-tanggal', '2026-13-45')['revenue']);
        $this->assertSame('1 Okt 2026 - 15 Okt 2026', $service->periodLabel(null, null));
    }

    public function test_kasir_tidak_boleh_membuka_laporan(): void
    {
        $kasir = User::factory()->create(['role' => 'cashier']);

        $this->actingAs($kasir)->get('/admin/laporan')->assertForbidden();
    }

    public function test_owner_membuka_laporan_dan_melihat_transaksi_periode(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-10-15 10:00:00', 'Asia/Jakarta'));
        $owner = User::factory()->create(['role' => 'owner']);
        $kasir = User::factory()->create(['role' => 'cashier']);
        $dalam = $this->transaksi($kasir, 'aaaaaaaa-0000-4000-8000-000000000001', 12000, 'cash', '2026-10-10T03:00:00Z');
        $luar = $this->transaksi($kasir, 'bbbbbbbb-0000-4000-8000-000000000002', 9000, 'cash', '2026-09-10T03:00:00Z');

        $this->actingAs($owner)->get('/admin/laporan')->assertOk();

        Livewire::actingAs($owner)
            ->test(\App\Filament\Widgets\LaporanDaftarTransaksi::class, ['pageFilters' => ['dari' => '2026-10-01', 'sampai' => '2026-10-15']])
            ->assertCanSeeTableRecords([$dalam])
            ->assertCanNotSeeTableRecords([$luar]);
    }

    public function test_halaman_laporan_dapat_dirender_oleh_owner(): void
    {
        $owner = User::factory()->create(['role' => 'owner']);

        Livewire::actingAs($owner)->test(Laporan::class)->assertOk();
    }
}
