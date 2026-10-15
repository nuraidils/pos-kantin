<?php

namespace Tests\Feature\Admin;

use App\Filament\Resources\Products\Pages\CreateProduct;
use App\Filament\Resources\Products\Pages\EditProduct;
use App\Filament\Resources\Products\Pages\ListProducts;
use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use Filament\Actions\Testing\TestAction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

class ProductResourceTest extends TestCase
{
    use RefreshDatabase;

    private Category $kategori;

    protected function setUp(): void
    {
        parent::setUp();

        $this->kategori = Category::create(['name' => 'Minuman', 'slug' => 'minuman']);
    }

    private function owner(): User
    {
        return User::factory()->create(['role' => 'owner']);
    }

    private function produk(string $nama = 'Es Teh', int $stok = 10): Product
    {
        return Product::create([
            'category_id' => $this->kategori->id,
            'name' => $nama,
            'price' => 5000,
            'stock' => $stok,
        ]);
    }

    public function test_daftar_menampilkan_produk(): void
    {
        $a = $this->produk('Es Teh');
        $b = $this->produk('Kopi Susu', 3);

        Livewire::actingAs($this->owner())
            ->test(ListProducts::class)
            ->assertCanSeeTableRecords([$a, $b]);
    }

    public function test_membuat_produk_dengan_stok_awal(): void
    {
        Livewire::actingAs($this->owner())
            ->test(CreateProduct::class)
            ->fillForm([
                'category_id' => $this->kategori->id,
                'name' => 'Jus Alpukat',
                'price' => 12000,
                'stock' => 8,
                'is_active' => true,
            ])
            ->call('create')
            ->assertHasNoFormErrors();

        $this->assertDatabaseHas('products', ['name' => 'Jus Alpukat', 'price' => 12000, 'stock' => 8, 'is_active' => true]);
    }

    public function test_harga_dan_stok_negatif_ditolak(): void
    {
        Livewire::actingAs($this->owner())
            ->test(CreateProduct::class)
            ->fillForm([
                'category_id' => $this->kategori->id,
                'name' => 'Salah',
                'price' => -1,
                'stock' => -5,
            ])
            ->call('create')
            ->assertHasFormErrors(['price', 'stock']);

        $this->assertDatabaseMissing('products', ['name' => 'Salah']);
    }

    public function test_menyimpan_formulir_edit_tidak_menimpa_stok_yang_sudah_berubah(): void
    {
        $produk = $this->produk('Es Teh', 10);

        $halaman = Livewire::actingAs($this->owner())
            ->test(EditProduct::class, ['record' => $produk->getRouteKey()]);

        // Sementara formulir terbuka, kasir menjual 4 buah dan transaksinya masuk.
        $produk->update(['stock' => 6]);

        $halaman
            ->fillForm(['name' => 'Es Teh Manis', 'price' => 6000])
            ->call('save')
            ->assertHasNoFormErrors();

        $produk->refresh();
        $this->assertSame('Es Teh Manis', $produk->name);
        $this->assertSame(6, $produk->stock);
    }

    public function test_ubah_stok_menambah_dan_mengurangi_dengan_selisih(): void
    {
        $produk = $this->produk('Es Teh', 10);
        $halaman = Livewire::actingAs($this->owner())->test(ListProducts::class);

        $halaman->callAction(TestAction::make('ubahStok')->table($produk), ['delta' => 5])
            ->assertNotified('Stok diperbarui');
        $this->assertSame(15, $produk->fresh()->stock);

        $halaman->callAction(TestAction::make('ubahStok')->table($produk), ['delta' => -3]);
        $this->assertSame(12, $produk->fresh()->stock);
    }

    public function test_ubah_stok_tidak_boleh_membuat_stok_negatif(): void
    {
        $produk = $this->produk('Es Teh', 2);

        Livewire::actingAs($this->owner())
            ->test(ListProducts::class)
            ->callAction(TestAction::make('ubahStok')->table($produk), ['delta' => -3])
            ->assertNotified('Stok tidak diubah');

        $this->assertSame(2, $produk->fresh()->stock);
    }

    public function test_hapus_produk_adalah_soft_delete(): void
    {
        $produk = $this->produk();

        Livewire::actingAs($this->owner())
            ->test(ListProducts::class)
            ->callAction(TestAction::make('delete')->table($produk));

        $this->assertSoftDeleted($produk);
        $this->assertDatabaseHas('products', ['id' => $produk->id]); // baris tetap ada
    }
}
