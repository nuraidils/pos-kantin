import 'package:equatable/equatable.dart';

import 'product.dart';
import 'product_category.dart';

/// Hasil satu kali tarik katalog dari server.
///
/// Data yang `deleted_at`-nya terisi dipisahkan menjadi `deleted*Ids` agar
/// lapisan lokal cukup menghapus, tanpa perlu tahu format API.
class CatalogChanges extends Equatable {
  const CatalogChanges({
    required this.categories,
    required this.products,
    required this.deletedCategoryIds,
    required this.deletedProductIds,
    required this.serverTime,
    required this.fullSync,
  });

  final List<ProductCategory> categories;
  final List<Product> products;
  final Set<int> deletedCategoryIds;
  final Set<int> deletedProductIds;

  /// `meta.server_time` apa adanya; disimpan dan dikirim kembali sebagai
  /// `updated_since` berikutnya (tanpa di-parse agar zona waktu tidak berubah).
  final String serverTime;

  /// true = respons berisi SELURUH katalog aktif; data lokal yang tidak ada
  /// di dalamnya harus dibuang.
  final bool fullSync;

  @override
  List<Object?> get props => [
    categories,
    products,
    deletedCategoryIds,
    deletedProductIds,
    serverTime,
    fullSync,
  ];
}
