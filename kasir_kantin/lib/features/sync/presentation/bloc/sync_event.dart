part of 'sync_bloc.dart';

sealed class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object?> get props => [];
}

/// Dikirim sekali saat kerangka aplikasi dibuka (sesi masuk): memulihkan
/// transaksi yang tertinggal `syncing`, lalu mengirim yang menunggu.
final class SyncStarted extends SyncEvent {
  const SyncStarted();
}

/// Kirim yang menunggu sekarang. Dipicu setelah pembayaran, timer berkala,
/// aplikasi dibuka kembali, dan tombol Coba Lagi. Aman dikirim berulang:
/// bila pengiriman sedang berjalan, permintaan ini hanya membuatnya
/// memeriksa sekali lagi setelah selesai.
final class SyncRequested extends SyncEvent {
  const SyncRequested();
}
