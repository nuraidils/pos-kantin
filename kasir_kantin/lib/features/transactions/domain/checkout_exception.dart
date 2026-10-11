/// Alasan pembayaran ditolak sebelum apa pun ditulis. [message] sudah dalam
/// bahasa Indonesia dan aman ditampilkan langsung ke kasir.
sealed class CheckoutException implements Exception {
  const CheckoutException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class CheckoutEmptyException extends CheckoutException {
  const CheckoutEmptyException() : super('Keranjang masih kosong.');
}

final class CheckoutInvalidQuantityException extends CheckoutException {
  const CheckoutInvalidQuantityException()
    : super('Jumlah produk tidak valid.');
}

/// Produk sudah tidak ada atau nonaktif di data lokal.
final class CheckoutProductUnavailableException extends CheckoutException {
  CheckoutProductUnavailableException(this.productName)
    : super(
        '$productName tidak lagi tersedia. '
        'Hapus dari keranjang lalu coba lagi.',
      );

  final String productName;
}

final class CheckoutInsufficientStockException extends CheckoutException {
  CheckoutInsufficientStockException(
    this.productName, {
    required this.available,
  }) : super(
         'Stok $productName tidak mencukupi (tersisa $available). '
         'Ubah jumlah di keranjang.',
       );

  final String productName;
  final int available;
}

final class CheckoutPriceChangedException extends CheckoutException {
  CheckoutPriceChangedException(this.productName)
    : super('Harga $productName berubah. Periksa keranjang lalu coba lagi.');

  final String productName;
}
