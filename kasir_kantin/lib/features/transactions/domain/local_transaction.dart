import 'package:equatable/equatable.dart';

import 'payment_method.dart';
import 'sync_status.dart';

/// Transaksi yang tersimpan di perangkat. [localUuid] adalah kunci
/// idempotensi untuk server; [invoiceNumber] hanya rujukan yang dibaca
/// manusia (AGENTS.md §21).
class LocalTransaction extends Equatable {
  const LocalTransaction({
    required this.localUuid,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.paymentMethod,
    required this.syncStatus,
    required this.createdAt,
    required this.items,
    this.syncMessage,
    this.serverId,
    this.syncedAt,
  });

  final String localUuid;
  final String invoiceNumber;
  final int totalAmount;
  final PaymentMethod paymentMethod;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final List<LocalTransactionItem> items;

  /// Alasan untuk status `failed` atau `conflict`, dalam bahasa kasir
  /// (DESIGN.md §20). Kosong untuk status lain.
  final String? syncMessage;

  /// `transactions.id` di server; terisi setelah `synced`.
  final int? serverId;

  final DateTime? syncedAt;

  @override
  List<Object?> get props => [
    localUuid,
    invoiceNumber,
    totalAmount,
    paymentMethod,
    syncStatus,
    createdAt,
    items,
    syncMessage,
    serverId,
    syncedAt,
  ];
}

/// Snapshot nama dan harga saat penjualan (AGENTS.md §9): tidak berubah
/// walau produk diubah atau dihapus kemudian.
class LocalTransactionItem extends Equatable {
  const LocalTransactionItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
  });

  final int productId;
  final String productName;
  final int quantity;
  final int price;

  int get subtotal => price * quantity;

  @override
  List<Object?> get props => [productId, productName, quantity, price];
}
