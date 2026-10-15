<?php

namespace App\Services;

use App\Models\Product;
use App\Models\Transaction;
use App\Support\DisplayTimezone;
use Carbon\CarbonInterface;
use Illuminate\Support\Carbon;

class DashboardSummaryService
{
    /**
     * Ringkasan singkat untuk halaman Dashboard. Sengaja kecil: laporan
     * berkala ada di Laporan dan tren di Statistik (AGENTS.md §25), bukan di sini.
     *
     * "Hari ini" mengikuti hari kalender zona tampilan (WIB), bukan UTC; waktu
     * penjualan disimpan UTC.
     *
     * @return array{revenue: int, transactions: int, out_of_stock: int, low_stock: int}
     */
    public function today(?CarbonInterface $now = null): array
    {
        $now = ($now ? Carbon::instance($now) : Carbon::now())->setTimezone(DisplayTimezone::NAME);
        $from = $now->copy()->startOfDay()->setTimezone(config('app.timezone'));
        $to = $now->copy()->endOfDay()->setTimezone(config('app.timezone'));

        $sales = Transaction::query()->whereBetween('created_at', [$from, $to]);

        return [
            'revenue' => (int) (clone $sales)->sum('total_amount'),
            'transactions' => (clone $sales)->count(),
            // Produk nonaktif tidak dijual di kasir, jadi stoknya tidak diperingatkan.
            'out_of_stock' => Product::query()->where('is_active', true)->outOfStock()->count(),
            'low_stock' => Product::query()->where('is_active', true)->lowStock()->count(),
        ];
    }
}
