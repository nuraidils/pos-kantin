part of 'checkout_bloc.dart';

enum CheckoutStatus { editing, submitting, success, failure }

class CheckoutState extends Equatable {
  const CheckoutState({
    this.method = PaymentMethod.cash,
    this.status = CheckoutStatus.editing,
    this.receipt,
    this.error,
  });

  final PaymentMethod method;
  final CheckoutStatus status;

  /// Transaksi yang baru tersimpan; terisi hanya saat [status] = success.
  final LocalTransaction? receipt;

  /// Pesan galat untuk kasir; terisi hanya saat [status] = failure.
  final String? error;

  bool get isSubmitting => status == CheckoutStatus.submitting;
  bool get isSuccess => status == CheckoutStatus.success;

  CheckoutState copyWith({
    PaymentMethod? method,
    CheckoutStatus? status,
    LocalTransaction? Function()? receipt,
    String? Function()? error,
  }) {
    return CheckoutState(
      method: method ?? this.method,
      status: status ?? this.status,
      receipt: receipt != null ? receipt() : this.receipt,
      error: error != null ? error() : this.error,
    );
  }

  @override
  List<Object?> get props => [method, status, receipt, error];
}
