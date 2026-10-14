import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/cart/presentation/bloc/cart_bloc.dart';
import '../features/products/domain/catalog_repository.dart';
import '../features/products/presentation/bloc/catalog_bloc.dart';
import '../features/products/presentation/pages/catalog_page.dart';
import '../features/sync/presentation/bloc/sync_bloc.dart';
import '../features/sync/presentation/widgets/sync_scheduler.dart';
import '../features/sync/presentation/widgets/sync_status_banner.dart';
import '../features/transactions/domain/transaction_repository.dart';
import '../features/transactions/presentation/bloc/history_bloc.dart';
import '../features/transactions/presentation/pages/history_page.dart';
import 'settings_page.dart';

/// Kerangka navigasi mobile: Kasir | Riwayat | Pengaturan (DESIGN.md §25,
/// AGENTS.md §23). Bukan salinan sidebar dashboard.
/// Tab Kasir = katalog + keranjang (tahap 8–9); tab Riwayat = semua transaksi
/// lokal dengan status sinkronisasinya (tahap 15). SyncBloc (tahap 13) ikut
/// hidup selama sesi masuk dan mengirim transaksi yang menunggu.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0; // state tampilan saja, bukan logika bisnis

  static const _pages = <Widget>[CatalogPage(), HistoryPage(), SettingsPage()];

  @override
  Widget build(BuildContext context) {
    // CatalogBloc dan CartBloc hidup selama sesi masuk (AppShell hanya ada
    // saat masuk), dan IndexedStack menjaga filter, pencarian, dan isi
    // keranjang tetap saat pindah tab.
    return MultiBlocProvider(
      providers: [
        BlocProvider<CatalogBloc>(
          create: (context) =>
              CatalogBloc(repository: context.read<CatalogRepository>())
                ..add(const CatalogStarted()),
        ),
        BlocProvider<CartBloc>(create: (_) => CartBloc()),
        BlocProvider<HistoryBloc>(
          create: (context) =>
              HistoryBloc(repository: context.read<TransactionRepository>())
                ..add(const HistoryLoaded()),
        ),
        BlocProvider<SyncBloc>(
          create: (context) =>
              SyncBloc(repository: context.read<TransactionRepository>())
                ..add(const SyncStarted()),
        ),
      ],
      child: MultiBlocListener(
        listeners: [
          // Katalog berubah (mis. selesai sinkronisasi) -> samakan harga dan
          // stok isi keranjang. Penghubung antar-BLoC ada di sini, bukan di
          // dalam BLoC.
          BlocListener<CatalogBloc, CatalogState>(
            listenWhen: (previous, current) =>
                previous.products != current.products,
            listener: (context, state) => context.read<CartBloc>().add(
              CartCatalogRefreshed(state.products),
            ),
          ),
          // Pengiriman mengubah data lokal (ada yang tersinkron atau menjadi
          // konflik, dan stok lokal bisa dikembalikan): baca ulang SQLite lalu
          // tarik katalog dari server. Urutan ini juga membetulkan proyeksi
          // stok bila tarikan katalog sempat bertepatan dengan pengiriman.
          BlocListener<SyncBloc, SyncState>(
            listenWhen: (previous, current) =>
                previous.changeRevision != current.changeRevision,
            listener: (context, state) {
              context.read<CatalogBloc>()
                ..add(const CatalogLocalReloaded())
                ..add(const CatalogRefreshed());
            },
          ),
          // Status transaksi bergerak (menunggu -> menyinkronkan -> tersinkron,
          // gagal, konflik) dan transaksi baru ikut dihitung: Riwayat dibaca
          // ulang dari SQLite setiap SyncBloc berubah.
          BlocListener<SyncBloc, SyncState>(
            listener: (context, state) =>
                context.read<HistoryBloc>().add(const HistoryLoaded()),
          ),
          BlocListener<CartBloc, CartState>(
            listenWhen: (previous, current) =>
                previous.noticeCount != current.noticeCount,
            listener: (context, state) {
              final notice = state.notice;
              if (notice == null) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(notice)));
            },
          ),
        ],
        child: SyncScheduler(
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const SyncStatusBanner(),
                  Expanded(
                    child: IndexedStack(index: _index, children: _pages),
                  ),
                ],
              ),
            ),
            // Builder: `context` milik State ini berada DI ATAS MultiBlocProvider
            // di build(), jadi tidak bisa membaca HistoryBloc. Context dari
            // Builder berada di bawahnya.
            bottomNavigationBar: Builder(
              builder: (context) => NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) {
                  // Membuka Riwayat selalu menampilkan data terbaru.
                  if (i == 1) {
                    context.read<HistoryBloc>().add(const HistoryLoaded());
                  }
                  setState(() => _index = i);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Kasir',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: 'Riwayat',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Pengaturan',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
