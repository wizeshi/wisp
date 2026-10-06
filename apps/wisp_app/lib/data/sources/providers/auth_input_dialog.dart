// Copyright © 2026 wizeshi

library;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

/// Modal dialog for user-provided text inputs (e.g. API keys, personal access tokens, custom server URLs).
class AuthInputDialog extends StatefulWidget {
  final String title;
  final String? description;
  final String label;
  final String? hint;
  final String? defaultValue;
  final String? link;
  final String? linkText;
  final bool isSecret;

  const AuthInputDialog({
    super.key,
    required this.title,
    this.description,
    this.label = 'API Key',
    this.hint,
    this.defaultValue,
    this.link,
    this.linkText,
    this.isSecret = false,
  });

  @override
  State<AuthInputDialog> createState() => _AuthInputDialogState();
}

class _AuthInputDialogState extends State<AuthInputDialog> {
  late final TextEditingController _controller;
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultValue ?? '');
    _obscured = widget.isSecret;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    Navigator.of(context).pop(text);
  }

  Future<void> _openLink() async {
    if (widget.link == null) return;
    final uri = Uri.tryParse(widget.link!);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF242424),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Text(
        widget.title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description != null && widget.description!.isNotEmpty) ...[
              Text(
                widget.description!,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _controller,
              obscureText: _obscured,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: widget.label,
                labelStyle: TextStyle(color: Colors.grey[400]),
                hintText: widget.hint,
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF181818),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                ),
                suffixIcon: widget.isSecret
                    ? IconButton(
                        icon: Icon(
                          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscured = !_obscured),
                      )
                    : null,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.link != null && widget.link!.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: _openLink,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.linkText ?? 'Get API Key',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new,
                        size: 13,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        GenericTextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
        ),
        GenericElevatedButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

