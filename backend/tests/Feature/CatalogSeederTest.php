<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use Database\Seeders\CatalogSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CatalogSeederTest extends TestCase
{
    use RefreshDatabase;

    public function test_seeder_aman_dijalankan_berulang(): void
    {
        $this->seed(CatalogSeeder::class);
        $kategori = Category::withTrashed()->count();
        $produk = Product::withTrashed()->count();

        $this->seed(CatalogSeeder::class);

        $this->assertSame(3, $kategori);
        $this->assertSame($kategori, Category::withTrashed()->count());
        $this->assertSame($produk, Product::withTrashed()->count());
    }

    public function test_seeder_membuat_kasus_uji_yang_dibutuhkan_aplikasi(): void
    {
        $this->seed(CatalogSeeder::class);

        $this->assertSame(1, Product::onlyTrashed()->count());
        $this->assertSame(1, Product::where('is_active', false)->count());
        $this->assertSame(1, Product::where('stock', 0)->count());
        $this->assertTrue(Product::where('stock', '>', 0)->where('stock', '<=', 5)->exists());
    }

    public function test_seeder_tidak_mengembalikan_stok_yang_sudah_berubah(): void
    {
        $this->seed(CatalogSeeder::class);
        Product::where('name', 'Nasi Goreng')->update(['stock' => 1]);

        $this->seed(CatalogSeeder::class);

        $this->assertSame(1, Product::where('name', 'Nasi Goreng')->value('stock'));
    }

    public function test_kasir_menerima_katalog_uji_tanpa_produk_terhapus(): void
    {
        $this->seed(CatalogSeeder::class);
        Sanctum::actingAs(User::factory()->create(['role' => 'cashier']));

        $response = $this->getJson('/api/catalog')->assertOk();

        $names = collect($response->json('data.products'))->pluck('name');
        $this->assertCount(Product::count(), $names);
        $this->assertNotContains('Produk Dihapus (uji)', $names->all());
        $this->assertContains('Es Campur (nonaktif)', $names->all());
        $this->assertCount(3, $response->json('data.categories'));
    }
}
