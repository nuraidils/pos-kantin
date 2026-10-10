import 'package:equatable/equatable.dart';

/// Satu baris keranjang (AGENTS.md §19): identitas produk, nama, harga
/// satuan, jumlah. [availableStock] adalah stok lokal yang diketahui saat
/// produk terakhir ditambahkan/disegarkan, dipakai sebagai batas jumlah.
class CartItem extends Equatable {
  const CartItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.availableStock,
  });

  final int productId;
  final String name;
  final int price;
  final int quantity;
  final int availableStock;

  int get subtotal => price * quantity;

  bool get canIncrement => quantity < availableStock;

  CartItem copyWith({
    String? name,
    int? price,
    int? quantity,
    int? availableStock,
  }) {
    return CartItem(
      productId: productId,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      availableStock: availableStock ?? this.availableStock,
    );
  }

  @override
  List<Object?> get props => [productId, name, price, quantity, availableStock];
}
