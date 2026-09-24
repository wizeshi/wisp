import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/services/system/listening_habits_service.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/rails/card_rail.dart';

const djTextInputTitles = [
  'Hi! What would you like to listen to today?',
  'What\'s your vibe right now?',
  'What kind of music are you in the mood for?',
];

const djTextInputHints = [
  'I\'m thinking about...',
  'I\'m in the mood for...',
  'I want to listen to...',
  'Play some music that makes me feel...',
  'I want to hear songs that remind me of...',
];

const Map<String, List<String>> djTagKeywords = {
  '60s': [
    '60s',
    '60\'s',
    '1960',
    'sixties',
    'sixty',
    'woodstock',
    'beatles era',
  ],
  '70s': [
    '70s',
    '70\'s',
    '1970',
    'seventies',
    'seventy',
    'disco',
    'groove',
    'funk',
  ],
  '80s': [
    '80s',
    '80\'s',
    '1980',
    'eighties',
    'eighty',
    'synth',
    'synthwave',
    'retro',
    'new wave',
  ],
  '90s': [
    '90s',
    '90\'s',
    '1990',
    'nineties',
    'ninety',
    'grunge',
    'boom bap',
    'eurodance',
  ],
  '2000s': [
    '2000s',
    '2000\'s',
    '2000',
    'y2k',
    'noughties',
    'millennium',
    'early 2000s',
  ],
  'chill': [
    'chill',
    'relax',
    'calm',
    'lo-fi',
    'lofi',
    'mellow',
    'ambient',
    'peaceful',
    'study',
    'unwind',
    'sleep',
    'cozy',
  ],
  'hood': [
    'hood',
    'trap',
    'drill',
    'gangsta',
    'gangster',
    'street',
    'block',
    '808',
  ],
  'party': [
    'party',
    'dance',
    'club',
    'upbeat',
    'hype',
    'rave',
    'celebrate',
    'energy',
    'banger',
    'turn up',
  ],
  'r&b': [
    'r&b',
    'r & b',
    'rnb',
    'soul',
    'rhythm and blues',
    'motown',
    'neo soul',
  ],
  'rap': [
    'rap',
    'hip hop',
    'hip-hop',
    'hiphop',
    'bars',
    'freestyle',
    'rapper',
    'mc',
    'rhymes',
  ],
  'rock': [
    'rock',
    'metal',
    'punk',
    'hard rock',
    'classic rock',
    'guitar',
    'headbang',
    'grunge',
  ],
  'en_underground': [
    'underground',
    'indie',
    'alternative',
    'alt rock',
    'alt pop',
    'garage rock',
    'underground english',
  ],
  'en_pop': [
    'pop',
    'chart',
    'charts',
    'top 40',
    'billboard',
    'mainstream',
    'radio hits',
    'pop music',
  ],
  'pt_pt_fado': [
    'fado',
    'fadista',
    'fados',
    'guitarra portuguesa',
    'coimbra',
    'alfama',
  ],
  'pt_pt_pop': [
    'pop portugues',
    'pop português',
    'portuguese pop',
    'musica portuguesa',
    'música portuguesa',
  ],
  'pt_pt_rap': [
    'rap tuga',
    'hip hop tuga',
    'hip-hop tuga',
    'rap portugues',
    'rap português',
    'portuguese rap',
    'rap de portugal',
    'rap portugal',
    'hip hop portugal',
    'tuga rap',
    'tuga',
  ],
  'pt_br_mpb': [
    'mpb',
    'musica popular brasileira',
    'música popular brasileira',
    'bossa nova',
    'bossa',
    'tropicalia',
    'tropicália',
    'caetano',
    'gilberto gil',
  ],
  'pt_br_samba': [
    'samba',
    'pagode',
    'sambas',
    'roda de samba',
    'carnaval',
    'pandeiro',
    'cavaco',
  ],
};

