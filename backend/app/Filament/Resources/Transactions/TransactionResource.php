<?php

namespace App\Filament\Resources\Transactions;

use App\Enums\PaymentMethod;
use App\Filament\Resources\Transactions\Pages\ListTransactions;
use App\Filament\Resources\Transactions\Pages\ViewTransaction;
use App\Models\Transaction;
use App\Support\DisplayTimezone;
use App\Support\Rupiah;
use BackedEnum;
use Carbon\Carbon;
use Filament\Actions\ViewAction;
use Filament\Forms\Components\DatePicker;
use Filament\Infolists\Components\RepeatableEntry;
use Filament\Infolists\Components\TextEntry;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * Transaksi di dashboard HANYA DIBACA. Transaksi lahir di perangkat kasir dan
 * masuk lewat API (idempoten, atomik dengan stok); mengubah atau menghapusnya
 * dari sini akan merusak jejak penjualan dan stok (AGENTS.md §9, §13).
 */
class TransactionResource extends Resource
{
    protected static ?string $model = Transaction::class;

    protected static string | BackedEnum | null $navigationIcon = Heroicon::OutlinedBanknotes;

    protected static ?int $navigationSort = 3;

    protected static ?string $recordTitleAttribute = 'invoice_number';

    public static function getModelLabel(): string
    {
        return 'Transaksi';
    }

    public static function getPluralModelLabel(): string
    {
        return 'Transaksi';
    }

    public static function canCreate(): bool
    {
        return false;
    }

    public static function canEdit(Model $record): bool
    {
        return false;
    }

    public static function canDelete(Model $record): bool
    {
        return false;
    }

    public static function canDeleteAny(): bool
    {
        return false;
    }

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()->with('user');
    }

    public static function infolist(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Rincian Transaksi')
                ->columns(2)
                ->components([
                    TextEntry::make('invoice_number')->label('No. Invoice')->copyable(),
                    TextEntry::make('created_at')->label('Waktu Penjualan')->dateTime('d M Y, H.i'),
                    TextEntry::make('user.name')->label('Kasir'),
                    TextEntry::make('payment_method')
                        ->label('Metode Pembayaran')
                        ->formatStateUsing(fn (PaymentMethod $state): string => $state->label())
                        ->badge(),
                    TextEntry::make('synced_at')
                        ->label('Diterima Server')
                        ->dateTime('d M Y, H.i')
                        ->placeholder('-'),
                    TextEntry::make('total_amount')
                        ->label('Total')
                        ->formatStateUsing(fn ($state): string => Rupiah::format($state))
                        ->weight('bold'),
                ]),
            Section::make('Produk')
                ->components([
                    // Nama dan harga dibaca dari snapshot item, bukan dari tabel
                    // produk, sehingga perubahan harga kemudian tidak mengubah
                    // transaksi lama (AGENTS.md §9).
                    RepeatableEntry::make('items')
                        ->hiddenLabel()
                        ->columns(4)
                        ->schema([
                            TextEntry::make('product_name')->label('Produk'),
                            TextEntry::make('quantity')->label('Jumlah'),
                            TextEntry::make('price')
                                ->label('Harga')
                                ->formatStateUsing(fn ($state): string => Rupiah::format($state)),
                            TextEntry::make('subtotal')
                                ->label('Subtotal')
                                ->formatStateUsing(fn ($state): string => Rupiah::format($state)),
                        ]),
                ]),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('invoice_number')
                    ->label('No. Invoice')
                    ->searchable()
                    ->copyable(),
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
            ->filters([
                SelectFilter::make('payment_method')
                    ->label('Metode Pembayaran')
                    ->options(collect(PaymentMethod::cases())
                        ->mapWithKeys(fn (PaymentMethod $m): array => [$m->value => $m->label()])
                        ->all()),
                Filter::make('tanggal')
                    ->label('Tanggal')
                    ->schema([
                        DatePicker::make('dari')->label('Dari tanggal'),
                        DatePicker::make('sampai')->label('Sampai tanggal'),
                    ])
                    ->query(fn (Builder $query, array $data): Builder => $query
                        ->when($data['dari'] ?? null, fn (Builder $q, string $date): Builder => $q->where('created_at', '>=', static::dayStartUtc($date)))
                        ->when($data['sampai'] ?? null, fn (Builder $q, string $date): Builder => $q->where('created_at', '<', static::dayStartUtc($date)->addDay())))
                    ->indicateUsing(function (array $data): array {
                        $indicators = [];
                        if ($data['dari'] ?? null) {
                            $indicators[] = 'Dari '.Carbon::parse($data['dari'])->format('d M Y');
                        }
                        if ($data['sampai'] ?? null) {
                            $indicators[] = 'Sampai '.Carbon::parse($data['sampai'])->format('d M Y');
                        }

                        return $indicators;
                    }),
            ])
            ->recordActions([
                ViewAction::make()->label('Lihat'),
            ])
            ->emptyStateHeading('Belum ada transaksi')
            ->emptyStateDescription('Transaksi dari aplikasi kasir akan tampil di sini setelah tersinkron.');
    }

    /**
     * Awal hari (zona tampilan) sebagai waktu UTC, karena kolom `created_at`
     * disimpan UTC. Tanggal dari filter adalah tanggal menurut owner (WIB).
     */
    protected static function dayStartUtc(string $date): Carbon
    {
        return Carbon::parse($date, DisplayTimezone::NAME)
            ->startOfDay()
            ->setTimezone(config('app.timezone'));
    }

    public static function getPages(): array
    {
        return [
            'index' => ListTransactions::route('/'),
            'view' => ViewTransaction::route('/{record}'),
        ];
    }
}
