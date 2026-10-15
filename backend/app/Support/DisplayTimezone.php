<?php

namespace App\Support;

/**
 * Zona waktu tampilan dashboard. Database dan config('app.timezone') tetap UTC
 * (waktu transaksi dari perangkat disimpan UTC); hanya tampilan dan batas
 * "hari ini" yang mengikuti zona ini.
 */
final class DisplayTimezone
{
    public const NAME = 'Asia/Jakarta';
}
