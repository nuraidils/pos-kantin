<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CatalogController;
use App\Http\Controllers\Api\TransactionController;
use Illuminate\Support\Facades\Route;

Route::prefix('auth')->group(function () {
    Route::post('login', [AuthController::class, 'login'])->middleware('throttle:10,1');

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me', [AuthController::class, 'me']);
    });
});

// Katalog dan transaksi hanya untuk kasir (AGENTS.md §8). Owner memakai Filament.
Route::middleware(['auth:sanctum', 'role:cashier'])->group(function () {
    Route::get('catalog', [CatalogController::class, 'index']);
    Route::post('transactions', [TransactionController::class, 'store']);
});
