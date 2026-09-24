// Copyright © 2026 wizeshi

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/utils/text_parser.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/features/details/views/artist_detail_view.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/features/shell/navigation/navigation_state.dart';

class MobileArtistInfoCard extends StatefulWidget {
  final GenericSimpleArtist artist;
  final String? trackId;

  const MobileArtistInfoCard({
    super.key,
    required this.artist,
    this.trackId,
  });

  @override
  State<MobileArtistInfoCard> createState() => _MobileArtistInfoCardState();
}

class _MobileArtistInfoCardState extends State<MobileArtistInfoCard> {
  Future<GenericArtist?>? _artistFuture;
  String? _artistId;
  String? _trackId;

  @override
  Widget build(BuildContext context) {
    if (_artistId != widget.artist.id || _trackId != widget.trackId) {
      _artistId = widget.artist.id;
      _trackId = widget.trackId;
      final spotifyInternal = context.read<SpotifyInternalProvider>();
      _artistFuture = _loadArtist(
        spotifyInternal,
        widget.artist,
        widget.trackId,
      );
    }

    return FutureBuilder<GenericArtist?>(
      future: _artistFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final imageUrl = data?.thumbnailUrl.isNotEmpty == true
            ? data!.thumbnailUrl
            : widget.artist.thumbnailUrl;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 320,
                      width: double.infinity,
                      child: imageUrl.isEmpty
                          ? Container(color: Colors.grey[850])
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  Container(color: Colors.grey[850]),
                            ),
                    ),
                    Positioned(
                      left: 16,
                      top: 16,
                      child: Text(
                        'Artist Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            data?.name ?? widget.artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () async {
                            await _openArtist(data, widget.artist);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('Open'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data == null
                          ? 'Loading artist info…'
                          : '${_formatNumber(data.followers)} monthly listeners',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    if (data != null) ...[
                      const SizedBox(height: 6),
                      (data.description?.trim().isNotEmpty == true)
                          ? buildParsedText(
                              context,
                              data.description!.trim(),
                              style: TextStyle(
                                color: Colors.grey[200],
                                fontSize: 13,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text(
                              'No description available for this artist.',
                              style: TextStyle(
                                color: Colors.grey[200],
                                fontSize: 13,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<GenericArtist?> _loadArtist(
    SpotifyInternalProvider spotify,
    GenericSimpleArtist artist,
    String? trackId,
  ) async {
    try {
      if (trackId != null && trackId.isNotEmpty) {
        return await spotify.getNpvArtistInfo(artist.id, trackId);
      }
      return await spotify.getArtistInfo(artist.id);
    } catch (_) {
      return null;
    }
  }

  String _formatNumber(int value) {
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  Future<void> _openArtist(
    GenericArtist? data,
    GenericSimpleArtist fallback,
  ) async {
    final libraryState = context.read<LibraryState>();
    final navState = context.read<NavigationState>();
    final artist = data == null
        ? fallback
        : GenericSimpleArtist(
            id: data.id,
            source: data.source,
            name: data.name,
            thumbnailUrl: data.thumbnailUrl,
          );

    await AppNavigation.instance.disableFullPlayerDesktopMode();
    if (!mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ArtistDetailView(
              artistId: artist.id,
              initialArtist: artist,
              playlists: libraryState.playlists,
              albums: libraryState.albums,
              artists: libraryState.artists,
              initialLibraryView: navState.selectedLibraryView,
              initialNavIndex: navState.selectedNavIndex,
            ),
      ),
    );
  }
}

