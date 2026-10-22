<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\User;
use App\Services\DashboardSummaryService;
use App\Services\ProductService;
use App\Services\ReportService;
use App\Services\StatistikService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * Alur lengkap lintas lapisan (AGENTS.md §27): kasir masuk -> membaca katalog ->
 * mengirim transaksi (termasuk kiriman ulang dan stok kurang) -> owner melihat
 * hasilnya di dashboard -> owner menambah stok -> kasir mengirim ulang.
 *
 * Tes lain memeriksa tiap lapisan sendiri-sendiri; tes ini memastikan semuanya
 * bersepakat tentang angka yang sama.
 */
class EndToEndFlowTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function payload(string $uuid, array $lines, string $metode): array
    {
        $items = [];
        $total = 0;
        foreach ($lines as [$produk, $jumlah]) {
            $items[] = [
                'product_id' => $produk->id,
                'quantity' => $jumlah,
                'price' => $produk->price,
                'subtotal' => $produk->price * $jumlah,
            ];
            $total += $produk->price * $jumlah;
        }

        return [
            'local_uuid' => $uuid,
            'invoice_number' => 'INV-20261015-'.strtoupper(substr($uuid, 0, 6)),
            'payment_method' => $metode,
            'total_amount' => $total,
            // 15 Okt 2026, 10.30 WIB.
            'created_at' => '2026-10-15T03:30:00Z',
            'items' => $items,
        ];
    }

    public function test_alur_penuh_dari_kasir_ke_dashboard_dan_kembali(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-10-15 11:00:00', 'Asia/Jakarta'));

        $owner = User::factory()->create(['role' => 'owner']);
        User::factory()->create(['email' => 'kasir@kantin.test', 'password' => 'rahasia-123', 'role' => 'cashier']);
        $kategori = Category::create(['name' => 'Makanan', 'slug' => 'makanan']);
        $nasi = Product::create(['category_id' => $kategori->id, 'name' => 'Nasi Goreng', 'price' => 15000, 'stock' => 10]);
        $teh = Product::create(['category_id' => $kategori->id, 'name' => 'Es Teh', 'price' => 5000, 'stock' => 6]);

        // 1. Kasir masuk dan membaca katalog.
        $token = $this->postJson('/api/auth/login', [
            'email' => 'kasir@kantin.test',
            'password' => 'rahasia-123',
            'device_name' => 'hp-kasir',
        ])->assertOk()->json('data.token');

        $this->withToken($token)->getJson('/api/catalog')
            ->assertOk()
            ->assertJsonFragment(['name' => 'Nasi Goreng'])
            ->assertJsonFragment(['name' => 'Es Teh']);

        // 2. Dua penjualan masuk; satu dikirim dua kali (jaringan putus-sambung).
        $a = $this->payload('aaaaaaaa-0000-4000-8000-000000000001', [[$nasi, 2]], 'cash');
        $b = $this->payload('bbbbbbbb-0000-4000-8000-000000000002', [[$teh, 3], [$nasi, 1]], 'qris');

        $this->postJson('/api/transactions', $a)->assertCreated()->assertJsonPath('meta.duplicate', false);
        $this->postJson('/api/transactions', $a)->assertOk()->assertJsonPath('meta.duplicate', true);
        $this->postJson('/api/transactions', $b)->assertCreated();

        $this->assertSame(2, Transaction::count(), 'Kiriman ulang tidak boleh membuat transaksi kedua.');
        $this->assertSame(7, $nasi->fresh()->stock, 'Stok hanya berkurang sekali per transaksi.');
        $this->assertSame(3, $teh->fresh()->stock);

        // 3. Stok server tidak cukup: ditolak utuh, tidak ada yang berubah.
        $c = $this->payload('cccccccc-0000-4000-8000-000000000003', [[$nasi, 20]], 'cash');
        $this->postJson('/api/transactions', $c)
            ->assertStatus(409)
            ->assertJsonPath('code', 'insufficient_stock');

        $this->assertSame(2, Transaction::count());
        $this->assertSame(7, $nasi->fresh()->stock);

        // 4. Owner melihat angka yang sama di semua lapisan dashboard.
        $laporan = app(ReportService::class)->summary('2026-10-15', '2026-10-15');
        $this->assertSame(60000, $laporan['revenue']);
        $this->assertSame(2, $laporan['transactions']);
        $this->assertSame(30000, $laporan['average']);
        $this->assertSame(['count' => 1, 'total' => 30000, 'share' => 50], $laporan['by_method']['cash']);
        $this->assertSame(['count' => 1, 'total' => 30000, 'share' => 50], $laporan['by_method']['qris']);

        $hariIni = app(DashboardSummaryService::class)->today();
        $this->assertSame(60000, $hariIni['revenue']);
        $this->assertSame(2, $hariIni['transactions']);

        $terlaris = app(StatistikService::class)->topProducts(7);
        $this->assertSame('Nasi Goreng', $terlaris[0]['name']);
        $this->assertSame(3, $terlaris[0]['quantity']);
        $this->assertSame(45000, $terlaris[0]['revenue']);
        $this->assertSame('Es Teh', $terlaris[1]['name']);

        foreach (['/admin', '/admin/transactions', '/admin/laporan', '/admin/statistik'] as $halaman) {
            $this->actingAs($owner)->get($halaman)->assertOk();
        }

        // 5. Owner menambah stok lewat layanan yang sama dengan aksi "Ubah Stok".
        app(ProductService::class)->adjustStock($nasi->fresh(), 20);
        $this->assertSame(27, $nasi->fresh()->stock);

        // Sesi web owner tidak boleh terbawa ke permintaan API kasir berikutnya.
        $this->app['auth']->forgetGuards();

        // 6. Kasir mengirim ulang transaksi yang tadi ditolak: kini diterima.
        $this->withToken($token)->postJson('/api/transactions', $c)
            ->assertCreated()
            ->assertJsonPath('meta.duplicate', false);

        $this->assertSame(3, Transaction::count());
        $this->assertSame(7, $nasi->fresh()->stock);

        $laporan = app(ReportService::class)->summary('2026-10-15', '2026-10-15');
        $this->assertSame(360000, $laporan['revenue']);
        $this->assertSame(3, $laporan['transactions']);
    }
}
