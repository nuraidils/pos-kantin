<?php

namespace Tests\Feature\Admin;

use App\Filament\Resources\Categories\Pages\ManageCategories;
use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use App\Services\CategoryService;
use Filament\Actions\Testing\TestAction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

class CategoryResourceTest extends TestCase
{
    use RefreshDatabase;

    private function owner(): User
    {
        return User::factory()->create(['role' => 'owner']);
    }

    public function test_daftar_menampilkan_kategori(): void
    {
        $makanan = Category::create(['name' => 'Makanan', 'slug' => 'makanan']);
        $minuman = Category::create(['name' => 'Minuman', 'slug' => 'minuman']);

        Livewire::actingAs($this->owner())
            ->test(ManageCategories::class)
            ->assertCanSeeTableRecords([$makanan, $minuman]);
    }

    public function test_membuat_kategori_mengisi_slug_dari_server(): void
    {
        Livewire::actingAs($this->owner())
            ->test(ManageCategories::class)
            ->callAction('create', ['name' => 'Es Teh & Kopi'])
            ->assertHasNoFormErrors();

        $this->assertDatabaseHas('categories', ['name' => 'Es Teh & Kopi', 'slug' => 'es-teh-kopi']);
    }

    public function test_slug_bentrok_diberi_akhiran_termasuk_kategori_terhapus(): void
    {
        $lama = Category::create(['name' => 'Camilan', 'slug' => 'camilan']);
        $lama->delete(); // slug masih terpakai di database (UNIQUE mencakup soft delete)

        $service = app(CategoryService::class);

        $this->assertSame('camilan-2', $service->makeSlug('Camilan'));
        $this->assertSame('kategori', $service->makeSlug('!!!'));
    }

    public function test_kategori_berisi_produk_tidak_bisa_dihapus(): void
    {
        $kategori = Category::create(['name' => 'Makanan', 'slug' => 'makanan']);
        Product::create(['category_id' => $kategori->id, 'name' => 'Nasi Goreng', 'price' => 15000, 'stock' => 5]);

        Livewire::actingAs($this->owner())
            ->test(ManageCategories::class)
            ->callAction(TestAction::make('delete')->table($kategori))
            ->assertNotified('Kategori tidak dapat dihapus');

        $this->assertNotSoftDeleted($kategori);
    }

    public function test_kategori_kosong_bisa_dihapus_dan_tersimpan_sebagai_soft_delete(): void
    {
        $kategori = Category::create(['name' => 'Kosong', 'slug' => 'kosong']);

        Livewire::actingAs($this->owner())
            ->test(ManageCategories::class)
            ->callAction(TestAction::make('delete')->table($kategori));

        $this->assertSoftDeleted($kategori);
    }
}
