<?php

namespace App\Filament\Widgets;

use App\Services\ReportService;
use App\Support\Rupiah;
use Filament\Widgets\Concerns\InteractsWithPageFilters;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class LaporanRingkasan extends StatsOverviewWidget
{
    use InteractsWithPageFilters;

    protected static bool $isLazy = false;

    protected static ?int $sort = 1;

    protected function getHeading(): ?string
    {
        $period = app(ReportService::class)
            ->periodLabel($this->pageFilters['dari'] ?? null, $this->pageFilters['sampai'] ?? null);

        return "Ringkasan: {$period}";
    }

    protected function getStats(): array
    {
        $summary = app(ReportService::class)
            ->summary($this->pageFilters['dari'] ?? null, $this->pageFilters['sampai'] ?? null);

        return [
            Stat::make('Total Omzet', Rupiah::format($summary['revenue']))
                ->description('Dari transaksi yang sudah tersinkron'),
            Stat::make('Jumlah Transaksi', (string) $summary['transactions']),
            Stat::make('Rata-rata per Transaksi', Rupiah::format($summary['average'])),
        ];
    }
}
