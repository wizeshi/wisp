// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:wisp/core/utils/logger.dart';

const kLogPackets = false;

/// Implementation of the Shannon stream cipher used for Spotify AP session framing.
/// Faithfully ported from librespot's shannon-rs crate (shannon-0.2.0).
class ShannonCipher {
  static const int _n = 16;
  static const int _initKonst = 0x6996c53a;
  static const int _keyp = 13;

  final Uint32List _r = Uint32List(_n);
  final Uint32List _crc = Uint32List(_n);
  final Uint32List _initR = Uint32List(_n);
  int _konst = _initKonst;
  int _sbuf = 0;
  int _mbuf = 0;
  int _nbuf = 0;

  ShannonCipher(Uint8List key) {
    _r[0] = 1;
    _r[1] = 1;
    for (var i = 2; i < _n; i++) {
      _r[i] = (_r[i - 1] + _r[i - 2]) & 0xFFFFFFFF;
    }

    _loadKey(key);
    _genKonst();
    _saveState();
  }

  static int _sbox1(int w) {
    w &= 0xFFFFFFFF;
    w ^= (w << 5 | w >>> (32 - 5)) | (w << 7 | w >>> (32 - 7));
    w &= 0xFFFFFFFF;
    w ^= (w << 19 | w >>> (32 - 19)) | (w << 22 | w >>> (32 - 22));
    return w & 0xFFFFFFFF;
  }

  static int _sbox2(int w) {
    w &= 0xFFFFFFFF;
    w ^= (w << 7 | w >>> (32 - 7)) | (w << 22 | w >>> (32 - 22));
    w &= 0xFFFFFFFF;
    w ^= (w << 5 | w >>> (32 - 5)) | (w << 19 | w >>> (32 - 19));
    return w & 0xFFFFFFFF;
  }

  static int _rotl(int w, int x) {
    return ((w << x) | (w >>> (32 - x))) & 0xFFFFFFFF;
  }

  void _saveState() {
    _initR.setAll(0, _r);
  }

  void _reloadState() {
    _r.setAll(0, _initR);
  }

  void _genKonst() {
    _konst = _r[0];
  }

  void _cycle() {
    var t = _r[12] ^ _r[13] ^ _konst;
    t = _sbox1(t) ^ _rotl(_r[0], 1);

    for (var i = 1; i < _n; i++) {
      _r[i - 1] = _r[i];
    }
    _r[_n - 1] = t & 0xFFFFFFFF;
    t = _sbox2((_r[2] ^ _r[15]) & 0xFFFFFFFF);
    _r[0] = (_r[0] ^ t) & 0xFFFFFFFF;
    _sbuf = (t ^ _r[8] ^ _r[12]) & 0xFFFFFFFF;
  }

  void _diffuse() {
    for (var i = 0; i < _n; i++) {
      _cycle();
    }
  }

  void _loadKey(Uint8List key) {
    final byteData = ByteData.sublistView(key);
    var offset = 0;
    while (offset + 4 <= key.length) {
      final word = byteData.getUint32(offset, Endian.little);
      _r[_keyp] = (_r[_keyp] ^ word) & 0xFFFFFFFF;
      _cycle();
      offset += 4;
    }

    if (offset < key.length) {
      var word = 0;
      for (var i = 0; offset + i < key.length; i++) {
        word |= (key[offset + i] << (i * 8));
      }
      _r[_keyp] = (_r[_keyp] ^ word) & 0xFFFFFFFF;
      _cycle();
    }

    _r[_keyp] = (_r[_keyp] ^ key.length) & 0xFFFFFFFF;
    _cycle();

    _crc.setAll(0, _r);
    _diffuse();

    for (var i = 0; i < _n; i++) {
      _r[i] = (_r[i] ^ _crc[i]) & 0xFFFFFFFF;
    }
  }

  void nonce(Uint8List nonce) {
    _reloadState();
    _konst = _initKonst;
    _loadKey(nonce);
    _genKonst();
    _nbuf = 0;
  }

