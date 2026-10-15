<?php

namespace Tests\Feature\Admin;

use App\Models\Category;
use App\Models\Product;
use App\Services\ProductService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use InvalidArgumentException;
use Tests\TestCase;

class ProductServiceTest extends TestCase
{
    use RefreshDatabase;

    private function produk(int $stok): Product
    {
        $kategori = Category::create(['name' => 'Minuman', 'slug' => 'minuman']);

        return Product::create(['category_id' => $kategori->id, 'name' => 'Es Teh', 'price' => 5000, 'stock' => $stok]);
    }

    public function test_selisih_dihitung_dari_stok_terbaru_di_database(): void
    {
        $produk = $this->produk(10);
        $salinanLama = Product::find($produk->id); // dipegang sebelum stok berubah

        Product::whereKey($produk->id)->update(['stock' => 6]); // penjualan masuk

        $hasil = app(ProductService::class)->adjustStock($salinanLama, 5);

        $this->assertSame(11, $hasil->stock);
        $this->assertSame(11, $produk->fresh()->stock);
    }

    public function test_hasil_di_bawah_nol_ditolak_dan_stok_tidak_berubah(): void
    {
        $produk = $this->produk(2);

        $this->expectException(InvalidArgumentException::class);

        try {
            app(ProductService::class)->adjustStock($produk, -3);
        } finally {
            $this->assertSame(2, $produk->fresh()->stock);
        }
    }

    public function test_selisih_nol_ditolak(): void
    {
        $produk = $this->produk(2);

        $this->expectException(InvalidArgumentException::class);

        app(ProductService::class)->adjustStock($produk, 0);
    }

    public function test_updated_at_berubah_agar_terbawa_ke_sinkronisasi_katalog(): void
    {
        $produk = $this->produk(5);
        Product::whereKey($produk->id)->update(['updated_at' => '2026-01-01 00:00:00']);

        app(ProductService::class)->adjustStock($produk->fresh(), 1);

        $this->assertTrue($produk->fresh()->updated_at->greaterThan('2026-01-01 00:00:00'));
    }

    public function test_batas_stok_menipis_sama_dengan_flutter(): void
    {
        $this->assertSame(5, Product::LOW_STOCK_THRESHOLD);
        $this->assertTrue($this->produk(5)->isLowStock());
    }
}
