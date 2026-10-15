<?php

namespace App\Services;

use App\Enums\PaymentMethod;
use App\Models\Transaction;
use App\Support\DisplayTimezone;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;

/**
 * Laporan = data historis pada rentang tanggal yang dipilih (AGENTS.md §25):
 * omzet, jumlah transaksi, rata-rata, dan rincian per metode pembayaran.
 * Tren dan produk terlaris adalah urusan Statistik (tahap 18), bukan di sini.
 *
 * Hanya transaksi yang sudah diterima server yang dihitung (transaksi `conflict`
 * dan yang belum tersinkron masih ada di perangkat kasir saja).
 */
class ReportService
{
    /**
     * Rentang dalam UTC: [dari (inklusif), sampai (eksklusif)]. Tanggal masukan
     * adalah tanggal kalender WIB (`Y-m-d`), kedua ujungnya ikut dihitung penuh.
     * Kosong atau tidak valid -> awal bulan ini sampai hari ini. Bila terbalik,
     * ditukar, supaya laporan tidak pernah kosong hanya karena urutan input.
     *
     * @return array{0: Carbon, 1: Carbon}
     */
    public function period(?string $dari, ?string $sampai): array
    {
        $now = Carbon::now(DisplayTimezone::NAME);

        $dari = $this->normalizeDate($dari) ?? $now->copy()->startOfMonth()->toDateString();
        $sampai = $this->normalizeDate($sampai) ?? $now->toDateString();

        if ($dari > $sampai) {
            [$dari, $sampai] = [$sampai, $dari];
        }

        return [
            DisplayTimezone::startOfDayUtc($dari),
            DisplayTimezone::startOfDayUtc($sampai)->addDay(),
        ];
    }

    /** Teks periode untuk judul, mis. "1 Okt 2026 - 15 Okt 2026". */
    public function periodLabel(?string $dari, ?string $sampai): string
    {
        [$from, $to] = $this->period($dari, $sampai);

        $format = fn (Carbon $date): string => $date
            ->copy()
            ->setTimezone(DisplayTimezone::NAME)
            ->locale('id')
            ->translatedFormat('j M Y');

        return $format($from).' - '.$format($to->copy()->subDay());
    }

    /** @return Builder<Transaction> */
    public function query(?string $dari, ?string $sampai): Builder
    {
        [$from, $to] = $this->period($dari, $sampai);

        return Transaction::query()
            ->where('created_at', '>=', $from)
            ->where('created_at', '<', $to);
    }

    /**
     * @return array{
     *     revenue: int,
     *     transactions: int,
     *     average: int,
     *     by_method: array<string, array{count: int, total: int, share: int}>
     * }
     */
    public function summary(?string $dari, ?string $sampai): array
    {
        $rows = $this->query($dari, $sampai)
            ->selectRaw('payment_method, COUNT(*) as aggregate_count, SUM(total_amount) as aggregate_total')
            ->groupBy('payment_method')
            ->get();

        $byMethod = [];
        foreach (PaymentMethod::cases() as $method) {
            $row = $rows->first(fn ($r) => $this->methodValue($r->payment_method) === $method->value);

            $byMethod[$method->value] = [
                'count' => (int) ($row->aggregate_count ?? 0),
                'total' => (int) ($row->aggregate_total ?? 0),
                'share' => 0,
            ];
        }

        $revenue = array_sum(array_column($byMethod, 'total'));
        $count = array_sum(array_column($byMethod, 'count'));

        foreach ($byMethod as $value => $data) {
            $byMethod[$value]['share'] = $revenue > 0 ? (int) round($data['total'] * 100 / $revenue) : 0;
        }

        return [
            'revenue' => $revenue,
            'transactions' => $count,
            'average' => $count > 0 ? (int) round($revenue / $count) : 0,
            'by_method' => $byMethod,
        ];
    }

    private function methodValue(mixed $value): string
    {
        return $value instanceof PaymentMethod ? $value->value : (string) $value;
    }

    private function normalizeDate(?string $date): ?string
    {
        if ($date === null || ! preg_match('/^\d{4}-\d{2}-\d{2}/', $date)) {
            return null;
        }

        $date = substr($date, 0, 10);

        try {
            return Carbon::createFromFormat('Y-m-d', $date)->format('Y-m-d') === $date ? $date : null;
        } catch (\Throwable) {
            return null;
        }
    }
}
