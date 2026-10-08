<?php

namespace App\Enums;

/**
 * Semantik status harus tetap stabil (AGENTS.md §11).
 * Server hanya menyimpan transaksi yang diterima, jadi nilainya praktis 'synced';
 * enum ini ada agar kontrak lima status tetap satu sumber di kedua sisi.
 */
enum SyncStatus: string
{
    case Pending = 'pending';
    case Syncing = 'syncing';
    case Synced = 'synced';
    case Failed = 'failed';
    case Conflict = 'conflict';
}
