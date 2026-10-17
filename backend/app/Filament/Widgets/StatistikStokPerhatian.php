<?php

namespace App\Filament\Widgets;

use App\Models\Product;
use App\Services\StatistikService;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;
use Filament\Widgets\TableWidget;

class StatistikStokPerhatian extends TableWidget
{
    protected static bool $isLazy = false;

    protected static ?int $sort = 4;

    protected ?string $pollingInterval = null;

    public function table(Table $table): Table
    {
        return $table
            ->heading('Stok Perlu Perhatian')
            ->description('Produk aktif yang habis atau menipis (5 ke bawah). Ubah stok lewat menu Produk.')
            ->query(fn () => app(StatistikService::class)->attentionProducts())
            ->columns([
                TextColumn::make('name')->label('Produk'),
                TextColumn::make('category.name')->label('Kategori'),
                TextColumn::make('stock')->label('Stok')->alignEnd(),
                TextColumn::make('status')
                    ->label('Status')
                    ->state(fn (Product $record): string => $record->stock <= 0 ? 'Habis' : 'Menipis')
                    ->badge()
                    ->color(fn (string $state): string => $state === 'Habis' ? 'danger' : 'warning'),
            ])
            ->paginated([10])
            ->defaultPaginationPageOption(10)
            ->emptyStateHeading('Semua stok aman')
            ->emptyStateDescription('Tidak ada produk aktif yang habis atau menipis.');
    }
}
