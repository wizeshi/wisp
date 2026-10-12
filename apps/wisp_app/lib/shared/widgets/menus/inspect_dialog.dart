// Copyright © 2026 wizeshi

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/shared/widgets/alert/wisp_alert_extensions.dart';

/// A reusable dev-mode inspector dialog that dumps and traverses an arbitrary
/// [Map<String, dynamic>] in a readable, copy-friendly tree view with collapsible
/// subsections.
class InspectDialog extends StatelessWidget {
  final Map<String, dynamic> data;
  final String title;

  const InspectDialog({
    super.key,
    required this.data,
    this.title = 'Inspect Element',
  });

  /// Convenience launcher — displays a modal bottom sheet on mobile (< 600px width)
  /// and a centered dialog on desktop/tablet.
  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> data,
    String title = 'Inspect Element',
  }) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    if (isNarrow) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => InspectDialog(data: data, title: title),
      );
    }

    final halfWidth = MediaQuery.sizeOf(context).width / 2;
    final padding = EdgeInsets.symmetric(horizontal: halfWidth * 0.5);

    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: padding,
        child: InspectDialog(data: data, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[800]!, width: 1),
        ),
        constraints: const BoxConstraints(maxHeight: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.code, size: 16, color: primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  GenericIconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.grey[800], height: 1),

            // Fields list with recursive subsections
            Flexible(
              child: data.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          '(No data)',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: _buildNodes(data, primaryColor),
                    ),
            ),

            Divider(color: Colors.grey[800], height: 1),

            // Copy all button
            Padding(
              padding: const EdgeInsets.all(12),
              child: GenericTextButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy all as JSON'),
                foregroundColor: Colors.grey[400],
                textStyle: const TextStyle(fontSize: 12),
                onPressed: () async {
                  final json = _formatJson(data);
                  await Clipboard.setData(ClipboardData(text: json));
                  if (!context.mounted) return;
                  context.showSuccessAlert('Copied all data to clipboard');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<Widget> _buildNodes(
    Map<String, dynamic> map,
    Color primaryColor, {
    int depth = 0,
  }) {
    final widgets = <Widget>[];

    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Map<String, dynamic>) {
        widgets.add(
          _CollapsibleSection(
            label: key,
            badge: '{${value.length}}',
            primaryColor: primaryColor,
            dataForCopy: value,
            depth: depth,
            children: _buildNodes(value, primaryColor, depth: depth + 1),
          ),
        );
      } else if (value is Map) {
        final castMap = value.map((k, v) => MapEntry(k.toString(), v));
        widgets.add(
          _CollapsibleSection(
            label: key,
            badge: '{${castMap.length}}',
            primaryColor: primaryColor,
            dataForCopy: castMap,
            depth: depth,
            children: _buildNodes(castMap, primaryColor, depth: depth + 1),
          ),
        );
      } else if (value is List && _isComplexList(value)) {
        widgets.add(
          _CollapsibleSection(
            label: key,
            badge: '[${value.length}]',
            primaryColor: primaryColor,
            dataForCopy: value,
            depth: depth,
            children: _buildListNodes(value, primaryColor, depth: depth + 1),
          ),
        );
      } else {
        widgets.add(
          _FieldRow(keyName: key, value: value, primaryColor: primaryColor),
        );
      }
    }

    return widgets;
  }

  static List<Widget> _buildListNodes(
    List list,
    Color primaryColor, {
    int depth = 0,
  }) {
    final widgets = <Widget>[];

    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      final itemKey = '[$i]';

      if (item is Map<String, dynamic>) {
        widgets.add(
          _CollapsibleSection(
            label: itemKey,
            badge: '{${item.length}}',
            primaryColor: primaryColor,
            dataForCopy: item,
            depth: depth,
            children: _buildNodes(item, primaryColor, depth: depth + 1),
          ),
        );
      } else if (item is Map) {
        final castMap = item.map((k, v) => MapEntry(k.toString(), v));
        widgets.add(
          _CollapsibleSection(
            label: itemKey,
            badge: '{${castMap.length}}',
            primaryColor: primaryColor,
            dataForCopy: castMap,
            depth: depth,
            children: _buildNodes(castMap, primaryColor, depth: depth + 1),
          ),
        );
      } else if (item is List && _isComplexList(item)) {
        widgets.add(
          _CollapsibleSection(
            label: itemKey,
            badge: '[${item.length}]',
            primaryColor: primaryColor,
            dataForCopy: item,
            depth: depth,
            children: _buildListNodes(item, primaryColor, depth: depth + 1),
          ),
        );
      } else {
        widgets.add(
          _FieldRow(keyName: itemKey, value: item, primaryColor: primaryColor),
        );
      }
    }

    return widgets;
  }

  static bool _isComplexList(List list) {
    if (list.isEmpty) return false;
    return list.any((item) => item is Map || (item is List && item.isNotEmpty));
  }

  static String _formatJson(Object? data) {
    try {
      return JsonEncoder.withIndent('  ', (nonEncodable) {
        if (nonEncodable is DateTime) {
          return nonEncodable.toIso8601String();
        }
        return nonEncodable.toString();
      }).convert(data);
    } catch (_) {
      return data.toString();
    }
  }
}

