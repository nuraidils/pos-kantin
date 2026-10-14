import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/local_transaction.dart';
import '../../domain/sync_status.dart';
import 'sync_status_chip.dart';

/// Rincian satu transaksi beserta status sinkronisasi SEBENARNYA. Dipakai
/// oleh layar sukses pembayaran dan detail dari tab Riwayat. Hanya
/// menampilkan; status datang dari transaksi yang diberikan.
class TransactionReceipt extends StatelessWidget {
  const TransactionReceipt({super.key, required this.transaction});

  final LocalTransaction transaction;

  /// Penjelasan singkat untuk status yang butuh tindakan atau menunggu.
  String? get _note => switch (transaction.syncStatus) {
    SyncStatus.failed =>
      '${transaction.syncMessage ?? 'Transaksi belum terkirim.'} '
          'Akan dicoba lagi otomatis.',
    SyncStatus.conflict =>
      '${transaction.syncMessage ?? 'Transaksi tidak dapat diterapkan oleh server.'} '
          'Transaksi tetap tersimpan. Buka "Perlu perhatian" di bagian atas '
          'layar untuk mengirim ulang.',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final time = DateFormat(
      'd MMM yyyy, HH.mm',
      'id_ID',
    ).format(transaction.createdAt.toLocal());
    final note = _note;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: SyncStatusChip(status: transaction.syncStatus)),
        if (note != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            note,
            key: const ValueKey('receipt-note'),
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                _DetailRow(
                  label: 'No. Invoice',
                  value: transaction.invoiceNumber,
                ),
                const SizedBox(height: AppSpacing.sm),
                _DetailRow(label: 'Waktu', value: time),
                const SizedBox(height: AppSpacing.sm),
                _DetailRow(
                  label: 'Metode',
                  value: transaction.paymentMethod.label,
                ),
                const Divider(height: AppSpacing.xxl),
                for (final item in transaction.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _DetailRow(
                      label: '${item.quantity} × ${item.productName}',
                      value: formatRupiah(item.subtotal),
                    ),
                  ),
                const Divider(height: AppSpacing.xxl),
                _DetailRow(
                  label: 'Total',
                  value: formatRupiah(transaction.totalAmount),
                  emphasized: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: text.bodyMedium)),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          style: emphasized
              ? text.titleMedium?.copyWith(color: AppColors.primary)
              : text.labelLarge,
        ),
      ],
    );
  }
}
