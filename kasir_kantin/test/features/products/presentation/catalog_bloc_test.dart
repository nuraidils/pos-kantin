import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/features/products/domain/catalog_repository.dart';
import 'package:kasir_kantin/features/products/domain/catalog_snapshot.dart';
import 'package:kasir_kantin/features/products/domain/product.dart';
import 'package:kasir_kantin/features/products/domain/product_category.dart';
import 'package:kasir_kantin/features/products/presentation/bloc/catalog_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockCatalogRepository extends Mock implements CatalogRepository {}

Product prod(int id, String name, {int categoryId = 1, int stock = 10}) =>
    Product(
      id: id,
      categoryId: categoryId,
      name: name,
      price: 10000,
      stock: stock,
      isActive: true,
      updatedAt: 't',
    );

void main() {
  const makanan = ProductCategory(
    id: 1,
    name: 'Makanan',
    slug: 'makanan',
    updatedAt: 't',
  );
  const minuman = ProductCategory(
    id: 2,
    name: 'Minuman',
    slug: 'minuman',
    updatedAt: 't',
  );
  final nasi = prod(1, 'Nasi Goreng');
  final teh = prod(2, 'Es Teh Manis', categoryId: 2);
  final kopi = prod(3, 'Kopi Susu', categoryId: 2);

  final local = CatalogSnapshot(
    categories: const [makanan, minuman],
    products: [nasi, teh],
  );
  final synced = CatalogSnapshot(
    categories: const [makanan, minuman],
    products: [nasi, teh, kopi],
    lastSyncedAt: DateTime(2026, 10, 9, 17, 5),
  );

  late MockCatalogRepository repository;

  setUp(() => repository = MockCatalogRepository());

  CatalogBloc build() => CatalogBloc(repository: repository);

  test('state awal: memuat, belum sinkron, tanpa filter', () {
    final state = build().state;

    expect(state.status, CatalogStatus.loading);
    expect(state.isSyncing, isFalse);
    expect(state.products, isEmpty);
    expect(state.selectedCategoryId, isNull);
  });

  group('CatalogStarted', () {
    blocTest<CatalogBloc, CatalogState>(
      'data lokal tampil dulu, baru sinkronisasi di belakang',
      build: () {
        when(() => repository.loadLocal()).thenAnswer((_) async => local);
        when(() => repository.sync()).thenAnswer((_) async => synced);
        return build();
      },
      act: (bloc) => bloc.add(const CatalogStarted()),
      expect: () => [
        isA<CatalogState>()
            .having((s) => s.status, 'status', CatalogStatus.ready)
            .having((s) => s.products, 'products', [nasi, teh])
            .having((s) => s.isSyncing, 'isSyncing', false),
        isA<CatalogState>().having((s) => s.isSyncing, 'isSyncing', true),
        isA<CatalogState>()
            .having((s) => s.isSyncing, 'isSyncing', false)
            .having((s) => s.products, 'products', [nasi, teh, kopi])
            .having(
              (s) => s.lastSyncedAt,
              'lastSyncedAt',
              DateTime(2026, 10, 9, 17, 5),
            )
            .having((s) => s.isOffline, 'isOffline', false),
      ],
    );

    blocTest<CatalogBloc, CatalogState>(
      'tanpa internet -> data lokal tetap, status offline, TANPA pesan galat',
      build: () {
        when(() => repository.loadLocal()).thenAnswer((_) async => local);
        when(() => repository.sync()).thenThrow(const NetworkException());
        return build();
      },
      act: (bloc) => bloc.add(const CatalogStarted()),
      verify: (bloc) {
        expect(bloc.state.status, CatalogStatus.ready);
        expect(bloc.state.products, [nasi, teh]);
        expect(bloc.state.isOffline, isTrue);
        expect(bloc.state.isSyncing, isFalse);
        expect(bloc.state.syncError, isNull);
      },
    );

    blocTest<CatalogBloc, CatalogState>(
      'server bermasalah -> pesan galat dengan data lokal tetap tampil',
      build: () {
        when(() => repository.loadLocal()).thenAnswer((_) async => local);
        when(() => repository.sync()).thenThrow(const ServerException());
        return build();
      },
      act: (bloc) => bloc.add(const CatalogStarted()),
      verify: (bloc) {
        expect(bloc.state.products, [nasi, teh]);
        expect(bloc.state.isOffline, isFalse);
        expect(
          bloc.state.syncError,
          'Terjadi masalah pada server. Coba lagi beberapa saat.',
        );
      },
    );

    blocTest<CatalogBloc, CatalogState>(
      '401 -> tidak menampilkan galat (AuthBloc yang mengakhiri sesi)',
      build: () {
        when(() => repository.loadLocal()).thenAnswer((_) async => local);
        when(() => repository.sync()).thenThrow(const UnauthorizedException());
        return build();
      },
      act: (bloc) => bloc.add(const CatalogStarted()),
      verify: (bloc) {
        expect(bloc.state.syncError, isNull);
        expect(bloc.state.isOffline, isFalse);
        expect(bloc.state.isSyncing, isFalse);
      },
    );

    blocTest<CatalogBloc, CatalogState>(
      'galat tak terduga saat sinkronisasi tidak membuat macet di "menyinkronkan"',
      build: () {
        when(() => repository.loadLocal()).thenAnswer((_) async => local);
        when(() => repository.sync()).thenThrow(StateError('bug'));
        return build();
      },
      act: (bloc) => bloc.add(const CatalogStarted()),
      verify: (bloc) {
        expect(bloc.state.isSyncing, isFalse);
        expect(bloc.state.syncError, isNotNull);
      },
    );

    blocTest<CatalogBloc, CatalogState>(
      'SQLite tidak terbaca -> status failure dan sinkronisasi tidak dijalankan',
      build: () {
        when(() => repository.loadLocal()).thenThrow(StateError('db'));
        return build();
      },
      act: (bloc) => bloc.add(const CatalogStarted()),
      verify: (bloc) {
        expect(bloc.state.status, CatalogStatus.failure);
        expect(bloc.state.loadError, isNotNull);
        verifyNever(() => repository.sync());
      },
    );
  });

  group('CatalogRefreshed', () {
    blocTest<CatalogBloc, CatalogState>(
      'tarik-perbarui menarik katalog dan memperbarui produk',
      build: () {
        when(() => repository.sync()).thenAnswer((_) async => synced);
        return build();
      },
      act: (bloc) => bloc.add(const CatalogRefreshed()),
      verify: (bloc) {
        expect(bloc.state.products, [nasi, teh, kopi]);
        verify(() => repository.sync()).called(1);
      },
    );

    blocTest<CatalogBloc, CatalogState>(
      'sinkronisasi ganda diabaikan saat masih berjalan',
      build: () {
        when(() => repository.sync()).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return synced;
        });
        return build();
      },
      act: (bloc) => bloc
        ..add(const CatalogRefreshed())
        ..add(const CatalogRefreshed()),
      wait: const Duration(milliseconds: 80),
      verify: (_) => verify(() => repository.sync()).called(1),
    );

    blocTest<CatalogBloc, CatalogState>(
      'berhasil setelah offline -> status offline dihapus',
      build: () {
        when(() => repository.sync()).thenAnswer((_) async => synced);
        return build();
      },
      seed: () =>
          const CatalogState(status: CatalogStatus.ready, isOffline: true),
      act: (bloc) => bloc.add(const CatalogRefreshed()),
      verify: (bloc) => expect(bloc.state.isOffline, isFalse),
    );
  });

  group('filter', () {
    final ready = CatalogState(
      status: CatalogStatus.ready,
      categories: const [makanan, minuman],
      products: [nasi, teh, kopi],
    );

    test('pencarian tidak peka huruf besar/kecil dan memangkas spasi', () {
      final state = ready.copyWith(query: '  KOPI ');

      expect(state.visibleProducts, [kopi]);
    });

    test('kategori menyaring produk', () {
      final state = ready.copyWith(selectedCategoryId: () => 2);

      expect(state.visibleProducts, [teh, kopi]);
    });

    test('kategori + pencarian digabung', () {
      final state = ready.copyWith(selectedCategoryId: () => 2, query: 'teh');

      expect(state.visibleProducts, [teh]);
    });

    test('kategori tanpa produk aktif tidak ditampilkan sebagai chip', () {
      final state = ready.copyWith(products: [nasi]);

      expect(state.categoriesWithProducts, [makanan]);
    });

    blocTest<CatalogBloc, CatalogState>(
      'CatalogSearchChanged dan CatalogCategorySelected mengubah filter',
      build: build,
      seed: () => ready,
      act: (bloc) => bloc
        ..add(const CatalogSearchChanged('es'))
        ..add(const CatalogCategorySelected(2)),
      verify: (bloc) {
        expect(bloc.state.query, 'es');
        expect(bloc.state.selectedCategoryId, 2);
        expect(bloc.state.visibleProducts, [teh]);
      },
    );

    blocTest<CatalogBloc, CatalogState>(
      'kembali ke "Semua" memakai kategori null',
      build: build,
      seed: () => ready.copyWith(selectedCategoryId: () => 2),
      act: (bloc) => bloc.add(const CatalogCategorySelected(null)),
      verify: (bloc) => expect(bloc.state.selectedCategoryId, isNull),
    );

    blocTest<CatalogBloc, CatalogState>(
      'kategori terpilih yang produknya hilang setelah sinkronisasi dikembalikan ke "Semua"',
      build: () {
        when(() => repository.sync()).thenAnswer(
          (_) async =>
              CatalogSnapshot(categories: const [makanan], products: [nasi]),
        );
        return build();
      },
      seed: () => ready.copyWith(selectedCategoryId: () => 2),
      act: (bloc) => bloc.add(const CatalogRefreshed()),
      verify: (bloc) {
        expect(bloc.state.selectedCategoryId, isNull);
        expect(bloc.state.visibleProducts, [nasi]);
      },
    );
  });
  group('CatalogLocalReloaded', () {
    blocTest<CatalogBloc, CatalogState>(
      'membaca ulang SQLite (stok baru) tanpa menyentuh server',
      build: () {
        when(() => repository.loadLocal()).thenAnswer(
          (_) async => CatalogSnapshot(
            categories: const [makanan, minuman],
            products: [prod(1, 'Nasi Goreng', stock: 7), teh],
          ),
        );
        return build();
      },
      act: (bloc) => bloc.add(const CatalogLocalReloaded()),
      expect: () => [
        isA<CatalogState>()
            .having((s) => s.status, 'status', CatalogStatus.ready)
            .having((s) => s.products.first.stock, 'stok', 7)
            .having((s) => s.isSyncing, 'isSyncing', false),
      ],
      verify: (_) => verifyNever(() => repository.sync()),
    );

    blocTest<CatalogBloc, CatalogState>(
      'gagal membaca -> tampilan lama dipertahankan, tanpa galat',
      build: () {
        when(() => repository.loadLocal()).thenThrow(Exception('sqlite'));
        return build();
      },
      seed: () => CatalogState(
        status: CatalogStatus.ready,
        categories: const [makanan],
        products: [nasi],
      ),
      act: (bloc) => bloc.add(const CatalogLocalReloaded()),
      expect: () => <CatalogState>[],
    );
  });
}
