<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** Akses ke POST /api/transactions: hanya kasir dengan token (AGENTS.md §8). */
class TransactionAccessTest extends TestCase
{
    use RefreshDatabase;

    private function payloadUntuk(Product $produk): array
    {
        return [
            'local_uuid' => '11111111-1111-4111-8111-111111111111',
            'payment_method' => 'cash',
            'total_amount' => 10000,
            'created_at' => '2026-10-11T08:30:00Z',
            'items' => [['product_id' => $produk->id, 'quantity' => 1, 'price' => 10000, 'subtotal' => 10000]],
        ];
    }

    private function makeProduct(): Product
    {
        $category = Category::create(['name' => 'Minuman', 'slug' => 'minuman']);

        return Product::create(['category_id' => $category->id, 'name' => 'Es Teh', 'price' => 10000, 'stock' => 10]);
    }

    public function test_tanpa_token_ditolak(): void
    {
        $produk = $this->makeProduct();

        $this->postJson('/api/transactions', $this->payloadUntuk($produk))->assertUnauthorized();

        $this->assertDatabaseCount('transactions', 0);
    }

    public function test_owner_tidak_boleh_mengirim_transaksi(): void
    {
        $produk = $this->makeProduct();
        Sanctum::actingAs(User::factory()->create(['role' => 'owner']));

        $this->postJson('/api/transactions', $this->payloadUntuk($produk))->assertForbidden();

        $this->assertDatabaseCount('transactions', 0);
        $this->assertSame(10, $produk->fresh()->stock);
    }

    public function test_peran_dibaca_dari_database_bukan_dari_request(): void
    {
        $produk = $this->makeProduct();
        Sanctum::actingAs(User::factory()->create(['role' => 'owner']));

        $this->postJson('/api/transactions', $this->payloadUntuk($produk) + ['role' => 'cashier'])->assertForbidden();

        $this->assertDatabaseCount('transactions', 0);
    }
}
