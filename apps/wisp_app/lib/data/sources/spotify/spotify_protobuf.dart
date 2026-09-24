// Copyright © 2026 wizeshi

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Minimal protobuf wire-format writer for Spotify spclient binary requests.
class ProtoWriter {
  final BytesBuilder _builder = BytesBuilder();

  void writeVarint(int value) {
    var v = value;
    while (v >= 0x80) {
      _builder.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    _builder.addByte(v & 0x7F);
  }

  void writeTag(int fieldNumber, int wireType) {
    writeVarint((fieldNumber << 3) | wireType);
  }

  void writeString(int fieldNumber, String value) {
    final bytes = utf8.encode(value);
    writeBytes(fieldNumber, bytes);
  }

  void writeBytes(int fieldNumber, List<int> bytes) {
    writeTag(fieldNumber, 2);
    writeVarint(bytes.length);
    _builder.add(bytes);
  }

  void writeInt32(int fieldNumber, int value) {
    writeTag(fieldNumber, 0);
    writeVarint(value);
  }

  void writeMessage(int fieldNumber, Uint8List messageBytes) {
    writeBytes(fieldNumber, messageBytes);
  }

  Uint8List toBytes() => _builder.toBytes();
}

/// Builds the binary protobuf payload for Spotify's extended-metadata endpoint
/// requesting the TRACK_DESCRIPTOR (6) extension for a track.
Uint8List buildTrackDescriptorsRequest({
  required String trackId,
  String country = 'PT',
  String catalogue = 'premium',
  String? etag,
  List<int>? taskId,
}) {
  final trackUri = trackId.startsWith('spotify:track:')
      ? trackId
      : 'spotify:track:$trackId';

  // Submessage: ExtensionQuery
  final queryWriter = ProtoWriter();
  queryWriter.writeInt32(1, 6); // ExtensionKind.TRACK_DESCRIPTOR = 6
  if (etag != null && etag.isNotEmpty) {
    queryWriter.writeString(2, etag);
  }

  // Submessage: EntityRequest
  final entityWriter = ProtoWriter();
  entityWriter.writeString(1, trackUri);
  entityWriter.writeMessage(2, queryWriter.toBytes());

  // Root request
  final rootWriter = ProtoWriter();
  rootWriter.writeString(1, country);
  rootWriter.writeString(2, catalogue);

  final rand = Random.secure();
  final traceId = taskId ?? List<int>.generate(16, (_) => rand.nextInt(256));
  rootWriter.writeBytes(3, traceId);

  rootWriter.writeMessage(2, entityWriter.toBytes());

  return rootWriter.toBytes();
}

// ---------------------------------------------------------------------------
// Protobuf reader
// ---------------------------------------------------------------------------

/// Minimal streaming protobuf wire-format reader.
class _ProtoReader {
  final Uint8List _bytes;
  int _offset;

  _ProtoReader(this._bytes) : _offset = 0;

  bool get hasMore => _offset < _bytes.length;

  int readVarint() {
    int result = 0;
    int shift = 0;
    while (_offset < _bytes.length) {
      final b = _bytes[_offset++];
      result |= (b & 0x7F) << shift;
      shift += 7;
      if ((b & 0x80) == 0) break;
    }
    return result;
  }

  (int field, int wire)? readTag() {
    if (!hasMore) return null;
    final tag = readVarint();
    return (tag >> 3, tag & 0x07);
  }

  Uint8List readLengthDelimited() {
    final len = readVarint();
    final slice = _bytes.sublist(_offset, _offset + len);
    _offset += len;
    return slice;
  }

  String readString() => utf8.decode(readLengthDelimited(), allowMalformed: true);

  double readFloat32() {
    final bd = ByteData(4)
      ..setUint8(0, _bytes[_offset++])
      ..setUint8(1, _bytes[_offset++])
      ..setUint8(2, _bytes[_offset++])
      ..setUint8(3, _bytes[_offset++]);
    return bd.getFloat32(0, Endian.little);
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
      case 1:
        _offset += 8;
      case 2:
        final len = readVarint();
        _offset += len;
      case 5:
        _offset += 4;
    }
  }
}

