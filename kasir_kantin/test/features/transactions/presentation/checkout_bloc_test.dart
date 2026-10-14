import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_exception.dart';
import 'package:kasir_kantin/features/transactions/domain/checkout_line.dart';
import 'package:kasir_kantin/features/transactions/domain/local_transaction.dart';
import 'package:kasir_kantin/features/transactions/domain/payment_method.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:kasir_kantin/features/transactions/domain/transaction_repository.dart';
import 'package:kasir_kantin/features/transactions/presentation/bloc/checkout_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockTransactionRepository extends Mock implements TransactionRepository {}

void main() {
  const lines = [
    CheckoutLine(
      productId: 1,
      name: 'Kopi Susu',
      quantity: 2,
      expectedPrice: 10000,
    ),
  ];

  final receipt = LocalTransaction(
    localUuid: 'uuid-1',
    invoiceNumber: 'INV-20261011-ABC123',
    totalAmount: 20000,
    paymentMethod: PaymentMethod.cash,
    syncStatus: SyncStatus.pending,
    createdAt: DateTime.utc(2026, 10, 11, 4),
    items: const [
      LocalTransactionItem(
        productId: 1,
        productName: 'Kopi Susu',
        quantity: 2,
        price: 10000,
      ),
    ],
  );

  late MockTransactionRepository repository;

  setUpAll(() {
    registerFallbackValue(<CheckoutLine>[]);
    registerFallbackValue(PaymentMethod.cash);
  });

  setUp(() => repository = MockTransactionRepository());

  CheckoutBloc build() => CheckoutBloc(repository: repository);

  void stubCreate(Future<LocalTransaction> Function() answer) {
    when(
      () => repository.createLocalTransaction(
        lines: any(named: 'lines'),
        paymentMethod: any(named: 'paymentMethod'),
      ),
    ).thenAnswer((_) => answer());
  }

  test('state awal: Tunai, belum ada transaksi', () {
    final state = build().state;

    expect(state.method, PaymentMethod.cash);
    expect(state.status, CheckoutStatus.editing);
    expect(state.receipt, isNull);
    expect(state.error, isNull);
  });

  blocTest<CheckoutBloc, CheckoutState>(
    'memilih metode mengganti metode',
    build: build,
    act: (bloc) => bloc.add(const CheckoutMethodSelected(PaymentMethod.qris)),
    expect: () => [
      isA<CheckoutState>().having(
        (s) => s.method,
        'method',
        PaymentMethod.qris,
      ),
    ],
  );

  blocTest<CheckoutBloc, CheckoutState>(
    'bayar berhasil -> menyimpan dengan metode terpilih lalu success',
    build: () {
      stubCreate(() async => receipt);
      return build();
    },
    act: (bloc) => bloc
      ..add(const CheckoutMethodSelected(PaymentMethod.qris))
      ..add(const CheckoutSubmitted(lines)),
    expect: () => [
      isA<CheckoutState>().having(
        (s) => s.method,
        'method',
        PaymentMethod.qris,
      ),
      isA<CheckoutState>().having(
        (s) => s.status,
        'status',
        CheckoutStatus.submitting,
      ),
      isA<CheckoutState>()
          .having((s) => s.status, 'status', CheckoutStatus.success)
          .having((s) => s.receipt, 'receipt', receipt),
    ],
    verify: (_) {
      verify(
        () => repository.createLocalTransaction(
          lines: lines,
          paymentMethod: PaymentMethod.qris,
        ),
      ).called(1);
    },
  );

  blocTest<CheckoutBloc, CheckoutState>(
    'stok tidak cukup -> failure dengan pesan dari alasan penolakan',
    build: () {
      stubCreate(
        () async =>
            throw CheckoutInsufficientStockException('Kopi Susu', available: 1),
      );
      return build();
    },
    act: (bloc) => bloc.add(const CheckoutSubmitted(lines)),
    expect: () => [
      isA<CheckoutState>().having(
        (s) => s.status,
        'status',
        CheckoutStatus.submitting,
      ),
      isA<CheckoutState>()
          .having((s) => s.status, 'status', CheckoutStatus.failure)
          .having(
            (s) => s.error,
            'error',
            'Stok Kopi Susu tidak mencukupi (tersisa 1). '
                'Ubah jumlah di keranjang.',
          )
          .having((s) => s.receipt, 'receipt', isNull),
    ],
  );

  blocTest<CheckoutBloc, CheckoutState>(
    'galat tak terduga -> pesan umum, bukan detail teknis',
    build: () {
      stubCreate(() async => throw Exception('database is locked'));
      return build();
    },
    act: (bloc) => bloc.add(const CheckoutSubmitted(lines)),
    verify: (bloc) {
      expect(bloc.state.status, CheckoutStatus.failure);
      expect(bloc.state.error, 'Transaksi tidak dapat disimpan. Coba lagi.');
    },
  );

  blocTest<CheckoutBloc, CheckoutState>(
    'setelah gagal, bayar lagi diperbolehkan dan menghapus pesan lama',
    build: () {
      var calls = 0;
      stubCreate(() async {
        calls++;
        if (calls == 1) throw const CheckoutEmptyException();
        return receipt;
      });
      return build();
    },
    act: (bloc) async {
      bloc.add(const CheckoutSubmitted(lines));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CheckoutSubmitted(lines));
    },
    verify: (bloc) {
      expect(bloc.state.status, CheckoutStatus.success);
      expect(bloc.state.error, isNull);
      expect(bloc.state.receipt, receipt);
    },
  );

  test('ketuk ganda saat menyimpan -> hanya SATU transaksi dibuat', () async {
    final completer = Completer<LocalTransaction>();
    stubCreate(() => completer.future);
    final bloc = build();

    bloc
      ..add(const CheckoutSubmitted(lines))
      ..add(const CheckoutSubmitted(lines));
    await Future<void>.delayed(Duration.zero);
    completer.complete(receipt);
    await Future<void>.delayed(Duration.zero);

    verify(
      () => repository.createLocalTransaction(
        lines: any(named: 'lines'),
        paymentMethod: any(named: 'paymentMethod'),
      ),
    ).called(1);
    expect(bloc.state.status, CheckoutStatus.success);
    await bloc.close();
  });

  test('setelah sukses, bayar lagi diabaikan', () async {
    stubCreate(() async => receipt);
    final bloc = build();

    bloc.add(const CheckoutSubmitted(lines));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    bloc.add(const CheckoutSubmitted(lines));
    await Future<void>.delayed(Duration.zero);

    verify(
      () => repository.createLocalTransaction(
        lines: any(named: 'lines'),
        paymentMethod: any(named: 'paymentMethod'),
      ),
    ).called(1);
    await bloc.close();
  });

  test(
    'metode tidak bisa diganti saat menyimpan atau sesudah sukses',
    () async {
      final completer = Completer<LocalTransaction>();
      stubCreate(() => completer.future);
      final bloc = build();

      bloc.add(const CheckoutSubmitted(lines));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CheckoutMethodSelected(PaymentMethod.qris));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.method, PaymentMethod.cash);

      completer.complete(receipt);
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CheckoutMethodSelected(PaymentMethod.qris));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.method, PaymentMethod.cash);
      await bloc.close();
    },
  );

  group('CheckoutReceiptRefreshed', () {
    LocalTransaction withStatus(SyncStatus status) => LocalTransaction(
      localUuid: receipt.localUuid,
      invoiceNumber: receipt.invoiceNumber,
      totalAmount: receipt.totalAmount,
      paymentMethod: receipt.paymentMethod,
      syncStatus: status,
      createdAt: receipt.createdAt,
      items: receipt.items,
    );

    test('membaca ulang transaksi dan memperbarui struk', () async {
      stubCreate(() async => receipt);
      when(
        () => repository.getTransaction('uuid-1'),
      ).thenAnswer((_) async => withStatus(SyncStatus.synced));
      final bloc = build();
      addTearDown(bloc.close);

      bloc.add(const CheckoutSubmitted(lines));
      await bloc.stream.firstWhere((s) => s.isSuccess);
      bloc.add(const CheckoutReceiptRefreshed());
      await bloc.stream.firstWhere(
        (s) => s.receipt?.syncStatus == SyncStatus.synced,
      );

      expect(bloc.state.isSuccess, isTrue);
      expect(bloc.state.receipt!.syncStatus, SyncStatus.synced);
    });

    test('tanpa struk: tidak membaca apa pun', () async {
      final bloc = build();
      addTearDown(bloc.close);

      bloc.add(const CheckoutReceiptRefreshed());
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => repository.getTransaction(any()));
      expect(bloc.state.receipt, isNull);
    });

    test('gagal membaca: struk lama dipertahankan', () async {
      stubCreate(() async => receipt);
      when(
        () => repository.getTransaction('uuid-1'),
      ).thenThrow(StateError('x'));
      final bloc = build();
      addTearDown(bloc.close);

      bloc.add(const CheckoutSubmitted(lines));
      await bloc.stream.firstWhere((s) => s.isSuccess);
      bloc.add(const CheckoutReceiptRefreshed());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.isSuccess, isTrue);
      expect(bloc.state.receipt, receipt);
    });
  });
}
