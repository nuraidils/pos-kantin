import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../products/domain/product.dart';
import '../../domain/cart_item.dart';

part 'cart_event.dart';
part 'cart_state.dart';

/// Keranjang kasir. Hanya di memori: tidak ada repository karena belum ada
/// yang perlu disimpan atau diambil dari luar (AGENTS.md Rule 9). Transaksi
/// lokal dibuat di tahap 10.
class CartBloc extends Bloc<CartEvent, CartState> {
  CartBloc() : super(const CartState()) {
    on<CartProductAdded>(_onProductAdded);
    on<CartQuantityIncremented>(_onIncremented);
    on<CartQuantityDecremented>(_onDecremented);
    on<CartItemRemoved>(_onRemoved);
    on<CartCleared>(_onCleared);
    on<CartCatalogRefreshed>(_onCatalogRefreshed);
  }

  void _onProductAdded(CartProductAdded event, Emitter<CartState> emit) {
    final product = event.product;

    if (!product.isSellable) {
      emit(state.copyWith(notice: 'Stok ${product.name} habis.'));
      return;
    }

    final index = _indexOf(product.id);
    if (index == -1) {
      emit(
        state.copyWith(
          items: [
            ...state.items,
            CartItem(
              productId: product.id,
              name: product.name,
              price: product.price,
              quantity: 1,
              availableStock: product.stock,
            ),
          ],
        ),
      );
      return;
    }

    // Produk sudah ada: segarkan nama/harga/stok dari data terbaru, lalu
    // tambah satu bila stok masih cukup.
    final item = state.items[index].copyWith(
      name: product.name,
      price: product.price,
      availableStock: product.stock,
    );
    if (!item.canIncrement) {
      emit(
        state.copyWith(
          items: _replaced(index, item),
          notice: 'Stok ${product.name} hanya ${product.stock}.',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        items: _replaced(index, item.copyWith(quantity: item.quantity + 1)),
      ),
    );
  }

  void _onIncremented(CartQuantityIncremented event, Emitter<CartState> emit) {
    final index = _indexOf(event.productId);
    if (index == -1) return;

    final item = state.items[index];
    if (!item.canIncrement) {
      emit(
        state.copyWith(
          notice: 'Stok ${item.name} hanya ${item.availableStock}.',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        items: _replaced(index, item.copyWith(quantity: item.quantity + 1)),
      ),
    );
  }

  void _onDecremented(CartQuantityDecremented event, Emitter<CartState> emit) {
    final index = _indexOf(event.productId);
    if (index == -1) return;

    final item = state.items[index];
    if (item.quantity <= 1) {
      emit(state.copyWith(items: _without(index)));
      return;
    }
    emit(
      state.copyWith(
        items: _replaced(index, item.copyWith(quantity: item.quantity - 1)),
      ),
    );
  }

  void _onRemoved(CartItemRemoved event, Emitter<CartState> emit) {
    final index = _indexOf(event.productId);
    if (index == -1) return;
    emit(state.copyWith(items: _without(index)));
  }

  void _onCleared(CartCleared event, Emitter<CartState> emit) {
    if (state.isEmpty) return;
    emit(state.copyWith(items: const []));
  }

  void _onCatalogRefreshed(
    CartCatalogRefreshed event,
    Emitter<CartState> emit,
  ) {
    if (state.isEmpty) return;

    final byId = {for (final p in event.products) p.id: p};
    final items = <CartItem>[];
    final notices = <String>[];

    for (final item in state.items) {
      final product = byId[item.productId];

      if (product == null) {
        // Nonaktif atau terhapus di server.
        notices.add(
          '${item.name} tidak lagi tersedia dan dihapus dari keranjang.',
        );
        continue;
      }
      if (product.isOutOfStock) {
        notices.add('Stok ${product.name} habis; dihapus dari keranjang.');
        continue;
      }

      var updated = item.copyWith(
        name: product.name,
        price: product.price,
        availableStock: product.stock,
      );
      if (updated.quantity > product.stock) {
        updated = updated.copyWith(quantity: product.stock);
        notices.add(
          'Jumlah ${product.name} disesuaikan dengan stok (${product.stock}).',
        );
      }
      if (item.price != product.price) {
        notices.add(
          'Harga ${product.name} berubah menjadi ${formatRupiah(product.price)}.',
        );
      }
      items.add(updated);
    }

    final next = state.copyWith(
      items: items,
      notice: notices.isEmpty ? null : notices.join('\n'),
    );
    emit(next);
  }

  int _indexOf(int productId) =>
      state.items.indexWhere((item) => item.productId == productId);

  List<CartItem> _replaced(int index, CartItem item) => [
    for (var i = 0; i < state.items.length; i++)
      i == index ? item : state.items[i],
  ];

  List<CartItem> _without(int index) => [
    for (var i = 0; i < state.items.length; i++)
      if (i != index) state.items[i],
  ];
}
