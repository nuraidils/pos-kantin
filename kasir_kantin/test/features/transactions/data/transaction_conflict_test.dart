import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/database/app_database.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_local_data_source.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_line.dart';
import 'package:kasir_kantin/features/transactions/domain/payment_method.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String uuidOf(String p) => '${p}00-0000-4000-8000-000000000000';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;
  late TransactionLocalDataSource local;
  var minute = 0;

  Future<int> stockOf(int id) async {
    final rows = await appDb.db.query(
      'products',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.first['stock'] as int;
  }

  Future<String> sell(int quantity) async {
    final tx = await local.create(
      lines: [
        CheckoutLine(
          productId: 1,
          name: 'x',
          quantity: quantity,
          expectedPrice: 10000,
        ),
      ],
      paymentMethod: PaymentMethod.cash,
    );
    return tx.localUuid;
  }

  Future<String> sellConflict(int quantity, String message) async {
    final uuid = await sell(quantity);
    await local.markSyncing(uuid);
    await local.markConflict(uuid, message);
    return uuid;
  }

  setUp(() async {
    minute = 0;
    appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    await appDb.db.insert('products', {
      'id': 1,
      'category_id': 1,
      'name': 'Kopi Susu',
      'price': 10000,
      'stock': 10,
      'is_active': 1,
      'updated_at': '2026-10-11T00:00:00+00:00',
    });
    final uuids = [
      for (final p in ['aaaaaa', 'bbbbbb', 'cccccc']) uuidOf(p),
    ];
    local = TransactionLocalDataSource(
      appDb,
      newUuid: () => uuids.removeAt(0),
      clock: () => DateTime(2026, 10, 11, 9, minute++),
    );
  });

  tearDown(() => appDb.close());

  test(
    'getConflicts hanya conflict, terbaru dulu, dengan alasan dan item',
    () async {
      await sell(1); // pending: tidak ikut
      final b = await sellConflict(2, 'Stok kurang B.');
      final c = await sellConflict(3, 'Stok kurang C.');

      final list = await local.getConflicts();

      expect(list.map((t) => t.localUuid), [c, b]);
      expect(list.first.syncMessage, 'Stok kurang C.');
      expect(list.first.items.single.productName, 'Kopi Susu');
      expect(list.first.items.single.quantity, 3);
    },
  );

  test('getAll: semua status, terbaru dulu, tidak mengubah apa pun', () async {
    final a = await sell(1);
    final b = await sellConflict(2, 'Stok kurang B.');
    final c = await sell(3);
    await local.markSyncing(a);
    await local.markSynced(a, serverId: 9, invoiceNumber: 'INV-SERVER-1');

    final all = await local.getAll();

    expect(all.map((t) => t.localUuid), [c, b, a]);
    expect(all.map((t) => t.syncStatus), [
      SyncStatus.pending,
      SyncStatus.conflict,
      SyncStatus.synced,
    ]);
    expect(all[1].syncMessage, 'Stok kurang B.');
    expect(all[2].invoiceNumber, 'INV-SERVER-1');
    expect(all[2].items.single.quantity, 1);
    // Membaca tidak mengubah status maupun stok.
    expect((await local.getAll()).length, 3);
    expect(await stockOf(1), 10 - 1 - 3);
  });

  test(
    'requeueConflict: conflict -> pending, isi tidak berubah, stok dikurangi lagi',
    () async {
      final uuid = await sellConflict(4, 'Stok kurang.');
      expect(await stockOf(1), 10);

      final changed = await local.requeueConflict(uuid);

      expect(changed, isTrue);
      final tx = (await local.getByUuid(uuid))!;
      expect(tx.syncStatus, SyncStatus.pending);
      expect(tx.syncMessage, isNull);
      expect(tx.totalAmount, 40000);
      expect(tx.items.single.quantity, 4);
      expect(await stockOf(1), 6);
      expect((await local.getSyncable()).map((t) => t.localUuid), [uuid]);
      expect(await local.countConflicts(), 0);
    },
  );

  test(
    'requeueConflict ditolak bila bukan conflict dan stok tidak berubah',
    () async {
      final pending = await sell(2);
      expect(await local.requeueConflict(pending), isFalse);
      expect(await stockOf(1), 8);

      expect(await local.requeueConflict(uuidOf('zzzzzz')), isFalse);
    },
  );

  test(
    'requeueConflict dua kali: yang kedua tidak mengurangi stok lagi',
    () async {
      final uuid = await sellConflict(4, 'Stok kurang.');

      expect(await local.requeueConflict(uuid), isTrue);
      expect(await local.requeueConflict(uuid), isFalse);

      expect(await stockOf(1), 6);
    },
  );

  test(
    'bolak-balik conflict -> pending -> conflict menjaga stok konsisten',
    () async {
      final uuid = await sellConflict(4, 'Stok kurang.');
      await local.requeueConflict(uuid);
      await local.markSyncing(uuid);
      await local.markConflict(uuid, 'Masih kurang.');

      expect(await stockOf(1), 10);
      expect((await local.getByUuid(uuid))!.syncMessage, 'Masih kurang.');
    },
  );
}
