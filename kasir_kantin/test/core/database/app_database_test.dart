import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;

  setUp(() async {
    appDb = await AppDatabase.open(path: inMemoryDatabasePath);
  });

  tearDown(() => appDb.close());

  Future<void> insertTransaction(
    String uuid, {
    String paymentMethod = 'cash',
    String? syncStatus,
  }) {
    return appDb.db.insert('transactions', {
      'local_uuid': uuid,
      'invoice_number': 'INV-$uuid',
      'total_amount': 20000,
      'payment_method': paymentMethod,
      if (syncStatus != null) 'sync_status': syncStatus,
      'created_at': '2026-10-08T10:00:00Z',
    });
  }

  test('membuat semua tabel yang dibutuhkan alur offline', () async {
    final rows = await appDb.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    final names = rows.map((r) => r['name']).toSet();

    expect(
      names,
      containsAll([
        'categories',
        'products',
        'transactions',
        'transaction_items',
        'sync_metadata',
      ]),
    );
  });

  test('transaksi baru berstatus pending secara default', () async {
    await insertTransaction('a');

    final row = (await appDb.db.query('transactions')).single;
    expect(row['sync_status'], 'pending');
  });

  test('menerima kelima status sinkronisasi', () async {
    for (final status in [
      'pending',
      'syncing',
      'synced',
      'failed',
      'conflict',
    ]) {
      await insertTransaction('uuid-$status', syncStatus: status);
    }
    expect(await appDb.db.query('transactions'), hasLength(5));
  });

  test('menolak status sinkronisasi yang tidak dikenal', () async {
    expect(
      () => insertTransaction('x', syncStatus: 'done'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('menolak metode pembayaran selain cash dan qris', () async {
    expect(
      () => insertTransaction('x', paymentMethod: 'card'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'menolak local_uuid ganda (satu transaksi lokal = satu identitas)',
    () async {
      await insertTransaction('dup');
      expect(() => insertTransaction('dup'), throwsA(isA<DatabaseException>()));
    },
  );

  test(
    'item ikut terhapus saat transaksi dihapus (foreign key aktif)',
    () async {
      await insertTransaction('t1');
      await appDb.db.insert('transaction_items', {
        'transaction_uuid': 't1',
        'product_id': 1,
        'product_name': 'Es Teh',
        'quantity': 2,
        'price': 5000,
        'subtotal': 10000,
      });

      await appDb.db.delete(
        'transactions',
        where: 'local_uuid = ?',
        whereArgs: ['t1'],
      );

      expect(await appDb.db.query('transaction_items'), isEmpty);
    },
  );

  test('menolak item untuk transaksi yang tidak ada', () async {
    expect(
      () => appDb.db.insert('transaction_items', {
        'transaction_uuid': 'tidak-ada',
        'product_id': 1,
        'product_name': 'Es Teh',
        'quantity': 1,
        'price': 5000,
        'subtotal': 5000,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