const Map<String, List<String>> djTagResponses = {
  '60s': [
    'Spinning the clock back to the 1960s! Let\'s dial into the golden era of rock, soul, and revolution.',
    '60s vibes incoming! Cueing up the classic warmth of vinyl and iconic vintage harmonies.',
    'Taking you straight to the swinging sixties. Get ready for legendary melodies from an unforgettable decade.',
  ],
  '70s': [
    'Dropping the needle on the 1970s! Get ready to groove to funk, disco, and pure classic rock energy.',
    '70s mood unlocked. Turning up the basslines, vintage guitars, and timeless grooves.',
    'Taking a trip back to the seventies! Slip on your dancing shoes and enjoy these timeless rhythms.',
  ],
  '80s': [
    'Powering up the neon synthesizers! Welcome to the electrifying, reverberating sound of the 1980s.',
    '80s retro wave activated! Cueing up gated snares, bold hooks, and unforgettable synth-pop anthems.',
    'Taking you back to the vibrant eighties. Turn the volume up and relive the glory days of pop and rock!',
  ],
  '90s': [
    'Cueing up the 1990s! From grunge to golden-age hip-hop and Eurodance, we have you covered.',
    '90s nostalgia hitting the deck! Get ready for raw guitar riffs and classic boom-bap beats.',
    'Dialing into the nineties soundscape. Unfiltered attitude and unforgettable melodies coming right up!',
  ],
  '2000s': [
    'Jumping into the 2000s! Cueing up the millennium anthems, iconic pop hits, and classic club tracks.',
    'Y2K energy activated! Dusting off the greatest hits that ruled the charts and iPods back in the 2000s.',
    'Throwing it back to the early 2000s. Get ready for infectious hooks and unforgettable bangers!',
  ],
  'chill': [
    'Lowering the tempo and setting the atmosphere. Here are some smooth, mellow tunes to help you unwind.',
    'Chill vibes locked in. Sit back, take a deep breath, and let these calm soundscapes wash over you.',
    'Slowing down the frequency. Queueing up some relaxed, cozy melodies perfect for clearing your mind.',
  ],
  'hood': [
    'Street frequency engaged. Cranking up heavy 808s, raw verses, and hard-hitting trap anthems.',
    'Locking in that hood vibe. Turn up the bass and get ready for pure gritty beats and relentless flow.',
    'Bass heavy and unfiltered! Dropping into some heavy street certified heat right now.',
  ],
  'party': [
    'Party mode activated! Turning up the energy with high-octane bangers to keep the dance floor packed.',
    'Dropping the beat right into the mix! Time to turn up the speakers and get the celebration started.',
    'Hands in the air! Spinning an electric selection guaranteed to get everybody moving.',
  ],
  'r&b': [
    'Setting the mood with silky smooth R&B. Expect lush harmonies, velvet vocals, and heartfelt rhythm.',
    'Pure soul and groove incoming. Dimming the lights and spinning the finest contemporary and classic R&B.',
    'Vibing out to some soulful R&B. Smooth basslines and captivating melodies cueing up for you now.',
  ],
  'rap': [
    'Mic check, one two! Dropping straight into punchy flows, clever rhymes, and razor-sharp lyricism.',
    'Spitting pure heat! Cueing up heavy-hitting hip-hop beats and top-tier bar work for your session.',
    'Rap session locked in. Spinning classic boom-bap, modern trap, and elite verses from the best MCs.',
  ],
  'rock': [
    'Plugging in the Marshall stacks! Prepare for crunching distortion, roaring riffs, and pounding drums.',
    'Rock and roll time! Turning up the amps to eleven with some electrifying rock power.',
    'Throwing up the horns! Cueing up high-energy riffs and anthemic rock classics to shake the room.',
  ],
  'en_underground': [
    'Digging deep beneath the mainstream. Here are some hidden gems and raw underground cuts.',
    'Off the beaten path! Cueing up atmospheric indie sounds and creative underground English artistry.',
    'Exploring the indie underground circuit. Fresh, authentic tracks that fly just below the radar.',
  ],
  'en_pop': [
    'Serving up pure ear candy! Here are irresistible hooks, polished production, and vibrant pop energy.',
    'Pop sensations cueing up! Bringing you catchy choruses and infectious rhythm that you cannot help but sing along to.',
    'Chart-topping pop flavour locked in. Turn up the shine and enjoy these sparkling anthems!',
  ],
  'pt_pt_fado': [
    'Afinação da guitarra portuguesa pronta. Vamos viajar pelo sentimento e a saudade do fado tradicional.',
    'Tradição e alma lusitana. Trazendo as vozes mais profundas e as cordas emotivas do fado para si.',
    'Entrando no coração de Lisboa e Coimbra. Deixe-se levar pela magia poética e melancólica do fado.',
  ],
  'pt_pt_pop': [
    'Sintonizando o melhor do pop português contemporâneo. Melodias frescas e canções que marcam o compasso.',
    'Pop nacional na mesa de mistura! Trazendo os refrões mais cativantes da música portuguesa atual.',
    'A vibrar com sonoridades lusófonas! Aqui estão temas pop cheios de energia e identidade portuguesa.',
  ],
  'pt_pt_rap': [
    'Hip-hop tuga na casa! Rimas afiadas da linha e batidas pesadas com sotaque de Portugal a caminho.',
    'Batidas de rua e mensagem crua. A carregar o melhor do rap e hip-hop português para a sua sessão.',
    'Flow nacional ao rubro! Preparando os sons mais emblemáticos e autênticos do rap lusófono.',
  ],
  'pt_br_mpb': [
    'Conectando com a sofisticação da MPB. Poesia brasileira, violão e melodias que encantam gerações.',
    'Aqueça o coração com Música Popular Brasileira. Ritmos refinados, poesia lírica e calor tropical.',
    'Da Bossa Nova ao Tropicalismo, viajando pela riqueza sem igual dos mestres da MPB.',
  ],
  'pt_br_samba': [
    'Puxa o cavaco e esquenta o pandeiro! A roda de samba e pagode está armada para levantar o seu astral.',
    'Ritmo, malemolência e alegria brasileira. Preparando uma seleção de samba de primeira linha para você.',
    'O samba não pode parar! Batucada contagiante e letras inesquecíveis para alegrar o seu dia.',
  ],
};

