import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/widgets/empty_state.dart';
import '../features/cart/presentation/bloc/cart_bloc.dart';
import '../features/products/domain/catalog_repository.dart';
import '../features/products/presentation/bloc/catalog_bloc.dart';
import '../features/products/presentation/pages/catalog_page.dart';
import 'settings_page.dart';

/// Kerangka navigasi mobile: Kasir | Riwayat | Pengaturan (DESIGN.md §25,
/// AGENTS.md §23). Bukan salinan sidebar dashboard.
/// Tab Kasir = katalog + keranjang (tahap 8–9); tab Riwayat diganti di
/// tahap berikutnya.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0; // state tampilan saja, bukan logika bisnis

  static const _pages = <Widget>[
    CatalogPage(),
    EmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'Belum ada transaksi',
      message: 'Riwayat transaksi akan tampil di sini.',
    ),
    SettingsPage(),
  ];

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
        child: Scaffold(
          body: SafeArea(
            child: IndexedStack(index: _index, children: _pages),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
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
    );
  }
}
