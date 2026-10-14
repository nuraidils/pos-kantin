import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/features/sync/presentation/bloc/conflict_bloc.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';

import '../../../support/fake_transaction_repository.dart';

void main() {
  late FakeTransactionRepository repo;

  setUp(() {
    repo = FakeTransactionRepository()
      ..add('a', SyncStatus.conflict)
      ..add('b', SyncStatus.pending)
      ..messages['a'] = 'Stok kurang.';
  });

  blocTest<ConflictBloc, ConflictState>(
    'ConflictLoaded membaca daftar conflict beserta alasannya',
    build: () => ConflictBloc(repository: repo),
    act: (bloc) => bloc.add(const ConflictLoaded()),
    verify: (bloc) {
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.transactions.map((t) => t.localUuid), ['a']);
      expect(bloc.state.transactions.single.syncMessage, 'Stok kurang.');
      expect(bloc.state.error, isNull);
    },
  );

  blocTest<ConflictBloc, ConflictState>(
    'gagal membaca -> pesan galat, tidak crash',
    build: () {
      repo.conflictsThrow = true;
      return ConflictBloc(repository: repo);
    },
    act: (bloc) => bloc.add(const ConflictLoaded()),
    verify: (bloc) {
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.error, isNotNull);
    },
  );

  blocTest<ConflictBloc, ConflictState>(
    'ConflictRetried: kembali pending, daftar dibaca ulang, retryCount naik',
    build: () => ConflictBloc(repository: repo),
    act: (bloc) => bloc.add(const ConflictRetried('a')),
    verify: (bloc) {
      expect(repo.statuses['a'], SyncStatus.pending);
      expect(bloc.state.transactions, isEmpty);
      expect(bloc.state.retryCount, 1);
    },
  );

  blocTest<ConflictBloc, ConflictState>(
    'ConflictRetried pada transaksi yang bukan conflict: retryCount tetap',
    build: () => ConflictBloc(repository: repo),
    act: (bloc) => bloc.add(const ConflictRetried('b')),
    verify: (bloc) {
      expect(bloc.state.retryCount, 0);
      expect(repo.statuses['b'], SyncStatus.pending);
    },
  );

  blocTest<ConflictBloc, ConflictState>(
    'ConflictRetried gagal -> pesan galat dan daftar tetap',
    build: () {
      repo.retryThrows = true;
      return ConflictBloc(repository: repo);
    },
    act: (bloc) => bloc.add(const ConflictRetried('a')),
    verify: (bloc) {
      expect(bloc.state.error, isNotNull);
      expect(bloc.state.retryCount, 0);
      expect(repo.statuses['a'], SyncStatus.conflict);
    },
  );
}
