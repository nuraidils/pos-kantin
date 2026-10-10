import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/core/network/api_client.dart';
import 'package:kasir_kantin/features/auth/data/auth_remote_data_source.dart';
import 'package:kasir_kantin/features/auth/domain/auth_user.dart';

http.Response jsonResponse(int status, Map<String, dynamic> body) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

ApiClient clientWith(Future<http.Response> Function(http.Request) handler) {
  return ApiClient(
    baseUrl: 'http://test/api',
    tokenProvider: () async => null,
    httpClient: MockClient(handler),
  );
}

void main() {
  const userJson = {
    'id': 7,
    'name': 'Siti',
    'email': 'siti@kantin.test',
    'role': 'cashier',
  };

  test('login mengirim kredensial dan mem-parsing token + pengguna', () async {
    late http.Request captured;
    final remote = AuthRemoteDataSource(
      clientWith((request) async {
        captured = request;
        return jsonResponse(200, {
          'data': {'token': '1|abc', 'user': userJson},
        });
      }),
    );

    final result = await remote.login(
      email: 'siti@kantin.test',
      password: 'rahasia-123',
      deviceName: 'kasir-mobile',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/auth/login');
    expect(jsonDecode(captured.body), {
      'email': 'siti@kantin.test',
      'password': 'rahasia-123',
      'device_name': 'kasir-mobile',
    });
    expect(result.token, '1|abc');
    expect(result.user, AuthUser.fromJson(userJson));
  });

  test(
    'kredensial salah -> UnauthorizedException dan BUKAN event sesi berakhir',
    () async {
      final client = clientWith(
        (_) async =>
            jsonResponse(401, {'message': 'Email atau kata sandi salah.'}),
      );
      final events = <void>[];
      final sub = client.unauthorized.listen(events.add);

      await expectLater(
        AuthRemoteDataSource(
          client,
        ).login(email: 'a@b.c', password: 'x', deviceName: 'd'),
        throwsA(isA<UnauthorizedException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await sub.cancel();
    },
  );

  test('akun owner -> ForbiddenException dengan pesan dari server', () async {
    final remote = AuthRemoteDataSource(
      clientWith(
        (_) async => jsonResponse(403, {'message': 'Gunakan dashboard web.'}),
      ),
    );

    await expectLater(
      remote.login(email: 'o@b.c', password: 'x', deviceName: 'd'),
      throwsA(
        isA<ForbiddenException>().having(
          (e) => e.message,
          'message',
          'Gunakan dashboard web.',
        ),
      ),
    );
  });

  test(
    'respons 200 dengan bentuk tidak sesuai -> UnexpectedApiException',
    () async {
      final remote = AuthRemoteDataSource(
        clientWith((_) async => jsonResponse(200, {'data': {}})),
      );

      await expectLater(
        remote.login(email: 'a@b.c', password: 'x', deviceName: 'd'),
        throwsA(isA<UnexpectedApiException>()),
      );
    },
  );

  test('logout memanggil POST /auth/logout dan menerima 204', () async {
    late http.Request captured;
    final remote = AuthRemoteDataSource(
      clientWith((request) async {
        captured = request;
        return http.Response('', 204);
      }),
    );

    await remote.logout();

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/auth/logout');
  });
}