const List<String> djUntaggedResponses = [
  'Hmm, I couldn\'t quite pinpoint that specific vibe. Spinning a diverse mix from across the library to see what catches your ear!',
  'That\'s an eclectic vibe! I\'m shuffling a curated blend of tracks to see what matches your mood.',
  'Not sure which genre fits that best, but good music knows no bounds. Dropping into a fresh surprise selection!',
  'Couldn\'t match that to a specific crate, so I\'m freestyling this set. Let\'s see where this groove takes us!',
  'My musical radar didn\'t catch a clear tag for that one, but don\'t worry—queueing up some all-around favorites for you now!',
];

// Map from our tags to Spotify's genre tags.
const List<String> djSuggestionTemplates = [
  'I want to listen to some {genre}',
  'Play some {genre}',
  'Get me some {genre}',
  'Put on some {genre}',
  'I\'m in the mood for {genre}',
  'Vibe to some {genre}',
  'Give me some {genre}',
];

const List<String> detectedSpotifyGenres = [
  'Alternative Pop',
  'Pop Rap',
  'Alternative Hip Hop',
  'Chill',
  'Indie Pop',
  'Hip Hop',
  'Indie',
  'Chill Beats',
  'Trap',
  'Upbeat',
  'Happy',
  'Pop',
  'Gaming',
  'Energetic',
  'Dance Pop',
  'Nostalgia',
  'Bubblegum Pop',
  'Pump Up',
  'Fast',
  'Club',
  'Crunk',
  'Calm',
  'Slow',
  'R&B',
  'Relaxing',
  'Tranquil',
  'Soft',
  'Love',
  'Mellow',
  'Smooth',
  'Quiet',
  'Soothing',
  'Peaceful',
  'Cozy',
  'Romantic',
  'Gentle',
  'Electropop',
  'Pop Rock',
  'Electronica',
  'Britpop',
  'EDM',
  'Children\'s Music',
  'Electronic',
  'Electro',
  'Rap',
  'New Age',
  'Beats',
  'Sensual',
  'Dark',
  'Dance',
  'Soft Rock',
  'Alternative Rock',
  'Motivation',
  'Bossa Nova',
  'Samba',
  'Psychedelic Rock',
  'Indie Rock',
  'Chillwave',
  'Dream Pop',
  'Gangster Rap',
  'Spooky',
  'Disco',
  'Soul',
  'Americana',
  'Reggaeton',
  'Latin',
  'Trap Latino',
  'Ibiza',
  'Synthpop',
  'Melancholy',
  'Rain',
  'Moody',
  'Ethereal',
  'Nature',
  'Emotional',
];

class DJChatMessage {
  String text;
  final bool isUser;

  DJChatMessage({required this.text, required this.isUser});
}

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
                return _DJNowPlayingBanner(
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

/// Compact "Now Playing" banner shown at the top of the DJ view.
///
/// Shows a DJ Mode badge, track artwork, title, and artists. When [isPlaying]
/// is true, the badge has a pulsing live dot.
class _DJNowPlayingBanner extends StatefulWidget {
  final GenericSong? track;
  final bool isPlaying;

  const _DJNowPlayingBanner({required this.track, required this.isPlaying});

  @override
  State<_DJNowPlayingBanner> createState() => _DJNowPlayingBannerState();
}

class _DJNowPlayingBannerState extends State<_DJNowPlayingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = widget.track;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: track != null
                  ? ArtworkThumbnail(
                      source: ArtworkSource.fromUrl(track.thumbnailUrl),
                      size: ArtworkSize.small,
                      sizeOverride: 56,
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Symbols.music_note,
                        size: 28,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            // Text info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge row
                  Row(
                    children: [
                      Builder(
                        builder: (context) {
                          final badgeBg = theme.colorScheme.primaryContainer;
                          final badgeFg =
                              ThemeData.estimateBrightnessForColor(badgeBg) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.isPlaying) ...[
                                  AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (_, _) => Opacity(
                                      opacity: _pulseAnimation.value,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: badgeFg,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Text(
                                  'DJ Mode',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: badgeFg,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (track != null) ...[
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      track.artists.map((a) => a.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    Text(
                      'Nothing playing — pick a vibe below!',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DJChatBubble extends StatelessWidget {
  final String message;
  final bool isUserMessage;

  const DJChatBubble({
    super.key,
    required this.message,
    required this.isUserMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUserMessage
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14.0),
            topRight: const Radius.circular(14.0),
            bottomLeft: Radius.circular(isUserMessage ? 14.0 : 2.0),
            bottomRight: Radius.circular(isUserMessage ? 2.0 : 14.0),
          ),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isUserMessage
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
