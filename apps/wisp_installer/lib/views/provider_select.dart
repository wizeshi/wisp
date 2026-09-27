import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:wisp_assets/wisp_assets.dart';
import 'package:wisp_newpipe_manager/services/wisp_support_directory.dart';

const appRepo = "${WispInfo.author}/wisp";

class InstallerProviderItem {
  final String id;
  final String name;
  final String type;
  final String version;
  final String description;
  final String author;
  final String path;
  final List<String> files;
  final List<String> capabilities;
  bool isSelected;

  InstallerProviderItem({
    required this.id,
    required this.name,
    required this.type,
    required this.version,
    required this.description,
    required this.author,
    required this.path,
    required this.files,
    required this.capabilities,
    this.isSelected = true,
  });

  factory InstallerProviderItem.fromJson(Map<String, dynamic> json) {
    return InstallerProviderItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'lyrics',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      path: json['path'] as String? ?? '',
      files: (json['files'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['manifest.json', 'index.js'],
      capabilities: (json['supportedSyncModes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isSelected: true,
    );
  }
}

class ProviderSelectStep extends StatefulWidget {
  const ProviderSelectStep({
    super.key,
    required this.onContinue,
  });

  final void Function(List<String> installedNames) onContinue;

  @override
  State<ProviderSelectStep> createState() => _ProviderSelectStepState();
}

class _ProviderSelectStepState extends State<ProviderSelectStep> {
  static const String _rawBaseUrl =
      'https://raw.githubusercontent.com/$appRepo/main/providers';

  List<InstallerProviderItem> _providers = [];
  bool _isLoading = true;
  bool _isInstalling = false;
  String _installStatusMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  Future<void> _fetchCatalog() async {
    setState(() {
      _isLoading = true;
    });

    final Map<String, InstallerProviderItem> discovered = {};

    // 1. Try remote GitHub Git Trees API
    try {
      final treeRes = await http.get(
        Uri.parse(
          'https://api.github.com/repos/$appRepo/git/trees/main?recursive=1',
        ),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'wisp-installer',
        },
      ).timeout(const Duration(seconds: 6));

      if (treeRes.statusCode == 200) {
        final treeData = jsonDecode(treeRes.body) as Map<String, dynamic>;
        final tree =
            (treeData['tree'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
                [];

        final manifestEntries = tree.where((item) {
          final path = (item['path'] as String? ?? '').replaceAll('\\', '/');
          return path.startsWith('providers/') &&
              path.endsWith('/manifest.json');
        }).toList();

        for (final entry in manifestEntries) {
          final manifestPath = (entry['path'] as String).replaceAll('\\', '/');
          final parentDir = p.dirname(manifestPath).replaceAll('\\', '/');
          final relativeProviderPath =
              parentDir.substring('providers/'.length);

          final siblingFiles = tree
              .where((item) {
                final pth =
                    (item['path'] as String? ?? '').replaceAll('\\', '/');
                final type = item['type'] as String? ?? '';
                return pth.startsWith('$parentDir/') && type == 'blob';
              })
              .map((item) => p.basename(item['path'] as String))
              .toList();

          try {
            final rawManifestUrl =
                '$_rawBaseUrl/$relativeProviderPath/manifest.json';
            final mRes = await http.get(
              Uri.parse(rawManifestUrl),
            ).timeout(const Duration(seconds: 4));

            if (mRes.statusCode == 200) {
              final json = jsonDecode(mRes.body) as Map<String, dynamic>;
              json['path'] = relativeProviderPath;
              json['files'] = siblingFiles.isNotEmpty
                  ? siblingFiles
                  : ['manifest.json', 'index.js'];
              final item = InstallerProviderItem.fromJson(json);
              discovered[item.id] = item;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2. Discover from local workspace providers directories recursively
    final potentialRoots = [
      p.join(Directory.current.path, 'providers'),
      p.join(Directory.current.path, '..', '..', 'providers'),
      p.join(Directory.current.path, '..', 'providers'),
    ];

    for (final rootPath in potentialRoots) {
      final rootDir = Directory(rootPath);
      if (!rootDir.existsSync()) continue;

      try {
        final manifests = rootDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => p.basename(f.path).toLowerCase() == 'manifest.json');

        for (final manifestFile in manifests) {
          try {
            final content = await manifestFile.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final providerDir = manifestFile.parent;
            final relativePath =
                p.relative(providerDir.path, from: rootDir.path).replaceAll('\\', '/');

            final files = providerDir
                .listSync()
                .whereType<File>()
                .map((f) => p.basename(f.path))
                .toList();

            json['path'] = relativePath;
            json['files'] =
                files.isNotEmpty ? files : ['manifest.json', 'index.js'];

            final item = InstallerProviderItem.fromJson(json);
            discovered[item.id] = item;
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _providers = discovered.values.toList();
      _isLoading = false;
    });
  }

  Future<void> _installSelected() async {
    final selected = _providers.where((p) => p.isSelected).toList();
    if (selected.isEmpty) {
      widget.onContinue([]);
      return;
    }

    setState(() {
      _isInstalling = true;
      _installStatusMessage = 'Preparing provider installation...';
    });

    final installedNames = <String>[];

    try {
      final supportDir = await WispSupportDirectory().get();
      final baseProvidersDir = Directory(p.join(supportDir.path, 'providers'));
      if (!baseProvidersDir.existsSync()) {
        baseProvidersDir.createSync(recursive: true);
      }

      for (final item in selected) {
        if (!mounted) return;
        setState(() {
          _installStatusMessage = 'Installing ${item.name}...';
        });

        final targetDir = Directory(p.join(baseProvidersDir.path, item.path));
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }

        for (final fileName in item.files) {
          String? content;

          // 1. Try remote download
          try {
            final res = await http.get(
              Uri.parse('$_rawBaseUrl/${item.path}/$fileName'),
            ).timeout(const Duration(seconds: 10));

            if (res.statusCode == 200) {
              content = res.body;
            }
          } catch (_) {}

          // 2. Fallback local repo paths
          if (content == null) {
            final localPaths = [
              p.join(Directory.current.path, 'providers', item.path, fileName),
              p.join(
                Directory.current.path,
                '..',
                '..',
                'providers',
                item.path,
                fileName,
              ),
              p.join(
                Directory.current.path,
                '..',
                'providers',
                item.path,
                fileName,
              ),
            ];

            for (final lp in localPaths) {
              final f = File(lp);
              if (f.existsSync()) {
                try {
                  content = await f.readAsString();
                  break;
                } catch (_) {}
              }
            }
          }

          if (content != null) {
            final targetFile = File(p.join(targetDir.path, fileName));
            await targetFile.writeAsString(content);
          }
        }

        installedNames.add(item.name);
      }
    } catch (e) {
      // Non-fatal: even if network download fails, continue with completed ones
    }

    if (!mounted) return;
    setState(() {
      _isInstalling = false;
    });

    widget.onContinue(installedNames);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 16),
            const Text(
              'Fetching available providers...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_isInstalling) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 20),
            Text(
              _installStatusMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Downloading provider bundles from repository',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 28 + 12 + 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                const Text(
                  'Modular Providers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Wisp supports modular community extensions for lyrics and metadata.\n'
                  'Select the providers you want to install. You can manage or update them later in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _providers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _providers[index];
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF181818),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: item.isSelected
                          ? primaryColor.withValues(alpha: 0.5)
                          : Colors.grey[850]!,
                      width: item.isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: CheckboxListTile(
                    value: item.isSelected,
                    onChanged: (val) {
                      setState(() {
                        item.isSelected = val ?? false;
                      });
                    },
                    activeColor: primaryColor,
                    checkColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    title: Row(
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'v${item.version}',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'by ${item.author}',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          item.description,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        if (item.capabilities.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: item.capabilities.map((cap) {
                              final isWord = cap.contains('word');
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isWord
                                      ? primaryColor.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isWord
                                        ? primaryColor.withValues(alpha: 0.4)
                                        : Colors.white12,
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  cap,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isWord ? primaryColor : Colors.grey[300],
                                    fontWeight: isWord
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => widget.onContinue([]),
                child: Text(
                  'Skip',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
              FilledButton.icon(
                onPressed: _installSelected,
                icon: const Icon(Icons.download_done, size: 18),
                label: Text(
                  'Install Selected (${_providers.where((p) => p.isSelected).length})',
                  style: const TextStyle(color: Colors.white),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
