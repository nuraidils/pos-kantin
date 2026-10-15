<?php

namespace App\Services;

use App\Models\Product;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

class ProductService
{
    /**
     * Mengubah stok server dengan SELISIH (+ menambah, - mengurangi), bukan
     * menimpa dengan angka baru. Stok server berubah juga oleh transaksi yang
     * masuk dari kasir (AGENTS.md §13); menimpa nilai lama dari formulir yang
     * sudah terbuka beberapa menit akan menghapus penjualan yang terjadi di
     * sela-selanya. Baris dikunci agar tidak berbarengan dengan transaksi.
     *
     * Produk disimpan lewat Eloquent sehingga `updated_at` ikut berubah dan
     * perubahan terbawa ke perangkat pada sinkronisasi berikutnya.
     *
     * @throws InvalidArgumentException bila selisih 0 atau hasilnya di bawah 0
     */
    public function adjustStock(Product $product, int $delta): Product
    {
        if ($delta === 0) {
            throw new InvalidArgumentException('Jumlah perubahan stok tidak boleh 0.');
        }

        return DB::transaction(function () use ($product, $delta): Product {
            $locked = Product::withTrashed()->lockForUpdate()->findOrFail($product->getKey());
            $newStock = $locked->stock + $delta;

            if ($newStock < 0) {
                throw new InvalidArgumentException(
                    "Stok tidak boleh kurang dari 0. Stok saat ini {$locked->stock}."
                );
            }

            $locked->stock = $newStock;
            $locked->save();

            return $locked;
        });
    }
}
