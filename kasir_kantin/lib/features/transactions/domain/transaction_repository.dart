import 'checkout_line.dart';
import 'local_transaction.dart';
import 'payment_method.dart';
import 'sync_outcome.dart';

abstract interface class TransactionRepository {
  /// Menyimpan transaksi di perangkat dengan status `pending` dan
  /// mengurangi stok lokal, SEMUANYA atau tidak sama sekali. Tidak menunggu
  /// server (AGENTS.md §12).
  ///
  /// Melempar `CheckoutException` bila keranjang tidak bisa dibayar; dalam
  /// kasus itu tidak ada data yang berubah.
  Future<LocalTransaction> createLocalTransaction({
    required List<CheckoutLine> lines,
    required PaymentMethod paymentMethod,
  });

  Future<LocalTransaction?> getTransaction(String localUuid);

  /// Transaksi yang boleh dikirim sekarang (`pending` dan `failed`), dari
  /// yang terlama.
  Future<List<LocalTransaction>> getTransactionsToSync();

  /// Transaksi yang belum diterima server: `pending`, `syncing`, `failed`.
  Future<int> countUnsyncedTransactions();

  /// Transaksi `conflict` yang menunggu perhatian kasir.
  Future<int> countConflictTransactions();

  /// Transaksi `conflict` beserta alasannya (`syncMessage`), terbaru dulu.
  Future<List<LocalTransaction>> getConflictTransactions();

  /// Mengembalikan transaksi `conflict` ke `pending` agar dikirim lagi
  /// (mis. stok server sudah ditambah). Isi transaksi tidak berubah dan stok
  /// lokal dikurangi lagi. False bila statusnya bukan `conflict` lagi.
  Future<bool> retryConflict(String localUuid);

  /// Mengirim satu transaksi dan mencatat hasilnya di SQLite. Aman dipanggil
  /// berulang atau bersamaan: hanya satu pemanggil yang benar-benar
  /// mengirim, dan server idempoten lewat `local_uuid` (Rule 5).
  ///
  /// Tidak pernah menghapus transaksi (Rule 6).
  Future<SyncOutcome> syncTransaction(String localUuid);

  /// Mengembalikan transaksi `syncing` yang tertinggal (aplikasi tertutup
  /// saat mengirim) ke `pending`. Mengembalikan jumlahnya.
  Future<int> recoverInterruptedSyncs();
}
