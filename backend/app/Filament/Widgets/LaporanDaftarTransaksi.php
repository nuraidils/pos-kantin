<?php

namespace App\Filament\Widgets;

use App\Enums\PaymentMethod;
use App\Filament\Resources\Transactions\TransactionResource;
use App\Models\Transaction;
use App\Services\ReportService;
use App\Support\Rupiah;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;
use Filament\Widgets\Concerns\InteractsWithPageFilters;
use Filament\Widgets\TableWidget;

class LaporanDaftarTransaksi extends TableWidget
{
    use InteractsWithPageFilters;

    protected static bool $isLazy = false;

    protected static ?int $sort = 2;

    protected int | string | array $columnSpan = 'full';

    public function table(Table $table): Table
    {
        return $table
            ->heading('Daftar Transaksi')
            ->query(fn () => app(ReportService::class)
                ->query($this->pageFilters['dari'] ?? null, $this->pageFilters['sampai'] ?? null)
                ->with('user'))
            ->columns([
                TextColumn::make('invoice_number')
                    ->label('No. Invoice')
                    ->searchable(),
                TextColumn::make('created_at')
                    ->label('Waktu')
                    ->dateTime('d M Y, H.i')
                    ->sortable(),
                TextColumn::make('user.name')
                    ->label('Kasir'),
                TextColumn::make('payment_method')
                    ->label('Metode')
                    ->formatStateUsing(fn (PaymentMethod $state): string => $state->label())
                    ->badge(),
                TextColumn::make('total_amount')
                    ->label('Total')
                    ->formatStateUsing(fn ($state): string => Rupiah::format($state))
                    ->alignEnd()
                    ->sortable(),
            ])
            ->defaultSort('created_at', 'desc')
            ->recordUrl(fn (Transaction $record): string => TransactionResource::getUrl('view', ['record' => $record]))
            ->paginated([10, 25, 50])
            ->emptyStateHeading('Tidak ada transaksi pada periode ini')
            ->emptyStateDescription('Ubah rentang tanggal di atas untuk melihat periode lain.');
    }
}
