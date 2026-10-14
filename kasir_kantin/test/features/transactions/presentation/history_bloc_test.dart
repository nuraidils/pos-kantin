import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';
import 'package:kasir_kantin/features/transactions/presentation/bloc/history_bloc.dart';

import '../../../support/fake_transaction_repository.dart';

void main() {
  late FakeTransactionRepository repo;

  setUp(() {
    repo = FakeTransactionRepository()
      ..add('a', SyncStatus.synced)
      ..add('b', SyncStatus.conflict)
      ..add('c', SyncStatus.pending)
      ..messages['b'] = 'Stok kurang.';
  });

  blocTest<HistoryBloc, HistoryState>(
    'HistoryLoaded membaca semua status, terbaru dulu',
    build: () => HistoryBloc(repository: repo),
    act: (bloc) => bloc.add(const HistoryLoaded()),
    verify: (bloc) {
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.error, isNull);
      expect(bloc.state.transactions.map((t) => t.localUuid), ['c', 'b', 'a']);
      expect(bloc.state.transactions.map((t) => t.syncStatus), [
        SyncStatus.pending,
        SyncStatus.conflict,
        SyncStatus.synced,
      ]);
      expect(bloc.state.transactions[1].syncMessage, 'Stok kurang.');
    },
  );

  blocTest<HistoryBloc, HistoryState>(
    'tanpa transaksi -> daftar kosong, bukan galat',
    build: () => HistoryBloc(repository: repo..statuses.clear()),
    act: (bloc) => bloc.add(const HistoryLoaded()),
    verify: (bloc) {
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.transactions, isEmpty);
      expect(bloc.state.error, isNull);
    },
  );

  blocTest<HistoryBloc, HistoryState>(
    'gagal membaca -> pesan galat, tidak crash',
    build: () => HistoryBloc(repository: repo..allThrow = true),
    act: (bloc) => bloc.add(const HistoryLoaded()),
    verify: (bloc) {
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.error, isNotNull);
    },
  );

  test('galat saat membaca ulang: daftar lama dipertahankan', () async {
    final bloc = HistoryBloc(repository: repo);
    addTearDown(bloc.close);

    bloc.add(const HistoryLoaded());
    await bloc.stream.firstWhere((s) => !s.isLoading);
    repo.allThrow = true;
    bloc.add(const HistoryLoaded());
    await bloc.stream.firstWhere((s) => s.error != null);

    expect(bloc.state.transactions, hasLength(3));
  });

  test('status yang berubah terbaca pada pembacaan berikutnya', () async {
    final bloc = HistoryBloc(repository: repo);
    addTearDown(bloc.close);

    bloc.add(const HistoryLoaded());
    await bloc.stream.firstWhere((s) => !s.isLoading);
    repo.statuses['c'] = SyncStatus.synced;
    bloc.add(const HistoryLoaded());
    await bloc.stream.firstWhere(
      (s) => s.transactions.first.syncStatus == SyncStatus.synced,
    );

    expect(bloc.state.transactions.first.localUuid, 'c');
  });
}
