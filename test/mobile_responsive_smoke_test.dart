import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cafe_management_system/screens/auth/login_screen.dart';
import 'package:cafe_management_system/screens/auth/register_screen.dart';
import 'package:cafe_management_system/theme/app_theme.dart';
import 'package:cafe_management_system/widgets/shared_widgets.dart';

const _phoneSizes = <Size>[
  Size(320, 640),
  Size(375, 812),
  Size(430, 932),
];

void main() {
  for (final size in _phoneSizes) {
    testWidgets('customer navigation fits ${size.width.toInt()}px phone',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(() {
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.binding.setSurfaceSize(null);
      });

      var selectedIndex = 0;
      final items = [
        NavItem(
          icon: Icons.storefront_outlined,
          label: 'Menu',
          builder: () => const SizedBox.shrink(),
        ),
        NavItem(
          icon: Icons.receipt_long_outlined,
          label: 'My Orders',
          builder: () => const SizedBox.shrink(),
        ),
        NavItem(
          icon: Icons.history_outlined,
          label: 'Order History',
          builder: () => const SizedBox.shrink(),
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            appBar: AppBar(title: const Text('Overnight Cafe')),
            body: Center(child: Text('Selected tab: $selectedIndex')),
            bottomNavigationBar: MobileBottomNavigation(
              items: items,
              selectedIndex: selectedIndex,
              onSelected: (index) => setState(() => selectedIndex = index),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('My Orders'), findsOneWidget);
      expect(find.text('Order History'), findsOneWidget);
      expect(
        tester.getRect(find.text('Order History')).bottom,
        lessThanOrEqualTo(size.height - 24),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Order History'));
      await tester.pumpAndSettle();
      expect(find.text('Selected tab: 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'login and registration scroll cleanly at ${size.width.toInt()}px',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(() {
        tester.view.resetPadding();
        tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: const LoginScreen(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Welcome Back'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your email address.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: const RegisterScreen(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Join Overnight Cafe'), findsOneWidget);
      expect(find.byTooltip('Show password'), findsWidgets);
      final showPassword = find.byTooltip('Show password').first;
      await tester.ensureVisible(showPassword);
      await tester.tap(showPassword);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide password'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
