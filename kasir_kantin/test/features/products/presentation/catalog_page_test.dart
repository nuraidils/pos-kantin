import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/cart/domain/cart_item.dart';
import 'package:kasir_kantin/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:kasir_kantin/features/cart/presentation/widgets/cart_bar.dart';
import 'package:kasir_kantin/features/products/domain/product.dart';
import 'package:kasir_kantin/features/products/domain/product_category.dart';
import 'package:kasir_kantin/features/products/presentation/bloc/catalog_bloc.dart';
import 'package:kasir_kantin/features/products/presentation/pages/catalog_page.dart';
import 'package:mocktail/mocktail.dart';

class MockCatalogBloc extends MockBloc<CatalogEvent, CatalogState>
    implements CatalogBloc {}

class MockCartBloc extends MockBloc<CartEvent, CartState> implements CartBloc {}

Product prod(
  int id,
  String name, {
  int categoryId = 1,
  int price = 10000,
  int stock = 10,
}) => Product(
  id: id,
  categoryId: categoryId,
  name: name,
  price: price,
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

  late MockCatalogBloc bloc;
  late MockCartBloc cartBloc;

  setUpAll(() {
    registerFallbackValue(const CatalogStarted());
    registerFallbackValue(const CartCleared());
  });

  setUp(() {
    bloc = MockCatalogBloc();
    cartBloc = MockCartBloc();
  });

  Future<void> pumpPage(
    WidgetTester tester,
    CatalogState state, {
    CartState cart = const CartState(),
  }) async {
    whenListen(bloc, const Stream<CatalogState>.empty(), initialState: state);
    whenListen(cartBloc, const Stream<CartState>.empty(), initialState: cart);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<CatalogBloc>.value(value: bloc),
              BlocProvider<CartBloc>.value(value: cartBloc),
            ],
            child: const CatalogPage(),
          ),
        ),
      ),
    );
  }

  CatalogState ready({
    List<Product>? products,
    List<ProductCategory> categories = const [makanan, minuman],
    bool isOffline = false,
    bool isSyncing = false,
    String? syncError,
    DateTime? lastSyncedAt,
  }) {
    return CatalogState(
      status: CatalogStatus.ready,
      categories: categories,
      products:
          products ??
          [
            prod(1, 'Nasi Goreng', price: 15000),
            prod(2, 'Es Teh Manis', categoryId: 2, price: 5000),
          ],
      isOffline: isOffline,
      isSyncing: isSyncing,
      syncError: syncError,
      lastSyncedAt: lastSyncedAt,
    );
  }

  testWidgets('memuat -> kerangka produk, bukan layar kosong', (tester) async {
    await pumpPage(tester, const CatalogState());

    expect(find.byKey(const ValueKey('product-skeleton')), findsWidgets);
    expect(find.text('Belum ada produk'), findsNothing);
  });

  testWidgets('menampilkan nama dan harga berformat rupiah', (tester) async {
    await pumpPage(tester, ready());

    expect(find.text('Kasir'), findsOneWidget);
    expect(find.text('Nasi Goreng'), findsOneWidget);
    expect(find.text('Rp15.000'), findsOneWidget);
    expect(find.text('Rp5.000'), findsOneWidget);
    expect(find.text('Stok 10'), findsNWidgets(2));
  });

  testWidgets('stok menipis dan habis ditandai dengan teks', (tester) async {
    await pumpPage(
      tester,
      ready(
        products: [
          prod(1, 'Kopi Susu', stock: 3),
          prod(2, 'Batagor', stock: 0),
        ],
      ),
    );

    expect(find.text('Stok tersisa 3'), findsOneWidget);
    expect(find.text('Habis'), findsOneWidget);
  });

  testWidgets(
    'belum ada produk sama sekali -> keadaan kosong dengan petunjuk',
    (tester) async {
      await pumpPage(tester, ready(products: const [], categories: const []));

      expect(find.text('Belum ada produk'), findsOneWidget);
      expect(find.text('Coba Lagi'), findsOneWidget);
    },
  );

  testWidgets('Coba Lagi pada keadaan kosong mengirim CatalogRefreshed', (
    tester,
  ) async {
    await pumpPage(tester, ready(products: const [], categories: const []));

    await tester.tap(find.text('Coba Lagi'));

    verify(() => bloc.add(const CatalogRefreshed())).called(1);
  });

  testWidgets('pencarian tanpa hasil -> "Produk tidak ditemukan"', (
    tester,
  ) async {
    await pumpPage(tester, ready().copyWith(query: 'zzz'));

    expect(find.text('Produk tidak ditemukan'), findsOneWidget);
  });

  testWidgets('mengetik di kolom cari mengirim CatalogSearchChanged', (
    tester,
  ) async {
    await pumpPage(tester, ready());

    await tester.enterText(find.byType(TextField), 'kopi');

    verify(() => bloc.add(const CatalogSearchChanged('kopi'))).called(1);
  });

  testWidgets('memilih chip kategori mengirim CatalogCategorySelected', (
    tester,
  ) async {
    await pumpPage(tester, ready());

    await tester.tap(find.text('Minuman'));
    await tester.pump();

    verify(() => bloc.add(const CatalogCategorySelected(2))).called(1);
  });

  testWidgets('"Semua" mengirim kategori null', (tester) async {
    await pumpPage(tester, ready().copyWith(selectedCategoryId: () => 2));

    await tester.tap(find.text('Semua'));
    await tester.pump();

    verify(() => bloc.add(const CatalogCategorySelected(null))).called(1);
  });

  testWidgets(
    'offline -> status tenang "Data lokal digunakan", produk tetap tampil',
    (tester) async {
      await pumpPage(tester, ready(isOffline: true));

      expect(find.text('Offline · Data lokal digunakan'), findsOneWidget);
      expect(find.text('Nasi Goreng'), findsOneWidget);
    },
  );

  testWidgets(
    'sedang sinkron -> "Menyinkronkan..." tanpa menyembunyikan produk',
    (tester) async {
      await pumpPage(tester, ready(isSyncing: true));

      expect(find.text('Menyinkronkan...'), findsOneWidget);
      expect(find.text('Nasi Goreng'), findsOneWidget);
    },
  );

  testWidgets(
    'galat server -> pesan + Coba Lagi yang mengirim CatalogRefreshed',
    (tester) async {
      await pumpPage(
        tester,
        ready(
          syncError: 'Terjadi masalah pada server. Coba lagi beberapa saat.',
        ),
      );

      expect(
        find.text('Terjadi masalah pada server. Coba lagi beberapa saat.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Coba Lagi'));

      verify(() => bloc.add(const CatalogRefreshed())).called(1);
    },
  );

  testWidgets(
    'SQLite gagal dibaca -> pesan dan Coba Lagi mengirim CatalogStarted',
    (tester) async {
      await pumpPage(
        tester,
        const CatalogState(
          status: CatalogStatus.failure,
          loadError: 'Data produk di perangkat tidak dapat dibaca. Coba lagi.',
        ),
      );

      expect(find.text('Produk tidak dapat dimuat'), findsOneWidget);

      await tester.tap(find.text('Coba Lagi'));

      verify(() => bloc.add(const CatalogStarted())).called(1);
    },
  );

  group('keranjang', () {
    testWidgets('mengetuk produk mengirim CartProductAdded', (tester) async {
      final nasi = prod(1, 'Nasi Goreng', price: 15000);
      await pumpPage(tester, ready(products: [nasi]));

      await tester.tap(find.text('Nasi Goreng'));

      verify(() => cartBloc.add(CartProductAdded(nasi))).called(1);
    });

    testWidgets('produk habis tidak mengirim apa pun saat diketuk', (
      tester,
    ) async {
      await pumpPage(tester, ready(products: [prod(1, 'Batagor', stock: 0)]));

      await tester.tap(find.text('Batagor'));

      verifyNever(() => cartBloc.add(any()));
    });

    testWidgets('keranjang kosong -> tidak ada bar keranjang', (tester) async {
      await pumpPage(tester, ready());

      expect(find.byType(CartBar), findsNothing);
    });

    testWidgets('keranjang berisi -> bar ringkasan dan lencana pada kartu', (
      tester,
    ) async {
      await pumpPage(
        tester,
        ready(),
        cart: const CartState(
          items: [
            CartItem(
              productId: 1,
              name: 'Nasi Goreng',
              price: 15000,
              quantity: 2,
              availableStock: 10,
            ),
          ],
        ),
      );

      expect(find.byType(CartBar), findsOneWidget);
      expect(find.text('2 item'), findsOneWidget);
      expect(find.text('Rp30.000'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // lencana jumlah pada kartu
    });
  });
}
