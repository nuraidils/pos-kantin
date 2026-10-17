import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/product.dart';

/// Kartu produk: gambar, nama, harga, stok (DESIGN.md §14–15).
/// [onTap] null = tidak dapat dipilih. [quantityInCart] > 0 menampilkan
/// lencana jumlah di keranjang.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.quantityInCart = 0,
  });

  final Product product;
  final VoidCallback? onTap;
  final int quantityInCart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final outOfStock = product.isOutOfStock;

    // Pembaca layar: kartu adalah tombol; produk habis tampil nonaktif
    // (DESIGN.md §37). Teks di dalamnya (nama, harga, stok) ikut dibacakan.
    return Semantics(
      button: true,
      enabled: !outOfStock,
      child: _card(context, text, outOfStock),
    );
  }

  Widget _card(BuildContext context, TextTheme text, bool outOfStock) {
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
              SizedBox(
                height: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ProductImage(url: product.imageUrl),
                    if (quantityInCart > 0)
                      Positioned(
                        top: AppSpacing.sm,
                        right: AppSpacing.sm,
                        child: _CartBadge(quantity: quantityInCart),
                      ),
                  ],
                ),
              ),
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

/// Lencana "di keranjang": ikon + angka, tidak hanya warna.
class _CartBadge extends StatelessWidget {
  const _CartBadge({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Di keranjang: $quantity',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_basket_outlined,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$quantity',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
