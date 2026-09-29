// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/shared/widgets/cards/user_card.dart';

void main() {
  group('UserCard widget', () {
    test('userSubtitle formats followers and states correctly', () {
      final regularUser = GenericSimpleUser(
        id: 'user1',
        source: 'spotify',
        displayName: 'Alice',
        followerCount: 42,
      );
      expect(userSubtitle(regularUser), '42 followers');

      final singleFollower = GenericSimpleUser(
        id: 'user2',
        source: 'spotify',
        displayName: 'Bob',
        followerCount: 1,
      );
      expect(userSubtitle(singleFollower), '1 follower');

      final followedUser = GenericSimpleUser(
        id: 'user3',
        source: 'spotify',
        displayName: 'Charlie',
        isFollowed: true,
        followerCount: 100,
      );
      expect(userSubtitle(followedUser), 'Follows you');

      final artistUser = GenericSimpleUser(
        id: 'user4',
        source: 'spotify',
        displayName: 'Dave',
        profileUrl: 'spotify:artist:12345',
        followerCount: 5000,
      );
      expect(userSubtitle(artistUser), 'Artist');

      final largeCountUser = GenericSimpleUser(
        id: 'user5',
        source: 'spotify',
        displayName: 'Eve',
        followerCount: 1500000,
      );
      expect(userSubtitle(largeCountUser), '1.5M followers');
    });

    testWidgets('renders user displayName and subtitle', (tester) async {
      final user = GenericSimpleUser(
        id: 'user1',
        source: 'spotify',
        displayName: 'Test User',
        followerCount: 10,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: UserCard(user: user),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('10 followers'), findsOneWidget);
    });

    testWidgets('renders explicit custom subtitle when provided', (tester) async {
      final user = GenericSimpleUser(
        id: 'user2',
        source: 'spotify',
        displayName: 'Custom User',
        followerCount: 10,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: UserCard(
                  user: user,
                  subtitle: 'Custom Subtitle Here',
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Custom User'), findsOneWidget);
      expect(find.text('Custom Subtitle Here'), findsOneWidget);
      expect(find.text('10 followers'), findsNothing);
    });

    testWidgets('UserCard.fromUser instantiates and displays correctly',
        (tester) async {
      final fullUser = GenericUser(
        id: 'full_user_1',
        source: 'spotify',
        displayName: 'Full Profile User',
        avatarUrl: null,
        followerCount: 350,
        followingCount: 10,
        recentArtists: const [],
        publicPlaylists: const [],
        followers: const [],
        following: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: UserCard.fromUser(user: fullUser),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Full Profile User'), findsOneWidget);
      expect(find.text('350 followers'), findsOneWidget);
    });
  });
}
