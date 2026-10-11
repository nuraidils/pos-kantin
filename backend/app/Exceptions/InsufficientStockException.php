<?php

namespace App\Exceptions;

use Exception;
use Illuminate\Http\JsonResponse;

/**
 * Konflik bisnis (AGENTS.md §13.4, §17): transaksi sah tetapi tidak bisa
 * diterapkan dengan aman karena stok server tidak cukup. Respons 409 membuat
 * Flutter menandai transaksi lokal sebagai `conflict` (Tahap 14), bukan `failed`.
 */
class InsufficientStockException extends Exception
{
    /**
     * @param  list<array{product_id: int, product_name: string, requested: int, available: int}>  $shortages
     */
    public function __construct(public readonly array $shortages)
    {
        parent::__construct('Stok produk di server tidak mencukupi.');
    }

    public function render(): JsonResponse
    {
        return response()->json([
            'message' => 'Stok produk tidak mencukupi. Transaksi belum berhasil disinkronkan.',
            'code' => 'insufficient_stock',
            'shortages' => $this->shortages,
        ], 409);
    }
}
