import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/products/presentation/bloc/catalog_bloc.dart';
import 'package:kasir_kantin/features/sync/presentation/bloc/conflict_bloc.dart';
import 'package:kasir_kantin/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:kasir_kantin/features/sync/presentation/pages/conflict_page.dart';
import 'package:kasir_kantin/features/sync/presentation/widgets/sync_status_banner.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:kasir_kantin/features/transactions/domain/transaction_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fake_transaction_repository.dart';

class MockSyncBloc extends MockBloc<SyncEvent, SyncState> implements SyncBloc {}

class MockCatalogBloc extends MockBloc<CatalogEvent, CatalogState>
    implements CatalogBloc {}

void main() {
  late FakeTransactionRepository repo;
  late MockSyncBloc sync;
  late MockCatalogBloc catalog;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    registerFallbackValue(const SyncRequested());
    registerFallbackValue(const CatalogLocalReloaded());
  });

  setUp(() {
    repo = FakeTransactionRepository()
      ..add('a', SyncStatus.conflict)
      ..messages['a'] =
          'Transaksi tidak dapat disinkronkan karena stok di server tidak '
          'mencukupi. Kopi Susu (diminta 4, tersedia 2).';
    sync = MockSyncBloc();
    catalog = MockCatalogBloc();
    whenListen(
      sync,
      const Stream<SyncState>.empty(),
      initialState: const SyncState(),
    );
    whenListen(
      catalog,
      const Stream<CatalogState>.empty(),
      initialState: const CatalogState(),
    );
  });

  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<SyncBloc>.value(value: sync),
        BlocProvider<CatalogBloc>.value(value: catalog),
        BlocProvider<ConflictBloc>(
          create: (_) =>
              ConflictBloc(repository: repo)..add(const ConflictLoaded()),
        ),
      ],
      child: child,
    ),
  );

  testWidgets('menampilkan alasan, item, dan tombol Kirim Ulang', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const ConflictPage()));
    await tester.pumpAndSettle();

    expect(find.text('Perlu Perhatian'), findsOneWidget); // judul halaman
    expect(find.text('INV-a'), findsOneWidget);
    expect(
      find.textContaining('stok di server tidak mencukupi'),
      findsOneWidget,
    );
    expect(find.textContaining('diminta 4, tersedia 2'), findsOneWidget);
    expect(find.text('1 × Kopi Susu'), findsOneWidget);
    expect(find.text('Kirim Ulang'), findsOneWidget);
  });

  testWidgets('tanpa konflik -> keadaan kosong yang jelas', (tester) async {
    repo.statuses.clear();
    await tester.pumpWidget(wrap(const ConflictPage()));
    await tester.pumpAndSettle();

    expect(
      find.text('Tidak ada transaksi yang perlu perhatian'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Kirim Ulang: kembali pending, katalog dibaca ulang, sinkronisasi diminta',
    (tester) async {
      await tester.pumpWidget(wrap(const ConflictPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kirim Ulang'));
      await tester.pumpAndSettle();

      expect(repo.statuses['a'], SyncStatus.pending);
      expect(find.text('Kirim Ulang'), findsNothing);
      verify(
        () => catalog.add(any(that: isA<CatalogLocalReloaded>())),
      ).called(1);
      verify(() => sync.add(any(that: isA<SyncRequested>()))).called(1);
    },
  );

  testWidgets('banner konflik dapat diketuk dan membuka halaman', (
    tester,
  ) async {
    whenListen(
      sync,
      const Stream<SyncState>.empty(),
      initialState: const SyncState(conflictCount: 1),
    );
    await tester.pumpWidget(
      RepositoryProvider<TransactionRepository>.value(
        value: repo,
        child: MaterialApp(
          theme: AppTheme.light,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SyncBloc>.value(value: sync),
              BlocProvider<CatalogBloc>.value(value: catalog),
            ],
            child: const Scaffold(body: SyncStatusBanner()),
          ),
        ),
      ),
    );

    await tester.tap(find.text('1 transaksi perlu perhatian'));
    await tester.pumpAndSettle();

    expect(find.text('Perlu Perhatian'), findsOneWidget);
    expect(find.text('INV-a'), findsOneWidget);
  });
}
