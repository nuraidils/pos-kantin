<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CatalogApiTest extends TestCase
{
    use RefreshDatabase;

    private function actingAsRole(string $role): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => $role]));
    }

    private function makeProduct(Category $category, string $name, array $extra = []): Product
    {
        return Product::create(array_merge([
            'category_id' => $category->id,
            'name' => $name,
            'price' => 10000,
            'stock' => 10,
        ], $extra));
    }

    public function test_tanpa_token_ditolak(): void
    {
        $this->getJson('/api/catalog')->assertUnauthorized();
    }

    public function test_owner_tidak_boleh_membaca_katalog_mobile(): void
    {
        $this->actingAsRole('owner');

        $this->getJson('/api/catalog')->assertForbidden();
    }

    public function test_sinkronisasi_penuh_tidak_menyertakan_data_terhapus_tapi_menyertakan_produk_nonaktif(): void
    {
        $this->actingAsRole('cashier');
        $category = Category::create(['name' => 'Minuman', 'slug' => 'minuman']);
        $this->makeProduct($category, 'Es Teh');
        $this->makeProduct($category, 'Kopi', ['is_active' => false]);
        $this->makeProduct($category, 'Dihapus')->delete();

        $response = $this->getJson('/api/catalog')->assertOk();

        $names = collect($response->json('data.products'))->pluck('name')->all();
        $this->assertEqualsCanonicalizing(['Es Teh', 'Kopi'], $names);
        $response->assertJsonPath('meta.full_sync', true);
    }

    public function test_sinkronisasi_inkremental_menyertakan_perubahan_dan_data_terhapus(): void
    {
        $this->actingAsRole('cashier');
        $category = Category::create(['name' => 'Makanan', 'slug' => 'makanan']);
        $lama = $this->makeProduct($category, 'Lama');
        $berubah = $this->makeProduct($category, 'Berubah');
        $dihapus = $this->makeProduct($category, 'Dihapus');

        Product::query()->whereKey($lama->id)->update(['updated_at' => '2026-01-01 00:00:00']);
        Product::query()->whereKey($berubah->id)->update(['updated_at' => '2026-10-01 00:00:00']);
        Product::query()->whereKey($dihapus->id)->update(['updated_at' => '2026-10-02 00:00:00']);
        Product::query()->whereKey($dihapus->id)->update([
            'deleted_at' => '2026-10-02 00:00:00', 'updated_at' => '2026-10-02 00:00:00',
        ]);

        $response = $this->getJson('/api/catalog?updated_since=2026-09-30T00:00:00Z')->assertOk();

        $products = collect($response->json('data.products'))->keyBy('name');
        $this->assertSame(['Berubah', 'Dihapus'], $products->keys()->sort()->values()->all());
        $this->assertNull($products['Berubah']['deleted_at']);
        $this->assertNotNull($products['Dihapus']['deleted_at']);
        $response->assertJsonPath('meta.full_sync', false);
    }

    public function test_updated_since_tidak_valid_menghasilkan_422(): void
    {
        $this->actingAsRole('cashier');

        $this->getJson('/api/catalog?updated_since=bukan-tanggal')
            ->assertUnprocessable()
            ->assertJsonValidationErrors('updated_since');
    }
}
