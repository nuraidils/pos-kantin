import 'package:equatable/equatable.dart';

import 'product.dart';
import 'product_category.dart';

/// Isi katalog lokal yang siap ditampilkan: hanya produk aktif.
class CatalogSnapshot extends Equatable {
  const CatalogSnapshot({
    required this.categories,
    required this.products,
    this.lastSyncedAt,
  });

  final List<ProductCategory> categories;
  final List<Product> products;

  /// Waktu server pada sinkronisasi terakhir yang berhasil; null = belum pernah.
  final DateTime? lastSyncedAt;

  @override
  List<Object?> get props => [categories, products, lastSyncedAt];
}
