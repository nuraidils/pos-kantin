<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Storage;

class Product extends Model
{
    use SoftDeletes;

    /**
     * Batas "stok menipis" (DESIGN.md §15). Nilainya SAMA dengan
     * `Product.lowStockThreshold` di Flutter; ubah keduanya bersamaan.
     */
    public const LOW_STOCK_THRESHOLD = 5;

    protected $fillable = ['category_id', 'image', 'name', 'price', 'stock', 'is_active'];

    protected function casts(): array
    {
        return [
            'price' => 'integer',
            'stock' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function isLowStock(): bool
    {
        return $this->stock > 0 && $this->stock <= self::LOW_STOCK_THRESHOLD;
    }

    public function isOutOfStock(): bool
    {
        return $this->stock <= 0;
    }

    public function scopeLowStock(Builder $query): Builder
    {
        return $query->where('stock', '>', 0)->where('stock', '<=', self::LOW_STOCK_THRESHOLD);
    }

    public function scopeOutOfStock(Builder $query): Builder
    {
        return $query->where('stock', '<=', 0);
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    protected function imageUrl(): Attribute
    {
        return Attribute::get(
            fn () => $this->image ? Storage::disk('public')->url($this->image) : null
        );
    }
}
