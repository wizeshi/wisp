import 'package:flutter/material.dart';
import 'package:wisp/shared/widgets/cards/album_card.dart';

import 'package:wisp/data/models/metadata_models.dart';

class SpecialCard extends StatelessWidget {
  final GenericAlbum album;
  final double width;

  const SpecialCard({super.key, required this.album, this.width = 160});

  // STUB: Special Card just redirects to AlbumCard for now, but it'll be customized in the future.
  @override
  Widget build(BuildContext context) {
    return AlbumCard(album: album, width: width);
  }
}
