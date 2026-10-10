import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/core/network/api_client.dart';
import 'package:kasir_kantin/features/products/data/catalog_remote_data_source.dart';

http.Response jsonResponse(int status, Map<String, dynamic> body) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

ApiClient clientWith(Future<http.Response> Function(http.Request) handler) {
  return ApiClient(
    baseUrl: 'http://test/api',
    tokenProvider: () async => 'abc123',
    httpClient: MockClient(handler),
  );
}

Map<String, dynamic> category(int id, {String? deletedAt}) => {
  'id': id,
  'name': 'Kategori $id',
  'slug': 'kategori-$id',
  'updated_at': '2026-10-09T10:00:00+00:00',
  'deleted_at': deletedAt,
};

Map<String, dynamic> product(int id, {String? deletedAt, bool active = true}) =>
    {
      'id': id,
      'category_id': 1,
      'name': 'Produk $id',
      'price': 10000,
      'stock': 7,
      'is_active': active,
      'image_url': null,
      'updated_at': '2026-10-09T10:00:00+00:00',
      'deleted_at': deletedAt,
    };

Map<String, dynamic> body({
  List<Map<String, dynamic>> categories = const [],
  List<Map<String, dynamic>> products = const [],
  bool fullSync = true,
}) => {
  'data': {'categories': categories, 'products': products},
  'meta': {'server_time': '2026-10-09T10:05:00+00:00', 'full_sync': fullSync},
};

void main() {
  test(
    'sinkronisasi penuh: tanpa updated_since, memakai token, mem-parsing data',
    () async {
      late http.Request captured;
      final remote = CatalogRemoteDataSource(
        clientWith((request) async {
          captured = request;
          return jsonResponse(
            200,
            body(
              categories: [category(1)],
              products: [product(1), product(2, active: false)],
            ),
          );
        }),
      );

      final changes = await remote.fetch();

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/catalog');
      expect(captured.url.queryParameters, isEmpty);
      expect(captured.headers['Authorization'], 'Bearer abc123');
      expect(changes.fullSync, isTrue);
      expect(changes.serverTime, '2026-10-09T10:05:00+00:00');
      expect(changes.categories.single.name, 'Kategori 1');
      // Produk nonaktif tetap dikirim server; penyaringan ada di sisi lokal.
      expect(changes.products.map((p) => p.id), [1, 2]);
      expect(changes.products.last.isActive, isFalse);
      expect(changes.products.first.price, 10000);
    },
  );

  test(
    'updated_since terkirim utuh, termasuk tanda + pada zona waktu',
    () async {
      late http.Request captured;
      final remote = CatalogRemoteDataSource(
        clientWith((request) async {
          captured = request;
          return jsonResponse(200, body(fullSync: false));
        }),
      );

      final changes = await remote.fetch(
        updatedSince: '2026-10-09T17:05:00+07:00',
      );

      expect(
        captured.url.queryParameters['updated_since'],
        '2026-10-09T17:05:00+07:00',
      );
      expect(changes.fullSync, isFalse);
    },
  );

  test('data dengan deleted_at dipisah menjadi daftar id terhapus', () async {
    final remote = CatalogRemoteDataSource(
      clientWith((_) async {
        return jsonResponse(
          200,
          body(
            fullSync: false,
            categories: [
              category(1),
              category(2, deletedAt: '2026-10-09T09:00:00+00:00'),
            ],
            products: [
              product(1),
              product(2, deletedAt: '2026-10-09T09:00:00+00:00'),
            ],
          ),
        );
      }),
    );

    final changes = await remote.fetch(updatedSince: 'x');

    expect(changes.categories.map((c) => c.id), [1]);
    expect(changes.deletedCategoryIds, {2});
    expect(changes.products.map((p) => p.id), [1]);
    expect(changes.deletedProductIds, {2});
  });

  test(
    '401 melempar UnauthorizedException dan memancarkan event sesi berakhir',
    () async {
      final client = clientWith(
        (_) async => jsonResponse(401, {'message': 'Unauthenticated.'}),
      );
      final event = client.unauthorized.first.timeout(
        const Duration(seconds: 1),
      );

      await expectLater(
        CatalogRemoteDataSource(client).fetch(),
        throwsA(isA<UnauthorizedException>()),
      );

      await event;
    },
  );

  test('akun owner -> ForbiddenException', () async {
    final remote = CatalogRemoteDataSource(
      clientWith((_) async => jsonResponse(403, {'message': 'Akses ditolak.'})),
    );

    await expectLater(remote.fetch(), throwsA(isA<ForbiddenException>()));
  });

  test('updated_since tidak valid (422) -> ValidationException', () async {
    final remote = CatalogRemoteDataSource(
      clientWith(
        (_) async => jsonResponse(422, {
          'message': 'Format updated_since tidak valid.',
          'errors': {
            'updated_since': ['Format updated_since tidak valid.'],
          },
        }),
      ),
    );

    await expectLater(
      remote.fetch(updatedSince: 'x'),
      throwsA(isA<ValidationException>()),
    );
  });

  test('bentuk respons tidak sesuai -> UnexpectedApiException', () async {
    final remote = CatalogRemoteDataSource(
      clientWith((_) async => jsonResponse(200, {'data': {}})),
    );

    await expectLater(remote.fetch(), throwsA(isA<UnexpectedApiException>()));
  });

  test('field produk bertipe salah -> UnexpectedApiException', () async {
    final broken = product(1)..['price'] = 'sepuluh ribu';
    final remote = CatalogRemoteDataSource(
      clientWith((_) async => jsonResponse(200, body(products: [broken]))),
    );

    await expectLater(remote.fetch(), throwsA(isA<UnexpectedApiException>()));
  });
}
