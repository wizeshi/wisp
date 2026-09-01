import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class InstallerTitleBar extends StatelessWidget {
  const InstallerTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints.expand(height: 32),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!Platform.isMacOS) buildWindowControlButtons()
        ],
      ),
    );
  }

  Widget buildWindowControlButtons() {
    return Row(
      children: [
        buildControlButton(Icons.minimize, () async {
          await windowManager.minimize();
        }),
        buildControlButton(Icons.crop_square, () async {
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        }),
        buildControlButton(Icons.close, () async {
          await windowManager.close();
        }, hoverColor: Colors.red),
      ],
    );
  }

  Widget buildControlButton(IconData icon, VoidCallback onPressed, {Color? hoverColor}) {
    return IconButton(
      hoverColor: hoverColor,
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
      ),
    );
  }
}