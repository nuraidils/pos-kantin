import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:kasir_kantin/features/auth/presentation/pages/login_page.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  late MockAuthBloc bloc;

  setUpAll(() => registerFallbackValue(const AuthStarted()));

  setUp(() => bloc = MockAuthBloc());

  Future<void> pumpPage(WidgetTester tester, AuthState state) async {
    whenListen(bloc, const Stream<AuthState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: const LoginPage(),
        ),
      ),
    );
  }

  testWidgets('menampilkan kolom email, kata sandi, dan tombol Masuk', (
    tester,
  ) async {
    await pumpPage(tester, const AuthUnauthenticated());

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Kata sandi'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Masuk'), findsOneWidget);
  });

  testWidgets('form kosong -> pesan validasi dan tidak mengirim event', (
    tester,
  ) async {
    await pumpPage(tester, const AuthUnauthenticated());

    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pump();

    expect(find.text('Email wajib diisi.'), findsOneWidget);
    expect(find.text('Kata sandi wajib diisi.'), findsOneWidget);
    verifyNever(() => bloc.add(any()));
  });

  testWidgets('email tidak valid -> pesan format, tidak mengirim event', (
    tester,
  ) async {
    await pumpPage(tester, const AuthUnauthenticated());

    await tester.enterText(find.byType(TextFormField).at(0), 'kasir');
    await tester.enterText(find.byType(TextFormField).at(1), 'rahasia-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pump();

    expect(find.text('Format email tidak valid.'), findsOneWidget);
    verifyNever(() => bloc.add(any()));
  });

  testWidgets('isian valid -> mengirim AuthLoginSubmitted', (tester) async {
    await pumpPage(tester, const AuthUnauthenticated());

    await tester.enterText(
      find.byType(TextFormField).at(0),
      ' kasir@kantin.test ',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'rahasia-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pump();

    verify(
      () => bloc.add(
        const AuthLoginSubmitted(
          email: 'kasir@kantin.test',
          password: 'rahasia-123',
        ),
      ),
    ).called(1);
  });

  testWidgets('saat memproses -> tombol nonaktif dan teks "Memproses..."', (
    tester,
  ) async {
    await pumpPage(tester, const AuthInProgress());

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('Memproses...'), findsOneWidget);
  });

  testWidgets('gagal -> menampilkan pesan dan detail kolom', (tester) async {
    await pumpPage(
      tester,
      const AuthFailure(
        message: 'Periksa kembali data yang Anda isi.',
        fieldErrors: {
          'email': ['Format email tidak valid.'],
        },
      ),
    );

    expect(find.text('Periksa kembali data yang Anda isi.'), findsOneWidget);
    expect(find.text('Format email tidak valid.'), findsOneWidget);
    expect(
      find.byIcon(Icons.error_outline),
      findsOneWidget,
    ); // bukan warna saja
  });

  testWidgets('sesi berakhir -> menampilkan pemberitahuan', (tester) async {
    await pumpPage(
      tester,
      const AuthUnauthenticated(
        message: 'Sesi berakhir. Silakan masuk kembali.',
      ),
    );

    expect(find.text('Sesi berakhir. Silakan masuk kembali.'), findsOneWidget);
  });

  testWidgets('tombol mata menampilkan/menyembunyikan kata sandi', (
    tester,
  ) async {
    await pumpPage(tester, const AuthUnauthenticated());

    bool obscured() => tester
        .widget<EditableText>(find.byType(EditableText).at(1))
        .obscureText;

    expect(obscured(), isTrue);
    await tester.tap(find.byTooltip('Tampilkan kata sandi'));
    await tester.pump();
    expect(obscured(), isFalse);
    expect(find.byTooltip('Sembunyikan kata sandi'), findsOneWidget);
  });
}
