<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\StoreTransactionRequest;
use App\Http\Resources\Api\TransactionResource;
use App\Services\TransactionService;
use Illuminate\Http\JsonResponse;

class TransactionController extends Controller
{
    /**
     * 201 = transaksi baru tersimpan. 200 = local_uuid sudah pernah diterima
     * (idempoten): hasil lama dikembalikan, tidak ada yang berubah. Bagi
     * perangkat keduanya berarti "sudah ada di server" (synced).
     */
    public function store(StoreTransactionRequest $request, TransactionService $transactions): JsonResponse
    {
        $result = $transactions->store($request->user(), $request->validated());

        return response()->json([
            'data' => (new TransactionResource($result['transaction']))->resolve(),
            'meta' => ['duplicate' => ! $result['created']],
        ], $result['created'] ? 201 : 200);
    }
}
