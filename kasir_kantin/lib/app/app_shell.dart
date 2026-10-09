import 'package:flutter/material.dart';

import '../core/widgets/empty_state.dart';
import 'settings_page.dart';

/// Kerangka navigasi mobile: Kasir | Riwayat | Pengaturan (DESIGN.md §25,
/// AGENTS.md §23). Bukan salinan sidebar dashboard.
/// Isi tab Kasir dan Riwayat diganti oleh fitur masing-masing di tahap berikutnya.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0; // state tampilan saja, bukan logika bisnis

  static const _pages = <Widget>[
    EmptyState(
      icon: Icons.storefront_outlined,
      title: 'Belum ada produk',
      message: 'Produk akan tampil di sini setelah katalog disinkronkan.',
    ),
    EmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'Belum ada transaksi',
      message: 'Riwayat transaksi akan tampil di sini.',
    ),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: _pages)),
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
    );
  }
}
