import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/app/settings_page.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/auth/domain/auth_user.dart';
import 'package:kasir_kantin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  const user = AuthUser(
    id: 1,
    name: 'Siti',
    email: 'siti@kantin.test',
    role: 'cashier',
  );
  late MockAuthBloc bloc;

  setUpAll(() => registerFallbackValue(const AuthStarted()));

  setUp(() => bloc = MockAuthBloc());

  Future<void> pumpPage(WidgetTester tester) async {
    whenListen(
      bloc,
      const Stream<AuthState>.empty(),
      initialState: const AuthAuthenticated(user),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BlocProvider<AuthBloc>.value(
            value: bloc,
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
}
