<?php

namespace Tests\Feature\Admin;

use App\Filament\Resources\Transactions\Pages\ListTransactions;
use App\Filament\Resources\Transactions\Pages\ViewTransaction;
use App\Models\Category;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

class TransactionResourceTest extends TestCase
{
    use RefreshDatabase;

    private function buatTransaksi(User $kasir, Product $produk, string $uuid, string $waktu, string $metode = 'cash'): Transaction
    {
        $transaksi = Transaction::create([
            'local_uuid' => $uuid,
            'user_id' => $kasir->id,
            'invoice_number' => 'INV-'.substr($uuid, 0, 8),
            'total_amount' => 20000,
            'payment_method' => $metode,
            'sync_status' => 'synced',
            'created_at' => $waktu,
            'synced_at' => $waktu,
        ]);
        $transaksi->items()->create([
            'product_id' => $produk->id,
            'product_name' => 'Kopi Susu (nama lama)',
            'quantity' => 2,
            'price' => 10000,
            'subtotal' => 20000,
        ]);

        return $transaksi;
    }

    private function siapkan(): array
    {
        $owner = User::factory()->create(['role' => 'owner']);
        $kasir = User::factory()->create(['role' => 'cashier']);
        $kategori = Category::create(['name' => 'Minuman', 'slug' => 'minuman']);
        $produk = Product::create(['category_id' => $kategori->id, 'name' => 'Kopi Susu', 'price' => 12000, 'stock' => 10]);

        return [$owner, $kasir, $produk];
    }

    public function test_daftar_menampilkan_transaksi(): void
    {
        [$owner, $kasir, $produk] = $this->siapkan();
        $a = $this->buatTransaksi($kasir, $produk, 'aaaaaaaa-0000-4000-8000-000000000001', '2026-10-14T03:00:00Z');
        $b = $this->buatTransaksi($kasir, $produk, 'bbbbbbbb-0000-4000-8000-000000000002', '2026-10-14T04:00:00Z', 'qris');

        Livewire::actingAs($owner)
            ->test(ListTransactions::class)
            ->assertCanSeeTableRecords([$a, $b]);
    }

    public function test_detail_memakai_snapshot_item_bukan_data_produk_sekarang(): void
    {
        [$owner, $kasir, $produk] = $this->siapkan();
        $transaksi = $this->buatTransaksi($kasir, $produk, 'cccccccc-0000-4000-8000-000000000003', '2026-10-14T03:00:00Z');

        // Produk berubah nama dan harga setelah transaksi.
        $produk->update(['name' => 'Kopi Susu Baru', 'price' => 15000]);

        Livewire::actingAs($owner)
            ->test(ViewTransaction::class, ['record' => $transaksi->getRouteKey()])
            ->assertSee('Kopi Susu (nama lama)')
            ->assertSee('Rp10.000')
            ->assertSee('Rp20.000')
            ->assertDontSee('Kopi Susu Baru');
    }

    public function test_transaksi_tidak_bisa_diubah_atau_dihapus_dari_dashboard(): void
    {
        [$owner, $kasir, $produk] = $this->siapkan();
        $transaksi = $this->buatTransaksi($kasir, $produk, 'dddddddd-0000-4000-8000-000000000004', '2026-10-14T03:00:00Z');

        $this->actingAs($owner);

        $resource = \App\Filament\Resources\Transactions\TransactionResource::class;
        $this->assertFalse($resource::canCreate());
        $this->assertFalse($resource::canEdit($transaksi));
        $this->assertFalse($resource::canDelete($transaksi));
        $this->assertFalse($resource::canDeleteAny());
    }
}
