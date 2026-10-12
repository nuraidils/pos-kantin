import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:kasir_kantin/features/sync/presentation/widgets/sync_scheduler.dart';
import 'package:mocktail/mocktail.dart';

class MockSyncBloc extends MockBloc<SyncEvent, SyncState> implements SyncBloc {}

void main() {
  late MockSyncBloc bloc;

  setUpAll(() => registerFallbackValue(const SyncRequested()));

  setUp(() {
    bloc = MockSyncBloc();
    whenListen(
      bloc,
      const Stream<SyncState>.empty(),
      initialState: const SyncState(),
    );
  });

  Future<void> pumpScheduler(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SyncBloc>.value(
          value: bloc,
          child: const SyncScheduler(
            interval: Duration(seconds: 30),
            child: Text('isi'),
          ),
        ),
      ),
    );
  }

  testWidgets('menampilkan anaknya apa adanya', (tester) async {
    await pumpScheduler(tester);

    expect(find.text('isi'), findsOneWidget);
  });

  testWidgets('tidak memicu apa pun sebelum interval pertama', (tester) async {
    await pumpScheduler(tester);

    await tester.pump(const Duration(seconds: 29));

    verifyNever(() => bloc.add(any()));
  });

  testWidgets('memicu SyncRequested di setiap interval', (tester) async {
    await pumpScheduler(tester);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));

    verify(() => bloc.add(const SyncRequested())).called(2);
  });

  testWidgets('aplikasi dibuka kembali -> memicu SyncRequested', (
    tester,
  ) async {
    await pumpScheduler(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    verifyNever(() => bloc.add(any()));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    verify(() => bloc.add(const SyncRequested())).called(1);
  });

  testWidgets('setelah dilepas, timer berhenti dan tidak memicu lagi', (
    tester,
  ) async {
    await pumpScheduler(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    await tester.pump(const Duration(seconds: 90));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    verifyNever(() => bloc.add(any()));
  });
}
