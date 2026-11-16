import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cafe_management_system/models/models.dart';
import 'package:cafe_management_system/theme/app_theme.dart';
import 'package:cafe_management_system/widgets/addon_picker.dart';
import 'package:cafe_management_system/widgets/customer_order_widgets.dart';
import 'package:cafe_management_system/widgets/shared_widgets.dart';

void main() {
  const phoneSizes = [Size(320, 640), Size(375, 812), Size(430, 932)];

  for (final size in phoneSizes) {
    testWidgets('order line and status fit ${size.width.toInt()}px phone', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final product = Product(
        id: 'test-latte',
        name: 'Vanilla latte with an extra-long customer-facing product name',
        category: 'Coffee',
        price: 5.25,
      );
      final item = CartItem(
        product: product,
        quantity: 2,
        selectedAddOns: [
          MenuAddOn(
            name: 'Extra espresso shot',
            price: 0.75,
            quantity: 2,
            allowQuantity: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StatusBadge(status: 'Preparing'),
                      const SizedBox(height: 12),
                      CustomerOrderItems(items: [item]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('2×'), findsOneWidget);
      expect(find.textContaining('Vanilla latte'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone add-on picker edits quantity and returns the selection', (
    tester,
  ) async {
    const phone = Size(320, 640);
    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final product = Product(
      id: 'custom-latte',
      name: 'Latte',
      category: 'Coffee',
      price: 4.5,
      addOns: [
        MenuAddOn(
          name: 'Extra espresso shot',
          price: 0.75,
          category: 'Extras',
          allowQuantity: true,
        ),
        MenuAddOn(name: 'Vanilla', price: 0.5, category: 'Flavors'),
      ],
    );
    List<MenuAddOn>? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showAddOnPickerDialog(
                    context: context,
                    product: product,
                    helperText: 'Choose a flavor and any extras.',
                  );
                },
                child: const Text('Open customizer'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open customizer'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(product.addOns, hasLength(2));
    expect(find.text('Flavors (Choose 1)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final dialogList = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Extra espresso shot'),
      100,
      scrollable: dialogList.last,
    );
    expect(find.text('Extras'), findsOneWidget);

    final increase = find.byTooltip('Increase Extra espresso shot');
    await tester.ensureVisible(increase);
    await tester.pumpAndSettle();
    await tester.tap(increase);
    await tester.pump();
    await tester.tap(increase);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(find.text('1 customization selected'), findsOneWidget);
    await tester.tap(find.textContaining('Apply'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result, hasLength(1));
    expect(result!.single.name, 'Extra espresso shot');
    expect(result!.single.quantity, 2);
    expect(tester.takeException(), isNull);
  });
}
