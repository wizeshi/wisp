import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wisp/utils/logger.dart';

import 'types.dart';

class DiscordRpcApi {
  DiscordRpcApi._();

  static final DiscordRpcApi instance = DiscordRpcApi._();

  static const int _opHandshake = 0;
  static const int _opFrame = 1;
  static const int _opClose = 2;
  static const int _opPing = 3;
  static const int _opPong = 4;

  String? _clientId;
  _IpcTransport? _transport;
  bool _connected = false;
  int _nonce = 0;

  bool get isConnected => _connected;

  Future<void> initialize(String clientId) async {
    logger.d('[Services/DiscordRPC-API] Initializing Discord RPC with client ID: $clientId');
    _clientId = clientId;
  }

  Future<void> connect() async {
    logger.d('[Services/DiscordRPC-API] Initializing connection to Discord RPC...');
    final clientId = _clientId;
    if (clientId == null || clientId.isEmpty) {
      logger.e('[Services/DiscordRPC-API] Discord RPC client ID is not set.');
      throw StateError('Discord RPC client has not been initialized.');
    }

    logger.d('[Services/DiscordRPC-API] Disconnecting existing connection (if any)...');
    await disconnect();
    _transport = await _connectTransport();

    logger.d('[Services/DiscordRPC-API] Sending handshake to Discord RPC...');
    await _send(_opHandshake, {'v': 1, 'client_id': clientId});

    final ready = await _readFrame();
    if (ready['cmd'] != 'DISPATCH' || ready['evt'] != 'READY') {
      logger.e('[Services/DiscordRPC-API] Discord RPC handshake failed: $ready');
      await disconnect();
      throw StateError('Discord RPC handshake failed: $ready');
    }

    logger.d('[Services/DiscordRPC-API] Discord RPC connected successfully.');
    _connected = true;
  }

  Future<void> reconnect() async {
    logger.d('[Services/DiscordRPC-API] Reconnecting to Discord RPC...');
    if (_clientId == null) return;
    await connect();
  }

  Future<void> setActivity({required RPCActivity activity}) async {
    await _sendCommand('SET_ACTIVITY', {
      'pid': pid,
      'activity': _activityToJson(activity),
    });
  }

  Future<void> clearActivity() async {
    logger.d('[Services/DiscordRPC-API] Clearing activity...');
    await _sendCommand('SET_ACTIVITY', {'pid': pid, 'activity': null});
  }

  Future<void> disconnect() async {
    logger.d('[Services/DiscordRPC-API] Disconnecting from Discord RPC...');
    final transport = _transport;
    if (transport == null) return;

    try {
      await _send(_opClose, {});
    } catch (_) {
      // Discord may already have closed the pipe.
    }

    await transport.close();
    _transport = null;
    _connected = false;
  }

  Future<void> dispose() async {
    await disconnect();
    _clientId = null;
  }

  Future<void> _sendCommand(String command, Map<String, Object?> args) async {
    if (!_connected) {
      await connect();
    }

    await _send(_opFrame, {
      'cmd': command,
      'args': args,
      'nonce': _nextNonce(),
    });

    while (true) {
      final frame = await _readFrame();
      final commandName = frame['cmd'];
      if (commandName == null || commandName == command) {
        return;
      }
    }
  }

  Future<void> _send(int opCode, Map<String, Object?> payload) async {
    final transport = _transport;
    if (transport == null) {
      throw StateError('Discord RPC is not connected.');
    }

    final jsonBytes = utf8.encode(jsonEncode(payload));
    final frame = Uint8List(8 + jsonBytes.length);
    final header = ByteData.sublistView(frame);
    header.setUint32(0, opCode, Endian.little);
    header.setUint32(4, jsonBytes.length, Endian.little);
    frame.setRange(8, frame.length, jsonBytes);

    await transport.write(frame);
  }

  Future<Map<String, dynamic>> _readFrame() async {
    final transport = _transport;
    if (transport == null) {
      throw StateError('Discord RPC is not connected.');
    }

    while (true) {
      final headerBytes = await transport.read(8);
      final header = ByteData.sublistView(headerBytes);
      final opCode = header.getUint32(0, Endian.little);
      final length = header.getUint32(4, Endian.little);
      final payloadBytes = length == 0
          ? Uint8List(0)
          : await transport.read(length);

      if (opCode == _opPing) {
        await _send(_opPong, _decodePayload(payloadBytes));
        continue;
      }

      if (opCode == _opClose) {
        _connected = false;
        throw StateError('Discord RPC closed the connection.');
      }

      return _decodePayload(payloadBytes);
    }
  }

