<?php

namespace App\Filament\Resources\Products;

use App\Filament\Resources\Products\Pages\CreateProduct;
use App\Filament\Resources\Products\Pages\EditProduct;
use App\Filament\Resources\Products\Pages\ListProducts;
use App\Models\Product;
use App\Services\ProductService;
use App\Support\Rupiah;
use BackedEnum;
use Filament\Actions\Action;
use Filament\Actions\DeleteAction;
use Filament\Actions\EditAction;
use Filament\Actions\RestoreAction;
use Filament\Forms\Components\FileUpload;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Notifications\Notification;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\ImageColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;
use InvalidArgumentException;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\SoftDeletingScope;

class ProductResource extends Resource
{
    protected static ?string $model = Product::class;

    protected static string | BackedEnum | null $navigationIcon = Heroicon::OutlinedShoppingBag;

    protected static ?int $navigationSort = 1;

    protected static ?string $recordTitleAttribute = 'name';

    public static function getModelLabel(): string
    {
        return 'Produk';
    }

    public static function getPluralModelLabel(): string
    {
        return 'Produk';
    }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Select::make('category_id')
                ->label('Kategori')
                ->relationship('category', 'name')
                ->searchable()
                ->preload()
                ->required(),
            TextInput::make('name')
                ->label('Nama Produk')
                ->required()
                ->maxLength(255),
            TextInput::make('price')
                ->label('Harga')
                ->prefix('Rp')
                ->numeric()
                ->integer()
                ->minValue(0)
                ->maxValue(100_000_000)
                ->required(),
            // Stok hanya diisi saat produk dibuat. Sesudahnya stok berubah oleh
            // transaksi kasir, jadi mengubahnya lewat aksi "Ubah Stok" (selisih),
            // bukan dengan menimpa angka dari formulir.
            TextInput::make('stock')
                ->label('Stok Awal')
                ->numeric()
                ->integer()
                ->minValue(0)
                ->maxValue(1_000_000)
                ->default(0)
                ->required()
                ->visibleOn('create'),
            FileUpload::make('image')
                ->label('Foto Produk')
                ->image()
                ->disk('public')
                ->directory('products')
                ->visibility('public')
                ->maxSize(2048),
            Toggle::make('is_active')
                ->label('Aktif (tampil di kasir)')
                ->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                ImageColumn::make('image')
                    ->label('Foto')
                    ->disk('public')
                    ->square(),
                TextColumn::make('name')
                    ->label('Nama Produk')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('category.name')
                    ->label('Kategori')
                    ->sortable(),
                TextColumn::make('price')
                    ->label('Harga')
                    ->formatStateUsing(fn ($state): string => Rupiah::format($state))
                    ->alignEnd()
                    ->sortable(),
                // Teks + warna, bukan warna saja (DESIGN.md §5, §37).
                TextColumn::make('stock')
                    ->label('Stok')
                    ->badge()
                    ->formatStateUsing(fn (int $state): string => match (true) {
                        $state <= 0 => 'Habis',
                        $state <= Product::LOW_STOCK_THRESHOLD => "Menipis ({$state})",
                        default => (string) $state,
                    })
                    ->color(fn (int $state): string => match (true) {
                        $state <= 0 => 'danger',
                        $state <= Product::LOW_STOCK_THRESHOLD => 'warning',
                        default => 'success',
                    })
                    ->sortable(),
                IconColumn::make('is_active')
                    ->label('Aktif')
                    ->boolean(),
            ])
            ->defaultSort('name')
            ->filters([
                SelectFilter::make('category_id')
                    ->label('Kategori')
                    ->relationship('category', 'name'),
                TernaryFilter::make('is_active')
                    ->label('Status')
                    ->placeholder('Semua')
                    ->trueLabel('Aktif')
                    ->falseLabel('Nonaktif'),
                Filter::make('stok_perlu_perhatian')
                    ->label('Stok menipis atau habis')
                    ->toggle()
                    ->query(fn (Builder $query): Builder => $query->where('stock', '<=', Product::LOW_STOCK_THRESHOLD)),
                TrashedFilter::make()->label('Produk terhapus'),
            ])
            ->recordActions([
                EditAction::make(),
                Action::make('ubahStok')
                    ->label('Ubah Stok')
                    ->icon(Heroicon::OutlinedArrowsUpDown)
                    ->hidden(fn (Product $record): bool => $record->trashed())
                    ->modalHeading(fn (Product $record): string => "Ubah Stok: {$record->name}")
                    ->modalDescription(fn (Product $record): string => "Stok saat ini {$record->stock}. Isi angka positif untuk menambah, negatif untuk mengurangi.")
                    ->modalSubmitActionLabel('Simpan')
                    ->schema([
                        TextInput::make('delta')
                            ->label('Perubahan Stok')
                            ->numeric()
                            ->integer()
                            ->minValue(-1_000_000)
                            ->maxValue(1_000_000)
                            ->required()
                            ->notIn([0]),
                    ])
                    ->action(function (Product $record, array $data): void {
                        try {
                            $updated = app(ProductService::class)->adjustStock($record, (int) $data['delta']);
                        } catch (InvalidArgumentException $e) {
                            Notification::make()
                                ->danger()
                                ->title('Stok tidak diubah')
                                ->body($e->getMessage())
                                ->send();

                            return;
                        }

                        Notification::make()
                            ->success()
                            ->title('Stok diperbarui')
                            ->body("Stok {$updated->name} sekarang {$updated->stock}.")
                            ->send();
                    }),
                DeleteAction::make()
                    ->modalHeading('Hapus Produk?')
                    ->modalDescription('Produk tidak akan tersedia di katalog. Riwayat transaksi lama tetap aman.')
                    ->modalSubmitActionLabel('Hapus Produk'),
                RestoreAction::make()
                    ->before(function (RestoreAction $action, Product $record): void {
                        // Relasi tidak memuat kategori yang sudah dihapus.
                        if ($record->category === null) {
                            Notification::make()
                                ->danger()
                                ->title('Produk tidak dapat dipulihkan')
                                ->body('Kategori produk ini sudah dihapus. Pulihkan kategorinya lebih dulu.')
                                ->send();

                            $action->halt();
                        }
                    }),
            ])
            ->emptyStateHeading('Belum ada produk')
            ->emptyStateDescription('Tambahkan produk agar muncul di aplikasi kasir.');
    }

    public static function getRecordRouteBindingEloquentQuery(): Builder
    {
        return parent::getRecordRouteBindingEloquentQuery()
            ->withoutGlobalScopes([SoftDeletingScope::class]);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListProducts::route('/'),
            'create' => CreateProduct::route('/create'),
            'edit' => EditProduct::route('/{record}/edit'),
        ];
    }
}
