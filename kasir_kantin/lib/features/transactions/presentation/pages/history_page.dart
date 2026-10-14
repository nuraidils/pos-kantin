import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/local_transaction.dart';
import '../bloc/history_bloc.dart';
import '../widgets/sync_status_chip.dart';
import '../widgets/transaction_receipt.dart';

/// Tab Riwayat: semua transaksi di perangkat dengan status sinkronisasinya
/// (DESIGN.md §20). Terbaca tanpa internet. Memerlukan [HistoryBloc] di
/// atasnya; AppShell yang membacanya ulang saat status sinkronisasi berubah.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.transactions.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Belum ada transaksi',
            message:
                state.error ?? 'Transaksi yang sudah dibayar tampil di sini.',
            action: state.error == null
                ? null
                : OutlinedButton(
                    onPressed: () =>
                        context.read<HistoryBloc>().add(const HistoryLoaded()),
                    child: const Text('Coba Lagi'),
                  ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Riwayat', style: text.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${state.transactions.length} transaksi',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                state.error!,
                style: text.bodySmall?.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            for (final t in state.transactions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: TransactionCard(
                  transaction: t,
                  onTap: () => showTransactionDetail(context, t.localUuid),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Satu baris riwayat: invoice, status, waktu, ringkasan item, total.
class TransactionCard extends StatelessWidget {
  const TransactionCard({super.key, required this.transaction, this.onTap});

  final LocalTransaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final time = DateFormat(
      'd MMM yyyy, HH.mm',
      'id_ID',
    ).format(transaction.createdAt.toLocal());
    final summary = transaction.items
        .map((i) => '${i.quantity} × ${i.productName}')
        .join(', ');

    return Material(
      key: ValueKey('history-${transaction.localUuid}'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      transaction.invoiceNumber,
                      style: text.titleMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SyncStatusChip(status: transaction.syncStatus),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$time · ${transaction.paymentMethod.label}',
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                summary,
                style: text.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                formatRupiah(transaction.totalAmount),
                style: text.titleMedium?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Membuka detail transaksi. Isinya dibaca dari [HistoryBloc] (bukan salinan),
/// jadi status di sheet ikut berubah saat sinkronisasi berjalan. Rute sheet
/// berada di luar pohon provider, jadi BLoC diteruskan lewat `.value`.
Future<void> showTransactionDetail(BuildContext context, String localUuid) {
  final history = context.read<HistoryBloc>();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    builder: (_) => BlocProvider<HistoryBloc>.value(
      value: history,
      child: _TransactionDetailSheet(localUuid: localUuid),
    ),
  );
}

class _TransactionDetailSheet extends StatelessWidget {
  const _TransactionDetailSheet({required this.localUuid});

  final String localUuid;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: BlocBuilder<HistoryBloc, HistoryState>(
        builder: (context, state) {
          final transaction = state.transactions
              .where((t) => t.localUuid == localUuid)
              .firstOrNull;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.lg,
                  top: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Detail Transaksi',
                        style: text.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      icon: const Icon(Icons.close),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: transaction == null
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.xxl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        child: TransactionReceipt(transaction: transaction),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
