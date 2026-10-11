import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/cart/domain/cart_item.dart';
import 'package:kasir_kantin/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:kasir_kantin/features/cart/presentation/widgets/cart_sheet.dart';
import 'package:kasir_kantin/features/products/presentation/bloc/catalog_bloc.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_exception.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_line.dart';
import 'package:kasir_kantin/features/transactions/domain/local_transaction.dart';
import 'package:kasir_kantin/features/transactions/domain/payment_method.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:kasir_kantin/features/transactions/domain/transaction_repository.dart';
import 'package:kasir_kantin/features/transactions/presentation/bloc/checkout_bloc.dart';
import 'package:kasir_kantin/features/transactions/presentation/widgets/checkout_sheet.dart';
import 'package:mocktail/mocktail.dart';

class MockCartBloc extends MockBloc<CartEvent, CartState> implements CartBloc {}

class MockCatalogBloc extends MockBloc<CatalogEvent, CatalogState>
    implements CatalogBloc {}

class MockTransactionRepository extends Mock implements TransactionRepository {}

CartItem item(int id, String name, int price, int quantity) => CartItem(
  productId: id,
  name: name,
  price: price,
  quantity: quantity,
  availableStock: 10,
);

void main() {
  // Total = 2 x 10.000 + 1 x 5.000 = 25.000
  final filledCart = CartState(
    items: [item(1, 'Kopi Susu', 10000, 2), item(2, 'Es Teh', 5000, 1)],
  );

  final receipt = LocalTransaction(
    localUuid: 'uuid-1',
    invoiceNumber: 'INV-20261011-ABC123',
    totalAmount: 25000,
    paymentMethod: PaymentMethod.cash,
    syncStatus: SyncStatus.pending,
    createdAt: DateTime.utc(2026, 10, 11, 4),
    items: const [
      LocalTransactionItem(
        productId: 1,
        productName: 'Kopi Susu',
        quantity: 2,
        price: 10000,
      ),
      LocalTransactionItem(
        productId: 2,
        productName: 'Es Teh',
        quantity: 1,
        price: 5000,
      ),
    ],
  );

  const navBarHeight = 48.0;

  late MockCartBloc cart;
  late MockCatalogBloc catalog;
  late MockTransactionRepository repository;

  setUpAll(() {
    registerFallbackValue(const CartCleared());
    registerFallbackValue(const CatalogLocalReloaded());
    registerFallbackValue(<CheckoutLine>[]);
    registerFallbackValue(PaymentMethod.cash);
  });

  setUp(() {
    cart = MockCartBloc();
    catalog = MockCatalogBloc();
    repository = MockTransactionRepository();
    whenListen(
      catalog,
      const Stream<CatalogState>.empty(),
      initialState: const CatalogState(),
    );
  });

  void stubCreate(Future<LocalTransaction> Function() answer) {
    when(
      () => repository.createLocalTransaction(
        lines: any(named: 'lines'),
        paymentMethod: any(named: 'paymentMethod'),
      ),
    ).thenAnswer((_) => answer());
  }

  Widget providers({required Widget child}) => MultiBlocProvider(
    providers: [
      BlocProvider<CartBloc>.value(value: cart),
      BlocProvider<CatalogBloc>.value(value: catalog),
      BlocProvider<CheckoutBloc>(
        create: (_) => CheckoutBloc(repository: repository),
      ),
    ],
    child: child,
  );

  Future<void> pumpSheet(WidgetTester tester, [CartState? state]) async {
    whenListen(
      cart,
      const Stream<CartState>.empty(),
      initialState: state ?? filledCart,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          // Meniru ponsel dengan tombol navigasi di bawah.
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(bottom: navBarHeight)),
          child: child!,
        ),
        home: Material(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: providers(child: const CheckoutSheet()),
          ),
        ),
      ),
    );
  }

  Future<void> tapPay(WidgetTester tester) async {
    await tester.tap(find.text('Bayar Sekarang'));
    await tester.pumpAndSettle();
  }

  group('tampilan pembayaran', () {
    testWidgets('menampilkan total, metode, dan ringkasan', (tester) async {
      await pumpSheet(tester);

      expect(find.text('Total Pembayaran'), findsOneWidget);
      expect(find.text('Rp25.000'), findsOneWidget);
      expect(find.text('Metode Pembayaran'), findsOneWidget);
      expect(find.text('Tunai'), findsOneWidget);
      expect(find.text('QRIS'), findsOneWidget);
      expect(find.text('2 × Kopi Susu'), findsOneWidget);
      expect(find.text('Rp20.000'), findsOneWidget);
      expect(find.text('1 × Es Teh'), findsOneWidget);
      expect(find.text('Bayar Sekarang'), findsOneWidget);
    });

    testWidgets('memilih QRIS menampilkan pengingat pembayaran', (
      tester,
    ) async {
      await pumpSheet(tester);
      expect(find.textContaining('Pastikan pembayaran QRIS'), findsNothing);

      await tester.tap(find.text('QRIS'));
      await tester.pump();

      expect(find.textContaining('Pastikan pembayaran QRIS'), findsOneWidget);
    });

    testWidgets('tombol Bayar Sekarang tidak tertutup tombol navigasi', (
      tester,
    ) async {
      await pumpSheet(tester);

      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final bottom = tester.getBottomLeft(find.text('Bayar Sekarang')).dy;

      expect(bottom, lessThanOrEqualTo(screenHeight - navBarHeight));
    });

    testWidgets('keranjang kosong -> tidak bisa membayar', (tester) async {
      await pumpSheet(tester, const CartState());

      expect(find.text('Keranjang masih kosong'), findsOneWidget);
      expect(find.text('Bayar Sekarang'), findsNothing);
      expect(find.text('Kembali'), findsOneWidget);
    });
  });

  group('membayar', () {
    testWidgets('mengirim isi keranjang dan metode terpilih ke repository', (
      tester,
    ) async {
      stubCreate(() async => receipt);
      await pumpSheet(tester);

      await tester.tap(find.text('QRIS'));
      await tester.pump();
      await tapPay(tester);

      verify(
        () => repository.createLocalTransaction(
          lines: const [
            CheckoutLine(
              productId: 1,
              name: 'Kopi Susu',
              quantity: 2,
              expectedPrice: 10000,
            ),
            CheckoutLine(
              productId: 2,
              name: 'Es Teh',
              quantity: 1,
              expectedPrice: 5000,
            ),
          ],
          paymentMethod: PaymentMethod.qris,
        ),
      ).called(1);
    });

    testWidgets('berhasil -> "disimpan", "Belum tersinkron", rincian', (
      tester,
    ) async {
      stubCreate(() async => receipt);
      await pumpSheet(tester);

      await tapPay(tester);

      expect(find.text('Transaksi berhasil disimpan'), findsOneWidget);
      expect(find.text('Belum tersinkron'), findsOneWidget);
      expect(find.text('INV-20261011-ABC123'), findsOneWidget);
      expect(find.text('Rp25.000'), findsOneWidget);
      expect(find.text('Tunai'), findsOneWidget);
      expect(find.text('Selesai'), findsOneWidget);
      expect(find.text('Bayar Sekarang'), findsNothing);
      // Tidak ada kata "gagal" untuk transaksi yang sudah tersimpan.
      expect(find.textContaining('gagal'), findsNothing);
    });

    testWidgets('berhasil -> keranjang dikosongkan dan stok dibaca ulang', (
      tester,
    ) async {
      stubCreate(() async => receipt);
      await pumpSheet(tester);

      await tapPay(tester);

      verify(() => cart.add(const CartCleared())).called(1);
      verify(() => catalog.add(const CatalogLocalReloaded())).called(1);
    });

    testWidgets('ditolak -> pesan jelas, keranjang utuh, bisa mencoba lagi', (
      tester,
    ) async {
      stubCreate(
        () async =>
            throw CheckoutInsufficientStockException('Kopi Susu', available: 1),
      );
      await pumpSheet(tester);

      await tapPay(tester);

      expect(
        find.text(
          'Stok Kopi Susu tidak mencukupi (tersisa 1). '
          'Ubah jumlah di keranjang.',
        ),
        findsOneWidget,
      );
      expect(find.text('Bayar Sekarang'), findsOneWidget);
      verifyNever(() => cart.add(const CartCleared()));
      // Stok dibaca ulang agar keranjang menyesuaikan diri.
      verify(() => catalog.add(const CatalogLocalReloaded())).called(1);
    });

    testWidgets('saat menyimpan: tombol dan Tutup nonaktif, ada penanda', (
      tester,
    ) async {
      final completer = Completer<LocalTransaction>();
      stubCreate(() => completer.future);
      await pumpSheet(tester);

      await tester.tap(find.text('Bayar Sekarang'));
      await tester.pump();

      expect(find.text('Menyimpan...'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      final close = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.close),
      );
      expect(close.onPressed, isNull);

      completer.complete(receipt);
      await tester.pumpAndSettle();
      expect(find.text('Transaksi berhasil disimpan'), findsOneWidget);
    });
  });

  group('dari keranjang', () {
    late StreamController<CartState> cartStates;

    setUp(() => cartStates = StreamController<CartState>.broadcast());
    tearDown(() => cartStates.close());

    Future<void> pumpApp(WidgetTester tester) async {
      whenListen(cart, cartStates.stream, initialState: filledCart);
      // Seperti aplikasi: repository di atas MaterialApp, sedangkan BLoC
      // dipasang di bawah Navigator (AppShell), jadi rute sheet tidak
      // melihatnya kecuali diteruskan.
      await tester.pumpWidget(
        RepositoryProvider<TransactionRepository>.value(
          value: repository,
          child: MaterialApp(
            theme: AppTheme.light,
            home: MultiBlocProvider(
              providers: [
                BlocProvider<CartBloc>.value(value: cart),
                BlocProvider<CatalogBloc>.value(value: catalog),
              ],
              child: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showCartSheet(context),
                      child: const Text('Buka keranjang'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Buka keranjang'));
      await tester.pumpAndSettle();
    }

    testWidgets('Bayar membuka sheet pembayaran; Tutup kembali ke keranjang', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
      await tester.pumpAndSettle();
      expect(find.text('Total Pembayaran'), findsOneWidget);

      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();

      expect(find.text('Total Pembayaran'), findsNothing);
      expect(find.text('Keranjang'), findsOneWidget);
    });

    testWidgets('setelah sukses, Selesai menutup pembayaran dan keranjang', (
      tester,
    ) async {
      stubCreate(() async => receipt);
      await pumpApp(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
      await tester.pumpAndSettle();
      await tapPay(tester);
      // CartBloc sungguhan akan menjadi kosong setelah CartCleared.
      cartStates.add(const CartState());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Selesai'));
      await tester.pumpAndSettle();

      expect(find.text('Transaksi berhasil disimpan'), findsNothing);
      expect(find.text('Keranjang'), findsNothing);
      expect(find.text('Keranjang masih kosong'), findsNothing);
      expect(find.text('Buka keranjang'), findsOneWidget);
    });
  });
}
