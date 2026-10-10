<?php

namespace Database\Seeders;

use App\Models\Category;
use App\Models\Product;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Data uji katalog untuk pengembangan, sampai resource Filament (tahap 16)
 * tersedia. TIDAK dipanggil dari DatabaseSeeder; jalankan sengaja:
 *
 *   php artisan db:seed --class=CatalogSeeder
 *
 * Aman dijalankan berulang: data yang sudah ada tidak diduplikasi dan stok
 * yang sudah berubah tidak dikembalikan ke nilai awal.
 *
 * Mencakup kasus yang perlu dilihat di aplikasi: stok menipis, stok habis,
 * produk nonaktif (tidak boleh muncul di kasir), dan produk terhapus
 * (tidak boleh muncul sama sekali).
 */
class CatalogSeeder extends Seeder
{
    /**
     * Format produk: [nama, harga, stok, aktif, terhapus].
     *
     * @var array<string, list<array{0: string, 1: int, 2: int, 3?: bool, 4?: bool}>>
     */
    private const CATALOG = [
        'Makanan' => [
            ['Nasi Goreng', 15000, 20],
            ['Mie Ayam', 12000, 15],
            ['Ayam Geprek', 14000, 4],            // stok menipis
            ['Batagor', 10000, 0],                // habis
            ['Es Campur (nonaktif)', 13000, 10, false],
        ],
        'Minuman' => [
            ['Es Teh Manis', 5000, 50],
            ['Kopi Susu', 10000, 3],              // stok menipis
            ['Air Mineral', 3000, 100],
            ['Jus Alpukat', 12000, 8],
        ],
        'Camilan' => [
            ['Risol Mayo', 3000, 30],
            ['Pisang Goreng', 2500, 25],
            ['Produk Dihapus (uji)', 9000, 5, true, true],
        ],
    ];

    public function run(): void
    {
        foreach (self::CATALOG as $categoryName => $products) {
            $category = Category::withTrashed()->firstOrCreate(
                ['slug' => Str::slug($categoryName)],
                ['name' => $categoryName],
            );

            if ($category->trashed()) {
                $category->restore();
            }

            foreach ($products as $row) {
                [$name, $price, $stock] = $row;
                $active = $row[3] ?? true;
                $deleted = $row[4] ?? false;

                $product = Product::withTrashed()->firstOrCreate(
                    ['category_id' => $category->id, 'name' => $name],
                    ['price' => $price, 'stock' => $stock, 'is_active' => $active],
                );

                if ($deleted && ! $product->trashed()) {
                    $product->delete();
                } elseif (! $deleted && $product->trashed()) {
                    $product->restore();
                }
            }
        }
    }
}
