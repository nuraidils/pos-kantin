<?php

namespace App\Filament\Resources\Categories;

use App\Filament\Resources\Categories\Pages\ManageCategories;
use App\Models\Category;
use BackedEnum;
use Filament\Actions\DeleteAction;
use Filament\Actions\EditAction;
use Filament\Actions\RestoreAction;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\SoftDeletingScope;

class CategoryResource extends Resource
{
    protected static ?string $model = Category::class;

    protected static string | BackedEnum | null $navigationIcon = Heroicon::OutlinedTag;

    protected static ?int $navigationSort = 2;

    protected static ?string $recordTitleAttribute = 'name';

    public static function getModelLabel(): string
    {
        return 'Kategori';
    }

    public static function getPluralModelLabel(): string
    {
        return 'Kategori';
    }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            TextInput::make('name')
                ->label('Nama Kategori')
                ->required()
                ->maxLength(100),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('name')
                    ->label('Nama Kategori')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('products_count')
                    ->label('Jumlah Produk')
                    ->counts('products')
                    ->sortable(),
                TextColumn::make('updated_at')
                    ->label('Diperbarui')
                    ->dateTime('d M Y, H.i')
                    ->sortable(),
            ])
            ->defaultSort('name')
            ->filters([
                TrashedFilter::make()->label('Kategori terhapus'),
            ])
            ->recordActions([
                EditAction::make(),
                DeleteAction::make()
                    ->modalHeading('Hapus Kategori?')
                    ->modalDescription('Kategori tidak akan tersedia lagi. Kategori yang masih memiliki produk tidak bisa dihapus.')
                    ->modalSubmitActionLabel('Hapus Kategori')
                    ->before(function (DeleteAction $action, Category $record): void {
                        // Produk bersoft-delete tidak dihitung; hanya produk yang
                        // masih ada di katalog yang menahan penghapusan.
                        if ($record->products()->exists()) {
                            Notification::make()
                                ->danger()
                                ->title('Kategori tidak dapat dihapus')
                                ->body('Masih ada produk di kategori ini. Pindahkan atau hapus produknya lebih dulu.')
                                ->send();

                            $action->halt();
                        }
                    }),
                RestoreAction::make(),
            ])
            ->emptyStateHeading('Belum ada kategori')
            ->emptyStateDescription('Tambahkan kategori untuk mengelompokkan produk.');
    }

    public static function getRecordRouteBindingEloquentQuery(): Builder
    {
        return parent::getRecordRouteBindingEloquentQuery()
            ->withoutGlobalScopes([SoftDeletingScope::class]);
    }

    public static function getPages(): array
    {
        return [
            'index' => ManageCategories::route('/'),
        ];
    }
}
