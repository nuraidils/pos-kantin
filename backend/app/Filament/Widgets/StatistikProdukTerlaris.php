<?php

namespace App\Filament\Widgets;

use App\Services\StatistikService;
use App\Support\Rupiah;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;
use Filament\Widgets\Concerns\InteractsWithPageFilters;
use Filament\Widgets\TableWidget;

class StatistikProdukTerlaris extends TableWidget
{
    use InteractsWithPageFilters;

    protected static bool $isLazy = false;

    protected static ?int $sort = 3;

    protected ?string $pollingInterval = null;

    public function table(Table $table): Table
    {
        return $table
            ->heading('Produk Terlaris')
            ->description('Berdasarkan jumlah terjual pada periode di atas.')
            ->records(function (): array {
                $service = app(StatistikService::class);

                return $service->topProducts($service->days($this->pageFilters['periode'] ?? null));
            })
            ->columns([
                TextColumn::make('rank')->label('#'),
                TextColumn::make('name')->label('Produk'),
                TextColumn::make('quantity')->label('Terjual')->alignEnd(),
                TextColumn::make('revenue')
                    ->label('Omzet')
                    ->formatStateUsing(fn ($state): string => Rupiah::format($state))
                    ->alignEnd(),
            ])
            ->paginated(false)
            ->emptyStateHeading('Belum ada penjualan pada periode ini')
            ->emptyStateDescription('Produk terlaris muncul setelah ada transaksi yang tersinkron.');
    }
}
