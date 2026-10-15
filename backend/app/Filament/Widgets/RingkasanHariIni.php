<?php

namespace App\Filament\Widgets;

use App\Services\DashboardSummaryService;
use App\Support\Rupiah;
use Filament\Support\Icons\Heroicon;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class RingkasanHariIni extends StatsOverviewWidget
{
    protected ?string $heading = 'Hari Ini';

    protected function getStats(): array
    {
        $summary = app(DashboardSummaryService::class)->today();
        $attention = $summary['out_of_stock'] + $summary['low_stock'];

        return [
            Stat::make('Omzet', Rupiah::format($summary['revenue']))
                ->description('Dari transaksi yang sudah tersinkron'),
            Stat::make('Jumlah Transaksi', (string) $summary['transactions']),
            Stat::make('Stok Perlu Perhatian', (string) $attention)
                ->description("{$summary['out_of_stock']} habis, {$summary['low_stock']} menipis")
                ->descriptionIcon($attention > 0 ? Heroicon::OutlinedExclamationTriangle : null)
                ->color($attention > 0 ? 'warning' : 'success'),
        ];
    }
}
