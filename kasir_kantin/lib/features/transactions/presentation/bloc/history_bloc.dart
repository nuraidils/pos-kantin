import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/local_transaction.dart';
import '../../domain/transaction_repository.dart';

sealed class HistoryEvent extends Equatable {
  const HistoryEvent();

  @override
  List<Object?> get props => [];
}

/// Membaca ulang seluruh transaksi lokal dari SQLite. Dikirim saat tab dibuka,
/// dan saat SyncBloc berubah (status transaksi bergerak).
final class HistoryLoaded extends HistoryEvent {
  const HistoryLoaded();
}

class HistoryState extends Equatable {
  const HistoryState({
    this.transactions = const [],
    this.isLoading = true,
    this.error,
  });

  final List<LocalTransaction> transactions;
  final bool isLoading;
  final String? error;

  @override
  List<Object?> get props => [transactions, isLoading, error];
}

/// Riwayat transaksi lokal, semua status, terbaru dulu. Hanya membaca:
/// tidak ada yang bisa dihapus atau diubah dari sini (AGENTS.md Rule 6).
class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc({required this._repository}) : super(const HistoryState()) {
    on<HistoryLoaded>((event, emit) => _load(emit));
  }

  final TransactionRepository _repository;

  // Handler berjalan bersamaan. Pembacaan lama yang selesai terlambat tidak
  // boleh menimpa hasil yang lebih baru.
  int _latestRequest = 0;

  Future<void> _load(Emitter<HistoryState> emit) async {
    final request = ++_latestRequest;
    try {
      final list = await _repository.getAllTransactions();
      if (request != _latestRequest) return;
      emit(HistoryState(transactions: list, isLoading: false));
    } catch (_) {
      if (request != _latestRequest) return;
      // Daftar lama dipertahankan bila ada; pesan galat tampil di atasnya.
      emit(
        HistoryState(
          transactions: state.transactions,
          isLoading: false,
          error: 'Riwayat tidak dapat dibaca. Coba lagi.',
        ),
      );
    }
  }
}
