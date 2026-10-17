<?php

namespace App\Filament\Pages;

use App\Filament\Widgets\StatistikPerforma;
use App\Filament\Widgets\StatistikProdukTerlaris;
use App\Filament\Widgets\StatistikStokPerhatian;
use App\Filament\Widgets\StatistikTren;
use BackedEnum;
use Filament\Forms\Components\Select;
use Filament\Pages\Dashboard;
use Filament\Pages\Dashboard\Concerns\HasFiltersForm;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;

/**
 * Statistik (AGENTS.md §25, DESIGN.md §30): wawasan performa terkini. Berbeda
 * dari Laporan, jendelanya selalu "N hari terakhir", bukan rentang tanggal bebas.
 */
class Statistik extends Dashboard
{
    use HasFiltersForm;

    protected static string $routePath = 'statistik';

    protected static ?string $title = 'Statistik';

    protected static ?string $navigationLabel = 'Statistik';

    protected static string | BackedEnum | null $navigationIcon = Heroicon::OutlinedChartBar;

    protected static ?int $navigationSort = 5;

    /** Pilihan periode selalu mulai dari 7 hari, bukan sisa sesi sebelumnya. */
    public function persistsFiltersInSession(): bool
    {
        return false;
    }

    public function getColumns(): int | array
    {
        return 2;
    }

    public function getWidgets(): array
    {
        return [
            StatistikPerforma::class,
            StatistikTren::class,
            StatistikProdukTerlaris::class,
            StatistikStokPerhatian::class,
        ];
    }

    public function filtersForm(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Periode')
                ->description('Dihitung mundur dari hari ini (WIB). Untuk rentang tanggal bebas, pakai Laporan.')
                ->components([
                    Select::make('periode')
                        ->label('Tampilkan')
                        ->options(['7' => '7 hari terakhir', '30' => '30 hari terakhir'])
                        ->default('7')
                        ->selectablePlaceholder(false)
                        ->native(false),
                ]),
        ]);
    }
}
