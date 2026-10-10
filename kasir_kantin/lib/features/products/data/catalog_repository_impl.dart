import '../domain/catalog_repository.dart';
import '../domain/catalog_snapshot.dart';
import 'catalog_local_data_source.dart';
import 'catalog_remote_data_source.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl({
    required CatalogRemoteDataSource remote,
    required CatalogLocalDataSource local,
  }) : _remote = remote,
       _local = local;

  final CatalogRemoteDataSource _remote;
  final CatalogLocalDataSource _local;

  @override
  Future<CatalogSnapshot> loadLocal() async {
    final categories = await _local.getCategories();
    final products = await _local.getActiveProducts();
    final lastSync = await _local.readLastSync();
    return CatalogSnapshot(
      categories: categories,
      products: products,
      lastSyncedAt: lastSync == null
          ? null
          : DateTime.tryParse(lastSync)?.toLocal(),
    );
  }

  @override
  Future<CatalogSnapshot> sync() async {
    // Tanpa kursor = sinkronisasi penuh (pertama kali). Bila fetch gagal,
    // exception naik dan SQLite tidak disentuh.
    final since = await _local.readLastSync();
    final changes = await _remote.fetch(updatedSince: since);
    await _local.applyChanges(changes);
    return loadLocal();
  }
}
