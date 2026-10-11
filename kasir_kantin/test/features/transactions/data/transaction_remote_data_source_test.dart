import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/core/network/api_client.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_remote_data_source.dart';
import 'package:kasir_kantin/features/transactions/domain/local_transaction.dart';
import 'package:kasir_kantin/features/transactions/domain/payment_method.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';

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

final transaction = LocalTransaction(
  localUuid: 'c0a8b2e4-5d3f-4f6a-9c1e-2b7d8e9f0a1b',
  invoiceNumber: 'INV-20261011-C0A8B2',
  totalAmount: 25000,
  paymentMethod: PaymentMethod.qris,
  syncStatus: SyncStatus.syncing,
  createdAt: DateTime.utc(2026, 10, 11, 2, 30),
  items: const [
    LocalTransactionItem(
      productId: 1,
      productName: 'Kopi Susu',
      quantity: 2,
      price: 10000,
    ),
    LocalTransactionItem(
      productId: 2,
      productName: 'Es Teh',
      quantity: 1,
      price: 5000,
    ),
  ],
);

Map<String, dynamic> success({bool duplicate = false}) => {
  'data': {
    'id': 42,
    'local_uuid': 'c0a8b2e4-5d3f-4f6a-9c1e-2b7d8e9f0a1b',
    'invoice_number': 'INV-20261011-C0A8B2-2',
    'synced_at': '2026-10-11T02:31:00+00:00',
  },
  'meta': {'duplicate': duplicate},
};

void main() {
  test('mengirim payload sesuai kontrak server', () async {
    late http.Request captured;
    final remote = TransactionRemoteDataSource(
      clientWith((request) async {
        captured = request;
        return jsonResponse(201, success());
      }),
    );

    await remote.submit(transaction);

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/transactions');
    expect(captured.headers['Authorization'], 'Bearer abc123');
    expect(jsonDecode(captured.body), {
      'local_uuid': 'c0a8b2e4-5d3f-4f6a-9c1e-2b7d8e9f0a1b',
      'invoice_number': 'INV-20261011-C0A8B2',
      'payment_method': 'qris',
      'total_amount': 25000,
      'created_at': '2026-10-11T02:30:00.000Z',
      'items': [
        {'product_id': 1, 'quantity': 2, 'price': 10000, 'subtotal': 20000},
        {'product_id': 2, 'quantity': 1, 'price': 5000, 'subtotal': 5000},
      ],
    });
  });

  test(
    '201 menghasilkan id server, invoice server, dan waktu sinkron',
    () async {
      final remote = TransactionRemoteDataSource(
        clientWith((_) async => jsonResponse(201, success())),
      );

      final result = await remote.submit(transaction);

      expect(result.serverId, 42);
      expect(result.invoiceNumber, 'INV-20261011-C0A8B2-2');
      expect(result.syncedAt, DateTime.utc(2026, 10, 11, 2, 31));
      expect(result.duplicate, isFalse);
    },
  );

  test('200 (kiriman ulang) juga sukses dan ditandai duplicate', () async {
    final remote = TransactionRemoteDataSource(
      clientWith((_) async => jsonResponse(200, success(duplicate: true))),
    );

    final result = await remote.submit(transaction);

    expect(result.serverId, 42);
    expect(result.duplicate, isTrue);
  });

  test('409 menjadi ConflictException dengan isi respons', () async {
    final remote = TransactionRemoteDataSource(
      clientWith(
        (_) async => jsonResponse(409, {
          'message': 'Stok produk tidak mencukupi.',
          'code': 'insufficient_stock',
          'shortages': [
            {
              'product_id': 1,
              'product_name': 'Kopi Susu',
              'requested': 2,
              'available': 1,
            },
          ],
        }),
      ),
    );

    await expectLater(
      remote.submit(transaction),
      throwsA(
        isA<ConflictException>().having(
          (e) => e.body['code'],
          'code',
          'insufficient_stock',
        ),
      ),
    );
  });

  test('422 menjadi ValidationException', () async {
    final remote = TransactionRemoteDataSource(
      clientWith(
        (_) async => jsonResponse(422, {
          'message': 'Data tidak valid.',
          'errors': {
            'total_amount': [
              'Total pembayaran tidak sesuai dengan jumlah subtotal.',
            ],
          },
        }),
      ),
    );

    await expectLater(
      remote.submit(transaction),
      throwsA(isA<ValidationException>()),
    );
  });

  test(
    '401 menjadi UnauthorizedException dan melaporkan sesi berakhir',
    () async {
      final client = clientWith(
        (_) async => jsonResponse(401, {'message': 'Unauthenticated.'}),
      );
      final remote = TransactionRemoteDataSource(client);
      var reported = 0;
      final sub = client.unauthorized.listen((_) => reported++);
      addTearDown(sub.cancel);

      await expectLater(
        remote.submit(transaction),
        throwsA(isA<UnauthorizedException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(reported, 1);
    },
  );

  test('500 menjadi ServerException (dapat dicoba ulang)', () async {
    final remote = TransactionRemoteDataSource(
      clientWith((_) async => jsonResponse(500, {'message': 'boom'})),
    );

    await expectLater(
      remote.submit(transaction),
      throwsA(isA<ServerException>()),
    );
  });

  test('tanpa koneksi menjadi NetworkException', () async {
    final remote = TransactionRemoteDataSource(
      clientWith((_) async => throw http.ClientException('putus')),
    );

    await expectLater(
      remote.submit(transaction),
      throwsA(isA<NetworkException>()),
    );
  });

  test(
    'respons sukses yang bentuknya salah menjadi UnexpectedApiException',
    () async {
      final remote = TransactionRemoteDataSource(
        clientWith(
          (_) async => jsonResponse(201, {
            'data': {'id': 'bukan-angka'},
          }),
        ),
      );

      await expectLater(
        remote.submit(transaction),
        throwsA(isA<UnexpectedApiException>()),
      );
    },
  );
}
