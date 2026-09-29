// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/shared/widgets/layout/mobile_bottom_padding.dart';

void main() {
  group('mobileBottomBarPadding and MobileBottomPaddingSliver', () {
    testWidgets('mobileBottomBarPadding returns extra padding on desktop runner',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final padding = mobileBottomBarPadding(context, extra: 24.0);
              // On desktop test runner, returns base extra padding
              expect(padding, 24.0);
              return const Placeholder();
            },
          ),
        ),
      );
    });

    testWidgets('MobileBottomPaddingSliver renders SizedBox with computed height in CustomScrollView',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: 50)),
                MobileBottomPaddingSliver(extra: 24.0),
              ],
            ),
          ),
        ),
      );

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      expect(sizedBoxes.any((box) => box.height == 24.0), isTrue);
    });
  });
}
