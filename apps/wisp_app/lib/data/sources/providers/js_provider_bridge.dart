// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'auth_input_dialog.dart';
import 'auth_webview_dialog.dart';
import 'ap_key_resolver.dart';
import 'crypto_bridge_utils.dart';
import 'jumo_crypto_utils.dart';
import 'service_session_manager.dart';

/// Configures and installs the standardized `wisp.*` host bridges into a JavaScript runtime.
class JsProviderBridge {
  JsProviderBridge._();

  static void resolveJsCallback(
    JavascriptRuntime runtime,
    int cbId,
    Map<String, dynamic> data,
  ) {
    try {
      final jsonStr = jsonEncode(data);
      runtime.evaluate('globalThis.__wisp_resolve_callback($cbId, $jsonStr);');
      runtime.executePendingJob();
    } catch (e) {
      logger.e('[JsProviderBridge] Error resolving callback $cbId: $e');
    }
  }

  /// Sets up all `wisp.*` host bridges (fetch, service vault, crypto, auth, storage, logging).
  static void setupBridge(
    JavascriptRuntime runtime, {
    required String providerId,
    required String providerName,
    String? serviceId,
  }) {
    final effectiveServiceId = serviceId ?? providerId;
    final Map<int, Completer<Map<String, dynamic>?>> refreshFnCompleters = {};

    // 1. Logging
    runtime.onMessage('wisp_log', (dynamic args) {
      try {
        final map = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : (args as Map).cast<String, dynamic>();
        final level = map['level'] as String? ?? 'info';
        final msg = map['msg'] as String? ?? '';
        if (level == 'error') {
          logger.e('[JS/$providerName] $msg');
        } else if (level == 'warn') {
          logger.w('[JS/$providerName] $msg');
        } else {
          logger.i('[JS/$providerName] $msg');
        }
      } catch (_) {}
      return '';
    });

    // 2. HTTP Fetch
    runtime.onMessage('wisp_fetch', (dynamic args) {
      unawaited(() async {
        int? cbId;
        String? url;
        String descriptor = '';
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          url = map['url'] as String?;
          final method = (map['method'] as String?)?.toUpperCase() ?? 'GET';
          final headers =
              (map['headers'] as Map?)?.cast<String, String>() ?? {};
          final body = map['body'] as String?;
          final bodyBase64 = map['bodyBase64'] as String?;
          final label = map['label'] as String?;

          if (url == null || cbId == null) {
            throw ArgumentError('url and cbId are required for wisp_fetch');
          }

          String? operationName;
          if (body != null && body.isNotEmpty) {
            try {
              final trimmed = body.trimLeft();
              if (trimmed.startsWith('{')) {
                final decoded = jsonDecode(body);
                if (decoded is Map) {
                  if (decoded['operationName'] != null) {
                    operationName = decoded['operationName'].toString();
                  } else if (decoded['query'] is String) {
                    final q = (decoded['query'] as String).trim();
                    final match = RegExp(
                      r'^(query|mutation|subscription)\s+([A-Za-z0-9_]+)',
                    ).firstMatch(q);
                    if (match != null) {
                      operationName = '${match.group(1)} ${match.group(2)}';
                    }
                  }
                }
              }
            } catch (_) {}
          }
          if (operationName == null) {
            final uri = Uri.tryParse(url);
            final opParam = uri?.queryParameters['operationName'];
            if (opParam != null && opParam.isNotEmpty) {
              operationName = opParam;
            }
          }

          if (operationName != null && operationName.isNotEmpty) {
            descriptor = ' [$operationName]';
          } else if (label != null && label.isNotEmpty) {
            descriptor = ' [$label]';
          }

          logger.d('[JS/$providerName HTTP] -> $method $url$descriptor');
          final uri = Uri.parse(url);
          final client = IOClient(CryptoBridgeUtils.createBridgeHttpClient() as dynamic);
          http.Response response;
          try {
            final request = http.Request(method, uri);
            request.headers.addAll(headers);
            if (bodyBase64 != null && bodyBase64.isNotEmpty) {
              request.bodyBytes = base64Decode(bodyBase64);
            } else if (body != null) {
              request.body = body;
            }
            final streamedResponse = await client.send(request);
            response = await http.Response.fromStream(streamedResponse);
            logger.d(
              '[JS/$providerName HTTP] <- $method $url$descriptor: status=${response.statusCode}',
            );
          } finally {
            client.close();
          }

          resolveJsCallback(runtime, cbId, {
            'status': response.statusCode,
            'body': response.body,
            'bodyBase64': base64Encode(response.bodyBytes),
            'headers': response.headers,
          });
        } catch (e) {
          logger.e('[JS/$providerName HTTP] Error requesting $url$descriptor: $e');
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {
              'status': 500,
              'body': '',
              'bodyBase64': '',
              'error': e.toString(),
              'headers': {},
            });
          }
        }
      }());
      return '';
    });

    // 3. Service Session Vault
    runtime.onMessage('wisp_service_get_session', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final sId = map['serviceId'] as String? ?? effectiveServiceId;
          final session = await ServiceSessionManager.instance.getSession(sId);
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'session': session});
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'session': null, 'error': e.toString()});
          }
        }
      }());
      return '';
    });

    runtime.onMessage('wisp_service_set_session', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final sId = map['serviceId'] as String? ?? effectiveServiceId;
          final session = (map['session'] as Map?)?.cast<String, dynamic>() ?? {};
          await ServiceSessionManager.instance.setSession(sId, session);
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'success': true});
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'success': false, 'error': e.toString()});
          }
        }
      }());
      return '';
    });

    runtime.onMessage('wisp_service_clear_session', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final sId = map['serviceId'] as String? ?? effectiveServiceId;
          await ServiceSessionManager.instance.clearSession(sId);
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'success': true});
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'success': false, 'error': e.toString()});
          }
        }
      }());
      return '';
    });

    // 4. Refresh Lock (Host-level Mutex)
    runtime.onMessage('wisp_service_refresh_lock', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final sId = map['serviceId'] as String? ?? effectiveServiceId;

          if (cbId == null) return;

          logger.i('[JS/$providerName] Requesting refresh lock for service "$sId"...');
          final result = await ServiceSessionManager.instance.withRefreshLock(
            sId,
            () async {
              // Execute the callback in JS
              final fnCompleter = Completer<Map<String, dynamic>?>();
              refreshFnCompleters[cbId!] = fnCompleter;
              runtime.evaluate('globalThis.__wisp_run_refresh_fn($cbId);');
              runtime.executePendingJob();
              return await fnCompleter.future;
            },
          );

          resolveJsCallback(runtime, cbId, {'session': result});
        } catch (e) {
          logger.e('[JS/$providerName] Error in withRefreshLock: $e');
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'error': e.toString()});
          }
        }
      }());
      return '';
    });

    runtime.onMessage('wisp_service_refresh_done', (dynamic args) {
      try {
        final map = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : (args as Map).cast<String, dynamic>();
        final cbId = map['cbId'] as int?;
        if (cbId != null) {
          final fnCompleter = refreshFnCompleters.remove(cbId);
          if (fnCompleter != null && !fnCompleter.isCompleted) {
            if (map.containsKey('error') && map['error'] != null) {
              fnCompleter.completeError(Exception(map['error']));
            } else {
              final result = map['result'] as Map?;
              fnCompleter.complete(result?.cast<String, dynamic>());
            }
          }
        }
      } catch (e) {
        logger.e('[JS/$providerName] Error in refresh_done: $e');
      }
      return '';
    });

    // 5. Crypto Bridges
    runtime.onMessage('wisp_crypto_totp', (dynamic args) {
      int? cbId;
      try {
        final map = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : (args as Map).cast<String, dynamic>();
        cbId = map['cbId'] as int?;
        final secret = map['secret'] as String? ?? '';
        final digits = map['digits'] as int? ?? 6;
        final interval = map['interval'] as int? ?? 30;
        final otp = CryptoBridgeUtils.generateTotp(
          secret,
          digits: digits,
          interval: interval,
        );
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'otp': otp});
        }
      } catch (e) {
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'otp': '', 'error': e.toString()});
        }
      }
      return '';
    });

    runtime.onMessage('wisp_crypto_sha1', (dynamic args) {
      int? cbId;
      try {
        final map = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : (args as Map).cast<String, dynamic>();
        cbId = map['cbId'] as int?;
        final text = map['text'] as String? ?? '';
        final hash = CryptoBridgeUtils.sha1Hex(text);
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'hash': hash});
        }
      } catch (e) {
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'hash': '', 'error': e.toString()});
        }
      }
      return '';
    });

    runtime.onMessage('wisp_crypto_sha256', (dynamic args) {
      int? cbId;
      try {
        final map = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : (args as Map).cast<String, dynamic>();
        cbId = map['cbId'] as int?;
        final text = map['text'] as String? ?? '';
        final hash = CryptoBridgeUtils.sha256Hex(text);
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'hash': hash});
        }
      } catch (e) {
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'hash': '', 'error': e.toString()});
        }
      }
      return '';
    });

    runtime.onMessage('wisp_crypto_hmac_sha1', (dynamic args) {
      int? cbId;
      try {
        final map = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : (args as Map).cast<String, dynamic>();
        cbId = map['cbId'] as int?;
        final key = map['key'] as String? ?? '';
        final data = map['data'] as String? ?? '';
        final hash = CryptoBridgeUtils.hmacSha1Hex(key, data);
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'hash': hash});
        }
      } catch (e) {
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'hash': '', 'error': e.toString()});
        }
      }
      return '';
    });

    runtime.onMessage('wisp_crypto_random_hex', (dynamic args) {
      int? cbId;
      try {
        final map = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : (args as Map).cast<String, dynamic>();
        cbId = map['cbId'] as int?;
        final length = map['length'] as int? ?? 32;
        final hex = CryptoBridgeUtils.randomHex(length);
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'hex': hex});
        }
      } catch (e) {
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'hex': '', 'error': e.toString()});
        }
      }
      return '';
    });

    runtime.onMessage('wisp_crypto_generate_p256_keypair', (dynamic args) {
      int? cbId;
      try {
        final map = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : (args as Map).cast<String, dynamic>();
        cbId = map['cbId'] as int?;
        final res = JumoCryptoUtils.generateP256KeyPair();
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, res);
        }
      } catch (e) {
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'error': e.toString()});
        }
      }
      return '';
    });

    runtime.onMessage('wisp_crypto_decrypt_jumo', (dynamic args) {
      int? cbId;
      try {
        final map = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : (args as Map).cast<String, dynamic>();
        cbId = map['cbId'] as int?;
        final clientPrivHex = map['clientPrivHex'] as String;
        final serverPubKey = map['serverPubKey'] as String;
        final bodyB64 = map['bodyB64'] as String;
        final url = map['url'] as String;
        final nonce = map['nonce'] as String;

        // 1. Derive shared secret X
        final sharedX = JumoCryptoUtils.deriveSharedSecretX(clientPrivHex, serverPubKey);
        // 2. Derive AES key
        final aesKey = JumoCryptoUtils.deriveAesGcmKey(sharedX);
        // 3. Decode payload body bytes
        var cleanB64 = bodyB64.replaceAll('-', '+').replaceAll('_', '/');
        while (cleanB64.length % 4 != 0) {
          cleanB64 += '=';
        }
        final bodyBytes = base64Decode(cleanB64);
        final iv = bodyBytes.sublist(0, 12);
        final ciphertext = bodyBytes.sublist(12);
        final aad = Uint8List.fromList(utf8.encode('$url\n$nonce'));

        // 4. Decrypt
        final decrypted = JumoCryptoUtils.decryptAesGcm(
          key: aesKey,
          iv: iv,
          ciphertextWithTag: ciphertext,
          aad: aad,
        );
        final decryptedText = utf8.decode(decrypted);
        final jsonResult = jsonDecode(decryptedText);

        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'result': jsonResult});
        }
      } catch (e) {
        if (cbId != null) {
          resolveJsCallback(runtime, cbId, {'error': e.toString()});
        }
      }
      return '';
    });

    // 6. Generic Auth Webview Dialog
    runtime.onMessage('wisp_auth_open_login', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final url = map['url'] as String?;
          final title = map['title'] as String? ?? 'Login';
          final targetCookies =
              (map['targetCookies'] as List?)?.map((e) => e.toString()).toList() ??
                  [];
          final redirectUrlPrefix = map['redirectUrlPrefix'] as String?;

          if (url == null || cbId == null) {
            throw ArgumentError('url and cbId are required for wisp_auth_open_login');
          }

          final navContext =
              NavigationHistory.instance.rootNavigatorKey.currentContext ??
              NavigationHistory.instance.navigatorKey.currentContext;
          if (navContext == null) {
            throw StateError('No navigation context available for login modal');
          }

          final result = await Navigator.of(navContext, rootNavigator: true).push<Map<String, dynamic>>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => AuthWebviewDialog(
                initialUrl: url,
                title: title,
                targetCookies: targetCookies,
                redirectUrlPrefix: redirectUrlPrefix,
              ),
            ),
          );

          resolveJsCallback(runtime, cbId, result ?? {});
        } catch (e) {
          logger.e('[JS/$providerName] Error opening login webview: $e');
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'error': e.toString()});
          }
        }
      }());
      return '';
    });

    runtime.onMessage('wisp_auth_prompt_input', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final title = map['title'] as String? ?? 'Input';
          final description = map['description'] as String?;
          final label = map['label'] as String? ?? 'Key';
          final hint = map['hint'] as String?;
          final defaultValue = map['defaultValue'] as String?;
          final link = map['link'] as String?;
          final linkText = map['linkText'] as String?;
          final isSecret = map['isSecret'] == true;

          final navContext =
              NavigationHistory.instance.rootNavigatorKey.currentContext ??
              NavigationHistory.instance.navigatorKey.currentContext;
          if (navContext == null) {
            throw StateError('No navigation context available for input dialog');
          }

          final result = await showDialog<String>(
            context: navContext,
            builder: (_) => AuthInputDialog(
              title: title,
              description: description,
              label: label,
              hint: hint,
              defaultValue: defaultValue,
              link: link,
              linkText: linkText,
              isSecret: isSecret,
            ),
          );

          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {
              'value': result,
              'cancelled': result == null,
            });
          }
        } catch (e) {
          logger.e('[JS/$providerName] Error opening input dialog: $e');
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'error': e.toString(), 'cancelled': true});
          }
        }
      }());
      return '';
    });

    // 7. Generic Storage
    runtime.onMessage('wisp_storage_get', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final key = map['key'] as String?;
          if (key != null && cbId != null) {
            final prefs = await SharedPreferences.getInstance();
            final val = prefs.getString('wisp_storage_${providerId}_$key');
            resolveJsCallback(runtime, cbId, {'value': val});
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'value': null, 'error': e.toString()});
          }
        }
      }());
      return '';
    });

    runtime.onMessage('wisp_storage_set', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final key = map['key'] as String?;
          final value = map['value'] as String?;
          if (key != null && value != null && cbId != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('wisp_storage_${providerId}_$key', value);
            resolveJsCallback(runtime, cbId, {'success': true});
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'success': false, 'error': e.toString()});
          }
        }
      }());
      return '';
    });

    runtime.onMessage('wisp_storage_delete', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final key = map['key'] as String?;
          if (key != null && cbId != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('wisp_storage_${providerId}_$key');
            resolveJsCallback(runtime, cbId, {'success': true});
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'success': false, 'error': e.toString()});
          }
        }
      }());
      return '';
    });

    // 7. Auth Delegation Bridges
    runtime.onMessage('wisp_auth_get_tokens', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final sId = map['serviceId'] as String? ?? effectiveServiceId;
          final forceRefresh = map['forceRefresh'] == true;

          final tokens = await AuthSourceManager.instance.getTokens(
            sId,
            forceRefresh: forceRefresh,
          );
          if (cbId != null) {
            if (tokens != null) {
              resolveJsCallback(runtime, cbId, {'tokens': tokens});
            } else {
              final session =
                  await ServiceSessionManager.instance.getSession(sId);
              if (session != null && session['accessToken'] != null) {
                resolveJsCallback(runtime, cbId, {'tokens': session});
              } else {
                resolveJsCallback(runtime, cbId, {
                  'tokens': null,
                  'error': 'Failed to obtain tokens for $sId',
                });
              }
            }
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {
              'tokens': null,
              'error': e.toString(),
            });
          }
        }
      }());
      return '';
    });

    runtime.onMessage('wisp_auth_login', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final sId = map['serviceId'] as String? ?? effectiveServiceId;
          await AuthSourceManager.instance.login(sId);
          final session = await ServiceSessionManager.instance.getSession(sId);
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {
              'success': session != null,
              'session': session,
            });
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {
              'success': false,
              'error': e.toString(),
            });
          }
        }
      }());
      return '';
    });

    runtime.onMessage('wisp_auth_logout', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final sId = map['serviceId'] as String? ?? effectiveServiceId;
          await AuthSourceManager.instance.logout(sId);
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'success': true});
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {
              'success': false,
              'error': e.toString(),
            });
          }
        }
      }());
      return '';
    });

    // 8. Legacy Spotify Token Bridge (for backwards compatibility)
    runtime.onMessage('wisp_get_spotify_tokens', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final forceRefresh = map['forceRefresh'] == true;
          final tokens = await AuthSourceManager.instance.getTokens(
            'spotify',
            forceRefresh: forceRefresh,
          );
          if (cbId != null) {
            if (tokens != null && tokens['accessToken'] != null) {
              resolveJsCallback(runtime, cbId, {
                'accessToken': tokens['accessToken'],
                'clientToken': tokens['clientToken'] ?? '',
              });
            } else {
              final session =
                  await ServiceSessionManager.instance.getSession('spotify');
              final access = session?['accessToken'] as String?;
              final client = session?['clientToken'] as String?;
              if (access != null && access.isNotEmpty) {
                resolveJsCallback(runtime, cbId, {
                  'accessToken': access,
                  'clientToken': client ?? '',
                });
              } else {
                resolveJsCallback(runtime, cbId, {
                  'error': 'No tokens available',
                });
              }
            }
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'error': e.toString()});
          }
        }
      }());
      return '';
    });

    // 9. Generic Audio Content Decryption Key Resolver Bridge
    runtime.onMessage('wisp_audio_resolve_key', (dynamic args) {
      unawaited(() async {
        int? cbId;
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          cbId = map['cbId'] as int?;
          final protocol = map['protocol'] as String? ?? 'ap';
          final trackId = map['trackId'] as String?;
          final fileId = map['fileId'] as String?;
          final token = map['token'] as String?;

          if (protocol == 'ap' && trackId != null && fileId != null && token != null) {
            final keyHex = await ApKeyResolver.resolveKey(
              trackId: trackId,
              fileId: fileId,
              token: token,
            );
            if (cbId != null) {
              resolveJsCallback(runtime, cbId, {
                'result': {'keyHex': keyHex}
              });
            }
          } else {
            throw ArgumentError('Unsupported protocol or missing parameters for audio key resolution');
          }
        } catch (e) {
          if (cbId != null) {
            resolveJsCallback(runtime, cbId, {'error': e.toString()});
          }
        }
      }());
      return '';
    });

    // 10. Inject standard global environment and polyfills
    runtime.evaluate('''
      globalThis.__wisp_pending_callbacks = {};
      globalThis.__wisp_pending_refresh_fns = {};
      globalThis.__wisp_callback_counter = 0;

      globalThis.__wisp_resolve_callback = function(cbId, dataStr) {
        try {
          var cb = globalThis.__wisp_pending_callbacks[cbId];
          if (cb) {
            delete globalThis.__wisp_pending_callbacks[cbId];
            var data = typeof dataStr === 'string' ? JSON.parse(dataStr) : dataStr;
            cb(data);
          }
        } catch (e) {
          console.error('Error in __wisp_resolve_callback: ' + e);
        }
      };

      globalThis.__wisp_run_refresh_fn = function(cbId) {
        try {
          var fn = globalThis.__wisp_pending_refresh_fns[cbId];
          if (fn) {
            delete globalThis.__wisp_pending_refresh_fns[cbId];
            Promise.resolve(fn()).then(function(result) {
              sendMessage('wisp_service_refresh_done', JSON.stringify({ cbId: cbId, result: result }));
            }).catch(function(err) {
              sendMessage('wisp_service_refresh_done', JSON.stringify({ cbId: cbId, error: String(err) }));
            });
          }
        } catch (e) {
          sendMessage('wisp_service_refresh_done', JSON.stringify({ cbId: cbId, error: String(e) }));
        }
      };

      globalThis.console = {
        log: function(msg) { sendMessage('wisp_log', JSON.stringify({ level: 'info', msg: String(msg) })); },
        error: function(msg) { sendMessage('wisp_log', JSON.stringify({ level: 'error', msg: String(msg) })); },
        warn: function(msg) { sendMessage('wisp_log', JSON.stringify({ level: 'warn', msg: String(msg) })); },
        debug: function(msg) { sendMessage('wisp_log', JSON.stringify({ level: 'debug', msg: String(msg) })); }
      };

      if (typeof atob === 'undefined') {
        globalThis.atob = function(b64) {
          var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          var str = String(b64).replace(/=+\$/, '');
          var output = '';
          for (var bc = 0, bs, buffer, idx = 0; buffer = str.charAt(idx++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
            buffer = chars.indexOf(buffer);
          }
          return output;
        };
      }

      if (typeof btoa === 'undefined') {
        globalThis.btoa = function(bin) {
          var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          var str = String(bin);
          var output = '';
          for (var block, charCode, idx = 0, map = chars; str.charAt(idx | 0) || (map = '=', idx % 1); output += map.charAt(63 & block >> 8 - idx % 1 * 8)) {
            charCode = str.charCodeAt(idx += 3/4);
            if (charCode > 0xFF) throw new Error('btoa failed: character outside Latin1');
            block = block << 8 | charCode;
          }
          return output;
        };
      }

      if (typeof Intl === 'undefined') {
        globalThis.Intl = {
          DateTimeFormat: function() {
            return {
              resolvedOptions: function() {
                return {
                  timeZone: 'UTC',
                  locale: 'en-US'
                };
              }
            };
          }
        };
      }

      if (typeof URL === 'undefined') {
        globalThis.URL = function(url, base) {
          var full = url;
          if (base) {
            var b = String(base).replace(/\\/+\$/, '');
            var u = String(url).replace(/^\\/+/, '');
            if (!String(url).match(/^https?:\\/\\//i)) {
              full = b + '/' + u;
            }
          }
          this.href = full;
          var match = full.match(/^(https?:\\/\\/[^\\/?#]+)([^?#]*)(\\?[^#]*)?(#.*)?/i);
          if (match) {
            this.origin = match[1];
            this.pathname = match[2] || '/';
            this.search = match[3] || '';
            this.hash = match[4] || '';
          } else {
            this.origin = '';
            this.pathname = full;
            this.search = '';
            this.hash = '';
          }
          this.toString = function() { return this.href; };
        };
      }

      if (typeof URLSearchParams === 'undefined') {
        globalThis.URLSearchParams = function(init) {
          var params = {};
          if (typeof init === 'string') {
            var str = init.replace(/^\\?/, '');
            var pairs = str.split('&');
            for (var i = 0; i < pairs.length; i++) {
              if (!pairs[i]) continue;
              var parts = pairs[i].split('=');
              params[decodeURIComponent(parts[0])] = decodeURIComponent(parts.slice(1).join('='));
            }
          } else if (init && typeof init === 'object') {
            for (var k in init) params[k] = String(init[k]);
          }
          this.get = function(name) { return params[name] !== undefined ? params[name] : null; };
          this.set = function(name, val) { params[name] = String(val); };
          this.toString = function() {
            var res = [];
            for (var k in params) res.push(encodeURIComponent(k) + '=' + encodeURIComponent(params[k]));
            return res.join('&');
          };
        };
      }

      globalThis.wisp = {
        fetch: function(url, options) {
          return new Promise(function(resolve) {
            var cbId = ++globalThis.__wisp_callback_counter;
            globalThis.__wisp_pending_callbacks[cbId] = function(res) {
              if (!res) res = { status: 500, headers: {}, body: '', bodyBase64: '' };
              resolve({
                status: res.status || 500,
                ok: (res.status >= 200 && res.status < 300),
                headers: res.headers || {},
                text: async function() { return res.body || ''; },
                json: async function() { return JSON.parse(res.body || '{}'); },
                base64: async function() { return res.bodyBase64 || ''; },
                bytes: async function() {
                  var b64 = res.bodyBase64 || '';
                  if (!b64) return new Uint8Array(0);
                  var raw = atob(b64);
                  var arr = new Uint8Array(raw.length);
                  for (var i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
                  return arr;
                }
              });
            };
            var body = (options && options.body) || null;
            var bodyBase64 = (options && options.bodyBase64) || null;
            if (body && typeof Uint8Array !== 'undefined' && body instanceof Uint8Array) {
              var binStr = '';
              for (var i = 0; i < body.length; i++) binStr += String.fromCharCode(body[i]);
              bodyBase64 = btoa(binStr);
              body = null;
            }
            var payload = {
              cbId: cbId,
              url: url,
              method: (options && options.method) || 'GET',
              headers: (options && options.headers) || {},
              body: body,
              bodyBase64: bodyBase64,
              label: (options && options.label) || null
            };
            sendMessage('wisp_fetch', JSON.stringify(payload));
          });
        },

        service: {
          getSession: function(serviceId) {
            var targetService = serviceId || '$effectiveServiceId';
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.session : null);
              };
              sendMessage('wisp_service_get_session', JSON.stringify({ serviceId: targetService, cbId: cbId }));
            });
          },

          setSession: function(serviceId, sessionData) {
            var targetService = (typeof serviceId === 'string' && sessionData !== undefined) ? serviceId : '$effectiveServiceId';
            var data = sessionData !== undefined ? sessionData : serviceId;
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.success : false);
              };
              sendMessage('wisp_service_set_session', JSON.stringify({ serviceId: targetService, session: data, cbId: cbId }));
            });
          },

          clearSession: function(serviceId) {
            var targetService = serviceId || '$effectiveServiceId';
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.success : false);
              };
              sendMessage('wisp_service_clear_session', JSON.stringify({ serviceId: targetService, cbId: cbId }));
            });
          },

          withRefreshLock: function(serviceId, refreshCallback) {
            var targetService = (typeof serviceId === 'string' && typeof refreshCallback === 'function') ? serviceId : '$effectiveServiceId';
            var callback = typeof serviceId === 'function' ? serviceId : refreshCallback;
            return new Promise(function(resolve, reject) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_refresh_fns[cbId] = callback;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                if (res && res.error) {
                  reject(new Error(res.error));
                } else {
                  resolve(res ? res.session : null);
                }
              };
              sendMessage('wisp_service_refresh_lock', JSON.stringify({ serviceId: targetService, cbId: cbId }));
            });
          },

          getTokens: function(serviceId, options) {
            var targetService = (typeof serviceId === 'string' && options !== undefined) ? serviceId : '$effectiveServiceId';
            var opts = (typeof serviceId === 'object' && options === undefined) ? serviceId : (options || {});
            return globalThis.wisp.auth.getTokens(Object.assign({ serviceId: targetService }, opts));
          }
        },

        crypto: {
          generateTotp: function(base32Secret, options) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.otp : '');
              };
              sendMessage('wisp_crypto_totp', JSON.stringify({
                cbId: cbId,
                secret: base32Secret,
                digits: (options && options.digits) || 6,
                interval: (options && options.interval) || 30
              }));
            });
          },
          totp: function(base32Secret, options) {
            return this.generateTotp(base32Secret, options);
          },
          hmacSha1: function(key, data) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.hash : '');
              };
              sendMessage('wisp_crypto_hmac_sha1', JSON.stringify({ cbId: cbId, key: key, data: data }));
            });
          },
          sha1: function(text) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.hash : '');
              };
              sendMessage('wisp_crypto_sha1', JSON.stringify({ cbId: cbId, text: text }));
            });
          },
          sha256: function(text) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.hash : '');
              };
              sendMessage('wisp_crypto_sha256', JSON.stringify({ cbId: cbId, text: text }));
            });
          },
          randomHex: function(length) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.hex : '');
              };
              sendMessage('wisp_crypto_random_hex', JSON.stringify({ cbId: cbId, length: length || 32 }));
            });
          },
          generateP256KeyPair: function() {
            return new Promise(function(resolve, reject) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                if (res && res.error) reject(new Error(res.error));
                else resolve(res);
              };
              sendMessage('wisp_crypto_generate_p256_keypair', JSON.stringify({ cbId: cbId }));
            });
          },
          decryptJumoPayload: function(options) {
            return new Promise(function(resolve, reject) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                if (res && res.error) reject(new Error(res.error));
                else resolve(res ? res.result : null);
              };
              sendMessage('wisp_crypto_decrypt_jumo', JSON.stringify({
                cbId: cbId,
                clientPrivHex: options.clientPrivHex,
                serverPubKey: options.serverPubKey,
                bodyB64: options.bodyB64,
                url: options.url,
                nonce: options.nonce
              }));
            });
          }
        },

        audio: {
          resolveKey: function(options) {
            return new Promise(function(resolve, reject) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                if (res && res.error) reject(new Error(res.error));
                else resolve(res ? res.result : null);
              };
              sendMessage('wisp_audio_resolve_key', JSON.stringify({
                cbId: cbId,
                protocol: (options && options.protocol) || 'ap',
                trackId: options && options.trackId,
                fileId: options && options.fileId,
                token: options && options.token
              }));
            });
          }
        },

        storage: {
          get: function(key) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.value : null);
              };
              sendMessage('wisp_storage_get', JSON.stringify({ cbId: cbId, key: key }));
            });
          },
          set: function(key, value) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.success : false);
              };
              sendMessage('wisp_storage_set', JSON.stringify({ cbId: cbId, key: key, value: String(value) }));
            });
          },
          delete: function(key) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res ? res.success : false);
              };
              sendMessage('wisp_storage_delete', JSON.stringify({ cbId: cbId, key: key }));
            });
          }
        },

        auth: {
          openLogin: function(options) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res || null);
              };
              sendMessage('wisp_auth_open_login', JSON.stringify({
                cbId: cbId,
                url: options.url,
                title: options.title || 'Login',
                targetCookies: options.captureCookies || options.targetCookies || [],
                redirectUrlPrefix: options.redirectUrlPrefix || null
              }));
            });
          },
          promptInput: function(options) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res || null);
              };
              sendMessage('wisp_auth_prompt_input', JSON.stringify({
                cbId: cbId,
                title: (options && options.title) || 'Input',
                description: options && options.description,
                label: (options && options.label) || 'Key',
                hint: options && options.hint,
                defaultValue: options && options.defaultValue,
                link: options && options.link,
                linkText: options && options.linkText,
                isSecret: Boolean(options && options.isSecret)
              }));
            });
          },
          getTokens: function(options) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                if (res && res.tokens) resolve(res.tokens);
                else resolve(null);
              };
              sendMessage('wisp_auth_get_tokens', JSON.stringify({
                serviceId: (options && options.serviceId) || '$effectiveServiceId',
                forceRefresh: Boolean(options && options.forceRefresh),
                cbId: cbId
              }));
            });
          },
          login: function(serviceId) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res || null);
              };
              sendMessage('wisp_auth_login', JSON.stringify({
                serviceId: serviceId || '$effectiveServiceId',
                cbId: cbId
              }));
            });
          },
          logout: function(serviceId) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                resolve(res || null);
              };
              sendMessage('wisp_auth_logout', JSON.stringify({
                serviceId: serviceId || '$effectiveServiceId',
                cbId: cbId
              }));
            });
          }
        },

        spotify: {
          getTokens: function(options) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                if (res && res.error) resolve(null);
                else resolve(res);
              };
              sendMessage('wisp_get_spotify_tokens', JSON.stringify({
                cbId: cbId,
                forceRefresh: Boolean(options && options.forceRefresh)
              }));
            });
          }
        }
      };
    ''');
    runtime.executePendingJob();
  }
}
