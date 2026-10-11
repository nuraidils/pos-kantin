import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/database/app_database.dart';
import 'package:kasir_kantin/features/products/data/catalog_local_data_source.dart';
import 'package:kasir_kantin/features/products/domain/catalog_changes.dart';
import 'package:kasir_kantin/features/products/domain/product.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_local_data_source.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_exception.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_line.dart';
import 'package:kasir_kantin/features/transactions/domain/payment_method.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String uuidOf(String prefix8, [int n = 0]) =>
    '$prefix8-0000-4000-8000-${n.toString().padLeft(12, '0')}';

CheckoutLine line(
  int productId, {
  int quantity = 1,
  int price = 10000,
  String name = 'x',
}) => CheckoutLine(
  productId: productId,
  name: name,
  quantity: quantity,
  expectedPrice: price,
);

Future<void> insertProduct(
  AppDatabase db,
  int id,
  String name, {
  int price = 10000,
  int stock = 10,
  bool active = true,
}) {
  return db.db.insert('products', {
    'id': id,
    'category_id': 1,
    'name': name,
    'price': price,
    'stock': stock,
    'is_active': active ? 1 : 0,
    'updated_at': '2026-10-11T00:00:00+00:00',
  });
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 09:30 waktu lokal pada 11 Okt 2026.
  final fixedNow = DateTime(2026, 10, 11, 9, 30);

  late AppDatabase appDb;

  Future<int> stockOf(int id) async {
    final rows = await appDb.db.query(
      'products',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.first['stock'] as int;
  }

  Future<int> count(String table) async => (await appDb.db.query(table)).length;

  TransactionLocalDataSource makeLocal({List<String>? uuids}) {
    final queue = [...?uuids];
    var counter = 0;
    return TransactionLocalDataSource(
      appDb,
      newUuid: () => queue.isNotEmpty
          ? queue.removeAt(0)
          // Enam karakter pertama berbeda di tiap transaksi -> invoice berbeda.
          : uuidOf('${(++counter).toRadixString(16).padLeft(6, '0')}00'),
      clock: () => fixedNow,
    );
  }

  setUp(() async {
    appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    await insertProduct(appDb, 1, 'Kopi Susu', price: 10000, stock: 10);
    await insertProduct(appDb, 2, 'Es Teh', price: 5000, stock: 3);
    await insertProduct(appDb, 3, 'Produk Nonaktif', active: false);
  });

  tearDown(() => appDb.close());

  group('transaksi berhasil', () {
    test('tersimpan pending dengan total, invoice, dan item', () async {
      final local = makeLocal(uuids: [uuidOf('abcdef12')]);

      final tx = await local.create(
        lines: [line(1, quantity: 2), line(2, price: 5000)],
        paymentMethod: PaymentMethod.qris,
      );

      expect(tx.totalAmount, 25000);
      expect(tx.syncStatus, SyncStatus.pending);
      expect(tx.paymentMethod, PaymentMethod.qris);
      expect(tx.invoiceNumber, 'INV-20261011-ABCDEF');
      expect(tx.localUuid, uuidOf('abcdef12'));
      expect(tx.createdAt, fixedNow);
      expect(tx.items.map((i) => (i.productName, i.quantity, i.subtotal)), [
        ('Kopi Susu', 2, 20000),
        ('Es Teh', 1, 5000),
      ]);

      final rows = await appDb.db.query('transactions');
      expect(rows, hasLength(1));
      expect(rows.first['local_uuid'], tx.localUuid);
      expect(rows.first['invoice_number'], 'INV-20261011-ABCDEF');
      expect(rows.first['total_amount'], 25000);
      expect(rows.first['payment_method'], 'qris');
      expect(rows.first['sync_status'], 'pending');
      expect(rows.first['created_at'], fixedNow.toUtc().toIso8601String());
      expect(rows.first['synced_at'], isNull);

      final items = await appDb.db.query('transaction_items', orderBy: 'id');
      expect(items.map((r) => r['transaction_uuid']).toSet(), {tx.localUuid});
      expect(items.map((r) => r['product_id']), [1, 2]);
      expect(items.map((r) => r['subtotal']), [20000, 5000]);
    });

    test('stok lokal berkurang sebanyak jumlah terjual', () async {
      await makeLocal().create(
        lines: [line(1, quantity: 3), line(2, price: 5000, quantity: 3)],
        paymentMethod: PaymentMethod.cash,
      );

      expect(await stockOf(1), 7);
      expect(await stockOf(2), 0); // tepat habis masih boleh dijual
    });

    test(
      'nama dan harga diambil dari SQLite, bukan dari baris pemanggil',
      () async {
        final tx = await makeLocal().create(
          lines: [line(1, name: 'Nama Basi')],
          paymentMethod: PaymentMethod.cash,
        );

        expect(tx.items.single.productName, 'Kopi Susu');
      },
    );

    test('riwayat tidak berubah saat harga dan nama produk berubah', () async {
      await makeLocal().create(
        lines: [line(1, quantity: 2)],
        paymentMethod: PaymentMethod.cash,
      );

      await appDb.db.update('products', {
        'name': 'Kopi Susu Baru',
        'price': 12000,
      }, where: 'id = 1');

      final item = (await appDb.db.query('transaction_items')).single;
      expect(item['product_name'], 'Kopi Susu');
      expect(item['price'], 10000);
      expect(item['subtotal'], 20000);
    });

    test('baris dengan produk sama digabung menjadi satu item', () async {
      final tx = await makeLocal().create(
        lines: [line(1), line(1, quantity: 2)],
        paymentMethod: PaymentMethod.cash,
      );

      expect(tx.items, hasLength(1));
      expect(tx.items.single.quantity, 3);
      expect(await stockOf(1), 7);
    });

    test('nomor invoice dan UUID berbeda untuk dua transaksi', () async {
      final local = makeLocal();

      final a = await local.create(
        lines: [line(1)],
        paymentMethod: PaymentMethod.cash,
      );
      final b = await local.create(
        lines: [line(1)],
        paymentMethod: PaymentMethod.cash,
      );

      expect(a.invoiceNumber, isNot(b.invoiceNumber));
      expect(a.localUuid, isNot(b.localUuid));
      expect(await count('transactions'), 2);
    });
  });

  group('ditolak -> tidak ada yang berubah', () {
    Future<void> expectUntouched() async {
      expect(await count('transactions'), 0);
      expect(await count('transaction_items'), 0);
      expect(await stockOf(1), 10);
      expect(await stockOf(2), 3);
    }

    test('stok tidak cukup', () async {
      await expectLater(
        makeLocal().create(
          lines: [line(1, quantity: 11)],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(
          isA<CheckoutInsufficientStockException>()
              .having((e) => e.productName, 'productName', 'Kopi Susu')
              .having((e) => e.available, 'available', 10),
        ),
      );
      await expectUntouched();
    });

    test('satu baris gagal -> baris lain yang valid ikut dibatalkan', () async {
      await expectLater(
        makeLocal().create(
          lines: [line(1, quantity: 2), line(2, price: 5000, quantity: 4)],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<CheckoutInsufficientStockException>()),
      );
      await expectUntouched();
    });

    test('stok lokal negatif dilaporkan sebagai tersisa 0', () async {
      await appDb.db.update('products', {'stock': -2}, where: 'id = 1');

      await expectLater(
        makeLocal().create(lines: [line(1)], paymentMethod: PaymentMethod.cash),
        throwsA(
          isA<CheckoutInsufficientStockException>().having(
            (e) => e.available,
            'available',
            0,
          ),
        ),
      );
    });

    test('produk tidak ada di data lokal', () async {
      await expectLater(
        makeLocal().create(
          lines: [line(99, name: 'Hantu')],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(
          isA<CheckoutProductUnavailableException>().having(
            (e) => e.productName,
            'productName',
            'Hantu',
          ),
        ),
      );
      await expectUntouched();
    });

    test('produk nonaktif', () async {
      await expectLater(
        makeLocal().create(
          lines: [line(3, name: 'Produk Nonaktif')],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<CheckoutProductUnavailableException>()),
      );
      await expectUntouched();
    });

    test('harga di SQLite berbeda dari yang dilihat kasir', () async {
      await expectLater(
        makeLocal().create(
          lines: [line(1, price: 9000)],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<CheckoutPriceChangedException>()),
      );
      await expectUntouched();
    });

    test('keranjang kosong', () async {
      await expectLater(
        makeLocal().create(lines: const [], paymentMethod: PaymentMethod.cash),
        throwsA(isA<CheckoutEmptyException>()),
      );
    });

    test('jumlah nol atau negatif', () async {
      for (final quantity in [0, -1]) {
        await expectLater(
          makeLocal().create(
            lines: [line(1, quantity: quantity)],
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(isA<CheckoutInvalidQuantityException>()),
        );
      }
      await expectUntouched();
    });
  });

  group('tabrakan nomor invoice', () {
    test('dicoba lagi dengan UUID baru', () async {
      // Tiga UUID pertama berawalan sama -> invoice sama (tanggal juga sama).
      final local = makeLocal(
        uuids: [uuidOf('aaaaaa01'), uuidOf('aaaaaa02'), uuidOf('bbbbbb03')],
      );

      final first = await local.create(
        lines: [line(1)],
        paymentMethod: PaymentMethod.cash,
      );
      final second = await local.create(
        lines: [line(1)],
        paymentMethod: PaymentMethod.cash,
      );

      expect(first.invoiceNumber, 'INV-20261011-AAAAAA');
      expect(second.invoiceNumber, 'INV-20261011-BBBBBB');
      expect(await count('transactions'), 2);
      // Percobaan yang gagal tidak boleh mengurangi stok dua kali.
      expect(await stockOf(1), 8);
    });

    test('menyerah setelah tiga kali dan tidak mengubah apa pun', () async {
      final local = makeLocal(
        uuids: [
          uuidOf('aaaaaa01'),
          uuidOf('aaaaaa02'),
          uuidOf('aaaaaa03'),
          uuidOf('aaaaaa04'),
        ],
      );
      await local.create(lines: [line(1)], paymentMethod: PaymentMethod.cash);

      await expectLater(
        local.create(lines: [line(1)], paymentMethod: PaymentMethod.cash),
        throwsA(isA<DatabaseException>()),
      );

      expect(await count('transactions'), 1);
      expect(await stockOf(1), 9);
    });
  });

  group('bersama katalog', () {
    test(
      'sinkronisasi katalog tidak mengembalikan stok yang sudah terjual',
      () async {
        await makeLocal().create(
          lines: [line(1, quantity: 3)],
          paymentMethod: PaymentMethod.cash,
        );

        // Server belum tahu penjualan ini: stok masih 10.
        await CatalogLocalDataSource(appDb).applyChanges(
          CatalogChanges(
            categories: const [],
            products: [
              const Product(
                id: 1,
                categoryId: 1,
                name: 'Kopi Susu',
                price: 10000,
                stock: 10,
                isActive: true,
                updatedAt: '2026-10-11T02:00:00+00:00',
              ),
            ],
            deletedCategoryIds: const {},
            deletedProductIds: const {},
            serverTime: '2026-10-11T02:00:00+00:00',
            fullSync: false,
          ),
        );

        expect(await stockOf(1), 7);
      },
    );
  });

  test(
    'transaksi masih ada setelah database ditutup dan dibuka lagi',
    () async {
      final dir = Directory.systemTemp.createTempSync('kasir_kantin_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'restart.db');

      var db = await AppDatabase.open(path: path);
      await insertProduct(db, 1, 'Kopi Susu', stock: 10);
      final tx = await TransactionLocalDataSource(db, clock: () => fixedNow)
          .create(
            lines: [line(1, quantity: 2)],
            paymentMethod: PaymentMethod.cash,
          );
      await db.close();

      // "Restart aplikasi".
      db = await AppDatabase.open(path: path);
      addTearDown(db.close);

      final rows = await db.db.query('transactions');
      expect(rows, hasLength(1));
      expect(rows.first['local_uuid'], tx.localUuid);
      expect(rows.first['sync_status'], 'pending');
      expect(await db.db.query('transaction_items'), hasLength(1));
      expect((await db.db.query('products')).first['stock'], 8);
    },
  );
}
