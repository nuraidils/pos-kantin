import '../../../core/error/api_exceptions.dart';
import '../domain/checkout_line.dart';
import '../domain/local_transaction.dart';
import '../domain/payment_method.dart';
import '../domain/sync_outcome.dart';
import '../domain/transaction_repository.dart';
import 'transaction_local_data_source.dart';
import 'transaction_remote_data_source.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl({required this._local, required this._remote});

  final TransactionLocalDataSource _local;
  final TransactionRemoteDataSource _remote;

  @override
  Future<LocalTransaction> createLocalTransaction({
    required List<CheckoutLine> lines,
    required PaymentMethod paymentMethod,
  }) {
    return _local.create(lines: lines, paymentMethod: paymentMethod);
  }

  @override
  Future<LocalTransaction?> getTransaction(String localUuid) =>
      _local.getByUuid(localUuid);

  @override
  Future<List<LocalTransaction>> getAllTransactions() => _local.getAll();

  @override
  Future<List<LocalTransaction>> getTransactionsToSync() =>
      _local.getSyncable();

  @override
  Future<int> countUnsyncedTransactions() => _local.countUnsynced();

  @override
  Future<int> countConflictTransactions() => _local.countConflicts();

  @override
  Future<List<LocalTransaction>> getConflictTransactions() =>
      _local.getConflicts();

  @override
  Future<bool> retryConflict(String localUuid) =>
      _local.requeueConflict(localUuid);

  @override
  Future<int> recoverInterruptedSyncs() => _local.resetInterruptedSyncs();

  @override
  Future<SyncOutcome> syncTransaction(String localUuid) async {
    final transaction = await _local.getByUuid(localUuid);
    if (transaction == null) return SyncOutcome.skipped;

    // Penjaga di SQL: hanya satu pemanggil yang berhasil mengambil transaksi
    // ini. Yang lain berhenti di sini, tidak mengirim apa pun.
    if (!await _local.markSyncing(localUuid)) return SyncOutcome.skipped;

    try {
      final result = await _remote.submit(transaction);
      await _local.markSynced(
        localUuid,
        serverId: result.serverId,
        invoiceNumber: result.invoiceNumber,
        syncedAt: result.syncedAt,
      );
      return SyncOutcome.synced;
    } on ConflictException catch (e) {
      await _local.markConflict(localUuid, _conflictMessage(e));
      return SyncOutcome.conflict;
    } on ValidationException {
      // Dikirim ulang pun hasilnya sama, jadi bukan `failed` (yang akan
      // dicoba lagi terus). Tetap tersimpan dan terlihat sebagai perlu perhatian.
      await _local.markConflict(
        localUuid,
        'Transaksi ditolak server karena datanya tidak valid.',
      );
      return SyncOutcome.conflict;
    } on UnauthorizedException {
      await _local.releaseSyncing(localUuid);
      return SyncOutcome.sessionExpired;
    } on ForbiddenException {
      await _local.releaseSyncing(localUuid);
      return SyncOutcome.sessionExpired;
    } on ApiException catch (e) {
      // Jaringan, 5xx, dan respons tak terduga: simpan, coba lagi nanti.
      await _local.markFailed(localUuid, e.message);
      return SyncOutcome.failed;
    } catch (_) {
      // Galat di luar API (mis. gagal menulis SQLite setelah server menerima):
      // jangan biarkan terkunci di `syncing`. Kiriman ulang aman karena
      // server idempoten lewat local_uuid.
      await _local.releaseSyncing(localUuid);
      rethrow;
    }
  }

  /// Pesan untuk kasir (DESIGN.md §20). Untuk stok kurang, nama produk dan
  /// jumlahnya ikut ditampilkan agar jelas apa yang bermasalah.
  String _conflictMessage(ConflictException e) {
    if (e.body['code'] != 'insufficient_stock') {
      return 'Transaksi tidak dapat diterapkan oleh server.';
    }

    const base =
        'Transaksi tidak dapat disinkronkan karena stok di server tidak mencukupi.';
    final shortages = e.body['shortages'];
    if (shortages is! List) return base;

    final details = <String>[];
    for (final item in shortages) {
      if (item is! Map) continue;
      final name = item['product_name'];
      final requested = item['requested'];
      final available = item['available'];
      if (name is String && requested is int && available is int) {
        details.add('$name (diminta $requested, tersedia $available)');
      }
    }
    return details.isEmpty ? base : '$base ${details.join(', ')}.';
  }
}
