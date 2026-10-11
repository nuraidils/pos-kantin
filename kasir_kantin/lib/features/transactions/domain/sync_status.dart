/// Status sinkronisasi transaksi (AGENTS.md §11). Nama enum sama dengan
/// isi kolom `sync_status`, jadi artinya tidak boleh diubah.
enum SyncStatus {
  /// Tersimpan lokal, menunggu dikirim.
  pending,

  /// Sedang dikirim.
  syncing,

  /// Diterima server.
  synced,

  /// Gagal karena sebab yang bisa dicoba ulang.
  failed,

  /// Ditolak server karena tidak bisa diterapkan (mis. stok kurang).
  conflict;

  static SyncStatus fromValue(String value) => values.byName(value);
}
