import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/app/settings_page.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/auth/domain/auth_user.dart';
import 'package:kasir_kantin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:kasir_kantin/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockSyncBloc extends MockBloc<SyncEvent, SyncState> implements SyncBloc {}

void main() {
  const user = AuthUser(
    id: 1,
    name: 'Siti',
    email: 'siti@kantin.test',
    role: 'cashier',
  );
  late MockAuthBloc bloc;
  late MockSyncBloc syncBloc;

  setUpAll(() => registerFallbackValue(const AuthStarted()));

  setUp(() {
    bloc = MockAuthBloc();
    syncBloc = MockSyncBloc();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    SyncState sync = const SyncState(),
  }) async {
    whenListen(syncBloc, const Stream<SyncState>.empty(), initialState: sync);
    whenListen(
      bloc,
      const Stream<AuthState>.empty(),
      initialState: const AuthAuthenticated(user),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: bloc),
              BlocProvider<SyncBloc>.value(value: syncBloc),
            ],
            child: const SettingsPage(),
          ),
        ),
      ),
    );
  }

  Finder dialogButton(String label) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

  testWidgets('menampilkan nama, email, dan peran dalam bahasa Indonesia', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('Siti'), findsOneWidget);
    expect(find.text('siti@kantin.test'), findsOneWidget);
    expect(find.text('Kasir'), findsOneWidget);
  });

  testWidgets('Keluar -> konfirmasi -> mengirim AuthLogoutRequested', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(find.text('Keluar dari akun?'), findsOneWidget);
    verifyNever(() => bloc.add(any()));

    await tester.tap(dialogButton('Keluar'));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const AuthLogoutRequested())).called(1);
  });

  testWidgets('Batal pada konfirmasi tidak keluar', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('Batal'));
    await tester.pumpAndSettle();

    verifyNever(() => bloc.add(any()));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('tanpa transaksi tertunda -> konfirmasi biasa', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('belum tersinkron'), findsNothing);
    expect(find.textContaining('perlu perhatian'), findsNothing);
    expect(
      find.textContaining('Data di perangkat ini tidak dihapus.'),
      findsOneWidget,
    );
  });

  testWidgets('ada transaksi belum tersinkron -> diberi tahu sebelum keluar', (
    tester,
  ) async {
    await pumpPage(tester, sync: const SyncState(unsyncedCount: 3));

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Masih ada 3 transaksi yang belum tersinkron.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('dikirim setelah Anda masuk kembali'),
      findsOneWidget,
    );
    // Tetap bisa keluar: transaksi aman di perangkat.
    await tester.tap(dialogButton('Keluar'));
    await tester.pumpAndSettle();
    verify(() => bloc.add(const AuthLogoutRequested())).called(1);
  });

  testWidgets('ada konflik -> diberi tahu bahwa transaksinya tetap tersimpan', (
    tester,
  ) async {
    await pumpPage(tester, sync: const SyncState(conflictCount: 2));

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('2 transaksi perlu perhatian dan tetap tersimpan'),
      findsOneWidget,
    );
    expect(find.textContaining('belum tersinkron'), findsNothing);
  });
}
