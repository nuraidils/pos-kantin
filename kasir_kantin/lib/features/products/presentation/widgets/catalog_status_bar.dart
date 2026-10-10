import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Status koneksi/sinkronisasi katalog yang tenang dan informatif
/// (DESIGN.md §19, §33). Selalu ikon + teks, tidak hanya warna.
class CatalogStatusBar extends StatelessWidget {
  const CatalogStatusBar({
    super.key,
    required this.isSyncing,
    required this.isOffline,
    required this.lastSyncedAt,
    this.syncError,
    this.onRetry,
  });

  final bool isSyncing;
  final bool isOffline;
  final DateTime? lastSyncedAt;
  final String? syncError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (isSyncing) {
      return _line(
        text,
        leading: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: 'Menyinkronkan...',
      );
    }

    final error = syncError;
    if (error != null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.infoSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.info),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(error, style: text.bodySmall)),
            TextButton(onPressed: onRetry, child: const Text('Coba Lagi')),
          ],
        ),
      );
    }

    if (isOffline) {
      return _line(
        text,
        leading: const Icon(
          Icons.cloud_off_outlined,
          size: 16,
          color: AppColors.offline,
        ),
        label: 'Offline · Data lokal digunakan',
      );
    }

    final syncedAt = lastSyncedAt;
    if (syncedAt != null) {
      return _line(
        text,
        leading: const Icon(
          Icons.check_circle_outline,
          size: 16,
          color: AppColors.success,
        ),
        label: 'Online · Diperbarui ${DateFormat('HH:mm').format(syncedAt)}',
      );
    }

    return const SizedBox.shrink();
  }

  Widget _line(
    TextTheme text, {
    required Widget leading,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(label, style: text.bodySmall)),
        ],
      ),
    );
  }
}