/// Parses genre/concept names from Spotify's [BatchedExtensionResponse] binary payload.
///
/// The response nests as:
///   BatchedExtensionResponse
///     → extended_metadata (field 2, repeated EntityExtensionDataArray)
///       → extension_kind (field 2, varint — 6 = TRACK_DESCRIPTOR)
///       → extension_data (field 3, repeated EntityExtensionData)
///         → extension_data (field 3, google.protobuf.Any)
///           → value (field 2, ExtensionDescriptorData bytes)
///             → descriptor items (field 1, repeated)
///               → tag   (field 1, string — e.g. "indie rock")
///               → score (field 2, float32)
///               → name  (field 5, string — e.g. "Indie Rock")
List<String> parseTrackDescriptorsResponse(Uint8List responseBytes) {
  final genres = <String>[];

  try {
    final root = _ProtoReader(responseBytes);
    while (root.hasMore) {
      final tag = root.readTag();
      if (tag == null) break;
      final (field, wire) = tag;

      if (field == 2 && wire == 2) {
        // EntityExtensionDataArray
        final arr = _ProtoReader(root.readLengthDelimited());
        int kind = 0;
        final extDataSlices = <Uint8List>[];

        while (arr.hasMore) {
          final aTag = arr.readTag();
          if (aTag == null) break;
          final (af, aw) = aTag;
          if (af == 2 && aw == 0) {
            kind = arr.readVarint(); // ExtensionKind
          } else if (af == 3 && aw == 2) {
            extDataSlices.add(arr.readLengthDelimited()); // EntityExtensionData
          } else {
            arr.skipField(aw);
          }
        }

        if (kind == 6) {
          // TRACK_DESCRIPTOR — dig into each EntityExtensionData
          for (final extBytes in extDataSlices) {
            Uint8List? anyValue;
            final ext = _ProtoReader(extBytes);
            while (ext.hasMore) {
              final eTag = ext.readTag();
              if (eTag == null) break;
              final (ef, ew) = eTag;
              if (ef == 3 && ew == 2) {
                // google.protobuf.Any
                final any = _ProtoReader(ext.readLengthDelimited());
                while (any.hasMore) {
                  final anyTag = any.readTag();
                  if (anyTag == null) break;
                  final (af2, aw2) = anyTag;
                  if (af2 == 2 && aw2 == 2) {
                    anyValue = any.readLengthDelimited(); // ExtensionDescriptorData value
                  } else {
                    any.skipField(aw2);
                  }
                }
              } else {
                ext.skipField(ew);
              }
            }

            if (anyValue != null) {
              // ExtensionDescriptorData — repeated descriptor items at field 1
              final desc = _ProtoReader(anyValue);
              while (desc.hasMore) {
                final dTag = desc.readTag();
                if (dTag == null) break;
                final (df, dw) = dTag;
                if (df == 1 && dw == 2) {
                  // One descriptor/concept item
                  final item = _ProtoReader(desc.readLengthDelimited());
                  String? rawTag;
                  String? displayName;
                  while (item.hasMore) {
                    final iTag = item.readTag();
                    if (iTag == null) break;
                    final (iField, iWire) = iTag;
                    if (iField == 1 && iWire == 2) {
                      rawTag = item.readString(); // e.g. "indie rock"
                    } else if (iField == 5 && iWire == 2) {
                      displayName = item.readString(); // e.g. "Indie Rock"
                    } else {
                      item.skipField(iWire);
                    }
                  }
                  final resolved = displayName ?? rawTag;
                  if (resolved != null && resolved.isNotEmpty) {
                    genres.add(resolved);
                  }
                } else {
                  desc.skipField(dw);
                }
              }
            }
          }
        }
      } else {
        root.skipField(wire);
      }
    }
  } catch (_) {}

  // De-duplicate while preserving score-based order.
  final seen = <String>{};
  return genres.where(seen.add).toList();
}

// ---------------------------------------------------------------------------
// Spotify Base62 <-> Hex GID conversion
// ---------------------------------------------------------------------------

const _spotifyBase62Alphabet =
    '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// Converts a 22-character Spotify Base62 ID (or URI) to a 32-character hex GID.
///
/// If [id] is already a 32-character hex string or does not match 22 chars,
/// it is returned stripped of any URI prefix.
String spotifyIdToHexGid(String id) {
  final clean = id.startsWith('spotify:track:')
      ? id.split(':').last
      : id.startsWith('spotify:')
          ? id.split(':').last
          : id;

  if (clean.length != 22) return clean;

  BigInt n = BigInt.zero;
  final base = BigInt.from(62);
  for (int i = 0; i < clean.length; i++) {
    final idx = _spotifyBase62Alphabet.indexOf(clean[i]);
    if (idx == -1) return clean;
    n = n * base + BigInt.from(idx);
  }
  return n.toRadixString(16).padLeft(32, '0');
}

/// Converts a 32-character Spotify hex GID back to a 22-character Base62 ID.
String hexGidToSpotifyId(String hex) {
  if (hex.length != 32) return hex;
  final n = BigInt.tryParse(hex, radix: 16);
  if (n == null) return hex;

  var current = n;
  final base = BigInt.from(62);
  final chars = <String>[];
  while (current > BigInt.zero) {
    final rem = (current % base).toInt();
    chars.add(_spotifyBase62Alphabet[rem]);
    current = current ~/ base;
  }
  final res = chars.reversed.join();
  return res.padLeft(22, '0');
}
