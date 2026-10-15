<?php

namespace App\Providers;

use App\Support\DisplayTimezone;
use Filament\Support\Facades\FilamentTimezone;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Waktu di dashboard tampil dalam WIB; penyimpanan tetap UTC.
        FilamentTimezone::set(DisplayTimezone::NAME);
    }
}
