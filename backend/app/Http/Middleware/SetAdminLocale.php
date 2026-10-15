<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Dashboard owner berbahasa Indonesia (AGENTS.md Rule 12). Hanya berlaku di
 * panel Filament, jadi pesan API tidak ikut berubah. Didaftarkan sebagai
 * middleware persisten agar request Livewire juga memakainya.
 */
class SetAdminLocale
{
    public function handle(Request $request, Closure $next): Response
    {
        app()->setLocale('id');

        return $next($request);
    }
}
