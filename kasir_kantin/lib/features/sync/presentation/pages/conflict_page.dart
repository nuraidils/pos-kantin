import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../products/presentation/bloc/catalog_bloc.dart';
import '../../../transactions/domain/local_transaction.dart';
import '../../../transactions/domain/transaction_repository.dart';
import '../bloc/conflict_bloc.dart';
import '../bloc/sync_bloc.dart';

/// Membuka [ConflictPage]. Rute baru berada di luar pohon provider pemanggil,
/// jadi BLoC yang dibutuhkan diteruskan lewat `BlocProvider.value`.
void openConflictPage(BuildContext context) {
  final repository = context.read<TransactionRepository>();
  final sync = context.read<SyncBloc>();
  final catalog = context.read<CatalogBloc>();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider<SyncBloc>.value(value: sync),
          BlocProvider<CatalogBloc>.value(value: catalog),
          BlocProvider<ConflictBloc>(
            create: (_) =>
                ConflictBloc(repository: repository)
                  ..add(const ConflictLoaded()),
          ),
        ],
        child: const ConflictPage(),
      ),
    ),
  );
}

/// Daftar transaksi "Perlu perhatian" (DESIGN.md §20): alasan ditampilkan
/// jelas dan datanya tetap utuh. Dibuka dari banner sinkronisasi.
///
/// Memerlukan [ConflictBloc], [SyncBloc], dan [CatalogBloc] di atasnya.
class ConflictPage extends StatelessWidget {
  const ConflictPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        // Pengiriman otomatis bisa menghasilkan konflik baru saat halaman terbuka.
        BlocListener<SyncBloc, SyncState>(
          listenWhen: (a, b) => a.changeRevision != b.changeRevision,
          listener: (context, _) =>
              context.read<ConflictBloc>().add(const ConflictLoaded()),
        ),
        // Kirim ulang: stok lokal dikurangi lagi, jadi baca ulang katalog,
        // lalu kirim sekarang tanpa menunggu timer.
        BlocListener<ConflictBloc, ConflictState>(
          listenWhen: (a, b) => a.retryCount != b.retryCount,
          listener: (context, _) {
            context.read<CatalogBloc>().add(const CatalogLocalReloaded());
            context.read<SyncBloc>().add(const SyncRequested());
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(title: const Text('Perlu Perhatian')),
        body: BlocBuilder<ConflictBloc, ConflictState>(
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.transactions.isEmpty) {
              return EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Tidak ada transaksi yang perlu perhatian',
                message: state.error,
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  'Transaksi ini sudah tersimpan di perangkat dan tidak '
                  'hilang. Server belum menerimanya. Setelah stok di server '
                  'diperbaiki, tekan Kirim Ulang.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (state.error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    state.error!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                for (final t in state.transactions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _ConflictCard(transaction: t),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.transaction});

  final LocalTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final time = DateFormat(
      'd MMM yyyy, HH.mm',
      'id_ID',
    ).format(transaction.createdAt.toLocal());

    return Container(
      key: ValueKey('conflict-${transaction.localUuid}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(transaction.invoiceNumber, style: text.titleMedium),
              ),
              Text('Perlu perhatian', style: text.labelMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$time · ${transaction.paymentMethod.label}',
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            transaction.syncMessage ??
                'Transaksi tidak dapat diterapkan oleh server.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final item in transaction.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.quantity} × ${item.productName}',
                      style: text.bodyMedium,
                    ),
                  ),
                  Text(formatRupiah(item.subtotal), style: text.bodyMedium),
                ],
              ),
            ),
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Text(
                  formatRupiah(transaction.totalAmount),
                  style: text.titleMedium,
                ),
              ),
              OutlinedButton(
                onPressed: () => context.read<ConflictBloc>().add(
                  ConflictRetried(transaction.localUuid),
                ),
                child: const Text('Kirim Ulang'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
