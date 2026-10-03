// Copyright © 2026 wizeshi

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';

void main() {
  group('DesktopSmoothScrollBehavior', () {
    testWidgets('provides ClampingScrollPhysics and desktop drag devices',
        (tester) async {
      const behavior = DesktopSmoothScrollBehavior();
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            final physics = behavior.getScrollPhysics(context);
            expect(physics, isA<ClampingScrollPhysics>());
            expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
            expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
            expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
            return const Placeholder();
          },
        ),
      );
    });
  });

  group('SmoothScrollController and SmoothScrollPosition', () {
    testWidgets('creates SmoothScrollPosition and responds to pointerScroll',
        (tester) async {
      final controller = SmoothScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: ListView.builder(
                controller: controller,
                itemCount: 50,
                itemBuilder: (context, index) => SizedBox(
                  height: 40,
                  child: Text('Item $index'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(controller.position, isA<SmoothScrollPosition>());
      final pos = controller.position as SmoothScrollPosition;
      expect(pos.pixels, 0.0);

      // Simulate a mouse pointer scroll event
      pos.pointerScroll(100.0);
      expect(pos.activity, isA<SmoothScrollActivity>());

      // Pump frames to let exponential smoothing progress
      await tester.pump(const Duration(milliseconds: 50));
      expect(pos.pixels, greaterThan(0.0));

      // Pump until idle
      await tester.pumpAndSettle();
      expect(pos.pixels, 100.0);
    });

    testWidgets('proxies to clientController transparently', (tester) async {
      final clientController = ScrollController();
      addTearDown(clientController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: WispListView.builder(
                controller: clientController,
                itemCount: 50,
                itemBuilder: (context, index) => SizedBox(
                  height: 40,
                  child: Text('Item $index'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(clientController.hasClients, isTrue);
      expect(clientController.position, isA<SmoothScrollPosition>());
      expect(clientController.offset, 0.0);

      final pos = clientController.position as SmoothScrollPosition;
      pos.pointerScroll(80.0);
      await tester.pumpAndSettle();
      expect(clientController.offset, 80.0);
    });
  });

  group('WispSingleChildScrollView', () {
    testWidgets('renders child and supports smooth pointer scrolling',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: WispSingleChildScrollView(
                controller: controller,
                child: Column(
                  children: List.generate(
                    30,
                    (i) => SizedBox(height: 30, child: Text('Row $i')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Row 0'), findsOneWidget);
      expect(controller.hasClients, isTrue);
      expect(controller.position, isA<SmoothScrollPosition>());

      final pos = controller.position as SmoothScrollPosition;
      pos.pointerScroll(60.0);
      await tester.pumpAndSettle();
      expect(controller.offset, 60.0);
    });
  });

  group('WispListView', () {
    testWidgets('standard WispListView renders children and attaches SmoothScrollPosition',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: WispListView(
                controller: controller,
                children: const [
                  SizedBox(height: 50, child: Text('Child 1')),
                  SizedBox(height: 50, child: Text('Child 2')),
                  SizedBox(height: 50, child: Text('Child 3')),
                  SizedBox(height: 50, child: Text('Child 4')),
                  SizedBox(height: 50, child: Text('Child 5')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Child 1'), findsOneWidget);
      expect(controller.position, isA<SmoothScrollPosition>());
    });

    testWidgets('WispListView.builder renders items with SmoothScrollPosition',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: WispListView.builder(
                controller: controller,
                itemCount: 20,
                itemBuilder: (context, index) => SizedBox(
                  height: 40,
                  child: Text('Built $index'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Built 0'), findsOneWidget);
      expect(controller.position, isA<SmoothScrollPosition>());
    });

    testWidgets('WispListView.separated renders items and separators',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: WispListView.separated(
                controller: controller,
                itemCount: 5,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) => SizedBox(
                  height: 40,
                  child: Text('Sep $index'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Sep 0'), findsOneWidget);
      expect(find.byType(Divider), findsWidgets);
      expect(controller.position, isA<SmoothScrollPosition>());
    });
  });

  group('WispCustomScrollView', () {
    testWidgets('renders slivers with SmoothScrollPosition', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: WispCustomScrollView(
                controller: controller,
                slivers: [
                  SliverToBoxAdapter(
                    child: Container(height: 100, color: Colors.red),
                  ),
                  SliverToBoxAdapter(
                    child: Container(height: 200, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(controller.hasClients, isTrue);
      expect(controller.position, isA<SmoothScrollPosition>());

      final pos = controller.position as SmoothScrollPosition;
      pos.pointerScroll(50.0);
      await tester.pumpAndSettle();
      expect(controller.offset, 50.0);
    });
  });
}