  void nonceU32(int n) {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, n & 0xFFFFFFFF, Endian.big);
    nonce(bytes);
  }

  void _crcFunc(int i) {
    final t = (_crc[0] ^ _crc[2] ^ _crc[15] ^ i) & 0xFFFFFFFF;
    for (var j = 1; j < _n; j++) {
      _crc[j - 1] = _crc[j];
    }
    _crc[_n - 1] = t;
  }

  void _macFunc(int i) {
    _crcFunc(i);
    _r[_keyp] = (_r[_keyp] ^ i) & 0xFFFFFFFF;
  }

  void _process(
    Uint8List buf,
    void Function(int offset) fullWord,
    void Function(int offset) partial,
  ) {
    var offset = 0;
    if (_nbuf != 0) {
      while (_nbuf > 0) {
        if (offset < buf.length) {
          partial(offset);
          offset++;
          _nbuf -= 8;
        } else {
          return;
        }
        final m = _mbuf;
        _macFunc(m);
      }
    }

    final remaining = buf.length - offset;
    final len = remaining & ~0x3;
    final endWords = offset + len;

    while (offset < endWords) {
      _cycle();
      fullWord(offset);
      offset += 4;
    }

    if (offset < buf.length) {
      _cycle();
      _mbuf = 0;
      _nbuf = 32;
      while (offset < buf.length) {
        partial(offset);
        offset++;
        _nbuf -= 8;
      }
    }
  }

  void encrypt(Uint8List buf) {
    final bd = ByteData.sublistView(buf);
    _process(
      buf,
      (offset) {
        var word = bd.getUint32(offset, Endian.little);
        _macFunc(word);
        word ^= _sbuf;
        bd.setUint32(offset, word & 0xFFFFFFFF, Endian.little);
      },
      (offset) {
        final b = buf[offset];
        _mbuf = (_mbuf ^ (b << (32 - _nbuf))) & 0xFFFFFFFF;
        buf[offset] = (b ^ ((_sbuf >>> (32 - _nbuf)) & 0xFF)) & 0xFF;
      },
    );
  }

  void decrypt(Uint8List buf) {
    final bd = ByteData.sublistView(buf);
    _process(
      buf,
      (offset) {
        var word = bd.getUint32(offset, Endian.little);
        word = (word ^ _sbuf) & 0xFFFFFFFF;
        _macFunc(word);
        bd.setUint32(offset, word, Endian.little);
      },
      (offset) {
        final b = (buf[offset] ^ ((_sbuf >>> (32 - _nbuf)) & 0xFF)) & 0xFF;
        _mbuf = (_mbuf ^ (b << (32 - _nbuf))) & 0xFFFFFFFF;
        buf[offset] = b;
      },
    );
  }

  Uint8List finish(int macSize) {
    if (_nbuf != 0) {
      _macFunc(_mbuf);
    }

    _cycle();
    _r[_keyp] = (_r[_keyp] ^ (_initKonst ^ (_nbuf << 3))) & 0xFFFFFFFF;
    _nbuf = 0;

    for (var i = 0; i < _n; i++) {
      _r[i] = (_r[i] ^ _crc[i]) & 0xFFFFFFFF;
    }
    _diffuse();

    final mac = Uint8List(macSize);
    final bd = ByteData.sublistView(mac);
    var offset = 0;
    while (offset + 4 <= macSize) {
      _cycle();
      bd.setUint32(offset, _sbuf, Endian.little);
      offset += 4;
    }
    if (offset < macSize) {
      _cycle();
      for (var i = 0; offset + i < macSize; i++) {
        mac[offset + i] = (_sbuf >>> (8 * i)) & 0xFF;
      }
    }
    return mac;
  }
}

/// Abstract provider-agnostic Access Point Key Resolver.
///
/// Implements secure connection and packet exchanges for services using the
/// Access Point protocol (such as Spotify) to retrieve content decryption keys.
class ApKeyResolver {
  ApKeyResolver._();

