import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:kasir_kantin/features/transactions/presentation/bloc/history_bloc.dart';
import 'package:kasir_kantin/features/transactions/presentation/pages/history_page.dart';

import '../../../support/fake_transaction_repository.dart';

void main() {
  late FakeTransactionRepository repo;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() {
    repo = FakeTransactionRepository()
      ..add('a', SyncStatus.synced)
      ..add('b', SyncStatus.conflict)
      ..add('c', SyncStatus.pending)
      ..add('d', SyncStatus.failed)
      ..add('e', SyncStatus.syncing)
      ..messages['b'] =
          'Transaksi tidak dapat disinkronkan karena stok di server tidak '
          'mencukupi. Kopi Susu (diminta 4, tersedia 2).';
  });

  Widget wrap(HistoryBloc bloc) => MaterialApp(
    theme: AppTheme.light,
    home: BlocProvider<HistoryBloc>.value(
      value: bloc,
      child: const Scaffold(body: HistoryPage()),
    ),
  );

  Future<HistoryBloc> pumpPage(WidgetTester tester) async {
    // Layar tinggi agar semua kartu langsung terbangun oleh ListView.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = HistoryBloc(repository: repo)..add(const HistoryLoaded());
    addTearDown(bloc.close);
    await tester.pumpWidget(wrap(bloc));
    await tester.pumpAndSettle();
    return bloc;
  }

  testWidgets('menampilkan semua transaksi dengan status masing-masing', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('5 transaksi'), findsOneWidget);
    for (final uuid in ['a', 'b', 'c', 'd', 'e']) {
      expect(find.byKey(ValueKey('history-$uuid')), findsOneWidget);
    }
    expect(find.text('Tersinkron'), findsOneWidget);
    expect(find.text('Perlu perhatian'), findsOneWidget);
    expect(find.text('Menunggu sinkronisasi'), findsOneWidget);
    expect(find.text('Gagal disinkronkan'), findsOneWidget);
    expect(find.text('Menyinkronkan...'), findsOneWidget);
    expect(find.text('Rp10.000'), findsWidgets);
  });

  testWidgets('terbaru di atas', (tester) async {
    await pumpPage(tester);

    final top = tester.getTopLeft(find.byKey(const ValueKey('history-e'))).dy;
    final bottom = tester
        .getTopLeft(find.byKey(const ValueKey('history-a')))
        .dy;
    expect(top, lessThan(bottom));
  });

  testWidgets('tanpa transaksi -> keadaan kosong yang jelas', (tester) async {
    repo.statuses.clear();
    await pumpPage(tester);

    expect(find.text('Belum ada transaksi'), findsOneWidget);
    expect(
      find.text('Transaksi yang sudah dibayar tampil di sini.'),
      findsOneWidget,
    );
  });

  testWidgets('gagal membaca -> pesan dan tombol Coba Lagi', (tester) async {
    repo.allThrow = true;
    await pumpPage(tester);

    expect(find.text('Riwayat tidak dapat dibaca. Coba lagi.'), findsOneWidget);

    repo.allThrow = false;
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(find.text('5 transaksi'), findsOneWidget);
  });

  testWidgets('ketuk transaksi konflik -> detail menampilkan alasan', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('history-b')));
    await tester.pumpAndSettle();

    expect(find.text('Detail Transaksi'), findsOneWidget);
    expect(find.text('INV-b'), findsWidgets);
    expect(find.textContaining('diminta 4, tersedia 2'), findsOneWidget);
    expect(find.textContaining('Transaksi tetap tersimpan'), findsOneWidget);
    expect(find.text('1 × Kopi Susu'), findsWidgets);
  });

  testWidgets('detail ikut berubah saat status berubah', (tester) async {
    final bloc = await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('history-c')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('status-chip-pending')), findsNWidgets(2));

    repo.statuses['c'] = SyncStatus.synced;
    bloc.add(const HistoryLoaded());
    await tester.pumpAndSettle();

    // Transaksi 'a' sudah synced sejak awal, ditambah 'c' di kartu riwayat dan
    // 'c' di detail.
    expect(find.byKey(const ValueKey('status-chip-synced')), findsNWidgets(3));
    expect(find.byKey(const ValueKey('status-chip-pending')), findsNothing);
  });

  testWidgets('detail dapat ditutup', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('history-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();

    expect(find.text('Detail Transaksi'), findsNothing);
  });
}
