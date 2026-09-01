import 'package:flutter/material.dart';
import 'package:wisp_installer/installation/models/install_log_entry.dart';

class InstallConsole extends StatefulWidget {
  const InstallConsole({
    super.key,
    required this.logs,
  });

  final List<InstallLogEntry> logs;

  @override
  State<InstallConsole> createState() => _InstallConsoleState();
}

class _InstallConsoleState extends State<InstallConsole> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant InstallConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.length != oldWidget.logs.length) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[800]!),
      ),
      padding: const EdgeInsets.all(8),
      child: widget.logs.isEmpty
          ? Center(
              child: Text(
                'Waiting for installation output...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontFamily: 'monospace',
                ),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              itemCount: widget.logs.length,
              itemBuilder: (context, index) {
                final entry = widget.logs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    entry.formattedLine,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: Colors.grey[300],
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
    );
  }
}