  static final BigInt _dhPrime = BigInt.parse(
    'ffffffffffffffffc90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74'
    '020bbea63b139b22514a08798e3404ddef9519b3cd3a431b302b0a6df25f1437'
    '4fe1356d6d51c245e485b576625e7ec6f44c42e9a63a3620ffffffffffffffff',
    radix: 16,
  );

  static _ApConnection? _activeConnection;
  static Future<_ApConnection>? _connectingFuture;
  static String? _cachedCanonicalUsername;
  static Uint8List? _cachedStoredCredentials;

  static Future<_ApConnection> _getOrConnect(String token) async {
    final active = _activeConnection;
    if (active != null && !active.isClosed) {
      return active;
    }

    if (_connectingFuture != null) {
      return await _connectingFuture!;
    }

    final completer = Completer<_ApConnection>();
    _connectingFuture = completer.future;

    try {
      final conn = await _doConnect(token);
      _activeConnection = conn;
      completer.complete(conn);
      return conn;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _connectingFuture = null;
    }
  }

  static Future<_ApConnection> _doConnect(String token) async {
    // 1. Try connecting directly with cached stored credentials if available
    final username = _cachedCanonicalUsername;
    final storedCreds = _cachedStoredCredentials;

    if (username != null && storedCreds != null) {
      try {
        final conn = await _ApConnection.connect();
        await conn.authenticateStoredCredentials(
          username: username,
          storedCredentials: storedCreds,
          timeout: const Duration(seconds: 5),
        );
        logger.i('[ApKeyResolver] Reconnected using cached stored credentials for $username');
        return conn;
      } catch (e) {
        logger.w('[ApKeyResolver] Cached stored credentials failed, re-authenticating with token: $e');
        _cachedCanonicalUsername = null;
        _cachedStoredCredentials = null;
      }
    }

    // 2. Initial token authentication to obtain reusable credentials
    final tokenConn = await _ApConnection.connect();
    _ApWelcome welcome;
    try {
      welcome = await tokenConn.authenticateToken(token, timeout: const Duration(seconds: 5));
    } finally {
      tokenConn.close();
    }

    logger.i('[ApKeyResolver] Authenticated as "${welcome.canonicalUsername}", establishing persistent key session...');
    _cachedCanonicalUsername = welcome.canonicalUsername;
    _cachedStoredCredentials = welcome.reusableCredentials;

    // 3. Connect persistent session with stored credentials
    final keyConn = await _ApConnection.connect();
    await keyConn.authenticateStoredCredentials(
      username: welcome.canonicalUsername,
      storedCredentials: welcome.reusableCredentials,
      timeout: const Duration(seconds: 5),
    );
    return keyConn;
  }

  /// Resolves the 16-byte audio key for a given [trackId] and [fileId] using the access [token].
  static Future<String> resolveKey({
    required String trackId,
    required String fileId,
    required String token,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      _ApConnection? conn;
      try {
        conn = await _getOrConnect(token);
        return await conn.requestKey(
          trackId: trackId,
          fileId: fileId,
          timeout: const Duration(seconds: 8),
        );
      } catch (e) {
        logger.w('[ApKeyResolver] Key request attempt $attempt failed: $e');
        if (conn == null || conn.isClosed || e is SocketException || e is TimeoutException) {
          if (identical(conn, _activeConnection)) {
            _activeConnection = null;
            conn?.close();
          }
        }
        if (attempt == 1) rethrow;
      }
    }
    throw Exception('Failed to resolve audio key after retries');
  }
}

// --- Protobuf Encoding & Decoding Helpers ---
void _writeVarint(BytesBuilder b, int value) {
  var v = value;
  while (v >= 0x80) {
    b.addByte((v & 0x7f) | 0x80);
    v >>= 7;
  }
  b.addByte(v & 0x7f);
}

void _writeField(BytesBuilder b, int fieldNumber, int wireType, List<int> data) {
  _writeVarint(b, (fieldNumber << 3) | wireType);
  if (wireType == 2) {
    _writeVarint(b, data.length);
  }
  b.add(data);
}

