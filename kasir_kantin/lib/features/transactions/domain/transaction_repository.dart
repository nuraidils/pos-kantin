import 'checkout_line.dart';
import 'local_transaction.dart';
import 'payment_method.dart';

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
}
