<?php

namespace App\Services;

use App\Models\Category;
use Illuminate\Support\Str;

class CategoryService
{
    /**
     * Slug unik dari nama. Kolom `slug` UNIQUE juga mencakup kategori yang
     * sudah dihapus (soft delete), jadi pengecekan memakai withTrashed();
     * bila bentrok diberi akhiran -2, -3, ... (seperti nomor invoice).
     */
    public function makeSlug(string $name): string
    {
        $base = Str::slug($name) ?: 'kategori';
        $slug = $base;

        for ($i = 2; Category::withTrashed()->where('slug', $slug)->exists(); $i++) {
            $slug = "{$base}-{$i}";
        }

        return $slug;
    }
}