void _writeVarintField(BytesBuilder b, int fieldNumber, int value) {
  _writeVarint(b, (fieldNumber << 3) | 0);
  _writeVarint(b, value);
}

({int value, int nextOffset}) _readVarint(Uint8List data, int offset) {
  var result = 0;
  var shift = 0;
  var curr = offset;
  while (curr < data.length) {
    final b = data[curr++];
    result |= (b & 0x7f) << shift;
    if ((b & 0x80) == 0) break;
    shift += 7;
  }
  return (value: result, nextOffset: curr);
}

class _ApWelcome {
  final String canonicalUsername;
  final int reusableCredentialsType;
  final Uint8List reusableCredentials;

  _ApWelcome({
    required this.canonicalUsername,
    required this.reusableCredentialsType,
    required this.reusableCredentials,
  });

  static _ApWelcome parse(Uint8List data) {
    var offset = 0;
    String username = '';
    int credsType = 1;
    Uint8List creds = Uint8List(0);

    while (offset < data.length) {
      final tagAndWire = _readVarint(data, offset);
      offset = tagAndWire.nextOffset;
      final tag = tagAndWire.value >> 3;
      final wireType = tagAndWire.value & 0x7;

      if (wireType == 0) {
        final val = _readVarint(data, offset);
        offset = val.nextOffset;
        if (tag == 0x1e) { // 30
          credsType = val.value;
        }
      } else if (wireType == 2) {
        final len = _readVarint(data, offset);
        offset = len.nextOffset;
        final bytes = data.sublist(offset, offset + len.value);
        offset += len.value;
        if (tag == 0x0a) { // 10
          username = utf8.decode(bytes);
        } else if (tag == 0x28) { // 40
          creds = Uint8List.fromList(bytes);
        }
      } else {
        break;
      }
    }

    return _ApWelcome(
      canonicalUsername: username,
      reusableCredentialsType: credsType,
      reusableCredentials: creds,
    );
  }
}

class _ApConnection {
  final Socket _socket;
  late final StreamSubscription<List<int>> _socketSub;
  final List<int> _incomingBuffer = [];
  Completer<void>? _dataNotifier;
  bool _closed = false;

  ShannonCipher? _sendCipher;
  ShannonCipher? _recvCipher;
  int _sendNonce = 0;
  int _recvNonce = 0;
  int? _pendingCmd;
  int? _pendingPayloadSize;
  int _seqCounter = 0;
  final Map<int, Completer<String>> _pendingKeyRequests = {};
  final StreamController<({int cmd, Uint8List data})> _packets =
      StreamController.broadcast();

  bool get isClosed => _closed;

  _ApConnection._(this._socket) {
    _socketSub = _socket.listen(
      (chunk) {
        _incomingBuffer.addAll(chunk);
        if (_dataNotifier != null && !_dataNotifier!.isCompleted) {
          _dataNotifier!.complete();
        }
        _processEncryptedPackets();
      },
      onError: (e) {
        logger.w('[ApKeyResolver] Socket error: $e');
        if (_dataNotifier != null && !_dataNotifier!.isCompleted) {
          _dataNotifier!.completeError(e);
        }
      },
      onDone: () {
        _closed = true;
        if (_dataNotifier != null && !_dataNotifier!.isCompleted) {
          _dataNotifier!.complete();
        }
        _packets.close();
        for (final comp in _pendingKeyRequests.values) {
          if (!comp.isCompleted) {
            comp.completeError(const SocketException('AP socket closed while awaiting audio key'));
          }
        }
        _pendingKeyRequests.clear();
      },
    );
  }

  Future<Uint8List> _readExact(int length) async {
    while (_incomingBuffer.length < length) {
      if (_closed) {
        throw const SocketException('Connection closed while reading handshake');
      }
      _dataNotifier = Completer<void>();
      await _dataNotifier!.future;
    }
    final result = Uint8List.fromList(_incomingBuffer.sublist(0, length));
    _incomingBuffer.removeRange(0, length);
    return result;
  }

