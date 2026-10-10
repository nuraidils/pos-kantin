import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/cart/domain/cart_item.dart';
import 'package:kasir_kantin/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:kasir_kantin/features/cart/presentation/widgets/cart_bar.dart';
import 'package:kasir_kantin/features/cart/presentation/widgets/cart_sheet.dart';
import 'package:kasir_kantin/features/cart/presentation/widgets/quantity_control.dart';
import 'package:mocktail/mocktail.dart';

class MockCartBloc extends MockBloc<CartEvent, CartState> implements CartBloc {}

CartItem item(
  int id,
  String name, {
  int price = 10000,
  int quantity = 1,
  int stock = 10,
}) => CartItem(
  productId: id,
  name: name,
  price: price,
  quantity: quantity,
  availableStock: stock,
);

void main() {
  late MockCartBloc bloc;

  setUpAll(() => registerFallbackValue(const CartCleared()));
  setUp(() => bloc = MockCartBloc());

  Future<void> pumpSheet(WidgetTester tester, CartState state) async {
    whenListen(bloc, const Stream<CartState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BlocProvider<CartBloc>.value(
            value: bloc,
            // Tinggi dibatasi seperti pada bottom sheet sungguhan.
            child: const SizedBox(height: 600, child: CartSheet()),
          ),
        ),
      ),
    );
  }

  group('QuantityControl', () {
    testWidgets('menampilkan jumlah dan memanggil callback', (tester) async {
      var plus = 0;
      var minus = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuantityControl(
              quantity: 2,
              onDecrement: () => minus++,
              onIncrement: () => plus++,
            ),
          ),
        ),
      );

      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.byTooltip('Tambah jumlah'));
      await tester.tap(find.byTooltip('Kurangi jumlah'));

      expect(plus, 1);
      expect(minus, 1);
    });

    testWidgets('tombol + nonaktif saat onIncrement null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuantityControl(
              quantity: 3,
              onDecrement: () {},
              onIncrement: null,
            ),
          ),
        ),
      );

      final plus = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(plus.onPressed, isNull);
    });

    testWidgets('target sentuh minimal 44x44', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuantityControl(
              quantity: 1,
              onDecrement: () {},
              onIncrement: () {},
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byTooltip('Tambah jumlah'));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('CartBar', () {
    testWidgets('menampilkan jumlah item dan total, dapat diketuk', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CartBar(
              totalQuantity: 3,
              totalAmount: 46000,
              onTap: () => tapped++,
            ),
          ),
        ),
      );

      expect(find.text('Keranjang'), findsOneWidget);
      expect(find.text('3 item'), findsOneWidget);
      expect(find.text('Rp46.000'), findsOneWidget);

      await tester.tap(find.byType(CartBar));
      expect(tapped, 1);
    });
  });

  group('CartSheet', () {
    testWidgets('keranjang kosong -> keadaan kosong dengan petunjuk', (
      tester,
    ) async {
      await pumpSheet(tester, const CartState());

      expect(find.text('Keranjang masih kosong'), findsOneWidget);
      expect(
        find.text('Tambahkan produk untuk mulai transaksi.'),
        findsOneWidget,
      );
    });

    testWidgets('menampilkan nama, harga satuan, jumlah, subtotal, total', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        CartState(
          items: [
            item(1, 'Kopi Susu', price: 10000, quantity: 2),
            item(2, 'Es Teh', price: 5000, quantity: 1),
          ],
        ),
      );

      expect(find.text('Kopi Susu'), findsOneWidget);
      expect(find.text('Rp10.000'), findsOneWidget); // harga satuan Kopi
      expect(find.text('Rp20.000'), findsOneWidget); // subtotal Kopi
      expect(
        find.text('Rp5.000'),
        findsNWidgets(2),
      ); // satuan + subtotal Es Teh
      expect(find.text('Total (3 item)'), findsOneWidget);
      expect(find.text('Rp25.000'), findsOneWidget);
    });

    testWidgets('+ dan - mengirim event yang sesuai', (tester) async {
      await pumpSheet(tester, CartState(items: [item(1, 'Kopi Susu')]));

      await tester.tap(find.byTooltip('Tambah jumlah'));
      await tester.tap(find.byTooltip('Kurangi jumlah'));

      verify(() => bloc.add(const CartQuantityIncremented(1))).called(1);
      verify(() => bloc.add(const CartQuantityDecremented(1))).called(1);
    });

    testWidgets('di batas stok: + nonaktif dan ada penjelasan', (tester) async {
      await pumpSheet(
        tester,
        CartState(items: [item(1, 'Kopi Susu', quantity: 3, stock: 3)]),
      );

      final plus = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(plus.onPressed, isNull);
      expect(find.text('Mencapai batas stok (3)'), findsOneWidget);
    });

    testWidgets('ikon hapus mengirim CartItemRemoved', (tester) async {
      await pumpSheet(tester, CartState(items: [item(1, 'Kopi Susu')]));

      await tester.tap(find.byTooltip('Hapus dari keranjang'));

      verify(() => bloc.add(const CartItemRemoved(1))).called(1);
    });

    testWidgets('Kosongkan -> konfirmasi -> CartCleared', (tester) async {
      await pumpSheet(tester, CartState(items: [item(1, 'Kopi Susu')]));

      await tester.tap(find.text('Kosongkan'));
      await tester.pumpAndSettle();
      expect(find.text('Kosongkan keranjang?'), findsOneWidget);
      verifyNever(() => bloc.add(any()));

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Kosongkan'),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => bloc.add(const CartCleared())).called(1);
    });

    testWidgets('Batal pada konfirmasi tidak mengosongkan', (tester) async {
      await pumpSheet(tester, CartState(items: [item(1, 'Kopi Susu')]));

      await tester.tap(find.text('Kosongkan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      verifyNever(() => bloc.add(any()));
    });
  });
}
