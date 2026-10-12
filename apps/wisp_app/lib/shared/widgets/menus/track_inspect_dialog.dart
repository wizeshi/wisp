// Copyright © 2026 wizeshi

import 'package:flutter/widgets.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'inspect_dialog.dart';

export 'inspect_dialog.dart';

/// Legacy wrapper for [InspectDialog].
/// Prefer using [InspectDialog.show(context, data: track.toJson(), title: 'Inspect Track')].
@Deprecated('Use InspectDialog directly instead')
class TrackInspectDialog extends StatelessWidget {
  final GenericSong track;

  const TrackInspectDialog({super.key, required this.track});

  static Future<void> show(BuildContext context, GenericSong track) {
    return InspectDialog.show(
      context,
      data: track.toJson(),
      title: 'Inspect Track',
    );
  }

  @override
  Widget build(BuildContext context) {
    return InspectDialog(
      data: track.toJson(),
      title: 'Inspect Track',
    );
  }
}