  void _processEncryptedPackets() {
    if (_recvCipher == null) return;

    while (true) {
      if (_pendingCmd == null) {
        if (_incomingBuffer.length < 3) return;
        final headerBytes = Uint8List.fromList(_incomingBuffer.sublist(0, 3));
        _incomingBuffer.removeRange(0, 3);

        _recvCipher!.nonceU32(_recvNonce++);
        _recvCipher!.decrypt(headerBytes);

        _pendingCmd = headerBytes[0];
        _pendingPayloadSize = ByteData.sublistView(headerBytes).getUint16(1, Endian.big);
      }

      final payloadSize = _pendingPayloadSize!;
      final totalNeeded = payloadSize + 4; // payload + 4 bytes MAC
      if (_incomingBuffer.length < totalNeeded) {
        return; // Await rest of packet
      }

      final payload = Uint8List.fromList(_incomingBuffer.sublist(0, payloadSize));
      final mac = Uint8List.fromList(_incomingBuffer.sublist(payloadSize, totalNeeded));
      _incomingBuffer.removeRange(0, totalNeeded);

      _recvCipher!.decrypt(payload);
      final computedMac = _recvCipher!.finish(4);

      final cmd = _pendingCmd!;
      _pendingCmd = null;
      _pendingPayloadSize = null;

      var macMatches = true;
      for (var i = 0; i < 4; i++) {
        if (computedMac[i] != mac[i]) {
          macMatches = false;
          break;
        }
      }
      if (!macMatches) {
        logger.w('[ApKeyResolver] Packet MAC mismatch for cmd 0x${cmd.toRadixString(16)}');
      }

      if (kLogPackets) {
        logger.d('[ApKeyResolver] Packet received: cmd=0x${cmd.toRadixString(16)}, size=$payloadSize');
      }

      // Auto-respond to server Ping (0x04) with Pong (0x49) to keep connection alive
      if (cmd == 0x04) {
        _sendPacket(0x49, Uint8List.fromList([0, 0, 0, 0]));
      } else if (cmd == 0x0d) {
        // AesKey response: [4-byte seq, 16-byte key]
        if (payload.length >= 20) {
          final seq = ByteData.sublistView(payload).getUint32(0, Endian.big);
          final keyBytes = payload.sublist(4, 20);
          final keyHex = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          final comp = _pendingKeyRequests.remove(seq);
          if (comp != null && !comp.isCompleted) {
            comp.complete(keyHex);
          }
        }
      } else if (cmd == 0x0e) {
        // AesKeyError response: [4-byte seq, 2-byte error code]
        if (payload.length >= 4) {
          final seq = ByteData.sublistView(payload).getUint32(0, Endian.big);
          final errCode = payload.length >= 6
              ? ByteData.sublistView(payload).getUint16(4, Endian.big)
              : 0;
          final comp = _pendingKeyRequests.remove(seq);
          if (comp != null && !comp.isCompleted) {
            comp.completeError(
              Exception('Spotify rejected audio key request (error 0x${errCode.toRadixString(16).padLeft(4, '0')})'),
            );
          }
        }
      }

      _packets.add((cmd: cmd, data: payload));
    }
  }

