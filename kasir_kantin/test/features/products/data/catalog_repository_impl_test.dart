import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/features/products/data/catalog_local_data_source.dart';
import 'package:kasir_kantin/features/products/data/catalog_remote_data_source.dart';
import 'package:kasir_kantin/features/products/data/catalog_repository_impl.dart';
import 'package:kasir_kantin/features/products/domain/catalog_changes.dart';
import 'package:kasir_kantin/features/products/domain/product.dart';
import 'package:kasir_kantin/features/products/domain/product_category.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements CatalogRemoteDataSource {}

class MockLocal extends Mock implements CatalogLocalDataSource {}

void main() {
  const category = ProductCategory(
    id: 1,
    name: 'Makanan',
    slug: 'makanan',
    updatedAt: 't',
  );
  const product = Product(
    id: 1,
    categoryId: 1,
    name: 'Nasi Goreng',
    price: 15000,
    stock: 9,
    isActive: true,
    updatedAt: 't',
  );
  const changes = CatalogChanges(
    categories: [category],
    products: [product],
    deletedCategoryIds: {},
    deletedProductIds: {},
    serverTime: '2026-10-09T10:05:00+00:00',
    fullSync: true,
  );

  late MockRemote remote;
  late MockLocal local;
  late CatalogRepositoryImpl repository;

  setUpAll(() => registerFallbackValue(changes));

  setUp(() {
    remote = MockRemote();
    local = MockLocal();
    repository = CatalogRepositoryImpl(remote: remote, local: local);

    when(() => local.getCategories()).thenAnswer((_) async => [category]);
    when(() => local.getActiveProducts()).thenAnswer((_) async => [product]);
    when(() => local.applyChanges(any())).thenAnswer((_) async {});
  });

  test('loadLocal membaca SQLite saja, tanpa menyentuh server', () async {
    when(
      () => local.readLastSync(),
    ).thenAnswer((_) async => '2026-10-09T10:05:00+00:00');

    final snapshot = await repository.loadLocal();

    expect(snapshot.categories, [category]);
    expect(snapshot.products, [product]);
    // Dibandingkan sebagai satu momen: hasilnya waktu lokal, bukan UTC.
    expect(
      snapshot.lastSyncedAt!.isAtSameMomentAs(
        DateTime.parse('2026-10-09T10:05:00+00:00'),
      ),
      isTrue,
    );
    verifyZeroInteractions(remote);
  });

  test('loadLocal: belum pernah sinkron -> lastSyncedAt null', () async {
    when(() => local.readLastSync()).thenAnswer((_) async => null);

    expect((await repository.loadLocal()).lastSyncedAt, isNull);
  });

  test(
    'sync pertama: tanpa kursor (penuh), menerapkan hasil, lalu membaca lokal',
    () async {
      when(() => local.readLastSync()).thenAnswer((_) async => null);
      when(
        () => remote.fetch(updatedSince: any(named: 'updatedSince')),
      ).thenAnswer((_) async => changes);

      final snapshot = await repository.sync();

      verify(() => remote.fetch(updatedSince: null)).called(1);
      verify(() => local.applyChanges(changes)).called(1);
      expect(snapshot.products, [product]);
    },
  );

  test(
    'sync berikutnya memakai kursor tersimpan sebagai updated_since',
    () async {
      when(
        () => local.readLastSync(),
      ).thenAnswer((_) async => '2026-10-09T10:05:00+00:00');
      when(
        () => remote.fetch(updatedSince: any(named: 'updatedSince')),
      ).thenAnswer((_) async => changes);

      await repository.sync();

      verify(
        () => remote.fetch(updatedSince: '2026-10-09T10:05:00+00:00'),
      ).called(1);
    },
  );

  test('server gagal -> exception naik dan SQLite tidak diubah', () async {
    when(() => local.readLastSync()).thenAnswer((_) async => null);
    when(
      () => remote.fetch(updatedSince: any(named: 'updatedSince')),
    ).thenThrow(const NetworkException());

    await expectLater(repository.sync(), throwsA(isA<NetworkException>()));

    verifyNever(() => local.applyChanges(any()));
  });
}
