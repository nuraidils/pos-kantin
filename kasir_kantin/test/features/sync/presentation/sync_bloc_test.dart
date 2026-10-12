import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_outcome.dart';
import 'package:kasir_kantin/features/transactions/domain/sync_status.dart';

import '../../../support/fake_transaction_repository.dart';

void main() {
  late FakeTransactionRepository repository;
  late SyncBloc bloc;

  setUp(() {
    repository = FakeTransactionRepository();
    bloc = SyncBloc(repository: repository);
  });

  tearDown(() => bloc.close());

  /// Semua future palsu selesai lewat antrean microtask, jadi cukup menguras
  /// antrean event. Dipakai sebagai ganti menunggu state, karena BLoC tidak
  /// memancarkan state yang sama dua kali.
  Future<void> settle() => pumpEventQueue(times: 100);

  group('SyncStarted', () {
    test('memulihkan transaksi syncing SEBELUM mengirim', () async {
      repository
        ..add('a', SyncStatus.syncing) // tertinggal saat aplikasi tertutup
        ..add('b');

      bloc.add(const SyncStarted());
      await settle();

      expect(repository.calls.first, 'recover');
      expect(repository.sent, ['a', 'b']);
      expect(repository.statuses['a'], SyncStatus.synced);
      expect(repository.statuses['b'], SyncStatus.synced);
    });

    test('gagal memulihkan tidak menghentikan pengiriman', () async {
      repository
        ..recoverError = StateError('sqlite')
        ..add('a');

      bloc.add(const SyncStarted());
      await settle();

      expect(repository.sent, ['a']);
    });
  });

  group('SyncRequested', () {
    test('mengirim berurutan dari yang terlama, hingga semua synced', () async {
      repository
        ..add('a')
        ..add('b')
        ..add('c');

      bloc.add(const SyncRequested());
      await settle();

      expect(repository.sent, ['a', 'b', 'c']);
      expect(bloc.state.isSyncing, isFalse);
      expect(bloc.state.unsyncedCount, 0);
      expect(bloc.state.conflictCount, 0);
      expect(bloc.state.lastRunFailed, isFalse);
      expect(bloc.state.changeRevision, 1);
    });

    test(
      'state selama pengiriman: isSyncing dan sisa antrean menurun',
      () async {
        repository
          ..add('a')
          ..add('b');
        final states = <SyncState>[];
        final sub = bloc.stream.listen(states.add);
        addTearDown(sub.cancel);

        bloc.add(const SyncRequested());
        await settle();

        final syncing = states.where((s) => s.isSyncing).toList();
        expect(syncing.first.unsyncedCount, 2);
        expect(syncing.map((s) => s.unsyncedCount), containsAllInOrder([2, 1]));
        expect(states.last.isSyncing, isFalse);
      },
    );

    test(
      'tanpa antrean: tidak ada yang dikirim dan tidak ada perubahan',
      () async {
        repository.add('a', SyncStatus.synced);

        bloc.add(const SyncRequested());
        await settle();

        expect(repository.sent, isEmpty);
        expect(bloc.state, const SyncState());
      },
    );

    test(
      'transaksi baru yang masuk antrean terhitung tanpa mengirim apa pun saat tidak ada',
      () async {
        repository.add('a', SyncStatus.conflict);

        bloc.add(const SyncRequested());
        await settle();

        expect(repository.sent, isEmpty);
        expect(bloc.state.conflictCount, 1);
        expect(bloc.state.unsyncedCount, 0);
        expect(bloc.state.changeRevision, 0);
      },
    );
  });

  group('kegagalan (Rule 6)', () {
    test(
      'gagal -> berhenti di situ, sisanya tetap menunggu, tidak ada yang hilang',
      () async {
        repository
          ..add('a')
          ..add('b')
          ..add('c')
          ..outcomes['b'] = SyncOutcome.failed;

        bloc.add(const SyncRequested());
        await settle();

        expect(repository.sent, ['a', 'b']); // c tidak ditembakkan
        expect(repository.statuses['a'], SyncStatus.synced);
        expect(repository.statuses['b'], SyncStatus.failed);
        expect(repository.statuses['c'], SyncStatus.pending);
        expect(bloc.state.lastRunFailed, isTrue);
        expect(bloc.state.unsyncedCount, 2);
        expect(bloc.state.isSyncing, isFalse);
      },
    );

    test('pemicu berikutnya mencoba lagi yang gagal sampai berhasil', () async {
      repository
        ..add('a')
        ..outcomes['a'] = SyncOutcome.failed;
      bloc.add(const SyncRequested());
      await settle();
      expect(bloc.state.lastRunFailed, isTrue);

      repository.outcomes.remove('a'); // internet kembali
      bloc.add(const SyncRequested());
      await settle();

      expect(repository.statuses['a'], SyncStatus.synced);
      expect(bloc.state.lastRunFailed, isFalse);
      expect(bloc.state.unsyncedCount, 0);
    });

    test(
      'sesi berakhir (401/403) -> berhenti, transaksi tetap pending',
      () async {
        repository
          ..add('a')
          ..add('b')
          ..outcomes['a'] = SyncOutcome.sessionExpired;

        bloc.add(const SyncRequested());
        await settle();

        expect(repository.sent, ['a']);
        expect(repository.statuses['a'], SyncStatus.pending);
        expect(repository.statuses['b'], SyncStatus.pending);
        expect(bloc.state.unsyncedCount, 2);
        expect(bloc.state.lastRunFailed, isTrue);
      },
    );

    test(
      'galat tak terduga -> berhenti, BLoC tetap hidup dan bisa mencoba lagi',
      () async {
        repository
          ..add('a')
          ..add('b')
          ..throwing.add('a');

        bloc.add(const SyncRequested());
        await settle();

        expect(repository.sent, ['a']);
        expect(bloc.state.lastRunFailed, isTrue);
        expect(bloc.state.isSyncing, isFalse);

        repository.throwing.clear();
        bloc.add(const SyncRequested());
        await settle();

        expect(repository.statuses['a'], SyncStatus.synced);
        expect(repository.statuses['b'], SyncStatus.synced);
      },
    );

    test(
      'antrean tidak terbaca -> tidak crash dan tidak mengubah tampilan',
      () async {
        repository.queueError = StateError('sqlite');

        bloc.add(const SyncRequested());
        await settle();

        expect(bloc.state, const SyncState());
        expect(bloc.isClosed, isFalse);
      },
    );
  });

  group('konflik', () {
    test(
      'conflict tidak menghentikan putaran; terhitung dan memicu pembaruan katalog',
      () async {
        repository
          ..add('a')
          ..add('b')
          ..outcomes['a'] = SyncOutcome.conflict;

        bloc.add(const SyncRequested());
        await settle();

        expect(repository.sent, ['a', 'b']);
        expect(repository.statuses['a'], SyncStatus.conflict);
        expect(repository.statuses['b'], SyncStatus.synced);
        expect(bloc.state.conflictCount, 1);
        expect(bloc.state.unsyncedCount, 0);
        expect(bloc.state.lastRunFailed, isFalse);
        expect(bloc.state.changeRevision, 1);
      },
    );

    test('conflict tidak dikirim ulang oleh putaran berikutnya', () async {
      repository
        ..add('a')
        ..outcomes['a'] = SyncOutcome.conflict;
      bloc.add(const SyncRequested());
      await settle();

      bloc.add(const SyncRequested());
      await settle();

      expect(repository.sent, ['a']);
      expect(bloc.state.conflictCount, 1);
    });

    test('dilewati (skipped) tidak mengubah apa pun', () async {
      repository
        ..add('a')
        ..outcomes['a'] = SyncOutcome.skipped;

      bloc.add(const SyncRequested());
      await settle();

      expect(bloc.state.changeRevision, 0);
      expect(bloc.state.lastRunFailed, isFalse);
    });
  });

  group('satu putaran pada satu waktu (Rule 5)', () {
    test('dua pemicu bersamaan: transaksi dikirim tepat sekali', () async {
      repository.add('a');
      final gate = repository.gates['a'] = Completer<void>();

      bloc
        ..add(const SyncRequested())
        ..add(const SyncRequested());
      await settle();
      expect(repository.sent, ['a']); // putaran kedua tidak ikut mengirim

      gate.complete();
      await settle();

      expect(repository.sent, ['a']);
      expect(repository.statuses['a'], SyncStatus.synced);
    });

    test(
      'pemicu yang tiba saat mengirim membuat putaran diulang, tanpa menunggu timer',
      () async {
        repository.add('a');
        final gate = repository.gates['a'] = Completer<void>();

        bloc.add(const SyncRequested());
        await settle();
        expect(bloc.state.isSyncing, isTrue);

        // Kasir membayar lagi saat 'a' masih dikirim.
        repository.add('b');
        bloc.add(const SyncRequested());
        await settle();
        expect(repository.sent, ['a']);

        gate.complete();
        await settle();

        expect(repository.sent, ['a', 'b']);
        expect(repository.statuses['b'], SyncStatus.synced);
        expect(bloc.state.unsyncedCount, 0);
      },
    );

    test('BLoC ditutup di tengah putaran -> sisanya tidak dikirim', () async {
      repository
        ..add('a')
        ..add('b');
      final gate = repository.gates['a'] = Completer<void>();

      bloc.add(const SyncRequested());
      await settle();
      // Kasir keluar dari akun saat 'a' masih dikirim. close() menunggu
      // handler selesai, jadi jangan di-await sebelum gerbang dibuka.
      final closing = bloc.close();
      gate.complete();
      await closing;

      expect(repository.sent, ['a']);
      expect(repository.statuses['b'], SyncStatus.pending); // utuh
    });
  });
}