  static Future<_ApConnection> connect() async {
    final hosts = ['ap.spotify.com', 'ap-gew4.spotify.com', 'ap-gew1.spotify.com'];
    Socket? socket;
    for (final host in hosts) {
      try {
        socket = await Socket.connect(host, 443, timeout: const Duration(seconds: 5));
        break;
      } catch (_) {}
    }
    if (socket == null) {
      throw const SocketException('Could not connect to any Spotify Access Point');
    }

    final conn = _ApConnection._(socket);

    // 1. Perform Diffie-Hellman Handshake
    final rand = Random.secure();
    final clientPrivateBytes = Uint8List(95);
    for (var i = 0; i < clientPrivateBytes.length; i++) {
      clientPrivateBytes[i] = rand.nextInt(256);
    }
    final clientPrivateKey = _bytesToBigInt(clientPrivateBytes);
    final clientPublicKey = BigInt.from(2).modPow(clientPrivateKey, ApKeyResolver._dhPrime);
    final gc = _bigIntToBytes(clientPublicKey, 96);

    // Client Hello packet
    final clientNonce = Uint8List(16);
    for (var i = 0; i < clientNonce.length; i++) {
      clientNonce[i] = rand.nextInt(256);
    }

    final helloPayload = _encodeClientHello(gc, clientNonce);
    final helloHeader = Uint8List(6);
    final helloBd = ByteData.sublistView(helloHeader);
    helloBd.setUint16(0, 0x0004);
    helloBd.setUint32(2, 6 + helloPayload.length);

    final sentAccumulator = BytesBuilder();
    sentAccumulator.add(helloHeader);
    sentAccumulator.add(helloPayload);
    final sentBytes = sentAccumulator.toBytes();

    socket.add(sentBytes);
    await socket.flush();

    // Read APResponseMessage using single continuous stream reader
    final recvAccumulator = BytesBuilder();
    final responseHeader = await conn._readExact(4);
    recvAccumulator.add(responseHeader);
    final responseSize = ByteData.sublistView(responseHeader).getUint32(0);
    final responsePayload = await conn._readExact(responseSize - 4);
    recvAccumulator.add(responsePayload);

    final gs = _extractGsFromApResponse(responsePayload);
    final serverPublicKey = _bytesToBigInt(gs);
    final sharedSecret = serverPublicKey.modPow(clientPrivateKey, ApKeyResolver._dhPrime);
    final sharedSecretBytes = _bigIntToBytes(sharedSecret, 96);

    final handshakePackets = Uint8List.fromList([
      ...sentBytes,
      ...recvAccumulator.toBytes(),
    ]);

    // Derive Shannon keys
    final dataBuilder = BytesBuilder();
    for (var i = 1; i <= 5; i++) {
      final hmac = Hmac(sha1, sharedSecretBytes);
      final digest = hmac.convert([...handshakePackets, i]);
      dataBuilder.add(digest.bytes);
    }
    final allKeys = dataBuilder.toBytes();

    final challengeHmac = Hmac(sha1, allKeys.sublist(0, 20)).convert(handshakePackets);
    final challenge = Uint8List.fromList(challengeHmac.bytes);
    final sendKey = allKeys.sublist(20, 52);
    final recvKey = allKeys.sublist(52, 84);

    // Send ClientResponsePlaintext
    final clientRespPayload = _encodeClientResponse(challenge);
    final respHeader = Uint8List(4);
    ByteData.sublistView(respHeader).setUint32(0, 4 + clientRespPayload.length);
    socket.add(respHeader);
    socket.add(clientRespPayload);
    await socket.flush();

    conn._sendCipher = ShannonCipher(sendKey);
    conn._recvCipher = ShannonCipher(recvKey);
    conn._processEncryptedPackets();

    return conn;
  }

