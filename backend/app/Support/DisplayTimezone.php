<?php

namespace App\Support;

use Illuminate\Support\Carbon;

/**
 * Zona waktu tampilan dashboard. Database dan config('app.timezone') tetap UTC
 * (waktu transaksi dari perangkat disimpan UTC); hanya tampilan dan batas
 * "hari" yang mengikuti zona ini.
 */
final class DisplayTimezone
{
    public const NAME = 'Asia/Jakarta';

    /**
     * Awal hari (00.00 WIB) dari tanggal `Y-m-d` menurut owner, dinyatakan
     * dalam zona penyimpanan (UTC) supaya bisa dipakai langsung di query.
     */
    public static function startOfDayUtc(string $date): Carbon
    {
        return Carbon::parse($date, self::NAME)
            ->startOfDay()
            ->setTimezone(config('app.timezone'));
    }
}
