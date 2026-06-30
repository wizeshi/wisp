import 'dart:typed_data';

enum ActivityType { playing, streaming, listening, watching, custom, competing }

enum ActivityStatusDisplayType { name, state, details }

class RPCEmoji {
  final String name;
  final String? id;
  final bool? animated;

  const RPCEmoji({required this.name, this.id, this.animated});
}

class RPCActivity {
  final String? name;
  final ActivityType type;
  final String? url;
  final int? createdAt;
  final RPCTimestamps? timestamps;
  final String? applicationId;
  final ActivityStatusDisplayType? statusDisplayType;
  final String? details;
  final String? detailsUrl;
  final String? state;
  final String? stateUrl;
  final RPCEmoji? emoji;
  final RPCParty? party;
  final RPCAssets? assets;
  final RPCSecrets? secrets;
  final bool? instance;
  final int? flags;
  final List<RPCButton>? buttons;

  const RPCActivity({
    this.name,
    this.type = ActivityType.listening,
    this.url,
    this.createdAt,
    this.timestamps,
    this.applicationId,
    this.statusDisplayType,
    this.details,
    this.detailsUrl,
    this.state,
    this.stateUrl,
    this.emoji,
    this.party,
    this.assets,
    this.secrets,
    this.instance,
    this.flags,
    this.buttons,
  });
}

class RPCAssets {
  final String? largeImage;
  final String? largeText;
  final String? smallImage;
  final String? smallText;

  const RPCAssets({
    this.largeImage,
    this.largeText,
    this.smallImage,
    this.smallText,
  });
}

class RPCButton {
  final String label;
  final String url;

  const RPCButton({required this.label, required this.url});
}

class RPCParty {
  final String? id;
  final Int32List? size;

  const RPCParty({this.id, this.size});
}

class RPCSecrets {
  final String? join;
  final String? spectate;
  final String? matchStr;

  const RPCSecrets({this.join, this.spectate, this.matchStr});
}

class RPCTimestamps {
  final int? start;
  final int? end;

  const RPCTimestamps({this.start, this.end});
}
