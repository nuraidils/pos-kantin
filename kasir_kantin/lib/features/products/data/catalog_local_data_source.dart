import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/catalog_changes.dart';
import '../domain/product.dart';
import '../domain/product_category.dart';
import 'catalog_mappers.dart';

/// Akses SQLite untuk katalog. Satu-satunya tempat SQL katalog berada.
class CatalogLocalDataSource {
  CatalogLocalDataSource(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Satu kursor untuk seluruh endpoint katalog: kategori dan produk datang
  /// dalam satu respons, jadi `categories_last_sync` terpisah tidak perlu.
  static const lastSyncKey = 'products_last_sync';

  Future<List<ProductCategory>> getCategories() async {
    final rows = await _db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map(categoryFromRow).toList();
  }

  /// Hanya produk aktif; produk nonaktif tetap tersimpan tetapi tidak dijual.
  Future<List<Product>> getActiveProducts() async {
    final rows = await _db.query(
      'products',
      where: 'is_active = 1',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(productFromRow).toList();
  }

  Future<String?> readLastSync() async {
    final rows = await _db.query(
      'sync_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [lastSyncKey],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// Menerapkan satu respons katalog SECARA ATOMIK: upsert, hapus, dan
  /// kursor sinkronisasi berhasil bersama atau batal bersama. Kursor yang
  /// maju tanpa data akan membuat perubahan terlewat selamanya.
  Future<void> applyChanges(CatalogChanges changes) {
    return _db.transaction((txn) async {
      // Dihitung sebelum menulis: stok yang diterima dari server belum
      // memperhitungkan penjualan offline yang belum sampai ke server.
      final unsynced = await _unsyncedQuantities(txn);

      if (changes.fullSync) {
        // Respons penuh tidak memuat data terhapus, jadi yang tidak ada di
        // dalamnya harus dibuang. Aman: tidak ada foreign key ke dua tabel
        // ini, dan riwayat transaksi memakai snapshot nama/harga sendiri.
        await txn.delete('products');
        await txn.delete('categories');
      }

      final batch = txn.batch();
      for (final id in changes.deletedCategoryIds) {
        batch.delete('categories', where: 'id = ?', whereArgs: [id]);
      }
      for (final id in changes.deletedProductIds) {
        batch.delete('products', where: 'id = ?', whereArgs: [id]);
      }
      for (final category in changes.categories) {
        batch.insert(
          'categories',
          categoryToRow(category),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final product in changes.products) {
        batch.insert(
          'products',
          productToRow(
            product,
            stock: product.stock - (unsynced[product.id] ?? 0),
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      batch.insert('sync_metadata', {
        'key': lastSyncKey,
        'value': changes.serverTime,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
  }

  /// Jumlah per produk dari transaksi lokal yang belum diterima server
  /// (`pending`, `syncing`, `failed`). `conflict` tidak dihitung: server
  /// menolaknya, jadi stok server memang tidak berkurang karenanya.
  Future<Map<int, int>> _unsyncedQuantities(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery('''
      SELECT i.product_id AS product_id, SUM(i.quantity) AS quantity
      FROM transaction_items i
      JOIN transactions t ON t.local_uuid = i.transaction_uuid
      WHERE t.sync_status IN ('pending', 'syncing', 'failed')
      GROUP BY i.product_id
    ''');
    return {
      for (final row in rows)
        (row['product_id'] as int): (row['quantity'] as num).toInt(),
    };
  }
}
