import 'package:flutter/material.dart';

class YtDlpInitializingView extends StatelessWidget {
  const YtDlpInitializingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('YT-DLP is initializing...'),
          ],
        ),
      ),
    );
  }
}
