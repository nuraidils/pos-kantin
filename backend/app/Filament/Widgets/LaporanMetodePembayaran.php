<?php

namespace App\Filament\Widgets;

use App\Enums\PaymentMethod;
use App\Services\ReportService;
use App\Support\Rupiah;
use Filament\Widgets\Concerns\InteractsWithPageFilters;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class LaporanMetodePembayaran extends StatsOverviewWidget
{
    use InteractsWithPageFilters;

    protected static bool $isLazy = false;

    protected static ?int $sort = 3;

    protected ?string $heading = 'Rincian Metode Pembayaran';

    protected function getColumns(): int
    {
        return 2;
    }

    protected function getStats(): array
    {
        $summary = app(ReportService::class)
            ->summary($this->pageFilters['dari'] ?? null, $this->pageFilters['sampai'] ?? null);

        return collect(PaymentMethod::cases())
            ->map(function (PaymentMethod $method) use ($summary): Stat {
                $data = $summary['by_method'][$method->value];

                return Stat::make($method->label(), Rupiah::format($data['total']))
                    ->description("{$data['count']} transaksi · {$data['share']}% dari omzet");
            })
            ->all();
    }
}
