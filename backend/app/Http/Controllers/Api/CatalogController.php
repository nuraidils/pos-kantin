<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\CatalogRequest;
use App\Http\Resources\Api\CategoryResource;
use App\Http\Resources\Api\ProductResource;
use App\Services\CatalogService;
use Illuminate\Http\JsonResponse;

class CatalogController extends Controller
{
    public function index(CatalogRequest $request, CatalogService $catalog): JsonResponse
    {
        // Diambil SEBELUM query: simpan sebagai updated_since berikutnya agar
        // perubahan yang terjadi saat query berjalan tidak terlewat.
        $serverTime = now();

        $since = $request->date('updated_since');
        $changes = $catalog->changesSince($since);

        return response()->json([
            'data' => [
                'categories' => CategoryResource::collection($changes['categories'])->resolve(),
                'products' => ProductResource::collection($changes['products'])->resolve(),
            ],
            'meta' => [
                'server_time' => $serverTime->toIso8601String(),
                'full_sync' => $since === null,
            ],
        ]);
    }
}
