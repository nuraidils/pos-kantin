import 'package:equatable/equatable.dart';

/// Produk di katalog lokal. [stock] adalah PROYEKSI stok di perangkat
/// (stok server dikurangi penjualan yang belum tersinkron), bukan stok
/// otoritatif (AGENTS.md §13).
class Product extends Equatable {
  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    required this.stock,
    required this.isActive,
    required this.updatedAt,
    this.imageUrl,
  });

  /// Batas "stok menipis" pada kartu produk (DESIGN.md §15).
  static const lowStockThreshold = 5;

  final int id;
  final int categoryId;
  final String name;
  final int price;
  final int stock;
  final bool isActive;
  final String? imageUrl;
  final String updatedAt;

  bool get isOutOfStock => stock <= 0;
  bool get isLowStock => stock > 0 && stock <= lowStockThreshold;

  /// Boleh dimasukkan ke keranjang (dipakai tahap 9).
  bool get isSellable => isActive && !isOutOfStock;

  @override
  List<Object?> get props => [
    id,
    categoryId,
    name,
    price,
    stock,
    isActive,
    imageUrl,
    updatedAt,
  ];
}
