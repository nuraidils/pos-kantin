<?php

namespace App\Filament\Widgets;

use App\Services\StatistikService;
use Filament\Support\RawJs;
use Filament\Widgets\ChartWidget;
use Filament\Widgets\Concerns\InteractsWithPageFilters;

class StatistikTren extends ChartWidget
{
    use InteractsWithPageFilters;

    protected static bool $isLazy = false;

    protected static ?int $sort = 2;

    protected int | string | array $columnSpan = 'full';

    protected ?string $heading = 'Tren Omzet Harian';

    protected ?string $maxHeight = '280px';

    protected ?string $pollingInterval = null;

    public function getDescription(): ?string
    {
        $days = app(StatistikService::class)->days($this->pageFilters['periode'] ?? null);

        return "Omzet per hari selama {$days} hari terakhir (hari tanpa penjualan tampil Rp0).";
    }

    protected function getType(): string
    {
        return 'line';
    }

    protected function getData(): array
    {
        $service = app(StatistikService::class);
        $trend = $service->trend($service->days($this->pageFilters['periode'] ?? null));

        return [
            'datasets' => [
                [
                    'label' => 'Omzet',
                    'data' => array_column($trend, 'revenue'),
                    'tension' => 0.25,
                    'fill' => false,
                    // Teal sekunder merek (DESIGN.md §4).
                    'borderColor' => '#287B72',
                    'backgroundColor' => '#287B72',
                    'pointBackgroundColor' => '#287B72',
                ],
            ],
            'labels' => array_column($trend, 'label'),
        ];
    }

    protected function getOptions(): RawJs
    {
        return RawJs::make(<<<'JS'
        {
            plugins: {
                legend: { display: false },
                tooltip: {
                    callbacks: {
                        label: (ctx) => 'Rp' + Number(ctx.parsed.y).toLocaleString('id-ID'),
                    },
                },
            },
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: { callback: (value) => 'Rp' + Number(value).toLocaleString('id-ID') },
                },
            },
        }
        JS);
    }
}
