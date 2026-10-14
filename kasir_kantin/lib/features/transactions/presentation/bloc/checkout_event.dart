part of 'checkout_bloc.dart';

sealed class CheckoutEvent extends Equatable {
  const CheckoutEvent();

  @override
  List<Object?> get props => [];
}

final class CheckoutMethodSelected extends CheckoutEvent {
  const CheckoutMethodSelected(this.method);

  final PaymentMethod method;

  @override
  List<Object?> get props => [method];
}

/// Tombol "Bayar Sekarang". Isi keranjang dikirim oleh widget agar BLoC ini
/// tidak bergantung pada CartBloc.
final class CheckoutSubmitted extends CheckoutEvent {
  const CheckoutSubmitted(this.lines);

  final List<CheckoutLine> lines;

  @override
  List<Object?> get props => [lines];
}

/// Membaca ulang transaksi yang baru dibayar dari SQLite agar struk mengikuti
/// status sinkronisasi sebenarnya. Dikirim widget saat SyncBloc berubah.
final class CheckoutReceiptRefreshed extends CheckoutEvent {
  const CheckoutReceiptRefreshed();
}
