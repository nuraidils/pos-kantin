<?php

namespace App\Support;

/**
 * Format rupiah Indonesia: Rp10.000, Rp1.250.000 (DESIGN.md §31). Satu tempat
 * agar semua tabel dashboard memakai format yang sama.
 */
final class Rupiah
{
    public static function format(int | float | string | null $amount): string
    {
        return 'Rp'.number_format((int) $amount, 0, ',', '.');
    }
}
