import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/app/app_shell.dart';
import 'package:kasir_kantin/app/auth_gate.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/auth/domain/auth_user.dart';
import 'package:kasir_kantin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:kasir_kantin/features/auth/presentation/pages/login_page.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  late MockAuthBloc bloc;

  setUp(() => bloc = MockAuthBloc());

  Future<void> pumpGate(WidgetTester tester, AuthState state) async {
    whenListen(bloc, const Stream<AuthState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BlocProvider<AuthBloc>.value(value: bloc, child: const AuthGate()),
      ),
    );
  }

  testWidgets('AuthUnknown -> indikator memuat', (tester) async {
    await pumpGate(tester, const AuthUnknown());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('belum masuk -> halaman masuk', (tester) async {
    await pumpGate(tester, const AuthUnauthenticated());

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('sudah masuk -> kerangka aplikasi', (tester) async {
    await pumpGate(
      tester,
      const AuthAuthenticated(
        AuthUser(id: 1, name: 'Siti', email: 'siti@kantin.test', role: 'cashier'),
      ),
    );

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });
}
