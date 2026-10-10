part of 'catalog_bloc.dart';

enum CatalogStatus {
  /// Membaca SQLite untuk pertama kali.
  loading,

  /// Data lokal tersedia (boleh kosong).
  ready,

  /// SQLite tidak terbaca.
  failure,
}

class CatalogState extends Equatable {
  const CatalogState({
    this.status = CatalogStatus.loading,
    this.categories = const [],
    this.products = const [],
    this.query = '',
    this.selectedCategoryId,
    this.isSyncing = false,
    this.isOffline = false,
    this.syncError,
    this.lastSyncedAt,
    this.loadError,
  });

  final CatalogStatus status;
  final List<ProductCategory> categories;

  /// Semua produk aktif lokal (belum difilter).
  final List<Product> products;
  final String query;
  final int? selectedCategoryId;

  /// Sinkronisasi sedang berjalan di latar belakang.
  final bool isSyncing;

  /// Percobaan sinkronisasi terakhir gagal karena tidak ada koneksi. Ini
  /// keadaan normal (DESIGN.md §33), bukan galat.
  final bool isOffline;

  /// Pesan untuk galat sinkronisasi selain koneksi (mis. server bermasalah).
  final String? syncError;
  final DateTime? lastSyncedAt;
  final String? loadError;

  /// Kategori yang punya minimal satu produk aktif; kategori kosong tidak
  /// ditampilkan sebagai chip agar tidak berujung pada layar kosong.
  List<ProductCategory> get categoriesWithProducts {
    final used = products.map((p) => p.categoryId).toSet();
    return categories.where((c) => used.contains(c.id)).toList();
  }

  /// Produk setelah filter kategori dan pencarian nama.
  List<Product> get visibleProducts {
    final q = query.trim().toLowerCase();
    return products.where((p) {
      final inCategory =
          selectedCategoryId == null || p.categoryId == selectedCategoryId;
      final matches = q.isEmpty || p.name.toLowerCase().contains(q);
      return inCategory && matches;
    }).toList();
  }

  // Parameter nullable memakai closure agar "tidak diubah" dan "ubah jadi
  // null" bisa dibedakan.
  CatalogState copyWith({
    CatalogStatus? status,
    List<ProductCategory>? categories,
    List<Product>? products,
    String? query,
    int? Function()? selectedCategoryId,
    bool? isSyncing,
    bool? isOffline,
    String? Function()? syncError,
    DateTime? Function()? lastSyncedAt,
    String? Function()? loadError,
  }) {
    return CatalogState(
      status: status ?? this.status,
      categories: categories ?? this.categories,
      products: products ?? this.products,
      query: query ?? this.query,
      selectedCategoryId: selectedCategoryId != null
          ? selectedCategoryId()
          : this.selectedCategoryId,
      isSyncing: isSyncing ?? this.isSyncing,
      isOffline: isOffline ?? this.isOffline,
      syncError: syncError != null ? syncError() : this.syncError,
      lastSyncedAt: lastSyncedAt != null ? lastSyncedAt() : this.lastSyncedAt,
      loadError: loadError != null ? loadError() : this.loadError,
    );
  }

  @override
  List<Object?> get props => [
    status,
    categories,
    products,
    query,
    selectedCategoryId,
    isSyncing,
    isOffline,
    syncError,
    lastSyncedAt,
    loadError,
  ];
}
