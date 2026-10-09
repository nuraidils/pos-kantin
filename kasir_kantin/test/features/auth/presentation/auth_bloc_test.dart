import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/features/auth/domain/auth_repository.dart';
import 'package:kasir_kantin/features/auth/domain/auth_user.dart';
import 'package:kasir_kantin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  const user = AuthUser(id: 1, name: 'Siti', email: 'siti@kantin.test', role: 'cashier');
  const login = AuthLoginSubmitted(email: 'siti@kantin.test', password: 'rahasia-123');

  late MockAuthRepository repository;

  setUp(() {
    repository = MockAuthRepository();
  });

  void stubLoginThrows(Object error) {
    when(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(error);
  }

  test('state awal adalah AuthUnknown', () {
    expect(AuthBloc(repository: repository).state, const AuthUnknown());
  });

  group('AuthStarted', () {
    blocTest<AuthBloc, AuthState>(
      'memulihkan sesi tersimpan (bekerja offline)',
      build: () {
        when(() => repository.restoreSession()).thenAnswer((_) async => user);
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const AuthStarted()),
      expect: () => [const AuthAuthenticated(user)],
    );

    blocTest<AuthBloc, AuthState>(
      'tanpa sesi -> belum masuk',
      build: () {
        when(() => repository.restoreSession()).thenAnswer((_) async => null);
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const AuthStarted()),
      expect: () => [const AuthUnauthenticated()],
    );

    blocTest<AuthBloc, AuthState>(
      'penyimpanan gagal dibaca -> belum masuk, tidak macet',
      build: () {
        when(() => repository.restoreSession()).thenThrow(Exception('keystore'));
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const AuthStarted()),
      expect: () => [const AuthUnauthenticated()],
    );
  });

  group('AuthLoginSubmitted', () {
    blocTest<AuthBloc, AuthState>(
      'kredensial benar -> InProgress lalu Authenticated',
      build: () {
        when(() => repository.login(
              email: any(named: 'email'),
              password: any(named: 'password'),
            )).thenAnswer((_) async => user);
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(login),
      expect: () => [const AuthInProgress(), const AuthAuthenticated(user)],
      verify: (_) => verify(() => repository.login(
            email: 'siti@kantin.test',
            password: 'rahasia-123',
          )).called(1),
    );

    blocTest<AuthBloc, AuthState>(
      'kredensial salah -> pesan tetap, tanpa menyebut "sesi berakhir"',
      build: () {
        stubLoginThrows(const UnauthorizedException());
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(login),
      expect: () => [
        const AuthInProgress(),
        const AuthFailure(message: 'Email atau kata sandi salah.'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'role tidak diizinkan (owner) -> pesan dari server',
      build: () {
        stubLoginThrows(const ForbiddenException('Gunakan dashboard web.'));
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(login),
      expect: () => [
        const AuthInProgress(),
        const AuthFailure(message: 'Gunakan dashboard web.'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'tanpa internet -> pesan menyebut koneksi internet',
      build: () {
        stubLoginThrows(const NetworkException());
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(login),
      expect: () => [
        const AuthInProgress(),
        isA<AuthFailure>().having((s) => s.message, 'message', contains('internet')),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'validasi server (422) -> membawa galat per kolom',
      build: () {
        stubLoginThrows(const ValidationException('x', errors: {
          'email': ['Format email tidak valid.'],
        }));
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(login),
      expect: () => [
        const AuthInProgress(),
        const AuthFailure(
          message: 'Periksa kembali data yang Anda isi.',
          fieldErrors: {
            'email': ['Format email tidak valid.'],
          },
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'galat server (5xx) -> pesan umum, tanpa detail teknis',
      build: () {
        stubLoginThrows(const ServerException());
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(login),
      expect: () => [
        const AuthInProgress(),
        const AuthFailure(message: 'Terjadi masalah pada server. Coba lagi beberapa saat.'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'galat tak terduga -> pesan umum, tidak macet di InProgress',
      build: () {
        stubLoginThrows(StateError('bug'));
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc.add(login),
      expect: () => [
        const AuthInProgress(),
        const AuthFailure(message: 'Terjadi kesalahan yang tidak terduga. Coba lagi.'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'kirim ganda saat sedang memproses diabaikan',
      build: () {
        when(() => repository.login(
              email: any(named: 'email'),
              password: any(named: 'password'),
            )).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return user;
        });
        return AuthBloc(repository: repository);
      },
      act: (bloc) => bloc
        ..add(login)
        ..add(login),
      wait: const Duration(milliseconds: 50),
      expect: () => [const AuthInProgress(), const AuthAuthenticated(user)],
      verify: (_) => verify(() => repository.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).called(1),
    );
  });

  group('AuthLogoutRequested', () {
    blocTest<AuthBloc, AuthState>(
      'keluar -> belum masuk dan repository.logout dipanggil',
      build: () {
        when(() => repository.logout()).thenAnswer((_) async {});
        return AuthBloc(repository: repository);
      },
      seed: () => const AuthAuthenticated(user),
      act: (bloc) => bloc.add(const AuthLogoutRequested()),
      expect: () => [const AuthUnauthenticated()],
      verify: (_) => verify(() => repository.logout()).called(1),
    );
  });

  group('sesi berakhir', () {
    blocTest<AuthBloc, AuthState>(
      'saat masuk -> hapus sesi lokal tanpa memanggil API keluar, tampilkan pesan',
      build: () {
        when(() => repository.clearSession()).thenAnswer((_) async {});
        return AuthBloc(repository: repository);
      },
      seed: () => const AuthAuthenticated(user),
      act: (bloc) => bloc.add(const AuthSessionExpired()),
      expect: () => [
        const AuthUnauthenticated(message: 'Sesi berakhir. Silakan masuk kembali.'),
      ],
      verify: (_) {
        verify(() => repository.clearSession()).called(1);
        verifyNever(() => repository.logout());
      },
    );

    blocTest<AuthBloc, AuthState>(
      'saat belum masuk -> diabaikan',
      build: () => AuthBloc(repository: repository),
      seed: () => const AuthUnauthenticated(),
      act: (bloc) => bloc.add(const AuthSessionExpired()),
      expect: () => <AuthState>[],
    );

    late StreamController<void> expired;

    setUp(() => expired = StreamController<void>.broadcast());
    tearDown(() => expired.close());

    blocTest<AuthBloc, AuthState>(
      'event 401 dari ApiClient mengakhiri sesi',
      build: () {
        when(() => repository.clearSession()).thenAnswer((_) async {});
        return AuthBloc(repository: repository, sessionExpired: expired.stream);
      },
      seed: () => const AuthAuthenticated(user),
      act: (_) => expired.add(null),
      expect: () => [
        const AuthUnauthenticated(message: 'Sesi berakhir. Silakan masuk kembali.'),
      ],
    );
  });
}
