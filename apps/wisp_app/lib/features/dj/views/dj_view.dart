import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/services/system/listening_habits_service.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/shared/widgets/rails/card_rail.dart';

import '../data/dj_constants.dart';
import '../models/dj_chat_message.dart';
import '../widgets/dj_now_playing_banner.dart';
import '../widgets/dj_chat_bubble.dart';

/// In-memory session message store for the DJ chat.
/// Preserved during the app session and automatically resets on app restart.
final List<DJChatMessage> _sessionDJMessages = [];

class DJView extends StatefulWidget {
  const DJView({super.key});

  @override
  State<DJView> createState() => _DJViewState();
}

class _DJViewState extends State<DJView> {
  late final List<DJChatMessage> _messages;
  late final ValueNotifier<List<DJChatMessage>> _chatMessagesNotifier;
  late final TextEditingController _textSubmissionController;
  final ScrollController _scrollController = ScrollController();

  bool _isBlocked = false;
  double _lastViewInsetsBottom = 0;

  late final Map<String, String> _randomSuggestions;
  late final String _randomTitle;
  late final String _randomHint;

  Map<String, String> _buildDynamicSuggestions() {
    final habits = ListeningHabitsService.instance;
    final freq = habits.genreFrequency;

    // 1. Sort user's listened genres descending by play count
    final sortedUserGenres = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final selectedGenres = <String>[];
    final seen = <String>{};

    for (final entry in sortedUserGenres) {
      final g = entry.key.trim();
      if (g.isNotEmpty && seen.add(g.toLowerCase())) {
        selectedGenres.add(g);
      }
      if (selectedGenres.length >= 9) break;
    }

    // 2. If fewer than 9 genres listened to, fill remainder from detectedSpotifyGenres
    if (selectedGenres.length < 9) {
      final fallbackPool = List<String>.from(detectedSpotifyGenres)..shuffle();
      for (final g in fallbackPool) {
        if (seen.add(g.toLowerCase())) {
          selectedGenres.add(g);
        }
        if (selectedGenres.length >= 9) break;
      }
    }

    // 3. Map to predetermined templates
    final templates = List<String>.from(djSuggestionTemplates)..shuffle();
    final suggestions = <MapEntry<String, String>>[];
    for (int i = 0; i < selectedGenres.length; i++) {
      final genre = selectedGenres[i];
      final template = templates[i % templates.length];
      final text = template.replaceAll('{genre}', genre);
      suggestions.add(MapEntry(genre.toLowerCase(), text));
    }

    // 4. Shuffle so most listened is not the left-most suggestion
    suggestions.shuffle();

    return Map<String, String>.fromEntries(suggestions);
  }

