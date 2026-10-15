<?php

namespace App\Filament\Pages;

use App\Filament\Widgets\LaporanDaftarTransaksi;
use App\Filament\Widgets\LaporanMetodePembayaran;
use App\Filament\Widgets\LaporanRingkasan;
use App\Support\DisplayTimezone;
use BackedEnum;
use Filament\Forms\Components\DatePicker;
use Filament\Pages\Dashboard;
use Filament\Pages\Dashboard\Concerns\HasFiltersForm;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Illuminate\Support\Carbon;

/**
 * Laporan historis (AGENTS.md §25, DESIGN.md §29): filter tanggal -> ringkasan ->
 * daftar transaksi -> rincian metode pembayaran. Dibangun di atas Dashboard
 * Filament agar widget otomatis menerima filter halaman.
 */
class Laporan extends Dashboard
{
    use HasFiltersForm;

    protected static string $routePath = 'laporan';

    protected static ?string $title = 'Laporan';

    protected static ?string $navigationLabel = 'Laporan';

    protected static string | BackedEnum | null $navigationIcon = Heroicon::OutlinedDocumentChartBar;

    protected static ?int $navigationSort = 4;

    /** Filter selalu mulai dari bawaan (bulan ini), bukan sisa sesi sebelumnya. */
    public function persistsFiltersInSession(): bool
    {
        return false;
    }

    public function getColumns(): int | array
    {
        return 1;
    }

    public function getWidgets(): array
    {
        return [
            LaporanRingkasan::class,
            LaporanDaftarTransaksi::class,
            LaporanMetodePembayaran::class,
        ];
    }

    public function filtersForm(Schema $schema): Schema
    {
        $hariIni = Carbon::now(DisplayTimezone::NAME);

        return $schema->components([
            Section::make('Filter Tanggal')
                ->description('Tanggal awal dan akhir ikut dihitung. Waktu mengikuti WIB.')
                ->columns(2)
                ->components([
                    DatePicker::make('dari')
                        ->label('Dari tanggal')
                        ->default($hariIni->copy()->startOfMonth()->toDateString())
                        ->maxDate($hariIni->toDateString())
                        ->native(false)
                        ->displayFormat('d/m/Y'),
                    DatePicker::make('sampai')
                        ->label('Sampai tanggal')
                        ->default($hariIni->toDateString())
                        ->maxDate($hariIni->toDateString())
                        ->native(false)
                        ->displayFormat('d/m/Y'),
                ]),
        ]);
    }
}
