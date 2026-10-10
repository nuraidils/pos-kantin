import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Ringkasan keranjang di bawah katalog; mengetuknya membuka daftar item.
class CartBar extends StatelessWidget {
  const CartBar({
    super.key,
    required this.totalQuantity,
    required this.totalAmount,
    required this.onTap,
  });

  final int totalQuantity;
  final int totalAmount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const onPrimary = TextStyle(color: Colors.white);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_basket_outlined,
                    color: Colors.white,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Keranjang',
                          style: text.labelLarge?.merge(onPrimary),
                        ),
                        Text(
                          '$totalQuantity item',
                          style: text.bodySmall?.merge(
                            const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatRupiah(totalAmount),
                    style: text.titleMedium?.merge(onPrimary),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.keyboard_arrow_up, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
