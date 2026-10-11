import '../../../core/error/api_exceptions.dart';
import '../../../core/network/api_client.dart';
import '../domain/local_transaction.dart';

/// Jawaban server untuk transaksi yang diterima.
typedef RemoteTransactionResult = ({
  int serverId,
  String invoiceNumber,
  DateTime? syncedAt,
  bool duplicate,
});

/// Satu-satunya tempat panggilan HTTP transaksi berada (AGENTS.md §4.3).
class TransactionRemoteDataSource {
  TransactionRemoteDataSource(this._client);

  final ApiClient _client;

  /// `POST /api/transactions`. 201 (baru) dan 200 (kiriman ulang) sama-sama
  /// berarti transaksi sudah ada di server. Galat dilempar sebagai
  /// `ApiException` oleh [ApiClient] (409 -> ConflictException, dst).
  Future<RemoteTransactionResult> submit(LocalTransaction transaction) async {
    final json = await _client.post(
      '/transactions',
      body: {
        'local_uuid': transaction.localUuid,
        'invoice_number': transaction.invoiceNumber,
        'payment_method': transaction.paymentMethod.value,
        'total_amount': transaction.totalAmount,
        // Waktu penjualan menurut perangkat, bukan waktu upload.
        'created_at': transaction.createdAt.toUtc().toIso8601String(),
        'items': [
          for (final item in transaction.items)
            {
              'product_id': item.productId,
              'quantity': item.quantity,
              'price': item.price,
              'subtotal': item.subtotal,
            },
        ],
      },
    );

    try {
      final data = json['data'] as Map<String, dynamic>;
      final meta = json['meta'] as Map<String, dynamic>?;
      final syncedAt = data['synced_at'] as String?;
      return (
        serverId: data['id'] as int,
        invoiceNumber: data['invoice_number'] as String,
        syncedAt: syncedAt == null ? null : DateTime.tryParse(syncedAt),
        duplicate: meta?['duplicate'] == true,
      );
    } on TypeError {
      throw const UnexpectedApiException(
        'Respons server tidak sesuai harapan.',
      );
    }
  }
}