  Future<_ApWelcome> authenticateToken(String token, {Duration timeout = const Duration(seconds: 10)}) async {
    final loginBytes = _encodeLoginPacket(
      authType: 3, // AUTHENTICATION_SPOTIFY_TOKEN
      authData: utf8.encode(token),
    );
    _sendPacket(0xab, loginBytes);

    final completer = Completer<_ApWelcome>();
    late StreamSubscription sub;

    sub = _packets.stream.listen((pkt) {
      if (pkt.cmd == 0xac) {
        try {
          final welcome = _ApWelcome.parse(pkt.data);
          if (!completer.isCompleted) completer.complete(welcome);
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      } else if (pkt.cmd == 0xad) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Spotify AP authentication failure (0xad)'));
        }
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    }, onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(const SocketException('AP socket closed during token authentication'));
      }
    });

    try {
      return await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  Future<void> authenticateStoredCredentials({
    required String username,
    required List<int> storedCredentials,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final loginBytes = _encodeLoginPacket(
      username: username,
      authType: 1, // AUTHENTICATION_STORED_SPOTIFY_CREDENTIALS
      authData: storedCredentials,
    );
    _sendPacket(0xab, loginBytes);

    final completer = Completer<void>();
    late StreamSubscription sub;

    sub = _packets.stream.listen((pkt) {
      if (pkt.cmd == 0xac) {
        if (!completer.isCompleted) completer.complete();
      } else if (pkt.cmd == 0xad) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Spotify AP authentication failure with stored credentials'));
        }
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    }, onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(const SocketException('AP socket closed during stored credentials login'));
      }
    });

    try {
      await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  Future<String> requestKey({
    required String trackId,
    required String fileId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_closed) {
      throw const SocketException('AP connection is closed');
    }

    final seq = ++_seqCounter;
    final cleanTrack = trackId.trim().replaceAll(RegExp(r'^spotify:track:'), '');
    final trackGidHex = _spotifyIdToHex(cleanTrack);
    final trackBytes = _hexToBytes(trackGidHex);
    final fileBytes = _hexToBytes(fileId.trim());

    final reqData = BytesBuilder();
    reqData.add(fileBytes); // 20 bytes
    reqData.add(trackBytes); // 16 bytes
    final seqBytes = Uint8List(4);
    ByteData.sublistView(seqBytes).setUint32(0, seq, Endian.big);
    reqData.add(seqBytes); // 4 bytes sequence
    reqData.add([0x00, 0x00]); // 2 bytes padding

    final completer = Completer<String>();
    _pendingKeyRequests[seq] = completer;

    _sendPacket(0x0c, reqData.toBytes()); // PacketType::RequestKey = 0x0c

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingKeyRequests.remove(seq);
          throw TimeoutException('Audio key request timed out for track $trackId (seq $seq)');
        },
      );
    } catch (_) {
      _pendingKeyRequests.remove(seq);
      rethrow;
    }
  }

  void _sendPacket(int cmd, Uint8List payload) {
    if (_sendCipher == null) return;
    final raw = Uint8List(3 + payload.length);
    raw[0] = cmd;
    ByteData.sublistView(raw).setUint16(1, payload.length, Endian.big);
    raw.setRange(3, raw.length, payload);

    _sendCipher!.nonceU32(_sendNonce++);
    _sendCipher!.encrypt(raw);
    final mac = _sendCipher!.finish(4);

    _socket.add(raw);
    _socket.add(mac);
  }

  void close() {
    try {
      _socketSub.cancel();
      _socket.destroy();
    } catch (_) {}
  }

  static Uint8List _encodeClientHello(Uint8List gc, Uint8List clientNonce) {
    final b = BytesBuilder();

    // Field 10 (build_info):
    final buildInfo = BytesBuilder();
    _writeVarintField(buildInfo, 0x0a, 0); // product = PRODUCT_CLIENT (0)
    _writeVarintField(buildInfo, 0x14, 1); // product_flags = PRODUCT_FLAG_DEV_BUILD (1)
    _writeVarintField(buildInfo, 0x1e, 0x27); // platform = PLATFORM_WIN32_X86_64 (39 = 0x27)
    _writeVarintField(buildInfo, 0x28, 124200290); // version = SPOTIFY_VERSION (124200290)
    _writeField(b, 0x0a, 2, buildInfo.toBytes());

    // Field 30 (cryptosuites_supported):
    _writeVarintField(b, 0x1e, 0); // CRYPTO_SUITE_SHANNON (0)

    // Field 50 (login_crypto_hello):
    final cryptoHello = BytesBuilder();
    final dh = BytesBuilder();
    _writeField(dh, 0x0a, 2, gc); // gc (field 10)
    _writeVarintField(dh, 0x14, 1); // server_keys_known = 1 (field 20)
    _writeField(cryptoHello, 0x0a, 2, dh.toBytes());
    _writeField(b, 0x32, 2, cryptoHello.toBytes());

    // Field 60 (client_nonce):
    _writeField(b, 0x3c, 2, clientNonce);

    // Field 70 (padding):
    _writeField(b, 0x46, 2, [0x1e]);

    return b.toBytes();
  }

  static Uint8List _encodeClientResponse(Uint8List challenge) {
    final b = BytesBuilder();

    // Field 10 (login_crypto_response):
    final cryptoResp = BytesBuilder();
    final dh = BytesBuilder();
    _writeField(dh, 0x0a, 2, challenge); // hmac
    _writeField(cryptoResp, 0x0a, 2, dh.toBytes());
    _writeField(b, 0x0a, 2, cryptoResp.toBytes());

    // Field 20 (pow_response):
    _writeField(b, 0x14, 2, const []);

    // Field 30 (crypto_response):
    _writeField(b, 0x1e, 2, const []);

    return b.toBytes();
  }

  static Uint8List _encodeLoginPacket({
    String? username,
    required int authType,
    required List<int> authData,
  }) {
    final b = BytesBuilder();

    // Field 10 (login_credentials):
    final creds = BytesBuilder();
    if (username != null && username.isNotEmpty) {
      _writeField(creds, 0x0a, 2, utf8.encode(username));
    }
    _writeVarintField(creds, 0x14, authType); // typ
    _writeField(creds, 0x1e, 2, authData);    // auth_data
    _writeField(b, 0x0a, 2, creds.toBytes());

    // Field 50 (system_info):
    final sys = BytesBuilder();
    _writeVarintField(sys, 0x0a, 2); // cpu_family = X86_64 (2)
    _writeVarintField(sys, 0x3c, 1); // os = Windows (1)
    _writeField(sys, 0x5a, 2, utf8.encode('librespot-0.4.2')); // system_information_string
    _writeField(sys, 0x64, 2, utf8.encode('wisp-desktop-client')); // device_id
    _writeField(b, 0x32, 2, sys.toBytes());

    // Field 70 (version_string):
    _writeField(b, 0x46, 2, utf8.encode('librespot 0.4.2'));

    return b.toBytes();
  }

  static Uint8List _extractGsFromApResponse(Uint8List responsePayload) {
    // Scan for the 96-byte Diffie-Hellman public key (tag 0x52 followed by 0x60 length)
    for (var i = 0; i <= responsePayload.length - 98; i++) {
      if (responsePayload[i] == 0x52 && responsePayload[i + 1] == 0x60) {
        return Uint8List.fromList(responsePayload.sublist(i + 2, i + 2 + 96));
      }
    }
    throw Exception('Could not extract Diffie-Hellman public key from AP response');
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  static Uint8List _bigIntToBytes(BigInt number, int length) {
    final result = Uint8List(length);
    var temp = number;
    for (var i = length - 1; i >= 0; i--) {
      result[i] = (temp & BigInt.from(0xff)).toInt();
      temp >>= 8;
    }
    return result;
  }

  static String _spotifyIdToHex(String id) {
    const base62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final clean = id.trim();
    if (clean.length == 32 && RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(clean)) {
      return clean.toLowerCase();
    }
    final bytes = <int>[];
    for (var i = 0; i < clean.length; i++) {
      final ch = clean[i];
      final idx = base62.indexOf(ch);
      if (idx == -1) return clean;
      var carry = idx;
      for (var j = 0; j < bytes.length; j++) {
        final val = bytes[j] * 62 + carry;
        bytes[j] = val & 0xff;
        carry = val >> 8;
      }
      while (carry > 0) {
        bytes.add(carry & 0xff);
        carry >>= 8;
      }
    }
    final sb = StringBuffer();
    for (var i = bytes.length - 1; i >= 0; i--) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString().padLeft(32, '0');
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '');
    final bytes = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < clean.length; i += 2) {
      bytes[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }
}
