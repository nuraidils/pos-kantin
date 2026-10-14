import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/sync_status.dart';

/// Label status sinkronisasi untuk kasir (DESIGN.md §20). Satu tempat agar
/// riwayat, struk, dan detail memakai kata yang sama.
extension SyncStatusLabel on SyncStatus {
  String get label => switch (this) {
    SyncStatus.pending => 'Menunggu sinkronisasi',
    SyncStatus.syncing => 'Menyinkronkan...',
    SyncStatus.synced => 'Tersinkron',
    SyncStatus.failed => 'Gagal disinkronkan',
    SyncStatus.conflict => 'Perlu perhatian',
  };
}

/// Chip status: SELALU ikon + teks, tidak pernah warna saja (DESIGN.md §5, §37).
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, required this.status});

  final SyncStatus status;

  ({IconData icon, Color color}) get _style => switch (status) {
    SyncStatus.pending => (icon: Icons.schedule, color: AppColors.info),
    SyncStatus.syncing => (icon: Icons.sync, color: AppColors.info),
    SyncStatus.synced => (icon: Icons.check_circle, color: AppColors.success),
    SyncStatus.failed => (icon: Icons.error_outline, color: AppColors.danger),
    SyncStatus.conflict => (
      icon: Icons.warning_amber_rounded,
      color: AppColors.warning,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final text = Theme.of(context).textTheme;

    return Container(
      key: ValueKey('status-chip-${status.name}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 16, color: style.color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              status.label,
              style: text.labelMedium?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
