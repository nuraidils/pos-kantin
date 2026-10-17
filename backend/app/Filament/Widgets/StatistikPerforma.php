<?php

namespace App\Filament\Widgets;

use App\Services\StatistikService;
use App\Support\Rupiah;
use Filament\Support\Icons\Heroicon;
use Filament\Widgets\Concerns\InteractsWithPageFilters;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class StatistikPerforma extends StatsOverviewWidget
{
    use InteractsWithPageFilters;

    protected static bool $isLazy = false;

    protected static ?int $sort = 1;

    protected ?string $pollingInterval = null;

    protected function getHeading(): ?string
    {
        $service = app(StatistikService::class);

        return 'Performa: '.$service->periodLabel($service->days($this->pageFilters['periode'] ?? null));
    }

    protected function getStats(): array
    {
        $service = app(StatistikService::class);
        $days = $service->days($this->pageFilters['periode'] ?? null);
        $comparison = $service->comparison($days);
        $busiest = $service->busiest($days);

        $omzet = Stat::make("Omzet {$days} Hari Terakhir", Rupiah::format($comparison['revenue']));

        if ($comparison['change'] === null) {
            $omzet->description("Belum ada pembanding ({$days} hari sebelumnya kosong)");
        } else {
            $change = $comparison['change'];
            $arah = $change > 0 ? '+' : '';
            $omzet->description("{$arah}{$change}% dibanding {$days} hari sebelumnya")
                ->descriptionIcon($change >= 0 ? Heroicon::ArrowTrendingUp : Heroicon::ArrowTrendingDown)
                ->descriptionColor($change > 0 ? 'success' : ($change < 0 ? 'danger' : 'gray'));
        }

        return [
            $omzet,
            Stat::make('Hari Tersibuk', $busiest['day']['name'] ?? '-')
                ->description($busiest['day'] ? "{$busiest['day']['count']} transaksi" : 'Belum ada transaksi'),
            Stat::make('Jam Tersibuk', $busiest['hour']['label'] ?? '-')
                ->description($busiest['hour'] ? "{$busiest['hour']['count']} transaksi (WIB)" : 'Belum ada transaksi'),
        ];
    }
}
