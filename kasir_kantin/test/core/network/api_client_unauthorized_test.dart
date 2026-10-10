import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/core/network/api_client.dart';

ApiClient buildClient(int status) {
  return ApiClient(
    baseUrl: 'http://test/api',
    tokenProvider: () async => 'abc123',
    httpClient: MockClient((_) async => http.Response('{}', status)),
  );
}

void main() {
  test('401 pada permintaan biasa memancarkan event unauthorized', () async {
    final client = buildClient(401);
    final event = client.unauthorized.first.timeout(const Duration(seconds: 1));

    await expectLater(
      client.get('/catalog'),
      throwsA(isA<UnauthorizedException>()),
    );

    await event; // selesai tanpa timeout = event terpancar
  });

  test('401 dengan reportUnauthorized:false tidak memancarkan event', () async {
    final client = buildClient(401);
    final events = <void>[];
    final sub = client.unauthorized.listen(events.add);

    await expectLater(
      client.post('/auth/login', reportUnauthorized: false),
      throwsA(isA<UnauthorizedException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
    await sub.cancel();
  });

  test('status selain 401 tidak memancarkan event', () async {
    final client = buildClient(500);
    final events = <void>[];
    final sub = client.unauthorized.listen(events.add);

    await expectLater(client.get('/catalog'), throwsA(isA<ServerException>()));
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
    await sub.cancel();
  });
}
