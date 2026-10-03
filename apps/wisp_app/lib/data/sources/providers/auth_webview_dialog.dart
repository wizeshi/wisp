// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:wisp/core/utils/logger.dart';

/// Generic in-app webview modal for provider authentication (OAuth, cookie capture, etc.).
class AuthWebviewDialog extends StatefulWidget {
  final String initialUrl;
  final String title;
  final List<String> targetCookies;
  final String? redirectUrlPrefix;

  const AuthWebviewDialog({
    super.key,
    required this.initialUrl,
    this.title = 'Login',
    this.targetCookies = const [],
    this.redirectUrlPrefix,
  });

  @override
  State<AuthWebviewDialog> createState() => _AuthWebviewDialogState();
}

class _AuthWebviewDialogState extends State<AuthWebviewDialog> {
  InAppWebViewController? _controller;
  final CookieManager _cookieManager = CookieManager.instance();
  bool _isLoading = true;
  bool _hasPopped = false;

  void _popWithResult(Map<String, dynamic>? result) {
    if (_hasPopped || !mounted) return;
    _hasPopped = true;

    try {
      _controller?.stopLoading();
    } catch (_) {}

    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      Navigator.of(context).pop(result);
    }
  }

  Future<Map<String, String>> _collectCookiesForCurrentUrl() async {
    if (_hasPopped) return {};
    try {
      final uri = await _controller?.getUrl();
      if (_hasPopped) return {};
      final url = uri ?? WebUri(widget.initialUrl);
      final cookies = await _cookieManager.getCookies(url: url);
      final Map<String, String> map = {};
      for (final c in cookies) {
        if (c.value != null) map[c.name] = c.value!.trim();
      }
      return map;
    } catch (e) {
      logger.d('[AuthWebviewDialog] Failed to collect cookies: $e');
      return {};
    }
  }

  void _checkConditions(Map<String, String> cookies, String? currentUrl) {
    if (_hasPopped || !mounted) return;

    // 1. Check target cookies condition
    if (widget.targetCookies.isNotEmpty) {
      final hasAllTargets = widget.targetCookies.every(
        (target) => cookies.containsKey(target) && cookies[target]!.isNotEmpty,
      );
      if (hasAllTargets) {
        logger.i('[AuthWebviewDialog] Target cookies captured successfully: ${widget.targetCookies}');
        _popWithResult({'cookies': cookies});
        return;
      }
    }

    // 2. Check redirect URL prefix condition
    if (widget.redirectUrlPrefix != null && currentUrl != null) {
      if (currentUrl.startsWith(widget.redirectUrlPrefix!)) {
        logger.i('[AuthWebviewDialog] Reached redirect URL: $currentUrl');
        _popWithResult({'url': currentUrl, 'cookies': cookies});
        return;
      }
    }
  }

  @override
  void dispose() {
    _hasPopped = true;
    try {
      _controller?.stopLoading();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasPopped,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _hasPopped = true;
          try {
            _controller?.stopLoading();
          } catch (_) {}
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: () async {
                if (_hasPopped) return;
                final cookies = await _collectCookiesForCurrentUrl();
                if (!context.mounted) return;
                _popWithResult(cookies.isNotEmpty ? {'cookies': cookies} : null);
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
                initialSettings: InAppWebViewSettings(
                  userAgent:
                      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
                  thirdPartyCookiesEnabled: true,
                  javaScriptEnabled: true,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                },
                onLoadStop: (controller, url) async {
                  if (_hasPopped) return;
                  setState(() => _isLoading = false);
                  if (url == null) return;
                  final cookies = await _collectCookiesForCurrentUrl();
                  _checkConditions(cookies, url.toString());
                },
                onConsoleMessage: (controller, message) {
                  logger.d('[AuthWebviewDialog] ${message.message}');
                },
              ),
              if (_isLoading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}
