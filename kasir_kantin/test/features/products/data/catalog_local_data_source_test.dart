import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/database/app_database.dart';
import 'package:kasir_kantin/features/products/data/catalog_local_data_source.dart';
import 'package:kasir_kantin/features/products/domain/catalog_changes.dart';
import 'package:kasir_kantin/features/products/domain/product.dart';
import 'package:kasir_kantin/features/products/domain/product_category.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ProductCategory cat(int id, String name) => ProductCategory(
  id: id,
  name: name,
  slug: name.toLowerCase(),
  updatedAt: '2026-10-09T10:00:00+00:00',
);

Product prod(
  int id,
  String name, {
  int categoryId = 1,
  int price = 10000,
  int stock = 10,
  bool active = true,
}) => Product(
  id: id,
  categoryId: categoryId,
  name: name,
  price: price,
  stock: stock,
  isActive: active,
  updatedAt: '2026-10-09T10:00:00+00:00',
);

CatalogChanges changes({
  List<ProductCategory> categories = const [],
  List<Product> products = const [],
  Set<int> deletedCategoryIds = const {},
  Set<int> deletedProductIds = const {},
  String serverTime = '2026-10-09T10:05:00+00:00',
  bool fullSync = false,
}) => CatalogChanges(
  categories: categories,
  products: products,
  deletedCategoryIds: deletedCategoryIds,
  deletedProductIds: deletedProductIds,
  serverTime: serverTime,
  fullSync: fullSync,
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;
  late CatalogLocalDataSource local;

  setUp(() async {
    appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    local = CatalogLocalDataSource(appDb);
  });

  tearDown(() => appDb.close());

  Future<void> insertTransaction(
    String uuid,
    String status,
    Map<int, int> quantities,
  ) async {
    await appDb.db.insert('transactions', {
      'local_uuid': uuid,
      'invoice_number': 'INV-$uuid',
      'total_amount': 10000,
      'payment_method': 'cash',
      'sync_status': status,
      'created_at': '2026-10-09T10:00:00Z',
    });
    for (final entry in quantities.entries) {
      await appDb.db.insert('transaction_items', {
        'transaction_uuid': uuid,
        'product_id': entry.key,
        'product_name': 'x',
        'quantity': entry.value,
        'price': 10000,
        'subtotal': 10000 * entry.value,
      });
    }
  }

  test('katalog kosong dan belum pernah sinkron pada awalnya', () async {
    expect(await local.getCategories(), isEmpty);
    expect(await local.getActiveProducts(), isEmpty);
    expect(await local.readLastSync(), isNull);
  });

  test('sinkronisasi penuh menyimpan data dan kursor', () async {
    await local.applyChanges(
      changes(
        fullSync: true,
        categories: [cat(1, 'Makanan'), cat(2, 'Minuman')],
        products: [
          prod(1, 'Nasi Goreng'),
          prod(2, 'Es Teh', categoryId: 2, price: 5000, stock: 3),
        ],
      ),
    );

    expect((await local.getCategories()).map((c) => c.name), [
      'Makanan',
      'Minuman',
    ]);
    final products = await local.getActiveProducts();
    expect(products.map((p) => p.name), ['Es Teh', 'Nasi Goreng']); // urut nama
    expect(products.first.price, 5000);
    expect(products.first.stock, 3);
    expect(await local.readLastSync(), '2026-10-09T10:05:00+00:00');
  });

  test('produk nonaktif disimpan tetapi tidak dikembalikan ke kasir', () async {
    await local.applyChanges(
      changes(
        fullSync: true,
        categories: [cat(1, 'Makanan')],
        products: [prod(1, 'Aktif'), prod(2, 'Nonaktif', active: false)],
      ),
    );

    expect((await local.getActiveProducts()).map((p) => p.name), ['Aktif']);
    expect(await appDb.db.query('products'), hasLength(2));
  });

  test(
    'sinkronisasi inkremental memperbarui baris yang ada dan menambah yang baru',
    () async {
      await local.applyChanges(
        changes(
          fullSync: true,
          categories: [cat(1, 'Makanan')],
          products: [prod(1, 'Nasi Goreng', price: 15000)],
        ),
      );

      await local.applyChanges(
        changes(
          serverTime: '2026-10-09T11:00:00+00:00',
          products: [prod(1, 'Nasi Goreng', price: 17000), prod(2, 'Mie Ayam')],
        ),
      );

      final products = await local.getActiveProducts();
      expect(products, hasLength(2));
      expect(products.firstWhere((p) => p.id == 1).price, 17000);
      expect(await local.readLastSync(), '2026-10-09T11:00:00+00:00');
    },
  );

  test('inkremental menghapus data yang dihapus di server', () async {
    await local.applyChanges(
      changes(
        fullSync: true,
        categories: [cat(1, 'Makanan'), cat(2, 'Minuman')],
        products: [prod(1, 'A'), prod(2, 'B', categoryId: 2)],
      ),
    );

    await local.applyChanges(
      changes(deletedCategoryIds: {2}, deletedProductIds: {2}),
    );

    expect((await local.getCategories()).map((c) => c.id), [1]);
    expect((await local.getActiveProducts()).map((p) => p.id), [1]);
  });

  test(
    'sinkronisasi penuh membuang data lokal yang sudah tidak ada di server',
    () async {
      await local.applyChanges(
        changes(
          fullSync: true,
          categories: [cat(1, 'Makanan'), cat(2, 'Lama')],
          products: [prod(1, 'A'), prod(2, 'Sudah dihapus')],
        ),
      );

      await local.applyChanges(
        changes(
          fullSync: true,
          categories: [cat(1, 'Makanan')],
          products: [prod(1, 'A')],
        ),
      );

      expect((await local.getCategories()).map((c) => c.id), [1]);
      expect((await local.getActiveProducts()).map((p) => p.id), [1]);
    },
  );

  test(
    'transaksi lokal TIDAK ikut terhapus saat produknya dihapus di server',
    () async {
      await local.applyChanges(
        changes(
          fullSync: true,
          categories: [cat(1, 'Makanan')],
          products: [prod(1, 'A')],
        ),
      );
      await insertTransaction('t1', 'synced', {1: 2});

      await local.applyChanges(changes(fullSync: true));

      expect(await appDb.db.query('transactions'), hasLength(1));
      final item = (await appDb.db.query('transaction_items')).single;
      expect(item['product_name'], 'x'); // snapshot utuh
    },
  );

  group('proyeksi stok', () {
    test(
      'mengurangi stok server dengan penjualan yang belum tersinkron',
      () async {
        await insertTransaction('p', 'pending', {1: 2});
        await insertTransaction('s', 'syncing', {1: 1});
        await insertTransaction('f', 'failed', {1: 3});

        await local.applyChanges(
          changes(
            fullSync: true,
            categories: [cat(1, 'Makanan')],
            products: [prod(1, 'A', stock: 10), prod(2, 'B', stock: 4)],
          ),
        );

        final products = {
          for (final p in await local.getActiveProducts()) p.id: p,
        };
        expect(products[1]!.stock, 4); // 10 - 2 - 1 - 3
        expect(products[2]!.stock, 4); // tidak ada penjualan tertunda
      },
    );

    test(
      'transaksi synced dan conflict tidak mengurangi stok server',
      () async {
        await insertTransaction('ok', 'synced', {1: 5});
        await insertTransaction('bad', 'conflict', {1: 4});

        await local.applyChanges(
          changes(
            fullSync: true,
            categories: [cat(1, 'Makanan')],
            products: [prod(1, 'A', stock: 10)],
          ),
        );

        expect((await local.getActiveProducts()).single.stock, 10);
      },
    );

    test('stok boleh negatif secara lokal; server yang memutuskan', () async {
      await insertTransaction('p', 'pending', {1: 8});

      await local.applyChanges(
        changes(
          fullSync: true,
          categories: [cat(1, 'Makanan')],
          products: [prod(1, 'A', stock: 2)],
        ),
      );

      expect((await local.getActiveProducts()).single.stock, -6);
    });
  });

  test(
    'gagal di tengah penerapan -> semua dibatalkan, kursor tidak maju',
    () async {
      await local.applyChanges(
        changes(
          fullSync: true,
          categories: [cat(1, 'Makanan')],
          products: [prod(1, 'Lama')],
        ),
      );

      // price negatif melanggar CHECK (price >= 0) pada baris kedua.
      await expectLater(
        local.applyChanges(
          changes(
            serverTime: '2026-10-09T12:00:00+00:00',
            products: [prod(1, 'Baru'), prod(2, 'Rusak', price: -1)],
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );

      final products = await local.getActiveProducts();
      expect(products.single.name, 'Lama');
      expect(await local.readLastSync(), '2026-10-09T10:05:00+00:00');
    },
  );
}
