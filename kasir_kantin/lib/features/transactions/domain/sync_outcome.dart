/// Hasil mengirim SATU transaksi ke server (AGENTS.md §12, §17).
enum SyncOutcome {
  /// Diterima server (baru, atau kiriman ulang yang dikenali): `synced`.
  synced,

  /// Gagal karena sebab yang bisa dicoba ulang (jaringan, 5xx): `failed`.
  failed,

  /// Server menolak karena tidak bisa diterapkan dengan aman: `conflict`.
  conflict,

  /// Token ditolak (401/403). Transaksinya sendiri tidak bersalah, jadi
  /// kembali `pending`; pengirim harus berhenti dan menunggu masuk ulang.
  sessionExpired,

  /// Tidak dikirim: transaksi tidak ada, atau statusnya bukan `pending`/`failed`
  /// (mis. sedang dikirim oleh pemanggil lain atau sudah `synced`).
  skipped,
}
