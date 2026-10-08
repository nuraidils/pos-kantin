<?php

namespace App\Models;

use App\Enums\PaymentMethod;
use App\Enums\SyncStatus;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Transaction extends Model
{
    // Tabel hanya punya created_at (waktu penjualan dari perangkat) dan synced_at.
    const UPDATED_AT = null;

    protected $fillable = [
        'local_uuid', 'user_id', 'invoice_number', 'total_amount',
        'payment_method', 'sync_status', 'created_at', 'synced_at',
    ];

    protected function casts(): array
    {
        return [
            'total_amount' => 'integer',
            'payment_method' => PaymentMethod::class,
            'sync_status' => SyncStatus::class,
            'created_at' => 'datetime',
            'synced_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(TransactionItem::class);
    }
}
