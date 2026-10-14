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

  // ---------------------------------------------------------------------
  // Pembacaan dan perpindahan status sinkronisasi (Tahap 12).
  //
  // Setiap perpindahan status dijaga di SQL (`WHERE sync_status IN (...)`)
  // sehingga dua pemanggil yang berbarengan tidak bisa sama-sama "mengambil"
  // transaksi yang sama. Tidak ada fungsi di sini yang menghapus transaksi
  // (AGENTS.md Rule 6). Stok lokal mengikuti aturan proyeksi di
  // CatalogLocalDataSource: `pending`, `syncing`, `failed` dikurangkan;
  // `synced` dan `conflict` tidak.
  // ---------------------------------------------------------------------

  Future<LocalTransaction?> getByUuid(String localUuid) async {
    final rows = await _db.query(
      'transactions',
      where: 'local_uuid = ?',
      whereArgs: [localUuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (await _withItems(_db, rows)).single;
  }

  /// Semua transaksi, apa pun statusnya, terbaru dulu. Hanya membaca: tidak ada
  /// yang diubah atau dihapus (Rule 6).
  Future<List<LocalTransaction>> getAll() async {
    final rows = await _db.query(
      'transactions',
      orderBy: 'created_at DESC, rowid DESC',
    );
    return _withItems(_db, rows);
  }

  /// `pending` dan `failed`, dari yang terlama (urutan penjualan).
  Future<List<LocalTransaction>> getSyncable() async {
    final rows = await _db.query(
      'transactions',
      where: "sync_status IN ('pending', 'failed')",
      orderBy: 'created_at, rowid',
    );
    return _withItems(_db, rows);
  }

  /// Semua `conflict`, terbaru dulu. Tidak pernah ada yang dihapus: daftar ini
  /// adalah satu-satunya cara kasir melihat transaksi yang ditolak server.
  Future<List<LocalTransaction>> getConflicts() async {
    final rows = await _db.query(
      'transactions',
      where: "sync_status = 'conflict'",
      orderBy: 'created_at DESC, rowid DESC',
    );
    return _withItems(_db, rows);
  }

  /// "Belum tersinkron" bagi kasir: belum diterima server dan masih akan dicoba.
  Future<int> countUnsynced() => _count("('pending', 'syncing', 'failed')");

  Future<int> countConflicts() => _count("('conflict')");

  Future<int> _count(String statuses) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM transactions WHERE sync_status IN $statuses',
    );
    return (rows.first['n'] as num).toInt();
  }

  /// `pending`/`failed` -> `syncing`. False bila sudah diambil pemanggil lain
  /// atau statusnya memang tidak boleh dikirim.
  Future<bool> markSyncing(String localUuid) {
    return _transition(
      localUuid,
      from: const [SyncStatus.pending, SyncStatus.failed],
      to: SyncStatus.syncing,
    );
  }

  /// `syncing` -> `synced`. Nomor invoice dari server (bisa berakhiran -2 bila
  /// bertabrakan) menggantikan nomor lokal agar kasir dan owner melihat
  /// nomor yang sama.
  Future<bool> markSynced(
    String localUuid, {
    required int serverId,
    required String invoiceNumber,
    DateTime? syncedAt,
  }) async {
    final changed = await _transition(
      localUuid,
      from: const [SyncStatus.syncing],
      to: SyncStatus.synced,
      extra: {
        'server_id': serverId,
        'synced_at': (syncedAt ?? _clock()).toUtc().toIso8601String(),
      },
    );
    if (changed) {
      // Terpisah dari perpindahan status: tabrakan invoice_number lokal
      // (sangat jarang) tidak boleh membatalkan status `synced`.
      try {
        await _db.update(
          'transactions',
          {'invoice_number': invoiceNumber},
          where: 'local_uuid = ? AND invoice_number <> ?',
          whereArgs: [localUuid, invoiceNumber],
        );
      } on DatabaseException catch (e) {
        if (!e.isUniqueConstraintError()) rethrow;
      }
    }
    return changed;
  }

  /// `syncing` -> `failed` (bisa dicoba ulang).
  Future<bool> markFailed(String localUuid, String message) {
    return _transition(
      localUuid,
      from: const [SyncStatus.syncing],
      to: SyncStatus.failed,
      extra: {'sync_message': message},
    );
  }

  /// `syncing` -> `conflict`. Transaksi TETAP tersimpan. Karena `conflict`
  /// tidak dikurangkan dari stok, stok lokal dikembalikan di transaksi SQLite
  /// yang sama; stok server tidak berubah, jadi pull katalog tidak akan
  /// mengoreksinya sendiri.
  Future<bool> markConflict(String localUuid, String message) {
    return _db.transaction((txn) async {
      final changed = await _transitionOn(
        txn,
        localUuid,
        from: const [SyncStatus.syncing],
        to: SyncStatus.conflict,
        extra: {'sync_message': message},
      );
      if (changed) {
        await txn.rawUpdate(
          '''
          UPDATE products SET stock = stock + COALESCE((
            SELECT SUM(i.quantity) FROM transaction_items i
            WHERE i.transaction_uuid = ? AND i.product_id = products.id
          ), 0)
          WHERE id IN (
            SELECT product_id FROM transaction_items WHERE transaction_uuid = ?
          )
          ''',
          [localUuid, localUuid],
        );
      }
      return changed;
    });
  }

  /// `conflict` -> `pending` atas permintaan kasir ("Kirim Ulang"). Isi
  /// transaksi TIDAK diubah. Karena `pending` dikurangkan dari stok, stok
  /// lokal dikurangi lagi di transaksi SQLite yang sama (kebalikan
  /// [markConflict]). False bila statusnya bukan `conflict` lagi.
  Future<bool> requeueConflict(String localUuid) {
    return _db.transaction((txn) async {
      final changed = await _transitionOn(
        txn,
        localUuid,
        from: const [SyncStatus.conflict],
        to: SyncStatus.pending,
      );
      if (changed) {
        await txn.rawUpdate(
          '''
          UPDATE products SET stock = stock - COALESCE((
            SELECT SUM(i.quantity) FROM transaction_items i
            WHERE i.transaction_uuid = ? AND i.product_id = products.id
          ), 0)
          WHERE id IN (
            SELECT product_id FROM transaction_items WHERE transaction_uuid = ?
          )
          ''',
          [localUuid, localUuid],
        );
      }
      return changed;
    });
  }

  /// `syncing` -> `pending` tanpa kesalahan transaksi (mis. token ditolak).
  Future<bool> releaseSyncing(String localUuid) {
    return _transition(
      localUuid,
      from: const [SyncStatus.syncing],
      to: SyncStatus.pending,
    );
  }

  /// Semua `syncing` -> `pending`. Dipanggil saat aplikasi mulai: yang masih
  /// `syncing` saat itu berarti aplikasi tertutup di tengah pengiriman.
  /// Aman: bila server sempat menerimanya, kiriman ulang dijawab 200.
  Future<int> resetInterruptedSyncs() {
    return _db.update(
      'transactions',
      {'sync_status': SyncStatus.pending.name, 'sync_message': null},
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.syncing.name],
    );
  }

  Future<bool> _transition(
    String localUuid, {
    required List<SyncStatus> from,
    required SyncStatus to,
    Map<String, Object?> extra = const {},
  }) => _transitionOn(_db, localUuid, from: from, to: to, extra: extra);

  Future<bool> _transitionOn(
    DatabaseExecutor executor,
    String localUuid, {
    required List<SyncStatus> from,
    required SyncStatus to,
    Map<String, Object?> extra = const {},
  }) async {
    final marks = List.filled(from.length, '?').join(', ');
    final updated = await executor.update(
      'transactions',
      {
        'sync_status': to.name,
        // Pesan lama hilang di setiap perpindahan, kecuali diisi lagi lewat [extra].
        'sync_message': null,
        ...extra,
      },
      where: 'local_uuid = ? AND sync_status IN ($marks)',
      whereArgs: [localUuid, ...from.map((status) => status.name)],
    );
    return updated == 1;
  }

  Future<List<LocalTransaction>> _withItems(
    DatabaseExecutor executor,
    List<Map<String, Object?>> rows,
  ) async {
    final result = <LocalTransaction>[];
    for (final row in rows) {
      final uuid = row['local_uuid'] as String;
      final itemRows = await executor.query(
        'transaction_items',
        where: 'transaction_uuid = ?',
        whereArgs: [uuid],
        orderBy: 'id',
      );
      final syncedAt = row['synced_at'] as String?;
      result.add(
        LocalTransaction(
          localUuid: uuid,
          invoiceNumber: row['invoice_number'] as String,
          totalAmount: row['total_amount'] as int,
          paymentMethod: PaymentMethod.fromValue(
            row['payment_method'] as String,
          ),
          syncStatus: SyncStatus.fromValue(row['sync_status'] as String),
          createdAt: DateTime.parse(row['created_at'] as String),
          syncMessage: row['sync_message'] as String?,
          serverId: row['server_id'] as int?,
          syncedAt: syncedAt == null ? null : DateTime.parse(syncedAt),
          items: [
            for (final item in itemRows)
              LocalTransactionItem(
                productId: item['product_id'] as int,
                productName: item['product_name'] as String,
                quantity: item['quantity'] as int,
                price: item['price'] as int,
              ),
          ],
        ),
      );
    }
    return result;
  }

  /// `INV-20261011-A1B2C3`: tanggal lokal + 6 karakter pertama UUID.
  String _invoiceNumber(DateTime now, String localUuid) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${now.year}${two(now.month)}${two(now.day)}';
    final suffix = localUuid.replaceAll('-', '').substring(0, 6).toUpperCase();
    return 'INV-$date-$suffix';
  }
}
