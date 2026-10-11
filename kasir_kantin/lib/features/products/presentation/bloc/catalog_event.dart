part of 'catalog_bloc.dart';

sealed class CatalogEvent extends Equatable {
  const CatalogEvent();

  @override
  List<Object?> get props => [];
}

/// Tab Kasir dibuka: tampilkan data lokal dulu, lalu tarik dari server.
final class CatalogStarted extends CatalogEvent {
  const CatalogStarted();
}

/// Tarik-untuk-memperbarui atau tombol Coba Lagi.
final class CatalogRefreshed extends CatalogEvent {
  const CatalogRefreshed();
}

final class CatalogSearchChanged extends CatalogEvent {
  const CatalogSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [categoryId] null = "Semua".
final class CatalogCategorySelected extends CatalogEvent {
  const CatalogCategorySelected(this.categoryId);

  final int? categoryId;

  @override
  List<Object?> get props => [categoryId];
}

/// Baca ulang katalog dari SQLite TANPA menyentuh server. Dipakai setelah
/// transaksi lokal dibuat, karena stok lokal berkurang.
final class CatalogLocalReloaded extends CatalogEvent {
  const CatalogLocalReloaded();
}
