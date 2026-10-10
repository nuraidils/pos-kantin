import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/core/network/api_client.dart';

ApiClient buildClient(
  Future<http.Response> Function(http.Request) handler, {
  String? token = 'abc123',
}) {
  return ApiClient(
    baseUrl: 'http://test/api',
    tokenProvider: () async => token,
    httpClient: MockClient(handler),
  );
}

http.Response jsonResponse(int status, Map<String, dynamic> body) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('mengirim header Accept dan Authorization Bearer', () async {
    late http.Request captured;
    final client = buildClient((request) async {
      captured = request;
      return jsonResponse(200, {'ok': true});
    });

    final result = await client.get(
      '/catalog',
      query: {'updated_since': '2026-10-08T00:00:00Z'},
    );

    expect(result['ok'], true);
    expect(captured.headers['Accept'], 'application/json');
    expect(captured.headers['Authorization'], 'Bearer abc123');
    expect(
      captured.url.queryParameters['updated_since'],
      '2026-10-08T00:00:00Z',
    );
  });

  test('tidak mengirim Authorization bila belum ada token', () async {
    late http.Request captured;
    final client = buildClient((request) async {
      captured = request;
      return jsonResponse(200, {});
    }, token: null);

    await client.post('/auth/login', body: {'email': 'a@b.c'});

    expect(captured.headers.containsKey('Authorization'), false);
  });

  test('401 -> UnauthorizedException', () {
    final client = buildClient(
      (_) async =>
          jsonResponse(401, {'message': 'Email atau kata sandi salah.'}),
    );

    expect(
      client.post('/auth/login'),
      throwsA(
        isA<UnauthorizedException>().having(
          (e) => e.message,
          'message',
          'Email atau kata sandi salah.',
        ),
      ),
    );
  });

  test('403 -> ForbiddenException', () {
    final client = buildClient((_) async => jsonResponse(403, {}));
    expect(client.get('/catalog'), throwsA(isA<ForbiddenException>()));
  });

  test('409 -> ConflictException membawa body', () {
    final client = buildClient(
      (_) async => jsonResponse(409, {
        'message': 'Stok tidak cukup.',
        'code': 'insufficient_stock',
      }),
    );

    expect(
      client.post('/transactions'),
      throwsA(
        isA<ConflictException>().having(
          (e) => e.body['code'],
          'code',
          'insufficient_stock',
        ),
      ),
    );
  });

  test('422 -> ValidationException membawa detail field', () {
    final client = buildClient(
      (_) async => jsonResponse(422, {
        'message': 'Data tidak valid.',
        'errors': {
          'email': ['Format email tidak valid.'],
        },
      }),
    );

    expect(
      client.post('/auth/login'),
      throwsA(
        isA<ValidationException>().having((e) => e.errors['email'], 'email', [
          'Format email tidak valid.',
        ]),
      ),
    );
  });

  test('500 -> ServerException (dapat dicoba ulang)', () async {
    final client = buildClient(
      (_) async => http.Response('<html>error</html>', 500),
    );

    await expectLater(client.get('/catalog'), throwsA(isA<ServerException>()));
    expect(const ServerException().isRetryable, true);
  });

  test('tanpa koneksi -> NetworkException (dapat dicoba ulang)', () async {
    final client = buildClient(
      (_) async => throw const SocketException('tidak ada jaringan'),
    );

    await expectLater(client.get('/catalog'), throwsA(isA<NetworkException>()));
    expect(const NetworkException().isRetryable, true);
  });

  test(
    'ValidationException dan ConflictException tidak dapat dicoba ulang',
    () {
      expect(const ValidationException('x').isRetryable, false);
      expect(const ConflictException('x').isRetryable, false);
    },
  );
}
