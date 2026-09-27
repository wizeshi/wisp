// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'package:flutter/material.dart';
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

  Future<Map<String, String>> _collectCookiesForCurrentUrl() async {
    try {
      final uri = await _controller?.getUrl();
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
    if (!mounted) return;

    // 1. Check target cookies condition
    if (widget.targetCookies.isNotEmpty) {
      final hasAllTargets = widget.targetCookies.every(
        (target) => cookies.containsKey(target) && cookies[target]!.isNotEmpty,
      );
      if (hasAllTargets) {
        logger.i('[AuthWebviewDialog] Target cookies captured successfully: ${widget.targetCookies}');
        Navigator.of(context).pop({'cookies': cookies});
        return;
      }
    }

    // 2. Check redirect URL prefix condition
    if (widget.redirectUrlPrefix != null && currentUrl != null) {
      if (currentUrl.startsWith(widget.redirectUrlPrefix!)) {
        logger.i('[AuthWebviewDialog] Reached redirect URL: $currentUrl');
        Navigator.of(context).pop({'url': currentUrl, 'cookies': cookies});
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () async {
              final cookies = await _collectCookiesForCurrentUrl();
              if (!context.mounted) return;
              Navigator.of(context).pop(cookies.isNotEmpty ? {'cookies': cookies} : null);
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
    );
  }
}
