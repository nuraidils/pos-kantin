import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/core/storage/session_storage.dart';
import 'package:kasir_kantin/features/auth/data/auth_remote_data_source.dart';
import 'package:kasir_kantin/features/auth/data/auth_repository_impl.dart';
import 'package:kasir_kantin/features/auth/domain/auth_user.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements AuthRemoteDataSource {}

class MockStorage extends Mock implements SessionStorage {}

void main() {
  const user = AuthUser(
    id: 1,
    name: 'Siti',
    email: 'siti@kantin.test',
    role: 'cashier',
  );

  late MockRemote remote;
  late MockStorage storage;
  late AuthRepositoryImpl repository;

  setUp(() {
    remote = MockRemote();
    storage = MockStorage();
    repository = AuthRepositoryImpl(
      remote: remote,
      storage: storage,
      logoutTimeout: const Duration(milliseconds: 50),
    );
    when(() => storage.clear()).thenAnswer((_) async {});
    when(
      () => storage.saveSession(
        token: any(named: 'token'),
        user: any(named: 'user'),
      ),
    ).thenAnswer((_) async {});
  });

  group('login', () {
    test('menyimpan token dan profil lalu mengembalikan pengguna', () async {
      when(
        () => remote.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
          deviceName: any(named: 'deviceName'),
        ),
      ).thenAnswer((_) async => (token: '1|abc', user: user));

      final result = await repository.login(
        email: ' siti@kantin.test ',
        password: 'rahasia-123',
      );

      expect(result, user);
      verify(
        () => remote.login(
          email: 'siti@kantin.test', // di-trim
          password: 'rahasia-123',
          deviceName: any(named: 'deviceName'),
        ),
      ).called(1);
      final saved =
          verify(
                () => storage.saveSession(
                  token: '1|abc',
                  user: captureAny(named: 'user'),
                ),
              ).captured.single
              as String;
      expect(jsonDecode(saved), user.toJson());
    });

    test('gagal -> melempar galat dan TIDAK menyimpan apa pun', () async {
      when(
        () => remote.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
          deviceName: any(named: 'deviceName'),
        ),
      ).thenThrow(const UnauthorizedException());

      await expectLater(
        repository.login(email: 'a@b.c', password: 'salah'),
        throwsA(isA<UnauthorizedException>()),
      );

      verifyNever(
        () => storage.saveSession(
          token: any(named: 'token'),
          user: any(named: 'user'),
        ),
      );
    });
  });

  group('restoreSession', () {
    test(
      'mengembalikan pengguna dari penyimpanan tanpa memanggil server',
      () async {
        when(() => storage.readToken()).thenAnswer((_) async => '1|abc');
        when(
          () => storage.readUser(),
        ).thenAnswer((_) async => jsonEncode(user.toJson()));

        expect(await repository.restoreSession(), user);
        verifyZeroInteractions(remote);
      },
    );

    test('tidak ada data -> null', () async {
      when(() => storage.readToken()).thenAnswer((_) async => null);
      when(() => storage.readUser()).thenAnswer((_) async => null);

      expect(await repository.restoreSession(), isNull);
      verifyNever(() => storage.clear());
    });

    test(
      'sesi setengah jadi (token tanpa profil) -> dibersihkan, null',
      () async {
        when(() => storage.readToken()).thenAnswer((_) async => '1|abc');
        when(() => storage.readUser()).thenAnswer((_) async => null);

        expect(await repository.restoreSession(), isNull);
        verify(() => storage.clear()).called(1);
      },
    );

    test('profil rusak -> dibersihkan, null', () async {
      when(() => storage.readToken()).thenAnswer((_) async => '1|abc');
      when(() => storage.readUser()).thenAnswer((_) async => '{bukan json');

      expect(await repository.restoreSession(), isNull);
      verify(() => storage.clear()).called(1);
    });

    test('profil JSON valid tapi bentuk salah -> dibersihkan, null', () async {
      when(() => storage.readToken()).thenAnswer((_) async => '1|abc');
      when(
        () => storage.readUser(),
      ).thenAnswer((_) async => jsonEncode({'id': 'bukan-angka'}));

      expect(await repository.restoreSession(), isNull);
      verify(() => storage.clear()).called(1);
    });
  });

  group('logout', () {
    test('mencabut token di server lalu menghapus sesi lokal', () async {
      when(() => remote.logout()).thenAnswer((_) async {});

      await repository.logout();

      verify(() => remote.logout()).called(1);
      verify(() => storage.clear()).called(1);
    });

    test('offline: sesi lokal tetap dihapus dan tidak melempar', () async {
      when(() => remote.logout()).thenThrow(const NetworkException());

      await repository.logout();

      verify(() => storage.clear()).called(1);
    });

    test(
      'server menggantung: berhenti menunggu setelah timeout, sesi tetap dihapus',
      () async {
        when(() => remote.logout()).thenAnswer((_) => Completer<void>().future);

        await repository.logout();

        verify(() => storage.clear()).called(1);
      },
    );
  });

  test(
    'clearSession hanya menghapus sesi lokal, tanpa memanggil server',
    () async {
      await repository.clearSession();

      verify(() => storage.clear()).called(1);
      verifyZeroInteractions(remote);
    },
  );
}
