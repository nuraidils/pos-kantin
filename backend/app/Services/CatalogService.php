<?php

namespace App\Services;

use App\Models\Category;
use App\Models\Product;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;

class CatalogService
{
    /**
     * Sinkronisasi penuh ($since = null): hanya data yang belum dihapus.
     * Sinkronisasi inkremental: semua perubahan sejak $since, TERMASUK yang
     * di-soft-delete (deleted_at terisi) agar perangkat bisa menghapusnya lokal.
     * Produk non-aktif tetap dikirim (is_active=false); Flutter yang menyaring.
     *
     * @return array{categories: Collection, products: Collection}
     */
    public function changesSince(?CarbonInterface $since): array
    {
        $categories = Category::query()->orderBy('updated_at')->orderBy('id');
        $products = Product::query()->orderBy('updated_at')->orderBy('id');

        if ($since !== null) {
            // '>=' + timestamp detik penuh: duplikasi tidak berbahaya (upsert
            // idempoten), sedangkan kehilangan baris di batas detik berbahaya.
            $categories->withTrashed()->where('updated_at', '>=', $since);
            $products->withTrashed()->where('updated_at', '>=', $since);
        }

        return [
            'categories' => $categories->get(),
            'products' => $products->get(),
        ];
    }
}
