// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';

class DJChatBubble extends StatelessWidget {
  final String message;
  final bool isUserMessage;

  const DJChatBubble({
    super.key,
    required this.message,
    required this.isUserMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUserMessage
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14.0),
            topRight: const Radius.circular(14.0),
            bottomLeft: Radius.circular(isUserMessage ? 14.0 : 2.0),
            bottomRight: Radius.circular(isUserMessage ? 2.0 : 14.0),
          ),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isUserMessage
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

