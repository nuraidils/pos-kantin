<?php

namespace Tests\Feature\Admin;

use App\Filament\Pages\Statistik;
use App\Filament\Widgets\StatistikPerforma;
use App\Filament\Widgets\StatistikProdukTerlaris;
use App\Filament\Widgets\StatistikStokPerhatian;
use App\Filament\Widgets\StatistikTren;
use App\Models\Category;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\TransactionItem;
use App\Models\User;
use App\Services\StatistikService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

class StatistikTest extends TestCase
{
    use RefreshDatabase;

    private User $kasir;

    private Product $nasiGoreng;

    private Product $esTeh;

    protected function setUp(): void
    {
        parent::setUp();

        // Kamis, 15 Oktober 2026, 10.00 WIB. Jendela 7 hari = 9-15 Okt WIB;
        // pembanding = 2-8 Okt WIB.
        Carbon::setTestNow(Carbon::parse('2026-10-15 10:00:00', 'Asia/Jakarta'));

        $this->kasir = User::factory()->create(['role' => 'cashier']);
        $kategori = Category::create(['name' => 'Makanan', 'slug' => 'makanan']);
        $this->nasiGoreng = Product::create(['category_id' => $kategori->id, 'name' => 'Nasi Goreng', 'price' => 5000, 'stock' => 20, 'is_active' => true]);
        $this->esTeh = Product::create(['category_id' => $kategori->id, 'name' => 'Es Teh', 'price' => 5000, 'stock' => 20, 'is_active' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function transaksi(string $uuid, int $total, string $waktuUtc, array $items = []): Transaction
    {
        $trx = Transaction::create([
            'local_uuid' => $uuid,
            'user_id' => $this->kasir->id,
            'invoice_number' => 'INV-'.substr($uuid, 0, 8),
            'total_amount' => $total,
            'payment_method' => 'cash',
            'sync_status' => 'synced',
            'created_at' => $waktuUtc,
            'synced_at' => $waktuUtc,
        ]);

        foreach ($items as [$produk, $jumlah, $subtotal]) {
            TransactionItem::create([
                'transaction_id' => $trx->id,
                'product_id' => $produk->id,
                'product_name' => $produk->name,
                'quantity' => $jumlah,
                'price' => intdiv($subtotal, $jumlah),
                'subtotal' => $subtotal,
            ]);
        }

        return $trx;
    }

    private function dataContoh(): void
    {
        // Jendela sekarang (9-15 Okt WIB)
        $this->transaksi('aaaaaaaa-0000-4000-8000-000000000001', 10000, '2026-10-10T03:00:00Z', [[$this->nasiGoreng, 2, 10000]]); // Sab 10.00
        $this->transaksi('bbbbbbbb-0000-4000-8000-000000000002', 20000, '2026-10-10T05:00:00Z', [[$this->esTeh, 3, 15000], [$this->nasiGoreng, 1, 5000]]); // Sab 12.00
        $this->transaksi('cccccccc-0000-4000-8000-000000000003', 30000, '2026-10-15T05:30:00Z', [[$this->nasiGoreng, 1, 5000]]); // Kam 12.30
        // Jendela pembanding (2-8 Okt WIB)
        $this->transaksi('dddddddd-0000-4000-8000-000000000004', 20000, '2026-10-05T03:00:00Z', [[$this->nasiGoreng, 10, 50000]]);
        $this->transaksi('eeeeeeee-0000-4000-8000-000000000005', 10000, '2026-10-08T16:59:00Z'); // 8 Okt 23.59 WIB
    }

    public function test_pilihan_periode_tidak_dikenal_jatuh_ke_7_hari(): void
    {
        $service = app(StatistikService::class);

        $this->assertSame(7, $service->days(null));
        $this->assertSame(7, $service->days('abc'));
        $this->assertSame(7, $service->days('14'));
        $this->assertSame(30, $service->days('30'));
        $this->assertSame('9 Okt 2026 - 15 Okt 2026', $service->periodLabel(7));
    }

    public function test_tren_mengisi_hari_kosong_dan_mengikuti_hari_wib(): void
    {
        $this->dataContoh();

        $tren = app(StatistikService::class)->trend(7);

        $this->assertCount(7, $tren);
        $this->assertSame('2026-10-09', $tren[0]['date']);
        $this->assertSame('2026-10-15', $tren[6]['date']);
        $this->assertSame([0, 30000, 0, 0, 0, 0, 30000], array_column($tren, 'revenue'));
        $this->assertSame([0, 2, 0, 0, 0, 0, 1], array_column($tren, 'transactions'));
        $this->assertSame('10 Okt', $tren[1]['label']);
    }

    public function test_perbandingan_dengan_periode_sebelumnya(): void
    {
        $this->dataContoh();

        $banding = app(StatistikService::class)->comparison(7);

        $this->assertSame(60000, $banding['revenue']);
        $this->assertSame(30000, $banding['previous']);
        $this->assertSame(100, $banding['change']);
    }

    public function test_perbandingan_tanpa_pembanding_bernilai_null(): void
    {
        $this->transaksi('aaaaaaaa-0000-4000-8000-000000000001', 10000, '2026-10-10T03:00:00Z');

        $banding = app(StatistikService::class)->comparison(7);

        $this->assertSame(10000, $banding['revenue']);
        $this->assertNull($banding['change']);
    }

    public function test_hari_dan_jam_tersibuk(): void
    {
        $this->dataContoh();

        $sibuk = app(StatistikService::class)->busiest(7);

        $this->assertSame(['name' => 'Sabtu', 'count' => 2], $sibuk['day']);
        $this->assertSame(['label' => '12.00 - 13.00', 'count' => 2], $sibuk['hour']);
    }

    public function test_tanpa_transaksi_semuanya_kosong_tanpa_error(): void
    {
        $service = app(StatistikService::class);

        $this->assertSame(['day' => null, 'hour' => null], $service->busiest(7));
        $this->assertSame([], $service->topProducts(7));
        $this->assertSame(0, $service->comparison(7)['revenue']);
        $this->assertSame(array_fill(0, 7, 0), array_column($service->trend(7), 'revenue'));
    }

    public function test_produk_terlaris_hanya_dari_jendela_dan_terurut(): void
    {
        $this->dataContoh();

        $this->assertSame([
            ['rank' => 1, 'name' => 'Nasi Goreng', 'quantity' => 4, 'revenue' => 20000],
            ['rank' => 2, 'name' => 'Es Teh', 'quantity' => 3, 'revenue' => 15000],
        ], app(StatistikService::class)->topProducts(7));

        // Jendela 30 hari ikut menghitung 10 Nasi Goreng dari 5 Okt.
        $this->assertSame(14, app(StatistikService::class)->topProducts(30)[0]['quantity']);
    }

    public function test_produk_terhapus_tetap_muncul_di_terlaris(): void
    {
        $this->dataContoh();
        $this->esTeh->delete();

        $nama = array_column(app(StatistikService::class)->topProducts(7), 'name');

        $this->assertContains('Es Teh', $nama);
    }

    public function test_stok_perlu_perhatian_hanya_produk_aktif_yang_habis_atau_menipis(): void
    {
        $kategori = Category::first();
        $buat = fn (string $nama, int $stok, bool $aktif = true) => Product::create([
            'category_id' => $kategori->id, 'name' => $nama, 'price' => 1000, 'stock' => $stok, 'is_active' => $aktif,
        ]);
        $habis = $buat('Habis', 0);
        $menipis = $buat('Menipis', 3);
        $batas = $buat('Batas', 5);
        $aman = $buat('Aman', 6);
        $nonaktif = $buat('Nonaktif', 0, false);

        $owner = User::factory()->create(['role' => 'owner']);

        Livewire::actingAs($owner)->test(StatistikStokPerhatian::class)
            ->assertCanSeeTableRecords([$habis, $menipis, $batas])
            ->assertCanNotSeeTableRecords([$aman, $nonaktif]);
    }

    public function test_kasir_tidak_boleh_membuka_statistik(): void
    {
        $this->actingAs($this->kasir)->get('/admin/statistik')->assertForbidden();
    }

    public function test_owner_membuka_statistik_dan_semua_widget_dapat_dirender(): void
    {
        $this->dataContoh();
        $owner = User::factory()->create(['role' => 'owner']);

        $this->actingAs($owner)->get('/admin/statistik')->assertOk();

        Livewire::actingAs($owner)->test(Statistik::class)->assertOk();

        foreach ([StatistikPerforma::class, StatistikTren::class] as $widget) {
            Livewire::actingAs($owner)->test($widget, ['pageFilters' => ['periode' => '30']])->assertOk();
        }

        Livewire::actingAs($owner)->test(StatistikProdukTerlaris::class, ['pageFilters' => ['periode' => '7']])
            ->assertOk()
            ->assertSee('Nasi Goreng');
    }
}
