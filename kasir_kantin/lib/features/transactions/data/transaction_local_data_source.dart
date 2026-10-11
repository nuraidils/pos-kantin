import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/checkout_exception.dart';
import '../domain/checkout_line.dart';
import '../domain/local_transaction.dart';
import '../domain/payment_method.dart';
import '../domain/sync_status.dart';

/// Akses SQLite untuk transaksi lokal. Satu-satunya tempat SQL pembuatan
/// transaksi berada.
class TransactionLocalDataSource {
  /// [newUuid] dan [clock] hanya diganti pada pengujian.
  TransactionLocalDataSource(
    this._database, {
    String Function()? newUuid,
    DateTime Function()? clock,
  }) : _newUuid = newUuid ?? Uuid().v4,
       _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final String Function() _newUuid;
  final DateTime Function() _clock;

  Database get _db => _database.db;

  /// Nomor invoice berasal dari UUID acak, jadi tabrakan sangat jarang;
  /// bila terjadi (UNIQUE gagal) dicoba lagi dengan UUID baru.
  static const _maxAttempts = 3;

  Future<LocalTransaction> create({
    required List<CheckoutLine> lines,
    required PaymentMethod paymentMethod,
  }) async {
    if (lines.isEmpty) throw const CheckoutEmptyException();
    final merged = _merge(lines);

    for (var attempt = 1; ; attempt++) {
      try {
        return await _insert(merged, paymentMethod);
      } on DatabaseException catch (e) {
        if (!e.isUniqueConstraintError() || attempt >= _maxAttempts) rethrow;
      }
    }
  }

  /// Satu baris per produk, jumlahnya dijumlahkan. Keranjang sudah menjamin
  /// ini, tetapi hasil akhir tidak boleh bergantung pada pemanggilnya.
  List<CheckoutLine> _merge(List<CheckoutLine> lines) {
    final byProduct = <int, CheckoutLine>{};
    for (final line in lines) {
      if (line.quantity <= 0) throw const CheckoutInvalidQuantityException();
      final existing = byProduct[line.productId];
      byProduct[line.productId] = existing == null
          ? line
          : CheckoutLine(
              productId: line.productId,
              name: existing.name,
              quantity: existing.quantity + line.quantity,
              expectedPrice: existing.expectedPrice,
            );
    }
    return byProduct.values.toList();
  }

  /// Seluruh pembuatan transaksi berjalan dalam SATU transaksi SQLite:
  /// stok dibaca ulang, divalidasi, lalu transaksi, item, dan pengurangan
  /// stok ditulis bersama. Galat di mana pun membatalkan semuanya.
  Future<LocalTransaction> _insert(
    List<CheckoutLine> lines,
    PaymentMethod paymentMethod,
  ) {
    final now = _clock();
    final localUuid = _newUuid();
    final invoiceNumber = _invoiceNumber(now, localUuid);

    return _db.transaction((txn) async {
      final items = <LocalTransactionItem>[];

      for (final line in lines) {
        final rows = await txn.query(
          'products',
          columns: ['name', 'price', 'stock', 'is_active'],
          where: 'id = ?',
          whereArgs: [line.productId],
          limit: 1,
        );
        if (rows.isEmpty || rows.first['is_active'] != 1) {
          throw CheckoutProductUnavailableException(line.name);
        }

        final row = rows.first;
        final name = row['name'] as String;
        final price = row['price'] as int;
        final stock = row['stock'] as int;

        if (price != line.expectedPrice) {
          throw CheckoutPriceChangedException(name);
        }
        if (stock < line.quantity) {
          throw CheckoutInsufficientStockException(
            name,
            available: stock < 0 ? 0 : stock,
          );
        }

        items.add(
          LocalTransactionItem(
            productId: line.productId,
            productName: name,
            quantity: line.quantity,
            price: price,
          ),
        );
      }

      final total = items.fold<int>(0, (sum, item) => sum + item.subtotal);

      await txn.insert('transactions', {
        'local_uuid': localUuid,
        'invoice_number': invoiceNumber,
        'total_amount': total,
        'payment_method': paymentMethod.value,
        'sync_status': SyncStatus.pending.name,
        'created_at': now.toUtc().toIso8601String(),
      });

      final batch = txn.batch();
      for (final item in items) {
        batch.insert('transaction_items', {
          'transaction_uuid': localUuid,
          'product_id': item.productId,
          'product_name': item.productName,
          'quantity': item.quantity,
          'price': item.price,
          'subtotal': item.subtotal,
        });
        batch.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [
          item.quantity,
          item.productId,
        ]);
      }
      await batch.commit(noResult: true);

      return LocalTransaction(
        localUuid: localUuid,
        invoiceNumber: invoiceNumber,
        totalAmount: total,
        paymentMethod: paymentMethod,
        syncStatus: SyncStatus.pending,
        createdAt: now,
        items: items,
      );
    });
  }

  /// `INV-20261011-A1B2C3`: tanggal lokal + 6 karakter pertama UUID.
  String _invoiceNumber(DateTime now, String localUuid) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${now.year}${two(now.month)}${two(now.day)}';
    final suffix = localUuid.replaceAll('-', '').substring(0, 6).toUpperCase();
    return 'INV-$date-$suffix';
  }
}
