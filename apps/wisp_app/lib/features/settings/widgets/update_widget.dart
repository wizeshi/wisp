// Copyright © 2026 wizeshi

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:simple_icons/simple_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wisp/core/utils/json.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp_assets/wisp_assets.dart';

class UpdateWidget extends StatefulWidget {
  const UpdateWidget({super.key});

  @override
  State<UpdateWidget> createState() => _UpdateWidgetState();
}

class _UpdateWidgetState extends State<UpdateWidget> {
  // Store the future instance here
  late Future<bool> _isUpdated;
  final bool _isDesktop =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    // Initialize the fetch task once
    _isUpdated = _fetchData();
  }

  Future<bool> _fetchData() async {
    bool isUpdated = true;

    final response = await http.get(
      Uri.parse(
        "https://api.github.com/repos/${WispInfo.author}/wisp/releases/latest",
      ),
    );

    if (response.statusCode != 200) {
      logger.e(
        "[Settings/Update]: Failed to fetch latest release info. Status code: ${response.statusCode}",
      );
      return isUpdated; // Return true to avoid showing update available on error
    }

    final latestVersion =
        (await JsonUtils.decode(response.body))['name'] as String;

    final latestVersionMajor = int.parse(latestVersion.split('.').first);
    final latestVersionMinor = int.parse(
      latestVersion.split('.').skip(1).first,
    );
    final latestVersionPatch = int.parse(
      latestVersion.split('.').skip(2).first,
    );

    final currentVersion = WispInfo.version;
    final currentVersionMajor = int.parse(currentVersion.split('.').first);
    final currentVersionMinor = int.parse(
      currentVersion.split('.').skip(1).first,
    );
    final currentVersionPatch = int.parse(
      currentVersion.split('.').skip(2).first,
    );

    if (latestVersionMajor > currentVersionMajor) {
      isUpdated = false;
    } else if (latestVersionMinor > currentVersionMinor) {
      isUpdated = false;
    } else if (latestVersionPatch > currentVersionPatch) {
      isUpdated = false;
    }

    return isUpdated;
  }

  Future<void> _launchUrl(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      logger.e("[Settings/Update]: Could not launch $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    const iconSize = 32.0;

    return FutureBuilder<bool>(
      future: _isUpdated,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else if (snapshot.hasData) {
          final isUpdated = snapshot.data!;
          return Row(
            spacing: _isDesktop ? 8 : 0,
            children: [
              if (isUpdated)
                IconButton(
                  icon: Center(
                    child: OverflowBox(
                      minWidth: 0,
                      minHeight: 0,
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      child: Icon(
                        SimpleIcons.github,
                        color: Colors.grey[700],
                        size: 32,
                      ),
                    ),
                  ),
                  onPressed: () {
                    _launchUrl(WispInfo.github);
                  },
                  constraints: BoxConstraints(
                    minWidth: iconSize,
                    minHeight: iconSize,
                    maxWidth: iconSize,
                    maxHeight: iconSize,
                  ),
                ),
              if (_isDesktop) const SizedBox.shrink(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isUpdated ? 'Up to date' : 'Update available',
                    style: TextStyle(
                      color: isUpdated ? Colors.green : Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'v${WispInfo.version}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
              if (!_isDesktop) const SizedBox(width: 8),
              isUpdated
                  ? Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: iconSize,
                    )
                  : Icon(Icons.update, color: Colors.orange, size: iconSize),
            ],
          );
        } else {
          return const Text('No data');
        }
      },
    );
  }
}

