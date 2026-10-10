import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../bloc/catalog_bloc.dart';
import '../widgets/catalog_status_bar.dart';
import '../widgets/category_chips.dart';
import '../widgets/product_card.dart';

/// Tab Kasir: katalog produk dari SQLite (DESIGN.md §14). Widget hanya
/// menampilkan state dan mengirim event.
class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  Future<void> _refresh(BuildContext context) {
    final bloc = context.read<CatalogBloc>();
    bloc.add(const CatalogRefreshed());
    // Indikator tarik-perbarui berhenti saat sinkronisasi selesai.
    return bloc.stream.firstWhere((s) => !s.isSyncing);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CatalogBloc, CatalogState>(
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: () => _refresh(context),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                sliver: SliverToBoxAdapter(child: _Header(state: state)),
              ),
              ..._body(context, state),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, CatalogState state) {
    switch (state.status) {
      case CatalogStatus.loading:
        return [const _SkeletonGrid()];

      case CatalogStatus.failure:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.error_outline,
              title: 'Produk tidak dapat dimuat',
              message: state.loadError,
              action: FilledButton(
                onPressed: () =>
                    context.read<CatalogBloc>().add(const CatalogStarted()),
                child: const Text('Coba Lagi'),
              ),
            ),
          ),
        ];

      case CatalogStatus.ready:
        if (state.products.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Belum ada produk',
                message: state.isOffline
                    ? 'Hubungkan perangkat ke internet untuk mengunduh katalog, '
                          'lalu tarik layar ke bawah.'
                    : 'Minta pemilik menambahkan produk, '
                          'lalu tarik layar ke bawah untuk memperbarui.',
                action: state.isSyncing
                    ? null
                    : OutlinedButton(
                        onPressed: () => context.read<CatalogBloc>().add(
                          const CatalogRefreshed(),
                        ),
                        child: const Text('Coba Lagi'),
                      ),
              ),
            ),
          ];
        }

        final visible = state.visibleProducts;
        if (visible.isEmpty) {
          return const [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off,
                title: 'Produk tidak ditemukan',
                message: 'Coba kata kunci atau kategori lain.',
              ),
            ),
          ];
        }

        // Tinggi kartu mengikuti ukuran teks sistem agar tidak meluap.
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 1.6).toDouble();
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                mainAxisExtent: 128 + 88 * textScale,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => ProductCard(product: visible[index]),
                childCount: visible.length,
              ),
            ),
          ),
        ];
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final CatalogState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final bloc = context.read<CatalogBloc>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Selamat Datang', style: text.bodySmall),
        Text('Kasir', style: text.headlineMedium),
        const SizedBox(height: AppSpacing.xs),
        CatalogStatusBar(
          isSyncing: state.isSyncing,
          isOffline: state.isOffline,
          lastSyncedAt: state.lastSyncedAt,
          syncError: state.syncError,
          onRetry: () => bloc.add(const CatalogRefreshed()),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SearchField(
          key: const ValueKey('catalog-search'),
          onChanged: (value) => bloc.add(CatalogSearchChanged(value)),
        ),
        if (state.categoriesWithProducts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          CategoryChips(
            categories: state.categoriesWithProducts,
            selectedId: state.selectedCategoryId,
            onSelected: (id) => bloc.add(CatalogCategorySelected(id)),
          ),
        ],
      ],
    );
  }
}

/// Kolom cari. Dipisah sebagai StatefulWidget agar teks yang diketik tidak
/// hilang saat halaman dibangun ulang oleh perubahan state.
class _SearchField extends StatefulWidget {
  const _SearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Cari produk...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Hapus pencarian',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Kerangka sementara selama SQLite dibaca (DESIGN.md §22). Statis, tanpa
/// animasi, agar murah dan mudah diuji.
class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          mainAxisExtent: 216,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => DecoratedBox(
            key: const ValueKey('product-skeleton'),
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
          ),
          childCount: 6,
        ),
      ),
    );
  }
}
