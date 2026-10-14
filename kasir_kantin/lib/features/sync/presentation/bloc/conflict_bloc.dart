import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../transactions/domain/local_transaction.dart';
import '../../../transactions/domain/transaction_repository.dart';

sealed class ConflictEvent extends Equatable {
  const ConflictEvent();

  @override
  List<Object?> get props => [];
}

/// Membaca daftar transaksi `conflict` dari SQLite.
final class ConflictLoaded extends ConflictEvent {
  const ConflictLoaded();
}

/// Kasir menekan "Kirim Ulang" pada satu transaksi.
final class ConflictRetried extends ConflictEvent {
  const ConflictRetried(this.localUuid);

  final String localUuid;

  @override
  List<Object?> get props => [localUuid];
}

class ConflictState extends Equatable {
  const ConflictState({
    this.transactions = const [],
    this.isLoading = true,
    this.error,
    this.retryCount = 0,
  });

  final List<LocalTransaction> transactions;
  final bool isLoading;
  final String? error;

  /// Naik setiap ada transaksi yang dikembalikan ke antrean. Halaman memakainya
  /// untuk memicu pengiriman dan membaca ulang stok.
  final int retryCount;

  ConflictState copyWith({
    List<LocalTransaction>? transactions,
    bool? isLoading,
    String? error,
    bool clearError = false,
    int? retryCount,
  }) {
    return ConflictState(
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  List<Object?> get props => [transactions, isLoading, error, retryCount];
}

/// Daftar transaksi yang ditolak server. Satu-satunya tindakan kasir adalah
/// mengirim ulang; tidak ada hapus atau ubah jumlah (AGENTS.md §13.4).
class ConflictBloc extends Bloc<ConflictEvent, ConflictState> {
  ConflictBloc({required this._repository}) : super(const ConflictState()) {
    on<ConflictLoaded>((event, emit) => _load(emit));
    on<ConflictRetried>(_onRetried);
  }

  final TransactionRepository _repository;

  Future<void> _load(Emitter<ConflictState> emit) async {
    try {
      final list = await _repository.getConflictTransactions();
      emit(
        state.copyWith(transactions: list, isLoading: false, clearError: true),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Daftar transaksi tidak dapat dibaca. Coba lagi.',
        ),
      );
    }
  }

  Future<void> _onRetried(
    ConflictRetried event,
    Emitter<ConflictState> emit,
  ) async {
    try {
      final requeued = await _repository.retryConflict(event.localUuid);
      if (requeued) emit(state.copyWith(retryCount: state.retryCount + 1));
    } catch (_) {
      emit(
        state.copyWith(
          error: 'Transaksi tidak dapat dikirim ulang. Coba lagi.',
        ),
      );
      return;
    }
    await _load(emit);
  }
}
