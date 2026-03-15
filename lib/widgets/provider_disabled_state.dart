import 'package:flutter/material.dart';

import '../services/app_navigation.dart';

class ProviderDisabledState extends StatelessWidget {
  final String message;

  const ProviderDisabledState({
    super.key,
    this.message = 'You\'ve disabled the provider for this page.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[300],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                AppNavigation.instance.openSettings();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Go to Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
