import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/database/app_database.dart';
import 'package:kasir_kantin/core/error/api_exceptions.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_local_data_source.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_remote_data_source.dart';
import 'package:kasir_kantin/features/transactions/data/transaction_repository_impl.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_line.dart';
import 'package:kasir_kantin/features/transactions/domain/local_transaction.dart';
import 'package:kasir_kantin/features/transactions/domain/payment_method.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_outcome.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockRemote extends Mock implements TransactionRemoteDataSource {}

final _fallback = LocalTransaction(
  localUuid: 'x',
  invoiceNumber: 'x',
  totalAmount: 1,
  paymentMethod: PaymentMethod.cash,
  syncStatus: SyncStatus.pending,
  createdAt: DateTime.utc(2026),
  items: const [],
);

RemoteTransactionResult accepted({
  int id = 1,
  String invoice = 'INV-20261011-AAAAAA',
  bool duplicate = false,
}) => (
  serverId: id,
  invoiceNumber: invoice,
  syncedAt: DateTime.utc(2026, 10, 11, 2, 31),
  duplicate: duplicate,
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() => registerFallbackValue(_fallback));

  late AppDatabase appDb;
  late MockRemote remote;
  late TransactionLocalDataSource local;
  late TransactionRepositoryImpl repository;
  late String uuid;

  Future<int> stockOf(int id) async {
    final rows = await appDb.db.query(
      'products',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.first['stock'] as int;
  }

  setUp(() async {
    appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    await appDb.db.insert('products', {
      'id': 1,
      'category_id': 1,
      'name': 'Kopi Susu',
      'price': 10000,
      'stock': 10,
      'is_active': 1,
      'updated_at': '2026-10-11T00:00:00+00:00',
    });
    remote = MockRemote();
    local = TransactionLocalDataSource(
      appDb,
      newUuid: () => 'aaaaaa00-0000-4000-8000-000000000000',
      clock: () => DateTime(2026, 10, 11, 9, 30),
    );
    repository = TransactionRepositoryImpl(local: local, remote: remote);

    final tx = await repository.createLocalTransaction(
      lines: const [
        CheckoutLine(
          productId: 1,
          name: 'Kopi Susu',
          quantity: 4,
          expectedPrice: 10000,
        ),
      ],
      paymentMethod: PaymentMethod.cash,
    );
    uuid = tx.localUuid;
  });

  tearDown(() => appDb.close());

  Future<LocalTransaction> stored() async =>
      (await repository.getTransaction(uuid))!;

  group('berhasil', () {
    test(
      'server menerima: synced, server_id terisi, dikirim tepat sekali',
      () async {
        when(
          () => remote.submit(any()),
        ).thenAnswer((_) async => accepted(id: 7));

        final outcome = await repository.syncTransaction(uuid);

        expect(outcome, SyncOutcome.synced);
        final tx = await stored();
        expect(tx.syncStatus, SyncStatus.synced);
        expect(tx.serverId, 7);
        expect(tx.syncedAt, DateTime.utc(2026, 10, 11, 2, 31));
        verify(() => remote.submit(any())).called(1);
        expect(await stockOf(1), 6);
      },
    );

    test(
      'yang dikirim ke server adalah transaksi lokal dalam status syncing',
      () async {
        when(() => remote.submit(any())).thenAnswer((_) async {
          // Saat request berjalan, transaksi harus sudah ditandai syncing.
          expect((await stored()).syncStatus, SyncStatus.syncing);
          return accepted();
        });

        await repository.syncTransaction(uuid);

        final sent =
            verify(() => remote.submit(captureAny())).captured.single
                as LocalTransaction;
        expect(sent.localUuid, uuid);
        expect(sent.totalAmount, 40000);
      },
    );

    test('jawaban 200 (kiriman ulang) tetap synced', () async {
      when(
        () => remote.submit(any()),
      ).thenAnswer((_) async => accepted(duplicate: true));

      expect(await repository.syncTransaction(uuid), SyncOutcome.synced);
      expect((await stored()).syncStatus, SyncStatus.synced);
    });

    test('nomor invoice dari server menggantikan nomor lokal', () async {
      when(
        () => remote.submit(any()),
      ).thenAnswer((_) async => accepted(invoice: 'INV-20261011-AAAAAA-2'));

      await repository.syncTransaction(uuid);

      expect((await stored()).invoiceNumber, 'INV-20261011-AAAAAA-2');
    });
  });

  group('gagal yang bisa dicoba ulang (Rule 6)', () {
    test(
      'tanpa internet: failed, pesan tersimpan, transaksi dan stok utuh',
      () async {
        when(() => remote.submit(any())).thenThrow(const NetworkException());

        final outcome = await repository.syncTransaction(uuid);

        expect(outcome, SyncOutcome.failed);
        final tx = await stored();
        expect(tx.syncStatus, SyncStatus.failed);
        expect(tx.syncMessage, 'Tidak dapat terhubung ke internet.');
        expect(tx.items.single.quantity, 4);
        expect(await stockOf(1), 6);
      },
    );

    test('5xx: failed', () async {
      when(() => remote.submit(any())).thenThrow(const ServerException());

      expect(await repository.syncTransaction(uuid), SyncOutcome.failed);
      expect((await stored()).syncStatus, SyncStatus.failed);
    });

    test('respons tak terduga: failed', () async {
      when(
        () => remote.submit(any()),
      ).thenThrow(const UnexpectedApiException());

      expect(await repository.syncTransaction(uuid), SyncOutcome.failed);
    });

    test('failed bisa dicoba lagi sampai berhasil', () async {
      when(() => remote.submit(any())).thenThrow(const NetworkException());
      await repository.syncTransaction(uuid);

      when(() => remote.submit(any())).thenAnswer((_) async => accepted());
      final retry = await repository.syncTransaction(uuid);

      expect(retry, SyncOutcome.synced);
      final tx = await stored();
      expect(tx.syncStatus, SyncStatus.synced);
      expect(tx.syncMessage, isNull);
    });

    test(
      'galat tak terduga: tidak terkunci di syncing, lalu dilempar ulang',
      () async {
        when(() => remote.submit(any())).thenThrow(StateError('bug'));

        await expectLater(repository.syncTransaction(uuid), throwsStateError);

        expect((await stored()).syncStatus, SyncStatus.pending);
      },
    );
  });

  group('konflik', () {
    test(
      '409 stok kurang: conflict, alasan jelas, stok lokal dikembalikan, transaksi tetap ada',
      () async {
        when(() => remote.submit(any())).thenThrow(
          const ConflictException(
            'Stok produk tidak mencukupi.',
            body: {
              'code': 'insufficient_stock',
              'shortages': [
                {
                  'product_id': 1,
                  'product_name': 'Kopi Susu',
                  'requested': 4,
                  'available': 2,
                },
              ],
            },
          ),
        );

        final outcome = await repository.syncTransaction(uuid);

        expect(outcome, SyncOutcome.conflict);
        final tx = await stored();
        expect(tx.syncStatus, SyncStatus.conflict);
        expect(
          tx.syncMessage,
          'Transaksi tidak dapat disinkronkan karena stok di server tidak mencukupi. '
          'Kopi Susu (diminta 4, tersedia 2).',
        );
        expect(tx.items.single.quantity, 4); // jumlah tidak diubah diam-diam
        expect(await stockOf(1), 10);
      },
    );

    test('409 tanpa rincian: pesan dasar', () async {
      when(() => remote.submit(any())).thenThrow(
        const ConflictException('x', body: {'code': 'insufficient_stock'}),
      );

      await repository.syncTransaction(uuid);

      expect(
        (await stored()).syncMessage,
        'Transaksi tidak dapat disinkronkan karena stok di server tidak mencukupi.',
      );
    });

    test('409 dengan kode lain: pesan umum', () async {
      when(
        () => remote.submit(any()),
      ).thenThrow(const ConflictException('x', body: {'code': 'lain'}));

      await repository.syncTransaction(uuid);

      expect(
        (await stored()).syncMessage,
        'Transaksi tidak dapat diterapkan oleh server.',
      );
    });

    test(
      '422: conflict (bukan failed) agar tidak dicoba ulang terus-menerus',
      () async {
        when(
          () => remote.submit(any()),
        ).thenThrow(const ValidationException('Data tidak valid.'));

        expect(await repository.syncTransaction(uuid), SyncOutcome.conflict);
        final tx = await stored();
        expect(tx.syncStatus, SyncStatus.conflict);
        expect(
          tx.syncMessage,
          'Transaksi ditolak server karena datanya tidak valid.',
        );
        expect(await repository.getTransactionsToSync(), isEmpty);
      },
    );

    test('conflict tidak dikirim ulang oleh pemanggilan berikutnya', () async {
      when(
        () => remote.submit(any()),
      ).thenThrow(const ConflictException('x', body: {}));
      await repository.syncTransaction(uuid);

      expect(await repository.syncTransaction(uuid), SyncOutcome.skipped);
      verify(() => remote.submit(any())).called(1);
    });
  });

  group('sesi', () {
    test('401: kembali pending (bukan failed), pengirim diberi tahu', () async {
      when(() => remote.submit(any())).thenThrow(const UnauthorizedException());

      final outcome = await repository.syncTransaction(uuid);

      expect(outcome, SyncOutcome.sessionExpired);
      final tx = await stored();
      expect(tx.syncStatus, SyncStatus.pending);
      expect(tx.syncMessage, isNull);
      expect(await stockOf(1), 6);
    });

    test('403: kembali pending', () async {
      when(() => remote.submit(any())).thenThrow(const ForbiddenException());

      expect(
        await repository.syncTransaction(uuid),
        SyncOutcome.sessionExpired,
      );
      expect((await stored()).syncStatus, SyncStatus.pending);
    });
  });

  group('tanpa transaksi ganda (Rule 5)', () {
    test('dua pemanggilan bersamaan: hanya satu yang mengirim', () async {
      final gate = Completer<RemoteTransactionResult>();
      when(() => remote.submit(any())).thenAnswer((_) => gate.future);

      final first = repository.syncTransaction(uuid);
      final second = repository.syncTransaction(uuid);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete(accepted());

      final outcomes = await Future.wait([first, second]);

      expect(outcomes, containsAll([SyncOutcome.synced, SyncOutcome.skipped]));
      verify(() => remote.submit(any())).called(1);
    });

    test('transaksi yang sudah synced tidak dikirim lagi', () async {
      when(() => remote.submit(any())).thenAnswer((_) async => accepted());
      await repository.syncTransaction(uuid);

      expect(await repository.syncTransaction(uuid), SyncOutcome.skipped);
      verify(() => remote.submit(any())).called(1);
    });

    test('UUID tidak dikenal dilewati tanpa memanggil server', () async {
      expect(
        await repository.syncTransaction('tidak-ada'),
        SyncOutcome.skipped,
      );
      verifyNever(() => remote.submit(any()));
    });
  });

  group('pemulihan dan hitungan', () {
    test('recoverInterruptedSyncs mengembalikan syncing ke pending', () async {
      await local.markSyncing(uuid);

      expect(await repository.recoverInterruptedSyncs(), 1);

      expect((await stored()).syncStatus, SyncStatus.pending);
    });

    test('hitungan belum tersinkron dan konflik mengikuti status', () async {
      expect(await repository.countUnsyncedTransactions(), 1);
      expect(await repository.countConflictTransactions(), 0);

      when(
        () => remote.submit(any()),
      ).thenThrow(const ConflictException('x', body: {}));
      await repository.syncTransaction(uuid);

      expect(await repository.countUnsyncedTransactions(), 0);
      expect(await repository.countConflictTransactions(), 1);
    });
  });
}
