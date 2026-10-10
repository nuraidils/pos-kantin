part of 'cart_bloc.dart';

class CartState extends Equatable {
  const CartState({this.items = const [], this.notice, this.noticeCount = 0});

  final List<CartItem> items;

  /// Pesan singkat untuk kasir (mis. batas stok tercapai). [noticeCount]
  /// naik setiap ada pesan baru agar pesan yang sama bisa tampil lagi.
  final String? notice;
  final int noticeCount;

  bool get isEmpty => items.isEmpty;

  /// Jumlah seluruh unit (bukan jumlah baris).
  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  int get totalAmount => items.fold(0, (sum, item) => sum + item.subtotal);

  int quantityOf(int productId) {
    for (final item in items) {
      if (item.productId == productId) return item.quantity;
    }
    return 0;
  }

  CartState copyWith({List<CartItem>? items, String? notice}) {
    return CartState(
      items: items ?? this.items,
      notice: notice ?? this.notice,
      noticeCount: notice == null ? noticeCount : noticeCount + 1,
    );
  }

  @override
  List<Object?> get props => [items, notice, noticeCount];
}