class _CollapsibleSection extends StatefulWidget {
  final String label;
  final String badge;
  final Color primaryColor;
  final Object dataForCopy;
  final int depth;
  final List<Widget> children;

  const _CollapsibleSection({
    required this.label,
    required this.badge,
    required this.primaryColor,
    required this.dataForCopy,
    required this.depth,
    required this.children,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.grey[750] ?? Colors.grey[800]!,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    widget.badge,
                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                  ),
                ),
                const Spacer(),
                GenericIconButton(
                  icon: Icon(Icons.copy, size: 12, color: Colors.grey[600]),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: () async {
                    final json = InspectDialog._formatJson(widget.dataForCopy);
                    await Clipboard.setData(ClipboardData(text: json));
                    if (!context.mounted) return;
                    context.showSuccessAlert(
                      '"${widget.label}" JSON copied to clipboard',
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          Container(
            margin: const EdgeInsets.only(left: 28, right: 12, bottom: 4),
            padding: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: widget.primaryColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String keyName;
  final dynamic value;
  final Color primaryColor;

  const _FieldRow({
    required this.keyName,
    required this.value,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final stringValue = _formatValue(value);
    final isUrl =
        value is String &&
        (value.startsWith('http://') || value.startsWith('https://'));
    final isNull = value == null;
    final isBool = value is bool;

    Color? textColor;
    if (isUrl) {
      textColor = Colors.blue[300];
    } else if (isNull) {
      textColor = Colors.grey[600];
    } else if (isBool) {
      textColor = value ? Colors.tealAccent[400] : Colors.red[300];
    } else if (value is num) {
      textColor = Colors.amber[200];
    } else {
      textColor = Colors.grey[300];
    }

    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: stringValue));
        if (!context.mounted) return;
        context.showSuccessAlert('"$keyName" copied to clipboard');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                keyName,
                style: TextStyle(
                  color: primaryColor.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MouseRegion(
                cursor: isUrl
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Text(
                  stringValue,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 11,
                    fontStyle: isNull ? FontStyle.italic : FontStyle.normal,
                    decoration: isUrl ? TextDecoration.underline : null,
                    decorationColor: isUrl ? textColor : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(Icons.copy, size: 12, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  String _formatValue(dynamic val) {
    if (val == null) return 'null';
    if (val is String) {
      return val.isEmpty ? '(empty)' : val;
    }
    if (val is List) {
      if (val.isEmpty) return '[] (empty)';
      return '[${val.join(', ')}]';
    }
    if (val is DateTime) {
      return val.toIso8601String();
    }
    return val.toString();
  }
}
