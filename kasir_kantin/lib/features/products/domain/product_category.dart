import 'package:equatable/equatable.dart';

/// Kategori produk (salinan lokal dari server; id = id server).
class ProductCategory extends Equatable {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String slug;

  /// Teks ISO 8601 apa adanya dari server.
  final String updatedAt;

  @override
  List<Object?> get props => [id, name, slug, updatedAt];
}
