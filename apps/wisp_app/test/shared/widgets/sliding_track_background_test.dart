// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/shared/widgets/display/sliding_track_background.dart';

void main() {
  group('SlidingTrackBackground', () {
    testWidgets(
      'does not trigger switch animation when only queueIndex changes (shuffle toggled)',
      (tester) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SlidingTrackBackground(
              transitionToken: 1,
              trackId: 'track_1',
              queueIndex: 5,
              duration: const Duration(milliseconds: 300),
              child: const SizedBox(key: ValueKey('content'), width: 100, height: 100),
            ),
          ),
        );

        final slideFinder = find.descendant(
          of: find.byType(SlidingTrackBackground),
          matching: find.byType(SlideTransition),
        );

        // Verify initial state has 1 SlideTransition in SlidingTrackBackground
        expect(slideFinder, findsOneWidget);

        // Simulate shuffle toggle: queueIndex changes from 5 to 0, trackId and transitionToken remain identical
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SlidingTrackBackground(
              transitionToken: 1,
              trackId: 'track_1',
              queueIndex: 0,
              duration: const Duration(milliseconds: 300),
              child: const SizedBox(key: ValueKey('content'), width: 100, height: 100),
            ),
          ),
        );

        // Advance a bit of time to see if any animation was scheduled
        await tester.pump(const Duration(milliseconds: 50));

        // AnimatedSwitcher should NOT have spawned a second SlideTransition for outgoing/incoming child
        expect(slideFinder, findsOneWidget);
      },
    );

    testWidgets(
      'triggers switch animation when trackId or transitionToken changes',
      (tester) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SlidingTrackBackground(
              transitionToken: 1,
              trackId: 'track_1',
              queueIndex: 0,
              duration: const Duration(milliseconds: 300),
              child: const SizedBox(key: ValueKey('content_1'), width: 100, height: 100),
            ),
          ),
        );

        final slideFinder = find.descendant(
          of: find.byType(SlidingTrackBackground),
          matching: find.byType(SlideTransition),
        );

        expect(slideFinder, findsOneWidget);

        // Change track
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SlidingTrackBackground(
              transitionToken: 2,
              trackId: 'track_2',
              queueIndex: 1,
              duration: const Duration(milliseconds: 300),
              child: const SizedBox(key: ValueKey('content_2'), width: 100, height: 100),
            ),
          ),
        );

        // Advance mid-transition
        await tester.pump(const Duration(milliseconds: 50));

        // In the middle of transition, AnimatedSwitcher has both outgoing and incoming SlideTransitions
        expect(slideFinder, findsNWidgets(2));

        // Complete transition
        await tester.pumpAndSettle();
        expect(slideFinder, findsOneWidget);
      },
    );
  });
}
