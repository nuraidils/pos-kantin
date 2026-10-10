import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/product.dart';

/// Kartu produk: gambar, nama, harga, stok (DESIGN.md §14–15).
/// [onTap] null = tidak dapat dipilih (mis. tahap sebelum keranjang ada).
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, this.onTap});

  final Product product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final outOfStock = product.isOutOfStock;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Produk habis tidak dapat dipilih.
        onTap: outOfStock ? null : onTap,
        child: Opacity(
          opacity: outOfStock ? 0.6 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 96, child: _ProductImage(url: product.imageUrl)),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: text.labelLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      formatRupiah(product.price),
                      style: text.titleMedium?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _StockLabel(product: product),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.primarySoft,
      alignment: Alignment.center,
      child: const Icon(
        Icons.fastfood_outlined,
        size: 32,
        color: AppColors.primary,
      ),
    );

    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) return placeholder;

    // Gambar bersifat tambahan: saat offline atau gagal dimuat, tampilkan
    // ikon pengganti, bukan galat.
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

/// Status stok selalu berupa ikon + teks, tidak hanya warna (DESIGN.md §5).
class _StockLabel extends StatelessWidget {
  const _StockLabel({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (product.isOutOfStock) {
      return Row(
        children: [
          const Icon(Icons.block, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Habis',
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    if (product.isLowStock) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: AppColors.accent,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                'Stok tersisa ${product.stock}',
                style: text.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Text('Stok ${product.stock}', style: text.bodySmall);
  }
}
