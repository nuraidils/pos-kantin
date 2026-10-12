import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../bloc/sync_bloc.dart';

/// Status transaksi yang belum tersinkron (DESIGN.md §19, §33). Tenang dan
/// informatif: selalu ikon + teks, tidak pernah merah untuk keadaan offline
/// biasa. Tidak tampil sama sekali bila semuanya sudah beres.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, state) {
        final rows = <Widget>[];

        if (state.isSyncing && state.unsyncedCount > 0) {
          rows.add(
            _Row(
              key: const ValueKey('sync-banner-syncing'),
              leading: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              label: 'Menyinkronkan ${state.unsyncedCount} transaksi...',
              background: AppColors.infoSoft,
            ),
          );
        } else if (state.unsyncedCount > 0) {
          rows.add(
            _Row(
              key: const ValueKey('sync-banner-pending'),
              leading: const Icon(
                Icons.cloud_upload_outlined,
                size: 18,
                color: AppColors.info,
              ),
              label: state.lastRunFailed
                  ? '${state.unsyncedCount} transaksi belum tersinkron. '
                        'Akan dicoba lagi otomatis.'
                  : '${state.unsyncedCount} transaksi menunggu sinkronisasi',
              background: AppColors.infoSoft,
              action: state.lastRunFailed
                  ? TextButton(
                      onPressed: () =>
                          context.read<SyncBloc>().add(const SyncRequested()),
                      child: const Text('Coba Lagi'),
                    )
                  : null,
            ),
          );
        }

        if (state.conflictCount > 0) {
          rows.add(
            _Row(
              key: const ValueKey('sync-banner-conflict'),
              leading: const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              label: '${state.conflictCount} transaksi perlu perhatian',
              background: AppColors.warning.withValues(alpha: 0.12),
            ),
          );
        }

        if (rows.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.xs),
                rows[i],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.leading,
    required this.label,
    required this.background,
    this.action,
  });

  final Widget leading;
  final String label;
  final Color background;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: text.bodySmall)),
          ?action,
        ],
      ),
    );
  }
}
