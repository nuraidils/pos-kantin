import 'package:equatable/equatable.dart';

/// Satu baris yang diminta kasir saat membayar. Hanya identitas dan jumlah:
/// nama dan harga untuk riwayat dibaca ulang dari SQLite saat transaksi
/// ditulis, bukan dipercaya dari keranjang.
///
/// [expectedPrice] adalah harga yang dilihat kasir. Bila harga di SQLite
/// sudah berbeda, pembayaran ditolak agar kasir tidak menagih nominal yang
/// berbeda dari yang tampil di layar. [name] hanya untuk pesan galat.
class CheckoutLine extends Equatable {
  const CheckoutLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.expectedPrice,
  });

  final int productId;
  final String name;
  final int quantity;
  final int expectedPrice;

  @override
  List<Object?> get props => [productId, name, quantity, expectedPrice];
}
