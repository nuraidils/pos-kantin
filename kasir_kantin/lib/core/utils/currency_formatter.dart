import 'package:intl/intl.dart';

/// Format rupiah Indonesia: Rp10.000, Rp1.250.000 (DESIGN.md §31).
String formatRupiah(int amount) {
  return 'Rp${NumberFormat.decimalPattern('id_ID').format(amount)}';
}
