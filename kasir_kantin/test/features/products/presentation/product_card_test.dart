import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/core/theme/app_theme.dart';
import 'package:kasir_kantin/features/products/domain/product.dart';
import 'package:kasir_kantin/features/products/presentation/widgets/product_card.dart';

Product product({int stock = 10}) => Product(
  id: 1,
  categoryId: 1,
  name: 'Nasi Goreng',
  price: 15000,
  stock: stock,
  isActive: true,
  updatedAt: '2026-10-17T00:00:00Z',
);

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    Product product, {
    VoidCallback? onTap,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          width: 180,
          height: 240,
          child: ProductCard(product: product, onTap: onTap),
        ),
      ),
    ),
  );

  SemanticsProperties semantics(WidgetTester tester) => tester
      .widget<Semantics>(
        find
            .descendant(
              of: find.byType(ProductCard),
              matching: find.byType(Semantics),
            )
            .first,
      )
      .properties;

  testWidgets('produk tersedia: tombol aktif dan dapat diketuk', (
    tester,
  ) async {
    var taps = 0;
    await pumpCard(tester, product(), onTap: () => taps++);

    expect(semantics(tester).button, isTrue);
    expect(semantics(tester).enabled, isTrue);

    await tester.tap(find.byType(ProductCard));
    expect(taps, 1);
  });

  testWidgets('produk habis: nonaktif, tampil "Habis", tidak dapat diketuk', (
    tester,
  ) async {
    var taps = 0;
    await pumpCard(tester, product(stock: 0), onTap: () => taps++);

    expect(semantics(tester).button, isTrue);
    expect(semantics(tester).enabled, isFalse);
    expect(find.text('Habis'), findsOneWidget);

    await tester.tap(find.byType(ProductCard));
    expect(taps, 0);
  });

  testWidgets('stok menipis menampilkan teks peringatan', (tester) async {
    await pumpCard(tester, product(stock: 3), onTap: () {});

    expect(find.text('Stok tersisa 3'), findsOneWidget);
  });
}
