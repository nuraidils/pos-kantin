<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TransactionApiTest extends TestCase
{
    use RefreshDatabase;

    private Category $category;

    private User $cashier;

    protected function setUp(): void
    {
        parent::setUp();

        $this->category = Category::create(['name' => 'Minuman', 'slug' => 'minuman']);
        $this->cashier = User::factory()->create(['role' => 'cashier']);
        Sanctum::actingAs($this->cashier);
    }

    private function makeProduct(string $name, int $price = 10000, int $stock = 10, array $extra = []): Product
    {
        return Product::create(array_merge([
            'category_id' => $this->category->id,
            'name' => $name,
            'price' => $price,
            'stock' => $stock,
        ], $extra));
    }

    /** Payload valid; total dan subtotal dihitung dari item. */
    private function payload(array $lines, array $override = []): array
    {
        $items = [];
        $total = 0;
        foreach ($lines as [$product, $quantity]) {
            $items[] = [
                'product_id' => $product->id,
                'quantity' => $quantity,
                'price' => $product->price,
                'subtotal' => $product->price * $quantity,
            ];
            $total += $product->price * $quantity;
        }

        return array_merge([
            'local_uuid' => (string) Str::uuid(),
            'invoice_number' => 'INV-20261011-ABC123',
            'payment_method' => 'cash',
            'total_amount' => $total,
            'created_at' => '2026-10-11T08:30:00Z',
            'items' => $items,
        ], $override);
    }

    // ---- Sukses ----

    public function test_transaksi_baru_tersimpan_dengan_item_snapshot_dan_stok_berkurang(): void
    {
        $teh = $this->makeProduct('Es Teh', 5000, 10);
        $kopi = $this->makeProduct('Kopi Susu', 10000, 4);
        $payload = $this->payload([[$teh, 2], [$kopi, 3]], ['payment_method' => 'qris']);

        $this->postJson('/api/transactions', $payload)
            ->assertCreated()
            ->assertJsonPath('meta.duplicate', false)
            ->assertJsonPath('data.local_uuid', $payload['local_uuid'])
            ->assertJsonPath('data.invoice_number', 'INV-20261011-ABC123')
            ->assertJsonPath('data.total_amount', 40000)
            ->assertJsonPath('data.payment_method', 'qris')
            ->assertJsonPath('data.sync_status', 'synced')
            ->assertJsonCount(2, 'data.items');

        $transaction = Transaction::sole();
        $this->assertSame($this->cashier->id, $transaction->user_id);
        $this->assertNotNull($transaction->synced_at);
        // created_at = waktu penjualan dari perangkat, bukan waktu upload.
        $this->assertSame('2026-10-11 08:30:00', $transaction->created_at->utc()->format('Y-m-d H:i:s'));

        $this->assertDatabaseHas('transaction_items', [
            'transaction_id' => $transaction->id, 'product_id' => $teh->id,
            'product_name' => 'Es Teh', 'quantity' => 2, 'price' => 5000, 'subtotal' => 10000,
        ]);
        $this->assertSame(8, $teh->fresh()->stock);
        $this->assertSame(1, $kopi->fresh()->stock);
    }

    public function test_stok_boleh_habis_tepat_nol(): void
    {
        $produk = $this->makeProduct('Gorengan', 2000, 3);

        $this->postJson('/api/transactions', $this->payload([[$produk, 3]]))->assertCreated();

        $this->assertSame(0, $produk->fresh()->stock);
    }

    public function test_pengurangan_stok_mengubah_updated_at_agar_terbawa_sinkronisasi_katalog(): void
    {
        $produk = $this->makeProduct('Es Teh', 5000, 10);
        Product::query()->whereKey($produk->id)->update(['updated_at' => '2026-01-01 00:00:00']);

        $this->postJson('/api/transactions', $this->payload([[$produk, 2]]))->assertCreated();

        $this->assertTrue($produk->fresh()->updated_at->isAfter('2026-10-01'));

        $response = $this->getJson('/api/catalog?updated_since=2026-10-01T00:00:00Z')->assertOk();
        $item = collect($response->json('data.products'))->firstWhere('id', $produk->id);
        $this->assertNotNull($item);
        $this->assertSame(8, $item['stock']);
    }

    public function test_harga_riwayat_tetap_harga_saat_penjualan_walau_harga_produk_berubah(): void
    {
        $produk = $this->makeProduct('Kopi Susu', 10000, 10);
        $payload = $this->payload([[$produk, 1]]);
        $produk->update(['price' => 12000]); // owner menaikkan harga sebelum sinkron

        $this->postJson('/api/transactions', $payload)->assertCreated();

        $this->assertDatabaseHas('transaction_items', ['product_id' => $produk->id, 'price' => 10000, 'subtotal' => 10000]);
        $this->assertSame(10000, Transaction::sole()->total_amount);
    }

    public function test_produk_yang_dinonaktifkan_atau_dihapus_sejak_sinkron_terakhir_tetap_diterima(): void
    {
        $nonaktif = $this->makeProduct('Nonaktif', 5000, 5, ['is_active' => false]);
        $dihapus = $this->makeProduct('Dihapus', 5000, 5);
        $payload = $this->payload([[$nonaktif, 1], [$dihapus, 2]]);
        $dihapus->delete();

        $this->postJson('/api/transactions', $payload)->assertCreated();

        $this->assertSame(4, $nonaktif->fresh()->stock);
        $this->assertSame(3, Product::withTrashed()->find($dihapus->id)->stock);
    }

    public function test_nomor_invoice_dibuat_server_bila_tidak_dikirim(): void
    {
        $produk = $this->makeProduct('Es Teh');
        $payload = $this->payload([[$produk, 1]], [
            'local_uuid' => 'abcdef12-0000-4000-8000-000000000000',
            'invoice_number' => null,
        ]);

        $this->postJson('/api/transactions', $payload)
            ->assertCreated()
            ->assertJsonPath('data.invoice_number', 'INV-20261011-ABCDEF');
    }

    // ---- Idempotensi (Rule 5) ----

    public function test_local_uuid_berulang_mengembalikan_hasil_lama_tanpa_transaksi_atau_pengurangan_stok_kedua(): void
    {
        $produk = $this->makeProduct('Es Teh', 5000, 10);
        $payload = $this->payload([[$produk, 2]]);

        $pertama = $this->postJson('/api/transactions', $payload)->assertCreated();
        $kedua = $this->postJson('/api/transactions', $payload)
            ->assertOk()
            ->assertJsonPath('meta.duplicate', true);

        $this->assertSame($pertama->json('data.id'), $kedua->json('data.id'));
        $this->assertSame($pertama->json('data.invoice_number'), $kedua->json('data.invoice_number'));
        $this->assertDatabaseCount('transactions', 1);
        $this->assertDatabaseCount('transaction_items', 1);
        $this->assertSame(8, $produk->fresh()->stock);
    }

    public function test_pengulangan_tetap_dijawab_sukses_walau_stok_kini_tidak_cukup_untuk_transaksi_yang_sama(): void
    {
        // Stok 5, jual 4: sukses (sisa 1). Mengirim ulang TIDAK boleh menjadi 409.
        $produk = $this->makeProduct('Es Teh', 5000, 5);
        $payload = $this->payload([[$produk, 4]]);

        $this->postJson('/api/transactions', $payload)->assertCreated();
        $this->postJson('/api/transactions', $payload)->assertOk()->assertJsonPath('meta.duplicate', true);

        $this->assertSame(1, $produk->fresh()->stock);
        $this->assertDatabaseCount('transactions', 1);
    }

    public function test_local_uuid_milik_pengguna_lain_ditolak(): void
    {
        $produk = $this->makeProduct('Es Teh');
        $payload = $this->payload([[$produk, 1]]);
        $this->postJson('/api/transactions', $payload)->assertCreated();

        Sanctum::actingAs(User::factory()->create(['role' => 'cashier']));

        $this->postJson('/api/transactions', $payload)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('local_uuid');
        $this->assertDatabaseCount('transactions', 1);
        $this->assertSame(9, $produk->fresh()->stock);
    }

    // ---- Tabrakan nomor invoice ----

    public function test_nomor_invoice_bertabrakan_diberi_akhiran_dan_transaksi_sah_tetap_diterima(): void
    {
        $produk = $this->makeProduct('Es Teh', 5000, 10);

        $a = $this->postJson('/api/transactions', $this->payload([[$produk, 1]]))->assertCreated();
        $b = $this->postJson('/api/transactions', $this->payload([[$produk, 1]]))->assertCreated();
        $c = $this->postJson('/api/transactions', $this->payload([[$produk, 1]]))->assertCreated();

        $this->assertSame('INV-20261011-ABC123', $a->json('data.invoice_number'));
        $this->assertSame('INV-20261011-ABC123-2', $b->json('data.invoice_number'));
        $this->assertSame('INV-20261011-ABC123-3', $c->json('data.invoice_number'));
        $this->assertDatabaseCount('transactions', 3);
        $this->assertSame(7, $produk->fresh()->stock);
    }

    public function test_akhiran_invoice_tidak_melebihi_panjang_kolom(): void
    {
        $produk = $this->makeProduct('Es Teh');
        $panjang = str_repeat('A', 40);

        $this->postJson('/api/transactions', $this->payload([[$produk, 1]], ['invoice_number' => $panjang]))->assertCreated();
        $kedua = $this->postJson('/api/transactions', $this->payload([[$produk, 1]], ['invoice_number' => $panjang]))->assertCreated();

        $this->assertSame(40, strlen($kedua->json('data.invoice_number')));
        $this->assertStringEndsWith('-2', $kedua->json('data.invoice_number'));
    }

    // ---- Stok kurang (409) ----

    public function test_stok_server_kurang_menghasilkan_409_dan_tidak_ada_yang_tersimpan(): void
    {
        $produk = $this->makeProduct('Es Teh', 5000, 2);

        $this->postJson('/api/transactions', $this->payload([[$produk, 4]]))
            ->assertStatus(409)
            ->assertJsonPath('code', 'insufficient_stock')
            ->assertJsonPath('shortages.0.product_id', $produk->id)
            ->assertJsonPath('shortages.0.requested', 4)
            ->assertJsonPath('shortages.0.available', 2);

        $this->assertDatabaseCount('transactions', 0);
        $this->assertDatabaseCount('transaction_items', 0);
        $this->assertSame(2, $produk->fresh()->stock); // tidak negatif, tidak diubah diam-diam
    }

    public function test_satu_produk_kurang_membatalkan_seluruh_transaksi_atomik(): void
    {
        $cukup = $this->makeProduct('Cukup', 5000, 10);
        $kurang = $this->makeProduct('Kurang', 5000, 1);

        $this->postJson('/api/transactions', $this->payload([[$cukup, 3], [$kurang, 2]]))
            ->assertStatus(409)
            ->assertJsonCount(1, 'shortages');

        $this->assertDatabaseCount('transactions', 0);
        $this->assertSame(10, $cukup->fresh()->stock);
        $this->assertSame(1, $kurang->fresh()->stock);
    }

    public function test_setelah_409_transaksi_yang_sama_bisa_dicoba_lagi_saat_stok_sudah_cukup(): void
    {
        $produk = $this->makeProduct('Es Teh', 5000, 1);
        $payload = $this->payload([[$produk, 3]]);

        $this->postJson('/api/transactions', $payload)->assertStatus(409);
        $produk->update(['stock' => 10]); // owner menambah stok

        $this->postJson('/api/transactions', $payload)->assertCreated();
        $this->assertSame(7, $produk->fresh()->stock);
    }

    // ---- Validasi (422) ----

    /**
     * @return array<string, array{0: callable(array): array, 1: string}>
     */
    public static function payloadTidakValid(): array
    {
        return [
            'local_uuid kosong' => [fn ($p) => array_diff_key($p, ['local_uuid' => 1]), 'local_uuid'],
            'local_uuid bukan uuid' => [fn ($p) => [...$p, 'local_uuid' => 'bukan-uuid'], 'local_uuid'],
            'metode pembayaran tidak dikenal' => [fn ($p) => [...$p, 'payment_method' => 'kartu'], 'payment_method'],
            'metode pembayaran kosong' => [fn ($p) => array_diff_key($p, ['payment_method' => 1]), 'payment_method'],
            'item kosong' => [fn ($p) => [...$p, 'items' => []], 'items'],
            'item tidak ada' => [fn ($p) => array_diff_key($p, ['items' => 1]), 'items'],
            'jumlah nol' => [function ($p) {
                $p['items'][0]['quantity'] = 0;

                return $p;
            }, 'items.0.quantity'],
            'jumlah desimal' => [function ($p) {
                $p['items'][0]['quantity'] = 1.5;

                return $p;
            }, 'items.0.quantity'],
            'harga negatif' => [function ($p) {
                $p['items'][0]['price'] = -1;

                return $p;
            }, 'items.0.price'],
            'produk tidak ada' => [function ($p) {
                $p['items'][0]['product_id'] = 999999;

                return $p;
            }, 'items.0.product_id'],
            'subtotal tidak sesuai' => [function ($p) {
                $p['items'][0]['subtotal'] += 1;

                return $p;
            }, 'items.0.subtotal'],
            'total tidak sesuai' => [fn ($p) => [...$p, 'total_amount' => $p['total_amount'] + 1], 'total_amount'],
            'waktu transaksi di masa depan' => [fn ($p) => [...$p, 'created_at' => '2999-01-01T00:00:00Z'], 'created_at'],
            'waktu transaksi tidak valid' => [fn ($p) => [...$p, 'created_at' => 'kemarin'], 'created_at'],
            'nomor invoice mengandung karakter terlarang' => [fn ($p) => [...$p, 'invoice_number' => 'INV 1; DROP'], 'invoice_number'],
        ];
    }

    #[\PHPUnit\Framework\Attributes\DataProvider('payloadTidakValid')]
    public function test_payload_tidak_valid_menghasilkan_422_dan_tidak_mengubah_apa_pun(callable $ubah, string $field): void
    {
        $produk = $this->makeProduct('Es Teh', 5000, 10);

        $this->postJson('/api/transactions', $ubah($this->payload([[$produk, 2]])))
            ->assertUnprocessable()
            ->assertJsonValidationErrors($field);

        $this->assertDatabaseCount('transactions', 0);
        $this->assertSame(10, $produk->fresh()->stock);
    }

    public function test_produk_yang_sama_dua_kali_dalam_satu_transaksi_ditolak(): void
    {
        $produk = $this->makeProduct('Es Teh', 5000, 10);
        $payload = $this->payload([[$produk, 2], [$produk, 3]]);

        $this->postJson('/api/transactions', $payload)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('items.0.product_id');

        $this->assertSame(10, $produk->fresh()->stock);
    }

    public function test_pesan_validasi_berbahasa_indonesia(): void
    {
        $produk = $this->makeProduct('Es Teh');
        $payload = $this->payload([[$produk, 1]], ['items' => []]);

        $this->postJson('/api/transactions', $payload)
            ->assertJsonPath('errors.items.0', 'Transaksi harus memiliki minimal satu produk.');
    }
}
