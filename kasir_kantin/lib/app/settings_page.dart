import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../features/auth/presentation/bloc/auth_bloc.dart';
import '../features/sync/presentation/bloc/sync_bloc.dart';

/// Tab Pengaturan. Saat ini hanya akun & keluar.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    // Transaksi yang belum diterima server tetap aman di perangkat, tetapi
    // baru terkirim setelah kasir masuk lagi. Kasir perlu tahu itu sebelum
    // keluar (AGENTS.md Rule 6).
    final sync = context.read<SyncBloc>().state;
    final notes = <String>[
      if (sync.unsyncedCount > 0)
        'Masih ada ${sync.unsyncedCount} transaksi yang belum tersinkron. '
            'Transaksi tetap tersimpan di perangkat ini dan akan dikirim '
            'setelah Anda masuk kembali.',
      if (sync.conflictCount > 0)
        '${sync.conflictCount} transaksi perlu perhatian dan tetap '
            'tersimpan di perangkat ini.',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: Text(
          [
            ...notes,
            if (notes.isEmpty) 'Data di perangkat ini tidak dihapus.',
            'Anda membutuhkan koneksi internet untuk masuk kembali.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<AuthBloc>().add(const AuthLogoutRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final user = state is AuthAuthenticated ? state.user : null;

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Pengaturan', style: text.headlineMedium),
            const SizedBox(height: AppSpacing.lg),
            if (user != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primarySoft,
                        child: Text(
                          user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                          style: text.titleMedium?.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.name, style: text.titleMedium),
                            Text(user.email, style: text.bodySmall),
                            const SizedBox(height: AppSpacing.xs),
                            Text(_roleLabel(user.role), style: text.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xxl),
            OutlinedButton.icon(
              onPressed: () => _confirmLogout(context),
              icon: const Icon(Icons.logout),
              label: const Text('Keluar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );
  }

  String _roleLabel(String role) => role == 'cashier' ? 'Kasir' : role;
}
