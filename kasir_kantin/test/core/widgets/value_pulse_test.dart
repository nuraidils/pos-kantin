import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/widgets/value_pulse.dart';

void main() {
  Widget host(int value, {bool disableAnimations = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: ValuePulse(value: value, child: Text('$value')),
    ),
  );

  double scale(WidgetTester tester) =>
      tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value;

  testWidgets('tidak beranimasi saat pertama kali tampil', (tester) async {
    await tester.pumpWidget(host(1));

    expect(find.text('1'), findsOneWidget);
    expect(scale(tester), 1.0);
  });

  testWidgets('membesar sebentar saat nilai berubah lalu kembali', (
    tester,
  ) async {
    await tester.pumpWidget(host(1));
    await tester.pumpWidget(host(2));
    await tester.pump(const Duration(milliseconds: 80));

    expect(scale(tester), greaterThan(1.05));
    // Teks tetap satu (tidak ada salinan lama yang ikut tampil).
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(1.0, 0.0001));
  });

  testWidgets('tidak beranimasi bila nilai sama', (tester) async {
    await tester.pumpWidget(host(3));
    await tester.pumpWidget(host(3));
    await tester.pump(const Duration(milliseconds: 80));

    expect(scale(tester), 1.0);
  });

  testWidgets('tidak beranimasi bila sistem meminta animasi dikurangi', (
    tester,
  ) async {
    await tester.pumpWidget(host(1, disableAnimations: true));
    await tester.pumpWidget(host(2, disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 80));

    expect(scale(tester), 1.0);
  });
}
