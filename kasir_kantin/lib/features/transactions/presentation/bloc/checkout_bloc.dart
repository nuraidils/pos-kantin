import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/checkout_exception.dart';
import '../../domain/checkout_line.dart';
import '../../domain/local_transaction.dart';
import '../../domain/payment_method.dart';
import '../../domain/transaction_repository.dart';

part 'checkout_event.dart';
part 'checkout_state.dart';

/// Satu kali pembayaran. Dibuat baru setiap sheet pembayaran dibuka, jadi
/// tidak ada sisa state dari penjualan sebelumnya.
///
/// Sukses = transaksi SUDAH tersimpan di SQLite. Tidak ada yang menunggu
/// server (AGENTS.md §12).
class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc({required this._repository}) : super(const CheckoutState()) {
    on<CheckoutMethodSelected>(_onMethodSelected);
    on<CheckoutSubmitted>(_onSubmitted);
  }

  final TransactionRepository _repository;

  void _onMethodSelected(
    CheckoutMethodSelected event,
    Emitter<CheckoutState> emit,
  ) {
    if (state.isSubmitting || state.isSuccess) return;
    emit(state.copyWith(method: event.method, error: () => null));
  }

  Future<void> _onSubmitted(
    CheckoutSubmitted event,
    Emitter<CheckoutState> emit,
  ) async {
    // Ketuk ganda tidak boleh menghasilkan dua transaksi (AGENTS.md Rule 5).
    // Status diubah secara sinkron sebelum await pertama, jadi event kedua
    // sudah melihat `submitting`.
    if (state.isSubmitting || state.isSuccess) return;
    emit(state.copyWith(status: CheckoutStatus.submitting, error: () => null));

    try {
      final receipt = await _repository.createLocalTransaction(
        lines: event.lines,
        paymentMethod: state.method,
      );
      emit(
        state.copyWith(status: CheckoutStatus.success, receipt: () => receipt),
      );
    } on CheckoutException catch (e) {
      emit(
        state.copyWith(status: CheckoutStatus.failure, error: () => e.message),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: CheckoutStatus.failure,
          error: () => 'Transaksi tidak dapat disimpan. Coba lagi.',
        ),
      );
    }
  }
}
