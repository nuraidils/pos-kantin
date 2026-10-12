import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:kasir_kantin/features/sync/presentation/widgets/sync_status_banner.dart';
import 'package:mocktail/mocktail.dart';

class MockSyncBloc extends MockBloc<SyncEvent, SyncState> implements SyncBloc {}

void main() {
  late MockSyncBloc bloc;

  setUpAll(() => registerFallbackValue(const SyncRequested()));

  setUp(() => bloc = MockSyncBloc());

  Future<void> pumpBanner(WidgetTester tester, SyncState state) async {
    whenListen(bloc, const Stream<SyncState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BlocProvider<SyncBloc>.value(
            value: bloc,
            child: const SyncStatusBanner(),
          ),
        ),
      ),
    );
  }

  testWidgets('semua beres -> tidak menampilkan apa pun', (tester) async {
    await pumpBanner(tester, const SyncState());

    expect(find.byType(Text), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('menunggu -> jumlah transaksi dalam bahasa Indonesia', (
    tester,
  ) async {
    await pumpBanner(tester, const SyncState(unsyncedCount: 3));

    expect(find.text('3 transaksi menunggu sinkronisasi'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsNothing);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
  });

  testWidgets(
    'sedang mengirim -> "Menyinkronkan N transaksi..." dengan penanda',
    (tester) async {
      await pumpBanner(
        tester,
        const SyncState(isSyncing: true, unsyncedCount: 2),
      );

      expect(find.text('Menyinkronkan 2 transaksi...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('3 transaksi menunggu sinkronisasi'), findsNothing);
    },
  );

  testWidgets(
    'mengirim tetapi antrean sudah kosong -> tidak menampilkan apa pun',
    (tester) async {
      await pumpBanner(tester, const SyncState(isSyncing: true));

      expect(find.byType(Text), findsNothing);
    },
  );

  testWidgets(
    'gagal -> pesan tenang, otomatis dicoba lagi, dan tombol Coba Lagi',
    (tester) async {
      await pumpBanner(
        tester,
        const SyncState(unsyncedCount: 2, lastRunFailed: true),
      );

      expect(
        find.text('2 transaksi belum tersinkron. Akan dicoba lagi otomatis.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Coba Lagi'));

      verify(() => bloc.add(const SyncRequested())).called(1);
    },
  );

  testWidgets('konflik -> "perlu perhatian", tidak pernah disembunyikan', (
    tester,
  ) async {
    await pumpBanner(tester, const SyncState(conflictCount: 1));

    expect(find.text('1 transaksi perlu perhatian'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('menunggu dan konflik tampil bersamaan', (tester) async {
    await pumpBanner(
      tester,
      const SyncState(unsyncedCount: 2, conflictCount: 1),
    );

    expect(find.text('2 transaksi menunggu sinkronisasi'), findsOneWidget);
    expect(find.text('1 transaksi perlu perhatian'), findsOneWidget);
  });
}
