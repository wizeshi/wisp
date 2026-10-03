// Copyright © 2026 wizeshi

part of '../../list_detail_view.dart';

/// Original list detail renderer — redirects to Spotify layout for now until M3E / Liquid Glass are officially supported.
class _OriginalListDetailRenderer extends StatelessWidget {
  final _SharedListDetailViewState view;
  final String title;
  final String? subtitle;
  final GenericSimpleUser? subtitleUser;
  final String imageUrl;
  final String? subtitleImageUrl;
  final int total;
  final bool isDesktop;
  final String? description;

  const _OriginalListDetailRenderer({
    required this.view,
    required this.title,
    required this.subtitle,
    required this.subtitleUser,
    required this.imageUrl,
    required this.subtitleImageUrl,
    required this.total,
    required this.isDesktop,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return _SpotifyListDetailRenderer(
      view: view,
      title: title,
      subtitle: subtitle,
      subtitleUser: subtitleUser,
      imageUrl: imageUrl,
      subtitleImageUrl: subtitleImageUrl,
      total: total,
      isDesktop: isDesktop,
      description: description,
    );
  }
}
