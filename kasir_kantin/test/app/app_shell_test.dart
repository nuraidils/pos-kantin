import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_kantin/app/app_shell.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/auth/domain/auth_user.dart';
import 'package:kasir_kantin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:kasir_kantin/features/products/domain/catalog_repository.dart';
import 'package:kasir_kantin/features/products/domain/catalog_snapshot.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:kasir_kantin/features/transactions/domain/transaction_repository.dart';

import '../support/fake_transaction_repository.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _FakeCatalogRepository implements CatalogRepository {
  @override
  Future<CatalogSnapshot> loadLocal() async =>
      const CatalogSnapshot(categories: [], products: []);

  @override
  Future<CatalogSnapshot> sync() async => throw const NetworkException();
}

void main() {
  late FakeTransactionRepository repo;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() => repo = FakeTransactionRepository());

  Future<void> pumpShell(WidgetTester tester) async {
    final auth = MockAuthBloc();
    whenListen(
      auth,
      const Stream<AuthState>.empty(),
      initialState: const AuthAuthenticated(
        AuthUser(
          id: 1,
          name: 'Siti',
          email: 'siti@kantin.test',
          role: 'cashier',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<CatalogRepository>.value(
              value: _FakeCatalogRepository(),
            ),
            RepositoryProvider<TransactionRepository>.value(value: repo),
          ],
          child: BlocProvider<AuthBloc>.value(
            value: auth,
            child: const AppShell(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder navLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('mengetuk tab Riwayat membukanya tanpa galat', (tester) async {
    repo.add('a', SyncStatus.synced);
    await pumpShell(tester);

    await tester.tap(navLabel('Riwayat'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('1 transaksi'), findsOneWidget);
    expect(find.text('INV-a'), findsOneWidget);
  });

  testWidgets('tab Riwayat kosong -> keadaan kosong yang jelas', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(navLabel('Riwayat'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Belum ada transaksi'), findsOneWidget);
  });

  testWidgets('membuka tab Riwayat membaca ulang transaksi terbaru', (
    tester,
  ) async {
    await pumpShell(tester);

    // Transaksi baru muncul di SQLite setelah AppShell dibuka.
    repo.add('b', SyncStatus.pending);
    await tester.tap(navLabel('Riwayat'));
    await tester.pumpAndSettle();

    expect(find.text('INV-b'), findsOneWidget);
    expect(find.text('Menunggu sinkronisasi'), findsWidgets);
  });

  testWidgets('pindah antar tab Kasir, Riwayat, dan Pengaturan', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(navLabel('Riwayat'));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Kasir'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