  Map<String, dynamic> _decodePayload(Uint8List bytes) {
    if (bytes.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  String _nextNonce() {
    _nonce = (_nonce + 1) % 0x7fffffff;
    return 'wisp-$_nonce-${DateTime.now().microsecondsSinceEpoch}';
  }

  Map<String, Object?> _activityToJson(RPCActivity activity) {
    return _withoutNulls({
      'name': activity.name,
      'type': activity.type.index,
      'url': activity.url,
      'created_at': activity.createdAt,
      'timestamps': _timestampsToJson(activity.timestamps),
      'application_id': activity.applicationId,
      'status_display_type': activity.statusDisplayType?.index,
      'details': activity.details,
      'details_url': activity.detailsUrl,
      'state': activity.state,
      'state_url': activity.stateUrl,
      'emoji': _emojiToJson(activity.emoji),
      'party': _partyToJson(activity.party),
      'assets': _assetsToJson(activity.assets),
      'secrets': _secretsToJson(activity.secrets),
      'instance': activity.instance,
      'flags': activity.flags,
      'buttons': activity.buttons?.map(_buttonToJson).toList(),
    });
  }

  Map<String, Object?>? _timestampsToJson(RPCTimestamps? timestamps) {
    if (timestamps == null) return null;
    return _withoutNulls({
      'start': _normalizeTimestamp(timestamps.start),
      'end': _normalizeTimestamp(timestamps.end),
    });
  }

  int? _normalizeTimestamp(int? value) {
    if (value == null) return null;

    // Discord IPC expects Unix seconds. The old service builds millisecond
    // values, so accept both formats and normalize only obvious millisecond
    // timestamps.
    if (value > 100000000000) {
      return value ~/ 1000;
    }
    return value;
  }

  Map<String, Object?>? _assetsToJson(RPCAssets? assets) {
    if (assets == null) return null;
    return _withoutNulls({
      'large_image': assets.largeImage,
      'large_text': assets.largeText,
      'small_image': assets.smallImage,
      'small_text': assets.smallText,
    });
  }

  Map<String, Object?>? _buttonToJson(RPCButton button) {
    return _withoutNulls({'label': button.label, 'url': button.url});
  }

  Map<String, Object?>? _emojiToJson(RPCEmoji? emoji) {
    if (emoji == null) return null;
    return _withoutNulls({
      'name': emoji.name,
      'id': emoji.id,
      'animated': emoji.animated,
    });
  }

  Map<String, Object?>? _partyToJson(RPCParty? party) {
    if (party == null) return null;
    return _withoutNulls({'id': party.id, 'size': party.size?.toList()});
  }

  Map<String, Object?>? _secretsToJson(RPCSecrets? secrets) {
    if (secrets == null) return null;
    return _withoutNulls({
      'join': secrets.join,
      'spectate': secrets.spectate,
      'match': secrets.matchStr,
    });
  }

  Map<String, Object?> _withoutNulls(Map<String, Object?> value) {
    value.removeWhere((_, entry) => entry == null);
    return value;
  }

  Future<_IpcTransport> _connectTransport() async {
    logger.d('[Services/DiscordRPC-API] Attempting to connect to Discord IPC transport...');
    Object? lastError;

    for (var index = 0; index < 10; index += 1) {
      try {
        if (Platform.isWindows) {
          return await _FileIpcTransport.connect(
            '\\\\?\\pipe\\discord-ipc-$index',
          );
        }

        return await _SocketIpcTransport.connect(_unixSocketPath(index));
      } catch (error) {
        lastError = error;
      }
    }

    logger.e('[Services/DiscordRPC-API] Discord IPC pipe was not found: $lastError');
    throw StateError('Discord IPC pipe was not found: $lastError');
  }

  String _unixSocketPath(int index) {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    final tempDir = Platform.environment['TMPDIR'] ?? '/tmp';
    final userId = Platform.environment['UID'];

    final candidates = <String>[
      if (runtimeDir != null && runtimeDir.isNotEmpty)
        '$runtimeDir/discord-ipc-$index',
      '$tempDir/discord-ipc-$index',
      '/tmp/discord-ipc-$index',
      if (userId != null && userId.isNotEmpty)
        '/run/user/$userId/discord-ipc-$index',
    ];

    return candidates.firstWhere(
      (path) =>
          FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound,
    );
  }
}

abstract class _IpcTransport {
  Future<void> write(Uint8List bytes);

  Future<Uint8List> read(int count);

  Future<void> close();
}

class _FileIpcTransport implements _IpcTransport {
  _FileIpcTransport._(this._file);

  final RandomAccessFile _file;

  static Future<_FileIpcTransport> connect(String path) async {
    final file = await File(path).open(mode: FileMode.write);
    return _FileIpcTransport._(file);
  }

  @override
  Future<void> write(Uint8List bytes) => _file.writeFrom(bytes);

  @override
  Future<Uint8List> read(int count) async {
    final output = BytesBuilder(copy: false);
    while (output.length < count) {
      final chunk = await _file.read(count - output.length);
      if (chunk.isEmpty) {
        throw StateError('Discord IPC pipe closed while reading.');
      }
      output.add(chunk);
    }
    return output.takeBytes();
  }

  @override
  Future<void> close() => _file.close();
}

class _SocketIpcTransport implements _IpcTransport {
  _SocketIpcTransport._(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final Queue<int> _buffer = Queue<int>();
  late final StreamSubscription<Uint8List> _subscription;
  Completer<void>? _readCompleter;
  Object? _error;
  bool _closed = false;

  static Future<_SocketIpcTransport> connect(String path) async {
    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return _SocketIpcTransport._(socket);
  }

  @override
  Future<void> write(Uint8List bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Future<Uint8List> read(int count) async {
    while (_buffer.length < count) {
      if (_error != null) throw StateError('Discord IPC socket error: $_error');
      if (_closed) throw StateError('Discord IPC socket closed while reading.');

      _readCompleter ??= Completer<void>();
      await _readCompleter!.future;
    }

    final bytes = Uint8List(count);
    for (var index = 0; index < count; index += 1) {
      bytes[index] = _buffer.removeFirst();
    }
    return bytes;
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
  }

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    _wakeReader();
  }

  void _onError(Object error) {
    _error = error;
    _wakeReader();
  }

  void _onDone() {
    _closed = true;
    _wakeReader();
  }

  void _wakeReader() {
    final completer = _readCompleter;
    if (completer == null || completer.isCompleted) return;

    _readCompleter = null;
    completer.complete();
  }
}
