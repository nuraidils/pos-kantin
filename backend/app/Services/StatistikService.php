<?php

namespace App\Services;

use App\Models\Product;
use App\Models\Transaction;
use App\Models\TransactionItem;
use App\Support\DisplayTimezone;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;

/**
 * Statistik = wawasan performa (AGENTS.md §25, DESIGN.md §30): tren penjualan
 * terkini, produk terlaris, hari/jam tersibuk, dan stok yang perlu perhatian.
 * Sengaja tanpa filter tanggal bebas: rentang tanggal tertentu adalah urusan
 * Laporan. Di sini jendelanya selalu "N hari terakhir" (termasuk hari ini, WIB).
 *
 * Hanya transaksi yang sudah diterima server yang dihitung.
 */
class StatistikService
{
    public const WINDOWS = [7, 30];

    private const DAY_NAMES = [1 => 'Senin', 2 => 'Selasa', 3 => 'Rabu', 4 => 'Kamis', 5 => 'Jumat', 6 => 'Sabtu', 7 => 'Minggu'];

    /** Pilihan tidak dikenal (atau kosong) jatuh ke 7 hari. */
    public function days(int | string | null $periode): int
    {
        $days = (int) $periode;

        return in_array($days, self::WINDOWS, true) ? $days : self::WINDOWS[0];
    }

    /**
     * Jendela [dari (inklusif), sampai (eksklusif)] dalam UTC. $offset 0 = N hari
     * terakhir sampai akhir hari ini WIB; 1 = N hari tepat sebelumnya (pembanding).
     *
     * @return array{0: Carbon, 1: Carbon}
     */
    public function window(int $days, int $offset = 0): array
    {
        $today = Carbon::now(DisplayTimezone::NAME)->toDateString();
        $end = DisplayTimezone::startOfDayUtc($today)->addDay()->subDays($days * $offset);

        return [$end->copy()->subDays($days), $end];
    }

    /** Teks periode, mis. "9 Okt 2026 - 15 Okt 2026". */
    public function periodLabel(int $days): string
    {
        [$from, $to] = $this->window($days);

        $format = fn (Carbon $date): string => $date->copy()
            ->setTimezone(DisplayTimezone::NAME)
            ->locale('id')
            ->translatedFormat('j M Y');

        return $format($from).' - '.$format($to->copy()->subDay());
    }

    /** @return Builder<Transaction> */
    private function transactions(Carbon $from, Carbon $to): Builder
    {
        return Transaction::query()
            ->where('created_at', '>=', $from)
            ->where('created_at', '<', $to);
    }

    /**
     * Omzet per hari WIB, tanpa hari yang terlewat (hari tanpa penjualan = 0)
     * supaya grafik tidak menyembunyikan hari sepi.
     *
     * @return list<array{date: string, label: string, revenue: int, transactions: int}>
     */
    public function trend(int $days): array
    {
        [$from, $to] = $this->window($days);

        $perDay = [];
        foreach ($this->transactions($from, $to)->get(['created_at', 'total_amount']) as $trx) {
            $key = $trx->created_at->copy()->setTimezone(DisplayTimezone::NAME)->toDateString();
            $perDay[$key]['revenue'] = ($perDay[$key]['revenue'] ?? 0) + (int) $trx->total_amount;
            $perDay[$key]['transactions'] = ($perDay[$key]['transactions'] ?? 0) + 1;
        }

        $result = [];
        $cursor = $from->copy()->setTimezone(DisplayTimezone::NAME);
        for ($i = 0; $i < $days; $i++) {
            $key = $cursor->toDateString();
            $result[] = [
                'date' => $key,
                'label' => $cursor->copy()->locale('id')->translatedFormat('j M'),
                'revenue' => $perDay[$key]['revenue'] ?? 0,
                'transactions' => $perDay[$key]['transactions'] ?? 0,
            ];
            $cursor->addDay();
        }

        return $result;
    }

    /**
     * Omzet N hari terakhir dibanding N hari sebelumnya. `change` = persen
     * perubahan (dibulatkan), null bila periode pembanding kosong.
     *
     * @return array{revenue: int, previous: int, change: int|null}
     */
    public function comparison(int $days): array
    {
        $sum = fn (int $offset): int => (int) $this->transactions(...$this->window($days, $offset))->sum('total_amount');

        $revenue = $sum(0);
        $previous = $sum(1);

        return [
            'revenue' => $revenue,
            'previous' => $previous,
            'change' => $previous > 0 ? (int) round(($revenue - $previous) * 100 / $previous) : null,
        ];
    }

    /**
     * Hari dalam pekan dan jam (WIB) dengan transaksi terbanyak; null bila tidak
     * ada transaksi. Seri: yang lebih awal (Senin dulu, jam lebih pagi).
     *
     * @return array{day: array{name: string, count: int}|null, hour: array{label: string, count: int}|null}
     */
    public function busiest(int $days): array
    {
        [$from, $to] = $this->window($days);

        $byDay = [];
        $byHour = [];
        foreach ($this->transactions($from, $to)->get(['created_at']) as $trx) {
            $local = $trx->created_at->copy()->setTimezone(DisplayTimezone::NAME);
            $byDay[$local->dayOfWeekIso] = ($byDay[$local->dayOfWeekIso] ?? 0) + 1;
            $byHour[$local->hour] = ($byHour[$local->hour] ?? 0) + 1;
        }

        if ($byDay === []) {
            return ['day' => null, 'hour' => null];
        }

        ksort($byDay);
        ksort($byHour);
        $day = array_key_first(array_filter($byDay, fn (int $c): bool => $c === max($byDay)));
        $hour = array_key_first(array_filter($byHour, fn (int $c): bool => $c === max($byHour)));

        return [
            'day' => ['name' => self::DAY_NAMES[$day], 'count' => $byDay[$day]],
            'hour' => [
                'label' => sprintf('%02d.00 - %02d.00', $hour, ($hour + 1) % 24),
                'count' => $byHour[$hour],
            ],
        ];
    }

    /**
     * Produk terlaris menurut jumlah terjual (seri: omzet, lalu nama). Nama dari
     * snapshot item transaksi, jadi produk yang sudah dihapus tetap muncul.
     *
     * @return list<array{rank: int, name: string, quantity: int, revenue: int}>
     */
    public function topProducts(int $days, int $limit = 5): array
    {
        [$from, $to] = $this->window($days);

        $rows = TransactionItem::query()
            ->join('transactions', 'transactions.id', '=', 'transaction_items.transaction_id')
            ->where('transactions.created_at', '>=', $from)
            ->where('transactions.created_at', '<', $to)
            ->selectRaw('transaction_items.product_id, MAX(transaction_items.product_name) as product_name, SUM(transaction_items.quantity) as total_quantity, SUM(transaction_items.subtotal) as total_revenue')
            ->groupBy('transaction_items.product_id')
            ->orderByDesc('total_quantity')
            ->orderByDesc('total_revenue')
            ->orderBy('product_name')
            ->limit($limit)
            ->get();

        return $rows->values()->map(fn ($row, int $i): array => [
            'rank' => $i + 1,
            'name' => (string) $row->product_name,
            'quantity' => (int) $row->total_quantity,
            'revenue' => (int) $row->total_revenue,
        ])->all();
    }

    /**
     * Produk aktif yang habis atau menipis, yang paling sedikit di atas.
     *
     * @return Builder<Product>
     */
    public function attentionProducts(): Builder
    {
        return Product::query()
            ->where('is_active', true)
            ->where('stock', '<=', Product::LOW_STOCK_THRESHOLD)
            ->with('category')
            ->orderBy('stock')
            ->orderBy('name');
    }
}
