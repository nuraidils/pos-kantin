import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/value_pulse.dart';

/// Kontrol jumlah [-] n [+] dengan target sentuh 44x44 (DESIGN.md §12, §36).
/// [onIncrement] null = sudah mencapai batas stok.
class QuantityControl extends StatelessWidget {
  const QuantityControl({
    super.key,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundButton(
          icon: Icons.remove,
          tooltip: 'Kurangi jumlah',
          onPressed: onDecrement,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 36),
          child: ValuePulse(
            value: quantity,
            child: Text(
              '$quantity',
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        _RoundButton(
          icon: Icons.add,
          tooltip: 'Tambah jumlah',
          onPressed: onIncrement,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      style: IconButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.textSecondary.withValues(alpha: 0.4),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
