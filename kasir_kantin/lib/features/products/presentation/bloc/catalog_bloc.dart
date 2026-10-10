import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exceptions.dart';
import '../../domain/catalog_repository.dart';
import '../../domain/catalog_snapshot.dart';
import '../../domain/product.dart';
import '../../domain/product_category.dart';

part 'catalog_event.dart';
part 'catalog_state.dart';

/// Katalog untuk tab Kasir. Data lokal SELALU tampil lebih dulu
/// (DESIGN.md §39); sinkronisasi berjalan di belakang dan tidak pernah
/// menghalangi kasir.
class CatalogBloc extends Bloc<CatalogEvent, CatalogState> {
  CatalogBloc({required this._repository}) : super(const CatalogState()) {
    on<CatalogStarted>(_onStarted);
    on<CatalogRefreshed>((event, emit) => _sync(emit));
    on<CatalogSearchChanged>(
      (event, emit) => emit(state.copyWith(query: event.query)),
    );
    on<CatalogCategorySelected>(
      (event, emit) =>
          emit(state.copyWith(selectedCategoryId: () => event.categoryId)),
    );
  }

  final CatalogRepository _repository;

  Future<void> _onStarted(
    CatalogStarted event,
    Emitter<CatalogState> emit,
  ) async {
    try {
      final snapshot = await _repository.loadLocal();
      emit(_withSnapshot(state.copyWith(loadError: () => null), snapshot));
    } catch (_) {
      emit(
        state.copyWith(
          status: CatalogStatus.failure,
          loadError: () =>
              'Data produk di perangkat tidak dapat dibaca. Coba lagi.',
        ),
      );
      return;
    }
    await _sync(emit);
  }

  Future<void> _sync(Emitter<CatalogState> emit) async {
    if (state.isSyncing) return; // cegah sinkronisasi ganda
    emit(state.copyWith(isSyncing: true, syncError: () => null));

    try {
      final snapshot = await _repository.sync();
      emit(
        _withSnapshot(
          state.copyWith(
            isSyncing: false,
            isOffline: false,
            syncError: () => null,
          ),
          snapshot,
        ),
      );
    } on NetworkException {
      // Tanpa internet bukan galat: kasir tetap bekerja dengan data lokal.
      emit(state.copyWith(isSyncing: false, isOffline: true));
    } on UnauthorizedException {
      // ApiClient sudah memberi tahu AuthBloc; sesi diakhiri di sana.
      emit(state.copyWith(isSyncing: false));
    } on ApiException catch (e) {
      emit(state.copyWith(isSyncing: false, syncError: () => _messageFor(e)));
    } catch (_) {
      emit(
        state.copyWith(
          isSyncing: false,
          syncError: () => 'Terjadi kesalahan yang tidak terduga. Coba lagi.',
        ),
      );
    }
  }

  CatalogState _withSnapshot(CatalogState base, CatalogSnapshot snapshot) {
    // Kategori terpilih yang sudah tidak punya produk (mis. dihapus di
    // server) dikembalikan ke "Semua".
    final usedCategoryIds = snapshot.products.map((p) => p.categoryId).toSet();
    final selected = base.selectedCategoryId;
    final keepSelected = selected != null && usedCategoryIds.contains(selected);

    return base.copyWith(
      status: CatalogStatus.ready,
      categories: snapshot.categories,
      products: snapshot.products,
      selectedCategoryId: () => keepSelected ? selected : null,
      lastSyncedAt: () => snapshot.lastSyncedAt,
    );
  }

  String _messageFor(ApiException e) {
    return switch (e) {
      ServerException() ||
      ForbiddenException() ||
      UnexpectedApiException() => e.message,
      _ => 'Katalog tidak dapat diperbarui. Coba lagi.',
    };
  }
}
