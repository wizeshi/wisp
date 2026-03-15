import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wisp/utils/logger.dart';

class SpotifyWebview extends StatefulWidget {
  final String initialUrl;
  const SpotifyWebview({Key? key, required this.initialUrl}) : super(key: key);

  @override
  _SpotifyWebviewState createState() => _SpotifyWebviewState();
}

class _SpotifyWebviewState extends State<SpotifyWebview> {
  InAppWebViewController? _controller;
  final CookieManager _cookieManager = CookieManager.instance();
  bool _isLoading = true;

  Future<Map<String, String>> _collectCookiesForCurrentUrl() async {
    try {
      final uri = await _controller?.getUrl();
      final url = uri ?? WebUri(widget.initialUrl);
      final cookies = await _cookieManager.getCookies(url: url);
      final Map<String, String> map = {};
      for (final c in cookies) {
        if (c.name != null && c.value != null) map[c.name] = c.value!.trim();
      }
      return map;
    } catch (e) {
      logger.d('[SpotifyWebview] Failed to collect cookies: $e');
      return {};
    }
  }

  void _maybeAutoClose(Map<String, String> cookies) {
    if (cookies.containsKey('sp_dc') && cookies['sp_dc']!.isNotEmpty) {
      Navigator.of(context).pop(cookies);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spotify Login'),
        actions: [
          TextButton(
            onPressed: () async {
              final cookies = await _collectCookiesForCurrentUrl();
              Navigator.of(context).pop(cookies.isNotEmpty ? cookies : null);
            },
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStop: (controller, url) async {
                setState(() => _isLoading = false);
                if (url == null) return;
                final cookies = await _cookieManager.getCookies(url: url);
                final Map<String, String> cookieMap = {};
                for (final c in cookies) {
                  if (c.name != null && c.value != null) cookieMap[c.name] = c.value!.trim();
                }
                if (cookieMap.isNotEmpty) {
                  _maybeAutoClose(cookieMap);
                }
              },
              onConsoleMessage: (controller, message) {
                logger.d('[SpotifyWebview][WebView] ${message.message}');
              },
            ),
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
