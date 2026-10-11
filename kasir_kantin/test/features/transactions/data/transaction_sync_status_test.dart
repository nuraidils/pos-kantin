import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/database/app_database.dart';
import 'package:kasir_kantin/features/products/data/catalog_local_data_source.dart';
import 'package:kasir_kantin/features/products/domain/catalog_changes.dart';
import 'package:kasir_kantin/features/products/domain/product.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_local_data_source.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_line.dart';
import 'package:kasir_kantin/features/transactions/domain/payment_method.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String uuidOf(String prefix6) => '${prefix6}00-0000-4000-8000-000000000000';

CheckoutLine line(int productId, {int quantity = 1, int price = 10000}) =>
    CheckoutLine(
      productId: productId,
      name: 'x',
      quantity: quantity,
      expectedPrice: price,
    );

Future<void> insertProduct(AppDatabase db, int id, String name, int stock) {
  return db.db.insert('products', {
    'id': id,
    'category_id': 1,
    'name': name,
    'price': 10000,
    'stock': stock,
    'is_active': 1,
    'updated_at': '2026-10-11T00:00:00+00:00',
  });
}

Future<int> stockOf(AppDatabase db, int id) async {
  final rows = await db.db.query(
    'products',
    columns: ['stock'],
    where: 'id = ?',
    whereArgs: [id],
  );
  return rows.first['stock'] as int;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final fixedNow = DateTime(2026, 10, 11, 9, 30);

  late AppDatabase appDb;
  late TransactionLocalDataSource local;

  TransactionLocalDataSource makeLocal(AppDatabase db, List<String> uuids) {
    final queue = [...uuids];
    return TransactionLocalDataSource(
      db,
      newUuid: () => queue.removeAt(0),
      clock: () => fixedNow,
    );
  }

  Future<String> sell(
    TransactionLocalDataSource source, {
    int product = 1,
    int quantity = 1,
  }) async {
    final tx = await source.create(
      lines: [line(product, quantity: quantity)],
      paymentMethod: PaymentMethod.cash,
    );
    return tx.localUuid;
  }

  setUp(() async {
    appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    await insertProduct(appDb, 1, 'Kopi Susu', 10);
    await insertProduct(appDb, 2, 'Es Teh', 5);
    local = makeLocal(appDb, [
      uuidOf('aaaaaa'),
      uuidOf('bbbbbb'),
      uuidOf('cccccc'),
      uuidOf('dddddd'),
    ]);
  });

  tearDown(() => appDb.close());

  group('membaca', () {
    test('getByUuid memuat item, status, dan kolom sinkronisasi', () async {
      final uuid = await sell(local, quantity: 2);

      final tx = await local.getByUuid(uuid);

      expect(tx, isNotNull);
      expect(tx!.syncStatus, SyncStatus.pending);
      expect(tx.items.single.productName, 'Kopi Susu');
      expect(tx.items.single.quantity, 2);
      expect(tx.totalAmount, 20000);
      expect(tx.syncMessage, isNull);
      expect(tx.serverId, isNull);
      expect(tx.syncedAt, isNull);
    });

    test('getByUuid mengembalikan null bila tidak ada', () async {
      expect(await local.getByUuid(uuidOf('zzzzzz')), isNull);
    });

    test('getSyncable hanya pending dan failed, dari yang terlama', () async {
      final a = await sell(local);
      final b = await sell(local);
      final c = await sell(local);
      final d = await sell(local);
      await local.markSyncing(b);
      await local.markFailed(b, 'Tidak ada internet.');
      await local.markSyncing(c); // syncing: tidak ikut
      await local.markSyncing(d);
      await local.markSynced(d, serverId: 1, invoiceNumber: 'INV-X');

      final syncable = await local.getSyncable();

      expect(syncable.map((t) => t.localUuid), [a, b]);
    });

    test('hitungan belum tersinkron dan konflik', () async {
      await sell(local); // a: pending
      final b = await sell(local);
      final c = await sell(local);
      final d = await sell(local);
      await local.markSyncing(b); // b: syncing
      await local.markSyncing(c);
      await local.markConflict(c, 'Stok kurang.'); // c: conflict
      await local.markSyncing(d);
      await local.markSynced(
        d,
        serverId: 9,
        invoiceNumber: 'INV-D',
      ); // d: synced

      expect(await local.countUnsynced(), 2);
      expect(await local.countConflicts(), 1);
    });
  });

  group('perpindahan status', () {
    test(
      'pending -> syncing -> synced mengisi server_id dan synced_at',
      () async {
        final uuid = await sell(local);

        expect(await local.markSyncing(uuid), isTrue);
        expect((await local.getByUuid(uuid))!.syncStatus, SyncStatus.syncing);

        final syncedAt = DateTime.utc(2026, 10, 11, 2, 31);
        expect(
          await local.markSynced(
            uuid,
            serverId: 77,
            invoiceNumber: (await local.getByUuid(uuid))!.invoiceNumber,
            syncedAt: syncedAt,
          ),
          isTrue,
        );

        final tx = (await local.getByUuid(uuid))!;
        expect(tx.syncStatus, SyncStatus.synced);
        expect(tx.serverId, 77);
        expect(tx.syncedAt, syncedAt);
        expect(tx.syncMessage, isNull);
      },
    );

    test(
      'markSyncing hanya berhasil satu kali (tidak ada kirim ganda)',
      () async {
        final uuid = await sell(local);

        expect(await local.markSyncing(uuid), isTrue);
        expect(await local.markSyncing(uuid), isFalse);
      },
    );

    test('transaksi synced tidak bisa dikirim atau diubah lagi', () async {
      final uuid = await sell(local);
      await local.markSyncing(uuid);
      await local.markSynced(uuid, serverId: 1, invoiceNumber: 'INV-1');

      expect(await local.markSyncing(uuid), isFalse);
      expect(await local.markFailed(uuid, 'x'), isFalse);
      expect(await local.markConflict(uuid, 'x'), isFalse);
      expect((await local.getByUuid(uuid))!.syncStatus, SyncStatus.synced);
    });

    test('perpindahan hanya sah dari syncing', () async {
      final uuid = await sell(local);

      expect(
        await local.markSynced(uuid, serverId: 1, invoiceNumber: 'A'),
        isFalse,
      );
      expect(await local.markFailed(uuid, 'x'), isFalse);
      expect(await local.markConflict(uuid, 'x'), isFalse);
      expect(await local.releaseSyncing(uuid), isFalse);
      expect((await local.getByUuid(uuid))!.syncStatus, SyncStatus.pending);
    });

    test('failed menyimpan alasan, dan bisa dikirim lagi', () async {
      final uuid = await sell(local);
      await local.markSyncing(uuid);
      await local.markFailed(uuid, 'Tidak dapat terhubung ke internet.');

      final failed = (await local.getByUuid(uuid))!;
      expect(failed.syncStatus, SyncStatus.failed);
      expect(failed.syncMessage, 'Tidak dapat terhubung ke internet.');

      expect(await local.markSyncing(uuid), isTrue);
      expect((await local.getByUuid(uuid))!.syncMessage, isNull);
    });

    test('conflict tidak bisa dikirim ulang diam-diam', () async {
      final uuid = await sell(local);
      await local.markSyncing(uuid);
      await local.markConflict(uuid, 'Stok kurang.');

      expect(await local.markSyncing(uuid), isFalse);
      expect((await local.getByUuid(uuid))!.syncStatus, SyncStatus.conflict);
      expect((await local.getByUuid(uuid))!.syncMessage, 'Stok kurang.');
    });

    test('releaseSyncing mengembalikan ke pending', () async {
      final uuid = await sell(local);
      await local.markSyncing(uuid);

      expect(await local.releaseSyncing(uuid), isTrue);
      expect((await local.getByUuid(uuid))!.syncStatus, SyncStatus.pending);
    });

    test('nomor invoice dari server menggantikan nomor lokal', () async {
      final uuid = await sell(local);
      await local.markSyncing(uuid);

      await local.markSynced(
        uuid,
        serverId: 5,
        invoiceNumber: 'INV-20261011-AAAAAA-2',
      );

      expect(
        (await local.getByUuid(uuid))!.invoiceNumber,
        'INV-20261011-AAAAAA-2',
      );
    });

    test(
      'invoice server yang bentrok dengan nomor lokal lain tidak membatalkan synced',
      () async {
        final a = await sell(local);
        final b = await sell(local);
        final invoiceA = (await local.getByUuid(a))!.invoiceNumber;
        await local.markSyncing(b);

        final ok = await local.markSynced(
          b,
          serverId: 6,
          invoiceNumber: invoiceA,
        );

        expect(ok, isTrue);
        final tx = (await local.getByUuid(b))!;
        expect(tx.syncStatus, SyncStatus.synced);
        expect(tx.invoiceNumber, isNot(invoiceA));
      },
    );

    test(
      'resetInterruptedSyncs mengembalikan semua syncing ke pending',
      () async {
        final a = await sell(local);
        final b = await sell(local);
        final c = await sell(local);
        await local.markSyncing(a);
        await local.markSyncing(b);
        await local.markSyncing(c);
        await local.markSynced(c, serverId: 1, invoiceNumber: 'INV-C');

        expect(await local.resetInterruptedSyncs(), 2);

        expect((await local.getByUuid(a))!.syncStatus, SyncStatus.pending);
        expect((await local.getByUuid(b))!.syncStatus, SyncStatus.pending);
        expect((await local.getByUuid(c))!.syncStatus, SyncStatus.synced);
      },
    );
  });

  group('stok lokal', () {
    test(
      'failed dan syncing tetap mengurangi stok, synced tidak mengubahnya',
      () async {
        final uuid = await sell(local, quantity: 3);
        expect(await stockOf(appDb, 1), 7);

        await local.markSyncing(uuid);
        expect(await stockOf(appDb, 1), 7);
        await local.markFailed(uuid, 'x');
        expect(await stockOf(appDb, 1), 7);
        await local.markSyncing(uuid);
        await local.markSynced(uuid, serverId: 1, invoiceNumber: 'INV-1');
        expect(await stockOf(appDb, 1), 7);
      },
    );

    test(
      'conflict mengembalikan stok lokal dan transaksi tetap tersimpan',
      () async {
        final uuid = await sell(local, quantity: 4);
        expect(await stockOf(appDb, 1), 6);

        await local.markSyncing(uuid);
        await local.markConflict(uuid, 'Stok kurang.');

        expect(await stockOf(appDb, 1), 10);
        expect(await stockOf(appDb, 2), 5); // produk lain tidak tersentuh
        expect(await local.getByUuid(uuid), isNotNull);
      },
    );

    test('conflict hanya mengembalikan stok transaksinya sendiri', () async {
      final a = await sell(local, quantity: 4);
      await sell(local, quantity: 2); // pending, tetap dikurangkan
      expect(await stockOf(appDb, 1), 4);

      await local.markSyncing(a);
      await local.markConflict(a, 'Stok kurang.');

      expect(await stockOf(appDb, 1), 8);
    });

    test(
      'conflict tidak error bila produknya sudah tidak ada di katalog lokal',
      () async {
        final uuid = await sell(local, product: 2, quantity: 1);
        await appDb.db.delete('products', where: 'id = 2');
        await local.markSyncing(uuid);

        expect(await local.markConflict(uuid, 'Stok kurang.'), isTrue);
        expect((await local.getByUuid(uuid))!.syncStatus, SyncStatus.conflict);
      },
    );

    test(
      'pull katalog sesudahnya konsisten: conflict tidak dikurangkan, pending tetap',
      () async {
        final catalog = CatalogLocalDataSource(appDb);
        final conflicted = await sell(local, quantity: 4);
        await sell(local, quantity: 2); // pending: tetap dikurangkan
        await local.markSyncing(conflicted);
        await local.markConflict(conflicted, 'Stok kurang.');

        // Server melaporkan stok 10: 10 - 2 (pending) = 8, bukan 4 atau 6.
        await catalog.applyChanges(
          const CatalogChanges(
            categories: [],
            products: [
              Product(
                id: 1,
                categoryId: 1,
                name: 'Kopi Susu',
                price: 10000,
                stock: 10,
                isActive: true,
                updatedAt: '2026-10-11T03:00:00+00:00',
              ),
            ],
            deletedCategoryIds: <int>{},
            deletedProductIds: <int>{},
            serverTime: '2026-10-11T03:00:00+00:00',
            fullSync: false,
          ),
        );

        expect(await stockOf(appDb, 1), 8);
      },
    );
  });

  group('bertahan setelah aplikasi ditutup (AGENTS.md §27)', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('kasir_kantin_test_');
      path = p.join(dir.path, 'kasir.db');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test(
      'transaksi, item, status, dan stok masih ada setelah database dibuka ulang',
      () async {
        final first = await AppDatabase.open(path: path);
        await insertProduct(first, 1, 'Kopi Susu', 10);
        final source = makeLocal(first, [uuidOf('eeeeee'), uuidOf('ffffff')]);
        final a = await sell(source, quantity: 3);
        final b = await sell(source, quantity: 1);
        await source.markSyncing(b);
        await source.markFailed(b, 'Tidak dapat terhubung ke internet.');
        await first.close(); // "aplikasi ditutup"

        final second = await AppDatabase.open(path: path);
        addTearDown(second.close);
        final reopened = makeLocal(second, []);

        final txA = await reopened.getByUuid(a);
        final txB = await reopened.getByUuid(b);
        expect(txA!.syncStatus, SyncStatus.pending);
        expect(txA.items.single.quantity, 3);
        expect(txA.items.single.productName, 'Kopi Susu');
        expect(txB!.syncStatus, SyncStatus.failed);
        expect(txB.syncMessage, 'Tidak dapat terhubung ke internet.');
        expect(await stockOf(second, 1), 6);
        expect((await reopened.getSyncable()).map((t) => t.localUuid), [a, b]);
      },
    );

    test(
      'transaksi yang tertinggal syncing dipulihkan ke pending setelah dibuka ulang',
      () async {
        final first = await AppDatabase.open(path: path);
        await insertProduct(first, 1, 'Kopi Susu', 10);
        final source = makeLocal(first, [uuidOf('eeeeee')]);
        final a = await sell(source);
        await source.markSyncing(a); // aplikasi mati di tengah pengiriman
        await first.close();

        final second = await AppDatabase.open(path: path);
        addTearDown(second.close);
        final reopened = makeLocal(second, []);
        expect((await reopened.getByUuid(a))!.syncStatus, SyncStatus.syncing);

        expect(await reopened.resetInterruptedSyncs(), 1);

        expect((await reopened.getByUuid(a))!.syncStatus, SyncStatus.pending);
        expect(await reopened.markSyncing(a), isTrue);
      },
    );

    test('conflict tetap terlihat setelah dibuka ulang', () async {
      final first = await AppDatabase.open(path: path);
      await insertProduct(first, 1, 'Kopi Susu', 10);
      final source = makeLocal(first, [uuidOf('eeeeee')]);
      final a = await sell(source, quantity: 4);
      await source.markSyncing(a);
      await source.markConflict(a, 'Stok kurang.');
      await first.close();

      final second = await AppDatabase.open(path: path);
      addTearDown(second.close);
      final reopened = makeLocal(second, []);

      final tx = await reopened.getByUuid(a);
      expect(tx!.syncStatus, SyncStatus.conflict);
      expect(tx.syncMessage, 'Stok kurang.');
      expect(await reopened.countConflicts(), 1);
    });
  });
}
