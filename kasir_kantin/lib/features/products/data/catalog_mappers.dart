import '../domain/product.dart';
import '../domain/product_category.dart';

// Pemetaan antara tiga bentuk data: JSON API, baris SQLite, dan entitas domain.

ProductCategory categoryFromApi(Map<String, dynamic> json) {
  return ProductCategory(
    id: json['id'] as int,
    name: json['name'] as String,
    slug: json['slug'] as String,
    updatedAt: json['updated_at'] as String,
  );
}

Product productFromApi(Map<String, dynamic> json) {
  return Product(
    id: json['id'] as int,
    categoryId: json['category_id'] as int,
    name: json['name'] as String,
    price: (json['price'] as num).toInt(),
    stock: (json['stock'] as num).toInt(),
    isActive: json['is_active'] as bool,
    imageUrl: json['image_url'] as String?,
    updatedAt: json['updated_at'] as String,
  );
}

Map<String, Object?> categoryToRow(ProductCategory category) {
  return {
    'id': category.id,
    'name': category.name,
    'slug': category.slug,
    'updated_at': category.updatedAt,
  };
}

/// [stock] diberikan terpisah karena yang disimpan adalah proyeksi lokal
/// (stok server dikurangi penjualan belum tersinkron), bukan `product.stock`.
Map<String, Object?> productToRow(Product product, {required int stock}) {
  return {
    'id': product.id,
    'category_id': product.categoryId,
    'name': product.name,
    'price': product.price,
    'stock': stock,
    'is_active': product.isActive ? 1 : 0,
    'image_url': product.imageUrl,
    'updated_at': product.updatedAt,
  };
}

ProductCategory categoryFromRow(Map<String, Object?> row) {
  return ProductCategory(
    id: row['id'] as int,
    name: row['name'] as String,
    slug: row['slug'] as String,
    updatedAt: row['updated_at'] as String,
  );
}

Product productFromRow(Map<String, Object?> row) {
  return Product(
    id: row['id'] as int,
    categoryId: row['category_id'] as int,
    name: row['name'] as String,
    price: row['price'] as int,
    stock: row['stock'] as int,
    isActive: row['is_active'] == 1,
    imageUrl: row['image_url'] as String?,
    updatedAt: row['updated_at'] as String,
  );
}
