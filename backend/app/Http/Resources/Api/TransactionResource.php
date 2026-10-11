<?php

namespace App\Http\Resources\Api;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Transaction */
class TransactionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'local_uuid' => $this->local_uuid,
            // Bisa berbeda dari yang dikirim perangkat bila bertabrakan (diberi akhiran).
            'invoice_number' => $this->invoice_number,
            'total_amount' => $this->total_amount,
            'payment_method' => $this->payment_method->value,
            'sync_status' => $this->sync_status->value,
            'created_at' => $this->created_at->toIso8601String(),
            'synced_at' => $this->synced_at?->toIso8601String(),
            'items' => $this->items->map(fn ($item) => [
                'product_id' => $item->product_id,
                'product_name' => $item->product_name,
                'quantity' => $item->quantity,
                'price' => $item->price,
                'subtotal' => $item->subtotal,
            ])->all(),
        ];
    }
}
