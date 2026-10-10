import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/features/cart/domain/cart_item.dart';
import 'package:kasir_kantin/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:kasir_kantin/features/products/domain/product.dart';

Product prod(
  int id,
  String name, {
  int price = 10000,
  int stock = 10,
  bool active = true,
}) => Product(
  id: id,
  categoryId: 1,
  name: name,
  price: price,
  stock: stock,
  isActive: active,
  updatedAt: 't',
);

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
  final nasi = prod(1, 'Nasi Goreng', price: 15000);
  final teh = prod(2, 'Es Teh', price: 5000, stock: 3);

  test('keranjang awal kosong', () {
    final state = CartBloc().state;

    expect(state.isEmpty, isTrue);
    expect(state.totalAmount, 0);
    expect(state.totalQuantity, 0);
  });

  test('subtotal = harga x jumlah; total = jumlah semua subtotal', () {
    final state = CartState(
      items: [
        item(1, 'A', price: 15000, quantity: 2),
        item(2, 'B', price: 5000, quantity: 3),
      ],
    );

    expect(state.items.first.subtotal, 30000);
    expect(state.totalAmount, 45000);
    expect(state.totalQuantity, 5);
    expect(state.quantityOf(2), 3);
    expect(state.quantityOf(99), 0);
  });

  group('menambah produk', () {
    blocTest<CartBloc, CartState>(
      'produk baru masuk dengan jumlah 1 dan menyimpan nama, harga, stok',
      build: CartBloc.new,
      act: (bloc) => bloc.add(CartProductAdded(nasi)),
      expect: () => [
        CartState(items: [item(1, 'Nasi Goreng', price: 15000, stock: 10)]),
      ],
    );

    blocTest<CartBloc, CartState>(
      'produk yang sama menambah jumlah, bukan baris baru',
      build: CartBloc.new,
      act: (bloc) => bloc
        ..add(CartProductAdded(nasi))
        ..add(CartProductAdded(nasi)),
      verify: (bloc) {
        expect(bloc.state.items, hasLength(1));
        expect(bloc.state.quantityOf(1), 2);
      },
    );

    blocTest<CartBloc, CartState>(
      'urutan baris mengikuti urutan penambahan',
      build: CartBloc.new,
      act: (bloc) => bloc
        ..add(CartProductAdded(teh))
        ..add(CartProductAdded(nasi)),
      verify: (bloc) =>
          expect(bloc.state.items.map((i) => i.productId), [2, 1]),
    );

    blocTest<CartBloc, CartState>(
      'produk habis ditolak dengan pesan',
      build: CartBloc.new,
      act: (bloc) => bloc.add(CartProductAdded(prod(3, 'Batagor', stock: 0))),
      verify: (bloc) {
        expect(bloc.state.isEmpty, isTrue);
        expect(bloc.state.notice, 'Stok Batagor habis.');
        expect(bloc.state.noticeCount, 1);
      },
    );

    blocTest<CartBloc, CartState>(
      'produk nonaktif ditolak',
      build: CartBloc.new,
      act: (bloc) => bloc.add(CartProductAdded(prod(3, 'Lama', active: false))),
      verify: (bloc) => expect(bloc.state.isEmpty, isTrue),
    );
  });

  group('batas stok', () {
    blocTest<CartBloc, CartState>(
      'tidak melebihi stok saat produk diketuk berulang',
      build: CartBloc.new,
      act: (bloc) => bloc
        ..add(CartProductAdded(teh))
        ..add(CartProductAdded(teh))
        ..add(CartProductAdded(teh))
        ..add(CartProductAdded(teh)), // stok 3: yang keempat ditolak
      verify: (bloc) {
        expect(bloc.state.quantityOf(2), 3);
        expect(bloc.state.notice, 'Stok Es Teh hanya 3.');
      },
    );

    blocTest<CartBloc, CartState>(
      'increment melewati stok ditolak dengan pesan',
      build: CartBloc.new,
      seed: () => CartState(items: [item(2, 'Es Teh', quantity: 3, stock: 3)]),
      act: (bloc) => bloc.add(const CartQuantityIncremented(2)),
      verify: (bloc) {
        expect(bloc.state.quantityOf(2), 3);
        expect(bloc.state.noticeCount, 1);
      },
    );

    test('canIncrement hanya benar selama jumlah < stok', () {
      expect(item(1, 'A', quantity: 2, stock: 3).canIncrement, isTrue);
      expect(item(1, 'A', quantity: 3, stock: 3).canIncrement, isFalse);
    });
  });

  group('mengubah jumlah', () {
    blocTest<CartBloc, CartState>(
      'increment menambah satu',
      build: CartBloc.new,
      seed: () => CartState(items: [item(1, 'A', quantity: 1)]),
      act: (bloc) => bloc.add(const CartQuantityIncremented(1)),
      verify: (bloc) => expect(bloc.state.quantityOf(1), 2),
    );

    blocTest<CartBloc, CartState>(
      'decrement mengurangi satu',
      build: CartBloc.new,
      seed: () => CartState(items: [item(1, 'A', quantity: 3)]),
      act: (bloc) => bloc.add(const CartQuantityDecremented(1)),
      verify: (bloc) => expect(bloc.state.quantityOf(1), 2),
    );

    blocTest<CartBloc, CartState>(
      'decrement pada jumlah 1 menghapus baris (jumlah tidak pernah 0)',
      build: CartBloc.new,
      seed: () => CartState(items: [item(1, 'A', quantity: 1)]),
      act: (bloc) => bloc.add(const CartQuantityDecremented(1)),
      verify: (bloc) => expect(bloc.state.isEmpty, isTrue),
    );

    blocTest<CartBloc, CartState>(
      'produk yang tidak ada di keranjang diabaikan',
      build: CartBloc.new,
      seed: () => CartState(items: [item(1, 'A')]),
      act: (bloc) => bloc
        ..add(const CartQuantityIncremented(99))
        ..add(const CartQuantityDecremented(99))
        ..add(const CartItemRemoved(99)),
      expect: () => <CartState>[],
    );
  });

  group('menghapus', () {
    blocTest<CartBloc, CartState>(
      'CartItemRemoved menghapus satu baris saja',
      build: CartBloc.new,
      seed: () => CartState(items: [item(1, 'A', quantity: 4), item(2, 'B')]),
      act: (bloc) => bloc.add(const CartItemRemoved(1)),
      verify: (bloc) => expect(bloc.state.items.map((i) => i.productId), [2]),
    );

    blocTest<CartBloc, CartState>(
      'CartCleared mengosongkan keranjang',
      build: CartBloc.new,
      seed: () => CartState(items: [item(1, 'A'), item(2, 'B')]),
      act: (bloc) => bloc.add(const CartCleared()),
      verify: (bloc) => expect(bloc.state.isEmpty, isTrue),
    );

    blocTest<CartBloc, CartState>(
      'CartCleared pada keranjang kosong tidak menghasilkan state baru',
      build: CartBloc.new,
      act: (bloc) => bloc.add(const CartCleared()),
      expect: () => <CartState>[],
    );
  });

  group('menyelaraskan dengan katalog terbaru', () {
    blocTest<CartBloc, CartState>(
      'keranjang kosong -> tidak melakukan apa-apa',
      build: CartBloc.new,
      act: (bloc) => bloc.add(CartCatalogRefreshed([nasi])),
      expect: () => <CartState>[],
    );

    blocTest<CartBloc, CartState>(
      'tidak ada perubahan -> tidak ada state baru dan tanpa pesan',
      build: CartBloc.new,
      seed: () => CartState(
        items: [item(1, 'Nasi Goreng', price: 15000, quantity: 2, stock: 10)],
      ),
      act: (bloc) => bloc.add(CartCatalogRefreshed([nasi])),
      expect: () => <CartState>[],
    );

    blocTest<CartBloc, CartState>(
      'harga berubah -> harga baru dipakai dan kasir diberi tahu',
      build: CartBloc.new,
      seed: () =>
          CartState(items: [item(1, 'Nasi Goreng', price: 12000, quantity: 2)]),
      act: (bloc) => bloc.add(CartCatalogRefreshed([nasi])), // 15000
      verify: (bloc) {
        expect(bloc.state.items.single.price, 15000);
        expect(bloc.state.totalAmount, 30000);
        expect(
          bloc.state.notice,
          'Harga Nasi Goreng berubah menjadi Rp15.000.',
        );
      },
    );

    blocTest<CartBloc, CartState>(
      'stok turun di bawah jumlah -> jumlah disesuaikan',
      build: CartBloc.new,
      seed: () => CartState(
        items: [item(2, 'Es Teh', price: 5000, quantity: 5, stock: 10)],
      ),
      act: (bloc) => bloc.add(CartCatalogRefreshed([teh])), // stok 3
      verify: (bloc) {
        expect(bloc.state.quantityOf(2), 3);
        expect(bloc.state.items.single.availableStock, 3);
        expect(bloc.state.notice, 'Jumlah Es Teh disesuaikan dengan stok (3).');
      },
    );

    blocTest<CartBloc, CartState>(
      'produk habis -> dihapus dari keranjang',
      build: CartBloc.new,
      seed: () => CartState(items: [item(2, 'Es Teh', price: 5000)]),
      act: (bloc) =>
          bloc.add(CartCatalogRefreshed([prod(2, 'Es Teh', stock: 0)])),
      verify: (bloc) {
        expect(bloc.state.isEmpty, isTrue);
        expect(bloc.state.notice, 'Stok Es Teh habis; dihapus dari keranjang.');
      },
    );

    blocTest<CartBloc, CartState>(
      'produk tidak ada lagi di katalog (nonaktif/terhapus) -> dihapus',
      build: CartBloc.new,
      seed: () => CartState(items: [item(1, 'A'), item(2, 'B')]),
      act: (bloc) => bloc.add(CartCatalogRefreshed([prod(1, 'A')])),
      verify: (bloc) {
        expect(bloc.state.items.map((i) => i.productId), [1]);
        expect(
          bloc.state.notice,
          'B tidak lagi tersedia dan dihapus dari keranjang.',
        );
      },
    );

    blocTest<CartBloc, CartState>(
      'stok bertambah -> batas jumlah ikut naik tanpa pesan',
      build: CartBloc.new,
      seed: () => CartState(
        items: [item(1, 'Nasi Goreng', price: 15000, quantity: 3, stock: 3)],
      ),
      act: (bloc) => bloc.add(CartCatalogRefreshed([nasi])), // stok 10
      verify: (bloc) {
        expect(bloc.state.items.single.availableStock, 10);
        expect(bloc.state.items.single.canIncrement, isTrue);
        expect(bloc.state.noticeCount, 0);
      },
    );
  });
}
