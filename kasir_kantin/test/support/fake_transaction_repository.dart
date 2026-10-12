import 'dart:async';

import 'package:kasir_kantin/features/transactions/domain/checkout_line.dart';
import 'package:kasir_kantin/features/transactions/domain/local_transaction.dart';
import 'package:kasir_kantin/features/transactions/domain/payment_method.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_outcome.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:kasir_kantin/features/transactions/domain/transaction_repository.dart';

LocalTransaction fakeTransaction(String uuid, {int minute = 0}) =>
    LocalTransaction(
      localUuid: uuid,
      invoiceNumber: 'INV-$uuid',
      totalAmount: 10000,
      paymentMethod: PaymentMethod.cash,
      syncStatus: SyncStatus.pending,
      createdAt: DateTime.utc(2026, 10, 11, 2, minute),
      items: const [
        LocalTransactionItem(
          productId: 1,
          productName: 'Kopi Susu',
          quantity: 1,
          price: 10000,
        ),
      ],
    );

/// Repository palsu yang meniru perpindahan status yang sebenarnya: transaksi
/// `pending`/`failed` boleh dikirim, hasil pengiriman mengubah statusnya, dan
/// hitungan mengikuti status. Dipakai oleh tes BLoC dan widget.
class FakeTransactionRepository implements TransactionRepository {
  /// Urutan = urutan penjualan (terlama dulu).
  final Map<String, SyncStatus> statuses = {};

  /// Hasil per UUID; bawaannya `synced`.
  final Map<String, SyncOutcome> outcomes = {};

  /// UUID yang melempar galat tak terduga saat dikirim.
  final Set<String> throwing = {};

  /// Menahan pengiriman UUID tertentu sampai completer selesai.
  final Map<String, Completer<void>> gates = {};

  /// Catatan panggilan berurutan: `recover`, `queue`, `sync:<uuid>`.
  final List<String> calls = [];

  Object? recoverError;
  Object? queueError;

  void add(String uuid, [SyncStatus status = SyncStatus.pending]) =>
      statuses[uuid] = status;

  List<String> get sent => [
    for (final call in calls)
      if (call.startsWith('sync:')) call.substring(5),
  ];

  @override
  Future<int> recoverInterruptedSyncs() async {
    calls.add('recover');
    if (recoverError != null) throw recoverError!;
    var count = 0;
    for (final uuid in statuses.keys.toList()) {
      if (statuses[uuid] == SyncStatus.syncing) {
        statuses[uuid] = SyncStatus.pending;
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<LocalTransaction>> getTransactionsToSync() async {
    calls.add('queue');
    if (queueError != null) throw queueError!;
    return [
      for (final entry in statuses.entries)
        if (entry.value == SyncStatus.pending ||
            entry.value == SyncStatus.failed)
          fakeTransaction(entry.key),
    ];
  }

  @override
  Future<SyncOutcome> syncTransaction(String localUuid) async {
    calls.add('sync:$localUuid');
    final status = statuses[localUuid];
    if (status != SyncStatus.pending && status != SyncStatus.failed) {
      return SyncOutcome.skipped;
    }

    statuses[localUuid] = SyncStatus.syncing;
    await gates[localUuid]?.future;

    if (throwing.contains(localUuid)) {
      statuses[localUuid] = SyncStatus.pending;
      throw StateError('galat tak terduga');
    }

    final outcome = outcomes[localUuid] ?? SyncOutcome.synced;
    statuses[localUuid] = switch (outcome) {
      SyncOutcome.synced => SyncStatus.synced,
      SyncOutcome.conflict => SyncStatus.conflict,
      SyncOutcome.failed => SyncStatus.failed,
      SyncOutcome.sessionExpired => SyncStatus.pending,
      SyncOutcome.skipped => status!,
    };
    return outcome;
  }

  int _count(Set<SyncStatus> wanted) =>
      statuses.values.where(wanted.contains).length;

  @override
  Future<int> countUnsyncedTransactions() async =>
      _count({SyncStatus.pending, SyncStatus.syncing, SyncStatus.failed});

  @override
  Future<int> countConflictTransactions() async =>
      _count({SyncStatus.conflict});

  @override
  Future<LocalTransaction?> getTransaction(String localUuid) async =>
      statuses.containsKey(localUuid) ? fakeTransaction(localUuid) : null;

  @override
  Future<LocalTransaction> createLocalTransaction({
    required List<CheckoutLine> lines,
    required PaymentMethod paymentMethod,
  }) => throw UnimplementedError();
}
