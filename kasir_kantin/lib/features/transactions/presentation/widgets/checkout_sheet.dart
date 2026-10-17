import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../cart/presentation/bloc/cart_bloc.dart';
import '../../../products/presentation/bloc/catalog_bloc.dart';
import '../../../sync/presentation/bloc/sync_bloc.dart';
import '../../domain/checkout_line.dart';
import '../../domain/local_transaction.dart';
import '../../domain/payment_method.dart';
import '../../domain/transaction_repository.dart';
import '../bloc/checkout_bloc.dart';
import 'transaction_receipt.dart';

/// Membuka sheet pembayaran (DESIGN.md §17). CheckoutBloc dibuat di sini,
/// satu per sheet, sedangkan CartBloc, CatalogBloc, dan SyncBloc diteruskan lewat
/// `.value` karena rute sheet berada di luar pohon widget BlocProvider.
Future<void> showCheckoutSheet(BuildContext context) {
  final cart = context.read<CartBloc>();
  final catalog = context.read<CatalogBloc>();
  final sync = context.read<SyncBloc>();
  final repository = context.read<TransactionRepository>();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Tarik-turun mengabaikan PopScope, jadi dimatikan agar sheet tidak
    // bisa ditutup di tengah penyimpanan. Ada tombol Tutup sebagai gantinya.
    enableDrag: false,
    backgroundColor: AppColors.background,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider<CartBloc>.value(value: cart),
        BlocProvider<CatalogBloc>.value(value: catalog),
        BlocProvider<SyncBloc>.value(value: sync),
        BlocProvider<CheckoutBloc>(
          create: (_) => CheckoutBloc(repository: repository),
        ),
      ],
      child: const CheckoutSheet(),
    ),
  );
}

class CheckoutSheet extends StatelessWidget {
  const CheckoutSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<CheckoutBloc, CheckoutState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case CheckoutStatus.success:
            // Transaksi sudah tersimpan: kosongkan keranjang, dan baca ulang
            // stok dari SQLite karena stok lokal sudah berkurang. Keranjang
            // dikosongkan lebih dulu agar penyesuaian stok tidak memunculkan
            // pesan yang menyesatkan.
            context.read<CartBloc>().add(const CartCleared());
            context.read<CatalogBloc>().add(const CatalogLocalReloaded());
            // Kirim ke server di belakang layar; kasir tidak menunggunya.
            context.read<SyncBloc>().add(const SyncRequested());
          case CheckoutStatus.failure:
            // Penyebab umum: stok lokal berubah. Muat ulang agar keranjang
            // menyesuaikan diri dengan data terbaru.
            context.read<CatalogBloc>().add(const CatalogLocalReloaded());
          case CheckoutStatus.editing:
          case CheckoutStatus.submitting:
            break;
        }
      },
      child: BlocBuilder<CheckoutBloc, CheckoutState>(
        builder: (context, checkout) {
          // useSafeArea pada showModalBottomSheet tidak menghindari sisi
          // bawah; tanpa ini tombol tertimpa tombol navigasi sistem.
          return PopScope(
            canPop: !checkout.isSubmitting,
            child: SafeArea(
              top: false,
              child: checkout.isSuccess
                  ? _SuccessView(receipt: checkout.receipt!)
                  : _PaymentView(checkout: checkout),
            ),
          );
        },
      ),
    );
  }
}

class _PaymentView extends StatelessWidget {
  const _PaymentView({required this.checkout});

  final CheckoutState checkout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cart = context.watch<CartBloc>().state;
    final bloc = context.read<CheckoutBloc>();

    if (cart.isEmpty) {
      return SizedBox(
        height: 320,
        child: EmptyState(
          icon: Icons.shopping_basket_outlined,
          title: 'Keranjang masih kosong',
          message: 'Tambahkan produk untuk mulai transaksi.',
          action: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kembali'),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            top: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(child: Text('Pembayaran', style: text.headlineSmall)),
              IconButton(
                tooltip: 'Tutup',
                icon: const Icon(Icons.close),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: checkout.isSubmitting
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Total Pembayaran',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  formatRupiah(cart.totalAmount),
                  style: text.headlineMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Metode Pembayaran', style: text.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    for (final method in PaymentMethod.values) ...[
                      if (method != PaymentMethod.values.first)
                        const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _MethodTile(
                          method: method,
                          selected: checkout.method == method,
                          onTap: checkout.isSubmitting
                              ? null
                              : () => bloc.add(CheckoutMethodSelected(method)),
                        ),
                      ),
                    ],
                  ],
                ),
                if (checkout.method == PaymentMethod.qris)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      'Pastikan pembayaran QRIS sudah diterima sebelum '
                      'menekan Bayar Sekarang.',
                      style: text.bodySmall,
                    ),
                  ),
                if (checkout.error != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ErrorBanner(message: checkout.error!),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text('Ringkasan', style: text.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                for (final item in cart.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${item.quantity} × ${item.name}',
                            style: text.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          formatRupiah(item.subtotal),
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: checkout.isSubmitting
                ? null
                : () => bloc.add(
                    CheckoutSubmitted([
                      for (final item in cart.items)
                        CheckoutLine(
                          productId: item.productId,
                          name: item.name,
                          quantity: item.quantity,
                          expectedPrice: item.price,
                        ),
                    ]),
                  ),
            child: checkout.isSubmitting
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surface,
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Text('Menyimpan...'),
                    ],
                  )
                : const Text('Bayar Sekarang'),
          ),
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback? onTap;

  IconData get _icon => switch (method) {
    PaymentMethod.cash => Icons.payments_outlined,
    PaymentMethod.qris => Icons.qr_code_2,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // Pilihan ditandai dengan ikon centang, tebal garis, dan latar, bukan
    // warna saja (DESIGN.md §37).
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: selected ? AppColors.secondary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? Icons.check_circle : _icon,
                  color: selected
                      ? AppColors.secondary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(method.label, style: text.labelLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: text.bodyMedium)),
        ],
      ),
    );
  }
}

/// Transaksi sudah ada di SQLite. Server tidak dilibatkan, jadi ini bukan
/// kegagalan (DESIGN.md §18). Status sinkronisasi di bawahnya NYATA: mulai
/// "Menunggu sinkronisasi", lalu berubah mengikuti SyncBloc (menyinkronkan,
/// tersinkron, gagal, atau perlu perhatian) selagi struk masih terbuka.
class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.receipt});

  final LocalTransaction receipt;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return BlocListener<SyncBloc, SyncState>(
      // Setiap perubahan SyncBloc (hitungan, putaran mulai/selesai) bisa
      // berarti status transaksi ini bergerak: baca ulang dari SQLite.
      listener: (context, _) =>
          context.read<CheckoutBloc>().add(const CheckoutReceiptRefreshed()),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            // Umpan balik sukses singkat (DESIGN.md §38): ikon membesar sekali,
            // tanpa memantul dan tanpa menunda kasir.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.7, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: const Icon(
                Icons.check_circle,
                size: 56,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Transaksi berhasil disimpan',
              style: text.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: TransactionReceipt(transaction: receipt),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Selesai'),
            ),
          ],
        ),
      ),
    );
  }
}
