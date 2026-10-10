import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/cart_item.dart';
import '../bloc/cart_bloc.dart';
import 'quantity_control.dart';

/// Membuka daftar keranjang. CartBloc diteruskan lewat `.value` karena rute
/// sheet berada di luar pohon widget tempat BlocProvider dipasang.
Future<void> showCartSheet(BuildContext context) {
  final bloc = context.read<CartBloc>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    builder: (_) =>
        BlocProvider<CartBloc>.value(value: bloc, child: const CartSheet()),
  );
}

/// Isi keranjang. Jumlah bisa diubah di sini tanpa pindah halaman
/// (DESIGN.md §16).
class CartSheet extends StatelessWidget {
  const CartSheet({super.key});

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kosongkan keranjang?'),
        content: const Text('Semua produk di keranjang akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Kosongkan'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<CartBloc>().add(const CartCleared());
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return BlocBuilder<CartBloc, CartState>(
      builder: (context, state) {
        if (state.isEmpty) {
          return const SafeArea(
            top: false,
            child: SizedBox(
              height: 320,
              child: EmptyState(
                icon: Icons.shopping_basket_outlined,
                title: 'Keranjang masih kosong',
                message: 'Tambahkan produk untuk mulai transaksi.',
              ),
            ),
          );
        }

        // useSafeArea pada showModalBottomSheet TIDAK menghindari sisi bawah,
        // jadi baris Total tertimpa tombol navigasi sistem tanpa ini.
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Keranjang', style: text.headlineSmall),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmClear(context),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Kosongkan'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        minimumSize: const Size(44, 44),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: state.items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) =>
                      _CartItemTile(item: state.items[index]),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total (${state.totalQuantity} item)',
                        style: text.bodyLarge,
                      ),
                    ),
                    Text(
                      formatRupiah(state.totalAmount),
                      style: text.headlineSmall?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final bloc = context.read<CartBloc>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: text.labelLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(formatRupiah(item.price), style: text.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus dari keranjang',
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.danger,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () => bloc.add(CartItemRemoved(item.productId)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                QuantityControl(
                  quantity: item.quantity,
                  onDecrement: () =>
                      bloc.add(CartQuantityDecremented(item.productId)),
                  onIncrement: item.canIncrement
                      ? () => bloc.add(CartQuantityIncremented(item.productId))
                      : null,
                ),
                const Spacer(),
                Text(formatRupiah(item.subtotal), style: text.titleMedium),
              ],
            ),
            if (!item.canIncrement)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Mencapai batas stok (${item.availableStock})',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
