import '../../../core/error/api_exceptions.dart';
import '../../../core/network/api_client.dart';
import '../domain/catalog_changes.dart';
import '../domain/product.dart';
import '../domain/product_category.dart';
import 'catalog_mappers.dart';

class CatalogRemoteDataSource {
  CatalogRemoteDataSource(this._client);

  final ApiClient _client;

  /// GET /catalog. [updatedSince] kosong = sinkronisasi penuh.
  /// 401 di sini sengaja DILAPORKAN (reportUnauthorized bawaan): token sesi
  /// aktif tidak berlaku lagi, sehingga AuthBloc mengakhiri sesi.
  Future<CatalogChanges> fetch({String? updatedSince}) async {
    final json = await _client.get(
      '/catalog',
      query: updatedSince == null ? null : {'updated_since': updatedSince},
    );

    try {
      final data = json['data'] as Map<String, dynamic>;
      final meta = json['meta'] as Map<String, dynamic>;

      final categories = <ProductCategory>[];
      final deletedCategoryIds = <int>{};
      for (final raw in data['categories'] as List) {
        final item = raw as Map<String, dynamic>;
        if (item['deleted_at'] != null) {
          deletedCategoryIds.add(item['id'] as int);
        } else {
          categories.add(categoryFromApi(item));
        }
      }

      final products = <Product>[];
      final deletedProductIds = <int>{};
      for (final raw in data['products'] as List) {
        final item = raw as Map<String, dynamic>;
        if (item['deleted_at'] != null) {
          deletedProductIds.add(item['id'] as int);
        } else {
          products.add(productFromApi(item));
        }
      }

      return CatalogChanges(
        categories: categories,
        products: products,
        deletedCategoryIds: deletedCategoryIds,
        deletedProductIds: deletedProductIds,
        serverTime: meta['server_time'] as String,
        fullSync: meta['full_sync'] as bool,
      );
    } on TypeError {
      throw const UnexpectedApiException(
        'Respons server tidak sesuai harapan.',
      );
    }
  }
}