  @override
  void initState() {
    super.initState();
    _messages = _sessionDJMessages;
    _chatMessagesNotifier = ValueNotifier(List.from(_messages));
    _textSubmissionController = TextEditingController();

    _randomSuggestions = _buildDynamicSuggestions();
    _randomTitle = (List.from(djTextInputTitles)..shuffle()).first;
    _randomHint = (List.from(djTextInputHints)..shuffle()).first;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final spotify = context.read<SpotifyInternalProvider>();
        ListeningHabitsService.instance.bindSpotifyProvider(spotify);
        if (_messages.isNotEmpty) {
          _scrollToBottom();
        }
      }
    });
  }

  @override
  void dispose() {
    _textSubmissionController.dispose();
    _scrollController.dispose();
    _chatMessagesNotifier.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String? _detectArtist(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return null;

    final artists = ListeningHabitsService.instance.allUniqueArtists.toList();
    artists.sort((a, b) {
      final aWords = a.split(' ').length;
      final bWords = b.split(' ').length;
      if (aWords != bWords) {
        return bWords.compareTo(aWords);
      }
      return b.length.compareTo(a.length);
    });

    for (final artist in artists) {
      final pattern = RegExp(
        r'(?:^|[^a-zA-Z0-9])' +
            RegExp.escape(artist.toLowerCase()) +
            r'(?:$|[^a-zA-Z0-9])',
        caseSensitive: false,
      );
      if (pattern.hasMatch(clean)) {
        return artist;
      }
    }

    return null;
  }

  /// Detects which track tag or genre best matches the user query.
  String? _detectGenreTag(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return null;

    // 1. Direct match with current dynamic suggestions values
    for (final entry in _randomSuggestions.entries) {
      final suggestionLower = entry.value.toLowerCase();
      if (clean == suggestionLower || clean.contains(suggestionLower)) {
        return entry.key;
      }
    }

    // 2. Direct match with tag keys
    if (_randomSuggestions.containsKey(clean)) {
      return clean;
    }
    if (djTagKeywords.containsKey(clean)) {
      return clean;
    }

    // 3. Specific & generic candidate matching sorted by specificity
    // Multi-word phrases (e.g. 'rap tuga', 'hip hop tuga') MUST be checked before
    // single-word genres (e.g. 'rap') to ensure specific queries are honored.
    final candidates = <(String keyword, String tag)>[];

    // Add all specific keywords from djTagKeywords (e.g. 'rap tuga', 'bossa nova', 'tuga')
    for (final entry in djTagKeywords.entries) {
      for (final kw in entry.value) {
        final k = kw.trim().toLowerCase();
        if (k.isNotEmpty) {
          candidates.add((k, entry.key));
        }
      }
    }

    // Add all detected Spotify genres (e.g. 'alternative hip hop', 'rap', 'chill')
    final allKnownGenres = <String>{
      ...detectedSpotifyGenres,
      ...ListeningHabitsService.instance.allUniqueGenres,
    };
    for (final g in allKnownGenres) {
      final gLower = g.trim().toLowerCase();
      if (gLower.isNotEmpty) {
        candidates.add((gLower, gLower));
      }
    }

    // Sort candidates:
    // Multi-word and longer phrases come first so that "rap tuga" (2 words, 8 chars)
    // always matches before "rap" (1 word, 3 chars).
    candidates.sort((a, b) {
      final aWords = a.$1.split(' ').length;
      final bWords = b.$1.split(' ').length;
      if (aWords != bWords) {
        return bWords.compareTo(aWords);
      }
      return b.$1.length.compareTo(a.$1.length);
    });

    for (final candidate in candidates) {
      final kw = candidate.$1;
      final tag = candidate.$2;
      // ignore: prefer_interpolation_to_compose_strings
      final pattern = RegExp(
        r'(?:^|[^a-zA-Z0-9])' + RegExp.escape(kw) + r'(?:$|[^a-zA-Z0-9])',
        caseSensitive: false,
      );
      if (pattern.hasMatch(clean)) {
        return tag;
      }
    }

    return null;
  }

  /// AI decision algorithm: checks for artists (first) and genres.
  /// If a known artist is mentioned, but no genre is detected/available
  /// (either unknown, not in DB, or artist does not have that genre),
  /// the genre is ignored.
  ({String? artist, String? tag}) _detectIntent(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return (artist: null, tag: null);

    // 1. Direct match with current dynamic suggestions
    for (final entry in _randomSuggestions.entries) {
      final suggestionLower = entry.value.toLowerCase();
      if (clean == suggestionLower || clean.contains(suggestionLower)) {
        return (artist: null, tag: entry.key);
      }
    }

    // 2. Check if a known artist is specified (checked before genre checking)
    final detectedArtist = _detectArtist(query);

    // 3. Check for genre tag
    final detectedTag = _detectGenreTag(query);

    if (detectedArtist != null) {
      if (detectedTag != null) {
        final artistGenres = ListeningHabitsService.instance.getGenresForArtist(
          detectedArtist,
        );
        final (keywords, _, _, _) = _getFilterForTag(detectedTag);

        final artistHasGenre = artistGenres.any((ag) {
          final agClean = ag.toLowerCase().trim();
          final tagClean = detectedTag.toLowerCase().trim();
          if (agClean == tagClean ||
              agClean.contains(tagClean) ||
              tagClean.contains(agClean)) {
            return true;
          }
          return keywords.any(
            (kw) =>
                agClean == kw.toLowerCase().trim() ||
                agClean.contains(kw.toLowerCase().trim()) ||
                kw.toLowerCase().trim().contains(agClean),
          );
        });

        if (artistHasGenre) {
          return (artist: detectedArtist, tag: detectedTag);
        } else {
          // Artist does not have that genre -> ignore the genre
          return (artist: detectedArtist, tag: null);
        }
      } else {
        // No genre detected or available -> ignore the genre
        return (artist: detectedArtist, tag: null);
      }
    }

    return (artist: null, tag: detectedTag);
  }

  String _generateDJResponse({String? detectedArtist, String? detectedTag}) {
    if (detectedArtist != null && detectedTag != null) {
      final genreTitle = detectedTag
          .split(' ')
          .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
          )
          .join(' ');
      final comboResponses = [
        'Dialing into some $genreTitle from $detectedArtist! Pure vibes coming right up.',
        'Coming right up! Queueing up $genreTitle tracks by $detectedArtist.',
        'Locked in on $detectedArtist with that $genreTitle sound. Enjoy the set!',
        'Spinning some top-tier $genreTitle cuts from $detectedArtist right now.',
      ];
      return (List<String>.from(comboResponses)..shuffle()).first;
    }

    if (detectedArtist != null) {
      final artistResponses = [
        'Cueing up the best of $detectedArtist! Let\'s dive into their sound.',
        'Locked in on $detectedArtist. Dropping into their catalog and similar tracks right now.',
        'Great choice! Setting up a curated $detectedArtist session for you.',
        'Spinning $detectedArtist! Let the music take over.',
      ];
      return (List<String>.from(artistResponses)..shuffle()).first;
    }

    if (detectedTag != null) {
      if (djTagResponses.containsKey(detectedTag)) {
        final responses = djTagResponses[detectedTag]!;
        final list = List<String>.from(responses)..shuffle();
        return list.first;
      }

      // Contextual response for dynamic genres
      final genreTitle = detectedTag
          .split(' ')
          .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
          )
          .join(' ');
      final dynamicResponses = [
        'Setting the mood with some $genreTitle! Dialing into the best tracks for your vibe.',
        'Coming right up! Queueing up a fresh wave of $genreTitle for your session.',
        'Locked in on $genreTitle. Turning up the sound and bringing you pure tunes.',
        'You got it! Spinning some top-tier $genreTitle tracks right now.',
        'Good choice. Dropping into that $genreTitle frequency—enjoy the ride!',
      ];
      return (List<String>.from(dynamicResponses)..shuffle()).first;
    }

    final fallback = List<String>.from(djUntaggedResponses)..shuffle();
    return fallback.first;
  }

  /// Resolves filter criteria (keywords, required languages, and release decade) for a detected tag.
  (
    List<String> keywords,
    List<String> requiredLanguages,
    int? minYear,
    int? maxYear,
  )
  _getFilterForTag(String tag) {
    switch (tag) {
      case 'pt_pt_rap':
        return (
          ['rap', 'hip hop', 'hip-hop', 'trap', 'tuga'],
          ['pt', 'por'],
          null,
          null,
        );
      case 'pt_pt_pop':
        return (['pop'], ['pt', 'por'], null, null);
      case 'pt_pt_fado':
        return (['fado'], ['pt', 'por'], null, null);
      case 'pt_br_samba':
        return (['samba', 'pagode'], ['pt', 'por'], null, null);
      case 'pt_br_mpb':
        return (['mpb', 'bossa nova', 'tropicalia'], ['pt', 'por'], null, null);
      case 'en_pop':
        return (['pop'], ['en', 'eng'], null, null);
      case 'en_underground':
        return (
          ['indie', 'alternative', 'underground'],
          ['en', 'eng'],
          null,
          null,
        );
      case '60s':
        return ([], [], 1960, 1969);
      case '70s':
        return ([], [], 1970, 1979);
      case '80s':
        return ([], [], 1980, 1989);
      case '90s':
        return ([], [], 1990, 1999);
      case '2000s':
        return ([], [], 2000, 2009);
      default:
        // Vague genre or specific subgenre (e.g. 'rap', 'chill', 'pop rap', 'indie rock')
        // No language restriction applied so all kinds are included!
        final explicit = djTagKeywords[tag];
        final keywords = <String>[tag];
        if (explicit != null) {
          keywords.addAll(explicit.map((k) => k.toLowerCase()));
        }
        return (keywords, <String>[], null, null);
    }
  }

  /// Resolves full track info (including track & album thumbnails) if missing.
  Future<GenericSong> _ensureTrackThumbnails(
    GenericSong track,
    SpotifyInternalProvider spotify,
  ) async {
    if (track.thumbnailUrl.isNotEmpty &&
        track.album?.thumbnailUrl != null &&
        track.album!.thumbnailUrl.isNotEmpty) {
      return track;
    }
    try {
      final cleanId = track.id.startsWith('spotify:track:')
          ? track.id.split(':').last
          : track.id;
      final info = await spotify.getTrackInfo(cleanId);
      ListeningHabitsService.instance.updateRecordThumbnail(
        trackId: track.id,
        thumbnailUrl: info.thumbnailUrl,
        albumThumbnailUrl: info.album?.thumbnailUrl,
      );
      return info;
    } catch (_) {
      return track;
    }
  }

  /// Builds the DJ session queue:
  /// 1. Grabs a safe option that the user has listened to (just one).
  /// 2. Fetches similar tracks using that safe track via the similar-tracks endpoint.
  /// 3. Gathers the rest of the user's matching listened tracks.
  /// 4. Shuffles the combined rest list (similar from endpoint + other listened).
  /// 5. Starts playing the first track (the safe one) followed by the shuffled rest.
  /// Builds the DJ session queue:
  /// 1. Grabs a safe option that the user has listened to (just one).
  /// 2. Fetches similar tracks using that safe track via the similar-tracks endpoint.
  /// 3. Gathers the rest of the user's matching listened tracks.
  /// 4. Shuffles the combined rest list (similar from endpoint + other listened).
  /// 5. Starts playing the first track (the safe one) followed by the shuffled rest.
  Future<List<GenericSong>?> _buildQueue({
    String? detectedTag,
    String? detectedArtist,
    required SpotifyInternalProvider spotify,
  }) async {
    final (keywords, requiredLanguages, minYear, maxYear) = detectedTag != null
        ? _getFilterForTag(detectedTag)
        : (<String>[], <String>[], null, null);

    final historyTracks = ListeningHabitsService.instance.getTracksMatchingTag(
      keywords: keywords,
      requiredLanguages: requiredLanguages,
      minYear: minYear,
      maxYear: maxYear,
      artistName: detectedArtist,
    );

    GenericSong? rawSafeTrack;
    if (historyTracks.isNotEmpty) {
      // Pick the user's most frequently listened compatible track as the safe track
      final trackCounts = <String, int>{};
      for (final r in ListeningHabitsService.instance.history) {
        trackCounts[r.trackId] = (trackCounts[r.trackId] ?? 0) + 1;
      }
      final sorted = List<GenericSong>.from(historyTracks)
        ..sort(
          (a, b) => (trackCounts[b.id] ?? 0).compareTo(trackCounts[a.id] ?? 0),
        );
      rawSafeTrack = sorted.first;
    } else {
      try {
        final queryTerm = detectedArtist != null
            ? (detectedTag != null
                  ? '$detectedArtist $detectedTag'
                  : detectedArtist)
            : (keywords.isNotEmpty ? keywords.first : (detectedTag ?? ''));
        final searchResults = await spotify.search(queryTerm);
        if (searchResults.tracks.isNotEmpty) {
          rawSafeTrack = searchResults.tracks.first;
        }
      } catch (_) {}
    }

    if (rawSafeTrack == null) {
      return null;
    }

    // 1. Grab a safe option that the user's listened to, just one.
    final safeTrack = await _ensureTrackThumbnails(rawSafeTrack, spotify);

    // 2. Use that safe track in the endpoint to fetch similar ones.
    final similarTracks = <GenericSong>[];
    try {
      final cleanId = safeTrack.id.startsWith('spotify:track:')
          ? safeTrack.id.split(':').last
          : safeTrack.id;
      final similar = await spotify.getSimilarTracks(cleanId);
      if (similar != null) {
        for (final item in similar) {
          if (item.id != safeTrack.id) {
            similarTracks.add(
              GenericSong(
                id: item.id,
                source: item.source,
                title: item.title,
                artists: item.artists,
                thumbnailUrl: item.thumbnailUrl,
                explicit: item.explicit,
                durationSecs: item.durationSecs,
                album: item.album,
              ),
            );
          }
        }
      }
    } catch (_) {
      // Silently proceed if similar tracks fetch fails
    }

    // 3. Get the rest of the user's similar listened tracks.
    final otherHistoryRaw = historyTracks
        .where((t) => t.id != safeTrack.id)
        .toList();

    // Ensure thumbnails for other history tracks
    final otherHistoryTracks = await Future.wait(
      otherHistoryRaw.take(20).map((t) => _ensureTrackThumbnails(t, spotify)),
    );

    // 4. Combine endpoint similar tracks + rest of listened tracks, deduplicate, and shuffle
    final seenIds = <String>{safeTrack.id};
    final restList = <GenericSong>[];

    for (final t in [...similarTracks, ...otherHistoryTracks]) {
      if (seenIds.add(t.id)) {
        restList.add(t);
      }
    }

    restList.shuffle();

    // 5. Final queue: Safe track is first, followed by the shuffled rest
    final finalQueue = [safeTrack, ...restList.take(59)];
    return finalQueue;
  }

  Future<void> _handleSubmitted(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isBlocked) return;

    _textSubmissionController.clear();
    setState(() {
      _isBlocked = true;
    });

    // 1. Add user query bubble
    final userMessage = DJChatMessage(text: query, isUser: true);
    _messages.add(userMessage);
    _chatMessagesNotifier.value = List.from(_messages);
    _scrollToBottom();

    // Detect intent (artist and/or tag) and start queue building in background immediately
    final intent = _detectIntent(query);
    final detectedTag = intent.tag;
    final detectedArtist = intent.artist;
    final spotify = context.read<SpotifyInternalProvider>();
    ListeningHabitsService.instance.bindSpotifyProvider(spotify);
    Future<List<GenericSong>?>? queueFuture;
    if (detectedTag != null || detectedArtist != null) {
      queueFuture = _buildQueue(
        detectedTag: detectedTag,
        detectedArtist: detectedArtist,
        spotify: spotify,
      );
    }

    // 2. Artificial thinking period
    await Future.delayed(
      Duration(seconds: 1 + 2 * (DateTime.now().millisecondsSinceEpoch % 3)),
    );
    if (!mounted) return;

    // 3. Response builds word by word
    final responseText = _generateDJResponse(
      detectedArtist: detectedArtist,
      detectedTag: detectedTag,
    );
    final words = responseText.split(' ');

    final djMessage = DJChatMessage(
      text: words.isNotEmpty ? words.first : '',
      isUser: false,
    );
    _messages.add(djMessage);
    _chatMessagesNotifier.value = List.from(_messages);
    _scrollToBottom();

    for (int i = 1; i < words.length; i++) {
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;

      djMessage.text = words.sublist(0, i + 1).join(' ');
      _chatMessagesNotifier.value = List.from(_messages);
      _scrollToBottom();
    }

    // 4. Re-enable input
    if (mounted) {
      setState(() {
        _isBlocked = false;
      });
    }

    // 5. Set queue once built (fire-and-forget with status feedback)
    if (queueFuture != null && mounted) {
      final audioHandler = context.read<WispAudioHandler>();

      // Show "building queue" status
      final queueMsg = DJChatMessage(
        text: 'Finding tracks for you...',
        isUser: false,
      );
      _messages.add(queueMsg);
      _chatMessagesNotifier.value = List.from(_messages);
      _scrollToBottom();

      final tracks = await queueFuture;
      if (!mounted) return;

      if (tracks != null && tracks.isNotEmpty) {
        queueMsg.text = 'Loaded ${tracks.length} tracks — enjoy the session!';
        _chatMessagesNotifier.value = List.from(_messages);
        _scrollToBottom();

        final contextId = detectedArtist != null
            ? 'dj_artist_${detectedArtist.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}'
            : 'dj_${detectedTag ?? 'session'}';

        await audioHandler.setQueue(
          tracks,
          startIndex: 0,
          play: true,
          playbackContext: PlaybackContext(
            type: PlaybackContextType.dj,
            id: contextId,
            name: 'DJ',
            source: SongSource.spotify,
          ),
        );
      } else {
        queueMsg.text =
            "Couldn't find enough tracks for that one. Try listening to more music first!";
        _chatMessagesNotifier.value = List.from(_messages);
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (isAvailable, finishedCount) = context
        .select<ListeningHabitsService, (bool, int)>(
          (h) => (h.hasEnoughData, h.hasEnoughData ? 15 : h.history.length),
        );

    if (!isAvailable) {
      const targetCount = ListeningHabitsService.minRequiredTracksForDJ;
      final theme = Theme.of(context);

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.graphic_eq,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'DJ needs more vibes',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Finish a few more tracks so the DJ can learn your taste and curate sets for you.\n($finishedCount / $targetCount tracks finished)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(
                  value: (finishedCount / targetCount).clamp(0.0, 1.0),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    ListeningHabitsService.instance.bindSpotifyProvider(
      context.read<SpotifyInternalProvider>(),
    );

    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    final viewInsetsBottom =
        isDesktop ? 0.0 : MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = isDesktop
        ? 16.0
        : (viewInsetsBottom > 0 ? viewInsetsBottom + 12.0 : 16.0);

    if (!isDesktop && viewInsetsBottom > _lastViewInsetsBottom) {
      _scrollToBottom();
    }
    _lastViewInsetsBottom = viewInsetsBottom;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Upper "Now Playing" banner ───────────────────────────────
            Selector<WispAudioHandler, (GenericSong?, bool)>(
              selector: (context, h) => (h.currentTrack, h.isPlaying),
              builder: (context, state, _) {
                final (currentTrack, isPlaying) = state;
                return DJNowPlayingBanner(
                  track: currentTrack,
                  isPlaying: isPlaying,
                );
              },
            ),
            const SizedBox(height: 12.0),
            Expanded(
              child: ValueListenableBuilder<List<DJChatMessage>>(
                valueListenable: _chatMessagesNotifier,
                builder: (context, messages, child) {
                  if (messages.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final item = messages[index];
                      return DJChatBubble(
                        message: item.text,
                        isUserMessage: item.isUser,
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _randomTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8.0),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const buttonHeight = 40.0;

                    if (!isDesktop) {
                      return SizedBox(
                        height: buttonHeight,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _randomSuggestions.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8.0),
                          itemBuilder: (context, index) {
                            final entry =
                                _randomSuggestions.entries.elementAt(index);
                            return ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * 0.8,
                              ),
                              child: ElevatedButton(
                                onPressed: _isBlocked
                                    ? null
                                    : () => _handleSubmitted(entry.value),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14.0,
                                  ),
                                ),
                                child: Text(
                                  entry.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }

                    final buttonWidth = (constraints.maxWidth - 24) / 5;

                    final items = _randomSuggestions.entries.map((entry) {
                      return SizedBox(
                        width: buttonWidth,
                        height: buttonHeight,
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: entry.key != _randomSuggestions.keys.last
                                ? 8.0
                                : 0.0,
                          ),
                          child: ElevatedButton(
                            onPressed: _isBlocked
                                ? null
                                : () => _handleSubmitted(entry.value),
                            child: Text(
                              entry.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      );
                    }).toList();

                    return CardRail(
                      title: 'Suggestions',
                      showTitle: false,
                      items: items,
                      itemWidth: buttonWidth,
                      itemHeight: buttonHeight,
                      itemBuilder: (context, item) => item,
                    );
                  },
                ),
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    isDesktop
                        ? SizedBox(
                            height: 48.0,
                            child: FilledButton.icon(
                              label: const Text('Pick something for me'),
                              icon: const Icon(Symbols.shuffle),
                              onPressed: () {
                                final randomKey =
                                    (_randomSuggestions.keys.toList()
                                          ..shuffle())
                                        .first;
                                final randomValue =
                                    _randomSuggestions[randomKey]!;
                                _handleSubmitted(randomValue);
                              },
                            ),
                          )
                        : SizedBox(
                            width: 48.0,
                            height: 48.0,
                            child: IconButton.filled(
                              icon: const Icon(Symbols.shuffle),
                              tooltip: 'Pick something for me',
                              onPressed: () {
                                final randomKey =
                                    (_randomSuggestions.keys.toList()
                                          ..shuffle())
                                        .first;
                                final randomValue =
                                    _randomSuggestions[randomKey]!;
                                _handleSubmitted(randomValue);
                              },
                            ),
                          ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: TextField(
                        controller: _textSubmissionController,
                        enabled: !_isBlocked,
                        decoration: InputDecoration(
                          hintText: _isBlocked
                              ? 'DJ is thinking...'
                              : _randomHint,
                          border: const OutlineInputBorder(),
                          suffixIcon: _isBlocked
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Symbols.send),
                                  onPressed: () {
                                    _handleSubmitted(
                                      _textSubmissionController.text,
                                    );
                                  },
                                ),
                        ),
                        onSubmitted: (query) {
                          _handleSubmitted(query);
                        },
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    IconButton.filled(
                      icon: const Icon(Symbols.info),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text('DJ Feature Info'),
                              content: const Text(
                                'The DJ feature generates music suggestions based on your listening habits and preferences.\n'
                                'You can select from the suggested buttons or enter your own query to discover new music.\n'
                                'Keep in mind: this feature does not use any type of AI or ML. It\'s based on your listened songs and their tags.\n'
                                'It also tries to find similar songs from known platforms, so it may take some time to learn your taste.\n'
                                'So, the more you listen, the better the suggestions will be!',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
