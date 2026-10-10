import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Database SQLite lokal kasir. Ini bagian dari arsitektur, bukan cache
/// sementara (AGENTS.md §18): transaksi offline tinggal di sini sampai
/// berhasil disinkronkan.
///
/// Aturan migrasi: JANGAN menghapus/membuat ulang database saat upgrade.
/// Tambahkan fungsi baru ke [_migrations] dan naikkan [_version].
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 1;
  static const _fileName = 'kasir_kantin.db';

  /// [path] hanya diisi pada pengujian (mis. inMemoryDatabasePath).
  static Future<AppDatabase> open({String? path}) async {
    final resolved = path ?? p.join(await getDatabasesPath(), _fileName);
    final db = await openDatabase(
      resolved,
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return AppDatabase._(db);
  }

  Future<void> close() => db.close();

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final statement in _createStatements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      final migration = _migrations[v];
      if (migration == null) {
        throw StateError('Migrasi database ke versi $v belum ditulis.');
      }
      await migration(db);
    }
  }

  /// Versi 2, 3, ... ditambahkan di sini. Versi 1 dibuat oleh [_createStatements].
  static final Map<int, Future<void> Function(Database db)> _migrations = {};

  static const _createStatements = <String>[
    // Salinan katalog dari server (id = id server). Data terhapus di server
    // dihapus lokal; riwayat tetap aman karena transaction_items menyimpan
    // snapshot nama & harga.
    '''
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      slug TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    // `stock` = proyeksi stok terakhir yang diketahui, dikurangi penjualan
    // offline. Sengaja tanpa CHECK >= 0: proyeksi boleh sementara tidak
    // sinkron dengan server; server yang memutuskan lewat status conflict.
    '''
    CREATE TABLE products (
      id INTEGER PRIMARY KEY,
      category_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      price INTEGER NOT NULL CHECK (price >= 0),
      stock INTEGER NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
      image_url TEXT,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_products_category ON products(category_id)',
    // Transaksi lokal. local_uuid = kunci idempotensi yang dikirim ke server.
    // sync_status mengikuti AGENTS.md §11; sync_message menyimpan alasan
    // failed/conflict agar bisa dijelaskan ke kasir (DESIGN.md §20).
    '''
    CREATE TABLE transactions (
      local_uuid TEXT PRIMARY KEY,
      invoice_number TEXT NOT NULL UNIQUE,
      total_amount INTEGER NOT NULL CHECK (total_amount > 0),
      payment_method TEXT NOT NULL CHECK (payment_method IN ('cash', 'qris')),
      sync_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (sync_status IN ('pending', 'syncing', 'synced', 'failed', 'conflict')),
      sync_message TEXT,
      server_id INTEGER,
      created_at TEXT NOT NULL,
      synced_at TEXT
    )
    ''',
    'CREATE INDEX idx_transactions_sync_status ON transactions(sync_status)',
    'CREATE INDEX idx_transactions_created_at ON transactions(created_at)',
    // Snapshot historis: nama & harga saat penjualan, bukan dari products.
    '''
    CREATE TABLE transaction_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      transaction_uuid TEXT NOT NULL
        REFERENCES transactions(local_uuid) ON DELETE CASCADE,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      quantity INTEGER NOT NULL CHECK (quantity > 0),
      price INTEGER NOT NULL CHECK (price >= 0),
      subtotal INTEGER NOT NULL CHECK (subtotal >= 0)
    )
    ''',
    'CREATE INDEX idx_transaction_items_tx ON transaction_items(transaction_uuid)',
    // products_last_sync, categories_last_sync, ... (AGENTS.md §15).
    '''
    CREATE TABLE sync_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ];
}
