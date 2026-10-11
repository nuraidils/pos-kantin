/// Metode pembayaran MVP (AGENTS.md §20). [value] adalah isi kolom
/// `payment_method` di SQLite dan di server; [label] tampil ke kasir.
enum PaymentMethod {
  cash('cash', 'Tunai'),
  qris('qris', 'QRIS');

  const PaymentMethod(this.value, this.label);

  final String value;
  final String label;

  static PaymentMethod fromValue(String value) =>
      values.firstWhere((method) => method.value == value);
}
