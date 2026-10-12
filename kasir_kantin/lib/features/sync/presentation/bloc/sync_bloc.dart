import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../transactions/domain/local_transaction.dart';
import '../../../transactions/domain/sync_outcome.dart';
import '../../../transactions/domain/transaction_repository.dart';

part 'sync_event.dart';
part 'sync_state.dart';

/// Mesin pengiriman transaksi lokal ke server (AGENTS.md §15 arah push).
///
/// Aturan yang dijaga di sini:
/// - Kasir tidak pernah menunggu: pembayaran sudah selesai di SQLite sebelum
///   BLoC ini bekerja (AGENTS.md §12).
/// - Satu putaran pada satu waktu, dan transaksi dikirim berurutan dari yang
///   terlama. Tidak ada transaksi ganda: pengiriman ulang pun aman karena
///   server idempoten lewat `local_uuid` (Rule 5).
/// - Gagal dikirim tidak menghapus apa pun (Rule 6). Putaran berhenti di
///   kegagalan pertama (jaringan/server) agar tidak menembak server yang
///   sedang bermasalah berulang kali; sisanya dicoba lagi pada pemicu berikutnya.
/// - `conflict` tidak menghentikan putaran: transaksi lain tetap dikirim.
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  SyncBloc({required this._repository}) : super(const SyncState()) {
    on<SyncStarted>((event, emit) => _run(emit, recoverFirst: true));
    on<SyncRequested>((event, emit) => _run(emit));
  }

  final TransactionRepository _repository;

  // Handler BLoC berjalan bersamaan secara bawaan. Penanda ini diperiksa dan
  // diisi secara sinkron (sebelum await pertama), jadi dua pemicu yang tiba
  // hampir bersamaan tidak membuat dua putaran.
  bool _running = false;
  bool _runAgain = false;

  // `isClosed` baru benar setelah handler yang sedang berjalan selesai, jadi
  // tidak bisa dipakai untuk berhenti di tengah putaran. Penanda ini diisi
  // begitu close() dipanggil (mis. kasir keluar akun).
  bool _stopping = false;

  @override
  Future<void> close() {
    _stopping = true;
    return super.close();
  }

  Future<void> _run(
    Emitter<SyncState> emit, {
    bool recoverFirst = false,
  }) async {
    if (_running) {
      // Pemicu tiba saat pengiriman berjalan (mis. kasir baru membayar):
      // periksa lagi setelah putaran ini, jangan menunggu timer berikutnya.
      _runAgain = true;
      return;
    }
    _running = true;

    try {
      if (recoverFirst) {
        // Yang masih `syncing` saat aplikasi baru dibuka berarti aplikasi
        // tertutup di tengah pengiriman. Mengirim ulang aman (idempoten).
        try {
          await _repository.recoverInterruptedSyncs();
        } catch (_) {
          // Gagal memulihkan tidak boleh menghentikan sinkronisasi lain.
        }
      }

      do {
        _runAgain = false;
        await _drain(emit);
      } while (_runAgain && !_stopping);
    } finally {
      _running = false;
    }
  }

  /// Satu putaran: kirim semua yang boleh dikirim, dari yang terlama.
  Future<void> _drain(Emitter<SyncState> emit) async {
    final List<LocalTransaction> queue;
    try {
      queue = await _repository.getTransactionsToSync();
    } catch (_) {
      // SQLite tidak terbaca: tampilan lama dipertahankan.
      return;
    }

    if (queue.isEmpty) {
      // Tidak ada yang dikirim; hanya sesuaikan hitungan (mis. transaksi
      // baru sudah `synced` oleh putaran lain, atau ada `conflict`).
      await _emitCounts(emit, isSyncing: false, lastRunFailed: false);
      return;
    }

    await _emitCounts(emit, isSyncing: true);

    var changedLocalData = false;
    var stoppedEarly = false;

    for (final transaction in queue) {
      if (_stopping) break;

      final SyncOutcome outcome;
      try {
        outcome = await _repository.syncTransaction(transaction.localUuid);
      } catch (_) {
        // Galat tak terduga: repository sudah melepas status `syncing`.
        stoppedEarly = true;
        break;
      }

      // synced dan conflict sama-sama mengubah data lokal (status, dan stok
      // yang dikembalikan pada konflik).
      if (outcome == SyncOutcome.synced || outcome == SyncOutcome.conflict) {
        changedLocalData = true;
      }
      // 401 sudah memicu AuthBloc lewat ApiClient. 403 dan kegagalan
      // jaringan/server: berhenti, coba lagi nanti.
      if (outcome == SyncOutcome.failed ||
          outcome == SyncOutcome.sessionExpired) {
        stoppedEarly = true;
      }

      await _emitCounts(emit, isSyncing: true);
      if (stoppedEarly) break;
    }

    await _emitCounts(
      emit,
      isSyncing: false,
      lastRunFailed: stoppedEarly,
      bumpRevision: changedLocalData,
    );
  }

  Future<void> _emitCounts(
    Emitter<SyncState> emit, {
    required bool isSyncing,
    bool? lastRunFailed,
    bool bumpRevision = false,
  }) async {
    final int unsynced;
    final int conflicts;
    try {
      unsynced = await _repository.countUnsyncedTransactions();
      conflicts = await _repository.countConflictTransactions();
    } catch (_) {
      emit(state.copyWith(isSyncing: isSyncing));
      return;
    }

    emit(
      state.copyWith(
        isSyncing: isSyncing,
        unsyncedCount: unsynced,
        conflictCount: conflicts,
        lastRunFailed: lastRunFailed,
        changeRevision: bumpRevision
            ? state.changeRevision + 1
            : state.changeRevision,
      ),
    );
  }
}
