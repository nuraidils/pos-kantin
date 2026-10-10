import 'catalog_snapshot.dart';

abstract interface class CatalogRepository {
  /// Membaca katalog dari SQLite TANPA jaringan.
  Future<CatalogSnapshot> loadLocal();

  /// Menarik perubahan dari server, menerapkannya ke SQLite, lalu
  /// mengembalikan isi katalog lokal terbaru. Melempar `ApiException` bila
  /// gagal; data lokal tidak berubah saat gagal.
  Future<CatalogSnapshot> sync();
}
