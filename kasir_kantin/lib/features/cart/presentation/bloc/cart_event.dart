part of 'cart_bloc.dart';

sealed class CartEvent extends Equatable {
  const CartEvent();

  @override
  List<Object?> get props => [];
}

/// Produk diketuk di katalog: tambah satu.
final class CartProductAdded extends CartEvent {
  const CartProductAdded(this.product);

  final Product product;

  @override
  List<Object?> get props => [product];
}

final class CartQuantityIncremented extends CartEvent {
  const CartQuantityIncremented(this.productId);

  final int productId;

  @override
  List<Object?> get props => [productId];
}

/// Mengurangi satu; pada jumlah 1 baris dihapus.
final class CartQuantityDecremented extends CartEvent {
  const CartQuantityDecremented(this.productId);

  final int productId;

  @override
  List<Object?> get props => [productId];
}

final class CartItemRemoved extends CartEvent {
  const CartItemRemoved(this.productId);

  final int productId;

  @override
  List<Object?> get props => [productId];
}

final class CartCleared extends CartEvent {
  const CartCleared();
}

/// Katalog lokal berubah (mis. selesai sinkronisasi): samakan harga dan
/// stok isi keranjang dengan produk terbaru.
final class CartCatalogRefreshed extends CartEvent {
  const CartCatalogRefreshed(this.products);

  final List<Product> products;

  @override
  List<Object?> get props => [products];
}
