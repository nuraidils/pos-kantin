import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/utils/currency_formatter.dart';

void main() {
  test('memformat rupiah gaya Indonesia tanpa spasi', () {
    expect(formatRupiah(0), 'Rp0');
    expect(formatRupiah(10000), 'Rp10.000');
    expect(formatRupiah(125000), 'Rp125.000');
    expect(formatRupiah(1250000), 'Rp1.250.000');
  });
}
